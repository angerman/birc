#!/usr/bin/env python3
"""Paint and /quit work while the initial TCP connect is still pending.

A full loopback accept backlog delays connect without an external network,
resolver override, or production test option. Every fixture socket is owned.
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


def case(binary: str, mode: str) -> None:
    blocked = mode != "ordinary"
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    fillers = []
    connection = None
    process = None
    master = None
    try:
        if blocked:
            for _ in range(32):
                filler = socket.socket()
                filler.setblocking(False)
                filler.connect_ex(server.getsockname())
                fillers.append(filler)
                if not select.select([], [filler], [], 0.02)[1]:
                    break
            else:
                raise AssertionError("fixture could not fill the loopback backlog")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        start = time.monotonic()
        process = subprocess.Popen(
            [binary, "--connect", "127.0.0.1", "--port", str(server.getsockname()[1]),
             "--nick", "probe", "--channel", "#t", "--frames", "0"],
            stdin=slave, stdout=slave, stderr=slave,
            env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
        )
        os.close(slave)
        if blocked:
            # Before the fix the entire screen waited behind Boot. The
            # deadline is shorter than the owned one-second connect timeout.
            output = bytearray()
            while time.monotonic() - start < 0.45 and b"connecting" not in output:
                output.extend(drain(master, 0.02))
            assert b"connecting" in output, "initial screen waited for TCP connect"
            assert not select.select([], [fillers[-1]], [], 0)[1], "fixture connect completed early"
        if not blocked:
            server.settimeout(3)
            connection, _ = server.accept()
            assert b"USER probe" in receive(connection, b"USER probe", 2)
            connection.sendall(b":irc 001 probe :Welcome\r\nPING :startup-control\r\n")
            drain(master, 0.3)
            assert b"PONG :startup-control" in receive(connection, b"PONG :startup-control", 1)
        os.write(master, b"/quit\r")
        process.wait(timeout=0.8 if mode == "blocked" else 3)
        assert process.returncode == 0, process.returncode
        print("startup_connect " + mode + "=ok", flush=True)
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        if connection is not None:
            connection.close()
        for filler in fillers:
            filler.close()
        server.close()
        if master is not None:
            os.close(master)


if __name__ == "__main__":
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    for mode in ("ordinary", "blocked"):
        case(binary, mode)
