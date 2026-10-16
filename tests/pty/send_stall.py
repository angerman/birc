#!/usr/bin/env python3
"""Normal traffic and a non-reading peer both leave /quit usable.

Long legal PINGs saturate the socket, command channel, and event channel.
The test drains the terminal throughout, isolating network backpressure.
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


def case(binary: str, stalled: bool) -> None:
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(8)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [binary, "--plain", "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_PREFERENCES": "none", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn = None
    try:
        conn, _ = listener.accept()
        conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
        drain(master, 0.6)
        assert b"USER probe" in receive(conn, b"JOIN #t", 2)
        os.write(master, b"/set autoreconn off\r")
        drain(master, 0.3)
        if stalled:
            conn.setblocking(False)
            flood = (b"PING :" + b"x" * 480 + b"\r\n") * 10000
            offset = 0
            end = time.monotonic() + 6
            while offset < len(flood) and time.monotonic() < end:
                drain(master, 0.002)
                try:
                    offset += conn.send(flood[offset:offset + 32768])
                except BlockingIOError:
                    continue
                except (BrokenPipeError, ConnectionResetError):
                    break
            assert offset > 65536, f"flood too small to test queue pressure: {offset}"
            drain(master, 0.3)
            assert proc.poll() is None, "send failure terminated the UI"
        else:
            conn.sendall(b"PING :ordinary\r\n")
            drain(master, 0.3)
            assert b"PONG :ordinary" in receive(conn, b"PONG :ordinary", 1)
        os.write(master, b"/quit\r")
        drain(master, 0.6)
        proc.wait(timeout=2)
        assert proc.returncode == 0, f"exit={proc.returncode} stalled={stalled}"
        if not stalled:
            assert b"QUIT" in receive(conn, b"QUIT", 1), "normal shutdown lost QUIT"
        print(f"send_stall stalled={stalled}=ok", flush=True)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        listener.close()
        os.close(master)


if __name__ == "__main__":
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    case(binary, False)
    case(binary, True)
