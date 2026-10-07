#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Visible restored images use the live worker without changing chat history.

Archives, payloads, helpers, configuration/cache directories, and IRC peers are
owned synthetic fixtures. No decoder, image host, supplied URL, or user cache is
used. Disk-cache reuse is qualified separately, not inferred from helper calls.
"""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import pty
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time

from image_marker import ERROR, Live, PRIVATE, Terminal, UNSUPPORTED, payload


A = "https://history-image.test/archived%20a%E2%80%AF.png"
B = "https://history-image.test/live%20b%E2%80%AF.png"
HELPER = r'''
import json, os, signal, sys, time
from pathlib import Path
signal.signal(signal.SIGALRM, signal.SIG_DFL)
signal.alarm(6)
folder = Path(__file__).parent
kind = "prefs" if Path(__file__).name == "prefs-helper" else "image"
def record(event):
    fd = os.open(folder / "helpers.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        row = {"event": event, "kind": kind, "pid": os.getpid(), "pgid": os.getpgrp(), "args": sys.argv[1:]}
        os.write(fd, (json.dumps(row) + "\n").encode())
    finally:
        os.close(fd)
record("start")
if kind == "prefs":
    if sys.argv[1] == "read":
        print("BIRC_PREFS1\nsettings\t1\t0\t1\t1\t100\t0\t0\t1\nchannel\t#archive")
    else:
        sys.stdin.buffer.read(40961)
    record("done")
    raise SystemExit(0)
assert len(sys.argv) == 2 and sys.argv[1] in json.loads((folder / "urls").read_text())
try:
    busy = os.open(folder / "busy", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
except FileExistsError:
    record("concurrent")
    raise SystemExit(2)
try:
    release = folder / ("release-a" if "archived" in sys.argv[1] else "release-b")
    end = time.monotonic() + 4.5
    while not release.exists() and time.monotonic() < end:
        time.sleep(0.01)
    assert release.exists(), "owned image hold deadline"
    print("PRIVATE-IMAGE-MARKER-HELPER-BODY", file=sys.stderr)
    print((folder / "payload").read_text(), flush=True)
finally:
    os.close(busy)
    (folder / "busy").unlink()
    record("done")
'''


class HistoryLive(Live):
    def __init__(self, binary, folder, mode):
        self.folder, self.mode = folder, mode
        self.proc = self.master = self.conn = None
        self.servers = [socket.socket(), socket.socket()]
        self.server = self.servers[0]
        self.terminal = Terminal()
        self.wire, self.lines = bytearray(), bytearray()
        self.terminal_eof = self.finished = False
        self.observations = {}
        slave = None
        try:
            folder.mkdir(mode=0o700)
            for server in self.servers:
                server.bind(("127.0.0.1", 0))
                server.listen(1)
                server.setblocking(False)
            self.archive = folder / "history"
            self.original = "".join(
                f"BIRC2\t127.0.0.1:{self.server.getsockname()[1]}\t#archive\tMSG\t12:00:00\talice\t"
                + ("ARCHIVE-IMAGE " + A if n == 1 else f"ARCHIVE-{n:04d}") + "\n"
                for n in range(1, 33)
            ).encode()
            if mode == "stale":
                self.original += (f"BIRC2\t127.0.0.1:{self.servers[1].getsockname()[1]}\t#archive\tMSG"
                                  f"\t12:00:00\tbob\tCURRENT-ARCHIVE {B}\n").encode()
            self.archive.write_bytes(self.original)
            self.archive.chmod(0o600)
            for name in ("image-helper", "prefs-helper"):
                helper = folder / name
                helper.write_text("#!" + sys.executable + "\n" + HELPER)
                helper.chmod(0o700)
            (folder / "urls").write_text(json.dumps([A, B]))
            (folder / "urls").chmod(0o600)
            (folder / "payload").write_text(payload())
            (folder / "payload").chmod(0o600)
            self.master, slave = pty.openpty()
            self.saved = termios.tcgetattr(slave)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 160, 0, 0))
            env = {name: value for name, value in os.environ.items()
                   if not name.startswith(("BIRC_", "TIMUI_"))
                   and name not in {"TMUX", "STY", "ZELLIJ", "SSH_CONNECTION", "KITTY_WINDOW_ID", "TERM_PROGRAM"}}
            env.update(TERM="xterm-ghostty", TERM_PROGRAM="ghostty", BIRC_HISTORY=str(self.archive),
                       BIRC_IMAGES="off" if mode == "off" else "on", BIRC_CARDS="off",
                       BIRC_PREFERENCES=str(folder / "preferences.toml"), BIRC_PREFS_HELPER=str(folder / "prefs-helper"),
                       BIRC_MEDIA_HELPER=str(folder / "image-helper"), XDG_CONFIG_HOME=str(folder / "config"),
                       XDG_CACHE_HOME=str(folder / "cache"))
            if mode == "unsupported":
                env.update(TERM="xterm-256color", TERM_PROGRAM="Apple_Terminal", TIMUI_IMAGE_PROTOCOL="")
            self.proc = subprocess.Popen(
                [str(binary), "--plain", "--connect", "127.0.0.1", "--port", str(self.server.getsockname()[1]),
                 "--nick", "probe", "--channel", "#archive", "--frames", "0"],
                stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
        except BaseException:
            self.close()
            raise
        finally:
            if slave is not None:
                os.close(slave)

    def image_calls(self, event="start"):
        return [row for row in self.ledger() if row["kind"] == "image" and row["event"] == event]

    def failure_diagnostic(self):
        # This test can paint only its synthetic archive and loopback peer.
        # Still redact the helper sentinel if a privacy assertion itself fails.
        print("history_images failure mode=" + self.mode + " observations=" + json.dumps(self.observations), flush=True)
        print("history_images helper_ledger=" + json.dumps(self.ledger()).replace(PRIVATE, "[redacted]"), flush=True)
        graphics = [{"header": part.split(b";", 1)[0].decode("ascii", "replace"), "bytes": len(part)}
                    for part in self.terminal.graphics]
        print("history_images graphics=" + json.dumps(graphics), flush=True)
        for row in range(1, 31):
            cells = "".join(self.terminal.screen.cells.get((row, col), " ") for col in range(1, 181)).rstrip()
            print(f"history_images row{row:02d}=" + cells.replace(PRIVATE, "[redacted]"), flush=True)

    def release(self, name):
        (self.folder / name).touch(mode=0o600)

    def welcome(self):
        self.until(lambda: self.conn is not None, "owned archive IRC connection", 8)
        self.until(lambda: b"USER probe" in self.wire, "archive registration")
        self.send(b":irc 001 probe :Welcome")
        self.until(lambda: b"JOIN #archive\r\n" in self.wire, "archive JOIN")
        self.send(b":probe!u@h JOIN :#archive")
        self.command("/join #archive")
        self.until(lambda: "ARCHIVE-0032" in self.terminal.screen.text(), "restored channel tail")
        assert not self.image_calls(), "offscreen archive image started a helper"

    def show_old(self):
        for _ in range(3):
            if A in self.terminal.screen.text():
                return
            os.write(self.master, b"\x1b[5~")
            self.pump(0.12)
        self.until(lambda: A in self.terminal.screen.text(), "scrolled archived URL")

    def tail(self):
        for _ in range(3):
            os.write(self.master, b"\x1b[6~")
            self.pump(0.06)

    def pong(self, marker):
        self.send(("PING :" + marker).encode())
        self.until(lambda: ("PONG :" + marker + "\r\n").encode() in self.wire, "image-worker PONG", 1)
        assert not any(line.startswith(b"PRIVMSG ") for line in self.wire.split(b"\r\n")), "image handling sent IRC chat"
        assert A.encode() not in self.wire and B.encode() not in self.wire, "image URL reached outbound IRC"

    def finish(self):
        self.command("/quit")
        end = time.monotonic() + 4
        while self.proc.poll() is None and time.monotonic() < end:
            self.pump()
        assert self.proc.wait(timeout=1) == 0, "history image quit failed"
        assert termios.tcgetattr(self.master) == self.saved, "history image terminal was not restored"
        rows = self.ledger()
        assert any(r["kind"] == "prefs" and r["event"] == "done" and r["args"][0] == "read"
                   for r in rows), "startup preference read was not exercised"
        starts = [(r["kind"], r["pid"], tuple(r["args"])) for r in rows if r["event"] == "start"]
        done = [(r["kind"], r["pid"], tuple(r["args"])) for r in rows if r["event"] == "done"]
        assert sorted(starts) == sorted(done), "history helper lifecycle incomplete"
        assert not any(r["event"] == "concurrent" for r in rows), "two physical image helpers ran"
        assert all(r["pgid"] == self.proc.pid for r in rows), "history helper escaped owned group"
        if self.mode in ("off", "unsupported"):
            assert not self.image_calls(), "blocked history image invoked a helper before shutdown"
        assert PRIVATE not in self.terminal.screen.text(), "helper diagnostics reached visible history"
        for pid in {r["pid"] for r in rows}:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue
            raise AssertionError("history helper was not reaped")
        self.finished = True

    def close(self):
        try:
            super().close()
        finally:
            for server in self.servers:
                server.close()


def visible_shared(live):
    live.show_old()
    live.observations["scrolled_A_visible"] = A in live.terminal.screen.text()
    live.until(lambda: len(live.image_calls()) == 1, "visible archived image worker")
    live.observations["worker_A_visible"] = A in live.terminal.screen.text()
    assert live.image_calls()[0]["args"] == [A], "archived URL identity changed"
    assert not live.image_calls("done") and not live.terminal.transmits(), "archive helper was not held"
    live.pong("held-archive")
    # Admission adds six virtual media rows while preserving the bottom
    # message/character anchor. Re-establish a visible URL before resize.
    live.show_old()
    assert A in live.terminal.screen.text(), "archived URL is not visible before resize"
    live.observations["pre_resize_A_visible"] = A in live.terminal.screen.text()
    fcntl.ioctl(live.master, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 180, 0, 0))
    os.kill(live.proc.pid, signal.SIGWINCH)
    live.until(lambda: A in live.terminal.screen.text(), "archived URL retained during resize")
    live.tail()
    live.send((":bob!u@h PRIVMSG #archive :LIVE-IMAGE " + B).encode())
    live.until(lambda: "LIVE-IMAGE" in live.terminal.screen.text(), "live row while archive helper held")
    live.pong("shared-queue")
    assert len(live.image_calls()) == 1, "live image bypassed the owned archive worker"
    checkpoint = live.archive.read_bytes()
    assert checkpoint.count(A.encode()) == 1 and checkpoint.count(B.encode()) == 1, "archive/live checkpoint duplicated or lost URLs"
    live.release("release-a")
    live.until(lambda: len(live.image_calls()) == 2, "queued live image worker")
    assert [r["args"] for r in live.image_calls()] == [[A], [B]], "live/history queue identity changed or duplicated"
    live.show_old()
    live.until(lambda: bool(live.terminal.transmits()), "archived image rendered after async completion")
    assert A in live.terminal.screen.text() and ERROR not in live.terminal.screen.text(), "image completion stole focus or failed"
    assert live.archive.read_bytes() == checkpoint, "image completion resaved restored archive rows"
    live.release("release-b")
    live.tail()
    live.until(lambda: len(live.image_calls("done")) == 2, "shared image jobs complete")
    live.until(lambda: len(live.terminal.transmits()) >= 2, "live image rendered through shared path")
    assert [r["args"] for r in live.image_calls()] == [[A], [B]], "viewport changes duplicated a request ID"
    assert live.archive.read_bytes() == checkpoint, "image rendering changed persisted history"


def blocked(live):
    live.show_old()
    live.pong("blocked-archive")
    assert not live.image_calls() and not live.terminal.graphics, "disabled/unsupported archive image invoked work"
    assert "[img]" not in live.terminal.screen.text() and A in live.terminal.screen.text(), "blocked archive URL is not ordinary text"
    checkpoint = live.archive.read_bytes()
    if live.mode == "unsupported":
        live.command("/log")
        live.until(lambda: UNSUPPORTED in live.terminal.screen.text(), "one archive capability explanation")
        assert live.terminal.screen.text().count(UNSUPPORTED) == 1, "archive capability explanation repeated"
    assert live.archive.read_bytes() == checkpoint, "blocked archive rendering resaved history"


def stale(live):
    live.show_old()
    live.until(lambda: len(live.image_calls()) == 1, "old endpoint archive worker")
    live.command("/connect 127.0.0.1:" + str(live.servers[1].getsockname()[1]))
    live.conn.close()
    live.conn = None
    live.server = live.servers[1]
    live.wire.clear()
    live.lines.clear()
    live.until(lambda: live.conn is not None, "new endpoint connection", 8)
    live.until(lambda: b"USER probe" in live.wire, "new endpoint registration")
    live.send(b":irc 001 probe :New endpoint")
    live.until(lambda: b"JOIN #archive\r\n" in live.wire, "new endpoint JOIN")
    live.send(b":probe!u@h JOIN :#archive")
    live.command("/join #archive")
    live.until(lambda: "CURRENT-ARCHIVE" in live.terminal.screen.text(), "new endpoint archive focus")
    assert A not in live.terminal.screen.text() and len(live.image_calls()) == 1, "old endpoint intent survived the scope change"
    live.release("release-a")
    live.until(lambda: len(live.image_calls()) == 2, "current worker after stale completion")
    live.pong("after-stale-image")
    assert not live.terminal.transmits(), "old endpoint image completion was rendered"
    assert live.image_calls()[1]["args"] == [B], "new endpoint image identity changed"
    checkpoint = live.archive.read_bytes()
    live.release("release-b")
    live.until(lambda: bool(live.terminal.transmits()), "current endpoint image rendered")
    assert B in live.terminal.screen.text() and A not in live.terminal.screen.text(), "stale image changed the new endpoint focus"
    assert live.archive.read_bytes() == checkpoint, "stale/current image completion resaved archive"


def deadline(_signum, _frame):
    raise TimeoutError("history image PTY total wall deadline")


def main(binary):
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(70)
    try:
        with tempfile.TemporaryDirectory(prefix="birc-history-images-") as directory:
            for mode, check in (("shared", visible_shared), ("off", blocked), ("unsupported", blocked), ("stale", stale)):
                live = HistoryLive(binary, Path(directory) / mode, mode)
                try:
                    live.welcome()
                    check(live)
                    live.finish()
                    assert live.archive.read_bytes().count(A.encode()) == 1, "shutdown resaved an imported image row"
                    print(f"history_images {mode}=ok image_calls={len(live.image_calls())} "
                          "history_checkpoint=True terminal_restored=True children_reaped=True", flush=True)
                except BaseException:
                    live.failure_diagnostic()
                    raise
                finally:
                    live.close()
        print("history_images_pty=ok cases=4", flush=True)
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "./build/birc").resolve())
