#!/usr/bin/env python3
"""M18/I13: 15 s idle and flood CPU. Not in make check.

usage: cpu_pty.py ./build/birc
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import socket
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


def run(birc: str, mode: str, secs: float, rows: int = 30, cols: int = 100) -> None:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    pid = os.fork()
    if pid == 0:
        os.setsid()
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        os.environ["TERM"] = "xterm-256color"
        os.execv(
            birc,
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
        )
    os.close(slave)
    conn, _ = srv.accept()
    conn.settimeout(0.001)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    t0 = time.time()
    sent = 0
    outbytes = 0
    while time.time() - t0 < secs:
        outbytes += drain(master)
        try:
            conn.recv(65536)
        except (socket.timeout, BlockingIOError, OSError):
            pass
        if mode == "flood":
            conn.sendall(
                (
                    ":a!a@h PRIVMSG #t :flood line %06d with some text "
                    "https://example.com/x *bold* `code`\r\n" % sent
                ).encode()
            )
            sent += 1
            time.sleep(0.01)
        else:
            time.sleep(0.02)
    os.write(master, b"/quit\r")
    t = time.time()
    ru = None
    while time.time() - t < 8:
        drain(master)
        p, _, ru = os.wait4(pid, os.WNOHANG)
        if p:
            break
        time.sleep(0.05)
    else:
        os.kill(pid, 9)
        p, _, ru = os.wait4(pid, 0)
    cpu = ru.ru_utime + ru.ru_stime
    print(
        f"{mode:5s} {rows}x{cols}: wall={secs:.0f}s cpu={cpu:.2f}s -> "
        f"{100 * cpu / secs:.1f}% of one core; lines sent={sent}; "
        f"tty bytes out={outbytes}"
    )
    os.close(master)
    conn.close()
    srv.close()


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    run(birc, "idle", 15)
    run(birc, "flood", 15)
    run(birc, "idle", 15, rows=82, cols=159)
    run(birc, "flood", 15, rows=82, cols=159)
    return 0


if __name__ == "__main__":
    sys.exit(main())
