#!/usr/bin/env python3
"""Measure the unchanged ordinary output-stall/progress traffic, not a gate.

Run only against committed BIRC_FRAME_PROFILE instrumentation. PONG latency
and phase averages are observations; the original tests keep their assertions.
The Make driver supplies an outer 90-second timeout. Each child is bounded,
killed and reaped on failure. stderr is separate from the unread terminal.
"""
from __future__ import annotations

import fcntl
import json
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
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "pty"))
from output_stall import drain, receive

PROFILE = re.compile(
    rb"birc_profile frames=(\d+) prepare_us=(\d+) begin_us=(\d+) "
    rb"draw_us=(\d+) end_us=(\d+) view_us=(\d+)"
)
PHASES = ("frames", "prepare_us", "begin_us", "draw_us", "end_us", "view_us")


def remaining(deadline: float, limit: float) -> float:
    left = min(limit, deadline - time.monotonic())
    if left <= 0:
        raise TimeoutError("output profile case deadline expired")
    return left


def case(binary: str, mode: str, whole_end: float) -> None:
    start = time.monotonic()
    deadline = min(start + 35, whole_end)
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    server.settimeout(remaining(deadline, 5))
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
    proc = None
    conn = None
    try:
        proc = subprocess.Popen(
            [binary, "--plain", "--connect", "127.0.0.1", "--port", str(server.getsockname()[1]),
             "--nick", "probe", "--channel", "#t", "--frames", "0"],
            stdin=slave, stdout=slave, stderr=subprocess.PIPE,
            env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none",
                 "BIRC_IMAGES": "off", "BIRC_FRAME_PROFILE": "1"},
        )
        os.close(slave)
        slave = -1
        conn, _ = server.accept()
        conn.settimeout(remaining(deadline, 2))
        if mode == "progress":
            assert b"USER probe" in receive(conn, b"USER probe", remaining(deadline, 2))
        conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
        drain(master, remaining(deadline, 0.8 if mode == "stall" else 0.6))
        registered = receive(conn, b"JOIN #t", remaining(deadline, 2))
        assert b"JOIN #t" in registered, "fixture did not register/join"
        if mode == "stall":
            assert b"USER probe" in registered
            for index in range(500):
                remaining(deadline, 1)
                conn.sendall((f":a!u@h PRIVMSG #t :{index:03d} " + "x" * 100 + "\r\n").encode())
                time.sleep(0.005)
            time.sleep(0.2)
            # Diff output may replace spaces with cursor moves. Observe the
            # distinctive final index, not a reconstructed terminal screen.
            marker = b"499"
            ping = b"PING :output-ordinary\r\n"
            pong = b"PONG :output-ordinary"
            original_limit = 0.8
        else:
            for index in range(199):
                remaining(deadline, 1)
                conn.sendall(f":a!u@h PRIVMSG #t :row{index:03d} ".encode() + b"x" * 160 + b"\r\n")
            marker = b"PROGRESS-END"
            ping = b":a!u@h PRIVMSG #t :PROGRESS-END\r\nPING :full-progress\r\n"
            pong = b"PONG :full-progress"
            original_limit = 1.0

        # Preserve the unread terminal through the entire measured PONG wait.
        ping_at = time.monotonic()
        conn.sendall(ping)
        wire = bytearray(receive(conn, pong, remaining(deadline, 15)))
        pong_at = time.monotonic() if pong in wire else None
        pong_while_unread = pong_at is not None
        painted = bytearray()
        resume_end = time.monotonic() + remaining(deadline, 6)
        while time.monotonic() < resume_end:
            painted.extend(drain(master, min(0.02, resume_end - time.monotonic())))
            if select.select([conn], [], [], 0)[0]:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                wire.extend(chunk)
                if pong_at is None and pong in wire:
                    pong_at = time.monotonic()
            if marker in painted and pong_at is not None:
                break

        os.write(master, b"/quit\r")
        quit_end = time.monotonic() + remaining(deadline, 3)
        stderr = bytearray()
        assert proc.stderr is not None
        while time.monotonic() < quit_end:
            painted.extend(drain(master, min(0.02, quit_end - time.monotonic())))
            if select.select([proc.stderr], [], [], 0)[0]:
                chunk = os.read(proc.stderr.fileno(), 4096)
                if len(stderr) + len(chunk) > 4096:
                    raise RuntimeError("unexpectedly large profile stderr")
                stderr.extend(chunk)
                if not chunk and proc.poll() is not None:
                    break
        proc.wait(timeout=remaining(deadline, 1))
        match = PROFILE.search(stderr)
        assert proc.returncode == 0, f"profile child exited {proc.returncode}"
        assert match, f"missing committed frame profile: {bytes(stderr)!r}"
        result = dict(zip(PHASES, map(int, match.groups())))
        result.update(
            case=mode,
            case_ms=round(1000 * (time.monotonic() - start), 3),
            pong_ms=None if pong_at is None else round(1000 * (pong_at - ping_at), 3),
            pong_while_unread=pong_while_unread,
            original_limit_ms=int(1000 * original_limit),
            original_limit_met=pong_at is not None and pong_at - ping_at <= original_limit,
            marker=marker in painted,
            terminal_bytes=len(painted),
        )
        print("output_profile " + json.dumps(result, sort_keys=True), flush=True)
    finally:
        if proc is not None:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=2)
            if proc.stderr is not None:
                proc.stderr.close()
        if conn is not None:
            conn.close()
        server.close()
        os.close(master)
        if slave >= 0:
            os.close(slave)


if __name__ == "__main__":
    whole_end = time.monotonic() + 85
    for mode in ("stall", "progress"):
        case(sys.argv[1] if len(sys.argv) > 1 else "./build/birc", mode, whole_end)
