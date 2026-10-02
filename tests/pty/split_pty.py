#!/usr/bin/env python3
"""M16.2 PTY: visible panes, focus routing, selection, and tiny resize."""
from __future__ import annotations

import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path


def drain(fd: int, seconds: float) -> bytes:
    out = bytearray()
    deadline = time.time() + seconds
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if ready:
            try:
                out.extend(os.read(fd, 65536))
            except OSError:
                break
    return bytes(out)


def send(fd: int, data: bytes, wait: float = 0.35) -> bytes:
    os.write(fd, data)
    return drain(fd, wait)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    proc = subprocess.Popen(
        [birc, "--plain", "--demo", "--frames", "0"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none",
             "PATH": str(Path(__file__).resolve().parent / "fake-bin")},
    )
    os.close(slave)
    try:
        initial = drain(master, 1.0)
        if b"#birc" not in initial:
            raise AssertionError("initial channel missing")

        split = send(master, b"/split server\r", 0.6)
        if b"server" not in split or b"#birc" not in split or b"[active]" not in split:
            raise AssertionError("split did not paint two named panes")
        if b"\x1b[2;2H" not in split or b"\x1b[13;1H" not in split:
            raise AssertionError("stacked panes do not have the expected 11/10 row geometry")

        # F6 focuses the other pane. The visible active marker must move.
        f6 = send(master, b"\x1b[17~", 0.5)
        if b"server [active]" not in f6:
            raise AssertionError("F6 did not focus the server pane")

        # Ctrl-W must also focus without deleting the draft.
        send(master, b"kept", 0.2)
        ctrl_w = send(master, b"\x17", 0.5)
        if b"kept" not in ctrl_w or b"[active]" not in ctrl_w:
            raise AssertionError("Ctrl-W did not preserve the draft and change focus")

        # Both split body panes remain independently selectable.
        top = send(master, b"\x1b[<0;5;8M", 0.15)
        top += send(master, b"\x1b[<32;15;8M", 0.15)
        top += send(master, b"\x1b[<0;15;8m", 0.4)
        if b"\x1b[7m" not in top:
            raise AssertionError("top split pane is not selectable")
        send(master, b"\x1b", 0.2)
        bottom = send(master, b"\x1b[<0;5;21M", 0.15)
        bottom += send(master, b"\x1b[<32;15;21M", 0.15)
        bottom += send(master, b"\x1b[<0;15;21m", 0.4)
        if b"\x1b[7m" not in bottom:
            raise AssertionError("bottom split pane is not selectable")
        send(master, b"\x1b", 0.2)

        # The horizontal spelling must use the same two buffers in two columns.
        horizontal = send(master, b"\x7f\x7f\x7f\x7f/split horizontal server\r", 0.6)
        if b"server" not in horizontal or b"#birc" not in horizontal:
            raise AssertionError("side-by-side split did not paint two named panes")
        if b"\x1b[2;31H" not in horizontal:
            raise AssertionError("side-by-side panes do not have the expected 31/31 column geometry")

        # Tiny terminals must keep running and recover on resize.
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 4, 10, 0, 0))
        os.kill(proc.pid, signal.SIGWINCH)
        drain(master, 0.3)
        if proc.poll() is not None:
            raise AssertionError("split view exited on tiny resize")
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        os.kill(proc.pid, signal.SIGWINCH)
        recovered = drain(master, 0.5)
        if b"#birc" not in recovered:
            raise AssertionError("split view did not recover after resize")

        send(master, b"/unsplit\r", 0.4)
        send(master, b"/quit\r", 0.2)
        proc.wait(timeout=5)
        if proc.returncode != 0:
            raise AssertionError(f"exit code {proc.returncode}")
        print("split_pty=ok")
        return 0
    except AssertionError as exc:
        print(f"split_pty: {exc}", file=sys.stderr)
        return 1
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


if __name__ == "__main__":
    raise SystemExit(main())
