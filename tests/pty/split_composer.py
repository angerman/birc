#!/usr/bin/env python3
"""wf-composer PTY: one <nick> prefix in the split widget pane.

Stacked splits seat the C text widget in the bottom-most pane and
side-by-side splits in the left-most pane; Bend must paint the <nick>
composer prefix exactly there (split_composer_rect mirrors the C
chooser) with the widget seated immediately after it.

Pins (24x80 demo, nick "birc", prefix "<birc> " is 7 cells wide):
- stacked + side-by-side: every painted composer prefix occupies row 22
  cols 2-8 (bottom pane last row / left pane inner edge; the nick
  starts at col 3). The other pane never carries one (top pane's last
  row is 11, right pane starts col 32), so any second or misplaced
  prefix fails the gate.
- widget/prefix agreement: typing "zzq" parks the cursor at 22;12H
  (widget origin col 9 = 2 + 7) in both layouts.
- degenerate 1-2-col side panes (24x6, 24x4): the process survives and
  resize-back restores the prefix + widget; Escape quits cleanly at
  24x4; /quit still works at 24x10 (smallest side-split width with a
  widget-viable pane).

Known unpinned edge (needs a fix slice, not a gate): at degenerate
widths Bend paints a clipped prefix ("<birc" at 24x6, "<" at 24x4)
while C draws no text widget (zero-inner panes are skipped), so typing
is dead until resize-back or Escape. Single-pane 1-2 cols diverge the
same way (test-pty-tinyquit 1col/2col). Pinning those bytes would bake
in the disagreement; unifying the Bend inner-width rule with the C skip
rule is a src change, out of scope for this gate.
"""
from __future__ import annotations

import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
from pathlib import Path

# Bold-nick "birc": the composer prefix paints "<" + nick_color("birc") +
# bold + "birc" + "> ". Chat/nicks/title/status never emit bold "birc"
# (nicks-list "birc" is unbolded, titles are dim), so each occurrence is
# one painted composer prefix.
PREFIX_SIG = b"\x1b[1mbirc"
CUP = re.compile(rb"\x1b\[(\d+);(\d+)H")


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


def send(fd: int, data: bytes, wait: float = 0.4) -> bytes:
    os.write(fd, data)
    return drain(fd, wait)


def spawn(birc: str, rows: int, cols: int):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
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
    return master, proc


def resize(master: int, proc, rows: int, cols: int) -> bytes:
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    os.kill(proc.pid, signal.SIGWINCH)
    return drain(master, 0.6)


def text_col(out: bytes, cup_end: int, col: int, stop: int) -> int:
    """Advance a 1-based column from a CUP over paint bytes to stop.

    Skips escape sequences (CSI/SGR, OSC, 2-char escapes) as zero-width
    and counts every UTF-8 char as one cell (the prefix run holds only
    ASCII plus the narrow border char).
    """
    i = cup_end
    while i < stop:
        b = out[i]
        if b == 0x1B:
            nxt = out[i + 1:i + 2]
            if nxt == b"[":
                j = i + 2
                while j < len(out) and not 0x40 <= out[j] <= 0x7E:
                    j += 1
                i = j + 1
            elif nxt == b"]":
                j = out.find(b"\x1b\\", i + 2)
                i = j + 2 if j >= 0 else len(out)
            else:
                i += 3 if nxt in (b"(", b")", b"#") else 2
        elif b < 0x80:
            col += 1
            i += 1
        elif b < 0xE0:
            col += 1
            i += 2
        elif b < 0xF0:
            col += 1
            i += 3
        else:
            col += 1
            i += 4
    return col


def prefix_sites(out: bytes) -> list[tuple[int, int]]:
    """(row, col) screen cell of the nick in each painted composer prefix.

    Follows the last CUP before the signature and advances over the
    paint run, so full repaints (CUP 22;1H + border + "<") and diff
    repaints (CUP 22;3H + styles only) resolve to the same cell.
    """
    sites = []
    idx = -1
    while True:
        idx = out.find(PREFIX_SIG, idx + 1)
        if idx < 0:
            return sites
        cups = list(CUP.finditer(out[:idx]))
        if not cups:
            raise AssertionError("composer prefix painted with no CUP address")
        last = cups[-1]
        row = int(last.group(1))
        col = text_col(out, last.end(), int(last.group(2)), idx)
        sites.append((row, col))


def check_single_prefix(out: bytes, layout: str) -> None:
    sites = prefix_sites(out)
    if not sites:
        raise AssertionError(f"{layout}: composer prefix missing from repaint")
    bad = [s for s in sites if s != (22, 3)]
    if bad:
        raise AssertionError(
            f"{layout}: prefix painted outside the widget pane: {bad}")


def check_draft_at_widget(master: int, layout: str) -> None:
    typed = send(master, b"zzq", 0.4)
    if b"zzq" not in typed:
        raise AssertionError(f"{layout}: draft not visible in widget pane")
    if b"\x1b[22;12H" not in typed:
        raise AssertionError(
            f"{layout}: widget not seated after the prefix (want 22;12H)")
    send(master, b"\x7f\x7f\x7f", 0.3)


def full_repaint(master: int, proc) -> bytes:
    resize(master, proc, 24, 79)
    if proc.poll() is not None:
        raise AssertionError("exit on shrink resize")
    back = resize(master, proc, 24, 80)
    if proc.poll() is not None:
        raise AssertionError("exit on resize-back")
    return back


def main_process(birc: str) -> None:
    master, proc = spawn(birc, 24, 80)
    try:
        initial = drain(master, 1.0)
        if b"#birc" not in initial:
            raise AssertionError("initial channel missing")

        stacked = send(master, b"/split server\r", 0.6)
        if b"server" not in stacked or b"[active]" not in stacked:
            raise AssertionError("stacked split did not land")
        if b"\x1b[13;1H" not in stacked:
            raise AssertionError("stacked panes lack the expected geometry")
        check_single_prefix(full_repaint(master, proc), "stacked")
        check_draft_at_widget(master, "stacked")

        side = send(master, b"/split horizontal server\r", 0.6)
        if b"server" not in side or b"#birc" not in side:
            raise AssertionError("side-by-side split did not land")
        if b"\x1b[2;31H" not in side:
            raise AssertionError("side-by-side panes lack the expected geometry")
        check_single_prefix(full_repaint(master, proc), "side-by-side")
        check_draft_at_widget(master, "side-by-side")

        # Degenerate 1-2-col panes: survive, then restore on resize-back.
        # (Exact prefix bytes here are NOT pinned: Bend paints a clipped
        # prefix with no C widget behind it; see module docstring.)
        resize(master, proc, 24, 6)
        if proc.poll() is not None:
            raise AssertionError("exit on 24x6 degenerate panes")
        resize(master, proc, 24, 4)
        if proc.poll() is not None:
            raise AssertionError("exit on 24x4 degenerate panes")
        recovered = resize(master, proc, 24, 80)
        if b"#birc" not in recovered:
            raise AssertionError("split view did not recover after resize-back")
        check_single_prefix(recovered, "recovered")
        if b"\x1b[22;9H" not in recovered:
            raise AssertionError("widget not restored after the prefix")

        send(master, b"/unsplit\r", 0.4)
        send(master, b"/quit\r", 0.2)
        proc.wait(timeout=5)
        if proc.returncode != 0:
            raise AssertionError(f"exit code {proc.returncode}")
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


def esc_process(birc: str) -> None:
    """Escape quits cleanly from a degenerate split (typing is dead)."""
    master, proc = spawn(birc, 24, 80)
    try:
        drain(master, 1.0)
        send(master, b"/split horizontal server\r", 0.6)
        resize(master, proc, 24, 4)
        if proc.poll() is not None:
            raise AssertionError("exit on 24x4 degenerate panes")
        out = send(master, b"\x1b", 1.0)
        try:
            proc.wait(timeout=4)
        except subprocess.TimeoutExpired:
            raise AssertionError("Escape did not quit at 24x4")
        if proc.returncode != 0:
            raise AssertionError(f"Escape exit code {proc.returncode}")
        if b"[?1049l" not in out:
            raise AssertionError("Escape quit left the alternate screen")
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


def boundary_process(birc: str) -> None:
    """/quit still works at 24x10: smallest side-split with a live widget."""
    master, proc = spawn(birc, 24, 80)
    try:
        drain(master, 1.0)
        send(master, b"/split horizontal server\r", 0.6)
        resize(master, proc, 24, 10)
        if proc.poll() is not None:
            raise AssertionError("exit on 24x10 split")
        send(master, b"/quit\r", 0.5)
        try:
            proc.wait(timeout=6)
        except subprocess.TimeoutExpired:
            raise AssertionError("/quit dead at 24x10 split")
        if proc.returncode != 0:
            raise AssertionError(f"/quit exit code {proc.returncode}")
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        os.close(master)


def main() -> int:
    birc = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    try:
        main_process(birc)
        esc_process(birc)
        boundary_process(birc)
    except AssertionError as exc:
        print(f"split_composer: {exc}", file=sys.stderr)
        return 1
    print("split_composer=ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
