#!/usr/bin/env python3
"""Every frame preserves clicks during resize and inbound chat paints.

A fake opener records exact URLs. No browser is launched. The long case
also checks wrapped links longer than the former 255-byte FFI buffer.
"""
from __future__ import annotations

import fcntl
import os
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
from pathlib import Path

from output_stall import drain, receive


def link_point(painted: bytes, url: str) -> tuple[int, int]:
    """Locate an actual OSC 8 glyph, not a guessed logical-line position."""
    row, col, active, underline = 1, 1, False, False
    points = []
    underlined = []
    tokens = re.finditer(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x1b\x07]*(?:\x1b\\|\x07)|.)|[^\x1b]",
                         painted.decode("utf-8", "replace"))
    for match in tokens:
        token = match.group()
        if token.startswith("\x1b]8;;"):
            active = token[5:].removesuffix("\x1b\\").removesuffix("\x07") == url
        elif token.startswith("\x1b["):
            params = token[2:-1].split(";")
            if token[-1] in "Hf":
                row = int(params[0] or "1")
                col = int(params[1] or "1") if len(params) > 1 else 1
            elif token[-1] == "G":
                col = int(params[0] or "1")
            elif token[-1] == "m":
                index = 0
                while index < len(params):
                    code = int(params[index] or "0")
                    if code in (38, 48) and index + 1 < len(params):
                        index += 5 if params[index + 1] == "2" else 3
                        continue
                    if code == 0 or code == 24:
                        underline = False
                    elif code == 4:
                        underline = True
                    index += 1
        elif token == "\r":
            col = 1
        elif token == "\n":
            row += 1
        elif not token.startswith("\x1b") and token >= " ":
            if active and not token.isspace():
                points.append((col, row))
            if underline and not token.isspace():
                underlined.append((col, row))
            col += 1
    # TimUI's native OSC 8 URI table is limited to 255 bytes. Bend's exact
    # longer target still has an underlined in-app hit region and is returned
    # by UiKeys. This fixture contains no other underlined text.
    points = points or underlined
    assert points, "exact URL has no rendered clickable glyph"
    return points[0]


def case(binary: str, mode: str, directory: str) -> None:
    log = Path(directory, "opened")
    log.unlink(missing_ok=True)
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(8)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    live = mode in ("inbound", "long", "latin1")
    args = ["--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
            "--nick", "probe", "--channel", "#t"] if live else ["--demo"]
    proc = subprocess.Popen(
        [binary, "--plain", *args, "--frames", "0"], stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_PREFERENCES": "none", "BIRC_HISTORY": "none",
             "BIRC_LINK_LOG": str(log), "PATH": directory},
    )
    os.close(slave)
    conn = None
    url = ("https://example.com/" + "x" * 280 if mode == "long" else
           "https://example.com/" + "é" * 430 if mode == "latin1" else
           "https://timui.dev")
    message = (":carol!u@h PRIVMSG #t :see " + url + "\r\n").encode(
        "latin-1" if mode == "latin1" else "utf-8")
    assert len(message) <= 512
    try:
        if live:
            conn, _ = listener.accept()
            assert b"USER probe" in receive(conn, b"USER probe", 2)
            conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
            drain(master, 0.4)
            assert b"JOIN #t" in receive(conn, b"JOIN #t", 2)
            conn.sendall(message)
        painted = bytearray()
        deadline = time.monotonic() + 3
        while url[:20].encode() not in painted and time.monotonic() < deadline:
            painted.extend(drain(master, 0.05))
        assert url[:20].encode() in painted, f"{mode}: link fixture was not painted"
        col, row = link_point(painted, url)
        click = f"\x1b[<0;{col};{row}M\x1b[<0;{col};{row}m".encode()
        # Positive control, then repeated concurrent paints at unchanged size.
        for index in range(11):
            if index and mode != "ordinary":
                if conn is not None and mode != "latin1":
                    conn.sendall(message)
                os.kill(proc.pid, signal.SIGWINCH)
            os.write(master, click)
            drain(master, 0.2)
        opened = log.read_text().splitlines() if log.exists() else []
        assert opened == [url] * 11, (
            f"{mode}: expected 11 exact clicks; got {len(opened)}, "
            f"target lengths {[len(target) for target in opened]}")
        if conn is not None:
            conn.sendall(b"PING :frame-links\r\n")
            drain(master, 0.2)
            assert b"PONG :frame-links" in receive(conn, b"PONG :frame-links", 2)
        os.write(master, b"/quit\r")
        drain(master, 0.2)
        proc.wait(timeout=3)
        assert proc.returncode == 0, proc.returncode
        print(f"frame_links {mode}=ok", flush=True)
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
    with tempfile.TemporaryDirectory(prefix="birc-frame-links-") as directory:
        opener = Path(directory, "open" if sys.platform == "darwin" else "xdg-open")
        opener.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$BIRC_LINK_LOG"\n')
        opener.chmod(0o755)
        for mode in ("ordinary", "resize", "inbound", "long", "latin1"):
            case(binary, mode, directory)
