#!/usr/bin/env python3
"""A failed atomic frame capture uses the normal connected shutdown path.

The negative binary is compiled with BIRC_OUTPUT_LIMIT=4096. Both binaries
first register and answer PING on a small terminal; only a later resize
crosses the negative binary's limit. The ordinary binary is the control.
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

from output_stall import drain, receive


def case(binary: str, failure: bool) -> None:
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    server.settimeout(5)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 10, 40, 0, 0))
    # macOS adds a sticky F_GETFL status bit on the first write, independently
    # of birc. Snapshot an already-written stream, not that kernel transition.
    os.write(slave, b"fixture\n")
    drain(master, 0.02)
    original_flags = fcntl.fcntl(slave, fcntl.F_GETFL)
    original_termios = termios.tcgetattr(slave)
    proc = subprocess.Popen(
        [binary, "--connect", "127.0.0.1", "--port", str(server.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
    )
    conn = None
    try:
        conn, _ = server.accept()
        assert b"USER probe" in receive(conn, b"USER probe", 2), "failed before healthy registration"
        conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
        painted = bytearray(drain(master, 0.4))
        assert b"JOIN #t" in receive(conn, b"JOIN #t", 2)
        for index in range(80):
            conn.sendall(f":a!u@h PRIVMSG #t :row{index:03d} ".encode() + b"x" * 160 + b"\r\n")
        conn.sendall(b":a!u@h PRIVMSG #t :LIMIT-CONTROL\r\nPING :small-frame\r\n")
        end = time.monotonic() + 2
        wire = bytearray()
        while b"PONG :small-frame" not in wire and time.monotonic() < end:
            painted.extend(drain(master, 0.01))
            if select.select([conn], [], [], 0)[0]:
                wire.extend(conn.recv(65536))
        assert b"PONG :small-frame" in wire, "small connected frame was not healthy"
        assert proc.poll() is None, "capture failed before deliberate resize"
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
        started = time.monotonic()
        os.kill(proc.pid, signal.SIGWINCH)
        if not failure:
            painted.extend(drain(master, 1.2))
            assert proc.poll() is None, "ordinary frame incorrectly failed"
            assert b"LIMIT-CONTROL" in painted, "ordinary resized frame did not paint"
            os.write(master, b"/quit\r")
        end = time.monotonic() + 2
        while proc.poll() is None and time.monotonic() < end:
            painted.extend(drain(master, 0.01))
        proc.wait(timeout=0.5)
        painted.extend(drain(master, 0.1))
        assert proc.returncode == (1 if failure else 0), proc.returncode
        conn.settimeout(0.5)
        while True:
            data = conn.recv(65536)
            if not data:
                break
            wire.extend(data)
        if not failure:
            assert b"QUIT" in wire, "submitted /quit did not flush QUIT"
        assert b"\x1b[?1049l" in painted, "terminal screen was not restored"
        assert (b"birc=failed" if failure else b"birc=ok") in painted
        actual_flags = fcntl.fcntl(slave, fcntl.F_GETFL)
        assert actual_flags == original_flags, f"tty fd flags were not restored: {original_flags:#x}->{actual_flags:#x}"
        assert termios.tcgetattr(slave) == original_termios, "tty termios was not restored"
        print(f"output_failure {'negative' if failure else 'positive'}=ok wall={time.monotonic() - started:.3f}s", flush=True)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        server.close()
        os.close(slave)
        os.close(master)


if __name__ == "__main__":
    case(sys.argv[1], False)
    case(sys.argv[2], True)
