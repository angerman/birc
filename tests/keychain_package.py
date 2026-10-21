#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed native launcher provenance and pre-Keychain refusal controls.

This guard never calls security, fetches a password, or connects to IRC.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def run(command, env):
    return subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


package = Path(sys.argv[1]).resolve()
launcher = package / "bin/keychain-birc"
assert launcher.is_file() and os.access(launcher, os.X_OK), "launcher is not installed"
assert not (package / "libexec/keychain_birc.py").exists(), "installed launcher still ships Python"
assert not (package / "libexec/_cache.py").exists(), "installed launcher still ships Python cache helper"
wrapper = launcher.read_text(errors="replace")
assert "python3" not in wrapper, "installed launcher still wraps python3"
assert str(package / "bin/birc") in wrapper, "installed client default is not absolute"

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
