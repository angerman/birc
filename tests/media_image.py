#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Synthetic-only fetch and decode controls; never contact an image host."""
import base64
import importlib.util
import io
import socket
import struct
import time
from pathlib import Path
from unittest.mock import patch

from PIL import Image

spec = importlib.util.spec_from_file_location("birc_image", Path(__file__).parents[1] / "src/media/image.py")
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)


def rejected(call):
    try:
        call()
    except Exception:
        return
    raise AssertionError("unsafe or malformed input was accepted")


def resolver(addresses):
    def resolve(host, port, **_):
        return [(socket.AF_INET6 if ":" in ip else socket.AF_INET,
                 socket.SOCK_STREAM, 0, "", (ip, port)) for ip in addresses]
    return resolve


public = resolver(["93.184.216.34"])
for ip in ("127.0.0.1", "0.0.0.0", "10.1.2.3", "172.16.0.1", "192.168.1.1",
           "169.254.169.254", "100.64.0.1", "224.0.0.1", "255.255.255.255",
           "::1", "fe80::1", "fc00::1", "ff02::1", "::ffff:127.0.0.1",
           "2002:7f00:1::", "64:ff9b::7f00:1", "64:ff9b:1::7f00:1", "fec0::1"):
    assert not media.public_address(ip), ip
    rejected(lambda: media.destination("https://example.test/a.png", resolver([ip])))
assert media.public_address("93.184.216.34")
assert media.public_address("2606:4700:4700::1111")
rejected(lambda: media.destination("https://example.test/a.png", resolver(["93.184.216.34", "127.0.0.1"])))
for url in ("file:///tmp/a.png", "ftp://example.test/a.png", "https://me:secret@example.test/a.png",
            "https://example.test:9999/a.png", "http://example.test:443/a.png",
            "https://example.test/a\r\nHost:x", "https://example.test/" + "x" * 4096):
    rejected(lambda: media.destination(url, public))
scheme, host, port, path, addresses = media.destination(
    "https://example.test/Screenshot%202026.png?q=x%2Fy", public)
assert (scheme, host, port, path) == ("https", "example.test", 443, "/Screenshot%202026.png?q=x%2Fy")
assert addresses[0][4][0] == "93.184.216.34"
assert media.destination("https://example.test/a.png?size=2#view", public)[3] == "/a.png?size=2"


class PinnedSocket:
    def __init__(self):
        self.address = None
        self.closed = False

    def settimeout(self, timeout):
        assert timeout > 0

    def connect(self, address):
        self.address = address

    def close(self):
        self.closed = True


class TLSContext:
    def wrap_socket(self, sock, *, server_hostname):
        assert server_hostname == "example.test"
        return sock


pinned_socket = PinnedSocket()
with patch.object(media.socket, "socket", return_value=pinned_socket), \
     patch.object(media.socket, "getaddrinfo", side_effect=AssertionError("connect re-resolved the host")), \
     patch.object(media.ssl, "create_default_context", return_value=TLSContext()) as context:
    client = media.PinnedHTTP(scheme, host, port, addresses, 1)
    client.connect()
    assert pinned_socket.address == ("93.184.216.34", 443)
    context.assert_called_once_with()
    client.close()
    assert pinned_socket.closed


class Response:
    def __init__(self, status=200, data=b"image", headers=None):
        self.status, self.data, self.headers = status, io.BytesIO(data), headers or {}

    def getheader(self, key, default=None):
        return self.headers.get(key, default)

    def read(self, size):
        return self.data.read(size)


connections = []
responses = []


class Connection:
    sock = None

    def __init__(self, scheme, host, port, addresses, timeout):
        self.scheme, self.host, self.addresses = scheme, host, addresses
        self.closed = False
        connections.append(self)

    def request(self, method, path, headers):
        assert method == "GET" and headers["Accept-Encoding"] == "identity"
        self.path = path

    def getresponse(self):
        return responses.pop(0)

    def close(self):
        self.closed = True


def fetched(url="https://example.test/a.png", resolve=public):
    return media.fetch(url, time.monotonic() + 2, resolve, Connection)


responses[:] = [Response(headers={"Content-Length": "5"})]
assert fetched() == b"image" and connections[-1].closed
responses[:] = [Response(302, headers={"Location": "https://127.0.0.1/a.png"})]
before = len(connections)
rejected(lambda: fetched(resolve=lambda host, port, **kw: resolver(
    ["127.0.0.1" if host == "127.0.0.1" else "93.184.216.34"])(host, port, **kw)))
assert len(connections) == before + 1 and connections[-1].closed
responses[:] = [Response(302, headers={"Location": "http://example.test/a.png"})]
rejected(fetched)
responses[:] = [Response(302, headers={"Location": "/next.png"}), Response()]
assert fetched() == b"image" and connections[-1].path == "/next.png"
resolutions = []


def rebound(host, port, **keywords):
    resolutions.append(host)
    return resolver(["93.184.216.34" if len(resolutions) == 1 else "127.0.0.1"])(host, port, **keywords)


responses[:] = [Response(302, headers={"Location": "/next.png"})]
before = len(connections)
rejected(lambda: fetched(resolve=rebound))
assert len(connections) == before + 1 and len(resolutions) == 2
for response in (Response(404), Response(headers={"Content-Encoding": "gzip"}),
                 Response(headers={"Content-Length": "999999999"}),
                 Response(headers={"Content-Length": "6"}), Response(data=b"x" * (media.MAX_DOWNLOAD + 1))):
    responses[:] = [response]
    rejected(fetched)
    assert connections[-1].closed
rejected(lambda: media.fetch("https://example.test/a.png", time.monotonic() - 1, public, Connection))


def source(fmt, **options):
    output = io.BytesIO()
    Image.new("RGB", (17, 11), (20, 40, 60)).save(output, format=fmt, **options)
    return output.getvalue()


def unpack(data):
    payload = base64.b64decode(media.encode(data), validate=True)
    assert payload[:8] == b"BIRCIMG1" and len(payload) <= media.MAX_PAYLOAD
    width, height, count, iterations, rgba_length, gif_length = struct.unpack(">6I", payload[8:32])
    assert rgba_length == width * height * 4
    offset = 32 + rgba_length
    gif = payload[offset:offset + gif_length]
    offset += gif_length
    frames = []
    for _ in range(count):
        duration, length = struct.unpack(">2I", payload[offset:offset + 8])
        offset += 8
        with Image.open(io.BytesIO(payload[offset:offset + length])) as frame:
            assert frame.format == "PNG" and frame.size == (width, height)
            frame.load()
            frames.append((duration, frame.getpixel((0, 0))))
        offset += length
    assert offset == len(payload)
    return width, height, count, iterations, gif, frames


formats = ["PNG", "JPEG", "GIF", "BMP", "TIFF", "WEBP", "AVIF"]
for fmt in formats:
    width, height, count, iterations, gif, frames = unpack(source(fmt))
    assert (width, height, count, iterations, gif) == (17, 11, 1, 1, b"")
    assert len(frames) == 1
output = io.BytesIO()
Image.new("RGBA", (640, 320)).save(output, format="PNG")
assert unpack(output.getvalue())[:2] == (320, 160)
output = io.BytesIO()
first, second = Image.new("RGB", (17, 11), "red"), Image.new("RGB", (17, 11), "blue")
first.save(output, format="GIF", save_all=True, append_images=[second], duration=[40, 80], loop=2)
width, height, count, iterations, gif, frames = unpack(output.getvalue())
assert (count, iterations) == (2, 3)
assert [frame[0] for frame in frames] == [40, 80]
assert frames[0][1] != frames[1][1]
with Image.open(io.BytesIO(gif)) as normalized:
    assert normalized.n_frames == 2 and normalized.info["loop"] == 2
    normalized.seek(1)
    assert normalized.info["duration"] == 80
for fmt in ("PNG", "WEBP"):
    output = io.BytesIO()
    first.save(output, format=fmt, save_all=True, append_images=[second], duration=[40, 80], loop=0)
    result = unpack(output.getvalue())
    assert result[2:4] == (2, 0) and [frame[0] for frame in result[5]] == [40, 80]
output = io.BytesIO()
first.save(output, format="GIF", save_all=True,
           append_images=[Image.new("RGB", (17, 11), (index, 0, 0)) for index in range(25)],
           duration=40, loop=0)
rejected(lambda: media.encode(output.getvalue()))
saved_limit = media.MAX_PAYLOAD
media.MAX_PAYLOAD = 64
rejected(lambda: media.encode(source("PNG")))
media.MAX_PAYLOAD = saved_limit
for malformed in (b"", b"<html>not an image</html>", b"<svg/>", source("PNG")[:30], b"x" * (media.MAX_DOWNLOAD + 1)):
    rejected(lambda: media.encode(malformed))
output = io.BytesIO()
Image.new("1", (4097, 1)).save(output, format="PNG")
rejected(lambda: media.encode(output.getvalue()))
print("media_image=ok formats=" + ",".join(formats) + " animation=2 public_redirects=guarded")
