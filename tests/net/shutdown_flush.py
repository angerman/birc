# SPDX-License-Identifier: Apache-2.0
"""Actual shutdown must flush pending QUIT despite peer EOF or stale ack."""
import os
import socket
import subprocess
import sys
import time

environment = dict(os.environ, TERM="xterm-256color", BIRC_IMAGES="off", BIRC_HISTORY="none")
for name in ("BIRC_DIE_AFTER_OPEN", "BIRC_FRAME_PROFILE", "TIMUI_TRACE"):
    environment.pop(name, None)

for mode in ("open", "half_close"):
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(3)
        started = time.monotonic()
        child = subprocess.Popen(
            [sys.argv[1], str(server.getsockname()[1]), mode],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=environment,
        )
        try:
            peer, _ = server.accept()
            wire = bytearray()
            with peer:
                peer.settimeout(3)
                if mode == "half_close":
                    peer.shutdown(socket.SHUT_WR)
                while True:
                    data = peer.recv(4096)
                    if not data:
                        break
                    wire.extend(data)
            stdout, stderr = child.communicate(timeout=3)
            expected = b"NOTICE #t :pending\r\nQUIT :shutdown-test\r\n"
            print(f"shutdown case={mode} rc={child.returncode} elapsed={time.monotonic()-started:.3f}s wire={bytes(wire)!r}", flush=True)
            assert child.returncode == 0, (mode, stdout, stderr)
            assert b"birc=ok" in stdout, (mode, stdout, stderr)
            assert wire == expected, (mode, bytes(wire), expected)
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()

for mode in ("demo", "offline"):
    result = subprocess.run(
        [sys.argv[1], "0", mode], stdin=subprocess.DEVNULL,
        capture_output=True, timeout=3, check=False,
        env=environment,
    )
    assert result.returncode == 0, (mode, result.stdout, result.stderr)
    assert b"birc=ok" in result.stdout, (mode, result.stdout, result.stderr)
    print(f"shutdown case={mode} writer=None: PASS", flush=True)
print("shutdown_flush=ok", flush=True)
