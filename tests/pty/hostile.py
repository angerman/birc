#!/usr/bin/env python3
"""M7.6 combined hostile wire/terminal corpus.

Exercise legal and overlong boundaries, bare CR recovery, invalid UTF-8,
fragmentation, buffer floods, message bursts, resize extremes, and recovery to
a final PING and painted marker. This harness is also used by full-app UBSan.

usage: hostile.py ./build/birc
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
import tempfile
import termios
import time


def drain(fd: int, output: bytearray) -> None:
    while select.select([fd], [], [], 0)[0]:
        try:
            data = os.read(fd, 65536)
        except OSError:
            return
        if not data:
            return
        output.extend(data)


def recv_into(conn: socket.socket, output: bytearray) -> None:
    while select.select([conn], [], [], 0)[0]:
        try:
            data = conn.recv(65536)
        except (BlockingIOError, ConnectionResetError, OSError):
            return
        if not data:
            return
        output.extend(data)


def pump(master: int, conn: socket.socket, screen: bytearray, wire: bytearray,
         seconds: float) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        drain(master, screen)
        recv_into(conn, wire)
        time.sleep(0.005)


def line_with_size(size: int, marker: bytes) -> bytes:
    prefix = b":edge!u@h PRIVMSG #m7 :" + marker
    if len(prefix) > size:
        raise ValueError("marker exceeds requested IRC payload")
    return prefix + b"x" * (size - len(prefix)) + b"\r\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    birc = sys.argv[1]
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    server.settimeout(20)
    port = server.getsockname()[1]
    conn: socket.socket | None = None

    master, slave = pty.openpty()
    check_fd = os.dup(slave)
    before = termios.tcgetattr(check_fd)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    with tempfile.TemporaryFile() as errors:
        proc = subprocess.Popen(
            [
                birc,
                "--connect",
                "127.0.0.1",
                "--port",
                str(port),
                "--nick",
                "probe",
                "--channel",
                "#m7",
                "--frames",
                "20000",
            ],
            stdin=slave,
            stdout=slave,
            stderr=errors,
            close_fds=True,
            env={**os.environ, "TERM": "xterm-256color"},
        )
        os.close(slave)
        screen = bytearray()
        wire = bytearray()
        try:
            conn, _ = server.accept()
            conn.setblocking(False)
            pump(master, conn, screen, wire, 1.0)
            conn.sendall(
                b":irc.example 001 probe :Welcome\r\n"
                b":probe!u@h JOIN #m7\r\n"
            )
            pump(master, conn, screen, wire, 0.5)

            # 510 octets before CRLF is legal; 511 is dropped. The following
            # marker proves that the framer recovers from the overlong line.
            conn.sendall(line_with_size(510, b"legal-boundary "))
            conn.sendall(line_with_size(511, b"drop-boundary "))
            conn.sendall(b":peer!u@h PRIVMSG #m7 :after-overlong\r\n")

            # A bare CR poisons only its own line. Invalid UTF-8 takes the
            # documented Latin-1 fallback, and C0 formatting bytes sanitize.
            conn.sendall(
                b":peer!u@h PRIVMSG #m7 :drop-me\rX\r\n"
                b":peer!u@h PRIVMSG #m7 :latin-\xff-fallback\r\n"
                b":peer!u@h PRIVMSG #m7 :c0-\x03" b"04red\x00-safe\r\n"
            )

            # Split CRLF and a UTF-8 scalar across writes.
            conn.sendall(b":peer!u@h PRIVMSG #m7 :split-caf\xc3")
            pump(master, conn, screen, wire, 0.05)
            conn.sendall(b"\xa9\r")
            pump(master, conn, screen, wire, 0.05)
            conn.sendall(b"\n")

            # Exceed both the buffer count and one actor tick without making
            # the test so large that sanitizers become impractical.
            for channel in range(24):
                conn.sendall(f":probe!u@h JOIN #f{channel}\r\n".encode())
            burst = b"".join(
                f":peer!u@h PRIVMSG #m7 :burst-{i}\r\n".encode()
                for i in range(400)
            )
            conn.sendall(burst)

            # Resize to the smallest supported geometry and back while data is
            # pending. The final marker and PONG prove continued service.
            fcntl.ioctl(check_fd, termios.TIOCSWINSZ,
                        struct.pack("HHHH", 1, 1, 0, 0))
            os.kill(proc.pid, signal.SIGWINCH)
            pump(master, conn, screen, wire, 0.1)
            fcntl.ioctl(check_fd, termios.TIOCSWINSZ,
                        struct.pack("HHHH", 90, 200, 0, 0))
            os.kill(proc.pid, signal.SIGWINCH)
            marker_targets = [b"#m7"] + [f"#f{i}".encode() for i in range(24)]
            conn.sendall(
                b"".join(
                    b":peer!u@h PRIVMSG " + target
                    + b" :hostile-survived\r\n"
                    for target in marker_targets
                )
                + b"PING :hostile-token\r\n"
            )
            pump(master, conn, screen, wire, 5.0)

            if proc.poll() is None:
                os.write(master, b"/quit hostile-done\r")
            deadline = time.monotonic() + 15.0
            while proc.poll() is None and time.monotonic() < deadline:
                drain(master, screen)
                recv_into(conn, wire)
                time.sleep(0.01)
            hung = proc.poll() is None
            if hung:
                proc.kill()
                proc.wait()
            drain(master, screen)
            recv_into(conn, wire)
            after = termios.tcgetattr(check_fd)
            errors.seek(0)
            diagnostics = errors.read()
        finally:
            if conn is not None:
                conn.close()
            server.close()
            os.close(master)
            os.close(check_fd)

    restored = bool(after[3] & termios.ICANON) == bool(before[3] & termios.ICANON)
    restored = restored and (
        bool(after[3] & termios.ECHO) == bool(before[3] & termios.ECHO)
    )
    pong = b"PONG :hostile-token" in wire
    marker = b"hostile-survived" in screen
    sanitizer_clean = not any(
        needle in diagnostics
        for needle in (
            b"AddressSanitizer",
            b"UndefinedBehaviorSanitizer",
            b"runtime error:",
        )
    )
    ok = (
        not hung
        and proc.returncode == 0
        and pong
        and marker
        and restored
        and sanitizer_clean
    )
    print(
        f"hostile exit={proc.returncode} hung={hung} pong={pong} "
        f"marker={marker} restored={restored} sanitizer_clean={sanitizer_clean}"
    )
    if diagnostics:
        print(diagnostics.decode("utf-8", "replace"), file=sys.stderr)
    if not ok:
        return 1
    print("hostile=ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
