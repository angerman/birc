#!/usr/bin/env python3
"""P1: after 3 s idle, an incoming line is painted within 100 ms.

The UI polls the socket fd as a wake hint; it never reads the socket.

Documented target: <= 100 ms. The pass criterion is the minimum of up to
three trials in one run, so a load spike cannot fail the gate. A 1 s idle
poll on the paint path exceeds 100 ms on every trial.

usage: paint_wake.py ./build/birc
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import socket
import struct
import subprocess
import sys
import termios
import time

MARKER = b"WAKESECRET99"
BOUND_MS = 100.0
TRIALS = 3


def drain(fd: int, sink: bytearray) -> None:
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
        sink += d


def trial(birc: str) -> tuple[bool, float | None]:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [
            birc,
            "--connect",
            "127.0.0.1",
            "--port",
            str(port),
            "--nick",
            "probe",
            "--channel",
            "#t",
            "--frames",
            "0",
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    out = bytearray()
    try:
        conn, _ = srv.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
        end = time.time() + 4.0
        while time.time() < end and proc.poll() is None:
            drain(master, out)
            if b"online" in bytes(out):
                break
            time.sleep(0.05)
        t_idle = time.time() + 3.0
        while time.time() < t_idle and proc.poll() is None:
            drain(master, out)
            time.sleep(0.05)
        drain(master, out)
        t_send = time.time()
        conn.sendall(b":a!a@h PRIVMSG #t :" + MARKER + b"\r\n")
        painted = False
        t_see = None
        deadline = t_send + 1.5
        while time.time() < deadline and proc.poll() is None:
            drain(master, out)
            if MARKER in bytes(out):
                t_see = time.time()
                painted = True
                break
            time.sleep(0.005)
        ms = None if t_see is None else (t_see - t_send) * 1000.0
        os.write(master, b"/quit\r")
        end = time.time() + 2.0
        while time.time() < end and proc.poll() is None:
            drain(master, out)
            time.sleep(0.05)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        conn.close()
        return painted, ms
    finally:
        try:
            srv.close()
        except OSError:
            pass
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        try:
            os.close(master)
        except OSError:
            pass


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    times: list[float] = []
    for i in range(TRIALS):
        painted, ms = trial(birc)
        print(f"trial {i + 1}/{TRIALS}: painted={painted} ms={ms}")
        if not painted or ms is None:
            print("FAIL marker not painted", file=sys.stderr)
            return 1
        times.append(ms)
        if min(times) <= BOUND_MS:
            break
    best = min(times)
    print(f"trials_ms={times} min={best:.1f} bound={BOUND_MS}")
    if best > BOUND_MS:
        print(f"FAIL paint min {best:.1f} ms > {BOUND_MS:.0f}", file=sys.stderr)
        return 1
    print("paint_wake=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
