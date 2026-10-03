#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fetch one link page and emit bounded OpenGraph text. No shell or decode files.

The parent owns scheduling and the output limit. This helper also has a total
deadline, so a helper adopted during application exit cannot run indefinitely.
Cards are public-HTTPS only: the initial page, every redirect hop, and every
thumbnail reference must be HTTPS. Only validated public addresses are
contacted, including after redirects. HTTPS is verified with the standard
library against the original host name.
Card HTML uses a private subdirectory of the image cache; local previews
never enter the disk cache. Images and cards share one explicit bounded
media budget (image.MAX_CACHE_ENTRIES / image.MAX_CACHE_BYTES) under one
lock (the parent cache .lock): this writer counts both pools and evicts
only its own oldest entries.
"""

import html
import importlib.util
import os
import re
import signal
import socket
import stat
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

spec = importlib.util.spec_from_file_location(
    "birc_image", Path(__file__).with_name("image.py"))
image = importlib.util.module_from_spec(spec)
spec.loader.exec_module(image)

MAX_HTML = 256 * 1024
MAX_TITLE = 128
MAX_DESC = 256
MAX_IMAGE = 1024
MAX_META_TAGS = 200
MAX_TAG_BYTES = 2048
# The envelope head is the UTF-8 final base: at most 4096 characters (the
# shared URL limit), which can expand to four bytes per character on disk.
MAX_BASE_BYTES = 4 * 4096
# No independent cards budget: the shared media budget lives in image.py
# (MAX_CACHE_ENTRIES / MAX_CACHE_BYTES) and covers images plus cards.
MAX_CACHE_SCAN = 256
TIMEOUT = 8
REDIRECTS = 3

META_TAG = re.compile(r"<meta\b[^>]{0,%d}>" % MAX_TAG_BYTES, re.IGNORECASE)
ATTR = re.compile(r"""([\w:-]{1,64})\s*=\s*("([^"]{0,4096})"|'([^']{0,4096})')""")
TITLE_TAG = re.compile(r"<title\b[^>]{0,256}>(.{0,512}?)</title\s*>",
                       re.IGNORECASE | re.DOTALL)


class CardError(Exception):
    pass


def url_parts(url):
    """Cards require public HTTPS; ports, credentials, and length stay shared."""
    scheme, host, port, path = image.url_parts(url)
    if scheme != "https":
        raise CardError("card URL must use HTTPS")
    return scheme, host, port, path


def destination(url, resolver=socket.getaddrinfo):
    """HTTPS-only destination with the shared public-address checks."""
    scheme, host, port, path = url_parts(url)
    addresses = resolver(host, port, type=socket.SOCK_STREAM)
    if not addresses or any(not image.public_address(item[4][0]) for item in addresses):
        raise CardError("card host must resolve only to public addresses")
    return scheme, host, port, path, addresses


def fetch(url, deadline, resolver=socket.getaddrinfo, connection=None):
    """Mirror the image fetch policy with HTML bounds and content checks."""
    if connection is None:
        connection = image.PinnedHTTP
    for redirect in range(REDIRECTS + 1):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise CardError("card fetch timed out")
        scheme, host, port, path, addresses = destination(url, resolver)
        client = connection(scheme, host, port, addresses, remaining)
        try:
            client.request("GET", path, headers={
                "User-Agent": "birc-cards/1", "Accept": "text/html",
                "Accept-Encoding": "identity", "Connection": "close",
            })
            response = client.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if not location or redirect == REDIRECTS:
                    raise CardError("too many card redirects")
                target = urljoin(url, location)
                if scheme == "https" and target.split(":", 1)[0] != "https":
                    raise CardError("card redirect cannot downgrade HTTPS")
                url = target
                continue
            if response.status != 200:
                raise CardError("card server returned an error")
            if response.getheader("Content-Encoding", "identity").lower() != "identity":
                raise CardError("compressed HTTP responses are not accepted")
            content_type = response.getheader("Content-Type", "")
            if content_type and not content_type.split(";", 1)[0].strip().lower() == "text/html":
                raise CardError("card response is not HTML")
            length = response.getheader("Content-Length")
            if length is not None and (not length.isdecimal() or int(length) > MAX_HTML):
                raise CardError("card page is too large")
            data = bytearray()
            while len(data) <= MAX_HTML:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise CardError("card fetch timed out")
                if client.sock is not None:
                    client.sock.settimeout(remaining)
                chunk = response.read(min(65536, MAX_HTML + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
            if len(data) > MAX_HTML:
                raise CardError("card page is too large")
            if length is not None and len(data) != int(length):
                raise CardError("incomplete card download")
            return bytes(data), url
        finally:
            client.close()
    raise CardError("too many card redirects")


def _open_cards(parent, create):
    """Open the cards subdirectory pinned to one retained parent fd."""
    if create:
        try:
            os.mkdir("cards", 0o700, dir_fd=parent)
        except FileExistsError:
            pass
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open("cards", flags, dir_fd=parent)
    try:
        info = os.fstat(fd)
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077):
            raise OSError("unsafe card cache directory")
    except (OSError, ValueError):
        try:
            os.close(fd)
        except OSError:
            pass
        raise
    return fd


def cache_directory(create=False):
    """Private cards subdirectory of the image cache, descriptor-checked."""
    parent = image.cache_directory(create=create)
    if parent is None:
        return None
    try:
        return _open_cards(parent, create)
    except (OSError, ValueError):
        return None
    finally:
        try:
            os.close(parent)
        except OSError:
            pass


def cache_name(url):
    import hashlib
    return hashlib.sha256(url.encode("utf-8")).hexdigest() + ".card"


def cache_split(data):
    """New entries store the final base on the first line; legacy entries are raw HTML.

    The envelope writes UTF-8, so the split reads UTF-8: a valid Unicode
    redirect base resolves hits exactly like the first fetch.
    """
    head, separator, rest = data.partition(b"\n")
    if not separator or len(head) > MAX_BASE_BYTES:
        return data, None
    try:
        text = head.decode("utf-8")
        url_parts(text)
    except (UnicodeDecodeError, image.ImageError, CardError):
        return data, None
    return rest, text


def cache_read(url):
    directory = cache_directory()
    fd = None
    if directory is None:
        return None
    try:
        name = cache_name(url)
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                     dir_fd=directory)
        info = os.fstat(fd)
        image.cache_owned(info)
        if not 0 < info.st_size <= MAX_HTML + MAX_BASE_BYTES + 1:
            return None
        os.fchmod(fd, 0o600)
        info = os.fstat(fd)
        data = bytearray()
        while len(data) < info.st_size:
            chunk = os.read(fd, min(65536, info.st_size - len(data)))
            if not chunk:
                return None
            data.extend(chunk)
        current = os.stat(name, dir_fd=directory, follow_symlinks=False)
        if (image.cache_identity(os.fstat(fd)) != image.cache_identity(info)
                or image.cache_identity(current) != image.cache_identity(info)):
            return None
        html, base = cache_split(bytes(data))
        return html, base or url
    except (OSError, ValueError):
        return None
    finally:
        for opened in (fd, directory):
            if opened is not None:
                try:
                    os.close(opened)
                except OSError:
                    pass


def image_usage(parent):
    """Bounded (count, bytes) of image payloads in the shared parent cache.

    Orphaned staging files count exactly like image.py's own scan: no live
    writer owns one while the shared lock is held.
    """
    count = total = 0
    try:
        with os.scandir(parent) as scan:
            for index, entry in enumerate(scan):
                if index >= image.MAX_CACHE_SCAN:
                    return None
                name = entry.name
                payload = (len(name) == 68 and name.endswith(".img")
                           and all(c in "0123456789abcdef" for c in name[:64]))
                staging = (len(name) == 35 and name.startswith(".write-")
                           and name.endswith(".tmp")
                           and all(c in "0123456789abcdef" for c in name[7:-4]))
                if not payload and not staging:
                    continue
                try:
                    info = entry.stat(follow_symlinks=False)
                    image.cache_owned(info)
                except OSError:
                    return None
                count += 1
                total += info.st_size
    except OSError:
        return None
    return count, total


def cache_write(url, data, final=None):
    """Best-effort bounded FIFO for fetched page HTML under the shared budget.

    The stored entry preserves the final fetch base so cache hits resolve
    relative thumbnails exactly like the first fetch. Images and cards share
    one explicit budget (image.MAX_CACHE_ENTRIES / image.MAX_CACHE_BYTES)
    under one lock (the parent cache .lock): this writer counts both pools,
    evicts only its own oldest entries, and skips the write when image
    payloads alone fill it. One retained parent fd pins the cards
    subdirectory, the lock, and the usage scan to the same directory inode,
    so a path swap between opens cannot split accounting from the write.
    """
    import fcntl
    import secrets
    if final is None:
        final = url
    try:
        url_parts(final)
    except (image.ImageError, CardError):
        final = url
    stored = final.encode("utf-8") + b"\n" + data
    if (not 0 < len(data) <= MAX_HTML or len(stored) > image.MAX_CACHE_BYTES
            or image.MAX_CACHE_ENTRIES < 1):
        return
    parent = directory = lock = temporary_fd = None
    temporary = None
    try:
        # One shared lock on one retained parent fd: the cards directory,
        # the lock, and the usage scan all derive from this fd, so concurrent
        # writers serialize and a renamed parent cannot split them.
        parent = image.cache_directory(create=True)
        if parent is None:
            return
        directory = _open_cards(parent, True)
        lock = os.open(".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK
                       | os.O_CLOEXEC, 0o600, dir_fd=parent)
        image.cache_owned(os.fstat(lock))
        os.fchmod(lock, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        usage = image_usage(parent)
        if usage is None:
            return
        img_count, img_bytes = usage
        if (img_count + 1 > image.MAX_CACHE_ENTRIES
                or img_bytes + len(stored) > image.MAX_CACHE_BYTES):
            return
        target = cache_name(url)
        try:
            previous = os.stat(target, dir_fd=directory, follow_symlinks=False)
            image.cache_owned(previous)
        except FileNotFoundError:
            previous = None
        entries = []
        with os.scandir(directory) as scan:
            for index, entry in enumerate(scan):
                if index >= MAX_CACHE_SCAN:
                    raise OSError("card cache scan limit")
                name = entry.name
                page = (len(name) == 69 and name.endswith(".card")
                        and all(c in "0123456789abcdef" for c in name[:64]))
                staging = (len(name) == 35 and name.startswith(".write-")
                           and name.endswith(".tmp")
                           and all(c in "0123456789abcdef" for c in name[7:-4]))
                if not page and not staging:
                    continue
                info = entry.stat(follow_symlinks=False)
                image.cache_owned(info)
                if name == target:
                    if previous is None or image.cache_identity(info) != image.cache_identity(previous):
                        raise OSError("card cache changed")
                    continue
                entries.append((info.st_mtime_ns, name, info))
        entries.sort(key=lambda item: (item[0], item[1]))
        total = sum(item[2].st_size for item in entries)
        while entries and (img_count + len(entries) + 1 > image.MAX_CACHE_ENTRIES
                           or img_bytes + total + len(stored) > image.MAX_CACHE_BYTES):
            _, name, info = entries.pop(0)
            if image.cache_identity(os.stat(name, dir_fd=directory, follow_symlinks=False)) != image.cache_identity(info):
                raise OSError("card cache changed")
            os.unlink(name, dir_fd=directory)
            total -= info.st_size
        temporary = ".write-" + secrets.token_hex(12) + ".tmp"
        temporary_fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
                               | os.O_CLOEXEC, 0o600, dir_fd=directory)
        os.fchmod(temporary_fd, 0o600)
        view = memoryview(stored)
        while view:
            count = os.write(temporary_fd, view)
            if count <= 0:
                raise OSError("short card cache write")
            view = view[count:]
        try:
            current = os.stat(target, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            current = None
        if ((previous is None) != (current is None)
                or (current is not None and image.cache_identity(current) != image.cache_identity(previous))):
            raise OSError("card cache changed")
        os.replace(temporary, target, src_dir_fd=directory, dst_dir_fd=directory)
        temporary = None
    except (OSError, ValueError):
        pass
    finally:
        if temporary is not None and temporary_fd is not None and directory is not None:
            try:
                os.unlink(temporary, dir_fd=directory)
            except OSError:
                pass
        for fd in (temporary_fd, lock, parent, directory):
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass


def clean(text, limit):
    """One sanitized single line: entities decoded, controls spaced, bounded."""
    text = html.unescape(text)
    text = "".join(char if 32 <= ord(char) != 127 else " " for char in text)
    return " ".join(text.split())[:limit]


def meta_fields(document):
    """First og:title, og:description, og:image across bounded meta tags."""
    found = {}
    for index, match in enumerate(META_TAG.finditer(document)):
        if index >= MAX_META_TAGS:
            break
        attrs = {}
        for name, _, double, single in ATTR.findall(match.group(0)):
            attrs[name.lower()] = double or single
        key = (attrs.get("property") or attrs.get("name") or "").lower()
        if key in ("og:title", "og:description", "og:image") and key not in found:
            found[key] = attrs.get("content", "")
        if key == "description" and "og:description" not in found and "description" not in found:
            found["description"] = attrs.get("content", "")
    return found


def card_image(raw, base):
    """Absolute HTTPS thumbnail references only; the rest stay text-only."""
    if not raw or len(raw) > MAX_IMAGE:
        return ""
    try:
        target = urljoin(base, raw.strip())
        url_parts(target)
    except (image.ImageError, CardError):
        return ""
    if len(target) > MAX_IMAGE:
        return ""
    return target


def parse_html(data, base):
    """Bounded decode; invalid bytes fall back to Latin-1 like live input."""
    try:
        document = data.decode("utf-8")
    except UnicodeDecodeError:
        document = data.decode("latin-1")
    found = meta_fields(document)
    title = found.get("og:title", "")
    if not title:
        match = TITLE_TAG.search(document)
        title = match.group(1) if match else ""
    desc = found.get("og:description", found.get("description", ""))
    raw_image = found.get("og:image", "")
    if len(raw_image) > MAX_IMAGE:
        thumbnail = ""
    else:
        thumbnail = card_image(clean(raw_image, MAX_IMAGE), base)
    return (clean(title, MAX_TITLE), clean(desc, MAX_DESC), thumbnail)


def encode_remote(url, deadline, resolver=socket.getaddrinfo, connection=None):
    url_parts(url)
    cached = cache_read(url)
    if cached is not None:
        data, base = cached
        try:
            return parse_html(data, base)
        except Exception:
            pass  # Never trust cached bytes without the same bounded parse.
    data, final = fetch(url, deadline, resolver, connection)
    result = parse_html(data, final)
    cache_write(url, data, final)
    return result


def read_local(path):
    """Only an explicit --local argument can enter this path."""
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= MAX_HTML:
            raise CardError("local card page must be a bounded regular file")
        data = bytearray()
        while len(data) <= metadata.st_size:
            chunk = os.read(fd, min(65536, metadata.st_size + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        if len(data) != metadata.st_size:
            raise CardError("local card page changed while reading")
        return bytes(data)
    finally:
        os.close(fd)


def main(args):
    # Terminate in the kernel even if a decoder/DNS call cannot dispatch a
    # Python exception. Process.run observes failure and reaps this helper.
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.alarm(TIMEOUT)
    if len(args) == 1:
        title, desc, thumbnail = encode_remote(args[0], time.monotonic() + TIMEOUT)
    elif len(args) == 2 and args[0] == "--local":
        title, desc, thumbnail = parse_html(read_local(args[1]), "https://local.invalid/")
    else:
        raise CardError("usage: birc-cards <HTTPS-page-URL> | --local <path>")
    print(title)
    print(desc)
    print(thumbnail)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Exception:
        # Do not echo a URL, server text, or decoder diagnostics into the tty.
        print("birc-cards: card unavailable", file=sys.stderr)
        sys.exit(1)
