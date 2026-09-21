#!/usr/bin/env python3
"""Supervisor check for H3: the server closes the connection.

usage: eof_pty.py ./build/birc

(-) on 8fc65a0 the UI is gone within 4 s of the close ([?1049l).
(+) the UI is still alive 4 s later, shows disconnected, reacts to keys,
    and /quit exits 0 with the terminal restored.

Process-alive is not UI-alive while boot_clock lingers 8 s (H6). Detect
UI shutdown by the [?1049l restore sequence.
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
    t0 = time.time()
    proc = subprocess.Popen(
        [birc, "--connect", "127.0.0.1", "--port", str(port), "--nick", "probe",
         "--channel", "#t", "--frames", "20000"],
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    out = bytearray()
    conn, _ = srv.accept()
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    end = time.time() + 1.5
    while time.time() < end:
        drain(master, out)
        time.sleep(0.05)
    conn.settimeout(0.2)
    try:
        while conn.recv(65536):
            pass
    except (socket.timeout, OSError):
        pass
    conn.shutdown(socket.SHUT_RDWR)
    conn.close()                      # server goes away -> clean FIN -> Eof
    t_close = time.time()
    end = time.time() + 4.0
    while time.time() < end and proc.poll() is None:
        drain(master, out)
        time.sleep(0.05)
    alive_after_eof = b"[?1049l" not in bytes(out)   # UI still owns the terminal
    died_after = None if alive_after_eof else round(time.time() - t_close, 1)
    mark = len(out)
    if alive_after_eof:
        os.write(master, b"zz")       # does the UI still react to keys?
        end = time.time() + 1.0
        while time.time() < end:
            drain(master, out)
            time.sleep(0.05)
    reacts = alive_after_eof and b"z" in bytes(out[mark:])
    if proc.poll() is None:
        os.write(master, b"\x7f\x7f/quit\r")
    end = time.time() + 12
    while time.time() < end and proc.poll() is None:
        drain(master, out)
        time.sleep(0.05)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    drain(master, out)
    text = out.decode("utf-8", "replace")
    plain = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", " ", text)
    words = sorted(set(re.findall(r"[A-Za-z][A-Za-z_.:-]{3,}", plain)))
    print("words painted:", " ".join(words)[:700])
    print(f"ui_alive_4s_after_eof={alive_after_eof} died_after={died_after}s ui_reacts_to_keys={reacts}")
    print(f"shows_disconnected={'disconnected' in text} deadlock_msg={'deadlock' in text} "
          f"birc_ok={'birc=ok' in text} restored={'[?1049l' in text}")
    print(f"exit={proc.returncode} hung_on_quit={hung} wall={time.time() - t0:.1f}s")
    ok = (
        alive_after_eof
        and reacts
        and ("disconnected" in text)
        and ("deadlock" not in text)
        and (proc.returncode == 0)
        and (not hung)
        and ("[?1049l" in text)
        and ("birc=ok" in text)
    )
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("eof_pty: UI did not stay alive after server close", file=sys.stderr)
        return 1
    print("eof_pty=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
