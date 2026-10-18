#!/usr/bin/env python3
"""Full worker channel must sync-append; accepted enqueue must not drop bytes."""
import subprocess
import sys
import tempfile
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())


def run(path, mode):
    result = subprocess.run(
        [binary, str(path), mode], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (mode, result.returncode, result.stderr, result.stdout)
    return result.stdout.strip().splitlines()


with tempfile.TemporaryDirectory(prefix="birc-ws-hist-enq-") as directory:
    root = Path(directory)

    overflow = root / "overflow.log"
    lines = run(overflow, "overflow")
    assert lines == ["filled=yes", "save=ok", "save=ok"], lines
    assert overflow.read_text() == "line-a\nline-b\n", overflow.read_text()

    accepted = root / "accepted.log"
    lines = run(accepted, "accepted")
    assert lines == ["accepted=yes", "save=ok"], lines
    assert not accepted.exists(), "accepted enqueue must not sync-write"

    missing = root / "missing.log"
    lines = run(missing, "missing")
    assert lines == ["save=ok"], lines
    assert missing.read_text() == "sync-only\n", missing.read_text()

print("ws_history_enqueue=ok")
