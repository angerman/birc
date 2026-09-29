#!/usr/bin/env python3
"""Profile the production replay and frame path at a bounded scale.

The program emits per-frame phase averages only when BIRC_FRAME_PROFILE is
set. This harness also measures end-to-end replay wall time. It is a profiler,
not a threshold gate; measured gates live in their focused tests.

usage: hardening_profile.py ./build/birc
"""
from __future__ import annotations

import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import fcntl


DEFAULT_BUFFERS = 8
DEFAULT_LINES = 256
MAX_BUFFERS = 15  # MAX_BUFFERS includes the server buffer.
MAX_LINES = 1024
FRAME_PULSES = 32
MAX_REPLAY_BYTES = 1_048_576
PROFILE_RE = re.compile(
    rb"birc_profile frames=(\d+) prepare_us=(\d+) begin_us=(\d+) "
    rb"draw_us=(\d+) end_us=(\d+)"
)


def corpus(buffers: int, lines: int) -> bytes:
    parts: list[bytes] = []
    for buf in range(buffers):
        channel = f"#m7-{buf}".encode()
        parts.append(b":probe!u@h JOIN " + channel + b"\n")
        for line in range(lines):
            parts.append(
                b":p!u@h PRIVMSG "
                + channel
                + f" :m {buf}:{line} *b* https://x\n".encode()
            )
    return b"".join(parts)


def drain(fd: int, output: bytearray) -> None:
    while select.select([fd], [], [], 0)[0]:
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return
        if not chunk:
            return
        output.extend(chunk)


def run(birc: str, replay: str, enabled: bool) -> tuple[float, float, bytes]:
    env = dict(os.environ)
    if enabled:
        env["BIRC_FRAME_PROFILE"] = "1"
    else:
        env.pop("BIRC_FRAME_PROFILE", None)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    start = time.monotonic()
    proc = subprocess.Popen(
        [
            birc,
            "--replay",
            replay,
            "--nick",
            "probe",
            "--frames",
            "20000",
        ],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)
    output = bytearray()
    deadline = time.monotonic() + 75.0
    ready_ms = 0.0
    while time.monotonic() < deadline and proc.poll() is None:
        drain(master, output)
        if b"\x1b[?1049h" in output:
            ready_ms = 1000.0 * (time.monotonic() - start)
            break
        time.sleep(0.02)
    for _ in range(FRAME_PULSES):
        if proc.poll() is not None:
            break
        os.write(master, b"x")
        pulse_end = time.monotonic() + 0.03
        while time.monotonic() < pulse_end and proc.poll() is None:
            drain(master, output)
            time.sleep(0.002)
    if proc.poll() is None:
        os.write(master, b"\x1b")
    while time.monotonic() < deadline and proc.poll() is None:
        drain(master, output)
        time.sleep(0.02)
    if proc.poll() is None:
        proc.send_signal(signal.SIGKILL)
        proc.wait()
    drain(master, output)
    os.close(master)
    wall_ms = 1000.0 * (time.monotonic() - start)
    if proc.returncode != 0:
        raise RuntimeError(f"birc exited {proc.returncode}: {bytes(output)!r}")
    return wall_ms, ready_ms, bytes(output)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    buffers = int(os.environ.get("BIRC_PROFILE_BUFFERS", DEFAULT_BUFFERS))
    lines = int(os.environ.get("BIRC_PROFILE_LINES", DEFAULT_LINES))
    if not 1 <= buffers <= MAX_BUFFERS or not 1 <= lines <= MAX_LINES:
        print("hardening_profile: requested scale exceeds in-memory limits", file=sys.stderr)
        return 2
    replay = corpus(buffers, lines)
    if len(replay) > MAX_REPLAY_BYTES:
        print("hardening_profile: scale corpus exceeds replay reader cap", file=sys.stderr)
        return 1
    with tempfile.NamedTemporaryFile(prefix="birc-m7-", suffix=".irc") as fixture:
        fixture.write(replay)
        fixture.flush()
        _, _, quiet = run(sys.argv[1], fixture.name, False)
        if b"birc_profile" in quiet:
            print("hardening_profile: profiler is not default-off", file=sys.stderr)
            return 1
        wall_ms, ready_ms, profiled = run(sys.argv[1], fixture.name, True)
    match = PROFILE_RE.search(profiled)
    if not match:
        print(f"hardening_profile: missing profile: {profiled!r}", file=sys.stderr)
        return 1
    frames, prepare, begin, draw, end = (int(item) for item in match.groups())
    if frames < 2:
        print(f"hardening_profile: only {frames} real frames", file=sys.stderr)
        return 1
    print(
        f"hardening_profile buffers={buffers} lines={lines} bytes={len(replay)} "
        f"frames={frames} "
        f"ready_ms={ready_ms:.1f} wall_ms={wall_ms:.1f} "
        f"prepare_us={prepare} begin_us={begin} "
        f"draw_us={draw} end_us={end}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
