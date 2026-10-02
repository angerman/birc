#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""TLS flags reach every CC call; effective TLS inputs invalidate app caches."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def run(command, env):
    return subprocess.check_output(command, env=env, text=True, timeout=10)


with tempfile.TemporaryDirectory(prefix="birc-build-tls-") as directory:
    root = Path(directory)
    fake_cc = root / "cc"
    fake_cc.write_text("#!/bin/sh\nprintf '%s\\n' 'synthetic clang version 21'\n")
    fake_cc.chmod(0o700)
    env = dict(os.environ)
    for name in list(env):
        if name.startswith(("BIRC_TLS_", "NIX_CFLAGS_COMPILE", "NIX_LDFLAGS")):
            del env[name]
    env.update(BIRC_NIX_SHELL="1", BIRC_BEND_REV="synthetic", BIRC_BEND_SRC="synthetic",
               CC=str(fake_cc), BIRC_NIX_CC_SUFFIX="test_target", BIRC_OPENSSL_DEV="/synthetic/dev",
               BIRC_OPENSSL_LIB="/synthetic/lib", BIRC_TLS_CFLAGS="-isystem /synthetic/dev/include",
               BIRC_TLS_LDFLAGS="-L/synthetic/lib/lib -rpath /synthetic/lib/lib -lssl -lcrypto",
               SSL_CERT_FILE="/synthetic/ca.pem", SSL_CERT_DIR="/synthetic/certs",
               NIX_CFLAGS_COMPILE_test_target="-DUSER_FLAG=1  -DSECOND=2",
               NIX_LDFLAGS_test_target="-L/synthetic/existing")
    extra_make = root / "inspect.mk"
    extra_make.write_text(".PHONY: inspect-tls-env\ninspect-tls-env:\n"
                          "\t@printf '%s\\n' \"$$NIX_CFLAGS_COMPILE_test_target\" \"$$NIX_LDFLAGS_test_target\"\n")
    command = ["make", "--no-print-directory", "-f", "Makefile", "-f", str(extra_make), "inspect-tls-env"]
    got = run(command, env).splitlines()
    assert got == [env["NIX_CFLAGS_COMPILE_test_target"] + " " + env["BIRC_TLS_CFLAGS"],
                   env["NIX_LDFLAGS_test_target"] + " " + env["BIRC_TLS_LDFLAGS"]], "Make lost caller flags or TLS libraries"
    env.update(NIX_CFLAGS_COMPILE_test_target=got[0], NIX_LDFLAGS_test_target=got[1])
    assert run(command, env).splitlines() == got, "recursive Make duplicated TLS flags"

    script = sys.argv[1] if len(sys.argv) == 2 else "scripts/build-config.sh"
    stamp = root / "build-config"
    stamp_command = ["sh", script, str(stamp), "-O2"]
    run(stamp_command, env)
    before = stamp.stat().st_mtime_ns
    run(stamp_command, env)
    assert stamp.stat().st_mtime_ns == before, "unchanged TLS inputs force a rebuild"
    body = stamp.read_text()
    for value in ("tls-dev=/synthetic/dev", "tls-lib=/synthetic/lib", "tls-ca=/synthetic/ca.pem",
                  "tls-ca-dir=/synthetic/certs", "NIX_CFLAGS_COMPILE_test_target=" + got[0],
                  "NIX_LDFLAGS_test_target=" + got[1]):
        assert value in body, "effective TLS input missing from stamp: " + value
    for key in ("BIRC_OPENSSL_DEV", "BIRC_OPENSSL_LIB", "BIRC_TLS_CFLAGS", "BIRC_TLS_LDFLAGS",
                "SSL_CERT_FILE", "SSL_CERT_DIR", "NIX_CFLAGS_COMPILE_test_target", "NIX_LDFLAGS_test_target"):
        previous = stamp.read_bytes()
        env[key] += "-changed"
        run(stamp_command, env)
        assert stamp.read_bytes() != previous, "changed TLS input missed: " + key
    before = stamp.read_bytes()
    env["BIRC_NIX_CC_SUFFIX"] = "unsafe;not-a-variable"
    failed = subprocess.run(stamp_command, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10)
    assert failed.returncode == 2 and stamp.read_bytes() == before, "unsafe suffix altered the stamp"
print("build_tls=ok")
