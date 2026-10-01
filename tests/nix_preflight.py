#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Execute only proto-parity's fixture preflight without ambient Python."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
make = shutil.which("make")
assert make is not None
with tempfile.TemporaryDirectory(prefix="birc-nix-preflight-") as directory:
    work = Path(directory)
    shutil.copytree(root / "fixtures", work / "fixtures")
    shim = work / "host-bin"
    shim.mkdir()
    host_python = shim / "python3"
    host_python.write_text("#!/bin/sh\nexit 77\n")
    host_python.chmod(0o700)
    wrapper = work / "provisioned"
    wrapper.write_text('#!/bin/sh\ncase "$1" in\n'
                       '  python3) shift; exec "$BIRC_PREFLIGHT_PYTHON" "$@" ;;\n'
                       '  *) exit 0 ;;\nesac\n')
    wrapper.chmod(0o700)
    env = {**os.environ, "PATH": str(shim) + os.pathsep + os.environ["PATH"],
           "BIRC_PREFLIGHT_PYTHON": sys.executable}
    command = [make, "-f", str(root / "Makefile"), "proto-parity", "NIXRUN=" + str(wrapper)]
    # The wrapper runs real provisioned Python for the fixture check only;
    # downstream compiler/golden invocations are outside this guard's scope.
    good = subprocess.run(command, cwd=work, env=env, capture_output=True, timeout=10)
    assert good.returncode == 0, good.stderr
    (work / "fixtures/action.irc").write_bytes(b":alice!u@h PRIVMSG #t :ACTION waves\n")
    bad = subprocess.run(command, cwd=work, env=env, capture_output=True, timeout=10)
    assert bad.returncode != 0
    assert b"CTCP validation failed" in bad.stderr
print("nix_preflight=ok")
