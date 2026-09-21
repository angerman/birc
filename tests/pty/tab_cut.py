#!/usr/bin/env python3
"""A7: tab labels must be cut on a UTF-8 code-point boundary.

(-) birc_str_list fitted then clamped to 63, so a 2-byte é at byte 62..63
    left a dangling C3 (U+FFFD / invalid UTF-8) in the tab strip.
(+) birc_utf8_fit(s, min(len, 63)) backs up to 62.

usage: tab_cut.py ./build/birc
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


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(20)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 120, 0, 0))
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
    conn.settimeout(0.2)
    name = "#" + ("é" * 40)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    conn.sendall(b":probe!p@h JOIN #t\r\n")
    conn.sendall((":probe!p@h JOIN %s\r\n" % name).encode("utf-8"))
    t = time.time()
    while time.time() - t < 1.5:
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
    try:
        conn.close()
    except OSError:
        pass
    srv.close()

    raw = bytes(out)
    dangling = False
    i = 0
    while i < len(raw):
        b = raw[i]
        if b < 0x80:
            i += 1
            continue
        if 0xC2 <= b <= 0xDF:
            if i + 1 >= len(raw) or (raw[i + 1] & 0xC0) != 0x80:
                dangling = True
                break
            i += 2
            continue
        if 0xE0 <= b <= 0xEF:
            if i + 2 >= len(raw) or (raw[i + 1] & 0xC0) != 0x80 or (
                raw[i + 2] & 0xC0
            ) != 0x80:
                dangling = True
                break
            i += 3
            continue
        if 0xF0 <= b <= 0xF4:
            if i + 3 >= len(raw) or any((raw[i + k] & 0xC0) != 0x80 for k in (1, 2, 3)):
                dangling = True
                break
            i += 4
            continue
        i += 1

    text = raw.decode("utf-8", "replace")
    e_count = text.count("é")
    has_fffd = "\ufffd" in text
    print(f"e_count={e_count} dangling={dangling} fffd={has_fffd} exit={proc.returncode}")
    # 31 × é fit in 62 bytes; a mid-code-point cut at 63 yields dangling/FFFD.
    ok = e_count >= 20 and not dangling and not has_fffd
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("tab_cut: tab label split inside a code point", file=sys.stderr)
        return 1
    print("tab_cut=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
