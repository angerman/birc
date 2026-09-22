#!/usr/bin/env python3
"""A1: a partial line then Eof must not glue onto the next connection.

(-) rem/drop survive session_fail and /connect, so 001 is not a numeric
    and JOIN is never sent.
(+) after /connect, 001 yields JOIN #t.

Documented target: 001 → JOIN <= 100 ms after the redial. The pass
criterion is the minimum of up to three trials in one run, so a load
spike cannot fail the gate and a regression to the 1 s idle tick still
fails all three.

usage: redial.py ./build/birc
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

BOUND_MS = 100.0
TRIALS = 3


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


def pump(master, out, conn, secs):
    end = time.time() + secs
    while time.time() < end:
        drain(master, out)
        if conn is not None:
            try:
                conn.recv(65536)
            except (socket.timeout, BlockingIOError, OSError):
                pass
        time.sleep(0.02)


def trial(birc: str) -> tuple[bool, float | None]:
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
    conn2 = None
    try:
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            print("redial: first accept timeout", file=sys.stderr)
            return False, None
        conn.settimeout(0.05)
        conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
        pump(master, out, conn, 1.0)
        conn.sendall(b":a!a@h PRIVMSG #t :partial")  # no CRLF: remainder
        pump(master, out, conn, 0.4)
        try:
            conn.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        conn.close()
        pump(master, out, None, 1.2)
        os.write(master, b"/connect 127.0.0.1 %d\r" % port)
        try:
            conn2, _ = srv.accept()
        except socket.timeout:
            print("redial: second accept timeout", file=sys.stderr)
            return False, None
        conn2.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        conn2.settimeout(0.05)
        pump(master, out, conn2, 0.8)
        conn2.sendall(b":irc.example.net 001 probe :Welcome\r\n")
        got = bytearray()
        t001 = time.time()
        t_join = None
        end = t001 + 1.5
        while time.time() < end:
            drain(master, out)
            try:
                got += conn2.recv(65536)
            except (socket.timeout, BlockingIOError, OSError):
                pass
            if b"JOIN #t" in got:
                t_join = time.time()
                break
            time.sleep(0.005)
        os.write(master, b"/quit\r")
        t = time.time()
        while proc.poll() is None and time.time() - t < 8:
            drain(master, out)
            time.sleep(0.05)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        joined = b"JOIN #t" in got
        ms = None if t_join is None else (t_join - t001) * 1000.0
        print(f"redial JOIN after 001: {joined} ms={ms} recv={got!r}")
        return joined, ms
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn2 is not None:
            try:
                conn2.close()
            except OSError:
                pass
        try:
            os.close(master)
        except OSError:
            pass
        srv.close()


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    times: list[float] = []
    for i in range(TRIALS):
        joined, ms = trial(birc)
        print(f"trial {i + 1}/{TRIALS}: joined={joined} ms={ms}")
        if not joined or ms is None:
            print("redial: no JOIN after reconnect 001", file=sys.stderr)
            return 1
        times.append(ms)
        if min(times) <= BOUND_MS:
            break
    best = min(times)
    print(f"trials_ms={times} min={best:.1f} bound={BOUND_MS}")
    if best > BOUND_MS:
        print(
            f"redial: min 001 to JOIN {best:.1f} ms (want <= {BOUND_MS:.0f})",
            file=sys.stderr,
        )
        return 1
    print("redial=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
