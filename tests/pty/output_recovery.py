#!/usr/bin/env python3
"""A short frame repairs itself after output recovers, without another input.

The unread and slowly draining cases also require PONG while repair is pending.
No key, resize, or new chat event may supply the missing repaint.
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

from output_stall import drain, receive


def fill(writer: int) -> None:
    deadline = time.monotonic() + 2
    for size in (4096, 256, 1):
        while time.monotonic() < deadline:
            try:
                os.write(writer, b"x" * size)
            except BlockingIOError:
                break
        else:
            raise AssertionError("fixture did not fill the terminal output queue")
    assert not select.select([], [writer], [], 0)[1], "output is still writable"


def release_some(master: int, writer: int) -> None:
    # Leave only enough room to start a full redraw, not finish it. A writable
    # notification does not promise that the rest of a frame will fit.
    released = 0
    while not select.select([], [writer], [], 0)[1] and released < 8192:
        assert select.select([master], [], [], 0.2)[0], "filled queue became empty"
        released += len(os.read(master, 256))
    assert select.select([], [writer], [], 0)[1], "output never became writable"


def case(binary: str, mode: str) -> None:
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(5)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    writer = os.open(os.ttyname(slave), os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
    proc = subprocess.Popen(
        [binary, "--plain", "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn = None
    try:
        conn, _ = listener.accept()
        assert b"USER probe" in receive(conn, b"USER probe", 2)
        conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
        drain(master, 0.8)
        assert b"JOIN #t" in receive(conn, b"JOIN #t", 2)
        if mode != "ordinary":
            fill(writer)
        conn.sendall(b"@+typing=active :alice!u@h TAGMSG #t\r\nPING :before-repair\r\n")
        assert b"PONG :before-repair" in receive(conn, b"PONG :before-repair", 0.8)

        if mode != "ordinary":
            # Keep output full across a maintenance tick. It must not start a
            # hot retry loop or park network progress on a blocking frame.
            time.sleep(1.2)
            conn.sendall(b"PING :unread-repair\r\n")
            assert b"PONG :unread-repair" in receive(conn, b"PONG :unread-repair", 0.8)
            if mode in ("slow", "slowquit"):
                release_some(master, writer)
                deadline = time.monotonic() + 1.5
                while select.select([], [writer], [], 0)[1] and time.monotonic() < deadline:
                    time.sleep(0.01)
                assert not select.select([], [writer], [], 0)[1], "retry did not start"
                if mode == "slowquit":
                    os.write(master, b"/quit\r")
                    proc.wait(timeout=1.5)
                    assert proc.returncode == 0, proc.returncode
                    assert b"QUIT" in receive(conn, b"QUIT", 0.2), "repair dropped QUIT"
                    print("output_recovery slowquit=ok", flush=True)
                    return
                conn.sendall(b"PING :slow-repair\r\n")
                assert b"PONG :slow-repair" in receive(conn, b"PONG :slow-repair", 0.8), "repair parked PONG"

        # Reading output is the only action that now permits the stored typing
        # state to appear. No further event is sent until that paint is seen.
        painted = bytearray()
        deadline = time.monotonic() + 2
        while b"alice" not in painted and time.monotonic() < deadline:
            painted.extend(drain(master, 0.02))
        assert b"alice" in painted, f"{mode}: short frame did not repair itself; bytes={len(painted)}"
        os.write(master, b"/quit\r")
        drain(master, 0.2)
        proc.wait(timeout=3)
        assert proc.returncode == 0, proc.returncode
        print(f"output_recovery {mode}=ok", flush=True)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        listener.close()
        os.close(writer)
        os.close(master)


if __name__ == "__main__":
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    for mode in sys.argv[2:] or ("ordinary", "unread", "slow", "slowquit"):
        case(binary, mode)
