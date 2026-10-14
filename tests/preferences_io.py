#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Actual Bend helper boundary, bounded child calls, private synthetic files only."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile


SOURCE = Path(__file__).resolve().parents[1] / "src/launcher/preferences_birc.py"
WIRE = ("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\n"
        "mute\talice*#room@irc.example\nchannel\t+#room\nchannel\t#日本語\n")


def main():
    binary = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="birc-preferences-io-") as directory:
        root = Path(directory)
        helper = root / "helper path"
        helper.write_text(f"#!{sys.executable}\nimport runpy\nrunpy.run_path({str(SOURCE)!r}, run_name='__main__')\n")
        helper.chmod(0o700)
        path = root / "preferences.toml"
        env = {**os.environ, "BIRC_PREFS_HELPER": str(helper), "BIRC_PREFERENCES": str(path)}
        def run(mode):
            result = subprocess.run([str(binary), mode], env=env, capture_output=True, timeout=10)
            assert result.returncode == 0 and not result.stderr, result
            # Bend IO.print appends one newline after its supplied text.
            return result.stdout.decode().removesuffix("\n")
        initial = run("read")
        assert initial == "0:absent\n", repr(initial)
        assert run("write") == "0\n"
        assert run("read") == "0:" + WIRE
        path.write_text("version = 999\n")
        assert run("read") == "2:absent\n"
        assert run("write") == "2\n" and path.read_text() == "version = 999\n"
        # (-) Unexpected child output is not copied into diagnostics or accepted.
        helper.write_text(f"#!{sys.executable}\nprint('private child stdout')\n")
        assert run("read") == "2:absent\n" and run("write") == "2\n"
        helper.write_text(f"#!{sys.executable}\nimport sys\nprint('private stdout')\nprint('private stderr', file=sys.stderr)\nsys.exit(7)\n")
        assert run("read") == "7:absent\n" and run("write") == "7\n"
        # (+) Disabled writes do not create or rewrite a user file.
        helper.write_text(f"#!{sys.executable}\nimport runpy\nrunpy.run_path({str(SOURCE)!r}, run_name='__main__')\n")
        env["BIRC_PREFERENCES"] = "none"
        assert run("read") == "0:absent\n" and run("write") == "0\n"
        assert path.read_text() == "version = 999\n"
    print("preferences_io=ok")


if __name__ == "__main__":
    main()
