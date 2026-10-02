#!/usr/bin/env python3
"""Runtime /open does not contaminate /links numbering or saved history."""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import pty
import re
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time

from output_stall import drain, receive
from softwrap import plain


def main() -> None:
    binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else "./build/birc").resolve())
    old, new = "https://old.example/path", "https://new.example/path"
    with tempfile.TemporaryDirectory(prefix="birc-session-links-") as directory:
        root = Path(directory)
        opened, history = root / "opened", root / "history"
        opener = root / ("open" if sys.platform == "darwin" else "xdg-open")
        opener.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$BIRC_LINK_LOG"\n')
        opener.chmod(0o755)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(8)
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
            child = subprocess.Popen(
                [binary, "--plain", "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
                 "--nick", "probe", "--channel", "#t", "--frames", "0"],
                stdin=slave, stdout=slave, stderr=slave,
                env={**os.environ, "TERM": "xterm-256color", "PATH": directory,
                     "BIRC_LINK_LOG": str(opened), "BIRC_HISTORY": str(history)},
            )
            os.close(slave)
            conn = None
            try:
                conn, _ = listener.accept()
                assert b"USER probe" in receive(conn, b"USER probe", 2)
                conn.sendall(b":s 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
                drain(master, 0.4)
                assert b"JOIN #t" in receive(conn, b"JOIN #t", 2)
                conn.sendall((f":a!u@h PRIVMSG #t :old {old}\r\n"
                              f":a!u@h PRIVMSG #t :new {new}\r\n").encode())
                painted = drain(master, 0.5)
                assert new.encode() in painted, "chat URLs were not painted"
                os.write(master, b"/open 1\r")
                deadline = time.monotonic() + 2
                while not opened.exists() and time.monotonic() < deadline:
                    drain(master, 0.03)
                assert opened.exists() and opened.read_text().splitlines() == [new]
                for _ in range(2):
                    os.write(master, b"/links\r")
                    drain(master, 0.3)
                # Resizing forces a complete paint; do not mistake an ANSI
                # incremental cell update for an incomplete logical line.
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 121, 0, 0))
                os.kill(child.pid, signal.SIGWINCH)
                listing = plain(drain(master, 0.5))
                numbered = re.findall(rb"\[[1-9][0-9]*\] https?://[^\s]+", listing)
                expected = [b"[1] " + new.encode(), b"[2] " + old.encode()]
                assert all(entry in numbered for entry in expected), numbered
                assert all(entry in expected for entry in numbered), numbered
                assert b"opening " not in listing, "opener echo survived /links"
                os.write(master, b"/quit\r")
                drain(master, 0.2)
                child.wait(timeout=3)
                assert child.returncode == 0, child.returncode
                persisted = history.read_text()
                assert "opening " not in persisted, persisted
                assert persisted.count(old) == 1 and persisted.count(new) == 1, persisted
                print("session_links=ok")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()
                if conn is not None:
                    conn.close()
                os.close(master)


if __name__ == "__main__":
    main()
