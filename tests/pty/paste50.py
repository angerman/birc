#!/usr/bin/env python3
"""M17: a 50-line paste must all reach the server (cap 8 per actor tick).

(-) send_lines flushed the whole Cont in one tick with no leftover.
(+) reader carries pending; all 50 PRIVMSGs arrive.

usage: paste50.py ./build/birc
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
    conn, _ = srv.accept()
    conn.settimeout(0.05)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    t = time.time()
    while time.time() - t < 1.2:
        drain(master, out)
        try:
            conn.recv(65536)
        except (socket.timeout, BlockingIOError, OSError):
            pass
        time.sleep(0.03)
    buf = bytearray()
    for i in range(50):
        os.write(master, ("L%02d\r" % i).encode())
        t = time.time()
        while time.time() - t < 0.15:
            drain(master, out)
            try:
                d = conn.recv(65536)
                if d:
                    buf += d
            except (socket.timeout, BlockingIOError, OSError):
                pass
            time.sleep(0.02)
    os.write(master, b"/quit\r")
    t = time.time()
    while proc.poll() is None and time.time() - t < 8:
        drain(master, out)
        try:
            d = conn.recv(65536)
            if d:
                buf += d
        except (socket.timeout, BlockingIOError, OSError):
            pass
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    text = bytes(buf).decode("utf-8", "replace")
    msgs = [ln for ln in text.split("\r\n") if ln.startswith("PRIVMSG #t :L")]
    print(f"privmsgs={len(msgs)} want=50 exit={proc.returncode}")
    ok = len(msgs) == 50
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("paste50: outbound cap dropped lines", file=sys.stderr)
        return 1
    print("paste50=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
