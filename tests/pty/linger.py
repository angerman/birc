#!/usr/bin/env python3
"""H6: boot_clock must not keep the process alive 8 s after the UI quits.

usage: linger.py ./build/birc

(-) IO.sleep(8000) in boot_clock: wall ~8–10 s after a 2-frame live run.
(+) sliced sleep + closed-chan probe: wall under 4 s.
"""
from __future__ import annotations

import socket
import subprocess
import sys
import time


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]
    srv.settimeout(10)
    t0 = time.time()
    proc = subprocess.Popen(
        [birc, "--connect", "127.0.0.1", "--port", str(port),
         "--nick", "probe", "--channel", "#t", "--frames", "2"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    try:
        conn, _ = srv.accept()
    except socket.timeout:
        proc.kill()
        print("linger: accept timeout", file=sys.stderr)
        return 1
    conn.sendall(b":irc.example.net 001 probe :Welcome\r\n")
    try:
        out, _ = proc.communicate(timeout=12)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        print("linger: hung past 12 s", file=sys.stderr)
        return 1
    wall = time.time() - t0
    text = out.decode("utf-8", "replace")
    print(f"exit={proc.returncode} wall={wall:.1f}s birc_ok={'birc=ok' in text}")
    ok = proc.returncode == 0 and "birc=ok" in text and wall < 4.0
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("linger: process lived too long after UI quit (H6)", file=sys.stderr)
        return 1
    print("linger=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
