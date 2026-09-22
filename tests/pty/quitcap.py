#!/usr/bin/env python3
"""X2: a burst of PINGs fills pending; /quit must still send QUIT.

(-) on_cmd appended QUIT after leftover; shutdown closed cmd without
    flushing pending. 40 PINGs -> 8 PONGs (SEND_CAP) and quit=0.
(+) cmd close and fuel-0 flush pending, so all PONGs and QUIT reach the wire.

usage: quitcap.py ./build/birc [npings]
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
    npings = int(sys.argv[2]) if len(sys.argv) > 2 else 40
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
    buf = bytearray()
    t = time.time()
    while time.time() - t < 3.0:
        drain(master, out)
        try:
            d = conn.recv(65536)
            if d:
                buf += d
        except (socket.timeout, BlockingIOError, OSError):
            pass
        if b"JOIN #t" in buf:
            break
        time.sleep(0.03)
    buf.clear()
    conn.sendall(b"".join(b"PING :p%03d\r\n" % i for i in range(npings)))
    t = time.time()
    while time.time() - t < 2.0:
        drain(master, out)
        try:
            d = conn.recv(65536)
            if d:
                buf += d
        except (socket.timeout, BlockingIOError, OSError):
            pass
        if bytes(buf).count(b"PONG") >= 8:
            break
        time.sleep(0.01)
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
        time.sleep(0.02)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    txt = bytes(buf).decode("utf-8", "replace")
    lines = [l for l in txt.split("\r\n") if l]
    pongs = [l for l in lines if l.startswith("PONG")]
    quits = [l for l in lines if l.startswith("QUIT")]
    print(
        "npings=%d pongs=%d quit=%d exit=%s"
        % (npings, len(pongs), len(quits), proc.returncode)
    )
    print("last5=%r" % (lines[-5:],))
    if len(pongs) != npings or len(quits) != 1:
        print("quitcap: expected all PONGs and one QUIT", file=sys.stderr)
        return 1
    print("quitcap=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
