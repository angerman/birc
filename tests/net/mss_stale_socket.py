#!/usr/bin/env python3
"""MSS stale-903 generation fence over real loopback sockets.

One listener, two accepts (same endpoint). Conn1 drives SASL to the 903
flight, which Bend holds; the redial opens conn2, the peer closes conn1
(FIN first), and the held gen-0 bytes are released only once the fresh
gen-1 exchange reaches payload-observed with the old EOF in hand. The
driver then proves the real AuthBridge event pipe stayed empty (still
open) before sending the fresh 903, and exactly one BIRC_AUTH_OK frame
plus EOF after it.

Modes: whole (903 in one write) and split (903 torn inside "903").
"""
from __future__ import annotations

import os
import re
import select
import socket
import subprocess
import sys
import time

HOST = "127.0.0.1"
SECRET = b"hunter2"
CAP_ACK = b":s CAP probe ACK :sasl\r\n"
PLUS = b"AUTHENTICATE +\r\n"
FLIGHT_903 = b":s 903 probe :SASL authentication successful\r\n"
WELCOME = b":s 001 probe :Welcome to the test net\r\n"
FRAME = b"BIRC_AUTH_OK\n"

# No byte-detector invariant: the Bend hold arms on the old exchange
# reaching AuthResult, which strictly precedes any 903 byte on the wire.
assert FLIGHT_903.endswith(b"\r\n")


class Peer:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.sock.settimeout(10)
        self.buf = bytearray()

    def line(self, what: str) -> bytes:
        while b"\r\n" not in self.buf:
            chunk = self.sock.recv(4096)
            assert chunk, f"{what} ended early: {self.buf!r}"
            self.buf.extend(chunk)
        raw, _, rest = self.buf.partition(b"\r\n")
        self.buf = bytearray(rest)
        return bytes(raw)

    def until(self, needle: bytes, what: str) -> None:
        while True:
            got = self.line(what)
            if got == needle:
                return

    def until_start(self, prefix: bytes, what: str) -> bytes:
        while True:
            got = self.line(what)
            if got.startswith(prefix):
                return got

    def quiet(self, seconds: float, what: str) -> None:
        ready, _, _ = select.select([self.sock], [], [], seconds)
        assert not ready, f"{what}: unexpected wire bytes while held"


SPLIT_PREFIX = FLIGHT_903[:3]
SPLIT_TAIL = FLIGHT_903[len(SPLIT_PREFIX):]
assert SPLIT_PREFIX == b":s ", SPLIT_PREFIX


def send_flight(peer: Peer, split: bool) -> None:
    # Fresh-side only: the held (conn1) split below is latch-gated, never
    # sleep-torn, so coalescing cannot fake it.
    if not split:
        peer.sock.sendall(FLIGHT_903)
        return
    peer.sock.sendall(FLIGHT_903[:6])
    time.sleep(0.05)
    peer.sock.sendall(FLIGHT_903[6:])


def send_held(peer: Peer, split: bool) -> None:
    if not split:
        peer.sock.sendall(FLIGHT_903)
        return
    # Deterministic ':s ' + '903...' split: the tail goes out only after
    # Bend's wire latch proves the prefix callback was collected, so the
    # tail provably lands in a later received callback.
    peer.sock.sendall(SPLIT_PREFIX)
    peer.until(b"PRIVMSG ackprobe :SPLITLATCH", "split latch")
    peer.sock.sendall(SPLIT_TAIL)


def sasl_opening(peer: Peer, tag: str) -> None:
    peer.until_start(b"USER ", f"{tag} registration")
    peer.sock.sendall(CAP_ACK)
    peer.until(b"AUTHENTICATE PLAIN", f"{tag} authenticate")
    peer.sock.sendall(PLUS)
    peer.until_start(b"AUTHENTICATE ", f"{tag} payload")


def check_markers(stdout: bytes, stderr: bytes, mode: str) -> None:
    text = stdout.decode("utf-8", "replace")
    marks = [
        "MARK START " + mode,
        "MARK HELD armed",
    ]
    if mode == "split":
        marks.append("MARK LATCHED")
    marks += [
        "MARK EOF0",
        "MARK HELDBYTES %d" % len(FLIGHT_903),
        "MARK REDIAL 0>dial:127.0.0.1:",
        "MARK AUTHPLUS",
        "MARK STALERELEASE edge:False code:0",
        "MARK STALERELEASED",
        "MARK DISPATCHED",
        "MARK FRESH903",
        "MARK BYTEEXACT %d" % len(FLIGHT_903),
        "MARK EOF1",
        "mss_stale_socket=ok",
    ]
    idx = [text.find(m) for m in marks]
    assert all(i >= 0 for i in idx), (mode, text, stderr)
    assert idx == sorted(idx), (mode, text)
    if mode == "whole":
        assert "MARK LATCHED" not in text, (mode, text)
    # Received held-callback boundaries + full exact bytes: one HELDCHUNK
    # length per collected chunk, in arrival order.
    lens = [int(v) for v in re.findall(r"MARK HELDCHUNK (\d+)", text)]
    assert len(lens) >= (2 if mode == "split" else 1), (mode, lens, text)
    assert sum(lens) == len(FLIGHT_903), (mode, lens, text)
    if mode == "split":
        assert lens[0] == len(SPLIT_PREFIX), (mode, lens, text)


def case(binary: str, mode: str) -> None:
    split = mode == "split"
    listener = socket.socket()
    listener.bind((HOST, 0))
    listener.listen(2)
    listener.settimeout(15)
    port = listener.getsockname()[1]
    r_secret, w_secret = os.pipe()
    os.write(w_secret, SECRET)
    os.close(w_secret)  # EOF: setup reads the secret to end-of-pipe.
    r_event, w_event = os.pipe()
    env = dict(os.environ)
    env["BIRC_AUTH_SECRET_FD"] = str(r_secret)
    env["BIRC_AUTH_EVENT_FD"] = str(w_event)
    child = subprocess.Popen(
        [binary, str(port), mode],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        pass_fds=(r_secret, w_event),
    )
    os.close(r_secret)
    os.close(w_event)  # Driver keeps the read end only; notify EOFs it.
    try:
        c1, _ = listener.accept()
        with c1:
            peer1 = Peer(c1)
            sasl_opening(peer1, "conn1")
            send_held(peer1, split)
            # Held means silent: no CAP END may leak on the old wire.
            peer1.quiet(0.3, "conn1")
            # Peer FIN first: Bend redials only after capturing old EOF.
            c1.close()
            c2, _ = listener.accept()
            with c2:
                peer2 = Peer(c2)
                sasl_opening(peer2, "conn2")
                # Post-dispatch ACK: Bend emits this PRIVMSG only after the
                # stale FIFO release, so the pipe check below is ordered
                # with no settle window.
                peer2.until(b"PRIVMSG ackprobe :STALERELEASED", "dispatch ack")
                ready, _, _ = select.select([r_event], [], [], 0.2)
                assert not ready, "stale release wrote to the event pipe"
                send_flight(peer2, split)
                peer2.until(b"CAP END", "fresh cap end")
                peer2.sock.sendall(WELCOME)
                peer2.until(b"JOIN #t", "channel join")
        data = bytearray()
        while True:
            chunk = os.read(r_event, 4096)
            if not chunk:
                break
            data.extend(chunk)
        assert bytes(data) == FRAME, (mode, bytes(data))
        stdout, stderr = child.communicate(timeout=10)
        assert child.returncode == 0, (mode, child.returncode, stdout, stderr)
        check_markers(stdout, stderr, mode)
        print(f"mss_stale_socket {mode}=ok", flush=True)
    finally:
        os.close(r_event)
        listener.close()
        if child.poll() is None:
            child.kill()
            child.wait()


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "./build/mss_stale_socket"
    case(target, "whole")
    case(target, "split")
