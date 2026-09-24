#!/usr/bin/env python3
"""A stalled tty must not freeze the net loop (F1).

Stop reading the pty, flood the client, then PING. PONG has to arrive
while the master is still unread. After the master is drained, a new
line has to show on the screen, including the flooded marker.

usage: stall.py ./build/birc
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


def drain(fd: int, sink: bytearray | None = None) -> None:
    while True:
        ready, _, _ = select.select([fd], [], [], 0)
        if not ready:
            return
        try:
            data = os.read(fd, 1 << 16)
        except OSError:
            return
        if not data:
            return
        if sink is not None:
            sink += data


def recv_for(sock: socket.socket, sink: bytearray, seconds: float) -> None:
    end = time.time() + seconds
    while time.time() < end:
        try:
            data = sock.recv(65536)
        except socket.timeout:
            continue
        if data:
            sink += data


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(10)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
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
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        proc.kill()
        proc.wait()
        os.close(master)
        srv.close()
        print("stall: accept timeout", file=sys.stderr)
        return 1
    conn.settimeout(0.05)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    end = time.time() + 1.0
    while time.time() < end:
        drain(master, screen)
        try:
            conn.recv(65536)
        except socket.timeout:
            pass
    # Nobody reads the pty from here until the stall window ends.
    for i in range(199):
        conn.sendall(b":a!a@h PRIVMSG #t :%s\r\n" % (b"x" * 80))
    conn.sendall(b":a!a@h PRIVMSG #t :STALLEND\r\n")
    time.sleep(0.3)
    conn.sendall(b"PING :stall1\r\n")
    stalled = bytearray()
    recv_for(conn, stalled, 3.0)
    pong_stalled = b"PONG" in stalled and b"stall1" in stalled
    print(f"PONG while tty stalled: {pong_stalled}")
    end = time.time() + 2.0
    while time.time() < end:
        drain(master, screen)
        try:
            data = conn.recv(65536)
        except socket.timeout:
            data = b""
        if data:
            stalled += data
    conn.sendall(b":a!a@h PRIVMSG #t :WAKE\r\n")
    end = time.time() + 3.0
    while time.time() < end:
        drain(master, screen)
        try:
            conn.recv(65536)
        except socket.timeout:
            pass
    text = screen.decode("latin1", "replace")
    has_end = "STALLEND" in text
    has_wake = "WAKE" in text
    print(f"screen STALLEND={has_end} WAKE={has_wake}")
    os.write(master, b"/quit\r")
    end = time.time() + 2.0
    while proc.poll() is None and time.time() < end:
        drain(master, screen)
        time.sleep(0.05)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    drain(master, screen)
    os.close(master)
    conn.close()
    srv.close()
    ok_text = b"birc=ok" in screen
    print(
        f"hung={hung} exit={proc.returncode} birc_ok={ok_text}"
    )
    if pong_stalled and has_end and has_wake and not hung and proc.returncode == 0 and ok_text:
        print("stall=ok")
        return 0
    print("stall: failed", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
