#!/usr/bin/env python3
"""K2 idle CPU of a parked demo.

(-) a frame loop with no wait burns a core (~100%).
(+) --demo on a tty, no input, frames=0: CPU <= 1.0% of a core.
    One startup paint is allowed. A 2 s sample at 30x100 and 82x159.

usage: tickrate.py ./build/birc
"""
from __future__ import annotations

import ctypes
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

WARM_S = 0.5
SAMPLE_S = 3.0
CPU_CAP = 1.0


class _RUsage(ctypes.Structure):
    _fields_ = [
        ("uuid", ctypes.c_uint8 * 16),
        ("user_ns", ctypes.c_uint64),
        ("sys_ns", ctypes.c_uint64),
        ("idle_wk", ctypes.c_uint64),
        ("intr_wk", ctypes.c_uint64),
        ("pageins", ctypes.c_uint64),
        ("wired", ctypes.c_uint64),
        ("resident", ctypes.c_uint64),
        ("foot", ctypes.c_uint64),
        ("start", ctypes.c_uint64),
        ("exit", ctypes.c_uint64),
    ]


def cpu_ns(pid: int) -> int:
    buf = _RUsage()
    lib = ctypes.CDLL("/usr/lib/libproc.dylib")
    lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(_RUsage)]
    lib.proc_pid_rusage.restype = ctypes.c_int
    if lib.proc_pid_rusage(pid, 0, ctypes.byref(buf)) != 0:
        return -1
    return int(buf.user_ns + buf.sys_ns)


def drain(fd: int) -> None:
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            return
        try:
            d = os.read(fd, 65536)
        except OSError:
            return
        if not d:
            return


def run_one(birc: str, rows: int, cols: int) -> tuple[float, bool]:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    pid = os.fork()
    if pid == 0:
        os.setsid()
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        os.close(master)
        os.close(slave)
        os.environ["TERM"] = "xterm-256color"
        os.execv(birc, [birc, "--demo", "--frames", "0"])
    os.close(slave)
    t_end = time.time() + WARM_S
    exited = False
    while time.time() < t_end:
        drain(master)
        p, _, _ = os.wait4(pid, os.WNOHANG)
        if p:
            exited = True
            break
        time.sleep(0.05)
    c0 = cpu_ns(pid) if not exited else 0
    t0 = time.time()
    if not exited:
        t_end = t0 + SAMPLE_S
        while time.time() < t_end:
            drain(master)
            p, _, _ = os.wait4(pid, os.WNOHANG)
            if p:
                exited = True
                break
            time.sleep(0.05)
    c1 = cpu_ns(pid) if not exited else c0
    if not exited:
        os.kill(pid, signal.SIGKILL)
        os.wait4(pid, 0)
    os.close(master)
    wall = time.time() - t0
    cpu = max(0, c1 - c0) / 1e9
    pct = 100.0 * cpu / wall if wall > 0 else 0.0
    print(
        f"{rows}x{cols}: parked {wall:.1f}s after warm-up, cpu {cpu:.3f}s "
        f"= {pct:.2f}% of a core exited={exited}"
    )
    return pct, exited


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    bad = 0
    for rows, cols in ((30, 100), (82, 159)):
        pct, exited = run_one(birc, rows, cols)
        if exited:
            print(f"FAIL demo exited while idle at {rows}x{cols}", file=sys.stderr)
            bad = 1
        if pct > CPU_CAP:
            print(f"FAIL cpu {pct:.2f}% > {CPU_CAP:.1f}% at {rows}x{cols}", file=sys.stderr)
            bad = 1
    if bad:
        return 1
    print("tickrate=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
