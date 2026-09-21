#!/usr/bin/env python3
"""H7: UTF-8 char split across two TCP writes; Latin-1 fallback; whole CJK.

usage: utf8_split_pty.py ./build/birc
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


def pump(master, out, secs):
    end = time.time() + secs
    while time.time() < end:
        drain(master, out)
        time.sleep(0.03)


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
    out = bytearray()
    conn, _ = srv.accept()
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n:probe!p@h JOIN #t\r\n")
    pump(master, out, 1.2)

    def wipe():
        conn.sendall(b":w!w@h PRIVMSG #t :" + b"W" * 40 + b"\r\n")
        pump(master, out, 0.4)

    # Wipe the bottom row before each probe so TimUI dirty-cell skip cannot
    # hide letters that overlap a previous line (café vs naïve share 'a').
    conn.sendall(b":a!a@h PRIVMSG #t :caf\xc3")
    pump(master, out, 0.5)
    conn.sendall(b"\xa9 split\r\n")
    pump(master, out, 0.8)
    wipe()
    conn.sendall(b":a!a@h PRIVMSG #t :na\xefve latin1\r\n")
    pump(master, out, 0.8)
    wipe()
    conn.sendall(b":a!a@h PRIVMSG #t :\xe6\xbc\xa2 cjk whole\r\n")
    pump(master, out, 0.8)
    os.write(master, b"/quit\r")
    t = time.time()
    while proc.poll() is None and time.time() - t < 15:
        drain(master, out)
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
    text = out.decode("utf-8", "replace")
    cafe = "café split" in text
    naive = "naïve latin1" in text
    han = "漢 cjk whole" in text
    print("split  'café split'  painted:", cafe, "| U+FFFD before ' split':", "� split" in text or "caf�" in text)
    print("latin1 'naïve latin1' painted:", naive, "| as U+FFFD:", "na�ve latin1" in text)
    print("cjk    '漢 cjk whole' painted:", han)
    plain = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "\n", text)
    for ln in plain.split("\n"):
        if any(k in ln for k in ("split", "latin1", "cjk")):
            print("DUMP:", repr(ln.strip())[:120])
    print("exit =", proc.returncode)
    ok = cafe and naive and han
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("utf8_split_pty: UTF-8/Latin-1 paint mismatch", file=sys.stderr)
        return 1
    print("utf8_split_pty=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
