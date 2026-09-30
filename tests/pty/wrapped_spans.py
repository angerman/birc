#!/usr/bin/env python3
"""Wrapped OSC-8 targets stay exact; CJK rows retain every visible glyph."""
import fcntl
import os
import pty
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import time

URL = b"https://example.test/very-long-path-for-a-wrapped-link"
WIDE = "甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥"


def drain(fd, seconds):
    out = bytearray()
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            out.extend(chunk)
    return bytes(out)


def receive(conn, master, needle):
    data = bytearray()
    end = time.monotonic() + 5
    conn.setblocking(False)
    while time.monotonic() < end:
        drain(master, 0.05)
        ready, _, _ = select.select([conn], [], [], 0.05)
        if ready:
            chunk = conn.recv(65536)
            if not chunk:
                break
            data.extend(chunk)
            if needle in data:
                conn.setblocking(True)
                return
    raise AssertionError((needle, bytes(data)))


def exact_targets(raw):
    urls = [url for url in re.findall(rb"\x1b\]8;;([^\x1b]*)\x1b\\", raw) if url]
    assert len(urls) >= 2, ("link was not wrapped", urls)
    assert all(url == URL for url in urls), ("wrapped target changed", urls)


def main():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        listener.settimeout(10)
        port = listener.getsockname()[1]
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 28, 50, 0, 0))
        proc = subprocess.Popen(
            [sys.argv[1], "--connect", "127.0.0.1", "--port", str(port),
             "--nick", "probe", "--channel", "#t", "--frames", "0"],
            stdin=slave, stdout=slave, stderr=slave, close_fds=True,
            env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
        )
        os.close(slave)
        conn = None
        try:
            conn, _ = listener.accept()
            receive(conn, master, b"USER probe")
            conn.sendall(b":irc.test 001 probe :Welcome\r\n")
            receive(conn, master, b"JOIN #t\r\n")
            conn.sendall(b":probe!p@h JOIN #t\r\n")
            drain(master, 0.4)
            conn.sendall(b":alice!a@h PRIVMSG #t :" + URL + b"\r\n")
            exact_targets(drain(master, 0.8))

            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 28, 40, 0, 0))
            os.kill(proc.pid, signal.SIGWINCH)
            exact_targets(drain(master, 0.8))

            # Restore enough columns for both the timestamp and hanging indent.
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 28, 50, 0, 0))
            os.kill(proc.pid, signal.SIGWINCH)
            drain(master, 0.5)
            conn.sendall(b":alice!a@h PRIVMSG #t :" + WIDE.encode() + b"\r\n")
            raw = drain(master, 0.8)
            for glyph in WIDE:
                assert glyph.encode() in raw, ("wide glyph clipped from prepared row", glyph, raw)

            os.write(master, b"/quit\r")
            proc.wait(timeout=5)
            assert proc.returncode == 0, proc.returncode
        finally:
            if conn is not None:
                conn.close()
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)
    print("wrapped_spans=ok")


if __name__ == "__main__":
    main()
