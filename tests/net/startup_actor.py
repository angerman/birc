#!/usr/bin/env python3
"""Queued Dial survives both a successful and failed initial connection."""
from __future__ import annotations

import socket
import subprocess
import sys


def registration(peer: socket.socket, nick: str) -> None:
    peer.settimeout(2)
    data = bytearray()
    while ("USER " + nick).encode() not in data:
        chunk = peer.recv(4096)
        assert chunk, f"registration ended early: {data!r}"
        data.extend(chunk)
    assert ("NICK " + nick + "\r\n").encode() in data, data


def case(binary: str, failed: bool) -> None:
    with socket.socket() as first, socket.socket() as second:
        first.bind(("127.0.0.1", 0))
        second.bind(("127.0.0.1", 0))
        second.listen(1)
        second.settimeout(3)
        if not failed:
            first.listen(1)
            first.settimeout(3)
        # A bound, non-listening socket reserves a refused port exactly.
        child = subprocess.Popen(
            [binary, str(first.getsockname()[1]), str(second.getsockname()[1]),
             "failed" if failed else "ordinary"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        try:
            if not failed:
                peer, _ = first.accept()
                with peer:
                    registration(peer, "probe")
            peer, _ = second.accept()
            with peer:
                registration(peer, "next")
            stdout, stderr = child.communicate(timeout=3)
            assert child.returncode == 0, (child.returncode, stdout, stderr)
            assert b"startup_actor=ok" in stdout, (stdout, stderr)
            print("startup_actor " + ("failed" if failed else "ordinary") + "=ok", flush=True)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()


if __name__ == "__main__":
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/startup_actor"
    case(binary, False)
    case(binary, True)
