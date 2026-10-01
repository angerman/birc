#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
"""Synthetic local PNG; test every decoder allocation with vertical flip on."""
import struct
import subprocess
import sys
import zlib

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 2, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(b"\x00\x11\x22\x33\xff\x00\x66\x77\x88\x99"))
       + chunk(b"IEND", b""))
result = subprocess.run([sys.argv[1], *sys.argv[2:]], input=png, capture_output=True, timeout=15)
assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
assert b"png_16bit_oom=ok" in result.stdout, result.stdout
print("png_16bit_oom=ok")
