#!/usr/bin/env python3
"""Characterization: after birc exits, the pty is left in cooked mode.

Normal close and atexit both call timui_restore_terminal. SIGTERM is
covered by TimUI's own restore-on-exit handlers.
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


def drain(fd: int) -> None:
    while True:
        r, _, _ = select.select([fd], [], [], 0)
        if not r:
            return
        try:
            data = os.read(fd, 65536)
        except OSError:
            return
        if not data:
            return


def run_one(
    birc: str,
    extra_env: dict,
    argv: list[str],
    allow_nonzero: bool,
    quit_line: bytes | None = None,
) -> int:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    proc = subprocess.Popen(
        [birc, *argv],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color", **extra_env},
    )
    os.close(slave)
    # frames=N on a tty parks until a message. Wait until the first
    # paint, then ask it to quit. The cooked-mode check is unchanged.
    if quit_line is not None:
        end = time.time() + 5
        while time.time() < end and proc.poll() is None:
            r, _, _ = select.select([master], [], [], 0.1)
            if r:
                drain(master)
                break
        if proc.poll() is None:
            os.write(master, quit_line)
    t1 = time.time() + 15
    while proc.poll() is None and time.time() < t1:
        drain(master)
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
        os.close(master)
        print("restore: hung", file=sys.stderr)
        return 1
    drain(master)
    attrs = termios.tcgetattr(master)
    os.close(master)
    if proc.returncode != 0 and not allow_nonzero:
        print(f"restore: exit {proc.returncode}", file=sys.stderr)
        return 1
    lflag = attrs[3]
    if not (lflag & termios.ICANON):
        print("restore: pty left in raw mode (ICANON off)", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    if run_one(birc, {}, ["--demo", "--frames", "20"], False, b"/quit\r") != 0:
        return 1
    # Test-only: die after Timui.open so atexit restore runs (normal /quit
    # goes through Timui.close and skips the hook).
    if run_one(birc, {"BIRC_DIE_AFTER_OPEN": "1"}, ["--demo", "--frames", "20000"], True) != 0:
        print("restore: die-after-open left raw mode", file=sys.stderr)
        return 1
    print("restore=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
