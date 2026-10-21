#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed preferences default is the linked native file effect."""
from pathlib import Path
import re
import sys

target = Path(sys.argv[1]).resolve()
binary = target / "bin/birc" if target.is_dir() else target
wrapper = binary.read_text()
found = re.findall(r"BIRC_PREFS_HELPER=\$\{BIRC_PREFS_HELPER-'([^']+)'\}", wrapper)
assert found == ["native"], "installed preferences default is not native"
assert "birc-preferences" not in wrapper, "installed birc wrapper still ships a preferences helper"
print("preferences_package=ok")
