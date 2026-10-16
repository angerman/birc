#!/usr/bin/env python3
"""view_us against line length on the replay path from hardening_profile.

The framer keeps at most 510 octets before LF (512 with CRLF) and drops a
longer record, so the sweep is 64 / 128 / 256 / 510. One quiet run checks
that the profiler stays default-off. Each length then uses the profiled
pty replay. This reports the shape of the after-curve; the previous
per-cluster walk is no longer in the tree.
"""
from __future__ import annotations

import os
import re
import sys
import tempfile

import hardening_profile

WIDTHS = (64, 128, 256, 510)
BUFFERS = 2
LINES = 48
PROFILE_RE = re.compile(
    rb"birc_profile frames=(\d+) prepare_us=(\d+) begin_us=(\d+) "
    rb"draw_us=(\d+) end_us=(\d+) view_us=(\d+)"
)


def corpus(width: int) -> bytes:
    parts: list[bytes] = []
    for buf in range(BUFFERS):
        channel = f"#t{buf}".encode()
        parts.append(b":probe!u@h JOIN " + channel + b"\n")
        prefix = b":p!u@h PRIVMSG " + channel + b" :"
        # `width` is octets before LF. 510 is the largest line the framer keeps.
        body = width - len(prefix)
        if body < 8:
            raise RuntimeError(f"prefix leaves no body at width {width}")
        payload = prefix + b"x" * body
        if len(payload) != width:
            raise RuntimeError(f"line width {len(payload)} != {width}")
        parts.append(payload + b"\n")
    return b"".join(parts)


def view_us(output: bytes) -> int:
    match = PROFILE_RE.search(output)
    if not match:
        raise RuntimeError(f"long_lines: missing profile: {output!r}")
    frames = int(match.group(1))
    if frames < 2:
        raise RuntimeError(f"long_lines: only {frames} real frames")
    return int(match.group(6))


def classify(samples: list[tuple[int, int]]) -> str:
    """Compare successive view_us values with the length ratio.

    flat: view_us stays within 25% while length doubles.
    superlinear: view_us grows by more than 1.5x the length ratio.
    linear: everything between those, including a noisy in-between sample.
    """
    kinds: list[str] = []
    for (left_n, left_us), (right_n, right_us) in zip(samples, samples[1:]):
        if left_us <= 0:
            return "undefined"
        growth = right_us / left_us
        length_ratio = right_n / left_n
        if growth < 1.25:
            kinds.append("flat")
        elif growth > 1.5 * length_ratio:
            kinds.append("superlinear")
        else:
            kinds.append("linear")
    if "superlinear" in kinds:
        return "superlinear"
    if kinds and all(kind == "flat" for kind in kinds):
        return "flat"
    return "linear"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    binary = sys.argv[1]
    samples: list[tuple[int, int]] = []
    quiet_checked = False
    for width in WIDTHS:
        replay = corpus(width)
        if len(replay) > hardening_profile.MAX_REPLAY_BYTES:
            print("long_lines: corpus exceeds replay reader cap", file=sys.stderr)
            return 1
        with tempfile.NamedTemporaryFile(prefix="birc-long-", suffix=".irc") as fixture:
            fixture.write(replay)
            fixture.flush()
            if not quiet_checked:
                _, _, quiet = hardening_profile.run(binary, fixture.name, False)
                if b"birc_profile" in quiet:
                    print("long_lines: profiler is not default-off", file=sys.stderr)
                    return 1
                quiet_checked = True
            _, _, profiled = hardening_profile.run(binary, fixture.name, True)
        measured = view_us(profiled)
        per_line = measured / (BUFFERS * LINES)
        samples.append((width, measured))
        print(
            f"long_lines bytes={width} lines={BUFFERS * LINES} "
            f"view_us={measured} view_us_per_line={per_line:.2f}"
        )
    verdict = classify(samples)
    print("long_lines shape=" + verdict)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
