#!/usr/bin/env python3
"""SEND_CAP, finite budgets, FIFO close flush, and drop without replay.

The child prints a checkpoint before command close. A finite budget must
hold its remainder then. Close must flush the same FIFO, including QUIT.
All sockets and children are owned by this test; no IRC service is used.
"""
from __future__ import annotations

import select
import socket
import subprocess
import sys
import time


def run(binary: str, frames: int, count: int, mode: str = "queue") -> None:
    expected = [f"NOTICE #t :{i}" for i in range(count, 0, -1)] + ["QUIT :queue-test"]
    wire = bytearray()
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(3)
        child = subprocess.Popen(
            [binary, str(server.getsockname()[1]), str(frames), str(count), mode],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            peer, _ = server.accept()
            with peer:
                peer.setblocking(False)
                checkpoint = False
                eof = False
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    sources = [child.stdout]
                    if not eof:
                        sources.append(peer)
                    ready, _, _ = select.select(sources, [], [], 0.05)
                    # Drain wire first if the stdout checkpoint and network
                    # become readable together. Writes finish before print.
                    if peer in ready:
                        data = peer.recv(65536)
                        if data:
                            wire.extend(data)
                        else:
                            eof = True
                    if child.stdout in ready:
                        line = child.stdout.readline().strip()
                        if line == b"held":
                            # Catch bytes already in the socket even when it
                            # was not included in the same select result.
                            while not eof:
                                try:
                                    data = peer.recv(65536)
                                except BlockingIOError:
                                    break
                                if not data:
                                    eof = True
                                    break
                                wire.extend(data)
                            limit = len(expected) if frames == 0 else min(8 * frames, len(expected))
                            actual = wire.decode().splitlines()
                            assert actual == expected[:limit], (frames, count, mode, "checkpoint", actual)
                            checkpoint = True
                        elif line == b"closed":
                            break
                        elif not line and child.poll() is not None:
                            break
                stdout, stderr = child.communicate(timeout=2)
                while not eof:
                    ready, _, _ = select.select([peer], [], [], 0.2)
                    if not ready:
                        break
                    data = peer.recv(65536)
                    if not data:
                        break
                    wire.extend(data)
                assert child.returncode == 0, (child.returncode, stdout, stderr)
                assert checkpoint, ("no checkpoint", stdout, stderr)
                actual = wire.decode().splitlines()
                want = expected[:8] if mode == "drop" else expected
                assert actual == want, (frames, count, mode, "final FIFO", actual, want)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
    print(f"actor queue frames={frames} lines={count} mode={mode}: PASS")


def main() -> None:
    binary = sys.argv[1] if len(sys.argv) > 1 else "./build/actor_queue"
    for frames, count in [(1, 0), (1, 7), (1, 8), (1, 9), (2, 16), (2, 17), (3, 40), (0, 100)]:
        run(binary, frames, count)
    run(binary, 1, 17, "drop")
    redial(binary)


def redial(binary: str) -> None:
    handshake = [
        "CAP LS 302", "CAP REQ :server-time", "CAP REQ :message-tags",
        "CAP END", "NICK probe", "USER probe 0 * :probe",
    ]
    first_expected = [f"NOTICE #t :{i}" for i in range(17, 9, -1)]
    wire = [bytearray(), bytearray()]
    peers = []
    checkpoint = False
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(2)
        server.setblocking(False)
        child = subprocess.Popen(
            [binary, str(server.getsockname()[1]), "1", "17", "redial"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                ready, _, _ = select.select([server, child.stdout, *peers], [], [], 0.05)
                if server in ready:
                    peer, _ = server.accept()
                    peer.setblocking(False)
                    peers.append(peer)
                    assert len(peers) <= 2, "unexpected reconnect"
                for i, peer in enumerate(peers):
                    if peer in ready:
                        wire[i].extend(peer.recv(65536))
                if child.stdout in ready:
                    line = child.stdout.readline().strip()
                    if line == b"held":
                        for i, peer in enumerate(peers):
                            while True:
                                try:
                                    data = peer.recv(65536)
                                except BlockingIOError:
                                    break
                                if not data:
                                    break
                                wire[i].extend(data)
                        assert len(peers) == 2, "redial never connected"
                        assert wire[0].decode().splitlines() == first_expected, wire[0]
                        assert wire[1].decode().splitlines() == handshake, wire[1]
                        checkpoint = True
                    elif line == b"closed":
                        break
                    elif not line and child.poll() is not None:
                        break
            stdout, stderr = child.communicate(timeout=2)
            for i, peer in enumerate(peers):
                while True:
                    ready, _, _ = select.select([peer], [], [], 0.2)
                    if not ready:
                        break
                    data = peer.recv(65536)
                    if not data:
                        break
                    wire[i].extend(data)
            assert child.returncode == 0, (child.returncode, stdout, stderr)
            assert checkpoint, ("no reconnect checkpoint", stdout, stderr)
            assert wire[0].decode().splitlines() == first_expected, wire[0]
            assert wire[1].decode().splitlines() == handshake + ["NOTICE #t :fresh"], wire[1]
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            for peer in peers:
                peer.close()
    print("actor queue redial discards old pending and retains new FIFO: PASS")


if __name__ == "__main__":
    main()
