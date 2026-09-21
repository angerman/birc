#!/usr/bin/env python3
"""Local mock IRC: assert NICK/USER/JOIN, PONG, and birc=ok without hanging."""
from __future__ import annotations

import socket
import subprocess
import sys
import time


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: live_mock.py ./build/birc", file=sys.stderr)
        return 2
    birc = sys.argv[1]
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
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
            "#t",
            "--frames",
            "8",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        proc.kill()
        print("live_mock: accept timeout", file=sys.stderr)
        return 1
    conn.settimeout(0.4)
    buf = b""
    deadline = time.time() + 12
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    conn.sendall(b"PING :xyz\r\n")
    while time.time() < deadline:
        try:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buf += chunk
        except (socket.timeout, ConnectionResetError, BrokenPipeError):
            pass
        if proc.poll() is not None:
            break
    try:
        out, _ = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
        out, _ = proc.communicate()
        print("live_mock: birc hung", file=sys.stderr)
        return 1
    conn.close()
    srv.close()
    text = out.decode("utf-8", "replace")
    if proc.returncode != 0:
        print(f"live_mock: exit {proc.returncode}\n{text}", file=sys.stderr)
        return 1
    if "birc=ok" not in text:
        print(f"live_mock: missing birc=ok\n{text}", file=sys.stderr)
        return 1
    if b"NICK probe" not in buf or b"USER probe" not in buf or b"JOIN #t" not in buf:
        print(f"live_mock: missing register in {buf!r}", file=sys.stderr)
        return 1
    if b"PONG :xyz" not in buf:
        print(f"live_mock: missing PONG in {buf!r}", file=sys.stderr)
        return 1
    print("live_mock=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
