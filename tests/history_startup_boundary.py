#!/usr/bin/env python3
"""Exercise full-cap archive reads with owned synthetic data only."""
from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys
import tempfile


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("expected startup boundary fixture command")
    binary = pathlib.Path(shutil.which(sys.argv[1]) or sys.argv[1]).resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="birc-startup-boundary-") as directory:
        history = pathlib.Path(directory) / "archive"
        history.write_text(
            "".join(
                f"BIRC2\tirc.example:6667\t#room\tMSG\t12:00:00\talice\trow{index}\n"
                for index in range(1024)
            ),
            encoding="utf-8",
        )
        history.chmod(0o600)
        result = subprocess.run(
            [str(binary), *sys.argv[2:], str(history)],
            capture_output=True, text=True, timeout=25,
        )
        print(result.stdout, end="", flush=True)
        if result.returncode != 0:
            print(result.stderr, end="", file=sys.stderr, flush=True)
            raise SystemExit(result.returncode)
        if not result.stdout.rstrip().endswith("history_startup_boundary=ok"):
            raise SystemExit("missing startup boundary result")


if __name__ == "__main__":
    main()
