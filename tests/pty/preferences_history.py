#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Native startup policy/checkpoint checks; owned archives and loopback IRC only."""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import pty
import runpy
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time

from preferences import Client, HELPER, SOURCE, Screen


class HistoryClient(Client):
    def __init__(self, binary, folder, *, history=True, cap=200, held=False, invalid=False, archive_rows=120, with_channel=False):
        self.folder, self.mode = folder, "held" if held else "normal"
        folder.mkdir(mode=0o700)
        self.path, self.history = folder / "preferences.toml", folder / "archive"
        self.server = socket.socket()
        self.conn = self.proc = self.master = None
        self.wire, self.pending = bytearray(), bytearray()
        self.terminal_tail, self.screen = b"", Screen()
        slave = None
        try:
            self.server.bind(("127.0.0.1", 0))
            self.server.listen(1)
            self.server.setblocking(False)
            self.port = self.server.getsockname()[1]
            body = f"BIRC_PREFS1\nsettings\t1\t0\t1\t{int(history)}\t{cap}\t0\t0\t0\n"
            runpy.run_path(str(SOURCE))["write"](self.path, "127.0.0.1", self.port, body)
            if invalid:
                self.path.write_text("version = 999\n")
            self.original = "".join(
                f"BIRC2\t127.0.0.1:{self.port}\t*server*\tMSG\t12:00:00\talice\tARCHIVE-{n:04d}\n"
                for n in range(1, archive_rows + 1)
            ).encode()
            if with_channel:
                self.original += f"BIRC2\t127.0.0.1:{self.port}\t#archived\tMSG\t12:00:00\talice\tCHANNEL-ARCHIVE\n".encode()
            self.history.write_bytes(self.original)
            self.history.chmod(0o600)
            helper = folder / "helper"
            helper.write_text("#!" + sys.executable + "\n" + HELPER)
            helper.chmod(0o700)
            self.master, slave = pty.openpty()
            self.saved = termios.tcgetattr(slave)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
            env = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": str(self.history),
                   "BIRC_IMAGES": "off", "BIRC_PREFERENCES": str(self.path), "BIRC_PREFS_HELPER": str(helper),
                   "XDG_CONFIG_HOME": str(folder), "BIRC_PREFS_TEST_DIR": str(folder),
                   "BIRC_PREFS_TEST_MODE": self.mode, "BIRC_PREFS_TEST_SOURCE": str(SOURCE)}
            for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH", "BIRC_HISTORY_LINES",
                         "BIRC_AUTH_SECRET_FD", "BIRC_AUTH_EVENT_FD", "BIRC_FRAME_PROFILE"):
                env.pop(name, None)
            self.proc = subprocess.Popen(
                [str(binary), "--plain", "--connect", "127.0.0.1", "--port", str(self.port),
                 "--nick", "probe", "--frames", "0"], stdin=slave, stdout=slave, stderr=slave,
                env=env, start_new_session=True)
        except BaseException:
            self.close()
            raise
        finally:
            if slave is not None:
                os.close(slave)

    def page(self, up):
        for _ in range(8):
            os.write(self.master, b"\x1b[5~" if up else b"\x1b[6~")
            self.pump(0.1)
        end = time.monotonic() + 0.15
        while time.monotonic() < end:
            self.pump(0.02)


def blocked(binary, folder, *, invalid=False, edit=False):
    client = HistoryClient(binary, folder, history=edit, held=edit, invalid=invalid)
    try:
        if edit:
            client.until(lambda: (folder / "read-started").exists(), "held initial preference read")
            client.painted("probe", "connecting")
            assert client.conn is None and not client.wire, "network preceded startup policy release"
            client.command("/set history off", "setting 'history' is now OFF")
            assert client.conn is None and not client.wire, "explicit edit bypassed startup policy"
            (folder / "release").touch(mode=0o600)
        client.welcome()
        assert "ARCHIVE-" not in client.screen.text(), "disabled/unknown policy restored archive"
        assert "Reconnected" not in client.screen.text(), "disabled/unknown policy added an archive divider"
        client.send(b":irc.test 372 probe :- NO-HISTORY-APPEND")
        client.painted("NO-HISTORY-APPEND")
        client.page(True)
        assert "ARCHIVE-" not in client.screen.text(), "disabled/unknown policy retained hidden archive"
        assert "Reconnected" not in client.screen.text(), "disabled/unknown policy retained a hidden archive divider"
        client.page(False)
        client.quit()
        assert client.history.read_bytes() == client.original, "disabled/unknown history policy appended"
        if edit:
            saved = runpy.run_path(str(SOURCE))["tomllib"].loads(client.path.read_text())
            assert saved["settings"]["history"] is False, "late read lost accepted history off"
    finally:
        client.close()


def capped(binary, folder, cap):
    client = HistoryClient(binary, folder, cap=cap)
    try:
        client.welcome()
        client.painted("ARCHIVE-0120", "Reconnected:")
        assert client.screen.text().count("Reconnected:") == 1, "restored server archive has duplicate startup dividers"
        client.page(True)
        if cap == 1:
            assert "ARCHIVE-0120" in client.screen.text() and "ARCHIVE-0119" not in client.screen.text(), "saved cap1 did not control initial restore"
        else:
            assert "ARCHIVE-0001" in client.screen.text(), "saved cap above100 did not restore oldest retained row"
        client.page(False)
        client.send(b":irc.test 372 probe :- POST-COMPLETION-LIVE")
        client.painted("POST-COMPLETION-LIVE")
        client.quit()
        persisted = client.history.read_bytes()
        assert persisted.startswith(client.original), "initial archive was replaced"
        assert persisted.count(b"POST-COMPLETION-LIVE") == 1, "completion checkpoint lost/duplicated new live row"
        assert b"Reconnected:" not in persisted, "startup divider entered persisted chat history"
        for n in range(1, 121):
            assert persisted.count(f"ARCHIVE-{n:04d}".encode()) == 1, "restored row appended as a new event"
    finally:
        client.close()


def divider(binary, folder):
    client = HistoryClient(binary, folder, cap=1, archive_rows=2, with_channel=True)
    try:
        client.welcome()
        client.painted("ARCHIVE-0002", "Reconnected:")
        assert client.screen.text().count("Reconnected:") == 1, "restored control buffer divider count differs"
        os.write(client.master, b"\x1b[1;2C")
        client.painted("CHANNEL-ARCHIVE", "Reconnected:")
        assert client.screen.text().count("Reconnected:") == 1, "restored channel buffer divider count differs"
        client.quit()
        persisted = client.history.read_bytes()
        assert b"Reconnected:" not in persisted, "channel startup divider was persisted"
        assert persisted.count(b"CHANNEL-ARCHIVE") == 1, "channel archive was appended as a new event"
    finally:
        client.close()


def empty(binary, folder):
    client = HistoryClient(binary, folder, archive_rows=0)
    try:
        client.welcome()
        assert "Reconnected" not in client.screen.text(), "empty archive created a startup divider"
        client.page(True)
        assert "Reconnected" not in client.screen.text(), "local-only rows received an archive divider"
        client.page(False)
        client.quit()
        assert b"Reconnected:" not in client.history.read_bytes(), "empty startup divider was persisted"
    finally:
        client.close()


def deadline(_signum, _frame):
    raise TimeoutError("preferences history PTY wall deadline")


def main(binary):
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(90)
    try:
        with tempfile.TemporaryDirectory(prefix="birc-preferences-history-pty-") as directory:
            root = Path(directory)
            blocked(binary, root / "off")
            blocked(binary, root / "invalid", invalid=True)
            blocked(binary, root / "late-off", edit=True)
            capped(binary, root / "cap1", 1)
            capped(binary, root / "cap200", 200)
            divider(binary, root / "dividers")
            empty(binary, root / "empty")
        print("preferences_history_pty=ok cases=7 children_reaped=True")
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
