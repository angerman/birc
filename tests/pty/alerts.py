#!/usr/bin/env python3
"""Live terminal bell and background-tab alert regression.

An ordinary message marks a background tab with reverse video. Mentions use a
gold background and emit one BEL per received highlight while bell is enabled.
Repaints do not replay BEL, and `/set bell off` suppresses later bells.

usage: alerts.py ./build/birc
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
import termios
import time

BEL = b"\a"


def drain(fd: int, duration: float = 0.4) -> bytes:
    out = bytearray()
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out.extend(chunk)
    return bytes(out)


def recv_until(conn: socket.socket, master: int, needle: bytes) -> bytes:
    got = bytearray()
    deadline = time.monotonic() + 4.0
    conn.setblocking(False)
    while time.monotonic() < deadline:
        drain(master, 0.05)
        ready, _, _ = select.select([conn], [], [], 0.05)
        if ready:
            chunk = conn.recv(65536)
            if not chunk:
                break
            got.extend(chunk)
        if needle in got:
            return bytes(got)
    raise AssertionError(f"did not receive {needle!r}; got={bytes(got)!r}")


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    srv.settimeout(10)
    port = srv.getsockname()[1]

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
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
            "#a",
            "--frames",
            "0",
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn: socket.socket | None = None
    try:
        conn, _ = srv.accept()
        recv_until(conn, master, b"USER probe")
        conn.setblocking(True)
        conn.sendall(b":irc.example 001 probe :Welcome\r\n")
        recv_until(conn, master, b"JOIN #a\r\n")
        conn.setblocking(True)
        conn.sendall(b":probe!p@h JOIN #a\r\n")
        drain(master, 0.5)

        os.write(master, b"/join #b\r")
        recv_until(conn, master, b"JOIN #b\r\n")
        conn.setblocking(True)
        conn.sendall(b":probe!p@h JOIN #b\r\n")
        drain(master, 0.5)

        # Return to #a, leaving #b as a background channel.
        os.write(master, b"\x1b[1;2D")
        drain(master, 0.5)

        conn.sendall(b":alice!a@h PRIVMSG #b :ordinary activity\r\n")
        ordinary = drain(master, 0.8)
        if BEL in ordinary:
            raise AssertionError("ordinary activity emitted BEL")
        if b"#b*" not in ordinary or (b";7m" not in ordinary and b"[7m" not in ordinary):
            raise AssertionError(f"ordinary tab is not reverse-video activity: {ordinary[-1000:]!r}")

        conn.sendall(b":alice!a@h PRIVMSG #b :hello probe\r\n")
        mention1 = drain(master, 0.8)
        if mention1.count(BEL) != 1:
            raise AssertionError(f"first mention BEL count={mention1.count(BEL)}")
        if b"#b!" not in mention1 or b"255;215;0" not in mention1:
            raise AssertionError(f"mention tab is not gold: {mention1[-1000:]!r}")

        conn.sendall(b":alice!a@h PRIVMSG #b :probe again\r\n")
        mention2 = drain(master, 0.8)
        if mention2.count(BEL) != 1:
            raise AssertionError(f"second mention BEL count={mention2.count(BEL)}")

        conn.sendall(b":bob!b@h PRIVMSG probe :hello\r\n")
        private = drain(master, 0.8)
        if private.count(BEL) != 1:
            raise AssertionError(f"private-message BEL count={private.count(BEL)}")
        if b"bob!" not in private:
            raise AssertionError(f"private-message alert tab is missing: {private[-1000:]!r}")

        # A redraw of the same state must not replay the bell.
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 31, 100, 0, 0))
        os.kill(proc.pid, signal.SIGWINCH)
        repaint = drain(master, 0.8)
        if BEL in repaint:
            raise AssertionError("resize repaint replayed BEL")

        os.write(master, b"/set bell off\r")
        drain(master, 0.8)
        conn.sendall(b":alice!a@h PRIVMSG #b :probe while quiet\r\n")
        quiet = drain(master, 0.8)
        if BEL in quiet:
            raise AssertionError("bell-off mention emitted BEL")

        os.write(master, b"/quit\r")
        proc.wait(timeout=8)
        if proc.returncode != 0:
            raise AssertionError(f"client exited with {proc.returncode}")
        print("alerts=ok")
        return 0
    finally:
        if conn is not None:
            conn.close()
        srv.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
