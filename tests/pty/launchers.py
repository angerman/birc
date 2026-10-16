#!/usr/bin/env python3
"""URL helpers are reaped, failures are visible, and slow helpers do not park UI."""
from __future__ import annotations

import fcntl
import os
import pty
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

from output_stall import drain, receive
from frame_links import link_point


def child_states(pid: int) -> list[str]:
    listing = subprocess.run(["/bin/ps", "-axo", "ppid=,stat="],
                             check=True, capture_output=True, text=True).stdout
    return [fields[1] for line in listing.splitlines()
            if len(fields := line.split()) == 2 and fields[0] == str(pid)]


def case(binary: str, mode: str, directory: str) -> None:
    log = Path(directory, "opened")
    log.unlink(missing_ok=True)
    helper_pid = Path(directory, "pid")
    helper_pid.unlink(missing_ok=True)
    opener = Path(directory, "open" if sys.platform == "darwin" else "xdg-open")
    opener.unlink(missing_ok=True)
    if mode != "absent":
        script = '#!/bin/sh\nprintf "%s\\n" "$1" >> "$BIRC_LINK_LOG"\n'
        script += ('printf "%s\\n" "$$" > "$BIRC_LAUNCH_PID"\nexec /bin/sleep 3\n'
                   if mode in ("slow", "slowquit") else
                   "exit 7\n" if mode == "failed" else "exit 0\n")
        opener.write_text(script)
        opener.chmod(0o755)
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(8)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    args = ["--connect", "127.0.0.1", "--port", str(listener.getsockname()[1]),
            "--nick", "probe", "--channel", "#t"] if mode in ("slow", "slowquit") else ["--demo"]
    proc = subprocess.Popen(
        [binary, "--plain", *args, "--frames", "0"], stdin=slave, stdout=slave, stderr=slave,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_PREFERENCES": "none", "BIRC_HISTORY": "none",
             "BIRC_LINK_LOG": str(log), "BIRC_LAUNCH_PID": str(helper_pid), "PATH": directory},
    )
    os.close(slave)
    conn = None
    try:
        if mode in ("slow", "slowquit"):
            conn, _ = listener.accept()
            assert b"USER probe" in receive(conn, b"USER probe", 2)
            conn.sendall(b":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n")
            drain(master, 0.4)
            assert b"JOIN #t" in receive(conn, b"JOIN #t", 2)
            conn.sendall(b":carol!u@h PRIVMSG #t :see https://timui.dev\r\n")
        painted = drain(master, 0.6)
        col, row = link_point(painted, "https://timui.dev")
        click = f"\x1b[<0;{col};{row}M\x1b[<0;{col};{row}m".encode()
        output = bytearray()
        for _ in range(8 if mode == "ordinary" else 1):
            os.write(master, click)
            output.extend(drain(master, 0.2))
        if mode == "ordinary":
            assert log.read_text().splitlines() == ["https://timui.dev"] * 8
        if mode in ("slow", "slowquit"):
            # The IO helper starts asynchronously; do not mistake scheduler
            # latency for a missing click. Keep reading the tty while waiting.
            deadline = time.monotonic() + 1.5
            while not log.exists() and time.monotonic() < deadline:
                output.extend(drain(master, 0.02))
            assert log.exists(), f"slow helper did not start: {bytes(output)!r}"
        if mode == "slowquit":
            assert child_states(proc.pid), "fixture helper already finished"
            os.write(master, b"/quit\r")
            proc.wait(timeout=1.5)
            assert proc.returncode == 0, proc.returncode
            # Quit does not cancel external applications. The fake helper is
            # adopted by the OS and exits naturally; leave no fixture behind.
            pid = int(helper_pid.read_text())
            deadline = time.monotonic() + 4
            while subprocess.run(["/bin/ps", "-p", str(pid)], capture_output=True).returncode == 0:
                assert time.monotonic() < deadline, "fake helper did not exit naturally"
                time.sleep(0.05)
            print("launchers slowquit=ok", flush=True)
            return
        if mode == "slow":
            conn.sendall(b"PING :slow-launcher\r\n")
            output.extend(drain(master, 0.1))
            assert b"PONG :slow-launcher" in receive(conn, b"PONG :slow-launcher", 0.6)
            output.extend(drain(master, 2.5))
        else:
            output.extend(drain(master, 0.5))
        if mode in ("failed", "absent", "slow"):
            assert b"cannot open link" in output, f"{mode}: failed helper was not reported"
        states = child_states(proc.pid)
        assert not states, f"{mode}: unreaped/running direct children: {states}"
        os.write(master, b"/quit\r")
        drain(master, 0.2)
        proc.wait(timeout=3)
        assert proc.returncode == 0, proc.returncode
        print(f"launchers {mode}=ok", flush=True)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if conn is not None:
            conn.close()
        listener.close()
        os.close(master)


if __name__ == "__main__":
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    with tempfile.TemporaryDirectory(prefix="birc-launchers-") as directory:
        for mode in ("ordinary", "failed", "absent", "slow", "slowquit"):
            case(binary, mode, directory)
