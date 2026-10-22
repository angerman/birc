#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Native keychain-birc launch with synthetic security and client helpers."""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def executable(path: Path, body: str) -> Path:
    path.write_text("#!" + sys.executable + "\n" + body)
    path.chmod(0o700)
    return path


def stdout_closed_past_deadline(launcher: str, root: Path, cfg: Path) -> None:
    """Helper closes stdout and sleeps past birc_kc_bounded's 30s deadline.

    load_secret and save_secret both pass 30.0. A blocking waitpid would sit
    until this sleep ends; the reap must fail soon after the deadline instead.
    """
    deadline = 30.0
    sleep_s = 120
    bound = deadline + 10.0
    executable(root / "security_hang", """
import os, time
os.close(1)
end = time.monotonic() + %d
while time.monotonic() < end:
    if os.getppid() == 1:
        raise SystemExit(0)
    time.sleep(0.05)
""" % sleep_s)
    for name in ("child", "calls"):
        stale = root / name
        if stale.exists():
            stale.unlink()
    env = {
        "HOME": str(root),
        "LANG": "C",
        "PATH": "",
        "BIRC_PROGRAM": str(root / "birc"),
        "BIRC_SECURITY": str(root / "security_hang"),
        "BIRC_KEYCHAIN_PLATFORM": "darwin",
        "BIRC_KEYCHAIN_PASSWORD": "synthetic-secret",
    }
    proc = subprocess.Popen(
        [launcher, "--profile", "test", "--config", str(cfg), "--frames", "1"],
        env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE)
    started = time.monotonic()
    try:
        try:
            out, err = proc.communicate(timeout=bound)
        except subprocess.TimeoutExpired:
            raise AssertionError(
                "reap still blocked %.0fs after stdout EOF; helper sleeps %ds"
                % (bound, sleep_s)) from None
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
    elapsed = time.monotonic() - started
    assert proc.returncode == 1, err
    assert b"Keychain helper timed out" in err, err
    assert b"synthetic-secret" not in out + err
    assert not (root / "child").exists()
    assert elapsed < bound, elapsed
    assert elapsed >= deadline - 2.0, elapsed


def main(launcher: str) -> None:
    with tempfile.TemporaryDirectory(prefix="birc-keychain-native-launch-") as name:
        root = Path(name)
        cfg = root / "config.toml"
        cfg.write_text('[profiles.test]\nhost = "127.0.0.1"\naccount = "alice"\n'
                       "trusted_relay = true\ntls = false\n")
        cfg.chmod(0o600)
        security = executable(root / "security", """
import json, os, sys
from pathlib import Path
root = Path(__file__).parent
with (root / "calls").open("a") as out:
    out.write(json.dumps({"argv": sys.argv[1:], "stdin": sys.stdin.read()}) + "\\n")
if sys.argv[1:] == ["-i"]:
    sys.exit(0)
code = int((root / "find_code").read_text())
if code == 0:
    sys.stdout.buffer.write((root / "stored").read_bytes())
sys.exit(code)
""")
        child = executable(root / "birc", """
import json, os, sys
from pathlib import Path
root = Path(__file__).parent
fd = int(os.environ["BIRC_AUTH_SECRET_FD"])
secret = b""
while True:
    part = os.read(fd, 2048)
    if not part:
        break
    secret += part
os.close(fd)
(root / "child").write_text(json.dumps({
    "argv": sys.argv[1:],
    "secret": secret.decode(),
    "env": {k: v for k, v in os.environ.items() if k.startswith("BIRC_")},
}))
fd = int(os.environ["BIRC_AUTH_EVENT_FD"])
os.write(fd, b"BIRC_AUTH_OK\\n")
os.close(fd)
sys.exit(0)
""")
        (root / "find_code").write_text("44")
        env = {
            "HOME": str(root),
            "LANG": "C",
            "PATH": "",
            "BIRC_PROGRAM": str(child),
            "BIRC_SECURITY": str(security),
            "BIRC_KEYCHAIN_PLATFORM": "darwin",
            "BIRC_KEYCHAIN_PASSWORD": "synthetic-secret",
        }
        result = subprocess.run(
            [launcher, "--profile", "test", "--config", str(cfg), "--frames", "1"],
            env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, result.stderr
        assert b"synthetic-secret" not in result.stdout + result.stderr
        calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
        assert calls[0]["argv"][0] == "find-generic-password"
        assert calls[1]["argv"] == ["-i"]
        envelope = bytes.fromhex(calls[1]["stdin"].split(" -X ")[1].strip()).decode("ascii")
        assert envelope == "birc-v1:" + base64.b64encode(b"synthetic-secret").decode()
        got = json.loads((root / "child").read_text())
        assert got["secret"] == "synthetic-secret"
        assert got["argv"][:6] == ["--connect", "127.0.0.1", "--port", "6667",
                                   "--sasl-user", "alice"]
        assert "--plain" in got["argv"] and got["argv"][-2:] == ["--frames", "1"]
        assert "BIRC_SASL_PASS" not in got["env"] and "BIRC_KEYCHAIN_PASSWORD" not in got["env"]

        (root / "find_code").write_text("0")
        (root / "stored").write_bytes(envelope.encode() + b"\n")
        (root / "calls").unlink()
        (root / "child").unlink()
        env.pop("BIRC_KEYCHAIN_PASSWORD")
        result = subprocess.run(
            [launcher, "--profile", "test", "--config", str(cfg)],
            env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, result.stderr
        assert len((root / "calls").read_text().splitlines()) == 1
        assert json.loads((root / "child").read_text())["secret"] == "synthetic-secret"

        help_result = subprocess.run(
            [launcher, "--help"], env={"PATH": "", "LANG": "C"},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert help_result.returncode == 0 and b"--profile" in help_result.stdout
        marker = "synthetic-secret-not-for-arguments"
        bad = subprocess.run(
            [launcher, "--profile", "test", "--sasl-pass", marker],
            env={"PATH": "", "LANG": "C"}, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=5)
        assert bad.returncode == 2 and marker.encode() not in bad.stdout + bad.stderr

        stdout_closed_past_deadline(launcher, root, cfg)
    print("keychain_native_launch=ok")


if __name__ == "__main__":
    try:
        assert len(sys.argv) == 2, "expected keychain-birc-test path"
        main(sys.argv[1])
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"keychain_native_launch: {error}", file=sys.stderr)
        raise SystemExit(1)
