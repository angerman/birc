#!/usr/bin/env python3
"""Note 19: a late Eof from the old server must not drop the new one.

(-) /connect while online shuts the old socket down. That reader's Eof
    can arrive after the new Up. Treating it as "disconnected" drops the
    new connection.
(+) connected to A, one-write /connect to B, A stays open for 1 s then
    closes. The client sends JOIN #t to B and, after A closes, answers
    B's PING with PONG.

usage: gen_eof.py ./build/birc
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


def drain(fd, sink) -> None:
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


def pump(master, out, conns, secs) -> None:
    end = time.time() + secs
    while time.time() < end:
        drain(master, out)
        for c in conns:
            if c is None:
                continue
            try:
                c.recv(65536)
            except (socket.timeout, BlockingIOError, OSError):
                pass
        time.sleep(0.02)


def wait_for(master, out, conn, needle: bytes, secs: float) -> bytearray:
    got = bytearray()
    end = time.time() + secs
    while time.time() < end:
        drain(master, out)
        try:
            d = conn.recv(65536)
            if d:
                got += d
        except (socket.timeout, BlockingIOError, OSError):
            pass
        if needle in got:
            return got
        time.sleep(0.01)
    return got


def trial(birc: str) -> tuple[bool, str]:
    a = socket.socket()
    b = socket.socket()
    a.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    b.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    a.bind(("127.0.0.1", 0))
    b.bind(("127.0.0.1", 0))
    a.listen(1)
    b.listen(1)
    pa = a.getsockname()[1]
    pb = b.getsockname()[1]
    a.settimeout(20)
    b.settimeout(20)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [
            birc,
            "--connect",
            "127.0.0.1",
            "--port",
            str(pa),
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
    ca = None
    cb = None
    try:
        try:
            ca, _ = a.accept()
        except socket.timeout:
            return False, "accept A timeout"
        ca.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        ca.settimeout(0.05)
        ca.sendall(b":irc.example.net 001 probe :Welcome\r\n")
        got_a = wait_for(master, out, ca, b"JOIN #t", 3.0)
        if b"JOIN #t" not in got_a:
            return False, f"no JOIN on A {got_a!r}"
        os.write(master, b"/connect 127.0.0.1 %d\r" % pb)
        t_switch = time.time()
        try:
            cb, _ = b.accept()
        except socket.timeout:
            return False, "accept B timeout"
        cb.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        cb.settimeout(0.05)
        cb.sendall(b":irc.example.net 001 probe :Welcome\r\n")
        got_b = wait_for(master, out, cb, b"JOIN #t", 3.0)
        if b"JOIN #t" not in got_b:
            return False, f"no JOIN on B {got_b!r}"
        left = 1.0 - (time.time() - t_switch)
        if left > 0:
            pump(master, out, [ca, cb], left)
        try:
            ca.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        ca.close()
        ca = None
        cb.sendall(b"PING :late\r\n")
        got_p = wait_for(master, out, cb, b"PONG :late", 2.0)
        if b"PONG :late" not in got_p:
            return False, f"no PONG after A closed {got_p!r}"
        os.write(master, b"/quit\r")
        t = time.time()
        while proc.poll() is None and time.time() - t < 8:
            drain(master, out)
            time.sleep(0.05)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
            return False, "quit hung"
        return True, "ok"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        for c in (ca, cb):
            if c is not None:
                try:
                    c.close()
                except OSError:
                    pass
        try:
            os.close(master)
        except OSError:
            pass
        a.close()
        b.close()


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    ok, msg = trial(birc)
    print(f"gen_eof: {msg}")
    if not ok:
        print(f"gen_eof: {msg}", file=sys.stderr)
        return 1
    print("gen_eof=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
