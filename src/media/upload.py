#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Upload one confirmed local file to 0x0.st, without a shell or proxies.

The UI owns confirmation. This helper contacts only the fixed HTTPS service,
requests a hard-to-guess URL, and prints only a checked URL on success. Files
are streamed from one descriptor; no temporary file or local basename is sent.
The service is public storage, not encryption or access-controlled storage.
"""

from __future__ import annotations

import http.client
import importlib.util
import os
import re
import secrets
import signal
import socket
import ssl
import stat
import sys
import time
from pathlib import Path

HOST = "0x0.st"
MAX_FILE = 32 * 1024 * 1024
MAX_RESPONSE = 1024
CHUNK_SIZE = 65536
TIMEOUT = 30
USER_AGENT = "birc/0.1 (IRC client; confirmed local file upload)"


def _load_cache():
    """Sibling src/media/_cache.py, or BIRC_CACHE_PY when the helper is stored alone."""
    override = os.environ.get("BIRC_CACHE_PY", "")
    path = Path(override) if override else Path(__file__).with_name("_cache.py")
    spec = importlib.util.spec_from_file_location("birc_cache", path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cache = _load_cache()


class UploadError(Exception):
    """Fixed diagnostics: 1 usage, 2 source, 3 changed, 4 IO, 5 reply, 6 time."""

    def __init__(self, code, *, http_status=0):
        self.code = code
        self.http_status = (http_status if code == 5 and type(http_status) is int
                            and 100 <= http_status <= 599 and http_status != 200 else 0)
        super().__init__(code)


def diagnostic(error):
    """A fixed numeric envelope, never a server reason/body or local path."""
    detail = f", http:{error.http_status}" if error.http_status else ""
    return f"birc-upload: failed (code:{error.code}{detail})"


def remaining(deadline, sock=None):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise UploadError(6)
    if sock is not None:
        sock.settimeout(seconds)
    return seconds


def open_source(path):
    """Stream from one descriptor. O_NOFOLLOW applies to the final component."""
    try:
        fd, metadata = cache.open_regular(path, nofollow=True)
    except (OSError, ValueError):
        raise UploadError(2) from None
    try:
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= MAX_FILE:
            raise UploadError(2)
        return fd, metadata
    except (OSError, UploadError):
        os.close(fd)
        raise UploadError(2) from None


def file_stamp(metadata):
    return metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns


def multipart(path, boundary):
    extension = os.path.splitext(path)[1]
    if not re.fullmatch(r"\.[A-Za-z0-9]{1,16}", extension):
        extension = ".bin"
    prefix = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="secret"\r\n\r\n\r\n'
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
        f'filename="upload{extension.lower()}"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n'
    ).encode("ascii")
    return prefix, f"\r\n--{boundary}--\r\n".encode("ascii")


def checked_url(body):
    if body.endswith(b"\r\n"):
        body = body[:-2]
    elif body.endswith(b"\n"):
        body = body[:-1]
    try:
        url = body.decode("ascii")
    except UnicodeDecodeError:
        raise UploadError(5) from None
    # The service generates short file paths, optionally /s/<secret>/<file>.
    # Accept only this fixed origin and a safe path, never arbitrary reply text.
    origin = "https://0x0.st/"
    if not url.startswith(origin) or len(url) > MAX_RESPONSE:
        raise UploadError(5)
    path = url[len(origin):]
    if (not re.fullmatch(r"[A-Za-z0-9._~/-]+", path) or "//" in path
            or any(part in ("", ".", "..") for part in path.split("/"))):
        raise UploadError(5)
    return url


def upload(path, *, connection=http.client.HTTPSConnection, deadline=None):
    """The transport injection is an offline test seam, never a CLI setting."""
    if deadline is None:
        deadline = time.monotonic() + TIMEOUT
    fd, metadata = open_source(path)
    client = response = None
    try:
        remaining(deadline)
        boundary = "birc-" + secrets.token_hex(16)
        prefix, footer = multipart(path, boundary)
        context = ssl.create_default_context()
        client = connection(HOST, timeout=remaining(deadline), context=context)
        client.connect()
        remaining(deadline, client.sock)
        client.putrequest("POST", "/", skip_accept_encoding=True)
        client.putheader("User-Agent", USER_AGENT)
        client.putheader("Content-Type", "multipart/form-data; boundary=" + boundary)
        client.putheader("Content-Length", str(len(prefix) + metadata.st_size + len(footer)))
        client.putheader("Accept", "text/plain")
        client.putheader("Accept-Encoding", "identity")
        client.putheader("Connection", "close")
        client.endheaders()
        remaining(deadline, client.sock)
        client.send(prefix)
        left = metadata.st_size
        while left:
            remaining(deadline, client.sock)
            data = os.read(fd, min(CHUNK_SIZE, left))
            if not data:
                raise UploadError(3)
            client.send(data)
            left -= len(data)
        if os.read(fd, 1) or file_stamp(os.fstat(fd)) != file_stamp(metadata):
            raise UploadError(3)
        remaining(deadline, client.sock)
        client.send(footer)
        remaining(deadline, client.sock)
        # HTTPConnection can release its socket after a Connection: close
        # response. Retain the socket object while its response file owns it.
        sock = client.sock
        response = client.getresponse()
        if response.status != 200:
            raise UploadError(5, http_status=response.status)
        if response.getheader("Content-Encoding", "identity").lower() != "identity":
            raise UploadError(5)
        length = response.getheader("Content-Length")
        if length is not None and (not length.isascii() or not length.isdecimal() or len(length) > 10 or int(length) > MAX_RESPONSE):
            raise UploadError(5)
        remaining(deadline, sock)
        try:
            body = response.read(MAX_RESPONSE + 1)
        except http.client.IncompleteRead:
            raise UploadError(5) from None
        remaining(deadline)
        if len(body) > MAX_RESPONSE or (length is not None and len(body) != int(length)):
            raise UploadError(5)
        return checked_url(body)
    except socket.timeout:
        raise UploadError(6) from None
    except (OSError, http.client.HTTPException):
        raise UploadError(4) from None
    finally:
        if response is not None:
            response.close()
        if client is not None:
            client.close()
        os.close(fd)


def main(args):
    # Kernel termination also bounds DNS or foreign calls that cannot dispatch
    # a Python exception. The parent observes the signal and reaps this helper.
    cache.arm_deadline(TIMEOUT)
    if len(args) != 2 or args[0] != "--local":
        raise UploadError(1)
    print(upload(args[1]))


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except UploadError as error:
        print(diagnostic(error), file=sys.stderr)
        sys.exit(error.code)
    except (Exception, KeyboardInterrupt):
        print("birc-upload: failed (code:4)", file=sys.stderr)
        sys.exit(4)
