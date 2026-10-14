#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Nicks setting plumbing: ten-field wire, legacy default, and TOML fill."""
from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "src/launcher/preferences_birc.py"
spec = importlib.util.spec_from_file_location("preferences_birc", SOURCE)
assert spec is not None and spec.loader is not None
prefs = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = prefs
spec.loader.exec_module(prefs)

WIRE_OFF = "BIRC_PREFS1\nsettings\t1\t1\t1\t1\t100\t0\t1\t1\t0\n"
WIRE_ON = "BIRC_PREFS1\nsettings\t1\t1\t1\t1\t100\t0\t1\t1\t1\n"
WIRE_LEGACY = "BIRC_PREFS1\nsettings\t1\t1\t1\t1\t100\t0\t1\t1\n"


def rejected(action) -> None:
    try:
        action()
    except prefs.Refusal:
        return
    raise AssertionError("unsafe input accepted")


def main() -> None:
    stg, channels = prefs.parse_wire(WIRE_OFF)
    assert stg["nicks"] is False and channels == []
    assert prefs.wire(stg, []) == WIRE_OFF
    legacy, _ = prefs.parse_wire(WIRE_LEGACY)
    assert legacy["nicks"] is True
    assert prefs.wire(legacy, []) == WIRE_ON
    rejected(lambda: prefs.parse_wire(WIRE_ON.replace("\t1\n", "\t2\n")))
    with tempfile.TemporaryDirectory(prefix="birc-settings-nicks-") as directory:
        path = Path(directory) / "preferences.toml"
        prefs.write(path, "irc.example", 6697, WIRE_OFF)
        assert prefs.read(path, "irc.example", 6697) == WIRE_OFF
        assert "\nnicks = false\n" in path.read_text()
        # Files written before nicks existed load with the default on.
        old = path.read_text().replace("\nnicks = false\n", "\n")
        assert "nicks" not in old
        path.write_text(old)
        path.chmod(0o600)
        assert prefs.read(path, "irc.example", 6697) == WIRE_ON
        # Every other key and value stays strict.
        path.write_text(old.replace("[settings]", "[settings]\nnicks = 'yes'"))
        rejected(lambda: prefs.read(path, "irc.example", 6697))
    print("settings_nicks=ok")


if __name__ == "__main__":
    main()
