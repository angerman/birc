#!/usr/bin/env python3
"""History overflow keeps FIFO via pending coalesce; HistStop acks the worker.
Sync-append failure must keep the extract baseline (unsaved IDs retry)."""
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
    assert lines == [
        "filled=yes",
        "save=ok",
        "held-b=yes",
        "save=ok",
        "held-c=yes",
        "stop=yes",
    ], lines
    assert overflow.read_text() == "line-a\nline-b\nline-c\n", overflow.read_text()

    accepted = root / "accepted.log"
    lines = run(accepted, "accepted")
    assert lines == ["accepted=yes", "save=ok"], lines
    assert not accepted.exists(), "accepted enqueue must not sync-write"

    missing = root / "missing.log"
    lines = run(missing, "missing")
    assert lines == ["save=ok"], lines
    assert missing.read_text() == "sync-only\n", missing.read_text()

    # Regular file as parent → open of child path fails closed.
    blocker = root / "not-a-dir"
    blocker.write_text("x")
    bad = blocker / "child.log"
    lines = run(bad, "syncfail")
    assert lines == ["delta=yes", "failed=yes", "baseline=yes", "retry=yes"], lines
    assert not bad.exists(), "failed sync append must not create the child"

    lines = run(root / "fence.log", "fence")
    assert lines == ["save=ok", "fenced=yes"], lines
    assert (root / "fence.log").read_text() == "OLD\nNEW\n", (root / "fence.log").read_text()

    lines = run(root / "queued.log", "queued")
    assert lines == ["failed=no", "kept=yes"], lines

    lines = run(root / "stop-unused.log", "stop")
    assert lines == ["stop=yes"], lines

    # 40000 pending, then on_fail of 40000. Room in the channel admits it.
    lines = run(root / "retry-unused.log", "retry")
    assert lines == ["before=80000", "save=ok", "pending=0"], lines

    # Empty pending on server 1 takes that job's id, base, and seq.
    ident = root / "ident-unused.log"
    lines = run(ident, "ident")
    assert lines == ["ident=yes", "save=ok"], lines
    assert not ident.exists(), "empty-ident mark must not sync-write"

    # History off, same endpoint, nonempty extract: claim must not run.
    off = root / "off.log"
    lines = run(off, "off")
    assert lines == ["off=yes", "same=yes", "moved=yes", "delta=yes", "failed=no"], lines
    assert not off.exists(), "history off appended the unchanged extract"

print("ws_history_enqueue=ok")
