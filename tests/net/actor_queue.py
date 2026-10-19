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
    # − Drop during held setup: zero registration bytes.
    # + same hold without Drop: CAP/NICK/USER handshake reaches the peer.
    held_setup(binary, drop=True)
    held_setup(binary, drop=False)
    held_setup(binary, drop=True, tls=True)
    held_setup(binary, drop=True, tls=False, mode="bootdrop")
    held_setup(binary, drop=False, tls=False, mode="bootdial")
    held_setup(binary, drop=True, tls=True, mode="bootls")
    held_setup(binary, drop=False, tls=False, mode="closesetup")
    held_setup(binary, drop=False, tls=True, mode="closels")
    held_setup(binary, drop=False, tls=False, mode="bootclose")
    # − Successful upgrade still admits Drop/cmd-close before registration.
    # + The same upgraded connection registers when neither is present.
    post_upgrade(binary, "bootlsdrop")
    post_upgrade(binary, "bootlsclose")
    post_upgrade(binary, "bootlsregister")
    # − A held launch superseded to another endpoint loses SASL scope.
    # + Superseding to the exact launch endpoint retains it.
    dial_auth_scope(binary, same=False)
    dial_auth_scope(binary, same=True)


def redial(binary: str) -> None:
    # Exact registration sequence. Order is cap_notify.bend wanted.sasl(False).
    handshake = [
        "CAP LS 302", "CAP REQ :server-time", "CAP REQ :message-tags",
        "CAP REQ :account-notify", "CAP REQ :away-notify",
        "CAP REQ :draft/chathistory", "CAP REQ :echo-message",
        "CAP REQ :extended-join", "CAP REQ :account-tag",
        "CAP REQ :labeled-response", "CAP REQ :cap-notify",
        "CAP END", "NICK probe", "USER probe 0 * :probe",
    ]
    # frames=1 sends SEND_CAP (8) then Dial flushes the healthy remainder
    # (NOTICE 8..1 + QUIT) before close; Cont{fresh} rides the new socket.
    first_expected = (
        [f"NOTICE #t :{i}" for i in range(17, 0, -1)] + ["QUIT :queue-test"]
    )
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
    print("actor queue redial flushes old pending and retains new FIFO: PASS")


HANDSHAKE = [
    "CAP LS 302", "CAP REQ :server-time", "CAP REQ :message-tags",
    "CAP REQ :account-notify", "CAP REQ :away-notify",
    "CAP REQ :draft/chathistory", "CAP REQ :echo-message",
    "CAP REQ :extended-join", "CAP REQ :account-tag",
    "CAP REQ :labeled-response", "CAP REQ :cap-notify",
    "CAP END", "NICK probe", "USER probe 0 * :probe",
]

HANDSHAKE_SASL = [
    "CAP LS 302", "CAP REQ :sasl", "CAP REQ :server-time",
    "CAP REQ :message-tags", "CAP REQ :account-notify",
    "CAP REQ :away-notify", "CAP REQ :draft/chathistory",
    "CAP REQ :echo-message", "CAP REQ :extended-join",
    "CAP REQ :account-tag", "CAP REQ :labeled-response",
    "CAP REQ :cap-notify", "NICK probe", "USER probe 0 * :probe",
]


def collect_child(child: subprocess.Popen, peer: socket.socket) -> tuple[bytes, bytes, bytes]:
    wire = bytearray()
    peer.setblocking(False)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and child.poll() is None:
        ready, _, _ = select.select([child.stdout, peer], [], [], 0.05)
        if peer in ready:
            data = peer.recv(65536)
            if data:
                wire.extend(data)
        if child.stdout in ready:
            line = child.stdout.readline().strip()
            if line == b"closed":
                break
    stdout, stderr = child.communicate(timeout=2)
    while True:
        ready, _, _ = select.select([peer], [], [], 0.1)
        if not ready:
            break
        data = peer.recv(65536)
        if not data:
            break
        wire.extend(data)
    return bytes(wire), stdout, stderr


def post_upgrade(binary: str, mode: str) -> None:
    """Drive after_conn with an owned successful plain upgrade result."""
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        child = subprocess.Popen(
            [binary, str(server.getsockname()[1]), "1", "0", mode],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        try:
            peer, _ = server.accept()
            with peer:
                wire, stdout, stderr = collect_child(child, peer)
            assert child.returncode == 0, (mode, child.returncode, stdout, stderr)
            actual = wire.decode().splitlines()
            want = HANDSHAKE if mode == "bootlsregister" else []
            assert actual == want, (mode, actual, want)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
    print(f"actor queue {mode} post-upgrade admission: PASS")


def accept_nonblocking(server: socket.socket, label: str) -> socket.socket:
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        try:
            peer, _ = server.accept()
            return peer
        except BlockingIOError:
            time.sleep(0.02)
    raise AssertionError(f"{label} was never connected")


def dial_auth_scope(binary: str, *, same: bool) -> None:
    """Supersede a held launch Dial and inspect the winner's registration."""
    with socket.socket() as initial, socket.socket() as other:
        initial.bind(("127.0.0.1", 0))
        initial.listen(1)
        initial.setblocking(False)
        other.bind(("127.0.0.1", 0))
        other.listen(1)
        other.setblocking(False)
        filler = socket.create_connection(initial.getsockname(), timeout=2)
        target = initial if same else other
        mode = "dialauthsame" if same else "dialauthscope"
        child = subprocess.Popen(
            [
                binary, str(initial.getsockname()[1]), "1",
                str(target.getsockname()[1]), mode,
            ],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        first = winner = None
        try:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                ready, _, _ = select.select([child.stdout], [], [], 0.05)
                if ready and child.stdout.readline().strip() == b"held":
                    break
            else:
                raise AssertionError((mode, "no held checkpoint"))

            stuck, _ = initial.accept()
            stuck.close()
            first = accept_nonblocking(initial, f"{mode} initial dial")
            first.close()
            first = None
            winner = accept_nonblocking(target, f"{mode} winner")
            wire, stdout, stderr = collect_child(child, winner)
            assert child.returncode == 0, (mode, child.returncode, stdout, stderr)
            actual = wire.decode().splitlines()
            want = HANDSHAKE_SASL if same else HANDSHAKE
            assert actual == want, (mode, actual, want)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            if first is not None:
                first.close()
            if winner is not None:
                winner.close()
            filler.close()
    label = "same endpoint retains SASL" if same else "changed endpoint drops SASL"
    print(f"actor queue held Dial auth scope: {label}: PASS")


def held_setup(binary: str, *, drop: bool, tls: bool = False, mode: str | None = None) -> None:
    """Hold TCP setup until the child queues Drop (or skips it), then release.

    listen(1) + a filler connection saturates the accept backlog so the
    child's connect blocks inside Dns.dial_dual. Drop must be queued before
    the filler is accepted; otherwise connect completes via the backlog
    before userspace accept and registration races ahead of Drop.

    Drop during setup must close with zero peer bytes. Without Drop, the
    peer must see the exact registration handshake after release.
    """
    if mode is None:
        mode = "droptls" if tls else ("dropsetup" if drop else "dialsetup")
    wire = bytearray()
    peer = None
    filler = None
    checkpoint = False
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        # Occupy the sole backlog slot so the child's Dial connect parks.
        filler = socket.create_connection(server.getsockname(), timeout=2)
        server.setblocking(False)
        child = subprocess.Popen(
            [binary, str(server.getsockname()[1]), "1", "0", mode],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                sources = [child.stdout]
                if peer is not None:
                    sources.append(peer)
                ready, _, _ = select.select(sources, [], [], 0.05)
                if child.stdout in ready:
                    line = child.stdout.readline().strip()
                    if line == b"held":
                        # Drop (if any) is queued while connect is still pending.
                        # Free the backlog slot, then take the child's socket.
                        stuck, _ = server.accept()
                        stuck.close()
                        peer = None
                        for _ in range(50):
                            try:
                                peer, _ = server.accept()
                                break
                            except BlockingIOError:
                                time.sleep(0.02)
                        assert peer is not None, (mode, "child never connected after release")
                        peer.setblocking(False)
                        checkpoint = True
                    elif line == b"closed":
                        break
                    elif not line and child.poll() is not None:
                        break
                if peer is not None and peer in ready:
                    data = peer.recv(65536)
                    if data:
                        wire.extend(data)
                    else:
                        break
            stdout, stderr = child.communicate(timeout=2)
            if peer is not None:
                while True:
                    ready, _, _ = select.select([peer], [], [], 0.2)
                    if not ready:
                        break
                    data = peer.recv(65536)
                    if not data:
                        break
                    wire.extend(data)
            assert child.returncode == 0, (mode, child.returncode, stdout, stderr)
            assert checkpoint, (mode, "no held checkpoint", stdout, stderr)
            if mode in ("droptls", "bootls", "closesetup", "closels", "bootclose"):
                assert wire == b"", (mode, "quit during connect must send nothing", wire)
            elif tls:
                assert wire == b"", (mode, "Drop must close before a TLS ClientHello", wire)
            else:
                actual = wire.decode().splitlines()
                if drop:
                    assert actual == [], (mode, "expected zero registration bytes", actual)
                else:
                    assert actual == HANDSHAKE, (mode, actual, HANDSHAKE)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            if peer is not None:
                peer.close()
            if filler is not None:
                filler.close()
    label = {
        "droptls": "Drop during held TLS setup sends no ClientHello",
        "dropsetup": "Drop during held setup sends zero registration bytes",
        "dialsetup": "held setup without Drop registers after release",
        "bootdrop": "Drop during first connect sends zero registration bytes",
        "bootdial": "first connect without Drop registers after release",
        "bootls": "Drop during first TLS connect sends no ClientHello",
        "closesetup": "cmd close during Dial sends zero registration bytes",
        "closels": "cmd close during TLS Dial sends no ClientHello",
        "bootclose": "cmd close during first connect sends zero registration bytes",
    }[mode]
    print(f"actor queue {label}: PASS")


if __name__ == "__main__":
    main()
