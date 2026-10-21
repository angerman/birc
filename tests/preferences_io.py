#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Actual Bend preferences boundary: native file IO and helper diagnostics."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile


WIRE = ("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\n"
        "mute\talice*#room@irc.example\nchannel\t+#room\nchannel\t#日本語\n")


def main():
    binary = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="birc-preferences-io-") as directory:
        root = Path(directory)
        path = root / "preferences.toml"
        env = {**os.environ, "BIRC_PREFS_HELPER": "native", "BIRC_PREFERENCES": str(path)}

        def run(mode, extra=None):
            result = subprocess.run([str(binary), mode], env=extra or env,
                                    capture_output=True, timeout=10)
            assert result.returncode == 0 and not result.stderr, result
            return result.stdout.decode().removesuffix("\n")

        initial = run("read")
        assert initial == "0:absent\n", repr(initial)
        assert run("write") == "0\n"
        assert run("read") == "0:" + WIRE
        path.write_text("version = 999\n")
        path.chmod(0o600)
        assert run("read") == "2:absent\n"
        assert run("write") == "2\n" and path.read_text() == "version = 999\n"
        helper = root / "helper path"
        helper.write_text("#!/bin/sh\nprintf 'private child stdout\\n'\n")
        helper.chmod(0o700)
        fake = {**env, "BIRC_PREFS_HELPER": str(helper)}
        assert run("read", fake) == "2:absent\n" and run("write", fake) == "2\n"
        helper.write_text("#!/bin/sh\nprintf 'private stdout\\n'\nprintf 'private stderr\\n' >&2\nexit 7\n")
        assert run("read", fake) == "7:absent\n" and run("write", fake) == "7\n"
        none = {**env, "BIRC_PREFERENCES": "none"}
        assert run("read", none) == "0:absent\n" and run("write", none) == "0\n"
        assert path.read_text() == "version = 999\n"
    print("preferences_io=ok")


if __name__ == "__main__":
    main()
