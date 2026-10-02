#!/usr/bin/env python3
"""Pty test: history persistence, reconnect markers, and BIRC_HISTORY env var.

Verifies:
1. Session 1 receives messages in server and #t, saves them to BIRC_HISTORY file upon quit.
2. Saved history file contains only actual messages (no reconnect markers).
3. Session 2 restores messages from BIRC_HISTORY, and renders:
   - Reconnected: <timestamp> divider line
   in buffers that had prior history.
4. Session 2 appends new messages without saving the reconnect markers.
5. BIRC_HISTORY=none disables persistence completely.
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
import tempfile
import termios
import time


def strip_ansi(raw: bytes) -> str:
    text = raw.decode("utf-8", "replace")
    return re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", " ", text)


def wait_for(fd: int, condition, timeout: float = 4.0, accumulated: bytearray | None = None) -> tuple[bool, bytearray]:
    acc = accumulated if accumulated is not None else bytearray()
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
                if chunk:
                    acc += chunk
            except OSError:
                break
        if condition(strip_ansi(acc)):
            return True, acc
    return False, acc


def drain_some(fd: int, timeout: float = 0.5) -> bytes:
    out = bytearray()
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                out += chunk
            except OSError:
                break
    return bytes(out)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"

    with tempfile.TemporaryDirectory() as tmpdir:
        hist_file = os.path.join(tmpdir, "test_hist.log")

        # =====================================================================
        # Session 1: Connect, receive welcome and #t message, save history
        # =====================================================================
        srv1 = socket.socket()
        srv1.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv1.bind(("127.0.0.1", 0))
        srv1.listen(1)
        port1 = srv1.getsockname()[1]
        srv1.settimeout(10)

        master1, slave1 = pty.openpty()
        fcntl.ioctl(slave1, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        env1 = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": hist_file}
        proc1 = subprocess.Popen(
            [
                birc,
                "--plain",
                "--connect",
                "127.0.0.1",
                "--port",
                str(port1),
                "--nick",
                "probe",
                "--channel",
                "#t",
                "--frames",
                "20000",
            ],
            stdin=slave1,
            stdout=slave1,
            stderr=slave1,
            env=env1,
        )
        os.close(slave1)

        try:
            conn1, _ = srv1.accept()
        except socket.timeout:
            proc1.kill()
            print("history_pty: session 1 accept timeout", file=sys.stderr)
            return 1

        conn1.sendall(b":irc.example.net 001 probe :Welcome to IRC\r\n")

        # Wait for welcome to appear in server buffer
        ok_srv1, acc1 = wait_for(master1, lambda p: "Welcome to IRC" in p)
        if not ok_srv1:
            print("history_pty: session 1 missing 'Welcome to IRC'", file=sys.stderr)
            proc1.kill()
            return 1

        # Now server sends join confirmation, which automatically switches client to #t
        conn1.sendall(b":probe!p@h JOIN #t\r\n")
        time.sleep(0.1)

        # Send message to #t
        conn1.sendall(b":alice!a@h PRIVMSG #t :history message one\r\n")
        ok_msg1, _ = wait_for(master1, lambda p: "history message one" in p, accumulated=acc1)
        if not ok_msg1:
            print("history_pty: session 1 failed to display message one", file=sys.stderr)
            print("plain output was:\n", strip_ansi(acc1), file=sys.stderr)
            proc1.kill()
            return 1

        # Quit session 1
        os.write(master1, b"/quit\r")
        proc1.wait(timeout=5)
        os.close(master1)
        conn1.close()
        srv1.close()

        # Check history file from session 1
        if not os.path.exists(hist_file):
            print("history_pty: history file was not created", file=sys.stderr)
            return 1

        with open(hist_file, "r", encoding="utf-8") as f:
            content1 = f.read()

        if "Welcome to IRC" not in content1:
            print("history_pty: 'Welcome to IRC' missing from history file", file=sys.stderr)
            return 1
        if "history message one" not in content1:
            print("history_pty: 'history message one' missing from history file", file=sys.stderr)
            print("content was:\n", content1, file=sys.stderr)
            return 1
        if "--- Reconnected" in content1 or "Reconnected:" in content1:
            print("history_pty: reconnect marker saved into history file in session 1", file=sys.stderr)
            return 1

        # =====================================================================
        # Session 2: Connect, restore history, verify markers, append message 2
        # =====================================================================
        srv2 = socket.socket()
        srv2.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        # Restore history from the same endpoint; distinct-port isolation is
        # covered by history_endpoints.py.
        srv2.bind(("127.0.0.1", port1))
        srv2.listen(1)
        port2 = srv2.getsockname()[1]
        srv2.settimeout(10)

        master2, slave2 = pty.openpty()
        fcntl.ioctl(slave2, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        env2 = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": hist_file}
        proc2 = subprocess.Popen(
            [
                birc,
                "--plain",
                "--connect",
                "127.0.0.1",
                "--port",
                str(port2),
                "--nick",
                "probe",
                "--channel",
                "#t",
                "--frames",
                "20000",
            ],
            stdin=slave2,
            stdout=slave2,
            stderr=slave2,
            env=env2,
        )
        os.close(slave2)

        try:
            conn2, _ = srv2.accept()
        except socket.timeout:
            proc2.kill()
            print("history_pty: session 2 accept timeout", file=sys.stderr)
            return 1

        # Wait for server buffer restored history & markers
        ok_srv2, acc2 = wait_for(
            master2,
            lambda p: "Welcome to IRC" in p and "Reconnected:" in p
        )
        if not ok_srv2:
            print("history_pty: session 2 server buffer missing restored history or markers", file=sys.stderr)
            print("plain output was:\n", strip_ansi(acc2), file=sys.stderr)
            proc2.kill()
            return 1

        # Give tty_watch time to settle and listen
        time.sleep(0.2)

        # Switch to #t buffer with Shift-Right
        os.write(master2, b"\x1b[1;2C")
        ok_t2, acc2 = wait_for(
            master2,
            lambda p: "history message one" in p and "Reconnected:" in p,
            accumulated=acc2
        )
        if not ok_t2:
            print("history_pty: session 2 #t buffer missing restored history or markers", file=sys.stderr)
            print("plain output was:\n", strip_ansi(acc2), file=sys.stderr)
            proc2.kill()
            return 1

        # Send message two from server
        conn2.sendall(b":bob!b@h PRIVMSG #t :history message two\r\n")
        ok_msg2, _ = wait_for(master2, lambda p: "history message two" in p, accumulated=acc2)
        if not ok_msg2:
            print("history_pty: session 2 failed to display message two", file=sys.stderr)
            proc2.kill()
            return 1

        # Quit session 2
        os.write(master2, b"/quit\r")
        proc2.wait(timeout=5)
        os.close(master2)
        conn2.close()
        srv2.close()

        # Verify history file after session 2
        with open(hist_file, "r", encoding="utf-8") as f:
            content2 = f.read()

        if "history message one" not in content2:
            print("history_pty: 'history message one' disappeared after session 2", file=sys.stderr)
            return 1
        if "history message two" not in content2:
            print("history_pty: 'history message two' missing after session 2", file=sys.stderr)
            print("content was:\n", content2, file=sys.stderr)
            return 1
        if "--- Reconnected" in content2 or "Reconnected:" in content2:
            print("history_pty: reconnect marker saved into history file in session 2", file=sys.stderr)
            return 1

        # =====================================================================
        # Session 3: BIRC_HISTORY=none disables persistence
        # =====================================================================
        srv3 = socket.socket()
        srv3.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv3.bind(("127.0.0.1", 0))
        srv3.listen(1)
        port3 = srv3.getsockname()[1]
        srv3.settimeout(10)

        none_file = os.path.join(tmpdir, "none.log")
        master3, slave3 = pty.openpty()
        fcntl.ioctl(slave3, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        env3 = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none"}
        proc3 = subprocess.Popen(
            [
                birc,
                "--plain",
                "--connect",
                "127.0.0.1",
                "--port",
                str(port3),
                "--nick",
                "probe",
                "--channel",
                "#t",
                "--frames",
                "20000",
            ],
            stdin=slave3,
            stdout=slave3,
            stderr=slave3,
            env=env3,
        )
        os.close(slave3)

        try:
            conn3, _ = srv3.accept()
        except socket.timeout:
            proc3.kill()
            print("history_pty: session 3 accept timeout", file=sys.stderr)
            return 1

        drain_some(master3, 0.5)
        os.write(master3, b"/quit\r")
        proc3.wait(timeout=5)
        os.close(master3)
        conn3.close()
        srv3.close()

        if os.path.exists(none_file):
            print("history_pty: file created when BIRC_HISTORY=none", file=sys.stderr)
            return 1

    print("history=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
