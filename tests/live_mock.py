#!/usr/bin/env python3
"""Local mock IRC: assert NICK/USER/JOIN, PONG, and birc=ok without hanging.

Headless birc quits on the first TimUI frame, so this must run under a pty
or JOIN/PONG is a race against a Tick.
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
    if len(sys.argv) < 2:
        print("usage: live_mock.py ./build/birc", file=sys.stderr)
        return 2
    birc = sys.argv[1]
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
            "20000",
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
        print("live_mock: accept timeout", file=sys.stderr)
        return 1
    conn.settimeout(0.4)
    buf = b""
    deadline = time.time() + 12
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    conn.sendall(b"PING :xyz\r\n")
    while time.time() < deadline:
        drain(master, out)
        try:
            chunk = conn.recv(4096)
            if chunk:
                buf += chunk
        except (socket.timeout, ConnectionResetError, BrokenPipeError):
            pass
        if (
            b"NICK probe" in buf
            and b"USER probe" in buf
            and b"JOIN #t" in buf
            and b"PONG :xyz" in buf
        ):
            break
        if proc.poll() is not None:
            break
    os.write(master, b"/quit\r")
    t = time.time()
    while proc.poll() is None and time.time() - t < 8:
        drain(master, out)
        try:
            chunk = conn.recv(4096)
            if chunk:
                buf += chunk
        except (socket.timeout, ConnectionResetError, BrokenPipeError, OSError):
            pass
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
        conn.close()
        srv.close()
        print("live_mock: birc hung", file=sys.stderr)
        return 1
    drain(master, out)
    conn.close()
    srv.close()
    os.close(master)
    text = out.decode("utf-8", "replace")
    if proc.returncode != 0:
        print(f"live_mock: exit {proc.returncode}\n{text}", file=sys.stderr)
        return 1
    if "birc=ok" not in text:
        print(f"live_mock: missing birc=ok\n{text}", file=sys.stderr)
        return 1
    if b"NICK probe" not in buf or b"USER probe" not in buf or b"JOIN #t" not in buf:
        print(f"live_mock: missing register in {buf!r}", file=sys.stderr)
        return 1
    if b"PONG :xyz" not in buf:
        print(f"live_mock: missing PONG in {buf!r}", file=sys.stderr)
        return 1
    print("live_mock=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
