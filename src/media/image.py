#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fetch and normalize one image. No files, shell, cookies, or proxy settings.

The parent owns scheduling and the output limit. This helper also has a total
deadline, so a helper adopted during application exit cannot run indefinitely.
Only validated public addresses are contacted, including after redirects.
"""

import base64
import http.client
import io
import ipaddress
import os
import signal
import socket
import ssl
import stat
import struct
import sys
import time
import warnings
from urllib.parse import quote, urljoin, urlsplit

from PIL import Image, ImageOps, PngImagePlugin

MAX_DOWNLOAD = 8 * 1024 * 1024
MAX_LOCAL_BYTES = 16 * 1024 * 1024
MAX_PIXELS = 16 * 1024 * 1024
MAX_SOURCE_FRAME_PIXELS = 32 * 1024 * 1024
MAX_SIDE = 320
MAX_FRAMES = 24
MAX_FRAME_PIXELS = 1536000
MAX_PAYLOAD = 2 * 1024 * 1024
TIMEOUT = 8
FORMATS = ("PNG", "JPEG", "GIF", "WEBP", "BMP", "TIFF", "AVIF")
Image.MAX_IMAGE_PIXELS = MAX_PIXELS
# Previews do not need large text/profile payloads. Use the decoder's existing
# limits instead of adding a separate PNG parser or metadata inflater.
PngImagePlugin.MAX_TEXT_CHUNK = 65536
PngImagePlugin.MAX_TEXT_MEMORY = 262144


class ImageError(Exception):
    pass


def public_address(value):
    """Reject private, loopback, link-local, multicast, and mapped aliases."""
    address = ipaddress.ip_address(value.split("%", 1)[0])
    if isinstance(address, ipaddress.IPv6Address):
        if address.ipv4_mapped is not None:
            address = address.ipv4_mapped
        elif address.sixtofour is not None or address.teredo is not None:
            return False
        elif address not in ipaddress.IPv6Network("2000::/3"):
            # Exclude NAT64/site-local aliases, even where is_global is true.
            return False
    return address.is_global and not address.is_multicast


def destination(url, resolver=socket.getaddrinfo):
    if len(url) > 4096 or any(ord(char) <= 32 or ord(char) == 127 for char in url):
        raise ImageError("invalid image URL")
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ImageError("image URL must use HTTP or HTTPS")
    if parsed.username is not None or parsed.password is not None:
        raise ImageError("image URL cannot contain credentials")
    host = parsed.hostname.encode("idna").decode("ascii")
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    if port != (443 if parsed.scheme == "https" else 80):
        raise ImageError("image URL must use the standard HTTP or HTTPS port")
    addresses = resolver(host, port, type=socket.SOCK_STREAM)
    if not addresses or any(not public_address(item[4][0]) for item in addresses):
        raise ImageError("image host must resolve only to public addresses")
    path = quote(parsed.path or "/", safe="/%:@!$&'()*+,;=-._~")
    if parsed.query:
        path += "?" + quote(parsed.query, safe="/%?:@!$&'()*+,;=-._~")
    return parsed.scheme, host, port, path, addresses


class PinnedHTTP(http.client.HTTPConnection):
    """Use the address already checked above; never resolve during connect."""

    def __init__(self, scheme, host, port, addresses, timeout):
        super().__init__(host, port, timeout=timeout)
        self.scheme = scheme
        self.addresses = addresses

    def connect(self):
        last_error = None
        for family, kind, protocol, _, address in self.addresses:
            sock = socket.socket(family, kind, protocol)
            try:
                sock.settimeout(self.timeout)
                sock.connect(address)
                if self.scheme == "https":
                    # The standard TLS library checks the original host name,
                    # not the pinned IP. No custom certificate or crypto code.
                    sock = ssl.create_default_context().wrap_socket(
                        sock, server_hostname=self.host
                    )
                self.sock = sock
                return
            except OSError as error:
                sock.close()
                last_error = error
        raise ImageError("cannot connect to image host") from last_error


def fetch(url, deadline, resolver=socket.getaddrinfo, connection=PinnedHTTP):
    for redirect in range(4):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ImageError("image fetch timed out")
        scheme, host, port, path, addresses = destination(url, resolver)
        client = connection(scheme, host, port, addresses, remaining)
        try:
            client.request("GET", path, headers={
                "User-Agent": "birc-image/1", "Accept": "image/*",
                "Accept-Encoding": "identity", "Connection": "close",
            })
            response = client.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if not location or redirect == 3:
                    raise ImageError("too many image redirects")
                target = urljoin(url, location)
                if scheme == "https" and urlsplit(target).scheme != "https":
                    raise ImageError("image redirect cannot downgrade HTTPS")
                url = target
                continue
            if response.status != 200:
                raise ImageError("image server returned an error")
            if response.getheader("Content-Encoding", "identity").lower() != "identity":
                raise ImageError("compressed HTTP responses are not accepted")
            length = response.getheader("Content-Length")
            if length is not None and (not length.isdecimal() or int(length) > MAX_DOWNLOAD):
                raise ImageError("image download is too large")
            data = bytearray()
            while len(data) <= MAX_DOWNLOAD:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise ImageError("image fetch timed out")
                if client.sock is not None:
                    client.sock.settimeout(remaining)
                chunk = response.read(min(65536, MAX_DOWNLOAD + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
            if len(data) > MAX_DOWNLOAD:
                raise ImageError("image download is too large")
            if length is not None and len(data) != int(length):
                raise ImageError("incomplete image download")
            return bytes(data)
        finally:
            client.close()
    raise ImageError("too many image redirects")


def encode(data):
    """Bound decode work; emit normalized PNG frames and predecoded first RGBA.

    The compact binary envelope is base64 on stdout because Bend Process.run
    returns UTF-8 strings. The UI owns the decoded bytes, not temporary paths.
    """
    if not data or len(data) > MAX_LOCAL_BYTES:
        raise ImageError("image input is empty or too large")
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(data), formats=FORMATS) as image:
            width, height = image.size
            if width <= 0 or height <= 0 or width > 4096 or height > 4096 or width * height > MAX_PIXELS:
                raise ImageError("image dimensions are too large")
            animated = image.format in ("GIF", "PNG", "WEBP") and getattr(image, "is_animated", False)
            count = getattr(image, "n_frames", 1) if animated else 1
            if count > MAX_FRAMES or width * height * count > MAX_SOURCE_FRAME_PIXELS:
                raise ImageError("image animation is too large")
            loops = image.info.get("loop") if animated else None
            iterations = 1 if loops is None else (0 if loops == 0 else min(int(loops) + 1, 65535))
            frames, durations, pngs = [], [], []
            frame_pixels = 0
            encoded_size = 32
            for index in range(count):
                image.seek(index)
                frame = ImageOps.exif_transpose(image).convert("RGBA")
                frame.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS)
                if frames and frame.size != frames[0].size:
                    raise ImageError("animation frame dimensions differ")
                frame_pixels += frame.width * frame.height
                if frame_pixels > MAX_FRAME_PIXELS:
                    raise ImageError("image animation is too large")
                duration = max(20, min(10000, int(image.info.get("duration", 100) or 100)))
                output = io.BytesIO()
                frame.save(output, format="PNG")
                png = output.getvalue()
                encoded_size += 8 + len(png)
                if encoded_size > MAX_PAYLOAD:
                    raise ImageError("image preview is too large")
                frames.append(frame)
                durations.append(duration)
                pngs.append(png)
            first = frames[0]
            rgba = first.tobytes()
            gif = b""
            if count > 1:
                output = io.BytesIO()
                options = {"loop": 0 if iterations == 0 else iterations - 1} if iterations != 1 else {}
                first.save(output, format="GIF", save_all=True, append_images=frames[1:],
                           duration=durations, disposal=2, **options)
                gif = output.getvalue()
            header = b"BIRCIMG1" + struct.pack(">6I", first.width, first.height, count, iterations, len(rgba), len(gif))
            payload = header + rgba + gif + b"".join(
                struct.pack(">2I", duration, len(png)) + png
                for duration, png in zip(durations, pngs)
            )
            if len(payload) > MAX_PAYLOAD:
                raise ImageError("image preview is too large")
            return base64.b64encode(payload).decode("ascii")


def read_local(path):
    """Only an explicit --local argument can enter this path."""
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= MAX_LOCAL_BYTES:
            raise ImageError("local image must be a bounded regular file")
        data = bytearray()
        while len(data) <= metadata.st_size:
            chunk = os.read(fd, min(65536, metadata.st_size + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        if len(data) != metadata.st_size:
            raise ImageError("local image changed while reading")
        return bytes(data)
    finally:
        os.close(fd)


def main(args):
    # Terminate in the kernel even if a decoder/DNS call cannot dispatch a
    # Python exception. Process.run observes failure and reaps this helper.
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.alarm(TIMEOUT)
    if len(args) == 1:
        data = fetch(args[0], time.monotonic() + TIMEOUT)
    elif len(args) == 2 and args[0] == "--local":
        data = read_local(args[1])
    else:
        raise ImageError("usage: birc-image <HTTP-or-HTTPS-image-URL> | --local <path>")
    result = encode(data)
    print(result)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Exception:
        # Do not echo a URL, server text, or decoder diagnostics into the tty.
        print("birc-image: image unavailable", file=sys.stderr)
        sys.exit(1)
