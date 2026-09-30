#!/usr/bin/env python3
"""History must be isolated by host and port, including before IRC welcome."""
from __future__ import annotations

from contextlib import contextmanager
import fcntl
import os
import pty
import socket
import struct
import subprocess
import sys
import tempfile
import termios

from history_pty import drain_some, strip_ansi, wait_for


@contextmanager
def listening():
    with socket.socket() as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(8)
        yield server


@contextmanager
def client(birc: str, server: socket.socket, path: str):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
    process = subprocess.Popen(
        [birc, "--connect", "127.0.0.1", "--port", str(server.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "20000"],
        stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": path},
    )
    os.close(slave)
    connection = None
    try:
        connection, _ = server.accept()
        yield master, connection
        os.write(master, b"/quit\r")
        assert process.wait(timeout=5) == 0, "client exited nonzero"
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=3)
        if connection is not None:
            connection.close()
        os.close(master)


def paint(fd: int, text: str, accumulated: bytearray | None = None) -> bytearray:
    ok, data = wait_for(fd, lambda plain: text in plain, accumulated=accumulated)
    assert ok, f"missing {text!r}; output:\n{strip_ansi(data)}"
    return data


def initial(birc: str, server: socket.socket, path: str, label: str, other: str):
    with client(birc, server, path) as (master, connection):
        before = paint(master, "connecting")
        before.extend(drain_some(master, 0.2))
        assert other not in strip_ansi(before), "foreign history visible before welcome"
        connection.sendall(f":endpoint 001 probe :{label}-control\r\n".encode())
        data = paint(master, f"{label}-control", before)
        connection.sendall(
            f":probe!p@h JOIN #t\r\n:alice!a@h PRIVMSG #t :{label}-chat\r\n".encode()
        )
        data = paint(master, f"{label}-chat", data)
        assert other not in strip_ansi(data), "foreign history visible after welcome"


def restored(birc: str, server: socket.socket, path: str, label: str, other: str):
    with client(birc, server, path) as (master, _):
        data = paint(master, f"{label}-control")
        data = paint(master, "Reconnected:", data)
        assert other not in strip_ansi(data), "foreign control history restored"
        os.write(master, b"\x1b[1;2C")
        data = paint(master, f"{label}-chat", data)
        assert other not in strip_ansi(data), "foreign chat history restored"


def switched(birc: str, a: socket.socket, b: socket.socket, path: str):
    # One process must load each changed endpoint without replaying its rows
    # as new history. Each load must finish before the new server's welcome.
    with client(birc, a, path) as (master, first):
        paint(master, "endpoint-A-secret-control")
        first.sendall(b":endpoint 001 probe :switch-A-ready\r\n")
        paint(master, "switch-A-ready")
        os.write(master, f"/connect 127.0.0.1 {b.getsockname()[1]}\r".encode())
        second, _ = b.accept()
        with second:
            paint(master, "endpoint-B-secret-control")
            os.write(master, b"\x1b[1;2C")
            data = paint(master, "endpoint-B-secret-chat")
            assert "endpoint-A-secret" not in strip_ansi(data), "old endpoint chat survived /connect"
            second.sendall(
                b":endpoint 001 probe :switch-B-ready\r\n"
                b":alice!a@h PRIVMSG #t :switch-B-live\r\n"
            )
            paint(master, "switch-B-live")
            os.write(master, f"/connect 127.0.0.1 {a.getsockname()[1]}\r".encode())
            third, _ = a.accept()
            with third:
                paint(master, "endpoint-A-secret-control")
                os.write(master, b"\x1b[1;2C")
                data = paint(master, "endpoint-A-secret-chat")
                assert "endpoint-B-secret" not in strip_ansi(data), "foreign chat survived return /connect"


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    with tempfile.TemporaryDirectory(prefix="birc-history-endpoints-") as folder:
        path = os.path.join(folder, "history.log")
        # Keep both listeners open: reconnects use exactly the original port.
        with listening() as a, listening() as b:
            assert a.getsockname()[1] != b.getsockname()[1]
            initial(birc, a, path, "endpoint-A-secret", "endpoint-B-secret")
            initial(birc, b, path, "endpoint-B-secret", "endpoint-A-secret")
            restored(birc, a, path, "endpoint-A-secret", "endpoint-B-secret")
            restored(birc, b, path, "endpoint-B-secret", "endpoint-A-secret")
            switched(birc, a, b, path)
            with open(path, encoding="utf-8") as source:
                records = source.read().splitlines()
            for server, label, other in (
                (a, "endpoint-A-secret", "endpoint-B-secret"),
                (b, "endpoint-B-secret", "endpoint-A-secret"),
            ):
                endpoint = f"127.0.0.1:{server.getsockname()[1]}"
                own = [record for record in records if record.split("\t")[1] == endpoint]
                assert sum(f"{label}-chat" in record for record in own) == 1, "restored chat was saved twice"
                assert sum(f"{label}-control" in record for record in own) == 1, "restored control was saved twice"
                assert not any(other in record for record in own), "history stored under wrong endpoint"
                assert not any("Reconnected:" in record for record in own), "marker was persisted"
    print("history_endpoints=ok")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print(f"history_endpoints: {error}", file=sys.stderr)
        raise SystemExit(1)
