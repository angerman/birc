#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed uploader provenance, clean PATH, and offline trust controls.

Every source supplied to the helper is invalid before network setup. The
separate upload PTY guard uses an owned fake helper and loopback IRC only.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


def run(command, env):
    return subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


def provenance(binary):
    paths = re.findall(r"/nix/store/[^\s'\"{}]+/bin/birc-upload", binary.read_text())
    assert len(set(paths)) == 1, "client wrapper has no unique absolute uploader"
    return helper_provenance(Path(paths[0]))


def helper_provenance(helper):
    assert helper.is_file() and os.access(helper, os.X_OK), "installed uploader missing"
    body = helper.read_text()
    commands = [shlex.split(line) for line in body.splitlines() if line.startswith("exec ")]
    assert len(commands) == 1 and len(commands[0]) == 4, "unexpected uploader exec"
    _, python, source, args = commands[0]
    assert args == "$@", "uploader lost argument forwarding"
    python, source = Path(python), Path(source)
    assert str(python).startswith("/nix/store/") and python.name == "python3" and python.is_file(), "uploader Python is not provisioned"
    assert str(source).startswith("/nix/store/") and source.is_file(), "uploader source is not installed"
    expected = Path(__file__).resolve().parents[1] / "src/media/upload.py"
    assert source.read_bytes() == expected.read_bytes(), "installed uploader source is stale"
    bundles = re.findall(r"/nix/store/[^\s'\"{}]+/etc/ssl/certs/ca-bundle\.crt", body)
    assert len(set(bundles)) == 1 and Path(bundles[0]).is_file(), "uploader CA bundle missing"
    return helper, python, Path(bundles[0])


def source_controls(helper, root, env):
    empty, fifo, large = root / "empty", root / "fifo", root / "large"
    empty.touch()
    os.mkfifo(fifo)
    with large.open("wb") as stream:
        stream.truncate(32 * 1024 * 1024 + 1)
    link = root / "symlink"
    link.symlink_to(empty)
    for path in (root, empty, fifo, large, link, root / "private missing file"):
        result = run([str(helper), "--local", str(path)], env)
        assert result.returncode == 2 and not result.stdout, "invalid source was not refused before network setup"
        assert result.stderr == b"birc-upload: failed (code:2)\n", "source diagnostic exposed private text"
    usage = run([str(helper)], env)
    assert usage.returncode == 1 and not usage.stdout
    assert usage.stderr == b"birc-upload: failed (code:1)\n", "usage diagnostic is not fixed"
    return empty


def trust_controls(helper, python, bundle, empty, root, env):
    shell = shlex.split(helper.read_text().splitlines()[0][2:])
    assert shell and shell[0].startswith("/nix/store/"), "uploader shell is not provisioned"
    custom = root / "custom CA bundle.pem"
    custom.write_bytes(bundle.read_bytes())
    for value, expected in ((None, bundle), ("", bundle), (str(custom), custom)):
        current = dict(env)
        if value is not None:
            current["SSL_CERT_FILE"] = value
        result = run(shell + ["-x", str(helper), "--local", str(empty)], current)
        assert result.returncode == 2 and not result.stdout, "offline uploader refused source incorrectly"
        selected = []
        for line in result.stderr.decode().splitlines():
            fields = shlex.split(line)
            if len(fields) == 3 and fields[:2] == ["+", "export"] and fields[2].startswith("SSL_CERT_FILE="):
                selected.append(fields[2].split("=", 1)[1])
        assert selected == [str(expected)], "CA default or explicit override was lost"
        current["SSL_CERT_FILE"] = selected[0]
        check = run([str(python), "-c",
            "import ssl,sys; assert ssl.get_default_verify_paths().cafile == sys.argv[1]; "
            "ctx=ssl.create_default_context(); assert ctx.check_hostname; "
            "assert ctx.verify_mode == ssl.CERT_REQUIRED; "
            "assert ctx.cert_store_stats()['x509_ca'] > 0", selected[0]], current)
        assert check.returncode == 0 and not check.stderr, "installed Python cannot load verifying CA trust"


def main(argument, helper_only=False):
    target = Path(argument).resolve()
    if helper_only:
        binary = None
        helper, python, bundle = helper_provenance(target / "bin/birc-upload" if target.is_dir() else target)
    else:
        binary = target / "bin/birc" if target.is_dir() else target
        helper, python, bundle = provenance(binary)
    with tempfile.TemporaryDirectory(prefix="birc-upload-package-") as temporary:
        root = Path(temporary)
        env = {"HOME": str(root), "TMPDIR": str(root), "PATH": "", "LANG": "C",
               "BIRC_HISTORY": "none", "BIRC_IMAGES": "off", "PYTHONDONTWRITEBYTECODE": "1"}
        empty = source_controls(helper, root, env)
        trust_controls(helper, python, bundle, empty, root, env)
        if binary is not None:
            smoke = run([str(binary), "--demo", "--frames", "1"], env)
            assert smoke.returncode == 0 and not smoke.stderr, "installed client cannot start without ambient helpers"
    print("upload_package=ok")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--helper":
            main(sys.argv[2], helper_only=True)
        else:
            assert len(sys.argv) == 2, "expected installed package/client or --helper uploader"
            main(sys.argv[1])
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"upload_package: {error}", file=sys.stderr)
        raise SystemExit(1)
