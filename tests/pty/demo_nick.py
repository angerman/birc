#!/usr/bin/env python3
"""H5: --demo --nick bob /connect must register as bob, not me.

usage: demo_nick.py ./build/birc
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


def drain(fd):
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            return
        try:
            if not os.read(fd, 65536):
                return
        except OSError:
            return


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(15)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [birc, "--demo", "--nick", "bob", "--channel", "#t", "--frames", "20000"],
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    end = time.time() + 2
    while time.time() < end:
        drain(master)
        time.sleep(0.05)
    os.write(master, f"/connect 127.0.0.1 {port}\r".encode())
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        proc.kill()
        print("demo_nick: accept timeout", file=sys.stderr)
        return 1
    conn.settimeout(5)
    buf = bytearray()
    try:
        while True:
            d = conn.recv(4096)
            if not d:
                break
            buf += d
            if b"USER" in buf:
                break
    except (socket.timeout, OSError):
        pass
    os.write(master, b"/quit\r")
    end = time.time() + 8
    while time.time() < end and proc.poll() is None:
        drain(master)
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    text = bytes(buf).decode("utf-8", "replace")
    print(f"register={text!r}")
    ok = "NICK bob" in text
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("demo_nick: expected NICK bob (H5; bug sent NICK me)", file=sys.stderr)
        return 1
    print("demo_nick=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
