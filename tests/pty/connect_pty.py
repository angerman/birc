#!/usr/bin/env python3
"""H4: /connect must not freeze the UI.

usage: connect_pty.py ./build/birc

(-) idle_dial blocks in TCP.connect: keys typed in the first second never
    appear, and /quit cannot run until the kernel SYN retry gives up.
(+) Tick loop keeps running during dial: the UI paints 'connecting',
    reacts to keys within 1 s, and /quit exits 0 with the terminal restored.

192.0.2.1 is TEST-NET-1 (RFC 5737); it should not route, so connect hangs.
"""
from __future__ import annotations

import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time


def drain(fd, sink):
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            return
        try:
            d = os.read(fd, 65536)
        except OSError:
            return
        if not d:
            return
        sink += d


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    t0 = time.time()
    proc = subprocess.Popen(
        [birc, "--demo", "--nick", "probe", "--channel", "#t", "--frames", "20000"],
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    out = bytearray()
    end = time.time() + 1.0
    while time.time() < end:
        drain(master, out)
        time.sleep(0.05)
    os.write(master, b"/connect 192.0.2.1\r")
    end = time.time() + 0.8
    while time.time() < end:
        drain(master, out)
        time.sleep(0.05)
    mark = len(out)
    os.write(master, b"zz")
    end = time.time() + 1.0
    while time.time() < end:
        drain(master, out)
        time.sleep(0.05)
    reacts = b"z" in bytes(out[mark:])
    if proc.poll() is None:
        os.write(master, b"\x7f\x7f/quit\r")
    end = time.time() + 8
    while time.time() < end and proc.poll() is None:
        drain(master, out)
        time.sleep(0.05)
    hung = proc.poll() is None
    if hung:
        proc.kill()
        proc.wait()
    drain(master, out)
    text = out.decode("utf-8", "replace")
    plain = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", " ", text)
    compact = re.sub(r"[^a-zA-Z]+", "", plain).lower()
    connecting = "connecting" in compact or "conncting" in compact
    restored = "[?1049l" in text
    birc_ok = "birc=ok" in text
    print(f"connecting={connecting} ui_reacts_to_keys={reacts}")
    print(f"restored={restored} birc_ok={birc_ok} "
          f"exit={proc.returncode} hung_on_quit={hung} wall={time.time() - t0:.1f}s")
    print("plain-tail:", " ".join(plain.split())[-400:])
    # Base TCP.connect has no timeout; a black-hole dial can keep the process
    # alive after the UI has quit. The freeze bug is UI-dead during dial.
    ok = connecting and reacts and restored and birc_ok
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("connect_pty: UI froze during /connect", file=sys.stderr)
        return 1
    print("connect_pty=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
