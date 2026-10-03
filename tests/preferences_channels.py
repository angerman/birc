#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Saved names must satisfy the same nonempty channel-body rule as IRC JOIN."""
from pathlib import Path
import runpy

p = runpy.run_path(str(Path(__file__).resolve().parents[1] / "src/launcher/preferences_birc.py"))
for prefix in "#&+!":
    assert p["text"](prefix + "a", 128, channel=True) == prefix + "a"
    try:
        p["text"](prefix, 128, channel=True)
    except p["Refusal"]:
        pass
    else:
        raise AssertionError("bare channel prefix accepted")
assert p["text"]("#room:*.fi", 128, channel=True) == "#room:*.fi"
long_name = "#" + "a" * 504
assert p["text"](long_name, 505, channel=True) == long_name
try:
    p["text"](long_name + "a", 505, channel=True)
except p["Refusal"]:
    pass
else:
    raise AssertionError("overlong channel accepted")
for name in ("#room:*.fi secret", "#room:*.fi,#other", "#room:*.fi\n"):
    try:
        p["text"](name, 128, channel=True)
    except p["Refusal"]:
        pass
    else:
        raise AssertionError("invalid masked channel accepted")
print("preferences_channels=ok")
