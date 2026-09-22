#!/usr/bin/env python3
"""B3: a burst mixing text, Backspace, arrows, and Enter in one write.

(-) timui_defer_edit_ops_after_ copied only TEXT and ENTER into pending_*,
    so the post-Enter tail dropped Backspace and cursor ops. mixburst
    lines 1..199 arrived as L001X instead of L001.
(+) each line is "Lnnn" + "X" + BS + LEFT + RIGHT + Enter; the exact
    ordered PRIVMSG list arrives, then QUIT.

usage: mixburst.py ./build/birc [N]
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
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200
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
            "40000",
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
    parts = []
    for i in range(n):
        parts.append(("L%03dX" % i).encode() + b"\x7f" + b"\x1b[D" + b"\x1b[C" + b"\r")
    payload = b"".join(parts)
    fl = fcntl.fcntl(master, fcntl.F_GETFL)
    fcntl.fcntl(master, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    deadline = time.time() + max(20.0, 0.1 * n + 10)
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
        msgs = [ln for ln in text.split("\r\n") if ln.startswith("PRIVMSG #t :")]
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
    msgs = [ln for ln in text.split("\r\n") if ln.startswith("PRIVMSG #t :")]
    quits = [ln for ln in text.split("\r\n") if ln.startswith("QUIT")]
    print(
        f"n={n} privmsgs={len(msgs)} want={n} quit={len(quits)} "
        f"equal={msgs == want} exit={proc.returncode}"
    )
    if msgs != want:
        bad = [(i, a, b) for i, (a, b) in enumerate(zip(msgs, want)) if a != b][:5]
        print("first diffs:", bad)
        print("tail got:", msgs[-3:] if msgs else [])
        print("mixburst: Backspace/cursor ops dropped from the deferred tail", file=sys.stderr)
        return 1
    if len(quits) != 1 or proc.returncode != 0:
        print("mixburst: /quit ignored after burst", file=sys.stderr)
        return 1
    print("mixburst=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
