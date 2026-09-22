#!/usr/bin/env python3
"""X3/M17: a 50-line paste in one write must all reach the server, in order.

(-) TimUI enter_at[32] dropped enters past 32, so a 50-line burst lost
    the tail and /quit was ignored. One-line-at-a-time paste50 hid that.
(+) one os.write of 50 lines; the exact ordered PRIVMSG list arrives.

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
    while time.time() - t < 3.0:
        drain(master, out)
        try:
            d = conn.recv(65536)
            if d and b"JOIN #t" in d:
                break
        except (socket.timeout, BlockingIOError, OSError):
            pass
        time.sleep(0.03)
    buf = bytearray()
    want = ["PRIVMSG #t :L%02d" % i for i in range(50)]
    os.write(master, b"".join(("L%02d\r" % i).encode() for i in range(50)))
    t = time.time()
    while time.time() - t < 8.0:
        drain(master, out)
        try:
            d = conn.recv(65536)
            if d:
                buf += d
        except (socket.timeout, BlockingIOError, OSError):
            pass
        text = bytes(buf).decode("utf-8", "replace")
        msgs = [ln for ln in text.split("\r\n") if ln.startswith("PRIVMSG #t :L")]
        if msgs == want:
            break
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
    quits = [ln for ln in text.split("\r\n") if ln.startswith("QUIT")]
    print(f"privmsgs={len(msgs)} want=50 quit={len(quits)} exit={proc.returncode}")
    print("got=%r" % (msgs[:5] + ["..."] + msgs[-5:] if len(msgs) > 10 else msgs,))
    ok = msgs == want and len(quits) == 1 and proc.returncode == 0
    print("RESULT:", "PASS" if ok else "FAIL")
    if msgs != want:
        print("paste50: burst paste dropped or reordered lines", file=sys.stderr)
        return 1
    if len(quits) != 1 or proc.returncode != 0:
        print("paste50: /quit ignored after burst", file=sys.stderr)
        return 1
    print("paste50=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
