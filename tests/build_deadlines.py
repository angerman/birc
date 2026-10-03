# SPDX-License-Identifier: Apache-2.0
"""Every Bend compiler recipe has a positive wall-clock deadline."""
import re
from pathlib import Path


def bounded(line):
    return bool(re.search(r"\btimeout\s+[1-9][0-9]*(?:[smhd])?\s+bend\b", line))


def package_bounded(line):
    return bool(re.search(r"\btimeout\s+[1-9][0-9]*\s+\$\(NIX\)", line)
                and re.search(r"--option\s+timeout\s+[1-9][0-9]*\b", line))


assert not bounded("bend test.bend -o build/test")
assert not bounded("timeout 0 bend test.bend -o build/test")
assert bounded("timeout 180 bend test.bend -o build/test")
recipes = [line for line in Path("Makefile").read_text().splitlines()
           if line.startswith("\t") and re.search(r"\bbend\b.*\s-o\s", line)]
assert recipes, "compiler recipes missing"
missing = [line.strip() for line in recipes if not bounded(line)]
assert not missing, "unbounded compiler recipes: " + repr(missing)
print(f"build_deadlines=ok ({len(recipes)} compiler recipes)")

# The client and daemon-owned builder need separate bounds.
assert package_bounded("timeout 900 $(NIX) build --option timeout 900")
assert not package_bounded("timeout 900 $(NIX) build")
assert not package_bounded("$(NIX) build --option timeout 900")
assert not package_bounded("timeout 900 $(NIX) build --option timeout 0")
packages = [line for line in Path("Makefile").read_text().splitlines()
            if line.startswith("\t") and "$(NIX)" in line
            and re.search(r"\bbuild\b", line)]
assert packages, "package recipes missing"
assert all(package_bounded(line) for line in packages), "unbounded package recipe"
print(f"package_deadlines=ok ({len(packages)} package recipes)")
