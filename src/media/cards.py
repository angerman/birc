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
import socket
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
    return image.cache.resolve_public(
        scheme, host, port, path, resolver, image.public_address,
        CardError("card host must resolve only to public addresses"))


def _https_downgrade(scheme, target):
    # Scheme prefix, not urlsplit: card redirects keep this check.
    return scheme == "https" and target.split(":", 1)[0] != "https"


def _html_type(content_type):
    if content_type and not content_type.split(";", 1)[0].strip().lower() == "text/html":
        return False
    return True


def fetch(url, deadline, resolver=socket.getaddrinfo, connection=None):
    """Mirror the image fetch policy with HTML bounds and content checks."""
    if connection is None:
        connection = image.PinnedHTTP
    return image.cache.bounded_fetch(
        url, deadline, resolve=lambda current: destination(current, resolver),
        connection=connection, max_bytes=MAX_HTML, redirects=REDIRECTS,
        headers={"User-Agent": "birc-cards/1", "Accept": "text/html",
                 "Accept-Encoding": "identity", "Connection": "close"},
        fail=CardError, timeout_msg="card fetch timed out",
        redirect_msg="too many card redirects", downgrade=_https_downgrade,
        downgrade_msg="card redirect cannot downgrade HTTPS",
        status_msg="card server returned an error",
        encoding_msg="compressed HTTP responses are not accepted",
        large_msg="card page is too large",
        incomplete_msg="incomplete card download",
        content_ok=_html_type, type_msg="card response is not HTML",
        return_final=True)


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
        # Cards subdirectory is 0700. Same mask as the image cache directory.
        if not image.cache.trusted(info, kind="dir", mask=0o077, nlink=False):
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
    return image.cache.payload_name(url, ".card")


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
    if directory is None:
        return None
    try:
        data = image.cache.read_cached(
            directory, cache_name(url), MAX_HTML + MAX_BASE_BYTES + 1,
            owned=image.cache_owned, identity_of=image.cache_identity)
        if data is None:
            return None
        html, base = cache_split(data)
        return html, base or url
    except (OSError, ValueError):
        return None
    finally:
        try:
            os.close(directory)
        except OSError:
            pass


def image_usage(parent):
    """Bounded (count, bytes) of image payloads in the shared parent cache.

    Orphaned staging files count exactly like image.py's own scan: no live
    writer owns one while the shared lock is held.
    """
    return image.cache.usage_scan(parent, ".img", scan_limit=image.MAX_CACHE_SCAN,
                                  owned=image.cache_owned)


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
    parent = directory = lock = None
    try:
        # One shared lock on one retained parent fd: the cards directory,
        # the lock, and the usage scan all derive from this fd, so concurrent
        # writers serialize and a renamed parent cannot split them.
        parent = image.cache_directory(create=True)
        if parent is None:
            return
        directory = _open_cards(parent, True)
        lock = image.cache.acquire_lock(parent, ".lock", owned=image.cache_owned)
        usage = image_usage(parent)
        if usage is None:
            return
        img_count, img_bytes = usage
        if (img_count + 1 > image.MAX_CACHE_ENTRIES
                or img_bytes + len(stored) > image.MAX_CACHE_BYTES):
            return
        image.cache.replace_fifo(
            directory, cache_name(url), stored, suffix=".card",
            scan_limit=MAX_CACHE_SCAN, max_entries=image.MAX_CACHE_ENTRIES,
            max_bytes=image.MAX_CACHE_BYTES, other_count=img_count,
            other_bytes=img_bytes, owned=image.cache_owned,
            identity_of=image.cache_identity,
            scan_error=lambda: OSError("card cache scan limit"),
            changed=lambda: OSError("card cache changed"),
            short_write=lambda: OSError("short card cache write"),
            token=image.secrets.token_hex)
    except (OSError, ValueError):
        pass
    finally:
        for fd in (lock, parent, directory):
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
    """Only an explicit --local argument can enter this path.

    nofollow=False: an explicit local path follows the caller's symlink.
    Cache names do not.
    """
    return image.cache.read_regular(
        path, MAX_HTML, nofollow=False,
        reject_bound=lambda: CardError("local card page must be a bounded regular file"),
        reject_short=lambda: CardError("local card page changed while reading"))


def main(args):
    # Terminate in the kernel even if a decoder/DNS call cannot dispatch a
    # Python exception. Process.run observes failure and reaps this helper.
    image.cache.arm_deadline(TIMEOUT)
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
