#!/usr/bin/env python3
"""Long chat lines wrap and reflow when the terminal width changes.

usage: softwrap.py ./build/birc
"""
from __future__ import annotations

import fcntl
import os
import pty
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import time


TAIL = b"ZZZZZZZZZ"
TAIL_VISIBLE = b"ZZZ"


def plain(raw: bytes) -> bytes:
    raw = re.sub(rb"\x1b\][^\x1b]*(?:\x1b\\)", b"", raw)
    return re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", raw)


def drain(fd: int, duration: float = 0.6) -> bytes:
    out = bytearray()
    deadline = time.monotonic() + duration
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


def recv_until(conn: socket.socket, master: int, needle: bytes) -> None:
    got = bytearray()
    deadline = time.monotonic() + 4.0
    conn.setblocking(False)
    while time.monotonic() < deadline:
        drain(master, 0.05)
        ready, _, _ = select.select([conn], [], [], 0.05)
        if ready:
            chunk = conn.recv(65536)
            if not chunk:
                break
            got.extend(chunk)
        if needle in got:
            return
    raise AssertionError(f"did not receive {needle!r}; got={bytes(got)!r}")


def resize(master: int, proc: subprocess.Popen[bytes], cols: int) -> bytes:
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, cols, 0, 0))
    os.kill(proc.pid, signal.SIGWINCH)
    return drain(master, 1.0)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    srv.settimeout(10)
    port = srv.getsockname()[1]
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 50, 0, 0))
    proc = subprocess.Popen(
        [birc, "--plain", "--connect", "127.0.0.1", "--port", str(port), "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_PREFERENCES": "none", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn: socket.socket | None = None
    try:
        conn, _ = srv.accept()
        recv_until(conn, master, b"USER probe")
        conn.setblocking(True)
        conn.sendall(b":irc.example 001 probe :Welcome\r\n")
        recv_until(conn, master, b"JOIN #t\r\n")
        conn.setblocking(True)
        conn.sendall(b":probe!p@h JOIN #t\r\n")
        drain(master, 0.5)

        body = b"WRAPHEAD" + (b"x" * 80) + TAIL
        conn.sendall(b":alice!a@h PRIVMSG #t :" + body + b"\r\n")
        narrow = drain(master, 1.0)
        if TAIL_VISIBLE not in plain(narrow):
            raise AssertionError("narrow line clipped its wrapped tail")

        wide = resize(master, proc, 100)
        if TAIL_VISIBLE not in plain(wide):
            raise AssertionError("wide resize did not reflow the wrapped tail")

        narrow_again = resize(master, proc, 40)
        if TAIL_VISIBLE not in plain(narrow_again):
            raise AssertionError("second narrow resize did not reflow the wrapped tail")

        os.write(master, b"/quit\r")
        proc.wait(timeout=8)
        if proc.returncode != 0:
            raise AssertionError(f"client exited with {proc.returncode}")
        print("softwrap=ok")
        return 0
    finally:
        if conn is not None:
            conn.close()
        srv.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
