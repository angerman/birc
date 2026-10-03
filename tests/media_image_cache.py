#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Owned synthetic cache files and fake fetches only; never use the network."""
import contextlib
import fcntl
import hashlib
import importlib.util
import io
import os
import stat
import tempfile
from pathlib import Path
from unittest.mock import patch

from PIL import Image

spec = importlib.util.spec_from_file_location(
    "birc_image", Path(__file__).parents[1] / "src/media/image.py")
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)
source = io.BytesIO()
Image.new("RGB", (2, 3), "red").save(source, format="PNG")
png = source.getvalue()
expected = media.encode(png) + "\n"
url = "https://example.test/image.png?token=synthetic#view"


def name(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest() + ".img"


def invoke(args, directory, fetched=png, **environment):
    env = {key: value for key, value in os.environ.items()
           if key not in ("BIRC_IMAGE_CACHE", "XDG_CACHE_HOME", "HOME")}
    if directory is not None:
        env["BIRC_IMAGE_CACHE"] = str(directory)
    env.update(environment)
    output = io.StringIO()
    with patch.dict(os.environ, env, clear=True), \
         patch.object(media, "fetch", side_effect=fetched if isinstance(fetched, Exception) else None,
                      return_value=fetched) as fetch, \
         patch.object(media, "destination", side_effect=AssertionError("cache used DNS")), \
         patch.object(media.socket, "getaddrinfo", side_effect=AssertionError("cache used DNS")), \
         patch.object(media.signal, "signal"), patch.object(media.signal, "alarm"), \
         contextlib.redirect_stdout(output):
        media.main(args)
    return output.getvalue(), fetch.call_count


def rejected(call):
    try:
        call()
    except (media.ImageError, OSError, ValueError):
        return
    raise AssertionError("invalid input was accepted")


with tempfile.TemporaryDirectory(prefix="birc-image-cache-") as temporary:
    root = Path(temporary).resolve()  # Darwin's /var alias is not the tested cache.
    cache = root / "cache"
    result, calls = invoke([url], cache)
    assert result == expected and calls == 1
    # RED on the old helper: the second invocation must not fetch or resolve.
    result, calls = invoke([url], cache, fetched=AssertionError("warm cache fetched"))
    assert result == expected and calls == 0
    entry = cache / name(url)
    assert entry.read_bytes() == png
    assert stat.S_IMODE(cache.stat().st_mode) == 0o700
    assert stat.S_IMODE(entry.stat().st_mode) == 0o600
    assert all("example" not in item.name and "synthetic" not in item.name for item in cache.iterdir())

    # Exact query/fragment identity, with no URL text saved in metadata.
    for distinct in (url + "2", url.replace("synthetic", "other")):
        assert invoke([distinct], cache) == (expected, 1)
        assert invoke([distinct], cache, fetched=AssertionError("hit fetched")) == (expected, 0)
        assert (cache / name(distinct)).read_bytes() == png

    # A hit must not turn an invalid URL into an accepted local image.
    for invalid in ("file:///tmp/a.png", "ftp://example.test/a.png",
                    "https://me:secret@example.test/a.png", "https://example.test:0/a.png",
                    "https://example.test:9999/a.png", "https://example.test/a\r\n.png",
                    "https://example.test/" + "x" * 4096):
        (cache / name(invalid)).write_bytes(png)
        rejected(lambda: invoke([invalid], cache, fetched=AssertionError("invalid URL fetched")))

    entry.write_bytes(b"broken image")
    assert invoke([url], cache) == (expected, 1)
    assert entry.read_bytes() == png
    entry.write_bytes(b"broken image")
    rejected(lambda: invoke([url], cache, fetched=media.ImageError("synthetic network failure")))
    assert entry.read_bytes() == b"broken image"  # no unsafe deletion on failure
    rejected(lambda: invoke([url], cache, fetched=b"also not an image"))
    assert entry.read_bytes() == b"broken image"
    assert invoke([url], cache) == (expected, 1)

    # Bound snapshots; an oversized cache entry is never read into memory.
    with entry.open("wb") as file:
        file.truncate(media.MAX_DOWNLOAD + 1)
    assert invoke([url], cache) == (expected, 1)
    assert entry.read_bytes() == png
    cache.chmod(0o755); entry.chmod(0o644)
    assert invoke([url], cache) == (expected, 1)
    assert stat.S_IMODE(cache.stat().st_mode) == 0o755
    assert stat.S_IMODE(entry.stat().st_mode) == 0o644
    cache.chmod(0o700)
    assert invoke([url], cache, fetched=AssertionError("private hit fetched")) == (expected, 0)
    assert stat.S_IMODE(cache.stat().st_mode) == 0o700
    assert stat.S_IMODE(entry.stat().st_mode) == 0o600

    # Symlinks, hard links, FIFOs, and nonregular files cannot be read, replaced,
    # chmodded, or evicted. A valid freshly fetched preview still succeeds.
    outside = root / "outside.png"; outside.write_bytes(png); outside.chmod(0o644)
    for kind in ("symlink", "hardlink", "fifo", "directory"):
        unsafe = root / kind; unsafe.mkdir(mode=0o700)
        target = unsafe / name(url)
        if kind == "symlink":
            target.symlink_to(outside)
        elif kind == "hardlink":
            os.link(outside, target)
        elif kind == "fifo":
            os.mkfifo(target)
        else:
            target.mkdir()
        before = target.lstat()
        assert invoke([url], unsafe) == (expected, 1)
        assert outside.read_bytes() == png and stat.S_IMODE(outside.stat().st_mode) == 0o644
        after = target.lstat()
        assert (after.st_dev, after.st_ino, after.st_mode, after.st_nlink) == (
            before.st_dev, before.st_ino, before.st_mode, before.st_nlink)
        if kind == "symlink":
            assert target.is_symlink()
        elif kind == "fifo":
            assert stat.S_ISFIFO(target.stat().st_mode)
        elif kind == "directory":
            assert target.is_dir()
        else:
            target.unlink()
    redirected = root / "redirected"; redirected.mkdir()
    alias = root / "alias"; alias.symlink_to(redirected, target_is_directory=True)
    assert invoke([url], alias) == (expected, 1)
    assert list(redirected.iterdir()) == []

    real_fstat = os.fstat
    def foreign_file(fd):
        info = real_fstat(fd)
        if stat.S_ISREG(info.st_mode):
            values = list(info); values[4] = info.st_uid + 1
            return os.stat_result(values)
        return info
    with patch.object(media.os, "fstat", side_effect=foreign_file):
        assert invoke([url], cache) == (expected, 1)
    assert entry.read_bytes() == png
    with patch.object(media.os, "getuid", return_value=os.getuid() + 1):
        assert invoke([url], cache) == (expected, 1)

    refreshed = root / "refreshed"
    with patch.object(media, "MAX_CACHE_ENTRIES", 2), \
         patch.object(media, "MAX_CACHE_BYTES", len(png) * 2):
        assert invoke([url], refreshed) == (expected, 1)
        assert invoke([url + "other"], refreshed) == (expected, 1)
        other = refreshed / name(url + "other")
        os.utime(other, ns=(1, 1))
        target = refreshed / name(url)
        target.write_bytes(b"x" * len(png))
        assert invoke([url], refreshed) == (expected, 1)
        assert target.read_bytes() == png
        assert other.exists() and other.read_bytes() == png
        assert len(list(refreshed.glob("*.img"))) == 2
        # A genuinely new key still consumes a slot and evicts FIFO's oldest.
        assert invoke([url + "new"], refreshed) == (expected, 1)
        assert not other.exists() and target.read_bytes() == png

    limited = root / "limited"
    with patch.object(media, "MAX_CACHE_ENTRIES", 2):
        for index in range(3):
            value = url + str(index)
            assert invoke([value], limited) == (expected, 1)
            os.utime(limited / name(value), ns=(index + 1, index + 1))
        assert sorted(item.name for item in limited.glob("*.img")) == sorted(name(url + str(i)) for i in (1, 2))
    byte_limited = root / "byte-limited"
    with patch.object(media, "MAX_CACHE_BYTES", len(png) * 2 - 1):
        assert invoke([url], byte_limited) == (expected, 1)
        assert invoke([url + "2"], byte_limited) == (expected, 1)
        files = list(byte_limited.glob("*.img"))
        assert len(files) == 1 and sum(item.stat().st_size for item in files) <= media.MAX_CACHE_BYTES
    with patch.object(media, "MAX_CACHE_BYTES", len(png) - 1):
        assert invoke([url], root / "too-small") == (expected, 1)
        assert list((root / "too-small").glob("*.img")) == []
    orphaned = root / "orphaned"; orphaned.mkdir(mode=0o700)
    orphan = orphaned / (".write-" + "0" * 24 + ".tmp")
    orphan.write_bytes(png); orphan.chmod(0o600); os.utime(orphan, ns=(1, 1))
    with patch.object(media, "MAX_CACHE_ENTRIES", 2), \
         patch.object(media, "MAX_CACHE_BYTES", len(png) * 2):
        assert invoke([url], orphaned) == (expected, 1)
        assert invoke([url + "2"], orphaned) == (expected, 1)
        files = [item for item in orphaned.iterdir() if item.name != ".lock"]
        assert len(files) == 2 and sum(item.stat().st_size for item in files) <= media.MAX_CACHE_BYTES
        assert not orphan.exists()

    # Cache contention and filesystem failure are optional-cache misses.
    with (cache / ".lock").open("r+b") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert invoke([url + "locked"], cache) == (expected, 1)
        assert not (cache / name(url + "locked")).exists()
    with patch.object(media.os, "replace", side_effect=OSError("synthetic cache failure")):
        assert invoke([url + "failed"], cache) == (expected, 1)
    assert not (cache / name(url + "failed")).exists()
    assert list(cache.glob(".write-*.tmp")) == []
    collision = root / "collision"; collision.mkdir(mode=0o700)
    original = collision / (".write-" + "0" * 24 + ".tmp")
    original.write_bytes(png); original.chmod(0o600)
    with patch.object(media.secrets, "token_hex", return_value="0" * 24):
        assert invoke([url], collision) == (expected, 1)
    assert original.exists() and original.read_bytes() == png
    assert not (collision / name(url)).exists()
    with patch.object(media.os, "read", side_effect=OSError("synthetic read failure")):
        assert invoke([url], cache) == (expected, 1)
    with patch.object(media.os, "open", side_effect=OSError("synthetic open failure")):
        assert invoke([url], cache) == (expected, 1)
    crowded = root / "crowded"; crowded.mkdir(mode=0o700)
    for index in range(3):
        (crowded / str(index)).touch()
    with patch.object(media, "MAX_CACHE_SCAN", 2):
        assert invoke([url], crowded) == (expected, 1)
    assert not (crowded / name(url)).exists()

    assert invoke([url], "none") == (expected, 1)
    assert invoke([url], "none") == (expected, 1)
    xdg, home = root / "xdg", root / "home"
    assert invoke([url], None, XDG_CACHE_HOME=str(xdg), HOME=str(home)) == (expected, 1)
    assert (xdg / "birc/images" / name(url)).read_bytes() == png
    assert invoke([url], None, HOME=str(home)) == (expected, 1)
    assert (home / ".cache/birc/images" / name(url)).read_bytes() == png
    local = root / "local.png"; local.write_bytes(png)
    local_cache = root / "local-cache"
    assert invoke(["--local", str(local)], local_cache,
                  fetched=AssertionError("local preview fetched")) == (expected, 0)
    assert not local_cache.exists()

print("media_image_cache=ok offline=hit safety=guarded bounds=fifo optional=best-effort")
