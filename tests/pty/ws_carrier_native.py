#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""SOURCE UNRUN. Nine owned-PTY carrier cases; no helper/actor descendants."""
import errno
import fcntl
import os
import select
import struct
import subprocess
import sys
import termios
import time

CASES = (("routed", None), ("routed-nil", b"birc: missing routed loop state"),
         ("parked", None), ("parked-nil", b"birc: loop envelope missing"),
         ("parked-net", None), ("parked-tick", None),
         ("parked-some-nil", b"birc: loop envelope missing"),
         ("parked-prefs", None),
         ("parked-prefs-nil", b"birc: loop envelope missing"))
CAP = 131072

# Fixed native open/close bytes for this no-frame owned-PTY fixture only.
# Do not strip arbitrary OSC/CSI sequences or controls from diagnostics.
STARTUP = (b"\x1b[22;0t\x1b]0;birc\x07\x1b[?7l\x1b[?1049h"
           b"\x1b[?1000h\x1b[?1006h\x1b[?2004h\x1b[?1002h")
TEARDOWN = (b"\x1b[?2004l\x1b[?1006l\x1b[?1002l\x1b[?1000l"
            b"\x1b[?25h\x1b[?1049l\x1b[?7h\x1b[23;0t")

def failure_output(data, error):
    return data in (STARTUP + TEARDOWN + error + b"\n",
                    STARTUP + TEARDOWN + error + b"\r\n")

def failure_output_controls():
    for error in (b"birc: missing routed loop state", b"birc: loop envelope missing"):
        good = STARTUP + TEARDOWN + error + b"\n"
        assert failure_output(good, error), "fixed LF diagnostic rejected"
        assert failure_output(good[:-1] + b"\r\n", error), "fixed CRLF diagnostic rejected"
        assert not failure_output(error + b"\n", error), "missing fixed terminal envelope accepted"
        assert not failure_output(good.replace(b"]0;birc", b"]0;foreign", 1), error), "foreign title accepted"
        assert not failure_output(b"\x1b]9;foreign\x07" + good, error), "unknown OSC accepted"
        assert not failure_output(STARTUP + b"\x1b[0m" + TEARDOWN + error + b"\n", error), "unknown CSI accepted"
        assert not failure_output(STARTUP + TEARDOWN + error + b"\x1b[?1002l\n", error), "control inside diagnostic accepted"
        assert not failure_output(STARTUP + TEARDOWN + error + b"\n" + error + b"\n", error), "duplicate diagnostic accepted"
        assert not failure_output(STARTUP + STARTUP + TEARDOWN + error + b"\n", error), "duplicate startup accepted"
        assert not failure_output(STARTUP + TEARDOWN[:-1] + error + b"\n", error), "partial teardown accepted"
        assert not failure_output(STARTUP + TEARDOWN + error + b" fake\n", error), "extra text accepted"

def run_case(binary, mode, error, overall):
    master, slave = os.openpty()
    proc = None
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        before = termios.tcgetattr(slave)
        env = os.environ.copy()
        env.update(TERM="xterm-256color", BIRC_PREFERENCES="none",
                   BIRC_HISTORY="none", BIRC_IMAGES="off", BIRC_IMAGE_CACHE="none",
                   BIRC_CARDS="off", BIRC_NOTIFY="off")
        proc = subprocess.Popen([binary, mode], stdin=slave, stdout=slave,
                                stderr=slave, env=env, close_fds=True)
        deadline = min(overall, time.monotonic() + 8)
        raw = bytearray()
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(mode + ": owned child timed out")
            ready, _, _ = select.select([master], [], [], min(0.05, remaining))
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
                    chunk = b""
                raw.extend(chunk)
                if len(raw) > CAP:
                    raise RuntimeError(mode + ": output exceeds owned bound")
            code = proc.poll()
            if code is not None and not select.select([master], [], [], 0)[0]:
                break
        code = proc.wait(timeout=2)
        restored = termios.tcgetattr(slave) == before
        data = bytes(raw)
        callback = ("carrier_callback:" + mode).encode()
        token = ("carrier_case=ok:" + mode).encode()
        if not restored:
            raise RuntimeError(mode + ": terminal attributes not restored")
        if error is None:
            if (code != 0 or data.count(callback) != 1 or data.count(token) != 1
                    or data.count(b"carrier_callback:") != 1
                    or data.count(b"carrier_case=ok:") != 1):
                raise RuntimeError(mode + ": positive callback/exit oracle failed")
            if b"birc:" in data:
                raise RuntimeError(mode + ": unexpected failure diagnostic")
        else:
            if code <= 0 or data.count(error) != 1:
                raise RuntimeError(mode + ": specific normal failure exit missing")
            if not failure_output(data, error):
                raise RuntimeError(mode + ": failure output is not the exact diagnostic line")
            if b"carrier_callback:" in data or b"carrier_case=ok:" in data:
                raise RuntimeError(mode + ": Nil entered continuation")
            if b"preferences were not fully saved" in data:
                raise RuntimeError(mode + ": false preferences attribution")
        print(mode + ": exit=" + str(code) + " terminal_restored=true bytes=" + str(len(data)))
    finally:
        try:
            if proc is not None and proc.poll() is None:
                proc.kill()  # Only this direct, unreaped child; no process-group sweep.
                proc.wait(timeout=2)
        finally:
            os.close(master)
            os.close(slave)

def main():
    if len(sys.argv) != 2:
        raise RuntimeError("expected exactly one native fixture path")
    failure_output_controls()
    binary = os.path.abspath(sys.argv[1])
    overall = time.monotonic() + 45
    for mode, error in CASES:
        run_case(binary, mode, error, overall)
    print("ws_carrier_native=ok")

if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print("ws_carrier_native: " + str(exc), file=sys.stderr)
        sys.exit(1)
