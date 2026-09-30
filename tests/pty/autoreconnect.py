#!/usr/bin/env python3
"""Live connections reconnect by default on the saved host and port."""
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
    listener.listen(2)
    listener.settimeout(12)
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
    first = None
    second = None
    try:
        first, _ = listener.accept()
        first.settimeout(0.1)
        registration = recv_until(first, b"USER probe", 3.0)
        if b"NICK probe" not in registration or b"USER probe" not in registration:
            print(f"FAIL: initial registration incomplete: {registration!r}", file=sys.stderr)
            return 1
        first.sendall(b":irc.test 001 probe :Welcome\r\n")
        initial = recv_until(first, b"JOIN #t", 3.0)
        if b"JOIN #t" not in initial:
            print(f"FAIL: initial JOIN missing: {initial!r}", file=sys.stderr)
            return 1
        drain(master, 0.5)
        first.shutdown(socket.SHUT_RDWR)
        first.close()
        first = None

        try:
            second, _ = listener.accept()
        except socket.timeout:
            print("FAIL: no automatic reconnect", file=sys.stderr)
            return 1
        second.settimeout(0.1)
        registration2 = recv_until(second, b"USER probe", 3.0)
        if b"NICK probe" not in registration2 or b"USER probe" not in registration2:
            print(f"FAIL: reconnect registration incomplete: {registration2!r}", file=sys.stderr)
            return 1
        second.sendall(b":irc.test 001 probe :Welcome back\r\n")
        joined = recv_until(second, b"JOIN #t", 3.0)
        if b"JOIN #t" not in joined:
            print(f"FAIL: reconnect JOIN missing: {joined!r}", file=sys.stderr)
            return 1

        screen = drain(master, 1.0)
        if b"send failed" in screen:
            print("FAIL: reconnect logged a stale send failure", file=sys.stderr)
            return 1
        os.write(master, b"/quit\r")
        deadline = time.monotonic() + 8.0
        while proc.poll() is None and time.monotonic() < deadline:
            screen += drain(master, 0.1)
            try:
                second.recv(65536)
            except (socket.timeout, OSError):
                pass
        if proc.poll() is None:
            print(f"FAIL: /quit timed out: {screen!r}", file=sys.stderr)
            return 1
        if proc.returncode != 0:
            print(f"FAIL: exit code {proc.returncode}", file=sys.stderr)
            return 1
        print("autoreconnect=ok")
        return 0
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if first is not None:
            first.close()
        if second is not None:
            second.close()
        listener.close()
        os.close(master)


if __name__ == "__main__":
    raise SystemExit(main())
