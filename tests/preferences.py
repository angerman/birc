#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Private preferences controls. All paths and configuration are synthetic."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import sys
import tempfile
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "src/launcher/preferences_birc.py"
spec = importlib.util.spec_from_file_location("preferences_birc", SOURCE)
assert spec is not None and spec.loader is not None
prefs = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = prefs
spec.loader.exec_module(prefs)

WIRE = ("BIRC_PREFS1\n"
        "settings\t0\t1\t0\t1\t200\t1\t0\t0\t1\n"
        "mute\talice*#room@irc.example\n"
        "channel\t+#room\nchannel\t#日本語\n")


def rejected(action) -> None:
    try:
        action()
    except prefs.Refusal:
        return
    raise AssertionError("unsafe input accepted")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="birc-preferences-") as directory:
        root = Path(directory)
        path = root / "preferences.toml"
        # (+) Missing optional configuration is success, not an empty overwrite.
        assert prefs.read(path, "irc.example", 6697) == ""
        assert not path.exists()
        prefs.write(path, "irc.example", 6697, WIRE)
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
        assert prefs.read(path, "irc.example", 6697) == WIRE
        # (+) Global preferences apply at another endpoint without copying channels.
        empty_channels = WIRE[:WIRE.index("channel\t")]
        assert prefs.read(path, "other.example", 6697) == empty_channels + "scope\t0\n"
        other = empty_channels + "channel\t#other\n"
        prefs.write(path, "other.example", 6697, other)
        assert prefs.read(path, "irc.example", 6697) == WIRE
        assert prefs.read(path, "other.example", 6697) == other
        # (+) Root-dot spelling and explicit port remain distinct scopes.
        assert prefs.read(path, "irc.example.", 6697) == empty_channels + "scope\t0\n"
        assert prefs.read(path, "irc.example", 6667) == empty_channels + "scope\t0\n"
        # (-) Malformed, future, unknown, or secret fields are never overwritten.
        valid = path.read_bytes()
        for text in ("version = 2\n", "version = 1\npassword = 'secret'\n",
                     "version = 1\n[settings]\nunknown = true\n", "invalid = [\n",
                     "version = 1\n[settings]\nbell = 'true'\n",
                     "version = 1\n[[servers]]\nhost = 'irc.example'\nport = 0\nchannels = []\n"):
            path.write_text(text)
            path.chmod(0o600)
            rejected(lambda: prefs.read(path, "irc.example", 6697))
            rejected(lambda: prefs.write(path, "irc.example", 6697, WIRE))
            assert path.read_text() == text
        path.write_bytes(valid)
        path.chmod(0o600)
        for body in (WIRE.replace("\t200\t", "\t4294967296\t"),
                     WIRE.replace("\t0\t1\t0\t", "\t2\t1\t0\t", 1),
                     WIRE + "password\tsecret\n", WIRE + "channel\t#room key\n",
                     WIRE + "channel\tserver\n", WIRE + "channel\t#bad,comma\n",
                     WIRE + "mute\tbad\x00rule\n", WIRE + "channel\t+#room\n",
                     WIRE + "\n", WIRE[:-1], WIRE.replace("BIRC_PREFS1", "BIRC_PREFS2")):
            rejected(lambda: prefs.write(path, "irc.example", 6697, body))
            assert path.read_bytes() == valid
        # (-) Size and list caps reject instead of truncating.
        path.write_bytes(b" " * (prefs.MAX_CONFIG + 1))
        rejected(lambda: prefs.read(path, "irc.example", 6697))
        path.write_bytes(valid)
        path.chmod(0o600)
        rejected(lambda: prefs.write(path, "irc.example", 6697,
                                    empty_channels + "".join(f"channel\t#c{i}\n" for i in range(16))))
        # (-) Symlink, directory, FIFO, foreign-owner, and writable file protections.
        link = root / "link.toml"
        link.symlink_to(path)
        before = path.read_bytes()
        rejected(lambda: prefs.read(link, "irc.example", 6697))
        rejected(lambda: prefs.write(link, "irc.example", 6697, WIRE))
        rejected(lambda: prefs.read(root, "irc.example", 6697))
        rejected(lambda: prefs.write(root, "irc.example", 6697, WIRE))
        fifo = root / "fifo.toml"
        os.mkfifo(fifo)
        rejected(lambda: prefs.read(fifo, "irc.example", 6697))
        rejected(lambda: prefs.write(fifo, "irc.example", 6697, WIRE))
        with patch.object(prefs.os, "getuid", return_value=os.getuid() + 1):
            rejected(lambda: prefs.read(path, "irc.example", 6697))
            rejected(lambda: prefs.write(path, "irc.example", 6697, WIRE))
        path.chmod(0o666)
        rejected(lambda: prefs.read(path, "irc.example", 6697))
        rejected(lambda: prefs.write(path, "irc.example", 6697, WIRE))
        path.chmod(0o600)
        assert path.read_bytes() == before
        path.chmod(0o644)
        rejected(lambda: prefs.read(path, "irc.example", 6697))
        rejected(lambda: prefs.write(path, "irc.example", 6697, WIRE))
        path.chmod(0o600)
        # (-) Failed atomic replacement preserves the original, cleans its temporary.
        with patch.object(prefs.os, "replace", side_effect=OSError("private path")):
            rejected(lambda: prefs.write(path, "irc.example", 6697, WIRE.replace("\t200\t", "\t300\t")))
        assert path.read_bytes() == before
        assert not list(root.glob(".preferences-*.tmp"))
        # (-) A final-name change after the read must not be overwritten.
        original_snapshot = prefs.snapshot
        def changed_snapshot(dirfd, name):
            value, info = original_snapshot(dirfd, name)
            path.write_text("version = 99\n")
            return value, info
        with patch.object(prefs, "snapshot", side_effect=changed_snapshot):
            rejected(lambda: prefs.write(path, "irc.example", 6697, WIRE))
        assert path.read_text() == "version = 99\n"
        assert not list(root.glob(".preferences-*.tmp"))
        path.write_bytes(before)
        path.chmod(0o600)
        # (-) Unsafe or symlink parent directories are refused too.
        bad_parent = root / "unsafe"
        bad_parent.mkdir(mode=0o777)
        bad_parent.chmod(0o777)
        rejected(lambda: prefs.write(bad_parent / "preferences.toml", "irc.example", 6697, WIRE))
        parent_link = root / "parent-link"
        parent_link.symlink_to(root, target_is_directory=True)
        rejected(lambda: prefs.write(parent_link / "preferences.toml", "irc.example", 6697, WIRE))
        # (+) Product writes own 0600 permissions even with a restrictive umask.
        previous_umask = os.umask(0o777)
        try:
            prefs.write(path, "irc.example", 6697, WIRE)
        finally:
            os.umask(previous_umask)
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
        # (+/-) Literal override, disabled persistence, and XDG defaults.
        with patch.dict(os.environ, {"BIRC_PREFERENCES": "none"}, clear=True):
            assert prefs.resolve_path() is None
        with patch.dict(os.environ, {"BIRC_PREFERENCES": str(path)}, clear=True):
            assert prefs.resolve_path() == path
        with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(root)}, clear=True):
            assert prefs.resolve_path() == root / "birc/preferences.toml"
        with patch.dict(os.environ, {"BIRC_PREFERENCES": ""}, clear=True):
            assert prefs.resolve_path() is None
    print("preferences=ok")


if __name__ == "__main__":
    main()
