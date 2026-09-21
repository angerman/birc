#!/usr/bin/env python3
"""T7 live minus cases: refused, 433, close mid-line, split line, non-UTF-8.

usage: live_minus.py ./build/birc
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


def listen():
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    srv.settimeout(20)
    return srv, srv.getsockname()[1]


def spawn(birc, args):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [birc, *args],
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    return master, proc


def quit_wait(master, proc, out, secs=8.0):
    if proc.poll() is None:
        os.write(master, b"/quit\r")
    t = time.time()
    while proc.poll() is None and time.time() - t < secs:
        drain(master, out)
        time.sleep(0.05)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    drain(master, out)
    return hung


def case_refused(birc) -> bool:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    master, proc = spawn(
        birc,
        ["--connect", "127.0.0.1", "--port", str(port), "--nick", "probe",
         "--channel", "#t", "--frames", "20000"],
    )
    out = bytearray()
    t = time.time()
    while proc.poll() is None and time.time() - t < 8:
        drain(master, out)
        time.sleep(0.05)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    os.close(master)
    print("refused: exit", proc.returncode, "hung", hung, "wall", round(time.time() - t, 1))
    return (not hung) and proc.returncode != 0


def case_433(birc) -> bool:
    srv, port = listen()
    master, proc = spawn(
        birc,
        ["--connect", "127.0.0.1", "--port", str(port), "--nick", "probe",
         "--channel", "#t", "--frames", "20000"],
    )
    out = bytearray()
    conn, _ = srv.accept()
    conn.settimeout(0.4)
    buf = b""
    deadline = time.time() + 6
    while time.time() < deadline and b"NICK probe" not in buf:
        drain(master, out)
        try:
            chunk = conn.recv(4096)
            if chunk:
                buf += chunk
        except (socket.timeout, OSError):
            pass
    conn.sendall(b":irc.example.net 433 * probe :Nickname is already in use\r\n")
    deadline = time.time() + 4
    while time.time() < deadline and b"NICK probe_" not in buf:
        drain(master, out)
        try:
            chunk = conn.recv(4096)
            if chunk:
                buf += chunk
        except (socket.timeout, OSError):
            pass
    hung = quit_wait(master, proc, out)
    conn.close()
    srv.close()
    os.close(master)
    ok = b"NICK probe_" in buf and not hung
    print("433: retry", b"NICK probe_" in buf, "hung", hung)
    return ok


def case_midline(birc) -> bool:
    srv, port = listen()
    master, proc = spawn(
        birc,
        ["--connect", "127.0.0.1", "--port", str(port), "--nick", "probe",
         "--channel", "#t", "--frames", "20000"],
    )
    out = bytearray()
    conn, _ = srv.accept()
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    t = time.time()
    while time.time() - t < 0.8:
        drain(master, out)
        time.sleep(0.05)
    conn.sendall(b":a!a@h PRIVMSG #t :partial")
    t = time.time()
    while time.time() - t < 0.4:
        drain(master, out)
        time.sleep(0.05)
    conn.settimeout(0.2)
    try:
        while conn.recv(65536):
            pass
    except (socket.timeout, OSError):
        pass
    conn.shutdown(socket.SHUT_RDWR)
    conn.close()
    srv.close()
    t_close = time.time()
    while time.time() - t_close < 4.0:
        drain(master, out)
        time.sleep(0.05)
    alive = b"[?1049l" not in bytes(out) and proc.poll() is None
    hung = quit_wait(master, proc, out)
    os.close(master)
    ok = alive and not hung and proc.returncode == 0 and b"birc=ok" in out
    print("midline: ui_alive", alive, "hung", hung, "birc_ok", b"birc=ok" in out)
    return ok


def case_split(birc) -> bool:
    srv, port = listen()
    master, proc = spawn(
        birc,
        ["--connect", "127.0.0.1", "--port", str(port), "--nick", "probe",
         "--channel", "#t", "--frames", "20000"],
    )
    out = bytearray()
    conn, _ = srv.accept()
    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    conn.sendall(b":probe!p@h JOIN #t\r\n")
    t = time.time()
    while time.time() - t < 1.2:
        drain(master, out)
        time.sleep(0.05)
    conn.sendall(b":a!a@h PRIVMSG #t :splitA")
    t = time.time()
    while time.time() - t < 0.4:
        drain(master, out)
        time.sleep(0.05)
    conn.sendall(b" splitB\r\n")
    t = time.time()
    while time.time() - t < 1.0:
        drain(master, out)
        time.sleep(0.05)
    hung = quit_wait(master, proc, out)
    conn.close()
    srv.close()
    os.close(master)
    text = out.decode("utf-8", "replace")
    plain = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", " ", text)
    painted = "splitA splitB" in plain
    print("split: painted", painted, "hung", hung)
    return painted and not hung


def case_latin1(birc) -> bool:
    srv, port = listen()
    master, proc = spawn(
        birc,
        ["--connect", "127.0.0.1", "--port", str(port), "--nick", "probe",
         "--channel", "#t", "--frames", "20000"],
    )
    out = bytearray()
    conn, _ = srv.accept()
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    conn.sendall(b":probe!p@h JOIN #t\r\n")
    t = time.time()
    while time.time() - t < 1.2:
        drain(master, out)
        time.sleep(0.05)
    conn.sendall(b":a!a@h PRIVMSG #t :lat" + bytes([0xE9]) + b"n1\r\n")
    t = time.time()
    while time.time() - t < 1.0:
        drain(master, out)
        time.sleep(0.05)
    hung = quit_wait(master, proc, out)
    conn.close()
    srv.close()
    os.close(master)
    text = out.decode("utf-8", "replace")
    painted = "latén1" in text
    print("latin1: painted", painted, "hung", hung, "fffd", "lat\ufffdn1" in text)
    return painted and not hung


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    a = case_refused(birc)
    b = case_433(birc)
    c = case_midline(birc)
    d = case_split(birc)
    e = case_latin1(birc)
    ok = a and b and c and d and e
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("live_minus: refused/433/midline/split/latin1 mismatch", file=sys.stderr)
        return 1
    print("live_minus=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
