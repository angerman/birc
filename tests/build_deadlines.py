# SPDX-License-Identifier: Apache-2.0
"""Every Bend compiler recipe has a positive wall-clock deadline."""
import re
from pathlib import Path


def bounded(line):
    return bool(re.search(r"\btimeout\s+[1-9][0-9]*(?:[smhd])?\s+bend\b", line))


assert not bounded("bend test.bend -o build/test")
assert not bounded("timeout 0 bend test.bend -o build/test")
assert bounded("timeout 180 bend test.bend -o build/test")
recipes = [line for line in Path("Makefile").read_text().splitlines()
           if line.startswith("\t") and re.search(r"\bbend\b.*\s-o\s", line)]
assert recipes, "compiler recipes missing"
missing = [line.strip() for line in recipes if not bounded(line)]
assert not missing, "unbounded compiler recipes: " + repr(missing)
print(f"build_deadlines=ok ({len(recipes)} compiler recipes)")
