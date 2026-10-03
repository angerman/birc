#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Offline preferences update global settings without inventing an IRC endpoint."""
from pathlib import Path
import runpy
import tempfile

p = runpy.run_path(str(Path(__file__).resolve().parents[1] / "src/launcher/preferences_birc.py"))
wire = "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\n"
with tempfile.TemporaryDirectory(prefix="birc-preferences-global-") as directory:
    path = Path(directory) / "preferences.toml"
    assert p["read"](path, "", 0) == ""
    p["write"](path, "", 0, wire)
    assert p["read"](path, "", 0) == wire + "scope\t0\n"
    assert p["document"](p["tomllib"].loads(path.read_text()))["servers"] == []
    p["write"](path, "irc.example", 6697, wire + "channel\t#saved\n")
    p["write"](path, "", 0, wire.replace("\t200\t", "\t300\t"))
    assert p["read"](path, "irc.example", 6697).endswith("channel\t#saved\n")
    assert "\t300\t" in p["read"](path, "irc.example", 6697)
    before = path.read_bytes()
    try:
        p["write"](path, "", 0, wire + "channel\t#fake\n")
    except p["Refusal"]:
        pass
    else:
        raise AssertionError("offline fake channel accepted")
    assert path.read_bytes() == before
print("preferences_global=ok")
