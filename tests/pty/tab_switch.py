#!/usr/bin/env python3
"""Pty test verifying tab switching via Shift-Left/Right and mouse click works on the first press/click.

Prior to fix, on_key painted before reading input without a follow-up redraw,
requiring two key presses or two mouse clicks to observe channel switches.

usage: tab_switch.py ./build/birc
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
        [birc, "--demo", "--frames", "0"],
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

        # Test 1: Shift-Right ONCE must switch to server buffer
        os.write(master, b"\x1b[1;2C")
        out1 = drain(master, 0.5)
        if b"Welcome to the birc IRC Network me" not in out1:
            print("FAIL: 1st Shift-Right did not switch to server buffer", file=sys.stderr)
            return 1

        # Test 2: Shift-Left ONCE must switch back to #birc
        os.write(master, b"\x1b[1;2D")
        out2 = drain(master, 0.5)
        if b"alice" not in out2:
            print("FAIL: 1st Shift-Left did not switch back to #birc", file=sys.stderr)
            return 1

        # Test 3: Mouse click on *server* tab (col 5, row 2) ONCE
        os.write(master, b"\x1b[<0;5;2M\x1b[<0;5;2m")
        out3 = drain(master, 0.5)
        if b"Welcome to the birc IRC Network me" not in out3:
            print("FAIL: 1st mouse click did not switch to server buffer", file=sys.stderr)
            return 1

        # Test 4: Mouse click on #birc tab (col 15, row 2) ONCE
        os.write(master, b"\x1b[<0;15;2M\x1b[<0;15;2m")
        out4 = drain(master, 0.5)
        if b"alice" not in out4:
            print("FAIL: 1st mouse click did not switch back to #birc", file=sys.stderr)
            return 1

        # Clean exit
        os.write(master, b"/quit\r")
        proc.wait(timeout=5)
        if proc.returncode != 0:
            print(f"FAIL: exit code {proc.returncode}", file=sys.stderr)
            return 1

        print("tab_switch=ok")
        return 0
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
