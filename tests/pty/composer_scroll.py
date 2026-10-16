#!/usr/bin/env python3
"""Composer horizontal follow: overlong drafts scroll, cursor stays visible.

usage: composer_scroll.py ./build/birc

Demo 24x80, no server. Types a 100-char line with a unique head and tail:
- the tail stays visible (widget follows the cursor, head scrolls out),
- the hardware cursor parks at the widget's last cell (not lost past it),
- Home scrolls back (head visible again, cursor at the widget origin),
- End scrolls forward again; Escape quits cleanly.

Pins (nick "probe", prefix 8 + 9 indent = 17; demo single-pane inner
width 60, so the widget spans cols 19-61, row 22).
"""
from __future__ import annotations

import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time

CUP = re.compile(rb"\x1b\[(\d+);(\d+)H")


def drain(fd: int, seconds: float) -> bytes:
    out = bytearray()
    deadline = time.time() + seconds
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                out.extend(os.read(fd, 65536))
            except OSError:
                return bytes(out)
    return bytes(out)


def main() -> None:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    env = {**os.environ, "TERM": "xterm-256color",
           "BIRC_HISTORY": "none", "BIRC_PREFERENCES": "none"}
    proc = subprocess.Popen(
        [birc, "--demo", "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=slave, stderr=slave, env=env)
    os.close(slave)
    try:
        first = drain(master, 1.5)
        if b"\x1b[1mprobe" not in first:
            raise AssertionError("composer prefix missing from demo paint")
        head, tail = b"HEADMARK", b"TAILMARK"
        line = head + b"a" * 84 + tail
        assert len(line) == 100
        os.write(master, line)
        typed = drain(master, 0.6)
        if tail not in typed:
            raise AssertionError("overlong draft tail not visible (no follow)")
        if head in typed.split(tail)[-1][-200:]:
            raise AssertionError("overlong draft head never scrolled out")
        cups = list(CUP.finditer(typed))
        if not cups:
            raise AssertionError("no cursor address after typing")
        row, col = int(cups[-1].group(1)), int(cups[-1].group(2))
        if (row, col) != (22, 61):
            raise AssertionError(
                f"cursor not at widget end after long line: got {row};{col}H, want 22;61H")
        os.write(master, b"\x1b[H")
        homed = drain(master, 0.5)
        if head not in homed:
            raise AssertionError("Home did not scroll back to the head")
        cups = list(CUP.finditer(homed))
        if not cups or (int(cups[-1].group(1)), int(cups[-1].group(2))) != (22, 19):
            got = cups[-1].group(0) if cups else None
            raise AssertionError(
                f"cursor not at widget origin after Home: got {got}, want 22;19H")
        os.write(master, b"\x1b[F")
        ended = drain(master, 0.5)
        cups = list(CUP.finditer(ended))
        if not cups or (int(cups[-1].group(1)), int(cups[-1].group(2))) != (22, 61):
            got = cups[-1].group(0) if cups else None
            raise AssertionError(
                f"cursor not back at widget end after End: got {got}, want 22;61H")
        if tail not in ended:
            raise AssertionError("tail not visible after End")
        os.write(master, b"\x1b")
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            raise AssertionError("Escape did not quit")
        if proc.returncode != 0:
            raise AssertionError(f"exit code {proc.returncode}")
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)
    print("composer_scroll=ok", flush=True)


if __name__ == "__main__":
    main()
