#!/usr/bin/env python3
"""A1: a partial line then Eof must not glue onto the next connection.

(-) rem/drop survive session_fail and /connect, so 001 is not a numeric
    and JOIN is never sent.
(+) after /connect, 001 yields JOIN #t.

usage: redial.py ./build/birc
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


def pump(master, out, conn, secs):
    end = time.time() + secs
    while time.time() < end:
        drain(master, out)
        if conn is not None:
            try:
                conn.recv(65536)
            except (socket.timeout, BlockingIOError, OSError):
                pass
        time.sleep(0.02)


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
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        proc.kill()
        print("redial: first accept timeout", file=sys.stderr)
        return 1
    conn.settimeout(0.05)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    pump(master, out, conn, 1.0)
    conn.sendall(b":a!a@h PRIVMSG #t :partial")  # no CRLF: remainder
    pump(master, out, conn, 0.4)
    try:
        conn.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    conn.close()
    pump(master, out, None, 1.2)
    os.write(master, b"/connect 127.0.0.1 %d\r" % port)
    try:
        conn2, _ = srv.accept()
    except socket.timeout:
        proc.kill()
        print("redial: second accept timeout", file=sys.stderr)
        return 1
    conn2.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    conn2.settimeout(0.05)
    pump(master, out, conn2, 0.8)
    conn2.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    got = bytearray()
    t001 = time.time()
    t_join = None
    end = t001 + 1.5
    while time.time() < end:
        drain(master, out)
        try:
            got += conn2.recv(65536)
        except (socket.timeout, BlockingIOError, OSError):
            pass
        if b"JOIN #t" in got:
            t_join = time.time()
            break
        time.sleep(0.005)
    os.write(master, b"/quit\r")
    t = time.time()
    while proc.poll() is None and time.time() - t < 8:
        drain(master, out)
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    try:
        conn2.close()
    except OSError:
        pass
    os.close(master)
    srv.close()
    joined = b"JOIN #t" in got
    ms = None if t_join is None else (t_join - t001) * 1000.0
    print(f"redial JOIN after 001: {joined} ms={ms} recv={got!r}")
    if not joined or ms is None:
        print("redial: no JOIN after reconnect 001", file=sys.stderr)
        return 1
    if ms > 100.0:
        print(f"redial: 001 to JOIN {ms:.1f} ms (want <= 100)", file=sys.stderr)
        return 1
    print("redial=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
