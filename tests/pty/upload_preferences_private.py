#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Additive private-settings characterization; original upload.py is unchanged.

Usage: upload_preferences_private.py BINARY INSTALLED_PREFS_HELPER MODE
MODE is coalesced, all, or full. Only full expects a failed preferences quit.
All settings, history, fake upload inputs, and loopback peers are owned here.
No real settings or credential values are read or printed.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import termios
import time
import tomllib

import upload

PREFS_FAILURE = b"birc: preferences were not fully saved (helper failure or timeout)"
PREFS_CODE = "preferences write failed (code: 2)"
SETTINGS = """[settings]
joins = true
ts = true
motd = true
history = true
hist_cap = 500
autoreconn = true
bell = true
images = false
mutes = []
theme = "dark"
"""


def seed(full):
    if not full:
        return ("version = 1\nservers = []\n\n" + SETTINGS).encode()
    rows = "".join(
        f'\n[[servers]]\nhost = "owned{i}.invalid"\nport = {6700 + i}\nchannels = ["#stored"]\n'
        for i in range(16)
    )
    return ("version = 1\n\n" + SETTINGS + rows).encode()


def reconnect_enabled(body):
    return tomllib.loads(body.decode())["settings"]["autoreconn"] is True


def config_guards():
    # Live startup enables automatic reconnect; the inherited case needs it.
    for full in (False, True):
        body = seed(full)
        assert reconnect_enabled(body), "private seed disabled required automatic reconnect"
        disabled = body.replace(b"autoreconn = true\n", b"autoreconn = false\n")
        assert not reconnect_enabled(disabled), "private reconnect guard accepted disabled settings"


def private_client(helper, full):
    class PrivateClient(upload.Client):
        def __init__(self, binary, folder):
            home = folder.parent / (folder.name + "-home")
            home.mkdir(mode=0o700)
            self.prefs_path = home / "preferences.toml"
            self.prefs_seed = seed(full)
            assert reconnect_enabled(self.prefs_seed), "private seed disabled required automatic reconnect"
            fd = os.open(self.prefs_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as output:
                output.write(self.prefs_seed)
            # This affects only the diagnostic process and its owned children.
            # Original Client still supplies its private history/upload helper.
            os.environ.update({
                "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
                "BIRC_PREFERENCES": str(self.prefs_path), "BIRC_PREFS_HELPER": str(helper),
                "BIRC_CARDS": "off", "BIRC_IMAGE_CACHE": "none",
                "BIRC_NOTIFY_HELPER": str(home / "no-notify-helper"),
            })
            for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH",
                         "BIRC_AUTH_SECRET_FD", "BIRC_AUTH_EVENT_FD"):
                os.environ.pop(name, None)
            super().__init__(binary, folder)

        def quit(self):
            # Execute every original clean-quit, QUIT, restore, privacy oracle.
            super().quit()
            info = self.prefs_path.stat()
            assert info.st_uid == os.getuid(), "private preferences changed owner"
            assert stat.S_IMODE(info.st_mode) == 0o600, "private preferences changed mode"
            saved = tomllib.loads(self.prefs_path.read_text())
            assert saved["settings"]["autoreconn"] is True, "private live settings lost automatic reconnect"
            endpoint = self.server.getsockname()[1]
            assert any(row["host"] == "127.0.0.1" and row["port"] == endpoint
                       and "#t" in row["channels"] for row in saved["servers"]), \
                "enabled preferences did not persist the owned endpoint/channel"
            assert PREFS_FAILURE not in self.raw, "successful quit reported preferences failure"

    return PrivateClient


def refused_quit(client):
    # New negative-only observation. No old exit-zero oracle is altered.
    client.command("/log")
    client.painted(PREFS_CODE)
    start = len(client.wire)
    client.command("/quit")
    deadline = time.monotonic() + 3
    while client.proc.poll() is None and time.monotonic() < deadline:
        client.pump()
    assert client.proc.poll() == 1, "refused private settings did not fail closed"
    client.pump(0.1)
    assert b"QUIT" in client.wire[start:], "preferences refusal dropped QUIT"
    assert termios.tcgetattr(client.master) == client.saved, "preferences refusal did not restore terminal state"
    client.private()
    assert PREFS_FAILURE in client.raw, "preferences refusal lost fixed quit diagnostic"
    assert client.prefs_path.read_bytes() == client.prefs_seed, "refused settings changed the full owned snapshot"
    print("upload_preferences_private helper_code=2 exit=1", flush=True)


def single(binary, helper, full):
    folder = Path(tempfile.mkdtemp(prefix="upload-private-prefs-", dir=upload.ROOT / "build"))
    success = False
    client = private_client(helper, full)(binary, folder / "coalesced")
    try:
        client.welcome()
        upload.coalesced_consent(client)
        if full:
            refused_quit(client)
        else:
            client.quit()
        success = True
    except Exception:
        client.evidence()
        print(f"upload_preferences_private evidence={client.folder}", file=sys.stderr, flush=True)
        raise
    finally:
        client.close()
        if success:
            shutil.rmtree(folder)


def main(binary, helper, mode):
    config_guards()
    assert helper.is_file() and os.access(helper, os.X_OK), "installed preferences helper unavailable"
    assert mode in ("coalesced", "all", "full"), "mode must be coalesced, all, or full"
    if mode == "all":
        original = upload.Client
        upload.Client = private_client(helper, False)
        try:
            upload.main(binary)
        finally:
            upload.Client = original
    else:
        single(binary, helper, mode == "full")
    print(f"upload_preferences_private {mode}=ok", flush=True)


if __name__ == "__main__":
    try:
        def wall_bound(_signal, _frame):
            raise TimeoutError("upload PTY wall-clock bound")
        signal.signal(signal.SIGALRM, wall_bound)
        signal.alarm(100)
        assert len(sys.argv) == 4, "expected BINARY INSTALLED_PREFS_HELPER MODE"
        main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), sys.argv[3])
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print("upload_preferences_private: " + str(error), file=sys.stderr)
        raise SystemExit(1)
