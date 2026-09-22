#!/usr/bin/env python3
"""P1 handshake: 001 to JOIN must be under 100 ms on the first connection.

Actor events (Up/Chunk) used to sit in the evt channel while the UI polled
1000 ms, so 001 → JOIN was ~1 s. Keep the UI at 16 ms while Connecting and
for ~2 s after actor events.

usage: join_latency.py ./build/birc
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


def drain(fd, sink):
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


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
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
            "60000",
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    out = bytearray()
    conn, _ = srv.accept()
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    conn.settimeout(0.005)
    got = bytearray()

    def pump(secs, stop=None):
        end = time.time() + secs
        while time.time() < end:
            drain(master, out)
            try:
                got.extend(conn.recv(65536))
            except Exception:
                pass
            if stop and stop in got:
                return True
            time.sleep(0.005)
        return False

    pump(1.5)
    t0 = time.time()
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    ok = pump(2.0, b"JOIN #t")
    ms = (time.time() - t0) * 1000.0
    os.write(master, b"/quit\r")
    t = time.time()
    while proc.poll() is None and time.time() - t < 8:
        drain(master, out)
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    print(f"001_to_JOIN_ms={ms:.1f} found={ok} exit={proc.returncode}")
    if not ok or ms > 100.0:
        print(f"join_latency: 001 to JOIN {ms:.1f} ms (want <= 100)", file=sys.stderr)
        return 1
    print("join_latency=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
