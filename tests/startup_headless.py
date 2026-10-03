#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Headless single-read preparation with owned files and a literal fake helper."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    bun, driver = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="birc-startup-headless-") as directory:
        root = Path(directory)
        helper = root / "helper"
        calls = root / "calls"
        archive = root / "history"
        archive.write_text("".join(
            f"BIRC2\tirc.example:6697\t*server*\tMSG\t12:00:00\talice\tarchive-{n}\n"
            for n in range(1, 4)
        ) + "BIRC2\tother.example:6697\t*server*\tMSG\t12:00:00\tbob\twrong-scope\n")
        env = {**os.environ, "BIRC_PREFS_HELPER": str(helper), "BIRC_PREFERENCES": "none"}

        def fake(history=True, code=0, absent=False):
            wire = "" if absent else (
                f"BIRC_PREFS1\nsettings\t0\t0\t0\t{int(history)}\t1\t0\t0\t0\nchannel\t#saved\n"
            )
            helper.write_text(f"#!{sys.executable}\n"
                              "import pathlib, sys\n"
                              f"p = pathlib.Path({str(calls)!r})\n"
                              "with p.open('a') as f: f.write('read\\n')\n"
                              "assert sys.argv[1:] == ['read', 'irc.example', '6697']\n"
                              f"sys.stdout.write({wire!r})\n"
                              f"sys.exit({code})\n")
            helper.chmod(0o700)

        def run(mode="normal", path=archive):
            previous = calls.read_text().count("\n") if calls.exists() else 0
            result = subprocess.run([bun, driver, mode, str(path)], env=env,
                                    capture_output=True, timeout=15)
            assert result.returncode == 0 and not result.stderr, result
            fields = dict(part.split("=", 1) for part in result.stdout.decode().strip().split(";"))
            assert fields["auth"] == "1", fields
            current = calls.read_text().count("\n") if calls.exists() else 0
            assert current - previous == (0 if mode == "disabled" else 1), fields
            return fields

        # (+) One preference read, then the final saved cap controls restoration.
        fake()
        assert run() == {"allowed": "1", "history": "1", "cap": "1",
                         "rows": "archive-3|", "divider": "1", "names": "#saved", "auth": "1", "pending": "0"}
        # (+) Explicit launch channels remain authoritative and queued for drain.
        explicit = run("explicit")
        assert explicit["names"] == "#initial" and explicit["pending"] == "1", explicit
        assert explicit["divider"] == "1", explicit
        # (-) Saved history off must not present archived rows.
        fake(history=False)
        off = run()
        assert off["history"] == "0" and off["rows"] == "", off
        assert off["divider"] == "0", off
        # (-) Unknown/failed preference policy cannot restore default archive rows.
        fake(code=2, absent=True)
        failed = run()
        assert failed["allowed"] == "0" and failed["rows"] == "", failed
        assert failed["divider"] == "0", failed
        # (+) Disabled preferences never call the helper and preserve defaults.
        disabled = run("disabled")
        assert disabled["allowed"] == "1" and disabled["history"] == "1", disabled
        assert disabled["rows"] == "archive-1|archive-2|archive-3|", disabled
        assert disabled["names"] == "#initial" and disabled["pending"] == "0", disabled
        assert disabled["divider"] == "1", disabled
        # (+) Missing configuration uses the original policy and imports once.
        fake(absent=True)
        absent = run()
        assert absent["allowed"] == "1" and absent["rows"] == disabled["rows"], absent
        assert absent["divider"] == "1", absent
        # (-) Empty archives never add a startup divider to local-only buffers.
        archive.write_text("")
        empty = run()
        assert empty["rows"] == "" and empty["divider"] == "0", empty
    print("startup_headless_io=ok")


if __name__ == "__main__":
    main()
