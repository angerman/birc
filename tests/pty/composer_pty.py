#!/usr/bin/env python3
"""Supervisor check for C8: type into birc through a pty; read the mock server.

usage: composer_pty.py ./build/birc
Case A: 300 x 'a' + Enter  -> server must get PRIVMSG with 300 a's (was 255).
Case B: "hello" Enter, Up (recall), Down (clear), "x" Enter
        -> server must get "PRIVMSG #t :x", not "...:hellox" / ":hello".
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


def drain(fd):
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            return
        try:
            if not os.read(fd, 65536):
                return
        except OSError:
            return


def pump(conn, master, buf, secs):
    end = time.time() + secs
    while time.time() < end:
        drain(master)
        try:
            d = conn.recv(65536)
            if d:
                buf += d
        except (socket.timeout, BlockingIOError):
            pass
        time.sleep(0.02)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [birc, "--connect", "127.0.0.1", "--port", str(port), "--nick", "probe",
         "--channel", "#t", "--frames", "20000"],
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    conn, _ = srv.accept()
    conn.settimeout(0.01)
    buf = bytearray()
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    pump(conn, master, buf, 1.5)

    def typ(data, gap=0.0):
        os.write(master, data)
        pump(conn, master, buf, 0.4 + gap)

    # Case A
    typ(b"a" * 300)
    typ(b"\r", 0.6)
    # Case B
    typ(b"hello")
    typ(b"\r", 0.4)
    typ(b"\x1b[A", 0.3)   # Up: recall "hello"
    typ(b"\x1b[B", 0.3)   # Down: past newest -> must clear
    typ(b"x")
    typ(b"\r", 0.6)
    typ(b"/quit\r", 1.0)
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    text = bytes(buf).decode("utf-8", "replace")
    msgs = [l for l in text.split("\r\n") if l.startswith("PRIVMSG")]
    a = [m for m in msgs if m.startswith("PRIVMSG #t :aaa")]
    alen = len(a[0].split(":", 1)[1]) if a else -1
    print(f"exit={proc.returncode} privmsgs={len(msgs)}")
    print(f"case A: a-count={alen} (want 300; bug gave 255)")
    tail = [m for m in msgs if not m.startswith("PRIVMSG #t :aaa")]
    print(f"case B: lines after A = {tail} (want ['PRIVMSG #t :hello', 'PRIVMSG #t :x'])")
    ok = alen == 300 and tail == ["PRIVMSG #t :hello", "PRIVMSG #t :x"]
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("composer_pty: composer protocol mismatch", file=sys.stderr)
        return 1
    print("composer_pty=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
