#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Local synthetic images: later-frame source bounds and cumulative decode work."""
import base64
import importlib.util
import io
import struct
from pathlib import Path
from unittest.mock import patch

from PIL import Image

spec = importlib.util.spec_from_file_location("birc_image", Path(__file__).parents[1] / "src/media/image.py")
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)


def animation(sizes, format="GIF", fallback=False):
    frames = [Image.new("RGB", size, color) for size, color in zip(sizes, ("red", "blue", "green"))]
    output = io.BytesIO()
    options = {"disposal": 2, "optimize": False} if format == "GIF" else {}
    if fallback:
        options["default_image"] = True
    frames[0].save(output, format=format, save_all=True, append_images=frames[1:],
                   duration=40, loop=0, **options)
    return output.getvalue()


def source_sizes(data):
    result = []
    with Image.open(io.BytesIO(data)) as image:
        for index in range(image.n_frames):
            image.seek(index)
            result.append(image.size)
    return result


def accepted(data, expected):
    payload = base64.b64decode(media.encode(data), validate=True)
    assert payload[:8] == b"BIRCIMG1"
    assert struct.unpack(">3I", payload[8:20]) == expected


def rejected(data):
    try:
        media.encode(data)
    except media.ImageError:
        return
    raise AssertionError("source bound was not enforced")


def rejected_before_conversion(data, expected_sizes):
    converted = []
    original = media.ImageOps.exif_transpose

    def record(image):
        converted.append(image.size)
        return original(image)

    with patch.object(media.ImageOps, "exif_transpose", side_effect=record):
        rejected(data)
    assert converted == expected_sizes, converted


ordinary = animation([(320, 320)] * 3)
expanding = animation([(320, 320), (640, 640), (640, 640)])
assert source_sizes(ordinary) == [(320, 320)] * 3
assert source_sizes(expanding) == [(320, 320), (640, 640), (640, 640)]

# The side cap applies to each later frame, not just the logical screen at open.
for sizes in ([(4096, 1)], [(320, 1), (4096, 1)], [(1, 320), (1, 4096)]):
    data = animation(sizes)
    accepted(data, (min(sizes[0][0], 320), min(sizes[0][1], 320), len(sizes)))
for sizes in ([(4097, 1)], [(320, 1), (4097, 1)], [(1, 320), (1, 4097)]):
    rejected(animation(sizes))
rejected_before_conversion(animation([(320, 1), (4097, 1)]), [(320, 1)])

saved_pixels, saved_source = media.MAX_PIXELS, media.MAX_SOURCE_FRAME_PIXELS
try:
    # Initial dimensions and a later expanded canvas share the same pixel cap.
    media.MAX_PIXELS = 640 * 640 - 1
    rejected(expanding)
    media.MAX_PIXELS += 1
    accepted(expanding, (320, 320, 3))
    media.MAX_PIXELS = saved_pixels

    # Fixed canvases retain the old exact-boundary behavior. An expanded canvas
    # must spend its actual pixels before normalization shrinks it to 320².
    media.MAX_SOURCE_FRAME_PIXELS = 320 * 320 * 3
    accepted(ordinary, (320, 320, 3))
    rejected_before_conversion(expanding, [(320, 320)])
    media.MAX_SOURCE_FRAME_PIXELS = 320 * 320 + 640 * 640 * 2
    accepted(expanding, (320, 320, 3))
    media.MAX_SOURCE_FRAME_PIXELS -= 1
    rejected(expanding)

    # APNG's default fallback is decoded while seeking, even though it is not
    # emitted. Count it once; ordinary APNG/WebP have no extra fallback frame.
    ordinary_png = animation([(17, 11)] * 2, "PNG")
    fallback_png = animation([(17, 11)] * 3, "PNG", fallback=True)
    ordinary_webp = animation([(17, 11)] * 2, "WEBP")
    media.MAX_SOURCE_FRAME_PIXELS = 17 * 11 * 2
    accepted(ordinary_png, (17, 11, 2))
    accepted(ordinary_webp, (17, 11, 2))
    rejected(fallback_png)
    media.MAX_SOURCE_FRAME_PIXELS = 17 * 11 * 3
    accepted(fallback_png, (17, 11, 2))
finally:
    media.MAX_PIXELS, media.MAX_SOURCE_FRAME_PIXELS = saved_pixels, saved_source

print("media_image_bounds=ok")
