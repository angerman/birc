#!/usr/bin/env python3
"""600-frame idle tickrate (M18 baseline). Not in make check.

P1 gate is tests/pty/tickrate.py (20 frames, <= 2 ticks/s).

usage: tickrate_pty.py ./build/birc [frames] [rows] [cols]
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time


def drain(fd: int) -> int:
    n = 0
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            return n
        try:
            d = os.read(fd, 65536)
        except OSError:
            return n
        if not d:
            return n
        n += len(d)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 600
    rows = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    cols = int(sys.argv[4]) if len(sys.argv) > 4 else 100
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    t0 = time.time()
    pid = os.fork()
    if pid == 0:
        os.setsid()
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        os.environ["TERM"] = "xterm-256color"
        os.execv(birc, [birc, "--demo", "--frames", str(frames)])
    os.close(slave)
    out = 0
    while True:
        out += drain(master)
        p, _, ru = os.wait4(pid, os.WNOHANG)
        if p:
            break
        if time.time() - t0 > 120:
            os.kill(pid, 9)
            p, _, ru = os.wait4(pid, 0)
            break
        time.sleep(0.01)
    os.close(master)
    wall = time.time() - t0
    cpu = ru.ru_utime + ru.ru_stime
    print(
        f"{rows}x{cols}: {frames} ticks in {wall:.1f}s = {frames / wall:.0f} ticks/s; "
        f"cpu {cpu:.2f}s = {100 * cpu / wall:.1f}% of a core; "
        f"{1000 * cpu / frames:.2f} ms cpu per tick "
        f"(user {1000 * ru.ru_utime / frames:.2f} + sys {1000 * ru.ru_stime / frames:.2f}); "
        f"tty bytes/tick {out / frames:.0f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
