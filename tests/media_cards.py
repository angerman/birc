#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Synthetic-only card fetch and parse controls; never contact a page host."""
import fcntl
import importlib.util
import io
import os
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location("birc_cards", HERE / "src/media/cards.py")
cards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cards)
image = cards.image


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

# Destination, address, and URL policy are shared with the image helper.
for ip in ("127.0.0.1", "10.1.2.3", "192.168.1.1", "169.254.169.254",
           "::1", "fe80::1", "fc00::1", "ff02::1", "::ffff:127.0.0.1"):
    assert not image.public_address(ip), ip
    rejected(lambda: image.destination("https://example.test/read", resolver([ip])))
assert image.public_address("93.184.216.34")
for url in ("file:///tmp/read.html", "ftp://example.test/read",
            "https://me:secret@example.test/read",
            "https://example.test:9999/read",
            "https://example.test/a\r\nHost:x",
            "https://example.test/" + "x" * 4096):
    rejected(lambda: image.destination(url, public))


class Response:
    def __init__(self, status=200, data=b"<html></html>", headers=None):
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
        assert headers["Accept"] == "text/html"
        self.path = path

    def getresponse(self):
        return responses.pop(0)

    def close(self):
        self.closed = True


def fetched(url="https://example.test/read", resolve=public):
    return cards.fetch(url, time.monotonic() + 2, resolve, Connection)


page = b'<html><head><meta property="og:title" content="T"></head></html>'
responses[:] = [Response(data=page, headers={"Content-Length": str(len(page))})]
data, final = fetched()
assert (data, final) == (page, "https://example.test/read") and connections[-1].closed
# Missing content type is accepted; anything but text/html is not.
responses[:] = [Response(data=page)]
assert fetched()[0] == page
responses[:] = [Response(data=page, headers={"Content-Type": "text/html; charset=utf-8"})]
assert fetched()[0] == page
for content_type in ("image/png", "text/plain", "application/json"):
    responses[:] = [Response(data=page, headers={"Content-Type": content_type})]
    rejected(fetched)
    assert connections[-1].closed
# Redirects re-resolve and never downgrade; private targets fail closed.
responses[:] = [Response(302, headers={"Location": "/next"}), Response(data=page)]
assert fetched()[1] == "https://example.test/next" and connections[-1].path == "/next"
responses[:] = [Response(302, headers={"Location": "http://example.test/read"})]
rejected(fetched)
responses[:] = [Response(302, headers={"Location": "https://127.0.0.1/read"})]
before = len(connections)
rejected(lambda: fetched(resolve=lambda host, port, **kw: resolver(
    ["127.0.0.1" if host == "127.0.0.1" else "93.184.216.34"])(host, port, **kw)))
assert len(connections) == before + 1 and connections[-1].closed
responses[:] = [Response(302, headers={"Location": "/a"}),
                Response(302, headers={"Location": "/b"}),
                Response(302, headers={"Location": "/c"}),
                Response(302, headers={"Location": "/d"})]
rejected(fetched)
for response in (Response(404), Response(headers={"Content-Encoding": "gzip"}),
                 Response(headers={"Content-Length": "999999999"}),
                 Response(headers={"Content-Length": str(len(page) + 1)}),
                 Response(data=b"x" * (cards.MAX_HTML + 1))):
    responses[:] = [response]
    rejected(fetched)
    assert connections[-1].closed
rejected(lambda: cards.fetch("https://example.test/read", time.monotonic() - 1,
                             public, Connection))
# C8.3: cards are public-HTTPS only, at the initial URL and after redirects.
rejected(lambda: cards.destination("http://example.test/read", public))
responses[:] = [Response(data=page)]
before = len(connections)
rejected(lambda: fetched("http://example.test/read"))
assert len(connections) == before and len(responses) == 1
responses[:] = [Response(302, headers={"Location": "http://example.test/next"})]
rejected(fetched)
saved_cache = os.environ.get("BIRC_IMAGE_CACHE")
os.environ["BIRC_IMAGE_CACHE"] = "none"
try:
    responses[:] = [Response(data=page)]
    before = len(connections)
    rejected(lambda: cards.encode_remote("http://example.test/read",
                                         time.monotonic() + 2, public, Connection))
    assert len(connections) == before
finally:
    if saved_cache is None:
        del os.environ["BIRC_IMAGE_CACHE"]
    else:
        os.environ["BIRC_IMAGE_CACHE"] = saved_cache


def parsed(data, base="https://example.test/read"):
    return cards.parse_html(data, base)


# Attribute order, quote style, entities, and whitespace are all normalized.
assert parsed(b'<meta content="T" property="og:title">') == ("T", "", "")
assert parsed(b"<meta property='og:title' content='Q'>") == ("Q", "", "")
assert parsed(b'<meta property="og:title" content="A &amp; B">') == ("A & B", "", "")
assert parsed(b'<meta property="og:title" content="  a\tb\nc  ">') == ("a b c", "", "")
assert parsed(b'<meta property="og:title" content="x\ty\x7fz">') == ("x y z", "", "")
assert parsed(b"<title>Fall back</title>") == ("Fall back", "", "")
assert parsed(b'<meta property="og:title" content="OG"><title>Other</title>') == ("OG", "", "")
assert parsed(b'<meta name="description" content="Plain">') == ("", "Plain", "")
assert parsed(b'<meta property="og:description" content="OG">'
               b'<meta name="description" content="Plain">') == ("", "OG", "")
assert parsed(b'<meta property="og:title" content="caf\xe9 \xff">') == ("caf\u00e9 \u00ff", "", "")
assert parsed(b"") == ("", "", "")
# First tag wins; later duplicates cannot override it.
assert parsed(b'<meta property="og:title" content="First">'
              b'<meta property="og:title" content="Second">') == ("First", "", "")
assert parsed(b'<meta property="og:title">') == ("", "", "")
# Only a bounded prefix of tags is scanned.
many = b"".join(b'<meta property="og:title" content="No%d">' % i for i in range(300))
assert parsed(many) == ("No0", "", "")
late = b"".join(b'<meta name="junk" content="x">' for _ in range(210))
assert parsed(late + b'<meta property="og:title" content="Late">') == ("", "", "")
assert parsed(b'<meta property="og:title" content="' + b"y" * 200 + b'">') == ("y" * 128, "", "")
assert parsed(b'<meta property="og:description" content="' + b"z" * 300 + b'">')[1] == "z" * 256
# A single tag past the scan bound is skipped, never partially read.
assert parsed(b'<meta property="og:title" content="' + b"y" * 5000 + b'">') == ("", "", "")
# Thumbnails must be absolute HTTP(S) after joining; the rest stay text-only.
assert parsed(b'<meta property="og:image" content="https://cdn.test/i.png">')[2] == "https://cdn.test/i.png"
assert parsed(b'<meta property="og:image" content="/i.png">')[2] == "https://example.test/i.png"
assert parsed(b'<meta property="og:image" content="file:///tmp/i.png">')[2] == ""
assert parsed(b'<meta property="og:image" content="https://me:s@example.test/i.png">')[2] == ""
assert parsed(b'<meta property="og:image" content="https://example.test:9999/i.png">')[2] == ""
assert parsed(b'<meta property="og:image" content="' + b"https://example.test/" + b"q" * 2000 + b'">')[2] == ""
# C8.2: overlong thumbnails are rejected before truncation; exact-1024 survives.
exact1024 = "https://example.test/" + "q" * 1003
assert len(exact1024) == 1024
assert parsed(b'<meta property="og:image" content="' + exact1024.encode() + b'">')[2] == exact1024
over1025 = "https://example.test/" + "q" * 1004
assert len(over1025) == 1025
assert parsed(b'<meta property="og:image" content="' + over1025.encode() + b'">')[2] == ""
assert cards.card_image("q" * 1025, "https://example.test/read") == ""
assert cards.card_image(exact1024, "https://example.test/read") == exact1024
# C8.3: plaintext thumbnails stay text-only, like any other non-HTTPS target.
assert parsed(b'<meta property="og:image" content="http://example.test/i.png">')[2] == ""

fixtures = HERE / "fixtures/cards"
assert parsed((fixtures / "og_basic.html").read_bytes()) == (
    "Synthetic Post & More", "A bounded description with newline.",
    "https://example.test/thumb.png")
assert parsed((fixtures / "og_minimal.html").read_bytes()) == (
    "Only A Title", "Plain meta fallback.", "")
assert parsed((fixtures / "og_none.html").read_bytes()) == ("", "", "")

# --local reads bounded regular files for synthetic fixtures.
title, desc, thumb = cards.parse_html(
    cards.read_local(str(fixtures / "og_basic.html")), "https://example.test/read")
assert (title, thumb) == ("Synthetic Post & More", "https://example.test/thumb.png")
rejected(lambda: cards.read_local(str(fixtures / "og_basic.html") + ".missing"))
with tempfile.TemporaryDirectory() as sandbox:
    big = Path(sandbox) / "big.html"
    big.write_bytes(b"x" * (cards.MAX_HTML + 1))
    rejected(lambda: cards.read_local(str(big)))
    link = Path(sandbox) / "link.html"
    try:
        link.symlink_to(fixtures / "og_basic.html")
    except OSError:
        link = None
    if link is not None:
        # Explicit local paths follow the caller's own symlink; cache never does.
        assert cards.read_local(str(link))[:15] == b"<!DOCTYPE html>"


def isolated_cache(monkey):
    root = Path(tempfile.mkdtemp(prefix="birc-cards-")).resolve()  # Darwin's /var alias is not the tested cache.
    monkey["BIRC_IMAGE_CACHE"] = str(root / "img")
    monkey["XDG_CACHE_HOME"] = str(root / "xdg")
    return root


saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    url = "https://example.test/cached"
    responses[:] = [Response(data=page)]
    assert cards.encode_remote(url, time.monotonic() + 2, public, Connection) == ("T", "", "")
    assert connections[-1].closed
    # The second request reuses the private cache without a network fetch.
    before = len(connections)
    assert cards.encode_remote(url, time.monotonic() + 2, public, Connection) == ("T", "", "")
    assert len(connections) == before
    cached = root / "img" / "cards"
    names = sorted(path.name for path in cached.iterdir() if path.name.endswith(".card"))
    assert len(names) == 1
    info = (cached / names[0]).stat()
    assert stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid()
    assert info.st_mode & 0o777 == 0o600
    assert cached.stat().st_mode & 0o777 == 0o700
    # A poisoned cache entry parses to a bounded empty card, never a crash.
    (cached / names[0]).write_bytes(b"\xff\xfe broken \x00 entry")
    before = len(connections)
    assert cards.encode_remote(url, time.monotonic() + 2, public, Connection) == ("", "", "")
    assert len(connections) == before
    # Eviction keeps the newest entries under the shared media budget.
    saved_entries, saved_bytes = image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES
    try:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = 2, 10 * 1024 * 1024
        for index in range(4):
            responses[:] = [Response(data=page)]
            cards.encode_remote("https://example.test/e%d" % index,
                                time.monotonic() + 2, public, Connection)
        names = sorted(path.name for path in cached.iterdir() if path.name.endswith(".card"))
        assert len(names) == 2, names
    finally:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = saved_entries, saved_bytes
    os.environ["BIRC_IMAGE_CACHE"] = "none"
    responses[:] = [Response(data=page)]
    before = len(connections)
    assert cards.encode_remote("https://example.test/nocache",
                               time.monotonic() + 2, public, Connection) == ("T", "", "")
    assert len(connections) == before + 1
    assert cards.cache_directory() is None
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8.1: a cache hit resolves relative thumbnails against the same final base
# as the first fetch, even across cross-origin/directory redirects.
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    first_url = "https://example.test/dir/page"
    moved = (b'<html><head><meta property="og:title" content="Moved">'
             b'<meta property="og:image" content="thumb.png"></head></html>')
    responses[:] = [Response(302, headers={"Location": "/other/final"}),
                    Response(data=moved)]
    before = len(connections)
    first = cards.encode_remote(first_url, time.monotonic() + 2, public, Connection)
    assert first == ("Moved", "", "https://example.test/other/thumb.png"), first
    assert len(connections) == before + 2
    before = len(connections)
    second = cards.encode_remote(first_url, time.monotonic() + 2, public, Connection)
    assert len(connections) == before
    assert second == first, (second, first)
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8e: the envelope writes UTF-8, so cache_split must read UTF-8. Valid
# Unicode redirect path/host hits resolve against the final base, exactly
# like the first fetch; the ASCII positive above keeps passing unchanged.
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    first_url = "https://example.test/dir/page"
    moved = ("<html><head><meta property=\"og:title\" content=\"Moved\">"
             "<meta property=\"og:image\" content=\"thumb.png\"></head></html>").encode("utf-8")
    responses[:] = [Response(302, headers={"Location": "/caf\u00e9/final"}),
                    Response(data=moved)]
    before = len(connections)
    first = cards.encode_remote(first_url, time.monotonic() + 2, public, Connection)
    assert first == ("Moved", "", "https://example.test/caf\u00e9/thumb.png"), first
    assert len(connections) == before + 2
    before = len(connections)
    second = cards.encode_remote(first_url, time.monotonic() + 2, public, Connection)
    assert len(connections) == before
    assert second == first, (second, first)
    assert second[2] == "https://example.test/caf\u00e9/thumb.png", second
finally:
    os.environ.clear()
    os.environ.update(saved)
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    first_url = "https://example.test/start"
    moved = ("<html><head><meta property=\"og:title\" content=\"Host\">"
             "<meta property=\"og:image\" content=\"/pic.png\"></head></html>").encode("utf-8")
    responses[:] = [Response(302, headers={"Location": "https://m\u00fcnchen.test/final"}),
                    Response(data=moved)]
    before = len(connections)
    first = cards.encode_remote(first_url, time.monotonic() + 2, public, Connection)
    assert first == ("Host", "", "https://m\u00fcnchen.test/pic.png"), first
    assert len(connections) == before + 2
    before = len(connections)
    second = cards.encode_remote(first_url, time.monotonic() + 2, public, Connection)
    assert len(connections) == before
    assert second == first, (second, first)
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8e: envelope unit guards — valid bases round-trip exactly, while legacy
# and hostile first lines stay raw HTML.
assert cards.cache_split(b"https://example.test/f\n<body>") == (b"<body>", "https://example.test/f")
assert cards.cache_split("https://example.test/caf\u00e9/f\n<body>".encode("utf-8")) == (
    b"<body>", "https://example.test/caf\u00e9/f")
extreme = "https://example.test/" + "\U0001d11e" * (4096 - len("https://example.test/"))
assert len(extreme) == 4096
assert cards.cache_split(extreme.encode("utf-8") + b"\n<body>") == (b"<body>", extreme)
assert cards.cache_split(b"no-newline-here") == (b"no-newline-here", None)
assert cards.cache_split(b"http://example.test/f\n<body>") == (
    b"http://example.test/f\n<body>", None)
assert cards.cache_split(b"\xff\xfe\n<body>") == (b"\xff\xfe\n<body>", None)
assert cards.cache_split(b"Just some text\n<html>") == (b"Just some text\n<html>", None)
assert cards.cache_split(b"https://example.test/" + b"q" * 20000 + b"\n<body>")[1] is None

# C8.4: images and cards share one explicit bounded media budget. The cards
# writer counts both pools, evicts only its own oldest entries, and skips a
# write (without evicting) when image payloads alone fill the budget.
assert not hasattr(cards, "MAX_CACHE_ENTRIES") and not hasattr(cards, "MAX_CACHE_BYTES")
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    saved_entries, saved_bytes = image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES
    try:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = 4, 10 * 1024 * 1024
        for index in range(3):
            image.cache_write("https://example.test/img%d" % index, b"01234567")
        parent = root / "img"
        assert len([p for p in parent.iterdir() if p.name.endswith(".img")]) == 3
        for index in range(3):
            os.utime(parent / image.cache_name("https://example.test/img%d" % index),
                     ns=(index + 1, index + 1))
        for index in range(2):
            responses[:] = [Response(data=page)]
            assert cards.encode_remote("https://example.test/c%d" % index,
                                       time.monotonic() + 2, public, Connection) == ("T", "", "")
        assert len([p for p in parent.iterdir() if p.name.endswith(".img")]) == 3
        cards_dir = parent / "cards"
        card_names = sorted(p.name for p in cards_dir.iterdir() if p.name.endswith(".card"))
        assert len(card_names) == 1, card_names
        image.cache_write("https://example.test/img3", b"01234567")
        responses[:] = [Response(data=page)]
        assert cards.encode_remote("https://example.test/c9",
                                   time.monotonic() + 2, public, Connection) == ("T", "", "")
        # C8d: the shared budget covers both writer orders. The fourth image
        # evicts the oldest image (never the card), so the combined total is
        # 4, not the 5 entries image-only accounting produced; the new card
        # then replaces the oldest card within the same budget.
        images = sorted(p.name for p in parent.iterdir() if p.name.endswith(".img"))
        assert images == sorted(image.cache_name("https://example.test/img%d" % i)
                                for i in (1, 2, 3)), images
        assert sorted(p.name for p in cards_dir.iterdir()
                      if p.name.endswith(".card")) == [
                          cards.cache_name("https://example.test/c9")]
        combined = len(images) + len([p for p in cards_dir.iterdir()
                                      if p.name.endswith(".card")])
        assert combined == 4, combined
    finally:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = saved_entries, saved_bytes
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8.4 (kept): when image payloads alone fill the shared budget, the cards
# writer skips without writing or evicting; the fetch itself still succeeds
# because the cache is best-effort.
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    saved_entries, saved_bytes = image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES
    try:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = 4, 10 * 1024 * 1024
        for index in range(4):
            image.cache_write("https://example.test/full%d" % index, b"01234567")
        parent = root / "img"
        before = sorted(p.name for p in parent.iterdir() if p.name.endswith(".img"))
        assert len(before) == 4, before
        responses[:] = [Response(data=page)]
        assert cards.encode_remote("https://example.test/skipped",
                                   time.monotonic() + 2, public, Connection) == ("T", "", "")
        assert sorted(p.name for p in parent.iterdir()
                      if p.name.endswith(".img")) == before
        cards_dir = parent / "cards"
        assert not cards_dir.is_dir() or not [
            p for p in cards_dir.iterdir() if p.name.endswith(".card")]
    finally:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = saved_entries, saved_bytes
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8d: sequential cards->image writes stay within the shared count budget; a
# full cards pool makes image writes skip without evicting cards, and a
# fitting image still lands.
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    saved_entries, saved_bytes = image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES
    try:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = 4, 10 * 1024 * 1024
        for index in range(4):
            responses[:] = [Response(data=page)]
            cards.encode_remote("https://example.test/k%d" % index,
                                time.monotonic() + 2, public, Connection)
        parent = root / "img"
        before = sorted(p.name for p in (parent / "cards").iterdir()
                        if p.name.endswith(".card"))
        assert len(before) == 4, before
        image.cache_write("https://example.test/late", b"01234567")
        assert not (parent / image.cache_name("https://example.test/late")).exists()
        assert sorted(p.name for p in (parent / "cards").iterdir()
                      if p.name.endswith(".card")) == before
        image.MAX_CACHE_ENTRIES = 8
        image.cache_write("https://example.test/fits", b"01234567")
        assert (parent / image.cache_name("https://example.test/fits")).exists()
        total = len([p for p in parent.iterdir() if p.name.endswith(".img")]) + len(
            [p for p in (parent / "cards").iterdir() if p.name.endswith(".card")])
        assert total == 5, total
    finally:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = saved_entries, saved_bytes
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8d: the shared byte budget also covers both writers. The image writer
# evicts its own oldest payload to fit, never a card.
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    saved_entries, saved_bytes = image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES
    try:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = 64, 400
        cards.cache_write("https://example.test/b0", b"x" * 100,
                          "https://example.test/b0")
        cards.cache_write("https://example.test/b1", b"y" * 100,
                          "https://example.test/b1")
        parent = root / "img"
        used = sum(p.stat().st_size for p in (parent / "cards").iterdir()
                   if p.name.endswith(".card"))
        assert used == 2 * (len("https://example.test/b0") + 1 + 100), used
        image.cache_write("https://example.test/a", b"a" * 100)
        first = parent / image.cache_name("https://example.test/a")
        assert first.exists()
        os.utime(first, ns=(1, 1))
        image.cache_write("https://example.test/b", b"b" * 100)
        assert not first.exists(), "image writer must evict its own oldest bytes"
        assert (parent / image.cache_name("https://example.test/b")).exists()
        total = sum(p.stat().st_size for p in parent.iterdir()
                    if p.name.endswith(".img")) + sum(
                        p.stat().st_size for p in (parent / "cards").iterdir()
                        if p.name.endswith(".card"))
        assert total <= 400, total
        assert len([p for p in (parent / "cards").iterdir()
                    if p.name.endswith(".card")]) == 2
    finally:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = saved_entries, saved_bytes
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8d: interleaved image/card writes keep every intermediate combined total
# within the shared budget.
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    saved_entries, saved_bytes = image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES
    try:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = 4, 10 * 1024 * 1024
        parent = root / "img"
        for index in range(6):
            responses[:] = [Response(data=page)]
            cards.encode_remote("https://example.test/w%d" % index,
                                time.monotonic() + 2, public, Connection)
            image.cache_write("https://example.test/v%d" % index, b"01234567")
            total = len([p for p in parent.iterdir() if p.name.endswith(".img")])
            cards_dir = parent / "cards"
            if cards_dir.is_dir():
                total += len([p for p in cards_dir.iterdir()
                              if p.name.endswith(".card")])
            assert total <= 4, (index, total)
    finally:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = saved_entries, saved_bytes
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8d: one shared lock. While the parent cache lock is held, both the image
# and the card writers skip without writing or evicting; the fetch itself
# still succeeds because the cache is best-effort.
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    image.cache_write("https://example.test/kept", b"01234567")
    parent = root / "img"
    assert (parent / image.cache_name("https://example.test/kept")).exists()
    responses[:] = [Response(data=page)]
    cards.encode_remote("https://example.test/kept-card",
                        time.monotonic() + 2, public, Connection)
    cards_dir = parent / "cards"
    before = sorted(p.name for p in cards_dir.iterdir() if p.name.endswith(".card"))
    assert len(before) == 1, before
    with (parent / ".lock").open("r+b") as held:
        fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
        image.cache_write("https://example.test/blocked-img", b"01234567")
        responses[:] = [Response(data=page)]
        assert cards.encode_remote("https://example.test/blocked-card",
                                   time.monotonic() + 2, public, Connection) == ("T", "", "")
        assert not (parent / image.cache_name("https://example.test/blocked-img")).exists()
        assert sorted(p.name for p in cards_dir.iterdir()
                      if p.name.endswith(".card")) == before
        assert (parent / image.cache_name("https://example.test/kept")).exists()
finally:
    os.environ.clear()
    os.environ.update(saved)

# C8d: concurrent image and card writers stay within the shared budget; the
# one lock serializes accounting so racing totals cannot exceed it.
saved = dict(os.environ)
try:
    root = isolated_cache(os.environ)
    saved_entries, saved_bytes = image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES
    try:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = 8, 10 * 1024 * 1024
        errors = []

        def hammer(worker):
            try:
                for index in range(8):
                    image.cache_write("https://example.test/t%d-i%d" % (worker, index),
                                      b"01234567")
                    blob = "https://example.test/t%d-c%d" % (worker, index)
                    cards.cache_write(blob, b"<html></html>", blob)
            except Exception as error:  # Writers are best-effort; threads report.
                errors.append(error)

        threads = [threading.Thread(target=hammer, args=(worker,)) for worker in range(4)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=60)
            assert not thread.is_alive()
        assert not errors, errors
        parent = root / "img"
        total = len([p for p in parent.iterdir() if p.name.endswith(".img")])
        cards_dir = parent / "cards"
        if cards_dir.is_dir():
            total += len([p for p in cards_dir.iterdir() if p.name.endswith(".card")])
        assert total <= 8, total
    finally:
        image.MAX_CACHE_ENTRIES, image.MAX_CACHE_BYTES = saved_entries, saved_bytes
finally:
    os.environ.clear()
    os.environ.update(saved)

# The CLI prints exactly three sanitized lines and fails with a fixed message.
ok = subprocess.run([sys.executable, str(HERE / "src/media/cards.py"),
                     "--local", str(fixtures / "og_basic.html")],
                    capture_output=True, text=True, timeout=30)
assert ok.returncode == 0, ok.stderr
lines = ok.stdout.split("\n")
assert lines[:3] == ["Synthetic Post & More", "A bounded description with newline.",
                     "https://local.invalid/thumb.png"], lines
bad = subprocess.run([sys.executable, str(HERE / "src/media/cards.py"),
                       "https://example.test:9999/read"],
                     capture_output=True, text=True, timeout=30,
                     env={**os.environ, "BIRC_IMAGE_CACHE": "none"})
assert bad.returncode == 1 and bad.stdout == ""
assert bad.stderr == "birc-cards: card unavailable\n", bad.stderr

print("media_cards=ok")
