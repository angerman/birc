#!/usr/bin/env python3
"""Pty: on a tall terminal, is the newest body line painted?

C used to collect BodyLn into Term lns[64] and keep the oldest 64, so a
90-row pty with 120 unique lines dropped the newest (C3 again). Bend now
assigns each body line its y; C paints as it walks.

usage: tall_rows.py ./build/birc ROWS NLINES

Sends NLINES numbered lines, then looks only at output after the last
line (that write forces a full body repaint). Fails if the newest token
is missing.
"""
from __future__ import annotations

import fcntl
import os
import pty
import re
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


def pump(master: int, out: bytearray, conn: socket.socket, secs: float) -> None:
    end = time.time() + secs
    while time.time() < end:
        drain(master, out)
        try:
            conn.recv(65536)
        except (socket.timeout, BlockingIOError, OSError):
            pass
        time.sleep(0.02)


def tok(i: int) -> str:
    # every cell differs from tok(i-1); unique within any 26 consecutive i
    a, b = i % 26, (i // 26) % 26
    ks = ((1, 1), (3, 2), (5, 3), (7, 5), (9, 7), (11, 9))
    return "".join(chr(97 + (a * k + b * m + j) % 26) for j, (k, m) in enumerate(ks))


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: tall_rows.py ./build/birc ROWS NLINES", file=sys.stderr)
        return 2
    birc, rows, nlines = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, 100, 0, 0))
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
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    out = bytearray()
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        proc.kill()
        print("tall_rows: accept timeout", file=sys.stderr)
        return 1
    conn.settimeout(0.01)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    pump(master, out, conn, 1.0)
    for i in range(nlines - 1):
        conn.sendall(b":a!a@h PRIVMSG #t :" + tok(i).encode() + b"\r\n")
        pump(master, out, conn, 0.03)
    pump(master, out, conn, 1.0)
    mark = len(out)
    conn.sendall(b":a!a@h PRIVMSG #t :" + tok(nlines - 1).encode() + b"\r\n")
    pump(master, out, conn, 1.5)
    after = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", out[mark:].decode("utf-8", "replace"))
    seen = [i for i in range(0, nlines) if tok(i) in after]
    os.write(master, b"/quit\r")
    t = time.time()
    while proc.poll() is None and time.time() - t < 10:
        drain(master, out)
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    try:
        conn.close()
    except OSError:
        pass
    os.close(master)
    srv.close()
    raw_after = out[mark:].decode("utf-8", "replace")
    rows_used = sorted(set(int(m) for m in re.findall(r"\x1b\[(\d+);\d+H", raw_after)))

    def row_of(token: str):
        k = raw_after.find(token)
        if k < 0:
            return None
        m = list(re.finditer(r"\x1b\[(\d+);\d+H", raw_after[:k]))
        return int(m[-1].group(1)) if m else None

    newest = (nlines - 1) in seen
    print(
        "screen row of newest 3:",
        [row_of(tok(i)) for i in range(nlines - 3, nlines)],
        "| of the oldest visible:",
        (seen[0], row_of(tok(seen[0]))) if seen else None,
    )
    print(
        f"max cursor row addressed after the last line: {max(rows_used) if rows_used else None}; "
        f"distinct rows repainted: {len(rows_used)}"
    )
    print(
        f"rows={rows} sent 0..{nlines - 1}; after full redraw: {len(seen)} lines visible, "
        f"range {seen[0] if seen else None}..{seen[-1] if seen else None}; newest visible: {newest}"
    )
    if not newest:
        print("tall_rows: newest line not painted", file=sys.stderr)
        return 1
    print("tall_rows=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
