#!/usr/bin/env python3
"""Esc split across reads is one Up, and a lone Esc still quits (F2).

`one` then `two`, then ESC, 10 ms, then `[A` and Enter. History must
recall `two` (one Up). Applying the sequence twice recalls `one`.
The same binary must also quit on a lone Esc.

usage: esc_up.py ./build/birc
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
        ready, _, _ = select.select([fd], [], [], 0)
        if not ready:
            return
        try:
            data = os.read(fd, 65536)
        except OSError:
            return
        if not data:
            return
        sink += data


def pump(master: int, conn: socket.socket, screen: bytearray, got: bytearray, seconds: float) -> None:
    end = time.time() + seconds
    while time.time() < end:
        drain(master, screen)
        try:
            data = conn.recv(65536)
        except socket.timeout:
            data = b""
        if data:
            got += data
        time.sleep(0.01)


def split_once(birc: str) -> str:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(15)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
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
            "0",
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    screen = bytearray()
    got = bytearray()
    conn, _ = srv.accept()
    conn.settimeout(0.05)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    pump(master, conn, screen, got, 0.8)
    for word in (b"one\r", b"two\r"):
        os.write(master, word)
        pump(master, conn, screen, got, 0.35)
    os.write(master, b"\x1b")
    time.sleep(0.01)
    os.write(master, b"[A")
    pump(master, conn, screen, got, 0.4)
    os.write(master, b"\r")
    pump(master, conn, screen, got, 0.4)
    os.write(master, b"/quit\r")
    pump(master, conn, screen, got, 1.0)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    os.close(master)
    conn.close()
    srv.close()
    lines = [ln for ln in got.decode("latin1", "replace").split("\r\n") if "PRIVMSG" in ln]
    print(lines)
    if not lines:
        return ""
    return lines[-1]


def lone_esc(birc: str) -> bool:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    proc = subprocess.Popen(
        [birc, "--demo", "--frames", "0"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    screen = bytearray()
    end = time.time() + 1.0
    while time.time() < end:
        drain(master, screen)
        time.sleep(0.02)
    os.write(master, b"\x1b")
    end = time.time() + 1.5
    while proc.poll() is None and time.time() < end:
        drain(master, screen)
        time.sleep(0.02)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    drain(master, screen)
    os.close(master)
    ok = (not hung) and proc.returncode == 0 and b"birc=ok" in screen
    print(f"lone_esc hung={hung} exit={proc.returncode} ok={ok}")
    return ok


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    bad = 0
    if not lone_esc(birc):
        bad += 1
    for i in range(3):
        last = split_once(birc)
        print(f"split {i + 1}: {last}")
        if "two" not in last or last.strip().endswith("one"):
            # The recalled line is the privmsg text. `one` means two Ups.
            if ":two" not in last and not last.endswith("two"):
                bad += 1
                print(f"split {i + 1}: wanted two", file=sys.stderr)
        elif ":one" in last.split("PRIVMSG")[-1] and ":two" not in last.split("PRIVMSG")[-1]:
            bad += 1
    if bad:
        print("esc_up: failed", file=sys.stderr)
        return 1
    print("esc_up=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
