#!/usr/bin/env python3
"""Headless EOF cannot win a race against initial registration/failure.

(-) UI-first startup painted EOF before the actor's boot result and exited
successfully on a refused connection; even healthy accept could time out.
(+) Refusal fails closed. Eight healthy runs deliver complete registration
before bounded headless completion. Existing linger.py stays unchanged.
"""
from __future__ import annotations

import os
import socket
import subprocess
import sys
import time


def launch(binary: str, port: int) -> subprocess.Popen:
    return subprocess.Popen(
        [binary, "--connect", "127.0.0.1", "--port", str(port),
         "--nick", "probe", "--channel", "#t", "--frames", "2"],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        env={**os.environ, "BIRC_HISTORY": "none"},
    )


def refused(binary: str) -> None:
    with socket.socket() as bound:
        # A bound, non-listening socket reserves a definitely refused port.
        bound.bind(("127.0.0.1", 0))
        proc = launch(binary, bound.getsockname()[1])
        try:
            out, _ = proc.communicate(timeout=3)
            assert proc.returncode != 0, f"refused connect reported success: {out!r}"
            assert b"birc=ok" not in out, f"refused connect painted a success: {out!r}"
            assert out.strip(), "refused connect omitted its error"
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=2)
    print("headless_startup refused=ok")


def healthy(binary: str, index: int) -> None:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(3)
        start = time.monotonic()
        proc = launch(binary, listener.getsockname()[1])
        try:
            with listener.accept()[0] as conn:
                conn.settimeout(2)
                wire = bytearray()
                while b"USER probe 0 * :probe\r\n" not in wire:
                    data = conn.recv(4096)
                    if not data:
                        break
                    wire.extend(data)
                assert b"NICK probe\r\nUSER probe 0 * :probe\r\n" in wire, (
                    f"run{index}: initial frame won before registration: {wire!r}")
            out, _ = proc.communicate(timeout=3)
            assert proc.returncode == 0, f"run{index}: exit={proc.returncode}, output={out!r}"
            assert b"birc=ok" in out, f"run{index}: headless completion missing: {out!r}"
            assert time.monotonic() - start < 4, f"run{index}: startup or shutdown lingered"
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate(timeout=2)


def main() -> None:
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    refused(binary)
    for index in range(8):
        healthy(binary, index)
    print("headless_startup healthy=8/8")
    print("headless_startup=ok")


if __name__ == "__main__":
    main()
