#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Transitive Bend import closure as a Make fragment.
#
#   sh scripts/bend-deps.sh <entry.bend> [output-stem]
#   sh scripts/bend-deps.sh --layers
#
# The fragment lists the entry, every imported .bend/.c/.h/.js, and quoted
# local headers pulled in by those C files. `import Base` is the prelude.
# A missing import path exits nonzero (fail closed) and writes nothing the
# caller keeps: the recipe redirects to a temporary file.
#
# --layers prints test-goldens-* membership from each test's direct imports
# (the counts in the simplification plan: view, irc|client, net|actor).
set -eu
exec python3 - "$@" <<'PY'
import os
import sys
from pathlib import Path

def fail(msg):
    print(f"bend-deps: {msg}", file=sys.stderr)
    sys.exit(1)

def norm(path):
    return Path(os.path.normpath(str(path)))

def rel_to_cwd(path):
    path = Path(path).resolve()
    cwd = Path.cwd().resolve()
    try:
        return path.relative_to(cwd).as_posix()
    except ValueError:
        return path.as_posix()

IMPORT_SUFFIXES = (".bend", ".c", ".h", ".js")
INCLUDE_DIRS = [Path("src/ffi"), Path("src/ui")]

def import_spec(line):
    stripped = line.strip()
    if not stripped.startswith("import "):
        return None
    spec = stripped[len("import "):].strip()
    if not spec or spec.startswith("#"):
        return None
    if spec[0] in "\"'":
        quote = spec[0]
        end = spec.find(quote, 1)
        if end < 0:
            return None
        spec = spec[1:end]
    else:
        spec = spec.split()[0]
    if spec == "Base" or spec.startswith("Base/"):
        return None
    if not spec.endswith(IMPORT_SUFFIXES):
        fail(f"unrecognized import {spec!r}")
    return spec

def quoted_includes(text):
    found = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("#include"):
            continue
        rest = line[len("#include"):].strip()
        if len(rest) < 3 or rest[0] != '"':
            continue
        end = rest.find('"', 1)
        if end > 1:
            found.append(rest[1:end])
    return found

def resolve_include(owner, spec):
    candidates = [owner.parent / spec]
    candidates.extend(directory / spec for directory in INCLUDE_DIRS)
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    return None

def closure(entry):
    entry = Path(entry)
    if not entry.is_file():
        fail(f"missing entry {entry}")
    seen = set()
    stack = [entry.resolve()]
    files = []
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        if not current.is_file():
            fail(f"missing import target {current}")
        files.append(current)
        text = current.read_text(encoding="utf-8", errors="replace")
        if current.suffix == ".bend":
            for line in text.splitlines():
                spec = import_spec(line)
                if spec is None:
                    continue
                nxt = (current.parent / spec).resolve()
                if not nxt.is_file():
                    fail(f"{rel_to_cwd(current)} imports missing {spec}")
                stack.append(nxt)
        if current.suffix in {".c", ".h"}:
            for spec in quoted_includes(text):
                nxt = resolve_include(current, spec)
                if nxt is not None:
                    stack.append(nxt)
    files.sort(key=lambda path: rel_to_cwd(path))
    return files

def products(blddir, stem):
    return [
        f"{blddir}/{stem}.bend.d",
        f"{blddir}/{stem}",
        f"{blddir}/{stem}.js",
        f"{blddir}/{stem}.c",
        f"{blddir}/{stem}_review.js",
    ]

def emit_fragment(entry, stem):
    blddir = os.environ.get("BLDDIR", "build")
    deps = " ".join(rel_to_cwd(path) for path in closure(entry))
    if not deps:
        fail(f"empty closure for {entry}")
    print(f"{' '.join(products(blddir, stem))}: {deps}")

def direct_bend_imports(path):
    names = set()
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        spec = import_spec(line)
        if spec and spec.endswith(".bend"):
            names.add(Path(spec).name)
    return names

def is_program(path):
    """A layer set must only contain runnable goldens. 11 of the 196 files under
    tests/bend are predicate/fixture libraries with no `def main`; building one
    fails with `Error: no main to run` and stops the whole scoped target."""
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("def main"):
            return True
    return False

def emit_layers():
    blddir = os.environ.get("BLDDIR", "build")
    groups = {
        "view": {"view.bend"},
        "proto": {"irc.bend", "client.bend"},
        "io": {"net.bend", "actor.bend"},
    }
    members = {name: [] for name in groups}
    root = Path("tests/bend")
    if not root.is_dir():
        fail("tests/bend is missing")
    for path in sorted(root.glob("*.bend")):
        if not is_program(path):
            continue
        names = direct_bend_imports(path)
        stem = "birc-proto" if path.name == "proto_demo.bend" else path.stem
        for group, goals in groups.items():
            if names & goals:
                members[group].append(f"{blddir}/{stem}")
    lines = ["# Generated by scripts/bend-deps.sh --layers. Do not edit."]
    for group, bins in members.items():
        var = f"GOLDEN_{group.upper()}_BINS"
        lines.append(f"{var} :=")
        for binary in bins:
            lines.append(f"{var} += {binary}")
        target = f"test-goldens-{group}"
        lines.append(f"{target}: $({var})")
        lines.append(f"\t@printf '%s\\n' '{target} bins=$(words $({var}))'")
    lines.append(".PHONY: test-goldens-view test-goldens-proto test-goldens-io")
    print("\n".join(lines))

def main(argv):
    if not argv or argv[0] in {"-h", "--help"}:
        print(__doc__ or "see scripts/bend-deps.sh")
        return
    if argv[0] == "--layers":
        if len(argv) != 1:
            fail("--layers takes no arguments")
        emit_layers()
        return
    entry = argv[0]
    if len(argv) == 1:
        stem = Path(entry).stem
    elif len(argv) == 2:
        stem = argv[1]
    else:
        fail("usage: bend-deps.sh <entry.bend> [output-stem]")
    if not stem or "/" in stem or stem.startswith("."):
        fail(f"bad output stem {stem!r}")
    emit_fragment(entry, stem)

if __name__ == "__main__":
    main(sys.argv[1:])
PY
