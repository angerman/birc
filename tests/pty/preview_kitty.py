#!/usr/bin/env python3
"""Pty test for /preview local PNG through TimUI's Kitty transport."""
from __future__ import annotations

import base64
import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time


PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def drain(fd: int, timeout: float) -> bytes:
    out = bytearray()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.05)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        out.extend(chunk)
    return bytes(out)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as image:
        image.write(PNG_1X1)
        image_path = image.name

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    proc = subprocess.Popen(
        [birc, "--demo", "--frames", "0"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
        env={
            **os.environ,
            "TERM": "xterm-kitty",
            "BIRC_FORCE_IMAGE_PROTOCOL": "kitty",
        },
    )
    os.close(slave)

    try:
        initial = drain(master, 1.0)
        if b"#birc" not in initial:
            print("FAIL: initial screen missing #birc", file=sys.stderr)
            return 1

        os.write(master, f"/preview file://{image_path}\r".encode())
        painted = drain(master, 2.0)
        if b"\x1b_Ga=t" not in painted:
            print("FAIL: no Kitty image transmission", file=sys.stderr)
            return 1
        if b"\x1b_Ga=p" not in painted:
            print("FAIL: no Kitty image placement", file=sys.stderr)
            return 1

        os.write(master, b"/quit\r")
        proc.wait(timeout=5)
        if proc.returncode != 0:
            print(f"FAIL: exit code {proc.returncode}", file=sys.stderr)
            return 1
        print("preview_kitty=ok")
        return 0
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)
        os.unlink(image_path)


if __name__ == "__main__":
    raise SystemExit(main())
