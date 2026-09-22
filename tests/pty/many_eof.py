#!/usr/bin/env python3
"""After disconnect, a one-write line+Enter must submit (idle poll).

(-) HOT_WINDOW=50 ms: UI idles 1000 ms. Text+CR in one os.write after RST
    was intermittently not submitted (composer kept /connect; 3/8..6/8).
    Split Enter 300 ms later was 36/36. 2 s hot window was 8/8.
(+) 12 disconnect cycles, mixed FIN/RST, one write of "/connect host port\\r"
    each time; every cycle accepts, then /quit.

usage: many_eof.py ./build/birc
"""
from __future__ import annotations

import fcntl
import os
import pty
import re
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
    n = 12
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(4)
    port = srv.getsockname()[1]
    srv.settimeout(0.05)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [birc, "--demo", "--frames", "60000"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    out = bytearray()
    t = time.time()
    while time.time() - t < 1.5:
        drain(master, out)
        time.sleep(0.02)
    if proc.poll() is not None:
        print("many_eof: birc exited before start", proc.returncode, file=sys.stderr)
        return 1
    cycles = 0
    for i in range(n):
        os.write(master, b"/connect 127.0.0.1 %d\r" % port)
        conn = None
        end = time.time() + 6
        while time.time() < end and conn is None:
            drain(master, out)
            try:
                conn, _ = srv.accept()
            except (socket.timeout, OSError):
                pass
        if conn is None:
            plain = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]", b" ", bytes(out[-1500:])).decode(
                "utf-8", "replace"
            )
            print(
                f"cycle {i}: no accept; /connect on screen "
                f"{plain.count('/connect 127.0.0.1')}x; tail={plain[-160:]!r}",
                file=sys.stderr,
            )
            break
        conn.settimeout(0.01)
        got = b""
        end = time.time() + 3
        while time.time() < end and b"USER" not in got:
            drain(master, out)
            try:
                got += conn.recv(4096)
            except Exception:
                pass
        conn.sendall(b":irc.example.net 001 probe :hi\r\n")
        t = time.time()
        while time.time() - t < 0.25:
            drain(master, out)
            time.sleep(0.02)
        if i % 2 == 0:
            try:
                while conn.recv(4096):
                    pass
            except Exception:
                pass
            conn.shutdown(socket.SHUT_RDWR)
        else:
            conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        conn.close()
        cycles += 1
        t = time.time()
        while time.time() - t < 2.0:
            drain(master, out)
            time.sleep(0.02)
        if b"[?1049l" in out or proc.poll() is not None:
            break
    alive = proc.poll() is None and b"[?1049l" not in out
    mark = len(out)
    os.write(master, b"zq")
    t = time.time()
    while time.time() - t < 0.8:
        drain(master, out)
        time.sleep(0.02)
    reacts = alive and b"z" in out[mark:]
    os.write(master, b"\x7f\x7f/quit\r")
    t = time.time()
    while proc.poll() is None and time.time() - t < 10:
        drain(master, out)
        time.sleep(0.05)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    print(
        f"cycles={cycles}/{n} ui_alive={alive} reacts={reacts} "
        f"exit={proc.returncode} hung_on_quit={hung}"
    )
    if cycles != n or not alive or hung or proc.returncode != 0:
        print("many_eof: one-write /connect after idle disconnect failed", file=sys.stderr)
        return 1
    print("many_eof=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
