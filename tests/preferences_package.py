#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Exercise the provisioned literal helper, never the real user configuration."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib

helper = sys.argv[1] if len(sys.argv) > 1 else "birc-preferences"
wire = "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\n"
with tempfile.TemporaryDirectory(prefix="birc-preferences-package-") as directory:
    path = Path(directory) / "preferences.toml"
    env = {**os.environ, "BIRC_PREFERENCES": str(path)}
    def run(action, host="", port="0", body=b""):
        return subprocess.run([helper, action, host, port], input=body, env=env,
                              capture_output=True, timeout=10)
    initial = run("read")
    assert initial.returncode == 0 and initial.stdout == initial.stderr == b""
    saved = run("write", body=wire.encode())
    assert saved.returncode == 0 and saved.stdout == saved.stderr == b""
    loaded = run("read")
    assert loaded.returncode == 0 and loaded.stdout == (wire + "scope\t0\n").encode()
    assert not loaded.stderr and tomllib.loads(path.read_text())["servers"] == []
    assert path.stat().st_mode & 0o777 == 0o600
    assert run("write", "irc.example", "6697", (wire + "channel\t#a\n").encode()).returncode == 0
    assert run("read", "irc.example", "6697").stdout == (wire + "channel\t#a\n").encode()
    # Unknown versions and unsafe final names remain unchanged, with no diagnostics.
    path.write_text("version = 999\n")
    rejected = run("write", body=wire.encode())
    assert rejected.returncode == 2 and rejected.stdout == rejected.stderr == b""
    assert path.read_text() == "version = 999\n"
    disabled = {**env, "BIRC_PREFERENCES": "none"}
    result = subprocess.run([helper, "write", "", "0"], input=wire.encode(), env=disabled,
                            capture_output=True, timeout=10)
    assert result.returncode == 0 and result.stdout == result.stderr == b""
    assert path.read_text() == "version = 999\n"
print("preferences_package=ok")
