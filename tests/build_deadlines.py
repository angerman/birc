# SPDX-License-Identifier: Apache-2.0
"""Every Bend compiler recipe has a positive wall-clock deadline.

Compiler recipes are read from `make -n` because slow compiles and link
rules are generated with $(eval). Scanning the Makefile text would only
see the four pattern rules.
"""
import os
import re
import subprocess
from pathlib import Path


def bounded(line):
    return bool(re.search(r"\btimeout\s+[1-9][0-9]*(?:[smhd])?\s+bend\b", line))


def package_bounded(line):
    return bool(re.search(r"\btimeout\s+[1-9][0-9]*\s+\$\(NIX\)", line)
                and re.search(r"--option\s+timeout\s+[1-9][0-9]*\b", line))


assert not bounded("bend test.bend -o build/test")
assert not bounded("timeout 0 bend test.bend -o build/test")
assert bounded("timeout 180 bend test.bend -o build/test")

stems = sorted(path.stem for path in Path("tests/bend").glob("*.bend"))
assert stems, "tests/bend sources missing"
targets = []
for stem in stems:
    targets.extend([
        f"build/{stem}",
        f"build/{stem}.js",
        f"build/{stem}.c",
        f"build/{stem}_review.js",
    ])
targets.extend([
    "build/birc-proto",
    "build/birc_bend.c",
    "test-perf-search",
    "test-perf-media-wrap",
    "paint-footprint",
])
# Do not regenerate closure files while printing recipes. Those scripts are
# real work even under -n, and this check has a 30s budget.
old_files = [f"build/{stem}.bend.d" for stem in stems]
old_files.extend(["build/birc-proto.bend.d", "build/golden-layers.mk"])
cmd = ["make", "-n", "-B", "--no-print-directory"]
cmd.extend(f"-o{path}" for path in old_files)
cmd.extend(targets)
env = os.environ.copy()
env["MAKEFLAGS"] = "-j2"
env["BIRC_UI_CACHE"] = "0"
dry = subprocess.run(cmd, env=env, capture_output=True, text=True)
assert dry.returncode == 0, "make -n failed:\n" + dry.stderr[-2000:]
recipes = [line for line in dry.stdout.splitlines()
           if re.search(r"\bbend\b.*\s-o\s", line)]
assert recipes, "compiler recipes missing from make -n"
missing = [line.strip() for line in recipes if not bounded(line)]
assert not missing, "unbounded compiler recipes: " + repr(missing)
print(f"build_deadlines=ok ({len(recipes)} compiler recipes)")

# The client and daemon-owned builder need separate bounds. Those recipes
# stay literal in the Makefile.
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
