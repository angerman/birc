#!/usr/bin/env python3
"""Pty test verifying /settings panel, /set, and /toggle commands.

usage: settings.py ./build/birc
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time


def drain(fd: int, timeout: float = 0.5) -> bytes:
    out = bytearray()
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                out += chunk
            except OSError:
                break
    return bytes(out)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    proc = subprocess.Popen(
        [birc, "--demo", "--nick", "me", "--frames", "0"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)

    try:
        # Drain initial paint
        init_out = drain(master, 1.0)
        if b"#birc" not in init_out:
            print("FAIL: initial screen missing #birc", file=sys.stderr)
            return 1

        # Test 1: Open /settings panel
        os.write(master, b"/settings\r")
        out1 = drain(master, 0.8)
        if b"*settings*" not in out1 or b"=== BIRC SETTINGS ===" not in out1:
            print("FAIL: /settings did not open settings panel", file=sys.stderr)
            return 1
        if b"joins" not in out1 or b"ON" not in out1:
            print("FAIL: settings panel missing joins: ON", file=sys.stderr)
            return 1
        if b"autoreconn" not in out1:
            print("FAIL: settings panel missing autoreconn setting", file=sys.stderr)
            return 1
        if b"bell" not in out1:
            print("FAIL: settings panel missing bell setting", file=sys.stderr)
            return 1

        # Test 2: Turn off joins with /set joins off
        os.write(master, b"/set joins off\r")
        out2 = drain(master, 0.8)
        if b"OFF" not in out2:
            print("FAIL: /set joins off did not update setting to OFF", file=sys.stderr)
            return 1

        # Test 3: Toggle timestamps with /toggle ts and toggle autoreconn
        os.write(master, b"/toggle ts\r")
        out3 = drain(master, 0.8)
        if b"setting 'ts' is now OFF" not in out3 and b"OFF" not in out3:
            print("FAIL: /toggle ts did not toggle ts to OFF", file=sys.stderr)
            return 1
        os.write(master, b"/toggle autoreconn\r")
        out3b = drain(master, 0.8)
        if b"setting 'autoreconn' is now ON" not in out3b and b"ON" not in out3b:
            print("FAIL: /toggle autoreconn did not toggle autoreconn to ON", file=sys.stderr)
            return 1

        # Test 4: Close settings buffer with /close
        os.write(master, b"/close\r")
        out4 = drain(master, 0.8)
        if b"*settings*" in out4 and b"#birc" not in out4:
            print("FAIL: /close did not leave settings buffer", file=sys.stderr)
            return 1
        # In #birc, alice's initial message is visible
        if b"hi everyone" not in out4:
            print("FAIL: initial message from alice missing in #birc", file=sys.stderr)
            return 1

        # Test 5: /mute alice (retroactively purges 'hi everyone' and adds mute)
        os.write(master, b"/mute alice\r")
        out5 = drain(master, 0.8)
        if b"muted alice" not in out5:
            print("FAIL: /mute alice did not confirm muting", file=sys.stderr)
            return 1
        if b"hi everyone" in out5:
            print("FAIL: /mute alice did not retroactively purge alice lines", file=sys.stderr)
            return 1

        # Test 6: /mutes lists active mutes
        os.write(master, b"/mutes\r")
        out6 = drain(master, 0.8)
        if b"alice#birc@irc.birc.dev" not in out6:
            print("FAIL: /mutes did not list alice#birc@irc.birc.dev", file=sys.stderr)
            return 1

        # Test 7: /unmute alice restores messages
        os.write(master, b"/unmute alice\r")
        out7 = drain(master, 0.8)
        if b"alice" not in out7:
            print("FAIL: /unmute alice did not confirm unmuting", file=sys.stderr)
            return 1
        if b"hi everyone" not in out7:
            print("FAIL: alice messages did not show up again after /unmute", file=sys.stderr)
            return 1
        os.write(master, b"/mutes\r")
        out7b = drain(master, 0.8)
        if b"no active mutes" not in out7b:
            print("FAIL: /mutes after unmute did not report 'no active mutes'", file=sys.stderr)
            return 1

        # Test 8: /query bob hello bob creates dedicated DM tab and sends message
        os.write(master, b"/query bob hello bob\r")
        out8 = drain(master, 0.8)
        if b" bob " not in out8 or b"hello bob" not in out8:
            print(f"FAIL: /query bob did not switch to bob tab or send message, got: {out8!r}", file=sys.stderr)
            return 1

        # Test 9: /close closes query tab back to #birc
        os.write(master, b"/close\r")
        out9 = drain(master, 0.8)
        if b" bob " in out9 or b"#birc" not in out9:
            print("FAIL: /close did not switch back to #birc", file=sys.stderr)
            return 1

        # Test 10: demo fixture identity is not a configured endpoint.
        os.write(master, b"/reconnect\r")
        out10 = drain(master, 0.8)
        if b"cannot reconnect: no server configured" not in out10:
            print("FAIL: demo /reconnect did not reject an unconfigured endpoint", file=sys.stderr)
            return 1
        if b"connecting" in out10:
            print("FAIL: demo /reconnect entered connecting state", file=sys.stderr)
            return 1

        # Clean exit
        os.write(master, b"/quit\r")
        proc.wait(timeout=5)
        if proc.returncode != 0:
            print(f"FAIL: exit code {proc.returncode}", file=sys.stderr)
            return 1

        print("settings=ok")
        return 0
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
