#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Live preferences use owned files/helpers and loopback IRC only."""
from __future__ import annotations

import codecs
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import runpy
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time

from split_identity import Screen as BaseScreen


SOURCE = Path(__file__).resolve().parents[2] / "src/launcher/preferences_birc.py"
PRIVATE = "PRIVATE-PREFERENCES-HELPER-BODY"
WIRE = "BIRC_PREFS1\nsettings\t1\t0\t1\t1\t200\t0\t1\t0\n"
HELPER = r'''
import json, os, runpy, signal, sys, time
from pathlib import Path
signal.signal(signal.SIGALRM, signal.SIG_DFL)
signal.alarm(6)
folder = Path(os.environ["BIRC_PREFS_TEST_DIR"])
def record(event):
    fd = os.open(folder / "helpers.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try: os.write(fd, (json.dumps({"event": event, "mode": sys.argv[1], "pid": os.getpid()}) + "\n").encode())
    finally: os.close(fd)
record("start")
if sys.argv[1] == "read":
    (folder / "read-started").touch(mode=0o600)
    if os.environ["BIRC_PREFS_TEST_MODE"] == "held":
        end = time.monotonic() + 4.5
        while not (folder / "release").exists() and time.monotonic() < end:
            time.sleep(0.01)
        if not (folder / "release").exists(): raise SystemExit(8)
    if os.environ["BIRC_PREFS_TEST_MODE"] == "malformed":
        print("PRIVATE-PREFERENCES-HELPER-BODY stdout")
        print("PRIVATE-PREFERENCES-HELPER-BODY stderr", file=sys.stderr)
        record("done")
        raise SystemExit(0)
code = runpy.run_path(os.environ["BIRC_PREFS_TEST_SOURCE"])["main"]()
record("done")
raise SystemExit(code)
'''


class Screen(BaseScreen):
    """Keep incomplete terminal controls and UTF-8 out of final screen cells."""

    control = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x1b\x07]*(?:\x1b\\|\x07)|.)")

    def __init__(self):
        super().__init__()
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.pending_control = ""

    def feed(self, data):
        text = self.pending_control + self.decoder.decode(data)
        self.pending_control = ""
        pos = 0
        while (start := text.find("\x1b", pos)) >= 0:
            token = self.control.match(text, start)
            # A generic two-byte escape must not swallow an incomplete CSI
            # or OSC introducer. The shared cell parser sees complete tokens.
            if token is None or (token.end() == start + 2 and text[start + 1] in "[]"):
                self.pending_control = text[start:]
                assert len(self.pending_control) <= 8192, "incomplete terminal control exceeded its bound"
                text = text[:start]
                break
            pos = token.end()
        super().feed(text.encode("utf-8"))


class Client:
    def __init__(self, binary: Path, folder: Path, channels, *, explicit=None, mode="normal"):
        self.folder, self.mode = folder, mode
        folder.mkdir(mode=0o700)
        self.path = folder / "preferences.toml"
        self.server = socket.socket()
        self.conn = self.proc = None
        self.master = slave = None
        self.wire = bytearray()
        self.pending = bytearray()
        self.terminal_tail = b""
        self.screen = Screen()
        try:
            self.server.bind(("127.0.0.1", 0))
            self.server.listen(1)
            self.server.setblocking(False)
            self.port = self.server.getsockname()[1]
            prefs = runpy.run_path(str(SOURCE))
            host = "other.example" if channels is None else "127.0.0.1"
            body = WIRE + "".join("channel\t" + name + "\n" for name in (channels or []))
            prefs["write"](self.path, host, self.port, body)
            if mode == "invalid-file":
                self.path.write_text("version = 999\n# " + PRIVATE + "\n")
            helper = folder / "helper path"
            helper.write_text("#!" + sys.executable + "\n" + HELPER)
            helper.chmod(0o700)
            self.master, slave = pty.openpty()
            self.saved = termios.tcgetattr(slave)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
            env = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none",
                   "BIRC_IMAGES": "off", "BIRC_PREFERENCES": str(self.path),
                   "BIRC_PREFS_HELPER": str(folder / "missing helper" if mode == "missing-helper" else helper),
                   "XDG_CONFIG_HOME": str(folder), "BIRC_PREFS_TEST_DIR": str(folder),
                   "BIRC_PREFS_TEST_MODE": mode, "BIRC_PREFS_TEST_SOURCE": str(SOURCE)}
            for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH", "BIRC_HISTORY_LINES",
                         "BIRC_AUTH_SECRET_FD", "BIRC_AUTH_EVENT_FD", "BIRC_FRAME_PROFILE"):
                env.pop(name, None)
            args = [str(binary), "--plain", "--connect", "127.0.0.1", "--port", str(self.port),
                    "--nick", "probe", "--frames", "0"]
            if explicit is not None:
                args += ["--channel", explicit]
            self.proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                                         env=env, start_new_session=True)
        except BaseException:
            self.close()
            raise
        finally:
            if slave is not None:
                os.close(slave)

    def pump(self, duration=0.04):
        handles = [self.master, self.server] + ([self.conn] if self.conn is not None else [])
        for handle in select.select(handles, [], [], duration)[0]:
            if handle is self.server:
                self.conn, _ = self.server.accept()
                self.conn.setblocking(False)
            elif handle is self.conn:
                data = self.conn.recv(65536)
                self.wire.extend(data)
                self.pending.extend(data)
                assert len(self.wire) <= 65536, "synthetic wire exceeded its bound"
                while b"\r\n" in self.pending:
                    line, _, rest = self.pending.partition(b"\r\n")
                    self.pending = bytearray(rest)
                    if line.startswith(b"PING :birc_"):
                        self.send(b"PONG " + line[5:])
            else:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    data = b""
                # A bounded privacy window also catches output erased in the
                # same read. UI-state assertions still use final screen cells.
                window = self.terminal_tail + data
                assert PRIVATE.encode() not in window, "private helper/file body reached the terminal"
                self.terminal_tail = window[-(len(PRIVATE) - 1):]
                self.screen.feed(data)
                cells = "".join(value for _, value in sorted(self.screen.cells.items()))
                assert PRIVATE not in cells, "private helper/file body was painted"

    def until(self, predicate, label, seconds=4):
        end = time.monotonic() + seconds
        while not predicate() and time.monotonic() < end:
            assert self.proc.poll() is None, "client exited during " + label
            self.pump()
        assert predicate(), "timeout: " + label + "\n" + self.screen_diagnostic()

    def screen_diagnostic(self):
        # Owned synthetic cells only; never disclose the privacy sentinel or
        # dump terminal bytes, helper output, environment, or process arguments.
        try:
            settings = runpy.run_path(str(SOURCE))["tomllib"].loads(self.path.read_text())["settings"]
            durable = json.dumps({name: settings.get(name) if isinstance(settings.get(name), bool) else None
                                  for name in ("ts", "bell")})
        except (OSError, ValueError, KeyError):
            durable = "unavailable"
        return ("durable booleans: " + durable + "\nfinal incremental screen:\n"
                + self.screen.text().replace(PRIVATE, "<redacted>")[:4096])

    def painted(self, *markers):
        self.until(lambda: all(marker in self.screen.text() for marker in markers), "expected screen")

    def command(self, text, *markers):
        os.write(self.master, text.encode() + b"\r")
        if markers:
            self.painted(*markers)

    def send(self, line):
        self.conn.settimeout(1)
        try:
            self.conn.sendall(line + b"\r\n")
        finally:
            self.conn.setblocking(False)

    def welcome(self):
        self.until(lambda: b"USER probe " in self.wire, "owned registration")
        self.send(b":irc.test 001 probe :PREFERENCES-WELCOME")
        self.painted("PREFERENCES-WELCOME", "online")

    def joins(self):
        return [line for line in bytes(self.wire).split(b"\r\n") if line.startswith(b"JOIN ")]

    def expected_joins(self, names):
        wanted = [b"JOIN " + name.encode() for name in names]
        if wanted:
            self.until(lambda: all(line in self.joins() for line in wanted), "loaded JOIN set")
        end = time.monotonic() + 0.15
        while time.monotonic() < end:
            self.pump(0.02)
        assert self.joins() == wanted, "loaded channel scope/explicit override differs"

    def setting(self, name, value):
        # /settings clears and repaints its table, so an old confirmation row
        # cannot satisfy this check. Do not queue another command when the
        # current table already satisfies the observer: it can be consumed by
        # the next command's immediate redraw rather than its own paint.
        end = time.monotonic() + 4
        pattern = re.compile(r"\b" + name + r"\s*:\s*" + value + r"\b")
        while time.monotonic() < end:
            if pattern.search(self.screen.text()):
                return
            self.command("/settings")
            self.pump(0.08)
        raise AssertionError("loaded setting was not painted\n" + self.screen_diagnostic())

    def quit(self):
        self.command("/quit")
        end = time.monotonic() + 8
        while self.proc.poll() is None and time.monotonic() < end:
            self.pump()
        assert self.proc.wait(timeout=1) == 0, "preferences blocked clean quit"
        assert termios.tcgetattr(self.master) == self.saved, "terminal state was not restored"
        ledger = self.folder / "helpers.jsonl"
        for pid in {json.loads(line)["pid"] for line in ledger.read_text().splitlines()} if ledger.exists() else ():
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue
            raise AssertionError("helper was not reaped on normal quit")

    def close(self):
        if self.proc is not None:
            # The app can exit before a failing assertion sees its helper.
            # Its isolated group still owns any such descendant.
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.proc.wait(timeout=3)
        if self.conn is not None:
            self.conn.close()
        self.server.close()
        if self.master is not None:
            os.close(self.master)
            self.master = None


def loaded_case(binary, folder, channels, expected, *, explicit=None, held=False):
    client = Client(binary, folder, channels, explicit=explicit, mode="held" if held else "normal")
    try:
        if held:
            client.until(lambda: (folder / "read-started").exists(), "held helper started")
            client.painted("probe", "connecting")
            assert not (folder / "release").exists(), "first paint followed helper release"
            assert client.conn is None, "connection bypassed held initial preferences policy"
            assert not client.joins(), "JOIN bypassed held preferences read"
            client.command("/set ts on", "setting 'ts' is now ON")
            assert client.conn is None, "setting input bypassed held initial preferences policy"
            assert not client.joins(), "setting input bypassed held preferences read"
            (folder / "release").touch(mode=0o600)
        client.welcome()
        client.setting("ts", "ON" if held else "OFF")
        client.expected_joins(expected)
        if held:
            client.setting("ts", "ON")
        client.command("/set bell off", "setting 'bell' is now OFF")
        client.quit()
        saved = runpy.run_path(str(SOURCE))["tomllib"].loads(client.path.read_text())
        assert saved["settings"]["ts"] is held, "late read overwrote explicit same-value setting"
        assert saved["settings"]["bell"] is False, "quit lost the latest setting"
        row = next(item for item in saved["servers"] if item["host"] == "127.0.0.1" and item["port"] == client.port)
        assert row["channels"] == expected, "quit saved the wrong endpoint channel intent"
    finally:
        client.close()


def error_case(binary, folder, mode):
    client = Client(binary, folder, ["#saved"], mode=mode)
    before = client.path.read_bytes()
    try:
        client.welcome()
        client.expected_joins(["#birc"])
        client.command("/log", "preferences read failed (code: 2)")
        assert PRIVATE not in client.screen.text(), "diagnostic disclosed helper/file body"
        client.quit()
        assert client.path.read_bytes() == before, "failed read rewrote an existing config"
    finally:
        client.close()


def deadline(_signum, _frame):
    raise TimeoutError("preferences PTY total wall deadline")


def setting_observer_guard():
    class Table:
        value = "ts : ON"

        def text(self):
            return self.value

    client = object.__new__(Client)
    client.screen = Table()
    writes = []

    def command(text):
        writes.append(text)
        client.screen.value = "ts : ON"

    client.command = command
    client.pump = lambda _duration: None
    client.setting("ts", "ON")
    assert not writes, "satisfied observer queued another settings command"
    client.screen.value = "ts : OFF"
    client.setting("ts", "ON")
    assert writes == ["/settings"], "unsatisfied observer did not request a fresh settings table"


def screen_parser_guard():
    data = ("\x1b[2J\x1b[3;4H\x1b[38;2;160;160;160msetting 'bell' is now OFF\x1b[0m"
            "\x1b[30;3Hé🐈\x1b]0;owned fixture\x07").encode()
    whole = BaseScreen()
    whole.feed(data)
    split = Screen()
    for byte in data:
        split.feed(bytes([byte]))
    assert split.cells == whole.cells, "byte-split ANSI/UTF8 observer differs from whole stream"
    pending = Screen()
    pending.feed(b"\x1b[3;")
    assert not pending.cells, "incomplete ANSI suffix reached visible cells"
    pending.feed(b"4H\xc3")
    assert not pending.cells, "incomplete UTF8 suffix reached visible cells"
    pending.feed(b"\xa9")
    assert pending.cells == {(3, 4): "é"}, "complete UTF8 suffix did not restore exact cursor/cell"
    try:
        Screen().feed(b"\x1b]" + b"x" * 8193)
    except AssertionError as error:
        assert str(error) == "incomplete terminal control exceeded its bound"
    else:
        raise AssertionError("incomplete terminal control was not bounded")


def main(binary):
    setting_observer_guard()
    screen_parser_guard()
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(75)
    try:
        with tempfile.TemporaryDirectory(prefix="birc-preferences-pty-") as directory:
            root = Path(directory)
            loaded_case(binary, root / "held", ["#saved", "+#second"], ["#saved", "+#second"], held=True)
            loaded_case(binary, root / "explicit", ["#saved"], ["#cli"], explicit="#cli")
            loaded_case(binary, root / "unknown", None, ["#birc"])
            loaded_case(binary, root / "empty", [], [])
            for mode in ("malformed", "invalid-file", "missing-helper"):
                error_case(binary, root / mode, mode)
        print("preferences_pty=ok cases=7 children_reaped=True")
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
