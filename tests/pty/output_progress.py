#!/usr/bin/env python3
"""A frame larger than the tty queue must finish across bounded repairs.

No new input/chat may supply the large recovery wake. The paced case also
checks PONG and latest geometry; quitting an incomplete frame remains prompt.
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import time

from output_recovery import fill
from output_stall import drain, receive


def case(binary: str, mode: str) -> None:
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    server.settimeout(5)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
    writer = os.open(os.ttyname(slave), os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
    proc = subprocess.Popen(
        [binary, "--connect", "127.0.0.1", "--port", str(server.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn = None
    try:
        conn, _ = server.accept()
        assert b"USER probe" in receive(conn, b"USER probe", 2)
        conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
        drain(master, 0.6)
        assert b"JOIN #t" in receive(conn, b"JOIN #t", 2)
        if mode != "ordinary":
            fill(writer)
        for index in range(199):
            conn.sendall(f":a!u@h PRIVMSG #t :row{index:03d} ".encode() + b"x" * 160 + b"\r\n")
        conn.sendall(b":a!u@h PRIVMSG #t :PROGRESS-END\r\nPING :full-progress\r\n")
        assert b"PONG :full-progress" in receive(conn, b"PONG :full-progress", 1)
        if mode != "ordinary":
            time.sleep(1.1)
            conn.sendall(b"PING :still-full\r\n")
            assert b"PONG :still-full" in receive(conn, b"PONG :still-full", 1)
        if mode == "quit":
            # Permit a partial physical frame, then stop reading again.
            if select.select([master], [], [], 0.2)[0]:
                os.read(master, 256)
            time.sleep(0.2)
            started = time.monotonic()
            os.write(master, b"/quit\r")
            proc.wait(timeout=1.5)
            assert proc.returncode == 0
            assert b"QUIT" in receive(conn, b"QUIT", 0.2)
            print(f"output_progress quit=ok wall={time.monotonic() - started:.3f}s", flush=True)
            return

        painted = bytearray()
        wire = bytearray()
        started = time.monotonic()
        ping_at = None
        resized = False
        while time.monotonic() - started < 6:
            elapsed = time.monotonic() - started
            if mode == "slow":
                if select.select([master], [], [], 0)[0]:
                    painted.extend(os.read(master, 128))
                if not resized and elapsed > 0.5:
                    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 160, 0, 0))
                    os.kill(proc.pid, signal.SIGWINCH)
                    resized = True
                if ping_at is None and elapsed > 0.7:
                    conn.sendall(b"PING :paced-progress\r\n")
                    ping_at = time.monotonic()
                if select.select([conn], [], [], 0)[0]:
                    wire.extend(conn.recv(65536))
                if ping_at is not None and time.monotonic() - ping_at > 1:
                    assert b"PONG :paced-progress" in wire, "paced repair blocked PONG"
                time.sleep(0.005)
            else:
                painted.extend(drain(master, 0.02))
            if b"PROGRESS-END" in painted and (mode != "slow" or b"PONG :paced-progress" in wire):
                break
        assert b"PROGRESS-END" in painted, f"{mode}: no finite output progress; bytes={len(painted)}"
        os.write(master, b"/quit\r")
        drain(master, 0.3)
        proc.wait(timeout=2)
        assert proc.returncode == 0
        print(f"output_progress {mode}=ok bytes={len(painted)}", flush=True)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        server.close()
        os.close(writer)
        os.close(master)


if __name__ == "__main__":
    for mode in sys.argv[2:] or ("ordinary", "large", "slow", "quit"):
        case(sys.argv[1] if len(sys.argv) > 1 else "./build/birc", mode)
