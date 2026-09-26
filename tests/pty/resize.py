#!/usr/bin/env python3
"""Pty test verifying dynamic window resize expands and shrinks the UI properly.

Tests both grow and shrink, verifying that composer and status bar are dynamically
repositioned to the bottom rows and redraw cleanly.

usage: resize.py ./build/birc
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
        # Drain initial paint (24x80)
        init_out = drain(master, 1.0)
        if b"#birc" not in init_out:
            print("FAIL: initial screen missing #birc", file=sys.stderr)
            return 1

        # Test 1: Expand to 35 rows, 120 cols
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 35, 120, 0, 0))
        proc.send_signal(28)  # SIGWINCH
        out_expand = drain(master, 1.0)

        # In 35 rows: status is row 34, composer is row 35
        if b"\x1b[35;" not in out_expand or b"\x1b[34;" not in out_expand:
            print("FAIL: expand to 35 rows did not position UI at rows 34-35", file=sys.stderr)
            return 1

        # Test 2: Shrink to 18 rows, 60 cols
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 18, 60, 0, 0))
        proc.send_signal(28)  # SIGWINCH
        out_shrink = drain(master, 1.0)

        # In 18 rows: status is row 17, composer is row 18
        if b"\x1b[18;" not in out_shrink or b"\x1b[17;" not in out_shrink:
            print("FAIL: shrink to 18 rows did not position UI at rows 17-18", file=sys.stderr)
            return 1

        # Clean exit
        os.write(master, b"/quit\r")
        proc.wait(timeout=5)
        if proc.returncode != 0:
            print(f"FAIL: exit code {proc.returncode}", file=sys.stderr)
            return 1

        print("resize=ok")
        return 0
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
