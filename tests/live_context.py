#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Facade effects: private archive reads, typed completion, and no-append controls."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    command = sys.argv[1:]
    if not command:
        raise SystemExit("expected fixture command prefix")
    with tempfile.TemporaryDirectory(prefix="birc-live-context-") as directory:
        root = Path(directory)
        archive = root / "history"
        body = "".join(
            f"BIRC2\tirc.example:6697\t*server*\tMSG\t12:00:00\talice\tarchive-{n}\n"
            for n in range(1, 5)
        )
        archive.write_text(body)
        archive.chmod(0o600)
        # Fixtures simulate the read completion purely. No prefs worker is due.
        # Any unintended helper scheduling fails instead of touching user data.
        env = {**os.environ, "BIRC_PREFERENCES": "none", "BIRC_PREFS_HELPER": str(root / "absent-helper")}

        def run(mode):
            result = subprocess.run([*command, mode, str(archive)], env=env,
                                    capture_output=True, timeout=15)
            assert result.returncode == 0 and not result.stderr, result
            fields = dict(part.split("=", 1) for part in result.stdout.decode().strip().split(";"))
            assert archive.read_text() == body, "no-append control unexpectedly modified archive"
            assert fields["checkpoint"] == "1", fields
            return fields

        normal = run("normal")
        assert normal["begin"] == "1" and normal["ready"] == "1", normal
        assert normal["divider"] == "1", normal
        assert normal["queued"] == "none" and normal["rows"] == "archive-2|archive-3|archive-4|", normal
        absent = run("absent")
        assert absent["begin"] == "1" and absent["rows"] == "archive-1|archive-2|archive-3|archive-4|", absent
        assert absent["divider"] == "1", absent
        # (-) These branches contain local rows but must never call native append.
        for mode, permission in (("off", "1"), ("invalid", "0")):
            got = run(mode)
            assert got["begin"] == "1" and got["ready"] == "1", got
            assert got["allowed"] == permission and got["rows"] == "local status|", got
            assert got["divider"] == "0", got
        # (-/+) Accepted policy changes reject old results and queue one new read.
        for mode, queued in (("cap", "1:1:1"), ("offedit", "1:3:0")):
            got = run(mode)
            assert got["begin"] == "0" and got["ready"] == "0", got
            assert got["queued"] == queued and "archive-" not in got["rows"], got
            assert got["divider"] == "0", got
        for mode in ("wronggen", "wrongep"):
            got = run(mode)
            assert got["begin"] == "0" and got["ready"] == "0" and got["queued"] == "1:3:1", got
            assert got["rows"] == "", got
            assert got["divider"] == "0", got
        wrong = run("wrongticket")
        assert wrong["begin"] == "0" and wrong["ready"] == "0" and wrong["queued"] == "0:3:1", wrong
        assert wrong["divider"] == "0", wrong
        dropped = run("drop")
        assert dropped["begin"] == "1" and dropped["ready"] == "1" and dropped["rows"] == "local status|", dropped
        assert dropped["divider"] == "0", dropped
    print("live_context_io=ok")


if __name__ == "__main__":
    main()
