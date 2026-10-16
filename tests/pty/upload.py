#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Confirmed uploads use a fake executable and owned loopback IRC only.

No public upload or image fetch occurs. On failure, retain the named case's
terminal, wire, helper ledger, and synthetic history under build/.
"""
from __future__ import annotations

import base64
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time

from split_identity import Screen

ROOT = Path(__file__).resolve().parents[2]
F8 = b"\x1b[19~"
PRIVATE_ERROR = "PRIVATE-UPLOAD-HELPER-STDERR"

FAKE_HELPER = r'''
import json, os, signal, sys, time
from pathlib import Path
signal.signal(signal.SIGALRM, signal.SIG_DFL)
signal.alarm(10)
folder = Path(os.environ["BIRC_UPLOAD_TEST_DIR"])
path = Path(sys.argv[2]) if len(sys.argv) == 3 else Path("invalid")
kind = path.name.split(" ", 1)[0]
def record(event):
    row = json.dumps({"event": event, "kind": kind, "args": sys.argv[1:], "pid": os.getpid()}) + "\n"
    fd = os.open(folder / "helpers.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try: os.write(fd, row.encode())
    finally: os.close(fd)
record("start")
try:
    assert sys.argv[1] == "--local" and path.is_file()
    if kind.startswith("delay"):
        deadline = time.monotonic() + 8
        while not (folder / (kind + ".release")).exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        if not (folder / (kind + ".release")).exists(): raise SystemExit(8)
    if kind == "failed":
        os.write(2, ("PRIVATE-UPLOAD-HELPER-STDERR " + str(path) + "\n").encode())
        raise SystemExit(7)
    if kind == "malformed": output = "https://evil.invalid/private\n"
    elif kind == "long": output = "https://0x0.st/" + "x" * 700 + "\n"
    else: output = "https://0x0.st/s/synthetic/" + kind + path.suffix.lower() + "\n"
    record("result")
    try: os.write(1, output.encode())
    except BrokenPipeError: pass
finally: record("exit")
'''


def listening():
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(2)
    server.settimeout(4)
    return server


class Client:
    def __init__(self, binary, folder):
        self.folder = folder
        folder.mkdir()
        self.helper = folder / "birc-upload"
        self.helper.write_text("#!" + sys.executable + "\n" + FAKE_HELPER)
        self.helper.chmod(0o755)
        self.history = folder / "history"
        self.paths = []
        self.server = listening()
        self.conn = None
        self.wire, self.raw, self.pending = bytearray(), bytearray(), bytearray()
        self.screen = Screen()
        self.master, slave = pty.openpty()
        self.saved = termios.tcgetattr(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        env = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none", "BIRC_PREFERENCES": "none", "BIRC_IMAGES": "off", "BIRC_CARDS": "off",
               "BIRC_HISTORY": str(self.history), "BIRC_UPLOAD_HELPER": str(self.helper),
               "BIRC_UPLOAD_TEST_DIR": str(folder), "PATH": str(folder)}
        for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH_SECRET_FD", "BIRC_AUTH_EVENT_FD"):
            env.pop(name, None)
        try:
            self.proc = subprocess.Popen(
                [str(binary), "--plain", "--connect", "127.0.0.1", "--port", str(self.server.getsockname()[1]),
                 "--nick", "probe", "--channel", "#t", "--frames", "0"],
                stdin=slave, stdout=slave, stderr=slave, env=env,
            )
        except Exception:
            os.close(self.master)
            self.server.close()
            raise
        finally:
            os.close(slave)

    def pump(self, duration=0.05):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            for fd in select.select([self.master] + ([self.conn] if self.conn else []), [], [], 0.01)[0]:
                if fd is self.conn:
                    data = self.conn.recv(65536)
                    self.wire.extend(data)
                    self.pending.extend(data)
                    while b"\r\n" in self.pending:
                        line, _, rest = self.pending.partition(b"\r\n")
                        self.pending = bytearray(rest)
                        if line.startswith(b"PING :birc_"):
                            self.conn.sendall(b"PONG " + line[5:] + b"\r\n")
                else:
                    try:
                        data = os.read(self.master, 65536)
                    except OSError:
                        continue
                    self.raw.extend(data)
                    self.screen.feed(data)

    def until(self, predicate, label, seconds=4):
        deadline = time.monotonic() + seconds
        while not predicate() and time.monotonic() < deadline:
            self.pump()
            assert self.proc.poll() is None, "client exited while waiting for " + label
        assert predicate(), "timeout: " + label

    def painted(self, *markers):
        self.until(lambda: all(marker in self.screen.text() for marker in markers), "paint " + repr(markers))

    def command(self, text):
        os.write(self.master, text.encode() + b"\r")
        self.pump(0.15)

    def welcome(self, server=None):
        server = server or self.server
        connection, _ = server.accept()
        if self.conn:
            self.conn.close()
        self.conn = connection
        self.conn.setblocking(False)
        self.pending.clear()
        start = len(self.wire)
        self.until(lambda: b"USER probe" in self.wire[start:], "registration")
        self.conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n"
                          b":irc 353 probe = #t :probe alice\r\n:irc 366 probe #t :End\r\n"
                          b":alice!u@h PRIVMSG #t :CHANNEL-READY\r\n")
        self.painted("CHANNEL-READY", "online")
        self.until(lambda: b"JOIN #t" in self.wire[start:], "channel join")

    def records(self, event=None, kind=None):
        ledger = self.folder / "helpers.jsonl"
        rows = [] if not ledger.exists() else [json.loads(line) for line in ledger.read_text().split("\n")[:-1]]
        return [row for row in rows if (event is None or row["event"] == event) and (kind is None or row["kind"] == kind)]

    def file(self, kind, suffix=".txt"):
        path = self.folder / (kind + " file π" + suffix)
        path.write_bytes(b"synthetic local upload fixture\x00\xff\n")
        self.paths.append(path)
        return path

    def offer(self, text, first, count=None):
        before = len(self.records("start"))
        self.command(text)
        self.painted("0x0.st", "F8", "Esc", "#t", first.name.split(" π")[0])
        if count is not None:
            self.painted(f"(files={count})")
        self.pump(0.2)
        assert len(self.records("start")) == before, "staging started an unconfirmed upload"
        assert str(self.folder) not in self.screen.text(), "confirmation exposed the complete local path"
        self.private()

    def confirm(self, path):
        os.write(self.master, F8)
        kind = path.name.split(" ", 1)[0]
        self.until(lambda: bool(self.records("start", kind)), "helper start " + kind)
        assert self.records("start", kind)[-1]["args"] == ["--local", str(path)], "helper received a changed path"

    def release(self, kind):
        (self.folder / (kind + ".release")).touch()

    def finished(self, kind):
        self.until(lambda: bool(self.records("exit", kind)), "helper exit " + kind)
        if kind.startswith("delay"):
            assert self.records("result", kind), "delayed fixture timed out instead of returning a URL"
        self.pump(0.3)

    def sent(self, text, target="#t", count=1):
        expected = f"PRIVMSG {target} :{text}\r\n".encode()
        self.until(lambda: self.wire.count(expected) >= count, "expected chat send")

    def quiet_urls(self, start):
        self.pump(0.35)
        assert b"PRIVMSG" not in self.wire[start:], "rejected upload emitted a chat message"
        self.private()

    def private(self):
        assert str(self.folder).encode() not in self.wire, "local path reached IRC"
        history = self.history.read_bytes() if self.history.exists() else b""
        assert str(self.folder).encode() not in history, "local path reached saved history"
        for path in self.paths:
            assert path.name.encode() not in history, "local basename reached saved history"
        assert PRIVATE_ERROR not in self.screen.text(), "helper stderr reached the screen"
        assert b"PRIVATE-UPLOAD-HELPER-STDERR" not in history, "helper stderr reached history"
        assert b"evil.invalid/private" not in history, "malformed helper output reached history"

    def history_previous(self, expected):
        before = self.wire.count(f"PRIVMSG #t :{expected}\r\n".encode())
        os.write(self.master, b"\x1b[A")
        self.pump(0.12)
        os.write(self.master, b"\r")
        self.sent(expected, count=before + 1)

    def quit(self):
        start = len(self.wire)
        self.command("/quit")
        deadline = time.monotonic() + 3
        while self.proc.poll() is None and time.monotonic() < deadline:
            self.pump()
        assert self.proc.poll() == 0, "pending upload blocked clean quit"
        self.pump(0.1)
        assert b"QUIT" in self.wire[start:], "pending upload dropped QUIT"
        assert termios.tcgetattr(self.master) == self.saved, "quit did not restore terminal state"
        self.private()

    def close(self):
        # Release every owned fake helper first, including one adopted on quit.
        for row in self.records("start"):
            self.release(row["kind"])
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait(timeout=3)
        deadline = time.monotonic() + 10
        while len(self.records("exit")) < len(self.records("start")) and time.monotonic() < deadline:
            time.sleep(0.02)
        if self.conn:
            self.conn.close()
        self.server.close()
        os.close(self.master)
        assert len(self.records("exit")) == len(self.records("start")), "fake helper did not finish"

    def evidence(self):
        (self.folder / "screen.raw").write_bytes(self.raw)
        (self.folder / "wire.raw").write_bytes(self.wire)


def url(path):
    return "https://0x0.st/s/synthetic/" + path.name.split(" ", 1)[0] + path.suffix.lower()


def consent(client):
    client.command("HISTORY-BASE")
    client.sent("HISTORY-BASE")
    paths = [client.file("jpg", ".jpg"), client.file("gif", ".gif"), client.file("text", ".txt")]
    # A desktop drop can contain quoted paths and a percent-UTF8 local URI.
    client.offer(" ".join([shlex.quote(str(paths[0])), shlex.quote(str(paths[1])), paths[2].as_uri()]), paths[0], 3)
    for index, path in enumerate(paths):
        client.confirm(path)
        client.finished(path.name.split(" ", 1)[0])
        client.sent(url(path))
        assert len(client.records("start")) == index + 1, "one consent uploaded the next file"
        if index + 1 < len(paths):
            client.painted("F8", "Esc", paths[index + 1].name.split(" π")[0])
            client.pump(0.2)
            assert len(client.records("start")) == index + 1, "queued file ran without its own F8"
    client.history_previous("HISTORY-BASE")
    client.private()


def coalesced_consent(client):
    path = client.file("coalesced", ".jpg")
    # A key already queued with the path cannot acknowledge an unseen warning.
    data = ("/upload " + shlex.quote(str(path))).encode() + b"\r" + F8
    assert os.write(client.master, data) == len(data), "fixture input write was incomplete"
    client.pump(0.25)
    assert not client.records("start"), "coalesced F8 acknowledged an unseen confirmation"
    client.painted("0x0.st", "F8", "Esc", "coalesced file")
    client.pump(0.2)
    assert not client.records("start"), "queued F8 started after the warning paint"
    client.confirm(path)
    client.finished("coalesced")
    client.sent(url(path))
    client.pump(0.2)
    assert len(client.records("start")) == 1, "one later F8 started multiple helpers"


def queued_consent(client):
    first = client.file("delayqueued", ".gif")
    second = client.file("queued-second", ".jpg")
    client.offer("/upload " + shlex.quote(str(first)) + " " + shlex.quote(str(second)), first, 2)
    client.confirm(first)
    assert not client.records("exit", "delayqueued"), "fixture did not hold the first helper"
    # Queue a key while Busy, then release the helper without draining input.
    # Worker completion may win the next event; the key still cannot acknowledge
    # the next file's not-yet-painted warning.
    assert os.write(client.master, F8) == len(F8), "fixture input write was incomplete"
    client.release("delayqueued")
    client.finished("delayqueued")
    client.sent(url(first))
    client.painted("F8", "Esc", "queued-second file", "(files=1)")
    client.pump(0.25)
    assert len(client.records("start")) == 1, "Busy F8 acknowledged the next file's unseen warning"
    assert not client.records("start", "queued-second"), "queued file ran before a new confirmation"
    client.confirm(second)
    client.finished("queued-second")
    client.sent(url(second))
    client.pump(0.2)
    assert len(client.records("start")) == 2, "later F8 did not start exactly one queued helper"


def rejection(client):
    client.command("HISTORY-BASE")
    client.sent("HISTORY-BASE")
    path = client.file("cancel", ".gif")
    client.offer("/upload " + shlex.quote(str(path)), path)
    before = len(client.wire)
    os.write(client.master, b"\x1b")
    client.pump(0.2)
    assert client.proc.poll() is None, "Escape cancelled the entire application"
    assert not client.records("start"), "cancel started a helper"
    client.quiet_urls(before)
    client.history_previous("HISTORY-BASE")

    client.offer("/upload " + shlex.quote(str(path)), path)
    before = len(client.records("start"))
    os.write(client.master, b"\x1b[200~F8\n/upload confirm\n\x1b[19~\x1b[201~")
    client.pump(0.4)
    assert len(client.records("start")) == before, "multiline paste authorized an upload"
    client.private()
    os.write(client.master, b"\x1b")
    client.pump(0.2)
    assert client.proc.poll() is None, "paste left cancellation unusable"
    # Esc cancels only the upload and intentionally preserves the pasted
    # ordinary draft. Clear that draft before submitting a fresh upload command.
    os.write(client.master, b"\x01\x0b")  # established composer Ctrl-A / Ctrl-K
    client.pump(0.2)
    # Positive control after hostile paste: a physical F8 still authorizes.
    client.offer("/upload " + shlex.quote(str(path)), path)
    client.confirm(path)
    client.finished("cancel")
    client.sent(url(path))

    for kind in ("failed", "malformed", "long"):
        path = client.file(kind)
        client.offer("/upload " + shlex.quote(str(path)), path)
        before = len(client.wire)
        client.confirm(path)
        client.finished(kind)
        client.quiet_urls(before)
        client.command("/log")
        client.painted("*log*")
        client.private()
        assert "evil.invalid/private" not in client.screen.text(), "untrusted helper stdout reached log"
        client.command("/query #t")
        client.painted("CHANNEL-READY")
        # Each failure must release the single worker for a subsequent upload.
        good = client.file("after-" + kind, ".jpg")
        client.offer("/upload " + shlex.quote(str(good)), good)
        client.confirm(good)
        client.finished("after-" + kind)
        client.sent(url(good))


def invalid_paths(client):
    previous = "INVALID-PATH-BASE"
    client.command(previous)
    client.sent(previous)
    paths = [client.file("limit" + str(index)) for index in range(9)]
    inputs = ["file:///tmp/private%FF.jpg", "fi''le:///tmp/private%FF.jpg",
              r"fi\le:///tmp/private%FF.jpg", " ".join(shlex.quote(str(path)) for path in paths)]
    for index, text in enumerate(inputs):
        start = len(client.wire)
        client.command(text)
        client.quiet_urls(start)
        assert not client.records("start"), "invalid dropped paths started a helper"
        history = client.history.read_bytes() if client.history.exists() else b""
        assert text.encode() not in history, "invalid path input reached saved history"
        assert text.encode() not in client.wire, "invalid path input reached IRC"
        client.history_previous(previous)
        previous = "AFTER-INVALID-PATH-" + str(index)
        client.command(previous)
        client.sent(previous)
    # Valid URI words use the same quoting/escaping paths as the rejected forms.
    # Percent-UTF8 decoding must preserve the exact synthetic space/Unicode path.
    for kind, prefix in (("concat-uri", "fi''le"), ("escaped-uri", r"fi\le")):
        path = client.file(kind, ".jpg")
        client.offer(prefix + path.as_uri()[4:], path)
        client.confirm(path)
        client.finished(kind)
        client.sent(url(path))
    client.private()


def selection_cancel(client):
    path = client.file("selected", ".gif")
    client.offer("/upload " + shlex.quote(str(path)), path)
    marker = "CHANNEL-READY"
    for row in range(1, 31):
        cells = "".join(client.screen.cells.get((row, col), " ") for col in range(1, 121))
        if marker in cells:
            col = cells.index(marker) + 1
            break
    else:
        raise AssertionError("selection fixture body was not painted")
    start = len(client.raw)
    end = col + len(marker) - 1
    for button, point, suffix in ((0, col, "M"), (32, end, "M"), (0, end, "m")):
        os.write(client.master, f"\x1b[<{button};{point};{row}{suffix}".encode())
        client.pump(0.15)  # separate frames make a drag, not a click
    copied = b"\x1b]52;c;" + base64.b64encode(marker.encode())
    client.until(lambda: copied in client.raw[start:], "real native selection")
    os.write(client.master, b"\x1b")
    client.pump(0.2)
    client.painted("0x0.st", "F8", "Esc", "selected file")
    assert client.proc.poll() is None, "selection dismissal quit the application"
    assert not client.records("start"), "selection dismissal confirmed an upload"
    os.write(client.master, b"\x1b")
    client.until(lambda: "0x0.st" not in client.screen.text(), "second Escape cancels upload")
    os.write(client.master, F8)
    client.pump(0.2)
    assert not client.records("start"), "cancelled selection upload later started a helper"
    client.offer("/upload " + shlex.quote(str(path)), path)
    client.confirm(path)
    client.finished("selected")
    client.sent(url(path))


def target_change(client):
    path = client.file("delaytarget", ".gif")
    client.offer("/upload " + shlex.quote(str(path)), path)
    client.confirm(path)
    other = client.file("busy-second", ".jpg")
    before = len(client.records("start"))
    client.command("/upload " + shlex.quote(str(other)))
    os.write(client.master, F8)
    client.pump(0.2)
    assert len(client.records("start")) == before, "two upload helpers ran concurrently"
    client.command("ORDINARY-WHILE-UPLOADING")
    client.sent("ORDINARY-WHILE-UPLOADING")
    client.history_previous("ORDINARY-WHILE-UPLOADING")
    os.write(client.master, b"ali\t")
    client.pump(0.2)
    client.command("ready")
    client.sent("alice: ready")
    client.conn.sendall(b"PING :upload-busy\r\n")
    client.until(lambda: b"PONG :upload-busy\r\n" in client.wire, "PONG during helper", 1)
    client.command("/query bob")
    client.command("/query #t")
    client.painted("CHANNEL-READY")
    start = len(client.wire)
    client.release("delaytarget")
    client.finished("delaytarget")
    client.quiet_urls(start)
    assert url(path).encode() not in client.wire, "away-and-back revived stale target consent"
    client.offer("/upload " + shlex.quote(str(other)), other)
    client.confirm(other)
    client.finished("busy-second")
    client.sent(url(other))


def draft_preserve(client):
    first = client.file("delaydraft", ".gif")
    second = client.file("draft-second", ".jpg")
    client.offer("/upload " + shlex.quote(str(first)) + " " + shlex.quote(str(second)), first, 2)
    client.confirm(first)
    os.write(client.master, b"DRAFT-KEEP")
    client.painted("DRAFT-KEEP")
    client.release("delaydraft")
    client.finished("delaydraft")
    client.sent(url(first))
    client.painted("F8", "Esc", "draft-second file", "DRAFT-KEEP")
    assert len(client.records("start")) == 1, "queued confirmation started a second helper"
    os.write(client.master, b"\x1b")
    client.pump(0.2)
    client.painted("DRAFT-KEEP")
    client.command("-SENT")
    client.sent("DRAFT-KEEP-SENT")
    # F8 must preserve the same ordinary draft while authorizing the file.
    client.offer("/upload " + shlex.quote(str(second)), second)
    os.write(client.master, b"CONFIRMED-DRAFT")
    client.painted("CONFIRMED-DRAFT")
    client.confirm(second)
    client.finished("draft-second")
    client.sent(url(second))
    client.painted("CONFIRMED-DRAFT")
    client.command("-SENT")
    client.sent("CONFIRMED-DRAFT-SENT")


def pending_enter_preserve(client):
    # Native Enter clears its editor. A same-batch confirmation must restore
    # the ordinary draft without sending it or starting a second helper.
    confirmed = client.file("delayenterconfirm", ".gif")
    client.offer("/upload " + shlex.quote(str(confirmed)), confirmed)
    os.write(client.master, b"DRAFT-ENTER-CONFIRM")
    client.painted("DRAFT-ENTER-CONFIRM")
    start = len(client.wire)
    data = b"\r" + F8
    assert os.write(client.master, data) == len(data), "fixture input write was incomplete"
    client.until(lambda: bool(client.records("start", "delayenterconfirm")), "same-batch confirmation")
    client.quiet_urls(start)
    client.painted("DRAFT-ENTER-CONFIRM")
    assert len(client.records("start")) == 1, "same-batch confirmation started multiple helpers"
    assert client.records("start")[0]["args"] == ["--local", str(confirmed)], "helper received a changed path"
    client.command("-SENT")
    client.sent("DRAFT-ENTER-CONFIRM-SENT")
    client.release("delayenterconfirm")
    client.finished("delayenterconfirm")
    client.sent(url(confirmed))

    cancelled = client.file("entercancel", ".jpg")
    client.offer("/upload " + shlex.quote(str(cancelled)), cancelled)
    os.write(client.master, b"DRAFT-ENTER-CANCEL")
    client.painted("DRAFT-ENTER-CANCEL")
    start = len(client.wire)
    data = b"\r\x1b"
    assert os.write(client.master, data) == len(data), "fixture input write was incomplete"
    client.quiet_urls(start)
    assert client.proc.poll() is None, "same-batch cancellation quit the application"
    assert len(client.records("start")) == 1, "same-batch cancellation started a helper"
    client.painted("DRAFT-ENTER-CANCEL")
    client.command("-SENT")
    client.sent("DRAFT-ENTER-CANCEL-SENT")
    assert not client.records("start", "entercancel"), "cancelled file later started a helper"


def server_change(client):
    path = client.file("delayserver", ".jpg")
    client.offer("/upload " + shlex.quote(str(path)), path)
    client.confirm(path)
    second = listening()
    try:
        client.command(f"/connect 127.0.0.1 {second.getsockname()[1]}")
        client.welcome(second)
        client.command(f"/connect 127.0.0.1 {client.server.getsockname()[1]}")
        client.welcome()
        start = len(client.wire)
        client.release("delayserver")
        client.finished("delayserver")
        client.quiet_urls(start)
        assert url(path).encode() not in client.wire, "away-and-back revived stale endpoint consent"
    finally:
        second.close()


def same_endpoint_reconnect(client):
    # (+) A delayed result still sends while the connection and target stay put.
    stable = client.file("delaystable", ".gif")
    client.offer("/upload " + shlex.quote(str(stable)), stable)
    client.confirm(stable)
    client.pump(0.2)
    assert not client.records("exit", "delaystable"), "fixture did not hold the helper"
    client.release("delaystable")
    client.finished("delaystable")
    client.sent(url(stable))

    # (-) Equal host/port/target after reconnect does not restore old consent.
    stale = client.file("delayreconnect", ".jpg")
    client.offer("/upload " + shlex.quote(str(stale)), stale)
    client.confirm(stale)
    client.conn.shutdown(socket.SHUT_RDWR)
    client.conn.close()
    client.conn = None
    client.welcome()
    start = len(client.wire)
    client.release("delayreconnect")
    client.finished("delayreconnect")
    client.quiet_urls(start)
    assert url(stale).encode() not in client.wire, "same-endpoint reconnect revived old upload consent"


def pending_quit(client):
    path = client.file("delayquit", ".gif")
    client.offer("/upload " + shlex.quote(str(path)), path)
    client.confirm(path)
    client.quit()
    client.release("delayquit")
    deadline = time.monotonic() + 3
    while not client.records("exit", "delayquit") and time.monotonic() < deadline:
        time.sleep(0.02)
    assert client.records("exit", "delayquit"), "pending helper outlived its bound"
    assert url(path).encode() not in client.wire, "quit submitted a pending upload"


def main(binary):
    folder = Path(tempfile.mkdtemp(prefix="upload-pty-", dir=ROOT / "build"))
    success = False
    try:
        for name, case in (("coalesced", coalesced_consent), ("queued", queued_consent),
                           ("consent", consent), ("rejection", rejection), ("invalid-paths", invalid_paths),
                           ("selection", selection_cancel),
                           ("target", target_change), ("draft", draft_preserve),
                           ("pending-enter", pending_enter_preserve), ("endpoint", server_change),
                           ("reconnect", same_endpoint_reconnect), ("quit", pending_quit)):
            client = Client(binary, folder / name)
            try:
                client.welcome()
                case(client)
                if client.proc.poll() is None:
                    client.quit()
            except Exception:
                client.evidence()
                print(f"upload_pty case={name} evidence={client.folder}", file=sys.stderr, flush=True)
                raise
            finally:
                client.close()
            print(f"upload_pty {name}=ok", flush=True)
        success = True
    finally:
        if success:
            shutil.rmtree(folder)
    print("upload_pty=ok", flush=True)


if __name__ == "__main__":
    try:
        def wall_bound(_signal, _frame):
            raise TimeoutError("upload PTY wall-clock bound")
        signal.signal(signal.SIGALRM, wall_bound)
        signal.alarm(100)
        main(Path(sys.argv[1] if len(sys.argv) > 1 else "./build/birc").resolve())
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print("upload_pty: " + str(error), file=sys.stderr)
        raise SystemExit(1)
