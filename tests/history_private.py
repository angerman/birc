#!/usr/bin/env python3
"""Synthetic history ownership/permission guards; never access user history."""
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())


def run(path, mode="write", mask=0o022):
    # Child-only umask exposes accidental ambient-mode dependence.
    result = subprocess.run(
        [binary, str(path), mode], capture_output=True, text=True, timeout=5,
        preexec_fn=lambda: os.umask(mask),
    )
    assert result.returncode == 0, (result.returncode, result.stderr)
    return result.stdout.strip()


def private(path):
    assert stat.S_IMODE(path.stat().st_mode) == 0o600, oct(path.stat().st_mode)


with tempfile.TemporaryDirectory(prefix="birc-private-history-") as directory:
    root = Path(directory)
    new = root / "new.log"
    assert run(new) == "save=ok"
    private(new)
    assert new.read_text() == "fixture\n"
    assert run(new, mask=0o077) == "save=ok"
    private(new)
    assert new.read_text() == "fixture\nfixture\n"

    owned = root / "owned.log"
    owned.write_text("retained\n")
    owned.chmod(0o644)
    assert run(owned) == "save=ok"
    private(owned)
    assert owned.read_text() == "retained\nfixture\n"

    link = root / "link.log"
    link.symlink_to(owned)
    before = owned.read_bytes()
    assert run(link).startswith("save=error:history save open failed (")
    assert owned.read_bytes() == before
    assert run(root).startswith("save=error:history save open failed (")
    fifo = root / "fifo"
    os.mkfifo(fifo, 0o600)
    assert run(fifo).startswith("save=error:history save open failed (")

    missing = root / "missing" / "history.log"
    assert run(missing).startswith("save=error:history save open failed (")
    assert run(missing, "empty") == "save=skip"
    assert run(missing, "disabled") == "save=ok"
    assert not missing.exists()
    assert run("", "write") == "save=skip"

print("m21_history_private=ok")
