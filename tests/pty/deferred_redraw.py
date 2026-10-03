#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""A drained two-command burst must paint its last accepted command.

Only demo data is used. A physical PTY write does not force native frame
ownership; tests/bend/deferred_frame.bend covers that exact callback seam.
No input follows the observation burst until bounded shutdown. Frame profiling
checks a small total budget, not a claim that each idle frame is impossible.
"""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
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

from preferences import Screen


class Demo:
    def __init__(self, binary: Path, folder: Path):
        folder.mkdir(mode=0o700)
        self.screen = Screen()
        self.errors = bytearray()
        self.bytes_seen = 0
        self.master = self.proc = None
        self.stdout_eof = self.stderr_eof = False
        self.finished = False
        slave = None
        try:
            self.master, slave = pty.openpty()
            self.saved = termios.tcgetattr(slave)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
            env = {name: value for name, value in os.environ.items()
                   if not name.startswith(("BIRC_", "TIMUI_"))}
            env.update(TERM="xterm-256color", BIRC_PREFERENCES="none", BIRC_HISTORY="none",
                       BIRC_IMAGES="off", BIRC_FRAME_PROFILE="1", XDG_CONFIG_HOME=str(folder))
            self.proc = subprocess.Popen(
                [str(binary), "--plain", "--demo", "--nick", "probe", "--frames", "0"],
                stdin=slave, stdout=slave, stderr=subprocess.PIPE, env=env, start_new_session=True)
        except BaseException:
            self.close()
            raise
        finally:
            if slave is not None:
                os.close(slave)

    def pump(self, duration=0.04):
        end = time.monotonic() + duration
        while time.monotonic() < end:
            handles = ([] if self.stdout_eof else [self.master]) + (
                [] if self.stderr_eof else [self.proc.stderr.fileno()])
            if not handles:
                return
            for fd in select.select(handles, [], [], min(0.04, max(0, end - time.monotonic())))[0]:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    data = b""
                if fd == self.master:
                    self.stdout_eof = not data
                    self.bytes_seen += len(data)
                    assert self.bytes_seen <= 1048576, "synthetic terminal output exceeded its bound"
                    self.screen.feed(data)
                else:
                    self.stderr_eof = not data
                    self.errors.extend(data)
                    assert len(self.errors) <= 4096, "synthetic stderr exceeded its bound"

    def until(self, predicate, label, seconds=4):
        end = time.monotonic() + seconds
        while not predicate() and time.monotonic() < end:
            assert self.proc.poll() is None, "demo exited during " + label
            self.pump()
        assert predicate(), "timeout: " + label + "\nfinal owned screen:\n" + self.screen.text()[:4096]

    def burst(self, data):
        # One physical write; no retry, split write, or later key can repair
        # the screen during the observation window.
        assert os.write(self.master, data) == len(data), "short synthetic input write"

    def started(self):
        self.until(lambda: "#birc" in self.screen.text() and "hi everyone" in self.screen.text(),
                   "initial demo paint")
        self.pump(0.15)

    def finish(self, *, sent=False, frame_cap=16):
        if not sent:
            self.burst(b"/quit\r")
        end = time.monotonic() + 4
        while self.proc.poll() is None and time.monotonic() < end:
            self.pump()
        assert self.proc.wait(timeout=1) == 0, "deferred paint blocked normal quit"
        self.pump(0.08)
        assert termios.tcgetattr(self.master) == self.saved, "terminal state was not restored"
        reports = re.findall(rb"birc_profile frames=(\d+) ", self.errors)
        assert len(reports) == 1, "missing or duplicate owned frame report"
        frames = int(reports[0])
        assert 1 <= frames <= frame_cap, "unexpected idle/deferred frame growth: " + str(frames)
        self.finished = True
        return frames

    def close(self):
        if self.proc is not None:
            if self.proc.poll() is None:
                try:
                    self.burst(b"/quit\r")
                    end = time.monotonic() + 2
                    while self.proc.poll() is None and time.monotonic() < end:
                        self.pump()
                except (OSError, AssertionError):
                    pass
            if self.proc.poll() is None:
                os.killpg(self.proc.pid, signal.SIGKILL)
            self.proc.wait(timeout=3)
            self.proc.stderr.close()
            if not self.finished:
                restored = termios.tcgetattr(self.master) == self.saved
                print(f"deferred_redraw failure_cleanup exit={self.proc.returncode} "
                      f"terminal_restored={restored} child_reaped=True", flush=True)
                assert self.proc.returncode == 0, "failing-case cleanup did not shut down normally"
                assert restored, "failing-case cleanup did not restore terminal state"
        if self.master is not None:
            os.close(self.master)
            self.master = None


def run_case(binary: Path, folder: Path, mode: str):
    demo = Demo(binary, folder)
    try:
        demo.started()
        if mode == "idle":
            before = dict(demo.screen.cells)
            demo.pump(1.25)
            assert demo.screen.cells == before, "idle demo changed visible cells"
            frames = demo.finish(frame_cap=6)
        elif mode == "halt":
            demo.burst(b"/settings\r/quit\r")
            frames = demo.finish(sent=True)
        else:
            data = b"/set bell off\r" if mode == "single" else b"/settings\r/set bell off\r"
            demo.burst(data)

            def painted():
                text = demo.screen.text()
                if "setting 'bell' is now OFF" not in text:
                    return False
                return mode == "single" or (
                    "*settings*" in text and re.search(r"\bbell\s*:\s*OFF\b", text))

            demo.until(painted, mode + " last accepted command paint without further input")
            # An idle tick cannot introduce duplicate confirmations or a
            # perpetual redraw after the new deferred continuation is drained.
            demo.pump(1.25)
            assert painted(), "idle completion lost the last accepted command paint"
            assert demo.screen.text().count("setting 'bell' is now OFF") == 1, "duplicate command echo"
            frames = demo.finish()
        assert not tuple(folder.iterdir()), "disabled preferences/history created a file"
        print(f"deferred_redraw {mode}=ok frames={frames} child_reaped=True", flush=True)
    finally:
        demo.close()


def deadline(_signum, _frame):
    raise TimeoutError("deferred redraw PTY total wall deadline")


def main(binary: Path):
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(30)
    try:
        with tempfile.TemporaryDirectory(prefix="birc-deferred-redraw-") as directory:
            for mode in ("single", "idle", "halt", "burst"):
                run_case(binary, Path(directory) / mode, mode)
        print("deferred_redraw_pty=ok cases=4 children_reaped=True", flush=True)
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "./build/birc").resolve())
