#!/usr/bin/env python3
"""Initial registration and reconnect both use the current acknowledged nick."""
from __future__ import annotations

import fcntl
import os
import pty
import socket
import struct
import subprocess
import sys
import termios

from output_stall import drain, receive


def case(binary: str, rename: bool) -> None:
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(2)
    listener.settimeout(8)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [binary, "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn = None
    try:
        conn, _ = listener.accept()
        registration = receive(conn, b"USER probe", 2)
        assert b"NICK probe\r\nUSER probe" in registration, registration
        conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
        drain(master, 0.4)
        assert b"JOIN #t" in receive(conn, b"JOIN #t", 2)
        nick = b"probe"
        if rename:
            os.write(master, b"/nick renamed\r")
            drain(master, 0.3)
            assert b"NICK renamed" in receive(conn, b"NICK renamed", 2)
            conn.sendall(b":probe!u@h NICK :renamed\r\n")
            drain(master, 0.4)
            nick = b"renamed"
        # Both explicit reconnect and the automatic reconnect use the same
        # Dial snapshot. Force automatic reconnect after the acknowledged NICK.
        conn.shutdown(socket.SHUT_RDWR)
        conn.close()
        conn = None
        drain(master, 2.5)
        conn, _ = listener.accept()
        registration = receive(conn, b"USER " + nick, 2)
        assert b"NICK " + nick + b"\r\nUSER " + nick in registration, registration
        conn.sendall(b":irc 001 " + nick + b" :Welcome again\r\n")
        drain(master, 0.4)
        os.write(master, b"/quit\r")
        drain(master, 0.4)
        proc.wait(timeout=3)
        assert proc.returncode == 0, proc.returncode
        print(f"reconnect_nick rename={rename}=ok", flush=True)
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
