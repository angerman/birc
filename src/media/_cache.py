#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Shared private-file and media-cache IO. Callers own policy and messages.

Bend cannot own flock, dir_fd, fchmod, or exclusive staging. This module is
the one copy of those operations. It does not choose a permission mask:
every caller passes `mask` for the path class it is checking.

Mask meanings (do not unify them):
- 0o077 on a directory requires mode 0700 (image cache, cards subdirectory,
  profile directory). Group and other get nothing.
- 0o022 on a directory forbids group/other write and permits read and
  traverse (preferences directory only).
- 0o077 on a file forbids every group/other bit (preference files).
- 0o022 on a file forbids group/other write and permits read (nonsecret
  profile TOML).
- 0 on a cache payload skips the mode test; the reader then fchmod 0600.
"""

import fcntl
import hashlib
import os
import signal
import socket
import stat
import time
from urllib.parse import urljoin

HEX = "0123456789abcdef"
_STAGING_PREFIX = ".write-"
_STAGING_MARK = ".tmp"


def trusted(info, *, kind, mask, nlink):
    """True when `info` matches an explicit path class.

    `kind` is "dir", "file", or "any". "any" is the profile-directory check,
    which refuses foreign ownership and group/other bits but does not require
    S_ISDIR. `mask` is required: there is no default. `nlink` requires a
    single link; directories and profile files pass False.
    """
    if kind == "dir":
        ok_kind = stat.S_ISDIR(info.st_mode)
    elif kind == "file":
        ok_kind = stat.S_ISREG(info.st_mode)
    elif kind == "any":
        ok_kind = True
    else:
        ok_kind = False
    if not ok_kind or info.st_uid != os.getuid() or info.st_mode & mask:
        return False
    if nlink and info.st_nlink != 1:
        return False
    return True


def identity(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


def payload_name(url, suffix):
    # Names never store the requested URL. Width is 64 hex chars plus suffix.
    return hashlib.sha256(url.encode("utf-8")).hexdigest() + suffix


def is_payload_name(name, suffix):
    width = 64 + len(suffix)
    return (len(name) == width and name.endswith(suffix)
            and all(char in HEX for char in name[:64]))


def is_staging_name(name):
    """Cache staging files only. Preferences use a different prefix."""
    mark = len(_STAGING_PREFIX)
    return (len(name) == 35 and name.startswith(_STAGING_PREFIX)
            and name.endswith(_STAGING_MARK)
            and all(char in HEX for char in name[mark:-len(_STAGING_MARK)]))


def staging_name(token, prefix=_STAGING_PREFIX):
    """`token` is the caller's secrets.token_hex so tests can patch that module."""
    return prefix + token(12) + _STAGING_MARK


def usage_scan(dirfd, suffix, *, scan_limit, owned):
    """(count, bytes) of payloads and orphaned staging files, or None."""
    count = total = 0
    try:
        with os.scandir(dirfd) as scan:
            for index, entry in enumerate(scan):
                if index >= scan_limit:
                    return None
                name = entry.name
                if not is_payload_name(name, suffix) and not is_staging_name(name):
                    continue
                try:
                    info = entry.stat(follow_symlinks=False)
                    owned(info)
                except OSError:
                    return None
                count += 1
                total += info.st_size
    except OSError:
        return None
    return count, total


def acquire_lock(dirfd, name, *, owned):
    """Exclusive non-blocking lock. Closes the fd if admission fails."""
    fd = os.open(name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK
                 | os.O_CLOEXEC, 0o600, dir_fd=dirfd)
    try:
        owned(os.fstat(fd))
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BaseException:
        os.close(fd)
        raise
    return fd


def open_regular(path, *, nofollow, cloexec=True, dir_fd=None):
    """Open a path and fstat it. The caller closes the fd and applies bounds.

    `nofollow` is required. Image and card --local paths pass False: those
    follow the caller's final symlink, and tests pin that. Cache names,
    preferences, and profiles pass True. Keychain's profile read also omits
    O_CLOEXEC; pass cloexec=False there. This helper does not decide size,
    ownership, or mode — those differ by caller.
    """
    flags = os.O_RDONLY | os.O_NONBLOCK
    if cloexec:
        flags |= os.O_CLOEXEC
    if nofollow:
        flags |= os.O_NOFOLLOW
    kwargs = {}
    if dir_fd is not None:
        kwargs["dir_fd"] = dir_fd
    fd = os.open(path, flags, **kwargs)
    try:
        return fd, os.fstat(fd)
    except BaseException:
        os.close(fd)
        raise


def read_exact(fd, size, *, chunk=65536):
    data = bytearray()
    remaining = size
    while remaining:
        piece = os.read(fd, min(chunk, remaining))
        if not piece:
            break
        data.extend(piece)
        remaining -= len(piece)
    return bytes(data)


def read_regular(path, limit, *, nofollow, reject_bound, reject_short):
    """Bounded regular-file body. Open errors propagate as OSError.

    Reads one byte past the fstat size so a growth during the read is
    refused. Cache reads use read_exact plus an identity recheck instead.
    """
    fd, metadata = open_regular(path, nofollow=nofollow)
    try:
        if not stat.S_ISREG(metadata.st_mode) or not 0 < metadata.st_size <= limit:
            raise reject_bound()
        data = bytearray()
        while len(data) <= metadata.st_size:
            chunk = os.read(fd, min(65536, metadata.st_size + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        if len(data) != metadata.st_size:
            raise reject_short()
        return bytes(data)
    finally:
        os.close(fd)


def read_cached(dirfd, name, limit, *, owned, identity_of):
    """Owned cache body, or None when the entry is unsafe or unstable."""
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                 dir_fd=dirfd)
    try:
        info = os.fstat(fd)
        owned(info)
        if not 0 < info.st_size <= limit:
            return None
        os.fchmod(fd, 0o600)
        info = os.fstat(fd)
        data = read_exact(fd, info.st_size)
        if len(data) != info.st_size:
            return None
        current = os.stat(name, dir_fd=dirfd, follow_symlinks=False)
        if (identity_of(os.fstat(fd)) != identity_of(info)
                or identity_of(current) != identity_of(info)):
            return None
        return data
    finally:
        os.close(fd)


def commit_staged(dirfd, target, data, previous, identity_of, *, token, prefix,
                  changed, short_write, before_replace=None, fsync_file=False,
                  fsync_dir=False, strict_unlink=False):
    """Exclusive staging write, then os.replace onto `target`.

    Never unlinks a staging file whose exclusive create failed. `temporary_fd`
    stays None when os.open raises, so the finally clause leaves that name
    alone. `temporary = None` runs only after os.replace succeeds.
    """
    temporary = staging_name(token, prefix)
    temporary_fd = None
    try:
        temporary_fd = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
            0o600, dir_fd=dirfd)
        os.fchmod(temporary_fd, 0o600)
        view = memoryview(data)
        while view:
            count = os.write(temporary_fd, view)
            if count <= 0:
                raise short_write()
            view = view[count:]
        if fsync_file:
            os.fsync(temporary_fd)
        if before_replace is not None:
            before_replace()
        try:
            current = os.stat(target, dir_fd=dirfd, follow_symlinks=False)
        except FileNotFoundError:
            current = None
        if ((previous is None) != (current is None)
                or (current is not None
                    and identity_of(current) != identity_of(previous))):
            raise changed()
        os.replace(temporary, target, src_dir_fd=dirfd, dst_dir_fd=dirfd)
        temporary = None
        if fsync_dir:
            os.fsync(dirfd)
    finally:
        created = temporary_fd
        unlink_error = None
        if temporary is not None and created is not None:
            try:
                os.unlink(temporary, dir_fd=dirfd)
            except FileNotFoundError:
                pass
            except OSError as error:
                if strict_unlink:
                    unlink_error = error
        if created is not None:
            try:
                os.close(created)
            except OSError:
                pass
        if unlink_error is not None:
            raise unlink_error


def replace_fifo(dirfd, target, data, *, suffix, scan_limit, max_entries,
                 max_bytes, other_count, other_bytes, owned, identity_of,
                 scan_error, changed, short_write, token, prefix=_STAGING_PREFIX):
    """Evict this directory's oldest entries, then commit `data`."""
    try:
        previous = os.stat(target, dir_fd=dirfd, follow_symlinks=False)
        owned(previous)
    except FileNotFoundError:
        previous = None
    entries = []
    with os.scandir(dirfd) as scan:
        for index, entry in enumerate(scan):
            if index >= scan_limit:
                raise scan_error()
            name = entry.name
            if not is_payload_name(name, suffix) and not is_staging_name(name):
                continue
            info = entry.stat(follow_symlinks=False)
            owned(info)
            if name == target:
                if previous is None or identity_of(info) != identity_of(previous):
                    raise changed()
                continue
            entries.append((info.st_mtime_ns, name, info))
    entries.sort(key=lambda item: (item[0], item[1]))
    total = sum(item[2].st_size for item in entries)
    while entries and (other_count + len(entries) + 1 > max_entries
                       or other_bytes + total + len(data) > max_bytes):
        _, name, info = entries.pop(0)
        if identity_of(os.stat(name, dir_fd=dirfd, follow_symlinks=False)) != identity_of(info):
            raise changed()
        os.unlink(name, dir_fd=dirfd)
        total -= info.st_size
    commit_staged(dirfd, target, data, previous, identity_of, token=token,
                  prefix=prefix, changed=changed, short_write=short_write)


def resolve_public(scheme, host, port, path, resolver, accept, reject):
    addresses = resolver(host, port, type=socket.SOCK_STREAM)
    if not addresses or any(not accept(item[4][0]) for item in addresses):
        raise reject
    return scheme, host, port, path, addresses


def bounded_fetch(url, deadline, *, resolve, connection, max_bytes, redirects,
                  headers, fail, timeout_msg, redirect_msg, downgrade,
                  downgrade_msg, status_msg, encoding_msg, large_msg,
                  incomplete_msg, content_ok=None, type_msg=None,
                  return_final=False):
    """Guarded GET with a caller-supplied redirect and body policy."""
    for redirect in range(redirects + 1):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise fail(timeout_msg)
        scheme, host, port, path, addresses = resolve(url)
        client = connection(scheme, host, port, addresses, remaining)
        try:
            client.request("GET", path, headers=headers)
            response = client.getresponse()
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if not location or redirect == redirects:
                    raise fail(redirect_msg)
                target = urljoin(url, location)
                if downgrade(scheme, target):
                    raise fail(downgrade_msg)
                url = target
                continue
            if response.status != 200:
                raise fail(status_msg)
            if response.getheader("Content-Encoding", "identity").lower() != "identity":
                raise fail(encoding_msg)
            if content_ok is not None:
                if not content_ok(response.getheader("Content-Type", "")):
                    raise fail(type_msg)
            length = response.getheader("Content-Length")
            if length is not None and (not length.isdecimal() or int(length) > max_bytes):
                raise fail(large_msg)
            data = bytearray()
            while len(data) <= max_bytes:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise fail(timeout_msg)
                if client.sock is not None:
                    client.sock.settimeout(remaining)
                chunk = response.read(min(65536, max_bytes + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
            if len(data) > max_bytes:
                raise fail(large_msg)
            if length is not None and len(data) != int(length):
                raise fail(incomplete_msg)
            body = bytes(data)
            return (body, url) if return_final else body
        finally:
            client.close()
    raise fail(redirect_msg)


def arm_deadline(seconds):
    """SIGALRM with the default disposition. Callers keep their own exits."""
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.alarm(seconds)
