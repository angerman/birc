#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Moritz Angermann <moritz@zw3rk.com>, zw3rk pte. ltd.
"""Bounded PNG/Sixel cases; no file writes, downloads, or real terminal."""
import struct
import subprocess
import sys
import zlib


def chunk(kind, data, declared=None):
    size = len(data) if declared is None else declared
    return struct.pack(">I", size) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def png(raw, width=1, height=1, declared=None, depth=8, color=6,
        interlace=0, palette=b"", split=False, iphone=False, compression=6):
    header = struct.pack(">IIBBBBB", width, height, depth, color, 0, 0, interlace)
    compressed = zlib.compress(raw, compression)
    if iphone:
        compressed = compressed[2:-4]
    idat = chunk(b"IDAT", compressed, declared)
    if split:
        middle = len(compressed) // 2
        idat = chunk(b"IDAT", compressed[:middle]) + chunk(b"IDAT", compressed[middle:])
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header) + (chunk(b"CgBI", b"") if iphone else b"")
            + (chunk(b"PLTE", palette) if palette else b"") + idat + chunk(b"IEND", b""))


def run(binary, name, data, expected=(0, 0, 0, 0), deny=0):
    proc = subprocess.run([binary, name, str(deny), *map(str, expected)], input=data, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=5, check=False)
    if proc.returncode:
        raise SystemExit(f"probe {name}: exit={proc.returncode} stderr={proc.stderr!r} stdout={proc.stdout!r}")
    text = proc.stdout.decode("ascii").strip()
    if not name.startswith(("valid_", "oom_")):
        print(text, flush=True)
    fields = {key: int(value) for key, value in (pair.split("=") for pair in text.split()[1:])}
    assert fields["live"] == 0
    assert fields["peak_live"] <= 8 * 1024 * 1024
    return fields


PASSES = ((0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
          (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2))


def samples_row(width, depth, samples):
    values = samples * width
    if depth == 16:
        return b"".join(struct.pack(">H", value) for value in values)
    if depth == 8:
        return bytes(values)
    packed = bytearray((len(values) * depth + 7) // 8)
    for index, value in enumerate(values):
        packed[index * depth // 8] |= value << (8 - depth - index * depth % 8)
    return bytes(packed)


def filtered(row, previous, bpp, mode):
    result = bytearray()
    for index, value in enumerate(row):
        left = row[index - bpp] if index >= bpp else 0
        above = previous[index] if previous else 0
        corner = previous[index - bpp] if previous and index >= bpp else 0
        if mode == 0:
            prediction = 0
        elif mode == 1:
            prediction = left
        elif mode == 2:
            prediction = above
        elif mode == 3:
            prediction = (left + above) // 2
        else:
            point = left + above - corner
            distances = (abs(point - left), abs(point - above), abs(point - corner))
            prediction = (left, above, corner)[distances.index(min(distances))]
        result.append((value - prediction) & 255)
    return bytes([mode]) + result


def scanlines(width, height, depth, samples, interlace, filters=False):
    output = bytearray()
    for x0, y0, dx, dy in PASSES if interlace else ((0, 0, 1, 1),):
        pass_width = max(0, (width - x0 + dx - 1) // dx)
        pass_height = max(0, (height - y0 + dy - 1) // dy)
        if not pass_width or not pass_height:
            continue
        previous = b""
        row = samples_row(pass_width, depth, samples)
        bpp = max(1, (depth * len(samples) + 7) // 8)
        for index in range(pass_height):
            output += filtered(row, previous, bpp, index % 5 if filters else 0)
            previous = row
    return bytes(output)


def valid_cases(binary):
    formats = [(0, depth) for depth in (1, 2, 4, 8, 16)]
    formats += [(color, depth) for color in (2, 4, 6) for depth in (8, 16)]
    formats += [(3, depth) for depth in (1, 2, 4, 8)]
    for color, depth in formats:
        palette = b""
        if color == 3:
            samples, expected = [1], (17, 34, 51, 255)
            palette = bytes([0, 0, 0, 17, 34, 51])
        elif color in (0, 4):
            gray = (1 << depth) - 1 if depth < 8 else 102 * (257 if depth == 16 else 1)
            samples = [gray] + ([153 * (257 if depth == 16 else 1)] if color == 4 else [])
            value = 255 if depth < 8 else 102
            expected = (value, value, value, 153 if color == 4 else 255)
        else:
            samples = [17, 34, 51] + ([255] if color == 6 else [])
            if depth == 16:
                samples = [value * 257 for value in samples]
            expected = (17, 34, 51, 255)
        for interlace in (0, 1):
            for width, height in ((1, 1), (9, 7)):
                raw = scanlines(width, height, depth, samples, interlace, filters=True)
                case = png(raw, width, height, depth=depth, color=color,
                           interlace=interlace, palette=palette, split=True)
                name = f"valid_c{color}_d{depth}_i{interlace}_{width}x{height}"
                value = run(binary, name, case, expected)
                assert value["decoded"] == value["first_decoded"] == value["pixels_ok"] == 1
                assert value["second_requests"] == value["refused"] == 0
    # This header-first CgBI placement is accepted by the existing TimUI header
    # reader and exercises stb's supported headerless DEFLATE branch.
    apple = run(binary, "valid_cgbi", png(b"\x00\x11\x22\x33\xff", iphone=True), (17, 34, 51, 255))
    assert apple["decoded"] == apple["pixels_ok"] == 1
    print("valid_png_variants=61", flush=True)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: png_bounds.py ./build/png_bounds")
    normal_png = png(b"\x00\x01\x02\x03\xff")
    normal = run(sys.argv[1], "normal", normal_png, (1, 2, 3, 255))
    assert normal["decoded"] == 1 and normal["max_requested"] == 4096
    assert normal["second_requests"] == 0
    owned = run(sys.argv[1], "cache_owner_denied", normal_png, (1, 2, 3, 255), deny="owned")
    assert owned["first_decoded"] == 0 and owned["decoded"] == owned["pixels_ok"] == 1
    assert owned["owned_refused"] == 1 and owned["second_requests"] > 0
    expanded = 3 * 1024 * 1024
    excess = png(b"\x00\x01\x02\x03\xff" + bytes(expanded - 5))
    extra = run(sys.argv[1], "excess_3mib", excess)
    assert extra["preflight"] == 1 and extra["decoded"] == 0
    assert extra["max_requested"] <= 4096 and extra["second_requests"] == 0
    bad_filter = run(sys.argv[1], "bad_filter", png(b"\x05\x01\x02\x03\xff"))
    assert bad_filter["preflight"] == 1 and bad_filter["decoded"] == 0
    assert bad_filter["max_requested"] <= 4096 and bad_filter["second_requests"] == 0
    declared = run(sys.argv[1], "declared_32mib", png(b"\x00\x01\x02\x03\xff", declared=32 * 1024 * 1024))
    assert declared["preflight"] == 1 and declared["decoded"] == 0
    assert declared["max_requested"] == 0 and declared["second_requests"] == 0
    malformed = run(sys.argv[1], "bad_signature", b"not a PNG")
    assert malformed["constructor"] == 0 and malformed["requests"] == 0
    large_header = run(sys.argv[1], "oversized_ihdr", png(b"\x00\x01\x02\x03\xff", width=4097))
    assert large_header["preflight"] == 0 and large_header["requests"] == 0
    for name, data in (("truncated", normal_png[:-5]),
                       ("short_pixels", png(b"\x00\x01\x02\x03")),
                       ("bad_interlace", png(b"\x00\x01\x02\x03\xff", interlace=2))):
        value = run(sys.argv[1], name, data)
        assert value["decoded"] == 0 and value["second_requests"] == 0
    # Deny each allocator site in a valid 16-bit decode, then permit retry.
    deep = png(b"\x00\x01\x01\x02\x02\x03\x03\xff\xff", depth=16)
    for site in range(1, 6):
        value = run(sys.argv[1], f"oom_{site}", deep, (1, 2, 3, 255), deny=site)
        assert value["first_decoded"] == 0 and value["decoded"] == value["pixels_ok"] == 1
        assert value["refused"] == 1 and value["second_requests"] > 0
    valid_cases(sys.argv[1])
    stored = run(sys.argv[1], "stored_normal", png(b"\x00\x01\x02\x03\xff", compression=0), (1, 2, 3, 255))
    assert stored["decoded"] == stored["pixels_ok"] == 1
    stored_excess = run(sys.argv[1], "stored_excess", png(b"\x00\x01\x02\x03\xff" + bytes(512), compression=0))
    assert stored_excess["decoded"] == stored_excess["second_requests"] == 0
    assert stored_excess["max_requested"] <= 4096
    for name, color, samples, expected, palette in (
        ("gray", 0, [102], (102, 102, 102, 255), b""),
        ("palette", 3, [1], (17, 34, 51, 255), bytes([0, 0, 0, 17, 34, 51])),
        ("adam7", 6, [17, 34, 51, 255], (17, 34, 51, 255), b""),
    ):
        interlace = int(name == "adam7")
        data = png(scanlines(9, 7, 8, samples, interlace), 9, 7,
                   color=color, palette=palette, interlace=interlace)
        control = run(sys.argv[1], f"oom_{name}_control", data, expected)
        assert control["pixels_ok"] == 1
        for site in range(1, control["requests"] + 1):
            value = run(sys.argv[1], f"oom_{name}_{site}", data, expected, deny=site)
            assert value["first_decoded"] == 0 and value["decoded"] == value["pixels_ok"] == 1
            assert value["refused"] == 1 and value["second_requests"] > 0
    print("decoder_allocation_failures_recovered=32", flush=True)
    print("png_bounds=ok")


if __name__ == "__main__":
    main()
