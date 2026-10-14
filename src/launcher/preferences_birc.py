#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Bounded private preferences IO. Bend owns settings and channel intent."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import tomllib


MAX_CONFIG = 65536
MAX_WIRE = 40960
MAX_MUTES = 64
MAX_CHANNELS = 14
MAX_SERVERS = 16
BOOL_KEYS = ("joins", "ts", "motd", "history", "autoreconn", "bell", "images", "nicks")
SETTING_KEYS = {*BOOL_KEYS, "hist_cap", "mutes"}
THEME_NAMES = ("dark", "light", "mono")


class Refusal(Exception):
    """Report only a numeric stage code; no paths or user values."""

    def __init__(self, code=1):
        self.code = code


def text(value, bound, *, channel=False):
    if (not isinstance(value, str) or not value or len(value.encode("utf-8")) > bound
            or any(ord(c) < 33 or ord(c) == 127 for c in value)):
        raise Refusal(2)
    if channel and (len(value) <= 1 or value[0] not in "#&+!" or "," in value):
        raise Refusal(2)
    return value


def endpoint(host, port):
    text(host, 254)
    canonical = host[:-1] if host.endswith(".") else host
    if (not canonical or len(canonical) > 253 or not re.fullmatch(r"[A-Za-z0-9.-]+", host)
            or any(not part or len(part) > 63 for part in canonical.split("."))
            or type(port) is not int or not 1 <= port <= 65535):
        raise Refusal(2)


def scope(host, port):
    # Offline demo/replay owns global settings only, never a fabricated server.
    if host == "" and type(port) is int and port == 0:
        return False
    endpoint(host, port)
    return True


def strings(value, cap, bound, *, channel=False):
    if not isinstance(value, list) or len(value) > cap:
        raise Refusal(2)
    for item in value:
        text(item, bound, channel=channel)
    if len(set(value)) != len(value):
        raise Refusal(2)
    return value


def settings(value):
    if (not isinstance(value, dict)
            or (set(value) != SETTING_KEYS and set(value) != SETTING_KEYS | {"theme"})
            or any(type(value[key]) is not bool for key in BOOL_KEYS)
            or type(value["hist_cap"]) is not int or not 0 <= value["hist_cap"] <= 4294967295
            or ("theme" in value and value["theme"] not in THEME_NAMES)):
        raise Refusal(2)
    strings(value["mutes"], MAX_MUTES, 512)
    return value


def document(value):
    if (not isinstance(value, dict) or set(value) != {"version", "settings", "servers"}
            or type(value["version"]) is not int or value["version"] != 1
            or not isinstance(value["servers"], list) or len(value["servers"]) > MAX_SERVERS):
        raise Refusal(2)
    settings(value["settings"])
    seen = set()
    for server in value["servers"]:
        if not isinstance(server, dict) or set(server) != {"host", "port", "channels"}:
            raise Refusal(2)
        endpoint(server["host"], server["port"])
        strings(server["channels"], MAX_CHANNELS, 505, channel=True)
        key = server["host"], server["port"]
        if key in seen:
            raise Refusal(2)
        seen.add(key)
    return value


def parse_wire(body):
    if (not isinstance(body, str) or len(body.encode("utf-8")) > MAX_WIRE
            or not body.endswith("\n")):
        raise Refusal(2)
    lines = body[:-1].split("\n")
    if len(lines) < 2 or lines[0] != "BIRC_PREFS1":
        raise Refusal(2)
    fields = lines[1].split("\t")
    if (len(fields) not in (9, 10) or fields[0] != "settings"
            or any(fields[i] not in {"0", "1"} for i in (1, 2, 3, 4, 6, 7, 8))
            or (len(fields) == 10 and fields[9] not in {"0", "1"})
            or not re.fullmatch(r"[0-9]{1,10}", fields[5])):
        raise Refusal(2)
    value = dict(zip(("joins", "ts", "motd", "history", "autoreconn", "bell", "images"),
                     (fields[i] == "1" for i in (1, 2, 3, 4, 6, 7, 8))))
    value.update(hist_cap=int(fields[5]), mutes=[],
                 nicks=True if len(fields) == 9 else fields[9] == "1")
    channels = []
    theme = None
    for line in lines[2:]:
        parts = line.split("\t")
        if len(parts) != 2 or parts[0] not in {"mute", "channel", "theme"}:
            raise Refusal(2)
        if parts[0] == "mute":
            value["mutes"].append(parts[1])
        elif parts[0] == "channel":
            channels.append(parts[1])
        elif theme is not None or parts[1] not in THEME_NAMES:
            raise Refusal(2)
        else:
            theme = parts[1]
    if theme is not None:
        value["theme"] = theme
    settings(value)
    strings(channels, MAX_CHANNELS, 505, channel=True)
    return value, channels


def wire(value, channels, known=True):
    values = [str(int(value[key])) for key in ("joins", "ts", "motd", "history")]
    values.append(str(value["hist_cap"]))
    values.extend(str(int(value[key])) for key in ("autoreconn", "bell", "images", "nicks"))
    theme = value.get("theme", "dark")
    return ("BIRC_PREFS1\nsettings\t" + "\t".join(values) + "\n"
            + ("" if theme == "dark" else "theme\t" + theme + "\n")
            + "".join("mute\t" + item + "\n" for item in value["mutes"])
            + "".join("channel\t" + item + "\n" for item in channels)
            + ("" if known else "scope\t0\n"))


def encode(value):
    stg = value["settings"]
    lines = ["version = 1", "", "[settings]"]
    for key in ("joins", "ts", "motd", "history", "hist_cap", "autoreconn", "bell", "images", "nicks"):
        item = stg[key]
        lines.append(f"{key} = {str(item).lower()}")
    if stg.get("theme", "dark") != "dark":
        lines.append("theme = " + json.dumps(stg["theme"], ensure_ascii=False))
    # JSON strings/arrays use the TOML basic-string subset and preserve Unicode.
    lines.append("mutes = " + json.dumps(stg["mutes"], ensure_ascii=False))
    for server in value["servers"]:
        lines.extend(("", "[[servers]]", "host = " + json.dumps(server["host"]),
                      "port = " + str(server["port"]),
                      "channels = " + json.dumps(server["channels"], ensure_ascii=False)))
    if not value["servers"]:
        # A root array is needed only before [settings]; reorder that case.
        lines.insert(1, "servers = []")
    data = ("\n".join(lines) + "\n").encode("utf-8")
    if len(data) > MAX_CONFIG:
        raise Refusal(2)
    return data


def owned(info, *, directory=False):
    kind = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
    forbidden = 0o022 if directory else 0o077
    if (not kind or info.st_uid != os.getuid() or info.st_mode & forbidden
            or (not directory and info.st_nlink != 1)):
        raise Refusal(3)


def identity(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def parent(path, *, create=False):
    if create:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        owned(os.fstat(fd), directory=True)
        if identity(os.stat(path.parent, follow_symlinks=False))[:2] != identity(os.fstat(fd))[:2]:
            raise Refusal(3)
        return fd
    except BaseException:
        os.close(fd)
        raise


def verify_parent(dirfd, path):
    owned(os.fstat(dirfd), directory=True)
    if identity(os.stat(path.parent, follow_symlinks=False))[:2] != identity(os.fstat(dirfd))[:2]:
        raise Refusal(4)


def snapshot(dirfd, name):
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dirfd)
    except FileNotFoundError:
        return None, None
    try:
        info = os.fstat(fd)
        owned(info)
        if info.st_size > MAX_CONFIG:
            raise Refusal(2)
        chunks = []
        remaining = info.st_size
        while remaining:
            chunk = os.read(fd, min(remaining, 4096))
            if not chunk:
                raise Refusal(4)
            chunks.append(chunk)
            remaining -= len(chunk)
        if identity(os.fstat(fd)) != identity(info):
            raise Refusal(4)
        current = os.stat(name, dir_fd=dirfd, follow_symlinks=False)
        if identity(current) != identity(info):
            raise Refusal(4)
        try:
            raw = tomllib.loads(b"".join(chunks).decode("utf-8"))
            if isinstance(raw.get("settings"), dict):
                # Files written before nicks existed keep working; the schema
                # stays strict about every other key and value.
                raw["settings"].setdefault("nicks", True)
            value = document(raw)
        except (ValueError, UnicodeError):
            raise Refusal(2) from None
        return value, info
    finally:
        os.close(fd)


def read(path, host, port):
    scope(host, port)
    try:
        try:
            dirfd = parent(path)
        except FileNotFoundError:
            return ""
        try:
            value, _ = snapshot(dirfd, path.name)
            verify_parent(dirfd, path)
            if value is None:
                return ""
            server = next((row for row in value["servers"]
                           if (row["host"], row["port"]) == (host, port)), None)
            return wire(value["settings"], [] if server is None else server["channels"], server is not None)
        finally:
            os.close(dirfd)
    except OSError:
        raise Refusal(3) from None


def write(path, host, port, body):
    server_scope = scope(host, port)
    stg, channels = parse_wire(body)
    if not server_scope and channels:
        raise Refusal(2)
    dirfd = lockfd = tempfd = -1
    temporary = None
    try:
        dirfd = parent(path, create=True)
        lockfd = os.open(path.name + ".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW
                         | os.O_NONBLOCK | os.O_CLOEXEC, 0o600, dir_fd=dirfd)
        owned(os.fstat(lockfd))
        os.fchmod(lockfd, 0o600)
        # Another process cannot leave this helper parked beyond its IO deadline.
        fcntl.flock(lockfd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        value, previous = snapshot(dirfd, path.name)
        rows = [] if value is None else value["servers"]
        if server_scope:
            target = next((row for row in rows if (row["host"], row["port"]) == (host, port)), None)
            if target is None:
                if len(rows) == MAX_SERVERS:
                    raise Refusal(2)
                rows.append({"host": host, "port": port, "channels": channels})
            else:
                target["channels"] = channels
        data = encode(document({"version": 1, "settings": stg, "servers": rows}))
        temporary = ".preferences-" + secrets.token_hex(12) + ".tmp"
        tempfd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
                         | os.O_CLOEXEC, 0o600, dir_fd=dirfd)
        os.fchmod(tempfd, 0o600)
        view = memoryview(data)
        while view:
            written = os.write(tempfd, view)
            if written <= 0:
                raise Refusal(4)
            view = view[written:]
        os.fsync(tempfd)
        # Recheck both the parent path and final name against the descriptor snapshot.
        verify_parent(dirfd, path)
        try:
            current = os.stat(path.name, dir_fd=dirfd, follow_symlinks=False)
        except FileNotFoundError:
            current = None
        if ((previous is None) != (current is None)
                or (current is not None and identity(current) != identity(previous))):
            raise Refusal(4)
        os.replace(temporary, path.name, src_dir_fd=dirfd, dst_dir_fd=dirfd)
        temporary = None
        os.fsync(dirfd)
    except OSError:
        raise Refusal(3) from None
    finally:
        if tempfd >= 0:
            os.close(tempfd)
        if temporary is not None and dirfd >= 0:
            try:
                os.unlink(temporary, dir_fd=dirfd)
            except FileNotFoundError:
                pass
        if lockfd >= 0:
            os.close(lockfd)
        if dirfd >= 0:
            os.close(dirfd)


def resolve_path():
    explicit = os.environ.get("BIRC_PREFERENCES")
    if explicit is not None:
        return None if explicit in {"", "none"} else Path(explicit)
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "birc/preferences.toml"


def main():
    try:
        if len(sys.argv) != 4 or sys.argv[1] not in {"read", "write"}:
            raise Refusal(2)
        host, port = sys.argv[2], int(sys.argv[3])
        scope(host, port)
        path = resolve_path()
        if path is None:
            return 0
        if sys.argv[1] == "read":
            sys.stdout.write(read(path, host, port))
        else:
            raw = sys.stdin.buffer.read(MAX_WIRE + 1)
            if len(raw) > MAX_WIRE:
                raise Refusal(2)
            write(path, host, port, raw.decode("utf-8"))
        return 0
    except (ValueError, UnicodeError):
        return 2
    except Refusal as error:
        return error.code
    except OSError:
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
