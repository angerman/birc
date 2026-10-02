# SPDX-License-Identifier: Apache-2.0
"""CLI failures print one diagnostic; normal headless demo still succeeds."""
import os
import subprocess
import sys


def run(arguments):
    environment = dict(os.environ, TERM="xterm-256color", BIRC_HISTORY="none",
                       BIRC_IMAGES="off", BIRC_SASL_USER="", BIRC_SASL_PASS="")
    for name in ("BIRC_DIE_AFTER_OPEN", "BIRC_FRAME_PROFILE", "TIMUI_TRACE"):
        environment.pop(name, None)
    return subprocess.run(
        [sys.argv[1], "--plain", *arguments], stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=environment, timeout=8, check=False,
    )


for arguments, diagnostic in (
    (["--frames", "xyz"], b"birc: expected a number\n"),
    (["--connect"], b"birc: missing value\n"),
    (["--unknown-irc-option"], b"birc: unknown option --unknown-irc-option\n"),
):
    result = run(arguments)
    assert result.returncode == 2, (arguments, result.returncode, result.stderr)
    assert result.stdout == b"", (arguments, result.stdout)
    assert result.stderr == diagnostic, (arguments, result.stderr, diagnostic)

result = run(["--help-irc"])
assert result.returncode == 2, (result.returncode, result.stderr)
assert result.stdout == b"", result.stdout
assert len(result.stderr.splitlines()) == 1, result.stderr
assert result.stderr.startswith(b"usage: birc "), result.stderr

result = run(["--demo", "--frames", "1"])
assert result.returncode == 0 and b"birc=ok" in result.stdout, (
    result.returncode, result.stdout, result.stderr)
assert result.stderr == b"", result.stderr
print("cli_diagnostics=ok", flush=True)
