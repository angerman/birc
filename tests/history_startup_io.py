#!/usr/bin/env python3
"""Qualify the startup archive worker using owned synthetic files only."""
from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys
import tempfile


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("expected startup worker fixture command")
    binary = pathlib.Path(shutil.which(sys.argv[1]) or sys.argv[1]).resolve(strict=True)
    command = [str(binary), *sys.argv[2:]]
    with tempfile.TemporaryDirectory(prefix="birc-startup-history-") as directory:
        history = pathlib.Path(directory) / "archive"
        history.write_text(
            "BIRC2\tirc.example:6667\t#room\tMSG\t12:00:00\talice\tone\n"
            "BIRC2\tirc.example:6668\t#wrong\tMSG\t12:00:01\talice\twrong endpoint\n"
            "BIRC2\tirc.example:6667\t#room\tMSG\t12:00:02\talice\ttwo\n",
            encoding="utf-8",
        )
        history.chmod(0o600)
        result = subprocess.run(
            [*command, str(history)], capture_output=True, text=True, timeout=20
        )
        if result.returncode != 0 or result.stdout.strip() != "history_startup_io=ok":
            raise SystemExit(
                f"startup worker failed: status={result.returncode}, "
                f"stdout={result.stdout!r}, stderr={result.stderr!r}"
            )
    print("history_startup_io=ok")


if __name__ == "__main__":
    main()
