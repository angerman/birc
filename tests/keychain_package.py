#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed launcher provenance and pre-Keychain refusal controls.

This guard never calls security, fetches a password, or connects to IRC.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def run(command, env):
    return subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


package = Path(sys.argv[1]).resolve()
launcher = package / "bin/keychain-birc"
script = package / "libexec/keychain_birc.py"
source = Path(__file__).resolve().parents[1] / "src/launcher/keychain_birc.py"
assert launcher.is_file() and os.access(launcher, os.X_OK), "launcher is not installed"
assert script.read_bytes() == source.read_bytes(), "installed launcher source is stale"
wrapper = launcher.read_text()
assert str(package / "bin/birc") in wrapper, "installed client default is not absolute"
assert str(script) in wrapper, "launcher does not use installed source"
python = re.findall(r"/nix/store/[^\s'\"{}]+/bin/python3", wrapper)
assert len(set(python)) == 1 and Path(python[0]).is_file(), "launcher Python is not provisioned"

with tempfile.TemporaryDirectory(prefix="birc-keychain-package-") as temporary:
    root = Path(temporary)
    env = {"HOME": str(root), "XDG_CONFIG_HOME": str(root), "PATH": "", "LANG": "C"}
    help_result = run([str(launcher), "--help"], env)
    assert help_result.returncode == 0, "installed launcher help failed"
    assert b"--profile" in help_result.stdout and b"--allow-insecure-auth" in help_result.stdout
    marker = "synthetic-secret-not-for-arguments"
    bad_args = run([str(launcher), "--profile", "test", "--sasl-pass", marker], env)
    assert bad_args.returncode != 0 and marker.encode() not in bad_args.stdout + bad_args.stderr
    profile = root / "config.toml"
    profile.write_text('[profiles.test]\nhost="irc.invalid"\naccount="test"\ntls=false\n')
    profile.chmod(0o600)
    unsafe = run([str(launcher), "--profile", "test", "--config", str(profile)], env)
    assert unsafe.returncode != 0, "unsafe endpoint accepted without opt-in"
    # Linux refuses the macOS-only operation even earlier; Darwin refuses
    # transport before any Keychain call. Neither needs an ambient PATH.
    expected = b"trusted loopback relay" if sys.platform == "darwin" else b"macOS is required"
    assert expected in unsafe.stderr, "launcher did not fail before Keychain access"
print("keychain_package=ok")
