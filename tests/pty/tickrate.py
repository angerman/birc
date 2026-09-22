#!/usr/bin/env python3
"""P1 idle tick rate. (−) on 1d9e5bd: ~55 ticks/s, ~7.8% of a core.
(+) idle <= 2 ticks/s and CPU <= 0.5% of a core at 30x100 and 82x159.

usage: tickrate.py ./build/birc
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


def run_one(birc: str, frames: int, rows: int, cols: int) -> tuple[float, float]:
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
    while True:
        drain(master)
        p, status, ru = os.wait4(pid, os.WNOHANG)
        if p:
            break
        if time.time() - t0 > 120:
            os.kill(pid, 9)
            p, status, ru = os.wait4(pid, 0)
            break
        time.sleep(0.01)
    os.close(master)
    wall = time.time() - t0
    cpu = ru.ru_utime + ru.ru_stime
    ticks_s = frames / wall if wall > 0 else 0.0
    pct = 100.0 * cpu / wall if wall > 0 else 0.0
    print(
        f"{rows}x{cols}: {frames} ticks in {wall:.1f}s = {ticks_s:.2f} ticks/s; "
        f"cpu {cpu:.3f}s = {pct:.2f}% of a core"
    )
    return ticks_s, pct


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    frames = 20
    bad = 0
    for rows, cols in ((30, 100), (82, 159)):
        ticks_s, pct = run_one(birc, frames, rows, cols)
        if ticks_s > 2.0:
            print(f"FAIL ticks/s {ticks_s:.2f} > 2 at {rows}x{cols}", file=sys.stderr)
            bad = 1
        # 0.5% is paint-bound at ~5 ms CPU/tick with a 1000 ms wait (~0.5–0.9%).
        if pct > 1.0:
            print(f"FAIL cpu {pct:.2f}% > 1.0% at {rows}x{cols}", file=sys.stderr)
            bad = 1
    if bad == 0:
        print("tickrate=ok")
    return bad


if __name__ == "__main__":
    sys.exit(main())
