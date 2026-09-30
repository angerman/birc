#!/usr/bin/env python3
"""All terminal output shares a deadline, including bells and clipboard.

The ordinary case is the positive control. The other cases reproduce writes
outside the old frame deadline. A slow fake pbcopy must not delay PONG either.
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import shlex
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path


def drain(master: int, duration: float) -> bytes:
    out = bytearray()
    end = time.monotonic() + duration
    while time.monotonic() < end:
        if select.select([master], [], [], 0.01)[0]:
            try:
                out.extend(os.read(master, 65536))
            except OSError:
                break
    return bytes(out)


def receive(conn: socket.socket, needle: bytes, duration: float) -> bytes:
    out = bytearray()
    end = time.monotonic() + duration
    while time.monotonic() < end and needle not in out:
        if select.select([conn], [], [], 0.02)[0]:
            data = conn.recv(65536)
            if not data:
                break
            out.extend(data)
    return bytes(out)


def startup_case(binary: str, mode: str) -> None:
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(3)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    if mode != "ordinary":
        flags = fcntl.fcntl(slave, fcntl.F_GETFL)
        fcntl.fcntl(slave, fcntl.F_SETFL, flags | os.O_NONBLOCK)
        try:
            for _ in range(4096):
                os.write(slave, b"x" * 4096)
            raise AssertionError("fixture could not fill the terminal output queue")
        except BlockingIOError:
            pass
        finally:
            fcntl.fcntl(slave, fcntl.F_SETFL, flags)
    output = os.open(os.ttyname(slave), os.O_WRONLY | os.O_NOCTTY) if mode == "separate" else slave
    proc = subprocess.Popen(
        [binary, "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=output, stderr=output,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
    )
    if output != slave:
        os.close(output)
    os.close(slave)
    conn = None
    try:
        conn, _ = listener.accept()
        conn.sendall(b":irc 001 probe :Welcome\r\nPING :startup-output\r\n")
        # Keep the terminal unread through startup and the PONG assertion.
        # Both shared and independent output descriptions must be bounded.
        got = receive(conn, b"PONG :startup-output", 1)
        assert b"PONG :startup-output" in got, f"startup {mode}: unread terminal blocked PONG: {got!r}"
        assert b"USER probe" in got, f"startup {mode}: missing registration: {got!r}"
        assert not termios.tcgetattr(master)[3] & termios.ICANON, f"startup {mode}: terminal did not enter raw mode"
        os.write(master, b"/quit\r")
        proc.wait(timeout=3)
        assert proc.returncode == 0, f"startup {mode}: exit={proc.returncode}"
        attrs = termios.tcgetattr(master)
        assert attrs[3] & termios.ICANON, f"startup {mode}: terminal remained raw"
        print(f"output_stall startup {mode}=ok", flush=True)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        listener.close()
        os.close(master)


def case(binary: str, mode: str, directory: str) -> None:
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(8)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
    env = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none",
           "PATH": directory,
           "BIRC_CLIPBOARD_LOG": os.path.join(directory, "copied")}
    # A reopened output has independent fd flags. Nonblocking input alone
    # does not bound writes to it.
    output = os.open(os.ttyname(slave), os.O_WRONLY | os.O_NOCTTY) if mode == "separate" else slave
    if mode == "separate":
        env["BIRC_FRAME_PROFILE"] = "1"
    proc = subprocess.Popen(
        [binary, "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=output, stderr=output, env=env,
    )
    if output != slave:
        os.close(output)
    os.close(slave)
    conn = None
    try:
        conn, _ = listener.accept()
        conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
        drain(master, 0.8)
        assert b"USER probe" in receive(conn, b"JOIN #t", 2)
        # Distinct paints fill the terminal's output queue. No output is read
        # from here until after the PONG assertion.
        for index in range(500):
            conn.sendall((f":a!u@h PRIVMSG #t :{index:03d} " + "x" * 100 + "\r\n").encode())
            time.sleep(0.005)
        if mode == "bell":
            conn.sendall(b":bob!u@h PRIVMSG probe :ring once\r\n")
        elif mode == "selection":
            # Distinct frames are required: coalesced press+release is a
            # click, not a drag. Select nonempty rows after the queue fills.
            for event in (b"\x1b[<0;20;40M", b"\x1b[<32;80;40M", b"\x1b[<0;80;40m"):
                os.write(master, event)
                time.sleep(0.2)
        time.sleep(0.2)
        token = ("PONG :output-" + mode).encode()
        conn.sendall(("PING :output-" + mode + "\r\n").encode())
        got = receive(conn, token, 0.8)
        assert token in got, f"{mode}: PONG blocked by unread terminal: {got!r}"
        if mode == "selection" and sys.platform == "darwin":
            copied = Path(env["BIRC_CLIPBOARD_LOG"])
            deadline = time.monotonic() + 0.8
            while not copied.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            assert copied.exists(), "selection did not invoke fake pbcopy"
        os.write(master, b"/quit\r")
        proc.wait(timeout=3)
        assert proc.returncode == 0, f"{mode}: exit={proc.returncode}"
        print(f"output_stall {mode}=ok", flush=True)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        listener.close()
        os.close(master)


def main() -> None:
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    for mode in ("ordinary", "shared", "separate"):
        startup_case(binary, mode)
    with tempfile.TemporaryDirectory(prefix="birc-output-stall-") as directory:
        # Consume input immediately, then remain alive long enough that a
        # synchronous pclose would fail the PONG latency assertion.
        opener = Path(directory, "pbcopy")
        cat = shutil.which("cat")
        sleep = shutil.which("sleep")
        assert cat and sleep, "fixture tools are missing"
        opener.write_text('#!/bin/sh\n' + shlex.quote(cat) +
                          ' > "$BIRC_CLIPBOARD_LOG"\n' + shlex.quote(sleep) + ' 3\n')
        opener.chmod(0o755)
        for mode in ("ordinary", "bell", "selection", "separate"):
            case(binary, mode, directory)


if __name__ == "__main__":
    main()
