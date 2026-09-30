#!/usr/bin/env python3
"""Split panes, focus, and sends distinguish control from a query named server."""
from __future__ import annotations

import fcntl
import os
import pty
import re
import socket
import struct
import subprocess
import sys
import termios
import time

from output_stall import drain, receive


class Screen:
    """Read the final cells; erased text from an older frame is not evidence."""

    def __init__(self) -> None:
        self.cells: dict[tuple[int, int], str] = {}
        self.row = self.col = 1

    def feed(self, data: bytes) -> None:
        tokens = re.finditer(
            r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x1b\x07]*(?:\x1b\\|\x07)|.)|[^\x1b]",
            data.decode("utf-8", "replace"),
        )
        for match in tokens:
            token = match.group()
            if token.startswith("\x1b["):
                params = token[2:-1].split(";")
                code = token[-1]
                if code in "Hf":
                    self.row = int(params[0] or "1")
                    self.col = int(params[1] or "1") if len(params) > 1 else 1
                elif code == "G":
                    self.col = int(params[0] or "1")
                elif code == "J" and params[0] == "2":
                    self.cells.clear()
                elif code == "K":
                    for point in list(self.cells):
                        if point[0] == self.row and point[1] >= self.col:
                            del self.cells[point]
            elif token == "\r":
                self.col = 1
            elif token == "\n":
                self.row += 1
            elif not token.startswith("\x1b") and token >= " ":
                self.cells[self.row, self.col] = token
                self.col += 1

    def text(self) -> str:
        return "\n".join("".join(self.cells.get((row, col), " ")
                               for col in range(1, 121)) for row in range(1, 31))


def main(binary: str) -> None:
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(8)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
    proc = subprocess.Popen(
        [binary, "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn = None
    screen = Screen()

    def painted(*present: str, absent: tuple[str, ...] = ()) -> str:
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            screen.feed(drain(master, 0.05))
            text = screen.text()
            if all(marker in text for marker in present) and all(marker not in text for marker in absent):
                return text
        raise AssertionError(f"pane mismatch; wanted {present}, absent {absent}:\n{screen.text()}")

    def command(data: bytes, *present: str, absent: tuple[str, ...] = ()) -> str:
        os.write(master, data)
        # Require a new paint before accepting markers already on the screen.
        screen.feed(drain(master, 0.2))
        return painted(*present, absent=absent)

    def send(target: bytes, body: bytes) -> None:
        os.write(master, body + b"\r")
        screen.feed(drain(master, 0.2))
        expected = b"PRIVMSG " + target + b" :" + body + b"\r\n"
        assert expected in receive(conn, expected, 2), expected

    try:
        conn, _ = listener.accept()
        assert b"USER probe" in receive(conn, b"USER probe", 2)
        conn.sendall(b":irc 001 probe :CONTROL-WELCOME\r\n:probe!u@h JOIN #t\r\n")
        screen.feed(drain(master, 0.4))
        assert b"JOIN #t" in receive(conn, b"JOIN #t", 2)
        conn.sendall(b":alice!u@h PRIVMSG #t :CHANNEL-MARKER\r\n")
        painted("CHANNEL-MARKER")

        # Existing /split server means control while no such query exists.
        command(b"/vsplit server\r", "CHANNEL-MARKER", "CONTROL-WELCOME")
        command(b"/unsplit\r", "CHANNEL-MARKER", absent=("CONTROL-WELCOME",))

        conn.sendall(b":server!u@h PRIVMSG probe :PRIVATE-SERVER-QUERY\r\n")
        command(b"/query server\r", "PRIVATE-SERVER-QUERY")
        command(b"/vsplit #t\r", "PRIVATE-SERVER-QUERY", "CHANNEL-MARKER",
                absent=("CONTROL-WELCOME",))
        send(b"server", b"before-focus")
        command(b"\x1b[17~", "#t [active]")
        send(b"#t", b"channel-focus")
        command(b"\x1b[17~", "server [active]", "PRIVATE-SERVER-QUERY",
                absent=("CONTROL-WELCOME",))
        send(b"server", b"after-focus")

        # The explicit invalid-nick key remains control despite the query.
        command(b"/split *server*\r", "PRIVATE-SERVER-QUERY", "CONTROL-WELCOME")
        command(b"\x1b[17~", "CONTROL-WELCOME")
        command(b"not-a-wire-message\r", "not in a channel")
        assert b"PRIVMSG" not in receive(conn, b"PRIVMSG", 0.2)
        command(b"\x1b[17~", "PRIVATE-SERVER-QUERY")
        send(b"server", b"query-after-control")
        command(b"/unsplit\r", "PRIVATE-SERVER-QUERY", absent=("CONTROL-WELCOME",))
        os.write(master, b"/quit\r")
        drain(master, 0.2)
        proc.wait(timeout=3)
        assert proc.returncode == 0, proc.returncode
        print("split_identity=ok", flush=True)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        listener.close()
        os.close(master)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "./build/birc")
