#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Checked-open evidence probe and retained-fd scan for disk history search.

Bend owns admission; this helper only reports OS evidence (lstat plus an
O_NOFOLLOW open plus fstat) and, for `scan`, exactly the fstat snapshot
bytes read via that one checked descriptor. Prints one strict ``SE`` bit
line (regular, owned, symlink, private, missing); `scan` appends the
snapshot bytes verbatim so a scan never reopens by pathname.
Post-snapshot appends are never read (cutoff); early EOF (shrink) exits 5
with partial bytes discarded. Refusals exit 0 with zeroed bits and no
content; oversize files exit 3 and undecodable files exit 4 so Bend fails
closed with a fixed diagnostic. Unexpected errors exit nonzero and Bend
refuses closed. No paths ever cross the seam.
"""
from __future__ import annotations

import errno
import os
import stat
import sys

SCAN_MAX = 8 * 1024 * 1024


def evidence_bits(info) -> tuple:
    """Evidence bits from an fstat result (never a pathname stat)."""
    regular = 1 if stat.S_ISREG(info.st_mode) else 0
    owned = 1 if info.st_uid == os.geteuid() else 0
    private = 1 if (info.st_mode & 0o777) == 0o600 else 0
    return (regular, owned, 0, private, 0)


def checked_open(path: str):
    """O_NOFOLLOW open a non-symlink path.

    Returns (fd, None) with a caller-owned descriptor, or (None, bits) for
    refused/missing paths, or (None, None) on unexpected errors.
    """
    try:
        lst = os.lstat(path)
    except FileNotFoundError:
        return (None, (0, 0, 0, 0, 1))
    except OSError:
        return (None, None)
    if stat.S_ISLNK(lst.st_mode):
        return (None, (0, 0, 1, 0, 0))
    try:
        # O_NONBLOCK so a fifo path cannot park the open; fstat refuses
        # non-regular files before any read. Regular reads never EAGAIN.
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            return (None, (0, 0, 1, 0, 0))
        if exc.errno == errno.ENOENT:
            return (None, (0, 0, 0, 0, 1))
        return (None, None)
    return (fd, None)


def probe(path: str):
    """Return (regular, owned, symlink, private, missing) or None on error."""
    fd, refused = checked_open(path)
    if fd is None:
        return refused
    try:
        info = os.fstat(fd)
    except OSError:
        return None
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
    return evidence_bits(info)


def scan_fd(fd: int, bits, snapshot: int):
    """Read EXACTLY snapshot bytes via the checked fd (never closes).

    Returns (bits, content) on exact reads; ("oversize", None) when the
    snapshot is past SCAN_MAX (refused before reading); ("shrink", None)
    on early EOF (partial bytes discarded); ("decode", None) for
    non-UTF-8 bytes; (None, None) on read errors. Post-snapshot
    appends are never read. The caller owns the fd on every path.
    """
    if snapshot > SCAN_MAX:
        return ("oversize", None)
    chunks = []
    remaining = snapshot
    while remaining > 0:
        try:
            chunk = os.read(fd, min(65536, remaining))
        except OSError:
            return (None, None)
        if not chunk:
            return ("shrink", None)
        chunks.append(chunk)
        remaining -= len(chunk)
    content = b"".join(chunks)
    try:
        content.decode("utf-8")
    except UnicodeDecodeError:
        return ("decode", None)
    return (bits, content)


def scan(path: str):
    """Return (bits, content) read via one checked descriptor.

    Returns ((bits), b"") for refused/missing paths (exit 0, bits only),
    ("oversize", None) past SCAN_MAX, ("shrink", None) on early EOF
    against the fstat snapshot, ("decode", None) for non-UTF-8 bytes,
    and (None, None) on unexpected errors. The descriptor closes on
    every path.
    """
    fd, refused = checked_open(path)
    if fd is None:
        if refused is None:
            return (None, None)
        return (refused, b"")
    try:
        try:
            info = os.fstat(fd)
        except OSError:
            return (None, None)
        bits = evidence_bits(info)
        if not (bits[0] and bits[1] and bits[3]):
            return (bits, b"")
        return scan_fd(fd, bits, info.st_size)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass


def write_scan(bits, content) -> None:
    out = os.fdopen(1, "wb", closefd=False)
    out.write(("SE%d%d%d%d%d\n" % bits).encode("ascii"))
    out.write(content)
    out.flush()


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in ("probe", "scan") or not argv[2]:
        return 2
    if argv[1] == "probe":
        evidence = probe(argv[2])
        if evidence is None:
            return 1
        sys.stdout.write("SE%d%d%d%d%d\n" % evidence)
        return 0
    bits, content = scan(argv[2])
    if bits is None:
        return 1
    if bits == "oversize":
        return 3
    if bits == "decode":
        return 4
    if bits == "shrink":
        return 5
    if content:
        write_scan(bits, content)
    else:
        sys.stdout.write("SE%d%d%d%d%d\n" % bits)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
