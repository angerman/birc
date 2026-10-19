#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate build/proof shards from LAWS.bend and PROOF.bend.

One Bend book that imports every proof module does not finish: the checker
spends more time in Bun GC than on the laws. Each shard is a complete book
(its own laws, discharged 1:1) and imports only the modules those laws use.
Shards are generated into build/proof and are not source.
"""
from __future__ import annotations

import hashlib
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "proof"
LAW_RE = re.compile(r"^law\s+(\w+)")
# Capture dotted helper names (media_unsupported_no_request.eligible).
DEF_RE = re.compile(r"^def\s+(?:Laws\.)?([\w.]+)")


def read_lines(name: str) -> list[str]:
    return (ROOT / name).read_text().splitlines()


def blocks(lines: list[str], start: re.Pattern[str]) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    name: str | None = None
    buf: list[str] = []
    for line in lines:
        match = start.match(line)
        if match:
            if name is not None:
                found.append((name, "\n".join(buf).rstrip() + "\n"))
            name = match.group(1)
            buf = [line]
        elif name is not None:
            buf.append(line)
    if name is not None:
        found.append((name, "\n".join(buf).rstrip() + "\n"))
    return found


def imports(lines: list[str]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for line in lines:
        if not line.startswith("import ") or line.startswith("import Base"):
            continue
        parts = line.split()
        if "as" in parts:
            out.append((parts[-1], parts[1]))
    return out


def uncomment(text: str) -> str:
    """Drop # comments so prose cannot pull helpers/aliases into a shard."""
    out: list[str] = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)


def used(text: str, aliases: list[str]) -> list[str]:
    clean = uncomment(text)
    hits = []
    for alias in aliases:
        if re.search(rf"(?<![A-Za-z0-9_]){re.escape(alias)}(?![A-Za-z0-9_])", clean):
            hits.append(alias)
    return hits


def rewrite(spec: str) -> str:
    if spec.startswith("./"):
        return "../../" + spec[2:]
    return spec


def trim_trailing_comments(body: str) -> str:
    lines = body.splitlines()
    while len(lines) > 1 and (lines[-1].strip() == "" or lines[-1].lstrip().startswith("#")):
        lines.pop()
    return "\n".join(lines) + "\n"


def main() -> None:
    law_lines = read_lines("LAWS.bend")
    proof_lines = read_lines("PROOF.bend")
    alias_specs = imports(law_lines)
    aliases = [alias for alias, _ in alias_specs]
    spec_of = dict(alias_specs)
    law_of = {name: trim_trailing_comments(body) for name, body in blocks(law_lines, LAW_RE)}
    proof_blocks = blocks(proof_lines, DEF_RE)
    proofs = {
        name: trim_trailing_comments(body)
        for name, body in proof_blocks
        if body.startswith("def Laws.")
    }
    helpers = [
        (name, trim_trailing_comments(body))
        for name, body in proof_blocks
        if not body.startswith("def Laws.")
    ]
    helper_names = [name for name, _ in helpers]
    missing = sorted(set(law_of) - set(proofs))
    extra = sorted(set(proofs) - set(law_of))
    if missing or extra or len(law_of) == 0:
        print(f"split-proof: laws={len(law_of)} proofs={len(proofs)} missing={missing} extra={extra}", file=sys.stderr)
        sys.exit(1)

    # One law per book. Laws that share an import still normalize independent
    # terms; putting the workspace scenarios in one process does not finish.
    groups: dict[tuple[tuple[str, ...], str], list[str]] = {}
    for name, law in law_of.items():
        text = law + proofs[name]
        key = tuple(used(text, aliases))
        groups[(key, name)] = [name]

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    manifest: list[str] = []
    for (key, law_name), names in sorted(groups.items(), key=lambda item: item[0]):
        digest = hashlib.sha256(("\n".join(key) + "\n" + law_name).encode()).hexdigest()[:8]
        laws_path = OUT / f"laws-{digest}.bend"
        proof_path = OUT / f"proof-{digest}.bend"
        law_imports = ["import Base"]
        for alias in key:
            law_imports.append(f"import {rewrite(spec_of[alias])} as {alias}")
        laws_body = ["# Generated from LAWS.bend. Do not edit."]
        laws_body.extend(law_imports)
        laws_body.append("")
        for name in names:
            laws_body.append(law_of[name].rstrip())
            laws_body.append("")
        laws_path.write_text("\n".join(laws_body))

        proof_text = "\n".join(proofs[name] for name in names)
        # Helpers live in the proof module, so that file must import every
        # alias they use. Copy only the helpers this shard's proofs reach;
        # the whole lemma block is what makes one book fail to finish.
        seen: set[str] = set()
        proof_clean = uncomment(proof_text)
        pending = [
            h
            for h in helper_names
            if re.search(rf"(?<![A-Za-z0-9_]){re.escape(h)}(?![A-Za-z0-9_])", proof_clean)
        ]
        while pending:
            helper_name = pending.pop()
            if helper_name in seen:
                continue
            seen.add(helper_name)
            for hname, body in helpers:
                if hname != helper_name:
                    continue
                body_clean = uncomment(body)
                for nxt in helper_names:
                    if nxt not in seen and re.search(
                        rf"(?<![A-Za-z0-9_]){re.escape(nxt)}(?![A-Za-z0-9_])", body_clean
                    ):
                        pending.append(nxt)
        # Source order: Bend rejects a dotted reference to a helper defined later.
        chosen = [body.rstrip() for hname, body in helpers if hname in seen]
        helper_body = "\n".join(chosen)
        proof_aliases = list(key)
        for alias in used(proof_text + "\n" + helper_body, aliases):
            if alias not in proof_aliases:
                proof_aliases.append(alias)
        proof_lines_out = ["# Generated from PROOF.bend. Do not edit.", "import Base", f"import ./laws-{digest}.bend as Laws"]
        for alias in proof_aliases:
            proof_lines_out.append(f"import {rewrite(spec_of[alias])} as {alias}")
        proof_lines_out.append("")
        if helper_body:
            proof_lines_out.append(helper_body.rstrip())
            proof_lines_out.append("")
        for name in names:
            proof_lines_out.append(proofs[name].rstrip())
            proof_lines_out.append("")
        proof_path.write_text("\n".join(proof_lines_out))
        manifest.append(f"{digest} {len(names)} {' '.join(key)}")
        print(f"shard {digest} laws={len(names)} imports={len(key)}")
    (OUT / "manifest.txt").write_text("\n".join(manifest) + "\n")
    print(f"split-proof: {len(groups)} shards, {len(law_of)} laws")


if __name__ == "__main__":
    main()
