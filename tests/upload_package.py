#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed uploader is the linked native effect, not a Python helper."""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile


def run(command, env):
    return subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


def provenance(binary: Path) -> None:
    wrapper = binary.read_text()
    found = re.findall(r"BIRC_UPLOAD_HELPER=\$\{BIRC_UPLOAD_HELPER-'([^']+)'\}", wrapper)
    assert found == ["native"], "installed upload default is not native"
    assert "birc-upload" not in wrapper, "installed wrapper still ships Python upload"
    bundles = re.findall(r"/nix/store/[^\s'\"{}]+/etc/ssl/certs/ca-bundle\.crt", wrapper)
    assert len(set(bundles)) == 1 and Path(bundles[0]).is_file(), "installed CA bundle missing"


def main(argument: str) -> None:
    target = Path(argument).resolve()
    binary = target / "bin/birc" if target.is_dir() else target
    provenance(binary)
    with tempfile.TemporaryDirectory(prefix="birc-upload-package-") as temporary:
        root = Path(temporary)
        env = {"HOME": str(root), "TMPDIR": str(root), "PATH": "", "LANG": "C",
               "BIRC_HISTORY": "none", "BIRC_IMAGES": "off", "BIRC_UPLOAD_HELPER": "native"}
        smoke = run([str(binary), "--demo", "--frames", "1"], env)
        assert smoke.returncode == 0 and not smoke.stderr, "installed client cannot start without ambient helpers"
    print("upload_package=ok")


if __name__ == "__main__":
    try:
        assert len(sys.argv) == 2, "expected installed package or birc wrapper path"
        main(sys.argv[1])
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"upload_package: {error}", file=sys.stderr)
        raise SystemExit(1)
