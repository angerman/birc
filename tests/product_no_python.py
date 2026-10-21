#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Production package inputs must not mention or wrap python3."""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    birc_nix = (ROOT / "nix/birc.nix").read_text()
    assert "python3" not in birc_nix, "nix/birc.nix still depends on python3"
    assert "keychain_birc.py" not in birc_nix, "nix/birc.nix still installs the Python Keychain wrapper"
    assert "birc-upload" not in birc_nix, "nix/birc.nix still ships birc-upload"
    assert "BIRC_UPLOAD_HELPER native" in birc_nix, "packaged upload default is not native"
    assert "src/ffi/keychain_birc.c" in birc_nix, "packaged keychain-birc is not the C launcher"
    flake = (ROOT / "flake.nix").read_text()
    packages = flake.split("devShells")[0]
    assert "python3" not in packages, "flake packages still mention python3"
    assert not (ROOT / "nix/upload.nix").exists(), "leftover Python upload package still present"
    for path in (ROOT / "src/bend").glob("*.bend"):
        text = path.read_text()
        assert not re.search(r"python3", text), f"{path.name} still names python3"
    shown = subprocess.run(
        ["nix", "--extra-experimental-features", "nix-command flakes",
         "derivation", "show", "--no-update-lock-file", ".#birc"],
        cwd=ROOT, capture_output=True, text=True, timeout=90)
    assert shown.returncode == 0, "could not evaluate the birc package derivation"
    text = shown.stdout
    assert "python3" not in text and "python-3" not in text, "birc derivation still mentions python"
    data = json.loads(text)
    drv = next(iter(data.get("derivations", data).values()))
    if isinstance(drv, dict) and "env" in drv:
        drv = drv
    elif isinstance(drv, dict) and "buildPhase" not in drv:
        drv = next(iter(data["derivations"].values()))
    env = drv.get("env", drv)
    install = env.get("installPhase", "")
    native = env.get("nativeBuildInputs", "")
    assert "python3" not in native and "python3" not in install
    assert "keychain_birc.py" not in install
    assert "BIRC_UPLOAD_HELPER native" in install
    print("product_no_python=ok")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError) as error:
        print(f"product_no_python: {error}", file=sys.stderr)
        raise SystemExit(1)
