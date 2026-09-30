#!/usr/bin/env python3
"""Positive short write and negative stalled/refused connection checks."""
import socket
import subprocess
import sys
import threading
import time


def run(binary, mode):
    with socket.socket() as listener:
        if mode == "stall":
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        received = []
        if mode != "refused":
            listener.listen()
            listener.settimeout(5)

            def server():
                conn, _ = listener.accept()
                with conn:
                    if mode == "stall":
                        time.sleep(1.5)
                    else:
                        conn.settimeout(5)
                        data = bytearray()
                        while True:
                            chunk = conn.recv(1024)
                            if not chunk:
                                break
                            data.extend(chunk)
                        received.append(bytes(data))

            worker = threading.Thread(target=server)
            worker.start()
        started = time.monotonic()
        result = subprocess.run([binary, str(port), mode], capture_output=True,
                                text=True, timeout=5, check=True)
        elapsed = time.monotonic() - started
        expected = {"success": "send:ok", "large": "send:ok", "stall": "send:fail",
                    "refused": "connect:fail"}[mode]
        assert result.stdout.strip() == expected, (mode, result.stdout, result.stderr)
        if mode != "refused":
            worker.join(timeout=5)
            assert not worker.is_alive(), mode
        if mode == "success":
            assert received == [b"hello"], received
        if mode == "large":
            assert received == [b"0123456789abcdef" * (1 << 19)]
        if mode == "stall":
            assert elapsed < 1.5, ("stalled write missed its deadline", elapsed)


for case in ("success", "large", "stall", "refused"):
    run(sys.argv[1], case)
print("socket_deadline=ok")
