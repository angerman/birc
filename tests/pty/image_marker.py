#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Classify image placeholders with the native app and an offline fake helper.

Only an owned loopback IRC peer and a synthetic .test URL are used. No image
host, supplied chat URL, user file, Keychain, or real decoder is contacted.
"""
from __future__ import annotations

import base64
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
import zlib

from preferences import Screen


URL = "https://image-marker.test/Screenshot%202026-10-03%20at%202.26.53%E2%80%AFAM.png"
PRIVATE = "PRIVATE-IMAGE-MARKER-HELPER-BODY"
ERROR = "image preview unavailable"
UNSUPPORTED = "image previews disabled: terminal image protocol is unavailable"
UNSUPPORTED_MODES = {"none", "mux", "masked"}
HELPER = r'''
import json, os, signal, sys
from pathlib import Path
signal.signal(signal.SIGALRM, signal.SIG_DFL)
signal.alarm(6)
folder = Path(__file__).parent
def record(event):
    fd = os.open(folder / "helpers.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        row = {"event": event, "pid": os.getpid(), "pgid": os.getpgrp(), "args": sys.argv[1:]}
        os.write(fd, (json.dumps(row) + "\n").encode())
    finally:
        os.close(fd)
record("start")
print("PRIVATE-IMAGE-MARKER-HELPER-BODY", file=sys.stderr)
print("PRIVATE-IMAGE-MARKER-HELPER-BODY" if os.environ["BIRC_MARKER_CASE"] == "malformed"
      else (folder / "payload").read_text(), end="\n", flush=True)
record("done")
'''


def payload():
    # A valid tiny PNG and the same literal envelope the real helper emits.
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    rgba = bytes((40, 100, 200, 255)) * 4
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", 2, 2, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(b"\0" + rgba[:8] + b"\0" + rgba[8:])) + chunk(b"IEND", b""))
    encoded = b"BIRCIMG1" + struct.pack(">6I", 2, 2, 1, 1, len(rgba), 0) + rgba
    return base64.b64encode(encoded + struct.pack(">2I", 100, len(png)) + png).decode()


class Terminal:
    def __init__(self):
        self.screen = Screen()
        self.pending = b""
        self.graphics = []
        self.seen = 0
        self.private_tail = b""

    def feed(self, data):
        self.seen += len(data)
        assert self.seen <= 262144, "bounded synthetic terminal output"
        window = self.private_tail + data
        assert PRIVATE.encode() not in window, "helper diagnostics reached terminal output"
        self.private_tail = window[-(len(PRIVATE) - 1):]
        data = self.pending + data
        self.pending = b""
        while data:
            start = data.find(b"\x1b_")
            if start < 0:
                if data.endswith(b"\x1b"):
                    self.pending, data = b"\x1b", data[:-1]
                self.screen.feed(data)
                break
            self.screen.feed(data[:start])
            end = data.find(b"\x1b\\", start + 2)
            if end < 0:
                self.pending = data[start:]
                assert len(self.pending) <= 8192, "bounded incomplete graphics control"
                break
            # Leave CSI/OSC/UTF-8 handling to the existing streaming Screen.
            # Kitty APC payloads are graphics, not visible terminal cells.
            if data[start + 2:start + 3] == b"G":
                self.graphics.append(data[start + 3:end])
                assert len(self.graphics) <= 128, "bounded graphics placements"
            data = data[end + 2:]
        assert PRIVATE not in self.screen.text(), "helper diagnostics reached visible cells"

    def transmits(self):
        return [part for part in self.graphics if part.startswith(b"a=t,")]

    def diagnostic(self):
        text = self.screen.text()
        return (f"placeholder={'[img]' in text} transmits={len(self.transmits())} "
                f"image_errors={text.count(ERROR)} terminal_bytes={self.seen}")


class Live:
    def __init__(self, binary, folder, mode):
        self.folder, self.mode = folder, mode
        self.proc = self.master = self.conn = None
        self.server = socket.socket()
        self.terminal = Terminal()
        self.wire, self.lines = bytearray(), bytearray()
        self.terminal_eof = False
        self.finished = False
        slave = None
        try:
            folder.mkdir(mode=0o700)
            helper = folder / "helper"
            helper.write_text("#!" + sys.executable + "\n" + HELPER)
            helper.chmod(0o700)
            (folder / "payload").write_text(payload())
            (folder / "payload").chmod(0o600)
            self.server.bind(("127.0.0.1", 0))
            self.server.listen(1)
            self.server.setblocking(False)
            self.master, slave = pty.openpty()
            self.saved = termios.tcgetattr(slave)
            # Keep the original URL on one body row in the no-image controls,
            # so an adjacent row also proves no blank image box was reserved.
            columns = 200 if mode in UNSUPPORTED_MODES else 120
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, columns, 0, 0))
            env = {name: value for name, value in os.environ.items()
                   if not name.startswith(("BIRC_", "TIMUI_"))
                   and name not in {"TMUX", "STY", "ZELLIJ", "SSH_CONNECTION", "KITTY_WINDOW_ID", "TERM_PROGRAM"}}
            env.update(TERM="xterm-ghostty", TERM_PROGRAM="ghostty", BIRC_HISTORY="none",
                       BIRC_PREFERENCES="none", BIRC_IMAGES="on", BIRC_CARDS="off", BIRC_MEDIA_HELPER=str(helper),
                       BIRC_MARKER_CASE=mode, XDG_CONFIG_HOME=str(folder))
            if mode == "none":
                env["TIMUI_IMAGE_PROTOCOL"] = "none"
            elif mode == "mux":
                env["TMUX"] = "synthetic-owned-multiplexer"
            elif mode in ("masked", "declared"):
                env.update(TERM="xterm-256color", TERM_PROGRAM="Apple_Terminal",
                           TIMUI_IMAGE_PROTOCOL="kitty" if mode == "declared" else "")
            self.proc = subprocess.Popen(
                [str(binary), "--plain", "--connect", "127.0.0.1", "--port", str(self.server.getsockname()[1]),
                 "--nick", "probe", "--channel", "#t", "--frames", "0"],
                stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
        except BaseException:
            self.close()
            raise
        finally:
            if slave is not None:
                os.close(slave)

    def pump(self, seconds=0.04):
        handles = ([] if self.terminal_eof else [self.master]) + (
            [self.server] if self.conn is None else [self.conn])
        for handle in select.select(handles, [], [], seconds)[0]:
            if handle is self.server:
                self.conn, _ = self.server.accept()
                self.conn.setblocking(False)
            elif handle is self.conn:
                data = self.conn.recv(65536)
                self.wire.extend(data)
                self.lines.extend(data)
                assert len(self.wire) <= 65536, "bounded synthetic IRC wire"
                while b"\r\n" in self.lines:
                    line, _, tail = self.lines.partition(b"\r\n")
                    self.lines = bytearray(tail)
                    if line.startswith(b"PING :birc_"):
                        self.send(b"PONG " + line[5:])
            else:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    data = b""
                self.terminal_eof = not data
                self.terminal.feed(data)

    def until(self, predicate, label, seconds=4):
        end = time.monotonic() + seconds
        while not predicate() and time.monotonic() < end:
            assert self.proc.poll() is None, "app exited during " + label
            self.pump()
        assert predicate(), "timeout: " + label + "; " + self.terminal.diagnostic()

    def send(self, line):
        self.conn.settimeout(2)
        try:
            self.conn.sendall(line + b"\r\n")
        finally:
            self.conn.setblocking(False)

    def command(self, text):
        data = text.encode() + b"\r"
        assert os.write(self.master, data) == len(data), "short synthetic command write"

    def ledger(self):
        path = self.folder / "helpers.jsonl"
        if not path.exists():
            return []
        assert path.stat().st_size <= 4096, "bounded helper lifecycle ledger"
        return [json.loads(line) for line in path.read_text().splitlines() if line.endswith("}")]

    def helper_done(self):
        return any(row["event"] == "done" for row in self.ledger())

    def finish(self):
        self.command("/quit")
        end = time.monotonic() + 4
        while self.proc.poll() is None and time.monotonic() < end:
            self.pump()
        assert self.proc.wait(timeout=1) == 0, "image fixture did not quit cleanly"
        assert termios.tcgetattr(self.master) == self.saved, "terminal state was not restored"
        rows = self.ledger()
        if self.mode in UNSUPPORTED_MODES:
            assert not rows, "unsupported terminal invoked an image helper before shutdown"
        else:
            assert [row["event"] for row in rows] == ["start", "done"], "helper ownership was not completed once"
            assert all(row["args"] == [URL] and row["pgid"] == self.proc.pid for row in rows), "helper source/scope changed"
            assert rows[0]["pid"] == rows[1]["pid"], "helper lifecycle identity changed"
            try:
                os.kill(rows[0]["pid"], 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError("owned helper was not reaped")
        self.finished = True

    def close(self):
        try:
            if self.proc is not None:
                if self.proc.poll() is None:
                    try:
                        self.command("/quit")
                        end = time.monotonic() + 2
                        while self.proc.poll() is None and time.monotonic() < end:
                            self.pump()
                    except (OSError, AssertionError):
                        pass
                if not self.finished:
                    # Normal success already proved every owned PID reaped.
                    # Only failed runs can leave descendant ownership debt.
                    try:
                        os.killpg(self.proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                self.proc.wait(timeout=2)
                if not self.finished:
                    print(f"image_marker failure_cleanup mode={self.mode} child_reaped=True "
                          f"terminal_restored={termios.tcgetattr(self.master) == self.saved}", flush=True)
        finally:
            if self.conn is not None:
                self.conn.close()
            self.server.close()
            if self.master is not None:
                os.close(self.master)
                self.master = None


def row_with(live, text):
    for row in range(30, 0, -1):
        cells = "".join(live.terminal.screen.cells.get((row, col), " ") for col in range(1, 201))
        if text in cells:
            return row
    return None


def no_image(live):
    assert not live.ledger(), "unsupported terminal invoked an image helper"
    assert "[img]" not in live.terminal.screen.text(), "unsupported terminal retained an image placeholder"
    assert not live.terminal.graphics, "unsupported terminal emitted image escapes"
    assert ERROR not in live.terminal.screen.text(), "unsupported terminal reported an image failure"


def plain_image(live, marker):
    live.send((":alice!u@h PRIVMSG #t :" + URL).encode())
    live.send((":alice!u@h PRIVMSG #t :" + marker).encode())
    live.until(lambda: row_with(live, URL) is not None and row_with(live, marker) is not None,
               "unchanged URL and following ordinary message")
    # The actor round trip also gives the UI a completed event after the URL.
    live.send(("PING :" + marker).encode())
    live.until(lambda: ("PONG :" + marker + "\r\n").encode() in live.wire, "unsupported image PONG")
    no_image(live)
    assert row_with(live, marker) == row_with(live, URL) + 1, "unsupported terminal reserved an image box"


def explanation(live):
    live.command("/log")
    live.until(lambda: UNSUPPORTED in live.terminal.screen.text(), "unsupported terminal log explanation")
    text = live.terminal.screen.text()
    assert text.count(UNSUPPORTED) == 1, "unsupported terminal explanation repeated"
    assert ERROR not in text, "unsupported terminal emitted a helper error"
    no_image(live)


def unsupported_case(live):
    plain_image(live, "IMAGE-AFTER-FIRST")
    explanation(live)
    live.command("/join #t")
    plain_image(live, "IMAGE-AFTER-REPEAT")
    live.command("/images off")
    plain_image(live, "IMAGE-AFTER-OFF")
    live.command("/preview " + URL)
    live.until(lambda: "*preview*" in live.terminal.screen.text()
               and "IMAGE-MARKER-BEGIN" not in live.terminal.screen.text(), "manual preview intent")
    no_image(live)
    live.command("/images on")
    live.command("/join #t")
    plain_image(live, "IMAGE-AFTER-ON")
    fcntl.ioctl(live.master, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 180, 0, 0))
    os.kill(live.proc.pid, signal.SIGWINCH)
    plain_image(live, "IMAGE-AFTER-RESIZE")
    live.command("/reconnect")
    live.conn.close()
    live.conn = None
    live.wire.clear()
    live.lines.clear()
    live.until(lambda: live.conn is not None, "unsupported reconnect", 8)
    live.until(lambda: b"USER probe" in live.wire, "unsupported reconnect registration")
    live.send(b":irc 001 probe :Welcome again")
    live.until(lambda: b"JOIN #t\r\n" in live.wire, "unsupported reconnect JOIN")
    live.send(b":probe!u@h JOIN :#t")
    live.command("/join #t")
    plain_image(live, "IMAGE-AFTER-RECONNECT")
    explanation(live)


def run_case(binary, folder, mode):
    live = Live(binary, folder, mode)
    try:
        live.until(lambda: live.conn is not None, "owned IRC connection", 8)
        live.until(lambda: b"USER probe" in live.wire, "registration")
        live.send(b":irc 001 probe :Welcome")
        live.until(lambda: b"JOIN #t\r\n" in live.wire, "initial JOIN")
        live.send(b":probe!u@h JOIN :#t")
        live.command("/join #t")
        live.send(b":alice!u@h PRIVMSG #t :IMAGE-MARKER-BEGIN")
        live.until(lambda: "IMAGE-MARKER-BEGIN" in live.terminal.screen.text(), "selected channel paint")
        if mode in UNSUPPORTED_MODES:
            unsupported_case(live)
            live.finish()
            print(f"image_marker {mode}=ok exact_url=True helper_calls=0 placeholder=False "
                  "log_explanations=1 log_errors=0 kitty_transmits=0 terminal_restored=True children_reaped=True", flush=True)
            return
        live.send((":alice!u@h PRIVMSG #t :" + URL).encode())
        live.until(live.helper_done, "offline helper completion")
        if mode in ("ghostty", "declared"):
            live.until(lambda: live.terminal.transmits() and "[img]" not in live.terminal.screen.text(),
                       "automatic Ghostty Kitty image, not a placeholder" if mode == "ghostty"
                       else "declared Kitty image, not a placeholder")
            assert any(part.startswith(b"a=p,") for part in live.terminal.graphics), "Kitty placement absent"
            png = base64.b64decode(live.terminal.transmits()[0].split(b";", 1)[1], validate=True)
            assert png.startswith(b"\x89PNG\r\n\x1a\n"), "successful helper did not transmit a PNG"
        else:
            live.until(lambda: "[img]" in live.terminal.screen.text(), "inline placeholder")
            if mode == "malformed":
                live.until(lambda: ERROR in live.terminal.screen.text(), "rejected payload diagnostic")
            assert not live.terminal.transmits(), "fallback/rejected payload emitted graphics"
        live.send(b"PING :image-marker-live")
        live.until(lambda: b"PONG :image-marker-live\r\n" in live.wire, "responsive PONG")
        live.command("/log")
        live.until(lambda: "*log*" in live.terminal.screen.text()
                   and "IMAGE-MARKER-BEGIN" not in live.terminal.screen.text(), "focused log paint")
        assert live.terminal.screen.text().count(ERROR) == (1 if mode == "malformed" else 0), "image log classification differs"
        live.finish()
        print(f"image_marker {mode}=ok exact_url=True log_errors={int(mode == 'malformed')} "
              f"kitty_transmits={len(live.terminal.transmits())} terminal_restored=True children_reaped=True", flush=True)
    finally:
        live.close()


def deadline(_signum, _frame):
    raise TimeoutError("image marker PTY total wall deadline")


def main(binary):
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(55)
    try:
        with tempfile.TemporaryDirectory(prefix="birc-image-marker-") as directory:
            for mode in ("ghostty", "none", "malformed", "mux", "masked", "declared"):
                run_case(binary, Path(directory) / mode, mode)
        print("image_marker_pty=ok cases=6", flush=True)
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "./build/birc").resolve())
