#!/usr/bin/env python3
"""H4 / H6: /connect must not freeze the UI, and /quit must exit the process.

usage: connect_pty.py ./build/birc

Case A: black-hole /connect to 192.0.2.1 (TEST-NET-1, RFC 5737).
  (-) idle_dial blocks in TCP.connect: keys never paint; /quit waits on SYN retry.
  (+) UI paints 'connecting', reacts to keys, and after /quit the *process*
      exits 0 within 2 s (CID_HALT; not just UI restore while TCP.connect parks).

Case B: plain --demo /quit.
  (+) process exits 0 in under 2 s wall (boot_clock used to add 8 s).
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


def spawn(birc, args):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    proc = subprocess.Popen(
        [birc, *args],
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    return master, proc


def wait_quit(master, proc, out, secs=2.0):
    t_quit = time.time()
    if proc.poll() is None:
        os.write(master, b"\x7f\x7f/quit\r")
    end = t_quit + secs
    while time.time() < end and proc.poll() is None:
        drain(master, out)
        time.sleep(0.05)
    hung = proc.poll() is None
    quit_wall = time.time() - t_quit
    if hung:
        proc.kill()
        proc.wait()
    drain(master, out)
    return hung, quit_wall


def case_blackhole(birc) -> bool:
    t0 = time.time()
    master, proc = spawn(
        birc, ["--demo", "--nick", "probe", "--channel", "#t", "--frames", "20000"]
    )
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
    hung, quit_wall = wait_quit(master, proc, out, 2.0)
    os.close(master)
    text = out.decode("utf-8", "replace")
    plain = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", " ", text)
    compact = re.sub(r"[^a-zA-Z]+", "", plain).lower()
    connecting = "connecting" in compact or "conncting" in compact
    restored = "[?1049l" in text
    birc_ok = "birc=ok" in text
    print(
        f"A blackhole: connecting={connecting} ui_reacts_to_keys={reacts} "
        f"restored={restored} birc_ok={birc_ok} exit={proc.returncode} "
        f"hung_on_quit={hung} quit_wall={quit_wall:.1f}s wall={time.time() - t0:.1f}s"
    )
    ok = (
        connecting
        and reacts
        and restored
        and birc_ok
        and (not hung)
        and (proc.returncode == 0)
        and (quit_wall < 2.0)
    )
    if not ok:
        print("connect_pty A: UI freeze or process linger after /quit", file=sys.stderr)
    return ok


def case_demo_quit(birc) -> bool:
    t0 = time.time()
    master, proc = spawn(birc, ["--demo", "--frames", "20000"])
    out = bytearray()
    end = time.time() + 0.8
    while time.time() < end:
        drain(master, out)
        time.sleep(0.05)
    hung, quit_wall = wait_quit(master, proc, out, 2.0)
    os.close(master)
    text = out.decode("utf-8", "replace")
    restored = "[?1049l" in text
    birc_ok = "birc=ok" in text
    wall = time.time() - t0
    print(
        f"B demo-quit: restored={restored} birc_ok={birc_ok} exit={proc.returncode} "
        f"hung_on_quit={hung} quit_wall={quit_wall:.1f}s wall={wall:.1f}s"
    )
    ok = (
        (not hung)
        and (proc.returncode == 0)
        and restored
        and birc_ok
        and (quit_wall < 2.0)
        and (wall < 2.0)
    )
    if not ok:
        print("connect_pty B: --demo /quit lingered", file=sys.stderr)
    return ok


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    a = case_blackhole(birc)
    b = case_demo_quit(birc)
    ok = a and b
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        return 1
    print("connect_pty=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
