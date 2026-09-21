#!/usr/bin/env python3
"""Pty flood: many server chunks, one TCP write each.

Headless birc quits on the first frame, so loop tests need a pty.

usage: chunk_flood.py ./build/birc [N=200] [FRAMES=0]

Fails (exit 1) on deadlock, hang, or missing birc=ok.
On ac97be1 this deadlocks around 128–158 chunks (two Chan.send per Chunk).
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


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    frames = sys.argv[3] if len(sys.argv) > 3 else "0"
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    t0 = time.time()
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
            frames,
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
        print("chunk_flood: accept timeout", file=sys.stderr)
        return 1
    conn.settimeout(0.005)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    time.sleep(0.2)
    sent = 0
    died_at = None
    for i in range(n):
        drain(master, out)
        if proc.poll() is not None:
            died_at = i
            break
        try:
            conn.sendall(b":a!a@h PRIVMSG #t :tok%03d\r\n" % i)
            sent += 1
        except (BrokenPipeError, ConnectionResetError):
            died_at = i
            break
        try:
            conn.recv(4096)
        except (socket.timeout, ConnectionResetError, BrokenPipeError):
            pass
        time.sleep(0.02)
    try:
        conn.close()
    except OSError:
        pass
    # H3: Eof keeps the UI alive. Ask it to quit instead of waiting for shutdown.
    if proc.poll() is None:
        os.write(master, b"/quit\r")
    deadline = time.time() + 25
    while proc.poll() is None and time.time() < deadline:
        drain(master, out)
        time.sleep(0.05)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    drain(master, out)
    os.close(master)
    srv.close()
    text = out.decode("utf-8", "replace")
    wall = time.time() - t0
    deadlock = "deadlock" in text
    ok = "birc=ok" in text
    print(
        f"sent={sent}/{n} died_at={died_at} hung={hung} exit={proc.returncode} "
        f"wall={wall:.1f}s deadlock={deadlock} birc_ok={ok}"
    )
    if hung or deadlock:
        print("chunk_flood: deadlock or hang", file=sys.stderr)
        return 1
    if not ok or proc.returncode not in (0, None):
        print("chunk_flood: missing birc=ok or nonzero exit", file=sys.stderr)
        return 1
    if sent < n:
        print(f"chunk_flood: died after {sent} of {n} chunks", file=sys.stderr)
        return 1
    print("chunk_flood=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
