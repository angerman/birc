#!/usr/bin/env python3
"""A6: composer must accept /quit below 3 columns and after resize-back.

(-) draw_composer returned before timui_text_area_mut when width <= 2, so
    the client could not be typed into. Skipping the widget for a frame
    dropped it from TimUI, so resize-back did not restore typing.
(+) always create the text area; skip only the prompt when narrow.

usage: tinyquit.py ./build/birc
"""
from __future__ import annotations

import fcntl
import os
import pty
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


def run(birc, rows, cols, resize_to, payload, label):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    proc = subprocess.Popen(
        [birc, "--demo", "--frames", "20000"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color"},
    )
    os.close(slave)
    out = bytearray()
    t = time.time()
    while time.time() - t < 1.0:
        drain(master, out)
        time.sleep(0.05)
    if resize_to:
        fcntl.ioctl(
            master,
            termios.TIOCSWINSZ,
            struct.pack("HHHH", resize_to[0], resize_to[1], 0, 0),
        )
        try:
            proc.send_signal(28)
        except Exception:
            pass
        t = time.time()
        while time.time() - t < 1.0:
            drain(master, out)
            time.sleep(0.05)
    os.write(master, payload)
    t = time.time()
    while proc.poll() is None and time.time() - t < 6:
        drain(master, out)
        time.sleep(0.05)
    alive = proc.poll() is None
    code = proc.returncode
    if alive:
        proc.kill()
        proc.wait()
        code = proc.returncode
    drain(master, out)
    os.close(master)
    restored = b"[?1049l" in bytes(out)
    # A crash or SIGKILL is not a successful quit (was: ok = not alive).
    ok = (not alive) and code == 0 and restored
    print(
        f"{label}: start={rows}x{cols} resize={resize_to} "
        f"quit_worked={ok} exit={code} restored={restored}"
    )
    return ok


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    cases = [
        run(birc, 24, 80, None, b"/quit\r", "control"),
        run(birc, 24, 80, (40, 100), b"/quit\r", "resize-ok"),
        run(birc, 5, 1, None, b"/quit\r", "1col"),
        run(birc, 5, 2, None, b"/quit\r", "2col"),
        run(birc, 5, 3, (1, 1), b"/quit\r", "3col-then-1x1"),
        run(birc, 1, 1, (24, 80), b"/quit\r", "1x1-then-24x80"),
        run(birc, 1, 1, None, b"\x1b", "esc-1x1"),
        run(birc, 1, 1, (24, 80), b"\x1b", "esc-1x1-then-24x80"),
    ]
    ok = all(cases)
    print("RESULT:", "PASS" if ok else "FAIL")
    if not ok:
        print("tinyquit: composer dead at narrow size or after resize", file=sys.stderr)
        return 1
    print("tinyquit=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
