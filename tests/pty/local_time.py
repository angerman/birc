#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Live server-time conversion, receipt fallback, and day rollover (loopback)."""
from __future__ import annotations

import fcntl
import os
import pty
import re
import select
import socket
import struct
import subprocess
import sys
import termios
import time
from split_identity import Screen


def main(binary: str) -> None:
    listener = socket.socket()
    master = slave = None
    process = conn = None
    cells = Screen()
    wire = bytearray()
    try:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(5)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        env = {**os.environ, "TERM": "xterm-256color", "TZ": "Asia/Seoul",
               "BIRC_HISTORY": "none", "BIRC_IMAGES": "off", "BIRC_PREFERENCES": "none"}
        for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH_SECRET_FD", "BIRC_AUTH_EVENT_FD"):
            env.pop(name, None)
        process = subprocess.Popen(
            [binary, "--plain", "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
             "--nick", "probe", "--channel", "#time", "--frames", "0"],
            stdin=slave, stdout=slave, stderr=slave, env=env,
        )
        os.close(slave)
        slave = None
        conn, _ = listener.accept()
        conn.setblocking(False)

        def pump() -> None:
            ready, _, _ = select.select([master, conn], [], [], 0.02)
            for fd in ready:
                if fd is conn:
                    data = conn.recv(65536)
                    if data:
                        wire.extend(data)
                else:
                    try:
                        chunk = os.read(master, 65536)
                        cells.feed(chunk)
                    except OSError:
                        pass

        def until(predicate, label: str, seconds: float = 4) -> None:
            deadline = time.monotonic() + seconds
            while not predicate() and time.monotonic() < deadline:
                pump()
            assert predicate(), label + "\n" + cells.text()

        def painted() -> bytes:
            return cells.text().encode()

        until(lambda: b"USER probe" in wire, "registration")
        conn.sendall(b":irc.test 001 probe :Welcome\r\n")
        until(lambda: b"JOIN #time\r\n" in wire, "initial JOIN")
        conn.sendall(b":probe!u@h JOIN #time\r\n")
        conn.sendall(b"@time=2000-01-01T23:30:59.123Z :alice!u@h PRIVMSG #time :local-event-marker\r\n")
        until(lambda: b"08:30:59 <alice> local-event-marker" in painted(), "live date-aware local event time")
        assert b"23:30:59 <alice> local-event-marker" not in painted(), "raw UTC painted"
        conn.sendall(b"@time=2000-01-01T99:99:99Z :alice!u@h PRIVMSG #time :invalid-event-marker\r\n")
        until(lambda: re.search(rb"(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d <alice> invalid-event-marker", painted()) is not None,
              "invalid server time uses local receipt clock")
        assert b"99:99:99 <alice> invalid-event-marker" not in painted(), "invalid time painted"
        conn.sendall(b":alice!u@h PRIVMSG #time :receipt-event-marker\r\nPING :time-control\r\n")
        until(lambda: b"PONG :time-control\r\n" in wire and b"receipt-event-marker" in painted(), "untagged receipt and PONG")
        os.write(master, b"/quit\r")
        until(lambda: process.poll() is not None, "clean quit", 6)
        process.wait(timeout=1)
        assert process.returncode == 0, "nonzero quit"
        print("local_time_pty=ok")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        if conn is not None:
            conn.close()
        listener.close()
        for fd in (master, slave):
            if fd is not None:
                os.close(fd)


if __name__ == "__main__":
    main(sys.argv[1])
