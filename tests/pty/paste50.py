#!/usr/bin/env python3
"""X3: a burst paste of N lines in one write must all reach the server, in order.

(-) enter_at overflow merged extra Enters into one line and /quit was ignored
    (50 with a 32-slot table, 100 with a 64-slot table).
(+) one os.write of N lines; the exact ordered PRIVMSG list arrives, then QUIT.

usage: paste50.py ./build/birc [N]
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
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 50
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
    want = ["PRIVMSG #t :L%03d" % i for i in range(n)]
    payload = b"".join(("L%03d\r" % i).encode() for i in range(n))
    # One logical write; drain the slave while feeding the master so a
    # 300-line paint cannot fill the pty and deadlock os.write.
    fl = fcntl.fcntl(master, fcntl.F_GETFL)
    fcntl.fcntl(master, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    deadline = time.time() + max(8.0, 0.05 * n + 5.0)
    off = 0
    while time.time() < deadline:
        drain(master, out)
        if off < len(payload):
            try:
                off += os.write(master, payload[off:])
            except BlockingIOError:
                pass
        try:
            d = conn.recv(65536)
            if d:
                buf += d
        except (socket.timeout, BlockingIOError, OSError):
            pass
        text = bytes(buf).decode("utf-8", "replace")
        msgs = [ln for ln in text.split("\r\n") if ln.startswith("PRIVMSG #t :L")]
        if off >= len(payload) and msgs == want:
            break
        time.sleep(0.02)
    sent_quit = False
    t = time.time()
    while proc.poll() is None and time.time() - t < 8:
        drain(master, out)
        if not sent_quit:
            try:
                os.write(master, b"/quit\r")
                sent_quit = True
            except BlockingIOError:
                pass
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
    print(
        f"n={n} privmsgs={len(msgs)} want={n} quit={len(quits)} "
        f"exit={proc.returncode}"
    )
    print("got=%r" % (msgs[:5] + ["..."] + msgs[-5:] if len(msgs) > 10 else msgs,))
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
