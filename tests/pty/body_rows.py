#!/usr/bin/env python3
"""Pty body-rows: the newest PRIVMSG must be painted.

Bend packed rows-4 lines; C drew rows-6 and kept the oldest, so the
newest two lines never appeared. Window is 16 rows.

usage: body_rows.py ./build/birc [FRAMES=0]
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


def drain(fd: int, sink: bytearray) -> None:
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            return
        try:
            data = os.read(fd, 65536)
        except OSError:
            return
        if not data:
            return
        sink += data


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    frames = sys.argv[2] if len(sys.argv) > 2 else "0"
    n = 20
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 16, 100, 0, 0))
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
            frames,
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
        print("body_rows: accept timeout", file=sys.stderr)
        return 1
    conn.settimeout(0.005)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    time.sleep(0.2)
    for i in range(n):
        drain(master, out)
        if proc.poll() is not None:
            break
        try:
            conn.sendall(b":a!a@h PRIVMSG #t :%s\r\n" % (bytes([97 + (i % 26)]) * 6))
        except (BrokenPipeError, ConnectionResetError):
            break
        try:
            conn.recv(4096)
        except (socket.timeout, ConnectionResetError, BrokenPipeError):
            pass
        time.sleep(0.03)
    try:
        conn.close()
    except OSError:
        pass
    if proc.poll() is None:
        os.write(master, b"/quit\r")
    deadline = time.time() + 20
    while proc.poll() is None and time.time() < deadline:
        drain(master, out)
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    drain(master, out)
    os.close(master)
    srv.close()
    text = out.decode("utf-8", "replace")
    newest = bytes([97 + ((n - 1) % 26)]) * 6
    newest_s = newest.decode("ascii")
    painted = newest_s in text
    print(f"newest={newest_s} painted={painted} birc_ok={'birc=ok' in text}")
    if not painted:
        print("body_rows: newest line never painted", file=sys.stderr)
        return 1
    print("body_rows=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
