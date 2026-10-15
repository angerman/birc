#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Sample physical footprint across capped-buffer repaints.

Not a check gate. The Bend program prints filled/paint/done. This driver
runs it on a tty so those lines flush, and records footprint -p at each
line. verdict=climbs means the paint loop committed more pages after the
buffer was already full. verdict=flat means it held.

A tentative slope trigger is confirmed by an immediate second run: the
profile trigger fires (trigger=profile, exit 3) only if both runs
trigger, so a single-run transient cannot page. Quiet runs cost one
measurement; see slope_verdict and combine_triggers.
PAINT_SLOPE_TRIGGER / PAINT_R2_TIGHT override the trigger thresholds.

Verdict layers (in priority order):
  1. slope trigger: least-squares slope of KB over the per-paint samples
     is steeply positive with a tight linear fit, sustained by the
     run's second half -> verdict=climbs, trigger=profile, exit 3.
  2. endpoint backstop: end - base >= 2048KB -> verdict=climbs.
  3. flat slope: slope near zero -> verdict=flat even if the endpoints
     wobble inside the unclear band.
  4. otherwise the endpoint verdict (flat <=512KB, else unclear).
"""
from __future__ import annotations

import os
import pty
import re
import select
import subprocess
import sys
import time

FOOTPRINT_RE = re.compile(
    r"^    phys_footprint:\s+([0-9]+(?:\.[0-9]+)?)\s+(KB|MB|GB)\s*$",
    re.M,
)
CLIMB_KB = 2048
FLAT_KB = 512
# Slope verdict, justified from the census in docs/column-walker-retention.md
# ("paint_footprint" paragraph): +784/+800KB at 32 passes and +1617KB at 64
# passes, i.e. ~25KB/paint of sustained growth that the endpoint bands wave
# through as `unclear`. The slope is fit over per-paint samples with
# x = paint index (KB/paint counts renders, not wall time, so sleep jitter
# and machine speed cannot dilute it).
# SLOPE_TRIGGER sits ~3x below the ~25KB/paint census signal so a repeat
# triggers with margin. White-noise slope jitter is far below: the slope
# std of n noisy samples is sigma/sqrt(sum((x-xbar)^2)) ~= sigma/52 at
# n=32, i.e. ~1KB/paint for 50KB sample noise, and the R^2 gate below
# rejects noise independently of scale.
SLOPE_TRIGGER_KB_PER_PAINT = 8.0
# SLOPE_FLAT sits ~12x below the census signal: over the maximum 64 passes
# 2*64=128KB of fitted drift stays well inside the 512KB endpoint flat
# band, so a flat slope with wobbling endpoints is still flat.
SLOPE_FLAT_KB_PER_PAINT = 2.0
# Fit quality: R-squared of the least-squares line. R^2 is used instead of
# an absolute residual band because footprint noise scale varies by machine
# and OS page size while R^2 is dimensionless. A staircase climb keeps
# R^2 ~= 1-(step/total)^2 above 0.9 while no single step exceeds ~30% of
# the total rise; a single sudden step fits a line poorly (R^2 ~0.5-0.75,
# see the synthetic step check) and must not trigger. Threshold 0.9 sits
# between the two; linear climbs with 50KB jitter on an 800KB rise still
# score ~0.95.
R2_TIGHT = 0.9
# Below this many per-paint samples a line fit is not trustworthy (R^2 is
# spuriously high at n=2), so short runs fall back to the endpoint verdict.
MIN_SLOPE_SAMPLES = 8
TRIGGER_PROFILE_EXIT = 3


def _env_float(name: str, default: float) -> float:
    """Tuning/testing override: PAINT_SLOPE_TRIGGER / PAINT_R2_TIGHT replace
    the trigger thresholds; unset or unparsable keeps the default."""
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return default


SLOPE_TRIGGER_EFF = _env_float("PAINT_SLOPE_TRIGGER", SLOPE_TRIGGER_KB_PER_PAINT)
R2_TIGHT_EFF = _env_float("PAINT_R2_TIGHT", R2_TIGHT)


def usage() -> None:
    sys.stderr.write("usage: paint_footprint.py BINARY [PASSES]\n")
    sys.exit(2)


def to_kb(number: str, unit: str) -> int:
    value = float(number)
    if unit == "MB":
        value *= 1024
    elif unit == "GB":
        value *= 1024 * 1024
    return int(value)


def footprint_kb(pid: int) -> int | None:
    try:
        done = subprocess.run(
            ["footprint", "-p", str(pid)],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    text = done.stdout + "\n" + done.stderr
    found = FOOTPRINT_RE.search(text)
    if found is None:
        return None
    return to_kb(found.group(1), found.group(2))


def verdict(delta: int) -> str:
    if delta >= CLIMB_KB:
        return "climbs"
    if delta <= FLAT_KB:
        return "flat"
    return "unclear"


def linfit(ys: list[float]) -> tuple[float, float]:
    """Least-squares line over samples with x = sample index.

    Returns (slope, r_squared). Fewer than 2 samples, or a perfectly
    constant series (zero total variance), yields (0.0, 0.0): a constant
    series is flat, and R^2 is undefined there, so 0.0 keeps it out of the
    tight-fit trigger while the flat-slope rule still applies.
    """
    n = len(ys)
    if n < 2:
        return (0.0, 0.0)
    mean_x = (n - 1) / 2.0
    mean_y = sum(ys) / n
    sxx = sum((i - mean_x) ** 2 for i in range(n))
    if sxx == 0.0:
        return (0.0, 0.0)
    sxy = sum((i - mean_x) * (y - mean_y) for i, y in enumerate(ys))
    slope = sxy / sxx
    intercept = mean_y - slope * mean_x
    ss_tot = sum((y - mean_y) ** 2 for y in ys)
    if ss_tot == 0.0:
        return (0.0, 0.0)
    ss_res = sum((y - (slope * i + intercept)) ** 2 for i, y in enumerate(ys))
    return (slope, max(0.0, 1.0 - ss_res / ss_tot))


def slope_verdict(
    paint_kb: list[int], delta: int
) -> tuple[str, str, float, float, float, int]:
    """Slope-over-samples verdict. Returns (verdict, trigger, slope, r2, tail_slope, exit).

    paint_kb is the per-paint footprint series in paint order; delta is the
    endpoint delta (end - base). trigger is "profile" only for a steep
    positive slope with a tight linear fit that the run's second half
    sustains; anything else reports trigger "none". The tail-agreement
    rule rejects single-run transients localized in one half of the
    series (observed once: a steep tight first-execution climb that never
    reproduced); a genuine per-paint leak climbs in both halves. The
    endpoint backstop (>=2048KB -> climbs) keeps firing even when the
    slope is flat (e.g. one sudden step), so it outranks the flat-slope
    rule; the slope trigger outranks the backstop because a sustained
    tight linear climb is the more specific signal.
    """
    ys = [float(kb) for kb in paint_kb]
    slope, r2 = linfit(ys)
    tail_slope, _ = linfit(ys[len(ys) // 2 :])
    enough = len(paint_kb) >= MIN_SLOPE_SAMPLES
    sustained = tail_slope >= SLOPE_TRIGGER_EFF
    if enough and slope >= SLOPE_TRIGGER_EFF and r2 >= R2_TIGHT_EFF and sustained:
        return ("climbs", "profile", slope, r2, tail_slope, TRIGGER_PROFILE_EXIT)
    if delta >= CLIMB_KB:
        return ("climbs", "none", slope, r2, tail_slope, 0)
    if enough and slope <= SLOPE_FLAT_KB_PER_PAINT:
        return ("flat", "none", slope, r2, tail_slope, 0)
    return (verdict(delta), "none", slope, r2, tail_slope, 0)


def main() -> None:
    if len(sys.argv) not in (2, 3):
        usage()
    binary = sys.argv[1]
    passes = 32
    if len(sys.argv) == 3:
        if not sys.argv[2].isdigit() or not 1 <= int(sys.argv[2]) <= 64:
            usage()
        passes = int(sys.argv[2])
    try:
        first = measure_once(binary, passes)
    except MeasureError as err:
        sys.stderr.write(err.text)
        sys.exit(1)
    if first["trigger"] != "profile":
        print_block(first, with_samples=True)
        sys.stdout.flush()
        sys.exit(first["exit_code"])
    print_block(first, tag="run1")
    try:
        second = measure_once(binary, passes)
    except MeasureError as err:
        sys.stderr.write(err.text)
        sys.exit(1)
    print_block(second, tag="run2", with_samples=True)
    verdict, trigger, exit_code = combine_triggers(first, second)
    sys.stdout.write(f"confirmed={str(trigger == 'profile').lower()}\n")
    sys.stdout.write(f"verdict={verdict}\n")
    sys.stdout.write(f"trigger={trigger}\n")
    sys.stdout.flush()
    sys.exit(exit_code)


class MeasureError(Exception):
    """Fatal harness failure: carries the exact stderr text for main."""

    def __init__(self, text: str) -> None:
        super().__init__(text)
        self.text = text


def combine_triggers(first: dict, second: dict) -> tuple[str, str, int]:
    """Confirm a tentative trigger: profile only if both runs trigger.

    Returns (verdict, trigger, exit). The confirmation run's verdict
    stands, with the ANDed trigger: a tentative climb the second run
    does not sustain downgrades to whatever the second run saw.
    """
    if first["trigger"] == "profile" and second["trigger"] == "profile":
        return ("climbs", "profile", TRIGGER_PROFILE_EXIT)
    return (second["verdict"], "none", 0)


def print_block(res: dict, tag: str | None = None, with_samples: bool = False) -> None:
    """Print one measurement. Untagged output is byte-identical to the
    legacy single-run format; tagged blocks rename verdict/trigger so a
    confirmation pair plus the final lines stay greppable."""
    vkey = f"{tag}_verdict" if tag else "verdict"
    tkey = f"{tag}_trigger" if tag else "trigger"
    if tag:
        sys.stdout.write(f"run={tag}\n")
    sys.stdout.write(f"filled_kb={res['base']}\n")
    sys.stdout.write(f"final_kb={res['end']}\n")
    sys.stdout.write(f"delta_kb={res['delta']}\n")
    sys.stdout.write(f"basis={res['basis']}\n")
    sys.stdout.write(f"paints={res['passes']}\n")
    sys.stdout.write(f"duration_s={res['duration_s']:.2f}\n")
    sys.stdout.write(f"checksum={res['checksum']}\n")
    sys.stdout.write(f"slope_kb_per_paint={res['slope']:.2f}\n")
    sys.stdout.write(f"slope_tail_kb_per_paint={res['tail_slope']:.2f}\n")
    sys.stdout.write(f"r2={res['r2']:.3f}\n")
    sys.stdout.write(f"{tkey}={res['trigger']}\n")
    if with_samples:
        for t, kb, stag in res["samples"]:
            if stag.startswith("filled ") or stag.startswith("paint ") or stag == "start":
                sys.stdout.write(f"sample t={t:.2f} kb={kb} marker={stag}\n")
    sys.stdout.write(f"{vkey}={res['verdict']}\n")


def measure_once(binary: str, passes: int, deadline_s: int = 150) -> dict:
    """Run the binary once on a pty, sample footprint, analyze. Raises
    MeasureError (exact legacy stderr) on harness failure."""
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        [binary, "--gpu", "off", str(passes)],
        stdin=subprocess.DEVNULL,
        stdout=slave,
        stderr=subprocess.PIPE,
        close_fds=True,
    )
    os.close(slave)
    deadline = time.monotonic() + deadline_s
    started = time.monotonic()
    buf = b""
    lines: list[str] = []
    samples: list[tuple[float, int, str]] = []
    marker = "start"

    def take(tag: str) -> None:
        kb = footprint_kb(proc.pid)
        if kb is None:
            return
        samples.append((time.monotonic() - started, kb, tag))

    take("start")
    while True:
        if time.monotonic() > deadline and proc.poll() is None:
            proc.kill()
            raise MeasureError("paint_footprint: timed out\n")
        ready, _, _ = select.select([master], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                chunk = b""
            if chunk:
                buf += chunk
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    text = raw.decode("utf-8", "replace")
                    lines.append(text)
                    marker = text
                    take(text)
                continue
        if proc.poll() is not None:
            break
        take(marker)
    if buf:
        lines.append(buf.decode("utf-8", "replace"))
    os.close(master)
    stderr = proc.stderr.read().decode("utf-8", "replace") if proc.stderr else ""
    code = proc.wait()
    paints = [line for line in lines if line.startswith("paint ")]
    filled = next((line for line in lines if line.startswith("filled ")), "")
    done = next((line for line in lines if line.startswith("done ")), "")
    if code != 0 or not filled or not done or len(paints) != passes:
        text = (
            stderr
            + "paint_footprint: binary failed "
            + f"exit={code} lines={len(lines)} paints={len(paints)}\n"
            + "".join(line + "\n" for line in lines)
        )
        raise MeasureError(text)
    for line in paints:
        parts = line.split()
        if len(parts) != 3 or not parts[2].isdigit() or int(parts[2]) <= 0:
            raise MeasureError(f"paint_footprint: empty paint {line}\n")
    if len(samples) < 2:
        raise MeasureError("paint_footprint: no footprint samples\n")
    paint_times = [t for (t, _, tag) in samples if tag.startswith("paint ")]
    filled_kb = [kb for (_, kb, tag) in samples if tag.startswith("filled ")]
    paint_kb = [kb for (_, kb, tag) in samples if tag.startswith("paint ")]
    separated = (
        len(paint_times) >= 2
        and paint_times[-1] - paint_times[0] >= 0.5
        and bool(filled_kb)
        and bool(paint_kb)
    )
    if separated:
        base = filled_kb[0]
        end = paint_kb[-1]
        basis = "paint-lines"
    else:
        span = samples[-1][0] - samples[0][0]
        cut = samples[0][0] + max(0.5, span * 0.25)
        base = next((kb for (t, kb, _) in samples if t >= cut), samples[len(samples) // 2][1])
        end = samples[-1][1]
        basis = "timer"
    delta = end - base
    decision, trigger, slope, r2, tail_slope, exit_code = slope_verdict(paint_kb, delta)
    return {
        "base": base,
        "end": end,
        "delta": delta,
        "basis": basis,
        "passes": passes,
        "duration_s": samples[-1][0],
        "checksum": paints[-1].split()[2],
        "slope": slope,
        "tail_slope": tail_slope,
        "r2": r2,
        "trigger": trigger,
        "verdict": decision,
        "exit_code": exit_code,
        "samples": samples,
    }


if __name__ == "__main__":
    main()
