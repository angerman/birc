#!/usr/bin/env python3
"""Reconnect-off disconnects release the writer before the next heartbeat."""
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


def recv_until(conn: socket.socket, needle: bytes, timeout: float) -> bytes:
    out = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            chunk = conn.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        out.extend(chunk)
        if needle in out:
            break
    return bytes(out)


def drain(fd: int, timeout: float) -> bytes:
    out = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out.extend(chunk)
    return bytes(out)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(10)
    port = listener.getsockname()[1]

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
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
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": ""},
    )
    os.close(slave)
    conn = None
    try:
        conn, _ = listener.accept()
        conn.settimeout(0.1)
        registration = recv_until(conn, b"USER probe", 3.0)
        if b"NICK probe" not in registration:
            print(f"FAIL: registration missing: {registration!r}", file=sys.stderr)
            return 1
        conn.sendall(b":irc.test 001 probe :Welcome\r\n")
        if b"JOIN #t" not in recv_until(conn, b"JOIN #t", 3.0):
            print("FAIL: JOIN missing", file=sys.stderr)
            return 1
        drain(master, 0.5)
        os.write(master, b"/set autoreconn off\r")
        setting = drain(master, 0.8)
        if b"autoreconn' is now OFF" not in setting:
            print(f"FAIL: could not disable reconnect: {setting!r}", file=sys.stderr)
            return 1

        conn.shutdown(socket.SHUT_RDWR)
        conn.close()
        conn = None
        screen = drain(master, 6.0)
        if b"disconnected" not in screen:
            print("FAIL: disconnect was not shown", file=sys.stderr)
            return 1
        if b"send failed" in screen:
            print("FAIL: heartbeat wrote to the released socket", file=sys.stderr)
            return 1

        os.write(master, b"/quit\r")
        deadline = time.monotonic() + 8.0
        while proc.poll() is None and time.monotonic() < deadline:
            drain(master, 0.1)
        if proc.poll() is None:
            print("FAIL: /quit timed out", file=sys.stderr)
            return 1
        if proc.returncode != 0:
            print(f"FAIL: exit code {proc.returncode}", file=sys.stderr)
            return 1
        print("disconnect_cleanup=ok")
        return 0
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        listener.close()
        os.close(master)


if __name__ == "__main__":
    raise SystemExit(main())
