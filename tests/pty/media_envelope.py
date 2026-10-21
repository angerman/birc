#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""BIRCIMG1 envelopes without Pillow. Used by leftover Python PTY fixtures."""
from __future__ import annotations

import base64
import struct
import zlib


def png_rgba(width: int, height: int, pixel: tuple[int, int, int, int]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    row = bytes(pixel) * width
    raw = b"".join(b"\0" + row for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def envelope(width: int, height: int, pixel: tuple[int, int, int, int], duration: int = 100) -> tuple[str, bytes]:
    png = png_rgba(width, height, pixel)
    rgba = bytes(pixel) * (width * height)
    payload = (
        b"BIRCIMG1"
        + struct.pack(">6I", width, height, 1, 1, len(rgba), 0)
        + rgba
        + struct.pack(">2I", duration, len(png))
        + png
    )
    return base64.b64encode(payload).decode("ascii"), png
