#!/usr/bin/env python3
"""A concurrent paste, network paints, and resize retain one input owner.

(-) Non-key paints used to add watcher keys. Their duplicate ACKs parked
the UI after the paste, so PING needed another terminal key to progress.
(+) Exact edited paste lines arrive in order, concurrent network work
finishes without more terminal input, then /quit sends one QUIT. The
channel seam separately proves queued events run before a paste tail.
That seam forces the old deadlock; this PTY case checks completion under
mixed input without claiming a deterministic native-event schedule.
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import threading
import time


def collect(master: int, conn: socket.socket, wire: bytearray,
            predicate, seconds: float) -> None:
    deadline = time.monotonic() + seconds
    while not predicate(bytes(wire)) and time.monotonic() < deadline:
        readable, _, _ = select.select([master, conn], [], [], 0.02)
        for source in readable:
            try:
                data = os.read(master, 65536) if source == master else conn.recv(65536)
            except (BlockingIOError, OSError):
                continue
            if source != master and data:
                wire.extend(data)


def messages(wire: bytes) -> list[bytes]:
    return [line for line in wire.split(b"\r\n") if line.startswith(b"PRIVMSG #t :")]


def case(binary: str, overlap: bool) -> None:
    count = 300 if overlap else 1
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(5)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [binary, "--plain", "--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
         "--nick", "probe", "--channel", "#t", "--frames", "0"],
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"},
    )
    os.close(slave)
    conn = None
    feeder = None
    stop = threading.Event()
    errors: list[Exception] = []
    wire = bytearray()
    try:
        conn, _ = listener.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        conn.setblocking(False)
        collect(master, conn, wire, lambda w: b"USER probe" in w, 3)
        assert b"USER probe" in wire, "registration missing"
        conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
        collect(master, conn, wire, lambda w: b"JOIN #t\r\n" in w, 3)
        assert b"JOIN #t\r\n" in wire, "JOIN missing"
        want = [f"PRIVMSG #t :L{i:03d}".encode() for i in range(count)]
        # Backspace and arrows are deferred alongside the Enter-separated tail.
        payload = b"".join(f"L{i:03d}X".encode() + b"\x7f\x1b[D\x1b[C\r"
                           for i in range(count))
        fcntl.fcntl(master, fcntl.F_SETFL, fcntl.fcntl(master, fcntl.F_GETFL) | os.O_NONBLOCK)

        def paint_stream() -> None:
            try:
                for index in range(120):
                    if stop.is_set():
                        return
                    conn.sendall(f":carol!u@h PRIVMSG #t :paint{index:03d}\r\n".encode())
                    if index == 0:
                        conn.sendall(b"PING :during-input\r\n")
                    if index % 2 == 0:
                        os.kill(proc.pid, signal.SIGWINCH)
                    stop.wait(0.002)
            except Exception as error:
                errors.append(error)

        offset = 0
        deadline = time.monotonic() + 8
        while offset < len(payload) and time.monotonic() < deadline:
            try:
                offset += os.write(master, payload[offset:])
            except BlockingIOError:
                collect(master, conn, wire, lambda _: False, 0.02)
            if overlap and feeder is None:
                feeder = threading.Thread(target=paint_stream, daemon=True)
                feeder.start()
        assert offset == len(payload), (
            f"paste fixture reached {offset}/{len(payload)} bytes, "
            f"messages={len(messages(bytes(wire)))}, "
            f"pong={b'PONG :during-input' in wire}, exit={proc.poll()}")
        collect(master, conn, wire, lambda w: len(messages(w)) >= count, 8)
        assert messages(bytes(wire)) == want, (
            f"overlap={overlap}: paste lost or reordered lines: {len(messages(bytes(wire)))}/{count}")
        if feeder is not None:
            feeder.join(timeout=2)
            assert not feeder.is_alive(), "network fixture did not finish"
            assert not errors, f"network fixture failed: {errors}"
            collect(master, conn, wire, lambda w: b"PONG :during-input\r\n" in w, 2)
            assert b"PONG :during-input\r\n" in wire, "network work starved during the paste"
        # No terminal input can release a wrongly blocked duplicate ACK here.
        conn.sendall(b"PING :after-input\r\n")
        collect(master, conn, wire, lambda w: b"PONG :after-input\r\n" in w, 2)
        assert b"PONG :after-input\r\n" in wire, (
            f"overlap={overlap}: PING stalled after paste without another terminal key")
        os.write(master, b"/quit\r")
        collect(master, conn, wire, lambda w: b"QUIT" in w, 2)
        proc.wait(timeout=2)
        assert proc.returncode == 0, f"client exit={proc.returncode}"
        assert sum(line.startswith(b"QUIT") for line in wire.split(b"\r\n")) == 1
        print(f"input_fairness: overlap={overlap} exact={count} pong=ok quit=ok")
    finally:
        stop.set()
        if feeder is not None:
            feeder.join(timeout=2)
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
        if conn is not None:
            conn.close()
        listener.close()
        os.close(master)


def main() -> None:
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    case(binary, False)
    case(binary, True)
    print("input_fairness=ok")


if __name__ == "__main__":
    main()
