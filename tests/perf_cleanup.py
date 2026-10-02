#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Owned child/socket controls for the live and CPU PTY harness cleanup."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch


def module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(result)
    return result


def run_case(harness, child: Path, ready: Path, failure: str) -> None:
    descriptors = []
    sockets = []
    children = []
    socket_create = socket.socket
    pty_open = harness.pty.openpty
    popen = subprocess.Popen
    fork = os.fork

    class Listener:
        def __init__(self):
            self.sock = socket_create()
            sockets.append(self.sock)

        def __getattr__(self, name):
            return getattr(self.sock, name)

        def accept(self):
            if failure == "accept":
                deadline = time.monotonic() + 3
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                assert ready.exists(), "owned fake child did not start"
                raise socket.timeout("owned fixture timeout")
            connection, address = self.sock.accept()
            sockets.append(connection)
            if failure == "send":
                class FailedSend:
                    def __getattr__(self, name):
                        return getattr(connection, name)

                    def sendall(self, data):
                        raise BrokenPipeError("owned fixture send failure")

                return FailedSend(), address
            return connection, address

    def open_pty():
        pair = pty_open()
        descriptors.extend(pair)
        return pair

    def start(*args, **kwargs):
        process = popen(*args, **kwargs)
        children.append(process.pid)
        return process

    def start_fork():
        pid = fork()
        if pid:
            children.append(pid)
        return pid

    def create_socket(*args, **kwargs):
        return socket_create(*args, **kwargs) if args or kwargs else Listener()

    with patch.object(harness.socket, "socket", create_socket), patch.object(harness.pty, "openpty", open_pty), \
            patch.object(harness.subprocess, "Popen", start) if hasattr(harness, "subprocess") else patch.object(harness.os, "fork", start_fork), \
            patch.object(sys, "argv", ["harness", str(child)]):
        try:
            if hasattr(harness, "subprocess"):
                result = harness.main()
                assert result == (1 if failure == "accept" else 0)
            else:
                harness.run(str(child), "idle", 0.02)
        except (socket.timeout, BrokenPipeError):
            assert failure in ("accept", "send")
        else:
            assert failure != "send", "owned send-failure fixture did not run"

    assert len(children) == 1, children
    pid = children[0]
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        pass
    else:
        # Keep the RED control safe even when testing the old leaking harness.
        os.kill(pid, 9)
        os.waitpid(pid, 0)
        raise AssertionError("failed harness left its owned child alive or unreaped")
    try:
        os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        pass
    else:
        raise AssertionError("owned child was not reaped")
    for fd in descriptors:
        try:
            os.fstat(fd)
        except OSError:
            pass
        else:
            os.close(fd)
            raise AssertionError("harness leaked a PTY descriptor")
    assert all(peer.fileno() == -1 for peer in sockets), "harness leaked a socket"


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    live = module(root / "tests/live_mock.py", "live_cleanup")
    cpu = module(root / "tests/perf/cpu_pty.py", "cpu_cleanup")
    with tempfile.TemporaryDirectory(prefix="birc-perf-cleanup-") as directory:
        base = Path(directory)
        for harness in (live, cpu):
            for failure in ("accept", "send", "none"):
                ready = base / f"{harness.__name__}-{failure}"
                child = base / "fake-birc"
                child.write_text(
                    f"#!{sys.executable}\n"
                    "import os, socket, sys, tty\n"
                    f"open({str(ready)!r}, 'w').close()\n"
                    "tty.setraw(0)\n"
                    "s=socket.socket(); s.connect(('127.0.0.1', int(sys.argv[sys.argv.index('--port')+1])))\n"
                    "s.sendall(b'NICK probe\\r\\nUSER probe 0 * :probe\\r\\nJOIN #t\\r\\nPONG :xyz\\r\\n')\n"
                    "data=b''\n"
                    "while b'/quit\\r' not in data: data+=os.read(0, 64)\n"
                    "os.write(1, b'birc=ok\\n')\n"
                )
                child.chmod(0o700)
                run_case(harness, child, ready, failure)
    print("perf_cleanup=ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
