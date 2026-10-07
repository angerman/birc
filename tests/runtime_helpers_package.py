#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed cards/search/preferences provenance and owned local dispatch.

No client/PTY/network/Keychain path is entered. Use the unchanged preferences
harness and existing package environment/run helpers. Source proposal: unrun.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

from notify_package import environment, run

REPO = Path(__file__).resolve().parents[1]
HELPERS = (("birc-cards", "src/media/cards.py"),
           ("birc-history-search", "src/launcher/search_probe_birc.py"),
           ("birc-preferences", "src/launcher/preferences_birc.py"))


def provenance(binary: Path, name: str, source: str) -> Path:
    found = re.findall(r"/nix/store/[^\s'\"{}]+/bin/" + re.escape(name) + r"(?=[\s'\"{}]|$)", binary.read_text())
    assert len(set(found)) == 1, name + ": no unique installed absolute default"
    helper = Path(found[0])
    assert helper.is_file() and os.access(helper, os.X_OK), name + ": helper missing"
    commands = [shlex.split(line) for line in helper.read_text().splitlines() if line.startswith("exec ")]
    assert len(commands) == 1 and len(commands[0]) == 4, name + ": unexpected exec"
    _, python, script, args = commands[0]
    assert args == "$@", name + ": argument forwarding changed"
    python, script = Path(python), Path(script)
    assert str(python).startswith("/nix/store/") and python.name == "python3" and os.access(python, os.X_OK), name + ": Python not provisioned"
    assert str(script).startswith("/nix/store/") and script.is_file(), name + ": source missing"
    assert script.read_bytes() == (REPO / source).read_bytes(), name + ": installed source stale"
    if name == "birc-cards":
        assert script.with_name("image.py").read_bytes() == (REPO / "src/media/image.py").read_bytes(), "cards sibling image source stale"
    return helper


def cards_controls(helper: Path, root: Path, env: dict[str, str]) -> None:
    page = root / "synthetic local page.html"
    page.write_bytes(b'<meta property="og:title" content="Title &amp; record"><meta property="og:description" content="Safe description">')
    page.chmod(0o600)
    got = run([str(helper), "--local", str(page)], env)
    assert got.returncode == 0 and got.stdout == b"Title & record\nSafe description\n\n" and not got.stderr, "installed cards local/argv dispatch failed"
    for argv in (["--local", str(root / "missing page.html")], ["--local", str(page), "extra"]):
        got = run([str(helper), *argv], env)
        assert got.returncode == 1 and not got.stdout and got.stderr == b"birc-cards: card unavailable\n", "cards refusal exposed variable text"


def search_controls(helper: Path, root: Path, env: dict[str, str]) -> None:
    history = root / "synthetic private history.txt"
    rows = b"BIRC2\ta:6667\t#chan\tMSG\t10:00:00\talice\tneedle one\n"
    history.write_bytes(rows)
    history.chmod(0o600)
    for action, expected in (("scan", b"SE11010\n" + rows), ("probe", b"SE11010\n")):
        got = run([str(helper), action, str(history)], env)
        assert got.returncode == 0 and got.stdout == expected and not got.stderr, "installed search private/argv dispatch failed"
    link = root / "synthetic history link"
    link.symlink_to(history)
    for path, expected in ((link, b"SE00100\n"), (root / "missing history", b"SE00001\n")):
        got = run([str(helper), "scan", str(path)], env)
        assert got.returncode == 0 and got.stdout == expected and not got.stderr, "search refusal leaked bytes/path"
    history.chmod(0o644)
    got = run([str(helper), "scan", str(history)], env)
    assert got.returncode == 0 and got.stdout == b"SE11000\n" and not got.stderr, "search nonprivate content crossed seam"


def main(argument: str) -> None:
    target = Path(argument).resolve()
    binary = target / "bin/birc" if target.is_dir() else target
    cards, search, preferences = [provenance(binary, name, source) for name, source in HELPERS]
    with tempfile.TemporaryDirectory(prefix="birc-runtime-helpers-package-") as temporary:
        root = Path(temporary)
        fake_bin = root / "empty-bin"
        fake_bin.mkdir()
        env = environment(root, fake_bin)
        env.update(BIRC_IMAGE_CACHE="none", BIRC_HISTORY="none", BIRC_PREFERENCES="none")
        cards_controls(cards, root, env)
        search_controls(search, root, env)
        # Preserve every existing preference oracle and its 10-second calls.
        got = run([sys.executable, str(REPO / "tests/preferences_package.py"), str(preferences)], env, timeout=60)
        assert got.returncode == 0 and got.stdout == b"preferences_package=ok\n" and not got.stderr, "installed preferences harness failed"
    print("runtime_helpers_package=ok")


if __name__ == "__main__":
    try:
        assert len(sys.argv) == 2, "expected installed package or birc wrapper path"
        main(sys.argv[1])
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print("runtime_helpers_package: " + str(error), file=sys.stderr)
        raise SystemExit(1)
