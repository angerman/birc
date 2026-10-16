#!/usr/bin/env python3
"""M16.4 live IRCv3 typing indicator lifecycle.

This is a real PTY and loopback-server test. It verifies capability request,
active/done repaint, active timeout, paused persistence, and muted-message
clear. Each assertion reads output produced after its triggering event, so an
earlier paint cannot make a later assertion pass.

usage: typing.py ./build/birc
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

# TimUI writes only changed terminal cells, so a full sentence can be split by
# cursor-position escapes. The pure view golden checks the exact sentence;
# the live PTY checks the newly painted nick on each protocol transition.
TYPING = b"alice"
STATUS = b"/connect"


def drain(fd: int, sink: bytearray) -> None:
    while True:
        ready, _, _ = select.select([fd], [], [], 0)
        if not ready:
            return
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return
        if not chunk:
            return
        sink.extend(chunk)


def settle(fd: int, sink: bytearray, duration: float = 0.2) -> None:
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        drain(fd, sink)
        time.sleep(0.01)


def wait_for(fd: int, needle: bytes, timeout: float) -> bytes:
    out = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        drain(fd, out)
        if needle in out:
            settle(fd, out)
            return bytes(out)
        time.sleep(0.02)
    drain(fd, out)
    raise AssertionError(
        f"did not paint {needle!r} within {timeout:.1f}s; bytes={len(out)} "
        f"alice={b'alice' in out} typing={b'typing' in out} "
        f"status={STATUS in out}; tail={bytes(out[-1000:])!r}"
    )


def assert_absent(fd: int, needle: bytes, duration: float) -> None:
    out = bytearray()
    deadline = time.monotonic() + duration
    while time.monotonic() < deadline:
        drain(fd, out)
        if needle in out:
            raise AssertionError(f"painted {needle!r} before {duration:.1f}s")
        time.sleep(0.02)


def recv_registration(conn: socket.socket, master: int) -> bytes:
    got = bytearray()
    ignored = bytearray()
    deadline = time.monotonic() + 4.0
    conn.setblocking(False)
    while time.monotonic() < deadline:
        drain(master, ignored)
        ready, _, _ = select.select([conn], [], [], 0.05)
        if ready:
            chunk = conn.recv(65536)
            if not chunk:
                break
            got.extend(chunk)
        if b"USER probe" in got and b"CAP REQ :message-tags" in got:
            return bytes(got)
    return bytes(got)


def recv_until(conn: socket.socket, master: int, needle: bytes, timeout: float) -> bytes:
    got = bytearray()
    ignored = bytearray()
    deadline = time.monotonic() + timeout
    conn.setblocking(False)
    while time.monotonic() < deadline:
        drain(master, ignored)
        ready, _, _ = select.select([conn], [], [], 0.05)
        if ready:
            chunk = conn.recv(65536)
            if not chunk:
                break
            got.extend(chunk)
        if needle in got:
            return bytes(got)
    raise AssertionError(f"did not receive {needle!r}; got={bytes(got)!r}")


def quit_wait(master: int, proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is None:
        os.write(master, b"/quit\r")
    deadline = time.monotonic() + 8.0
    sink = bytearray()
    while proc.poll() is None and time.monotonic() < deadline:
        drain(master, sink)
        time.sleep(0.05)
    if proc.poll() is None:
        raise AssertionError("client did not exit after /quit")
    if proc.returncode != 0:
        raise AssertionError(f"client exited with {proc.returncode}")


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
            "--plain",
            "--connect",
            "127.0.0.1",
            "--port",
            str(port),
            "--nick",
            "probe",
            "--channel",
            "#t",
            "--frames",
            "0",
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_PREFERENCES": "none", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn: socket.socket | None = None
    try:
        conn, _ = srv.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        registration = recv_registration(conn, master)
        assert b"CAP LS 302\r\n" in registration
        assert b"CAP REQ :message-tags\r\n" in registration

        conn.setblocking(True)
        conn.sendall(b":irc.example 001 probe :Welcome\r\n")
        recv_until(conn, master, b"JOIN #t\r\n", 3.0)
        conn.setblocking(True)
        # The self-JOIN and typing tag share one ordered TCP stream. Do not
        # wait for the unchanged footer here: recv_until may already have
        # drained that paint, and TimUI does not repaint unchanged cells.
        conn.sendall(b":probe!p@h JOIN #t\r\n")

        conn.sendall(b"@+typing=active :alice!a@h TAGMSG #t\r\n")
        wait_for(master, TYPING, 2.0)
        conn.sendall(b"@+typing=done :alice!a@h TAGMSG #t\r\n")
        wait_for(master, STATUS, 2.0)

        conn.sendall(b"@+typing=active :alice!a@h TAGMSG #t\r\n")
        wait_for(master, TYPING, 2.0)
        wait_for(master, STATUS, 8.0)

        conn.sendall(b"@+typing=paused :alice!a@h TAGMSG #t\r\n")
        wait_for(master, TYPING, 2.0)
        assert_absent(master, STATUS, 7.0)

        conn.sendall(b"@+typing=done :alice!a@h TAGMSG #t\r\n")
        wait_for(master, STATUS, 2.0)
        os.write(master, b"/mute alice\r")
        wait_for(master, b"muted alice", 2.0)
        conn.sendall(b"@+typing=active :alice!a@h TAGMSG #t\r\n")
        wait_for(master, TYPING, 2.0)
        conn.sendall(b":alice!a@h PRIVMSG #t :this line is muted\r\n")
        cleared = wait_for(master, STATUS, 2.0)
        assert b"this line is muted" not in cleared

        quit_wait(master, proc)
        print("typing_pty=ok")
        return 0
    except (AssertionError, OSError) as exc:
        print(f"typing_pty: FAIL: {exc}", file=sys.stderr)
        return 1
    finally:
        if conn is not None:
            try:
                conn.close()
            except OSError:
                pass
        srv.close()
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


if __name__ == "__main__":
    sys.exit(main())
