#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""NATIVE-TESTED (four cases). Actual native media stages with a synthetic recording helper.

No network, uploads, URL reads, source-file reads, PTY, or production test hooks.
The clear decision is exercised but not directly observed; clear-before-spawn
remains a source-order check, not a claim inferred from helper start timestamps.
"""
import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import tempfile
import time

CASES = (("free", 1), ("blocked", 0), ("jobs-none", 0), ("jobs-some", 1))
CAP = 131072


def run_case(binary, mode, calls, overall):
    with tempfile.TemporaryDirectory(prefix="birc-media-stage-") as directory:
        root = Path(directory)
        log = root / "calls.jsonl"
        helper = root / "helper"
        helper.write_text("#!" + sys.executable + "\n" + r'''
import json, os, sys
args = sys.argv[1:]
with open(os.environ["BIRC_TEST_MEDIA_LOG"], "a", encoding="utf-8") as out:
    out.write(json.dumps(args) + "\n")
if args != ["--local", "media-stage-fixture.png"]:
    raise SystemExit(2)
print("synthetic-media-result", flush=True)
''', encoding="utf-8")
        helper.chmod(0o700)
        env = os.environ.copy()
        for name in ("TIMUI_TRACE", "BIRC_FRAME_PROFILE", "BIRC_DIE_AFTER_OPEN"):
            env.pop(name, None)
        env.update(BIRC_MEDIA_HELPER=str(helper), BIRC_TEST_MEDIA_LOG=str(log),
                   BIRC_PREFERENCES="none", BIRC_HISTORY="none",
                   BIRC_IMAGE_CACHE="none", BIRC_CARDS="off", BIRC_NOTIFY="off")
        proc = subprocess.Popen([binary, mode], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                env=env, close_fds=True)
        raw = bytearray()
        try:
            deadline = min(overall, time.monotonic() + 8)
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError(mode + ": owned child timed out")
                ready, _, _ = select.select([proc.stdout], [], [], min(0.05, remaining))
                if ready:
                    chunk = os.read(proc.stdout.fileno(), 4096)
                    raw.extend(chunk)
                    if len(raw) > CAP:
                        raise RuntimeError(mode + ": output exceeds bound")
                    if not chunk:
                        break
            code = proc.wait(timeout=min(2, max(0.01, overall - time.monotonic())))
            token = ("ws_media_stage_native=ok:" + mode + "\n").encode()
            if code != 0 or bytes(raw).count(token) != 1:
                raise RuntimeError(mode + ": exact stage result/exit missing")
            # Native open enables mouse even on a pipe. Strip CSI and CR only;
            # assertions, ordinary extra text, and all other controls still fail.
            plain = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", bytes(raw)).replace(b"\r", b"")
            if plain != token:
                raise RuntimeError(mode + ": unexpected native output")
            if log.exists() and log.stat().st_size > 4096:
                raise RuntimeError(mode + ": helper log exceeds bound")
            rows = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            if rows != [["--local", "media-stage-fixture.png"]] * calls:
                raise RuntimeError(mode + ": helper count or literal arguments differ")
            print(mode + ": exit=0 helper_calls=" + str(len(rows)))
        finally:
            if proc.poll() is None:
                proc.kill()  # Only the owned unreaped child; no process-group sweep.
                proc.wait(timeout=2)
            proc.stdout.close()


def main():
    if len(sys.argv) != 2:
        raise RuntimeError("expected one native fixture path")
    binary = os.path.abspath(sys.argv[1])
    overall = time.monotonic() + 45
    for mode, calls in CASES:
        run_case(binary, mode, calls, overall)
    print("ws_media_stage_native=ok")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as exc:
        print("ws_media_stage_native: " + str(exc), file=sys.stderr)
        sys.exit(1)
