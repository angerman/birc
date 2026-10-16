#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Offline media integration: exact requests, terminal playback, and live IO.

The helper never fetches a URL. Pillow creates all source images in this fixture.
Native transport/refusal/allocation boundaries have deterministic C controls;
this test checks the combined Bend scheduling and native playback boundary.
"""
from __future__ import annotations

import base64
import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import re
import select
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time

# The existing typing.py PTY fixture must not shadow Python's typing module
# while Pillow imports it. Restore the test path for the shared PTY helpers.
saved_path = sys.path[:]
sys.path[:] = [entry for entry in sys.path
               if Path(entry or os.getcwd()).resolve() != Path(__file__).resolve().parent]
try:
    from PIL import Image
finally:
    sys.path[:] = saved_path
from output_recovery import fill


def drain(fd: int, duration: float) -> bytes:
    output = bytearray()
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        if select.select([fd], [], [], min(0.02, max(0, deadline - time.monotonic())))[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            output.extend(chunk)
    return bytes(output)


def wait_for(predicate, timeout: float, tick=lambda: time.sleep(0.01)) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        tick()
    assert predicate(), "bounded media precondition was not reached"


def receive(conn: socket.socket, needle: bytes, timeout: float) -> bytes:
    output = bytearray()
    deadline = time.monotonic() + timeout
    while needle not in output and time.monotonic() < deadline:
        if select.select([conn], [], [], 0.02)[0]:
            chunk = conn.recv(65536)
            if not chunk:
                break
            output.extend(chunk)
    return bytes(output)


def assets(directory: Path) -> bytes:
    spec = importlib.util.spec_from_file_location("birc_image", Path(__file__).parents[2] / "src/media/image.py")
    image_helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(image_helper)
    jpeg = io.BytesIO()
    Image.new("RGB", (12, 8), (30, 70, 100)).save(jpeg, format="JPEG")
    (directory / "local.jpg").write_bytes(jpeg.getvalue())
    (directory / "still.txt").write_text(image_helper.encode(jpeg.getvalue()) + "\n")
    gif = io.BytesIO()
    first = Image.new("RGB", (12, 8), (220, 20, 40))
    second = Image.new("RGB", (12, 8), (20, 100, 220))
    first.save(gif, format="GIF", save_all=True, append_images=[second], duration=[40, 120], loop=1)
    encoded = image_helper.encode(gif.getvalue())
    (directory / "animated.txt").write_text(encoded + "\n")
    payload = base64.b64decode(encoded, validate=True)
    width, height, count, iterations, rgba_len, gif_len = struct.unpack(">6I", payload[8:32])
    assert (width, height, count, iterations) == (12, 8, 2, 2)
    return payload[32 + rgba_len:32 + rgba_len + gif_len]


def fake_helper(directory: Path) -> Path:
    helper = directory / "helper"
    helper.write_text("#!" + sys.executable + "\n" + r'''
import json, os, pathlib, sys, time
root = pathlib.Path(__file__).parent
args = sys.argv[1:]
def record(phase):
    with (root / "calls").open("a") as out:
        out.write(json.dumps({"phase": phase, "args": args}) + "\n")
        out.flush()
try:
    owner = os.open(root / "busy", os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
except FileExistsError:
    record("concurrent")
    raise SystemExit(2)
record("start")
try:
    source = args[-1]
    payload = (root / ("animated.txt" if ".GIF" in source or "slow" in source else "still.txt")).read_text().strip()
    if args[0] == "--local":
        assert len(args) == 2 and pathlib.Path(source).read_bytes()[:2] == b"\xff\xd8"
    if "slow" in source:
        time.sleep(1.2)
    starts = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
    attempts = sum(row["phase"] == "start" and row["args"] == args for row in starts)
    print("invalid-envelope" if "retry" in source and attempts == 1 else payload, end="\n", flush=True)
finally:
    os.close(owner)
    (root / "busy").unlink()
    record("end")
''')
    helper.chmod(0o755)
    return helper


class Live:
    def __init__(self, binary: str, directory: Path, protocol: str):
        self.directory = directory
        self.output = bytearray()
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.listener.settimeout(4)
        self.master, slave = pty.openpty()
        self.slave_name = os.ttyname(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        self.attrs = termios.tcgetattr(slave)
        env = dict(os.environ)
        for name in ("TMUX", "STY", "ZELLIJ", "SSH_CONNECTION", "KITTY_WINDOW_ID",
                     "TIMUI_IMAGE_PROTOCOL", "BIRC_FORCE_IMAGE_PROTOCOL", "TERM_PROGRAM",
                     "BIRC_REPLAY", "BIRC_FRAME_PROFILE"):
            env.pop(name, None)
        env.update(TERM="xterm-kitty" if protocol == "kitty" else "xterm-256color",
                   TERM_PROGRAM="kitty" if protocol == "kitty" else "iTerm.app",
                   BIRC_IMAGES="on", BIRC_HISTORY="none", BIRC_PREFERENCES="none",
                   BIRC_MEDIA_HELPER=str(fake_helper(directory)))
        if protocol == "kitty":
            env["BIRC_FORCE_IMAGE_PROTOCOL"] = "kitty"
        self.proc = subprocess.Popen(
            [binary, "--plain", "--connect", "127.0.0.1", "--port", str(self.listener.getsockname()[1]),
             "--nick", "probe", "--channel", "#t", "--frames", "0"],
            stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        self.conn = None
        try:
            self.conn, _ = self.listener.accept()
            assert b"USER probe" in receive(self.conn, b"USER probe", 2), "registration missing"
            self.conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
            self.paint(0.4)
            assert b"JOIN #t" in receive(self.conn, b"JOIN #t", 2), "channel registration missing"
            # /join selects an existing buffer as well as a newly created one.
            # This avoids assuming that startup leaves the server or channel active.
            self.command("/join #t")
            self.paint(0.2)
        except BaseException:
            self.close()
            raise

    def paint(self, duration: float = 0.02) -> None:
        self.output.extend(drain(self.master, duration))

    def until(self, predicate, timeout: float = 3) -> None:
        wait_for(predicate, timeout, self.paint)

    def calls(self, phase: str = "start") -> list[list[str]]:
        path = self.directory / "calls"
        return [row["args"] for line in path.read_text().splitlines()
                if (row := json.loads(line))["phase"] == phase] if path.exists() else []

    def command(self, command: str) -> None:
        os.write(self.master, command.encode() + b"\r")

    def message(self, text: str) -> None:
        self.conn.sendall((":alice!u@h PRIVMSG #t :" + text + "\r\n").encode())

    def pong(self, token: str) -> None:
        self.conn.sendall(("PING :" + token + "\r\n").encode())
        assert ("PONG :" + token).encode() in receive(self.conn, ("PONG :" + token).encode(), 0.8), "media blocked PONG"

    def stop(self) -> None:
        self.command("/quit")
        self.proc.wait(timeout=2)
        assert self.proc.returncode == 0, self.proc.returncode
        assert b"QUIT" in receive(self.conn, b"QUIT", 0.4), "media dropped QUIT"
        assert termios.tcgetattr(self.master) == self.attrs, "media left tty attributes changed"

    def close(self) -> None:
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()
        # A deliberately slow external helper can outlive birc. Let this owned
        # fixture finish before its temporary files are removed.
        try:
            wait_for(lambda: not (self.directory / "busy").exists()
                     and len(self.calls("end")) == len(self.calls()), 3)
            assert not self.calls("concurrent"), "more than one media helper ran"
        finally:
            if self.conn is not None:
                self.conn.close()
            self.listener.close()
            os.close(self.master)


def kitty_frames(data: bytes) -> list[bytes]:
    # Playback/deletion controls have no payload or semicolon separator.
    return re.findall(rb"\x1b_G([^;\x1b]*)(?:;[^\x1b]*)?\x1b\\", data)


def kitty_case(binary: str, directory: Path) -> None:
    assets(directory)
    live = Live(binary, directory, "kitty")
    try:
        url = "https://offline.invalid/loop.GIF?size=2#view"
        live.message(url)
        live.until(lambda: b"s=3,v=3" in live.output)
        assert live.calls() == [[url]], "automatic request changed the exact URL"
        frames = kitty_frames(live.output)
        root = next(frame for frame in frames if frame.startswith(b"a=t,"))
        image_id = re.search(rb"(?:^|,)i=(\d+)", root).group(1)
        assert any(frame.startswith(b"a=f,") and b"i=" + image_id in frame and b"X=1,z=120" in frame for frame in frames), "Kitty frame upload missing"
        assert any(frame.startswith(b"a=a,") and b"i=" + image_id in frame and b"r=1,z=40" in frame for frame in frames), f"Kitty root gap missing: {frames!r}"
        live.pong("animation-live")

        live.command("/images off")
        live.paint(0.3)
        count = len(live.calls())
        live.message("https://offline.invalid/off.png")
        live.paint(0.3)
        assert len(live.calls()) == count, "images off still fetched an automatic image"

        retry = "https://offline.invalid/retry.jpg"
        live.command("/preview " + retry)
        live.until(lambda: b"image preview unavailable" in live.output)
        before = live.output.count(b"\x1b_Ga=t,")
        live.command("/preview " + retry)
        live.until(lambda: live.output.count(b"\x1b_Ga=t,") > before)
        assert live.calls().count([retry]) == 2, "identical manual preview was not retried"

        local = str(directory / "local.jpg")
        before = live.output.count(b"\x1b_Ga=t,")
        live.command("/preview " + local)
        live.until(lambda: live.output.count(b"\x1b_Ga=t,") > before)
        assert ["--local", local] in live.calls(), "local JPEG did not use the local helper boundary"

        os.write(live.master, b"\x1b[1;2D")  # *preview* -> #t
        live.paint(0.2)
        live.command("/images on")
        live.paint(0.2)
        slow = "https://offline.invalid/slow.GIF"
        live.message(slow)
        live.until(lambda: [slow] in live.calls())
        live.pong("helper-pending")
        live.command("/images off")
        live.paint(0.2)
        before = live.output.count(b"\x1b_Ga=t,")
        live.until(lambda: [slow] in live.calls("end"))
        live.paint(0.2)
        assert live.output.count(b"\x1b_Ga=t,") == before, "disabled stale completion created an image"
        live.command("/images on")
        live.paint(0.2)
        fresh = "https://offline.invalid/fresh.png"
        live.message(fresh)
        live.until(lambda: [fresh] in live.calls("end"))
        live.until(lambda: live.output.count(b"\x1b_Ga=t,") > before)
        live.pong("after-stale")
        live.stop()
        print("media kitty=ok", flush=True)
    finally:
        live.close()


def iterm_case(binary: str, directory: Path) -> None:
    gif = assets(directory)
    live = Live(binary, directory, "iterm")
    try:
        url = "https://offline.invalid/loop.GIF"
        live.message(url)
        encoded = base64.b64encode(gif)
        live.until(lambda: b"\x1b]1337;File=" in live.output and encoded in live.output)
        assert b"\x1b_Ga=f," not in live.output, "iTerm used Kitty playback"
        assert live.calls() == [[url]]
        live.pong("iterm-live")
        live.stop()
        print("media iterm=ok", flush=True)
    finally:
        live.close()


def pending_quit_case(binary: str, directory: Path) -> None:
    assets(directory)
    live = Live(binary, directory, "kitty")
    try:
        url = "https://offline.invalid/slow.GIF"
        live.message(url)
        live.until(lambda: [url] in live.calls())
        assert [url] not in live.calls("end"), "slow helper fixture was not pending"
        live.pong("quit-pending")
        started = time.monotonic()
        live.stop()
        assert time.monotonic() - started < 1, "quit waited for external media completion"
        print("media pending_quit=ok", flush=True)
    finally:
        live.close()


def unread_case(binary: str, directory: Path) -> None:
    assets(directory)
    live = Live(binary, directory, "kitty")
    writer = os.open(live.slave_name, os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
    try:
        # The reopened slave shares the output queue the client uses, but has
        # an independent nonblocking file description.
        fill(writer)
        url = "https://offline.invalid/loop.GIF"
        live.message(url)
        wait_for(lambda: [url] in live.calls("end"), 3)
        live.pong("media-unread")
        time.sleep(1.2)
        live.pong("media-still-unread")
        # Reading is the only action that permits pending bytes to progress.
        # No key, resize, or new chat event supplies the animation paint.
        live.until(lambda: b"s=3,v=3" in live.output, 4)
        live.stop()
        print("media unread_recovery=ok", flush=True)
    finally:
        os.close(writer)
        live.close()


def main() -> None:
    binary = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "./build/birc")
    with tempfile.TemporaryDirectory(prefix="birc-media-pty-") as temporary:
        for name, case in (("kitty", kitty_case), ("iterm", iterm_case),
                           ("pending", pending_quit_case), ("unread", unread_case)):
            directory = Path(temporary, name)
            directory.mkdir()
            case(binary, directory)


if __name__ == "__main__":
    main()
