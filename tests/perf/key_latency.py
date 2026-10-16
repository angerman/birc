#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Keystroke-to-composer latency on a pty.

Writes one key and waits until that key's glyph appears in the bytes painted
after the write. The wait is a read progress condition (select until the
glyph, or a hard failure deadline). It is not a fixed sleep.

Proposed budget is p95 < 16 ms. The assertion is looser so a loaded shared
host does not flake; tighten it toward 16 ms from the recorded baseline.

usage: key_latency.py ./build/birc
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

# Proposed target: 16 ms. Gate stays above measured loaded-host noise.
PROPOSED_P95_MS = 16.0
P95_BUDGET_MS = 80.0
SAMPLES = 24
WARMUP = 3
FAIL_DEADLINE_S = 2.0
# Absent from the demo transcript and from nick "probe".
KEYS = b"QWERTYUIOPASDFGHJKLZXCVBNM"


def percentile(values: list[float], pct: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    rank = (len(ordered) - 1) * pct / 100.0
    lo = int(rank)
    hi = min(lo + 1, len(ordered) - 1)
    frac = rank - lo
    return ordered[lo] * (1.0 - frac) + ordered[hi] * frac


def read_until(fd: int, pred, deadline: float) -> bytes:
    """Read until pred(buf) or deadline. Returns the bytes seen."""
    buf = bytearray()
    while time.monotonic() < deadline:
        timeout = max(0.0, deadline - time.monotonic())
        ready, _, _ = select.select([fd], [], [], timeout)
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        buf.extend(chunk)
        if pred(buf):
            break
    return bytes(buf)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    birc = sys.argv[1]
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    env = {
        **os.environ,
        "TERM": "xterm-256color",
        "BIRC_HISTORY": "none",
        "BIRC_PREFERENCES": "none",
        "BIRC_IMAGE_CACHE": "none",
    }
    proc = subprocess.Popen(
        [birc, "--demo", "--nick", "probe", "--channel", "#birc", "--frames", "0"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)
    samples: list[float] = []
    try:
        first = read_until(master, lambda buf: b"\x1b[?1049h" in buf, time.monotonic() + FAIL_DEADLINE_S)
        if b"\x1b[?1049h" not in first:
            print("key_latency: demo frame did not open", file=sys.stderr)
            return 1
        # Drain whatever the first paint already queued. Stop when the pty
        # has nothing buffered; do not sleep for a fixed interval.
        while select.select([master], [], [], 0)[0]:
            try:
                if not os.read(master, 65536):
                    break
            except OSError:
                break
        for index in range(WARMUP + SAMPLES):
            key = KEYS[index % len(KEYS): index % len(KEYS) + 1]
            started = time.monotonic()
            os.write(master, key)
            painted = read_until(
                master,
                lambda buf, glyph=key: glyph in buf,
                started + FAIL_DEADLINE_S,
            )
            elapsed_ms = 1000.0 * (time.monotonic() - started)
            if key not in painted:
                print(
                    f"key_latency: composer did not paint {key!r} within {FAIL_DEADLINE_S:.0f}s",
                    file=sys.stderr,
                )
                return 1
            if index >= WARMUP:
                samples.append(elapsed_ms)
        os.write(master, b"\x1b")
        quit_deadline = time.monotonic() + FAIL_DEADLINE_S
        while time.monotonic() < quit_deadline and proc.poll() is None:
            read_until(master, lambda _buf: False, time.monotonic() + 0.05)
        if proc.poll() is None:
            proc.kill()
        proc.wait(timeout=2)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)
    p50 = percentile(samples, 50)
    p95 = percentile(samples, 95)
    print(
        f"key_latency samples={len(samples)} "
        f"p50_ms={p50:.2f} p95_ms={p95:.2f} "
        f"max_ms={max(samples):.2f} "
        f"proposed_p95_ms={PROPOSED_P95_MS:.0f} budget_ms={P95_BUDGET_MS:.0f}"
    )
    if p95 >= P95_BUDGET_MS:
        print(
            f"key_latency: p95 {p95:.2f} ms exceeds budget {P95_BUDGET_MS:.0f} ms",
            file=sys.stderr,
        )
        return 1
    print("key_latency=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
