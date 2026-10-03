#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Optional profile channel lists use only synthetic profiles and launch fakes."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "src/launcher/keychain_birc.py"
spec = importlib.util.spec_from_file_location("keychain_channels", SOURCE)
assert spec is not None and spec.loader is not None
launcher = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = launcher
spec.loader.exec_module(launcher)


def main():
    with tempfile.TemporaryDirectory(prefix="birc-profile-channels-") as directory:
        root = Path(directory)
        path = root / "config.toml"
        base = '[profiles.test]\nhost="irc.example"\naccount="alice"\n'
        path.write_text(base)
        path.chmod(0o600)
        original = launcher.read_profile(path, "test")
        path.write_text(base + 'channels=["+#room", "#日本語"]\n')
        profile = launcher.read_profile(path, "test")
        assert profile.channels == ("+#room", "#日本語")
        assert profile.service == original.service and profile.account == original.account
        assert profile.tls and profile.port == 6697
        for value in (["#room key"], ["#bad,other"], ["server"], ["#room", "#room"],
                      ["#bad\nline"], "#room", [f"#c{i}" for i in range(15)]):
            path.write_text(base + "channels=" + json.dumps(value) + "\n")
            try:
                launcher.read_profile(path, "test")
            except launcher.Refusal:
                pass
            else:
                raise AssertionError("unsafe profile channels accepted")
        path.write_text(base + 'channels=[]\n')
        assert launcher.read_profile(path, "test").channels == ()
        for prefix in "#&+!":
            assert launcher.profile_channels([prefix + "a"]) == (prefix + "a",)
            try:
                launcher.profile_channels([prefix])
            except launcher.Refusal:
                pass
            else:
                raise AssertionError("bare profile channel prefix accepted")
        assert launcher.profile_channels(["#room:*.fi"]) == ("#room:*.fi",)
        long_name = "#" + "a" * 504
        assert launcher.profile_channels([long_name]) == (long_name,)
        try:
            launcher.profile_channels([long_name + "a"])
        except launcher.Refusal:
            pass
        else:
            raise AssertionError("overlong profile channel accepted")
        csv = ",".join("#" + str(i) + "a" * (504 - len(str(i))) for i in range(14))
        assert len(csv.encode()) == 7083 and launcher.channel_csv(csv) == csv
        assert launcher.channel_csv("") == ""
        for invalid in ("#a,", ",#a", "#a,,#b", "#a key", csv + ",#extra"):
            try:
                launcher.channel_csv(invalid)
            except launcher.Refusal:
                pass
            else:
                raise AssertionError("invalid explicit channel CSV accepted")
        # The launch primitive forwards exact comma text, unless explicitly overridden.
        class Child:
            def wait(self): return 0
            def poll(self): return 0
        with patch.object(launcher.subprocess, "Popen", return_value=Child()) as spawn, \
             patch.object(launcher, "auth_succeeded", return_value=False):
            assert launcher.launch("/owned/birc", profile, b"synthetic", [], "/fake/security", save=False) == 0
            argv = spawn.call_args.args[0]
            assert argv[argv.index("--channel") + 1] == "+#room,#日本語"
            assert "synthetic" not in argv
            assert launcher.launch("/owned/birc", profile, b"synthetic", ["--channel", "#override"],
                                   "/fake/security", save=False) == 0
            argv = spawn.call_args.args[0]
            assert argv.count("--channel") == 1 and argv[argv.index("--channel") + 1] == "#override"
    print("keychain_channels=ok")


if __name__ == "__main__":
    main()
