#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
"""Compare whole-cluster boundaries and widths with the actual native helper."""
import subprocess
import sys

bases = ["a", "漢", "©", "®", "⌚", "♥", "❤", "👩", "💻", "🇰", "🇷", "", "́", "🏽", "\r", "\n", "\x1b", "\u200d"]
suffixes = ["", "x", "́x", "🏽x", "️x", "︎x", "\u200dbx", "\u200d💻x", "🇷x", "́🇷x", "\nx"]
corpus = [base + suffix for base in bases for suffix in suffixes]
corpus += ["\r\nx", "🇰🇷🇯🇵x", "🇰‍a🇷x", "👩‍❤️‍💋‍👩x", "a‍漢x", "👩́‍💻️x"]
native = subprocess.run([sys.argv[2], "--columns", *corpus], check=True, capture_output=True, timeout=15).stdout.splitlines()
bend = subprocess.run([sys.argv[1], "--", "--columns", *corpus], check=True, capture_output=True, timeout=15).stdout.splitlines()
assert bend[-1] == b"ui_review_columns=ok", bend[-1:]
assert len(bend) - 1 == len(native) == len(corpus), (len(bend), len(native), len(corpus))
for text, actual, expected in zip(corpus, bend, native):
    assert actual == expected, f"cluster {text!r}: Bend {actual!r}, native {expected!r}"
print("ui_review_columns_parity=ok")
