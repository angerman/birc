#!/usr/bin/env python3
"""Real helper failures/success/timeout without a desktop clipboard."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

binary = str(Path(sys.argv[1]).resolve())


def run(program, capture):
    result = subprocess.run([binary, str(program)], capture_output=True, text=True, timeout=4,
                            env={**os.environ, "BIRC_TEST_CLIPBOARD_INPUT": str(capture)})
    assert result.returncode == 0, (result.returncode, result.stderr)
    assert "pasted-secret" not in result.stdout and "https://" not in result.stdout, result.stdout
    return result.stdout.strip()


with tempfile.TemporaryDirectory(prefix="birc-clipboard-errors-") as directory:
    root = Path(directory)
    capture = root / "copied"
    for mode, suffix in (("success", "exit 0"), ("failed", "exit 7"),
                         ("timeout", "exec /bin/sleep 3")):
        helper = root / (mode + " with spaces")
        helper.write_text('#!/bin/sh\n/bin/cat > "$BIRC_TEST_CLIPBOARD_INPUT"\n'
                          'printf "pasted-secret https://unused.invalid/private\\n" >&2\n' + suffix + "\n")
        helper.chmod(0o700)
        output = run(helper, capture)
        assert capture.read_text() == "pasted-secret https://unused.invalid/private"
        if mode == "success":
            assert output == "clipboard=ok", output
        elif mode == "failed":
            assert output == "clipboard=error:clipboard helper failed (exit 7)", output
        else:
            assert output.startswith("clipboard=error:clipboard helper failed ("), output
    assert run(root / "missing", capture).startswith("clipboard=error:clipboard helper failed (OS ")
    capture.unlink()
    assert run("", capture) == "clipboard=ok"
    assert not capture.exists()

print("clipboard_errors=ok")
