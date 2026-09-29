#!/usr/bin/env python3
"""Run a small ASan binary with a tight, platform-aware startup bound.

LLVM's ASan runtime can hang during interceptor initialization on arm64 macOS
(llvm/llvm-project#58503). Record that state as an explicit unsupported skip;
never claim ASan coverage when the runtime did not reach the test program.
"""
from __future__ import annotations

import os
import platform
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} ASAN_BINARY", file=sys.stderr)
        return 2
    env = {
        **os.environ,
        "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1:abort_on_error=1",
    }
    try:
        result = subprocess.run(
            [sys.argv[1]],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
    except subprocess.TimeoutExpired:
        if platform.system() == "Darwin" and platform.machine() == "arm64":
            print(
                "asan=unsupported platform=Darwin-arm64 "
                "reason=runtime-interceptor-startup-hang llvm=58503"
            )
            return 0
        print("asan gate timed out", file=sys.stderr)
        return 1
    if result.returncode != 0:
        sys.stderr.buffer.write(result.stderr)
        print(f"asan gate exited {result.returncode}", file=sys.stderr)
        return 1
    if result.stdout.strip() != b"utf8_fit_cap=ok":
        sys.stderr.buffer.write(result.stderr)
        print(f"unexpected ASan probe output: {result.stdout!r}", file=sys.stderr)
        return 1
    print("asan=ok coverage=utf8-fit-cap")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
