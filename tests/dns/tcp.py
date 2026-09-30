#!/usr/bin/env python3
"""DNS-over-TCP framing and owned-deadline regression peers; no network DNS."""
import socket
import struct
import subprocess
import sys
import threading
import time

HEADER = bytes([0, 1, 129, 128, 0, 1, 0, 1, 0, 0, 0, 0])
QUESTION = bytes([1, 97, 0, 0, 1, 0, 1])
ANSWER = bytes([192, 12, 0, 1, 0, 1, 0, 0, 0, 1, 0, 4, 1, 2, 3, 4])
PACKET = HEADER + QUESTION + ANSWER
FRAME = struct.pack("!H", len(PACKET)) + PACKET


def read_exact(conn, size):
    data = bytearray()
    while len(data) < size:
        chunk = conn.recv(size - len(data))
        if not chunk:
            raise AssertionError("client closed before query was complete")
        data.extend(chunk)
    return bytes(data)


def run(binary, mode):
    failures = []
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        listener.settimeout(5)
        port = listener.getsockname()[1]

        def server():
            try:
                conn, _ = listener.accept()
                with conn:
                    conn.settimeout(5)
                    size, = struct.unpack("!H", read_exact(conn, 2))
                    query = read_exact(conn, size)
                    assert query[:2] == b"\x00\x01" and query[12:] == QUESTION, query
                    if mode == "complete":
                        conn.sendall(FRAME)
                    elif mode == "split_prefix":
                        conn.sendall(FRAME[:1])
                        time.sleep(0.05)
                        conn.sendall(FRAME[1:2])
                        time.sleep(0.05)
                        conn.sendall(FRAME[2:])
                    elif mode == "split_body":
                        for i in range(0, len(FRAME), 3):
                            conn.sendall(FRAME[i:i + 3])
                            time.sleep(0.01)
                    elif mode == "large":
                        header = HEADER[:7] + b"\x02" + HEADER[8:]
                        txt = bytes([192, 12, 0, 16, 0, 1, 0, 0, 0, 1, 32, 0]) + b"x" * 8192
                        packet = header + QUESTION + txt + ANSWER
                        conn.sendall(struct.pack("!H", len(packet)) + packet)
                    elif mode == "false_short":
                        conn.sendall(b"\x00\x01" + PACKET)
                    elif mode == "false_long":
                        conn.sendall(struct.pack("!H", len(PACKET) + 1) + PACKET)
                    elif mode == "prefix_eof":
                        conn.sendall(FRAME[:1])
                    elif mode == "body_eof":
                        conn.sendall(FRAME[:-1])
                    elif mode == "trailing":
                        conn.sendall(FRAME + b"\x00")
                    elif mode == "silent":
                        time.sleep(3.5)
                    elif mode == "trickle":
                        for byte in FRAME:
                            try:
                                conn.sendall(bytes([byte]))
                            except OSError:
                                break
                            time.sleep(0.2)
            except BaseException as error:
                failures.append(error)

        worker = threading.Thread(target=server)
        worker.start()
        started = time.monotonic()
        result = subprocess.run([binary, str(port)], capture_output=True,
                                text=True, timeout=5, check=True)
        elapsed = time.monotonic() - started
        worker.join(timeout=5)
        assert not worker.is_alive(), mode
        assert not failures, (mode, failures)
        expected = {"complete": "ok:1.2.3.4", "split_prefix": "ok:1.2.3.4",
                    "split_body": "ok:1.2.3.4", "large": "ok:1.2.3.4",
                    "false_short": "fail:tcp length", "false_long": "fail:tcp eof",
                    "prefix_eof": "fail:tcp eof", "body_eof": "fail:tcp eof",
                    "trailing": "fail:tcp length", "silent": "fail:tcp timeout",
                    "trickle": "fail:tcp timeout"}[mode]
        assert result.stdout.strip() == expected, (mode, result.stdout, result.stderr)
        if mode in ("silent", "trickle"):
            assert 2.8 <= elapsed < 4.0, (mode, "deadline not respected", elapsed)


for case in ("complete", "split_prefix", "split_body", "large", "false_short",
             "false_long", "prefix_eof", "body_eof", "trailing", "silent", "trickle"):
    run(sys.argv[1], case)
print("dns_tcp=ok")
