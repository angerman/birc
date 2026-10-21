#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed helper provenance: native image/cards/search/prefs defaults.

No client/PTY/network/Keychain path is entered.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys


def native_default(binary: Path, name: str, token: str) -> None:
    wrapper = binary.read_text()
    found = re.findall(
        r"BIRC_" + name + r"_HELPER=\$\{BIRC_" + name + r"_HELPER-'([^']+)'\}", wrapper)
    assert found == ["native"], "installed " + token + " default is not native"
    assert token not in wrapper, "installed birc wrapper still ships " + token


def main(argument: str) -> None:
    target = Path(argument).resolve()
    binary = target / "bin/birc" if target.is_dir() else target
    native_default(binary, "SEARCH", "birc-history-search")
    native_default(binary, "PREFS", "birc-preferences")
    native_default(binary, "MEDIA", "birc-image")
    native_default(binary, "CARDS", "birc-cards")
    native_default(binary, "UPLOAD", "birc-upload")
    print("runtime_helpers_package=ok")


if __name__ == "__main__":
    try:
        assert len(sys.argv) == 2, "expected installed package or birc wrapper path"
        main(sys.argv[1])
    except (AssertionError, OSError, ValueError) as error:
        print("runtime_helpers_package: " + str(error), file=sys.stderr)
        raise SystemExit(1)
