#!/usr/bin/env python3
"""Pty test verifying in-app mouse text selection and Escape dismissal.

Tests:
1. Mouse drag in body pane sets active selection with reverse video attribute (\\x1b[7m).
2. Pressing Escape dismisses selection without quitting birc.
3. Subsequent /quit exits cleanly.

usage: mouse_select.py ./build/birc
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
from pathlib import Path


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
        env={**os.environ, "TERM": "xterm-256color",
             "PATH": str(Path(__file__).resolve().parent / "fake-bin")},
    )
    os.close(slave)

    try:
        # Drain initial paint
        init_out = drain(master, 1.0)
        if b"#birc" not in init_out:
            print("FAIL: initial screen missing #birc", file=sys.stderr)
            return 1

        # Simulate mouse drag in body pane:
        # 1-based SGR coordinates:
        # Press at col 5, row 5
        os.write(master, b"\x1b[<0;5;5M")
        time.sleep(0.05)
        # Drag to col 15, row 5
        os.write(master, b"\x1b[<32;15;5M")
        time.sleep(0.05)
        # Release at col 15, row 5
        os.write(master, b"\x1b[<0;15;5m")

        drag_out = drain(master, 0.5)
        # Reverse video SGR code \x1b[7m must be emitted for selected text
        if b"\x1b[7m" not in drag_out:
            print("FAIL: expected reverse video attribute \\x1b[7m in drag output", file=sys.stderr)
            return 1

        # Press Escape once to dismiss selection
        os.write(master, b"\x1b")
        esc_out = drain(master, 0.5)

        # Ensure birc is still running (Escape dismissed selection instead of quitting)
        if proc.poll() is not None:
            print(f"FAIL: birc quit prematurely on first Escape (exit {proc.returncode})", file=sys.stderr)
            return 1

        # Clean quit
        os.write(master, b"/quit\r")
        proc.wait(timeout=5)
        if proc.returncode != 0:
            print(f"FAIL: exit code {proc.returncode}", file=sys.stderr)
            return 1

        print("mouse_select=ok")
        return 0
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
