#!/usr/bin/env python3
"""Synthetic save failures and successful/disabled controls; no user history."""
import subprocess
import sys
import tempfile
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())


def run(path, mode):
    result = subprocess.run([binary, str(path), mode], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, (mode, result.returncode, result.stderr)
    assert "secret" not in result.stdout and "https://" not in result.stdout, result.stdout
    return result.stdout.strip()


with tempfile.TemporaryDirectory(prefix="birc-history-save-") as directory:
    root = Path(directory)
    path = root / "history.log"
    assert run(path, "write") == "save=ok"
    assert path.read_text() == "fixture\n"
    assert run(path, "write") == "save=ok"
    assert path.read_text() == "fixture\nfixture\n"
    assert run(root / "injected.log", "inject") == "save=error:history save write failed (5)"
    assert run(root, "write").startswith("save=error:history save open failed (")
    missing = root / "missing" / "history.log"
    assert run(missing, "write").startswith("save=error:history save open failed (")
    assert run(missing, "disabled") == "save=ok"
    assert run(missing, "empty") == "save=ok"
    assert not missing.exists()
    assert run("", "write") == "save=ok"

print("history_save_errors=ok")
