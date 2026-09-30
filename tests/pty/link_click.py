#!/usr/bin/env python3
"""A click on a rendered chat link opens its exact URL.

The demo's newest line contains https://timui.dev. A fake platform opener
records the argument, so this test never launches a real browser.

usage: link_click.py ./build/birc
"""
from __future__ import annotations

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


def drain(fd: int, duration: float = 0.5) -> bytes:
    out = bytearray()
    deadline = time.monotonic() + duration
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


def wait_text(path: str, timeout: float = 3.0) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with open(path, encoding="utf-8") as handle:
                return handle.read().strip()
        except FileNotFoundError:
            time.sleep(0.05)
    return ""


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    with tempfile.TemporaryDirectory(prefix="birc-link-") as tmp:
        log = os.path.join(tmp, "opened")
        opener = "open" if sys.platform == "darwin" else "xdg-open"
        opener_path = os.path.join(tmp, opener)
        with open(opener_path, "w", encoding="utf-8") as handle:
            handle.write('#!/bin/sh\nprintf "%s\\n" "$1" > "$BIRC_LINK_LOG"\n')
        os.chmod(opener_path, 0o755)

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
                "TERM": "xterm-256color",
                "BIRC_HISTORY": "none",
                "BIRC_LINK_LOG": log,
                "PATH": tmp,
            },
        )
        os.close(slave)
        try:
            initial = drain(master, 1.0)
            if b"https://timui.dev" not in initial:
                raise AssertionError("demo link was not painted")

            # The newest demo line is bottom-aligned at terminal row 21. Its
            # link begins at column 23 after the timestamp and "<carol> see ".
            os.write(master, b"\x1b[<0;25;21M\x1b[<0;25;21m")
            drain(master, 0.5)
            opened = wait_text(log)
            if opened != "https://timui.dev":
                raise AssertionError(f"clicked URL was not opened: {opened!r}")

            os.write(master, b"/quit\r")
            proc.wait(timeout=5)
            if proc.returncode != 0:
                raise AssertionError(f"client exited with {proc.returncode}")
            print("link_click=ok")
            return 0
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)


if __name__ == "__main__":
    sys.exit(main())
