#!/usr/bin/env python3
"""A3: a TCP RST must keep the UI alive, like a clean FIN.

(-) take_oct.r maps recv Fail to reader_die with no Eof, so RST exits.
(+) UI still alive 4 s later, shows disconnected.

usage: rst.py ./build/birc
"""
from __future__ import annotations

import fcntl
import os
import pty
import re
import select
import socket
import struct
import subprocess
import sys
import termios
import time


def drain(fd, sink):
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            return
        try:
            d = os.read(fd, 65536)
        except OSError:
            return
        if not d:
            return
        sink += d


def run(birc, reset: bool) -> tuple[bool, bool, int | None]:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
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
            "#t",
            "--frames",
            "20000",
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    out = bytearray()
    conn, _ = srv.accept()
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    t = time.time()
    while time.time() - t < 1.2:
        drain(master, out)
        time.sleep(0.05)
    conn.settimeout(0.2)
    try:
        while conn.recv(65536):
            pass
    except (socket.timeout, OSError):
        pass
    if reset:
        conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        conn.close()
    else:
        conn.shutdown(socket.SHUT_RDWR)
        conn.close()
    srv.close()
    t = time.time()
    while time.time() - t < 4.0:
        drain(master, out)
        time.sleep(0.05)
    alive = b"[?1049l" not in bytes(out) and proc.poll() is None
    if alive:
        # "disconnected" is logged on the server buffer; JOIN left us on #t.
        os.write(master, b"\x1b[1;2D")
        t = time.time()
        while time.time() - t < 1.0:
            drain(master, out)
            time.sleep(0.05)
        os.write(master, b"/quit\r")
        t = time.time()
        while proc.poll() is None and time.time() - t < 6:
            drain(master, out)
            time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    drain(master, out)
    os.close(master)
    raw = bytes(out)
    text = raw.decode("utf-8", "replace")
    plain = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", text)
    disc = "disconnected" in plain
    restored = b"[?1049l" in raw
    code = proc.returncode
    print(
        f"reset={reset} ui_alive_4s={alive} shows_disconnected={disc} "
        f"restored={restored} exit={code}"
    )
    return alive, disc, restored, code


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    fin_alive, fin_disc, fin_rest, fin_code = run(birc, False)
    rst_alive, rst_disc, rst_rest, rst_code = run(birc, True)
    if not fin_alive or not rst_alive:
        print("rst: UI died after FIN or RST", file=sys.stderr)
        return 1
    if not fin_disc or not rst_disc:
        print("rst: disconnected not painted after FIN or RST", file=sys.stderr)
        return 1
    if fin_code != 0 or rst_code != 0 or not fin_rest or not rst_rest:
        print("rst: /quit did not exit 0 with restore", file=sys.stderr)
        return 1
    print("rst=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
