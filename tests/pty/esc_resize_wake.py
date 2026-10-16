#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Diagnose lone ESC after resize without treating a later wake as a pass.

Preserve tinyquit's 1 s startup, resize, 1 s drain, ESC, and 6 s quit bound.
Retain raw terminal output and a unique existing TIMUI_TRACE for each case.
Only after recording an original failure, try a SIGWINCH-only wake for 2 s.
Usage: esc_resize_wake.py ./build/birc [artifact-root]
"""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time


MAX_OUTPUT = 8 * 1024 * 1024
WHOLE_SECONDS = 90.0


def drain(master, output, raw, until):
    while time.monotonic() < until:
        ready, _, _ = select.select([master], [], [], 0)
        if not ready:
            return
        try:
            data = os.read(master, 65536)
        except OSError:
            return
        if not data:
            return
        if len(output) + len(data) > MAX_OUTPUT:
            raise RuntimeError("raw terminal capture exceeded 8 MiB")
        output.extend(data)
        raw.write(data)


def pump(master, output, raw, seconds, whole_deadline, proc=None):
    end = time.monotonic() + seconds
    if end > whole_deadline:
        raise RuntimeError("whole diagnostic deadline reached")
    while time.monotonic() < end:
        drain(master, output, raw, min(end, time.monotonic() + 0.05))
        if proc is not None and proc.poll() is not None:
            break
        time.sleep(min(0.05, max(0.0, end - time.monotonic())))
    drain(master, output, raw, min(whole_deadline, time.monotonic() + 0.05))
    raw.flush()


def tty_restored(master, before):
    try:
        return termios.tcgetattr(master) == before
    except termios.error:
        return False


def run(birc, label, resize, payload, artifacts, sandbox_home, whole_deadline):
    master, slave = pty.openpty()
    before = termios.tcgetattr(slave)
    initial_size = (1, 1)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", *initial_size, 0, 0))
    raw_path = artifacts / (label + ".raw")
    trace_path = artifacts / (label + ".trace")
    env = {**os.environ, "HOME": sandbox_home, "TERM": "xterm-256color", "BIRC_HISTORY": "none", "BIRC_PREFERENCES": "none",
           "BIRC_HISTORY": "none", "BIRC_IMAGES": "off",
           "TIMUI_TRACE": str(trace_path)}
    env.pop("BIRC_FRAME_PROFILE", None)
    proc = None
    output = bytearray()
    result = {"case": label, "original_pass": False, "rescue_attempted": False,
              "rescue_pass": False, "raw": str(raw_path), "trace": str(trace_path),
              "state_wait_trace_available": False}
    with raw_path.open("wb") as raw:
        try:
            proc = subprocess.Popen([birc, "--plain", "--demo", "--frames", "20000"],
                                    stdin=slave, stdout=slave, stderr=slave,
                                    close_fds=True, env=env)
            os.close(slave)
            slave = -1
            pump(master, output, raw, 1.0, whole_deadline)
            if resize:
                fcntl.ioctl(master, termios.TIOCSWINSZ,
                            struct.pack("HHHH", 24, 80, 0, 0))
                proc.send_signal(signal.SIGWINCH)
                pump(master, output, raw, 1.0, whole_deadline)
            if proc.poll() is not None:
                raise RuntimeError("child exited before the input probe")
            if os.write(master, payload) != len(payload):
                raise RuntimeError("input probe was only partially written")
            input_at = time.monotonic()
            pump(master, output, raw, 6.0, whole_deadline, proc)
            alive = proc.poll() is None
            result.update(original_alive=alive, original_exit=proc.returncode,
                          original_wait_ms=round((time.monotonic() - input_at) * 1000, 3),
                          original_restored=b"[?1049l" in output,
                          original_tty_restored=tty_restored(master, before),
                          original_bytes=len(output))
            result["original_pass"] = not alive and proc.returncode == 0 and result["original_restored"]
            if alive:
                # This wake is diagnostic evidence, never an original pass.
                result["rescue_attempted"] = True
                rescue_at = time.monotonic()
                proc.send_signal(signal.SIGWINCH)
                pump(master, output, raw, 2.0, whole_deadline, proc)
                result.update(rescue_alive=proc.poll() is None, rescue_exit=proc.returncode,
                              rescue_wait_ms=round((time.monotonic() - rescue_at) * 1000, 3),
                              rescue_restored=b"[?1049l" in output,
                              rescue_tty_restored=tty_restored(master, before))
                result["rescue_pass"] = proc.poll() is not None and proc.returncode == 0 and result["rescue_restored"]
        except Exception as exc:
            result["diagnostic_error"] = str(exc)
        finally:
            if proc is not None and proc.poll() is None:
                proc.kill()
                try:
                    proc.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    result["cleanup_error"] = "SIGKILL child was not reaped within 1 s"
            if proc is not None:
                result["final_exit"] = proc.poll()
            try:
                drain(master, output, raw, time.monotonic() + 0.1)
            except Exception as exc:
                result["cleanup_error"] = str(exc)
            result["total_bytes"] = len(output)
            try:
                termios.tcsetattr(master, termios.TCSANOW, before)
            except termios.error:
                pass
            if slave >= 0:
                os.close(slave)
            os.close(master)
    trace = trace_path.read_bytes() if trace_path.exists() else b""
    result["trace_read_esc_alone"] = b"READ  \\e\n" in trace
    if result["original_pass"]:
        result["classification"] = "original-pass"
    elif result["rescue_pass"]:
        result["classification"] = "original-fail-sigwinch-rescued"
    else:
        result["classification"] = "original-fail"
    print("esc_resize_wake " + json.dumps(result, sort_keys=True), flush=True)
    return result


def main():
    birc = str(Path(sys.argv[1] if len(sys.argv) > 1 else "./build/birc").resolve())
    artifact_root = Path(sys.argv[2] if len(sys.argv) > 2 else "build").resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix="review-esc-resize-wake-", dir=artifact_root))
    whole_deadline = time.monotonic() + WHOLE_SECONDS
    with tempfile.TemporaryDirectory(prefix="birc-esc-home-") as sandbox_home:
        results = [run(birc, label, resize, payload, artifacts, sandbox_home, whole_deadline)
                   for label, resize, payload in
                   [("no-resize-esc", False, b"\x1b"),
                    ("resize-quit", True, b"/quit\r"),
                    ("resize-esc", True, b"\x1b")]]
    (artifacts / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    ok = all(result["original_pass"] and result.get("original_tty_restored", False)
             and "cleanup_error" not in result for result in results)
    print("esc_resize_wake artifacts=" + str(artifacts), flush=True)
    print("esc_resize_wake=" + ("ok" if ok else "original-failure"), flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
