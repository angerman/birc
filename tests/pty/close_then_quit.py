#!/usr/bin/env python3
"""Server close racing /quit must still exit.

A network frame reads the tty. If that frame drops the keys, /quit is
consumed and the UI waits forever for a Key that will not come. Twelve
runs: each must print birc=ok and exit 0 within 5 s of /quit.

usage: close_then_quit.py ./build/birc
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

RUNS = 12
CHUNKS = 30
QUIT_S = 5.0


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


def one(birc: str) -> tuple[bool, str]:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(8)
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
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        proc.kill()
        proc.wait()
        os.close(master)
        srv.close()
        return False, "accept timeout"
    conn.settimeout(0.005)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    for i in range(CHUNKS):
        drain(master, out)
        if proc.poll() is not None:
            break
        try:
            conn.sendall(b":a!a@h PRIVMSG #t :line %d\r\n" % i)
        except OSError:
            break
        try:
            conn.recv(4096)
        except OSError:
            pass
        time.sleep(0.04)
    try:
        conn.close()
    except OSError:
        pass
    os.write(master, b"/quit\r")
    t0 = time.time()
    while proc.poll() is None and time.time() - t0 < QUIT_S:
        drain(master, out)
        time.sleep(0.02)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    drain(master, out)
    os.close(master)
    srv.close()
    try:
        conn.close()
    except OSError:
        pass
    ok = (not hung) and proc.returncode == 0 and b"birc=ok" in out
    why = f"hung={hung} exit={proc.returncode} ok_text={b'birc=ok' in out} quit_s={time.time()-t0:.2f}"
    return ok, why


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    bad = 0
    for i in range(RUNS):
        ok, why = one(birc)
        print(f"run {i + 1}/{RUNS}: {why}")
        if not ok:
            bad += 1
    if bad:
        print(f"close_then_quit: {bad}/{RUNS} failed", file=sys.stderr)
        return 1
    print("close_then_quit=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
