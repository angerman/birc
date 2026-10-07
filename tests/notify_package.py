#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed notify helper: provenance, absolute backend, explicit override.

No live IRC or desktop session is required, and no real desktop delivery is
ever attempted. Backend policy (n9-bind3 R4): Linux uses the absolute
installed backend from BIRC_NOTIFY_SEND_DEFAULT (nix-provisioned libnotify),
ignoring ambient PATH by default; only an explicit BIRC_NOTIFY_SEND override
selects another backend. An ambient PATH impostor must never receive
body/title by default (paired installed tests: impostor-not-chosen vs
explicit-chosen, separate fake paths). macOS pins the OS-owned
/usr/bin/osascript with BIRC_OSASCRIPT as the only override (tests always set
it, so the real system backend is never touched; no Darwin impostor run).
Fakes log exact argv boundaries (repr, not "$*"). Both backends fail closed
with one fixed diagnostic; no title/body bytes are echoed.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

FAIL = b"birc-notify: notification unavailable\n"


def environment(root: Path, fake_bin: Path) -> dict[str, str]:
    return {"HOME": str(root), "TMPDIR": str(root), "PATH": str(fake_bin),
            "LANG": "C", "PYTHONDONTWRITEBYTECODE": "1"}


def run(command, env, timeout=15):
    return subprocess.run(command, env=env, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout)


def provenance(binary: Path) -> tuple[Path, Path, Path]:
    wrapper = binary.read_text()
    found = re.findall(r"/nix/store/[^\s'\"{}]+/bin/birc-notify", wrapper)
    assert len(set(found)) == 1, "installed birc wrapper has no unique absolute notify helper"
    helper = Path(found[0])
    assert helper.is_file() and os.access(helper, os.X_OK), "installed notify helper missing"
    body = helper.read_text()
    commands = [shlex.split(line) for line in body.splitlines() if line.startswith("exec ")]
    assert len(commands) == 1 and len(commands[0]) == 4, "unexpected installed notify exec"
    _, python, script, args = commands[0]
    assert args == "$@", "installed notify helper lost argument forwarding"
    python, script = Path(python), Path(script)
    assert str(python).startswith("/nix/store/") and python.name == "python3" and python.is_file(), "Python is not installed"
    assert str(script).startswith("/nix/store/") and script.is_file(), "notify source is not installed"
    expected = Path(__file__).resolve().parents[1] / "src/media/notify.py"
    assert script.read_bytes() == expected.read_bytes(), "installed notify source differs from this checkout"
    return helper, python, script


def fake_platform(path: Path, log: Path) -> None:
    # Exact argv boundaries via repr (not "$*", which does not prove them).
    # sys.executable is absolute: PATH in the test env is the fake bin only.
    path.write_text("#!" + sys.executable + "\n" +
                    "import sys\n" +
                    f"log = {str(log)!r}\n" +
                    "with open(log, 'a', encoding='utf-8') as handle:\n" +
                    "    handle.write(repr(sys.argv[1:]) + '\\n')\n")
    path.chmod(0o755)


def backend_provenance(wrapper: str, script: Path) -> None:
    """Absolute backend provenance: provisioned (Linux) or pinned (Darwin)."""
    if sys.platform == "darwin":
        installed = script.read_text()
        assert "/usr/bin/osascript" in installed, "darwin backend is not the owned system osascript"
        assert "BIRC_OSASCRIPT" in installed, "darwin backend override is missing"
        return
    # Installed Linux backend is absolute via BIRC_NOTIFY_SEND_DEFAULT (the
    # nix-provisioned libnotify notify-send), never ambient PATH. The wrapper
    # must not append libnotify to PATH (that would let an ambient impostor
    # shadow it).
    assert "BIRC_NOTIFY_SEND_DEFAULT" in wrapper, "installed notify wrapper has no absolute backend default"
    assert "BIRC_NOTIFY_SEND_DEFAULT" in script.read_text(), "notify source has no absolute backend default"
    found = re.findall(r"/nix/store/[^\s'\"{}]*libnotify[^\s'\"{}]*/bin/notify-send", wrapper)
    assert len(set(found)) == 1, "installed notify wrapper has no unique absolute libnotify backend"
    notify_send = Path(found[0])
    assert notify_send.is_file() and os.access(notify_send, os.X_OK), "provisioned notify-send missing"
    for line in wrapper.splitlines():
        assert not ("PATH" in line and "libnotify" in line), \
            "installed notify wrapper still appends libnotify to PATH (ambient impostor wins)"
    bare = {"HOME": "/nonexistent", "PATH": "/nonexistent",
            "LANG": "C", "PYTHONDONTWRITEBYTECODE": "1"}
    for flag in ("--version", "--help"):
        result = run([str(notify_send), flag], bare)
        if result.returncode == 0:
            break
    else:
        raise AssertionError("provisioned notify-send is not headless-runnable")


def helper_controls(helper: Path, root: Path, env: dict[str, str]) -> None:
    fake_bin = Path(env["PATH"])
    is_darwin = sys.platform == "darwin"
    platform = "osascript" if is_darwin else "notify-send"
    # Separate fake paths: explicit (override target) vs ambient (PATH impostor).
    explicit_dir = root / "explicit-fake"
    explicit_dir.mkdir()
    explicit_log = root / "explicit.calls"
    explicit_fake = explicit_dir / platform
    fake_platform(explicit_fake, explicit_log)
    ambient_log = root / "ambient.calls"
    ambient_fake = fake_bin / platform
    fake_platform(ambient_fake, ambient_log)
    forward = dict(env)
    if is_darwin:
        # The darwin backend pins /usr/bin/osascript, so PATH shadowing
        # cannot inject the fake; the explicit override is the only path.
        forward["BIRC_OSASCRIPT"] = str(explicit_fake)
    else:
        forward["BIRC_NOTIFY_SEND"] = str(explicit_fake)
    # Explicit-chosen (paired with impostor-not-chosen below): the explicit
    # fake receives the exact argv with boundaries; the ambient impostor does
    # not. Tricky titles/bodies prove boundaries ("$*" would not).
    cases = [("bob in #room", "hi me"),
             ("a b", "c d"),
             ("--help", "--")]
    for title, body in cases:
        if explicit_log.exists():
            explicit_log.unlink()
        if ambient_log.exists():
            ambient_log.unlink()
        result = run([str(helper), "--", title, body], forward)
        assert result.returncode == 0 and not result.stdout and not result.stderr, \
            "installed notify helper failed with explicit backend"
        calls = explicit_log.read_text().splitlines()
        assert len(calls) == 1, "explicit backend was not invoked once"
        if is_darwin:
            assert calls[0].startswith("['-e', 'display notification "), \
                "osascript invocation lost argv boundaries"
            assert body in calls[0] and title in calls[0], \
                "osascript invocation dropped title/body"
        else:
            assert calls[0] == repr(["--", title, body]), \
                f"notify-send invocation lost argv boundaries: {calls[0]!r}"
        assert not ambient_log.exists(), \
            "ambient PATH impostor received the explicit invocation"
    if not is_darwin:
        # Impostor-not-chosen (Linux): ambient PATH impostor, no explicit
        # override. The installed absolute backend (provisioned libnotify)
        # handles it; the impostor log stays empty (never receives
        # body/title). Headless provisioned delivery fails closed (FAIL) or
        # no-ops (success with no output); either is accepted, but no
        # title/body bytes may leak and no real desktop delivery occurs.
        if explicit_log.exists():
            explicit_log.unlink()
        if ambient_log.exists():
            ambient_log.unlink()
        impostor = run([str(helper), "--", "bob in #room", "hi me"], env)
        assert not impostor.stdout, "default backend emitted output"
        assert b"bob in #room" not in impostor.stdout + impostor.stderr, \
            "default backend leaked title"
        assert b"hi me" not in impostor.stdout + impostor.stderr, \
            "default backend leaked body"
        if impostor.returncode == 0:
            assert not impostor.stderr, "default backend success emitted diagnostics"
        else:
            assert impostor.stderr == FAIL, "default backend failure exposed variable text"
        assert not ambient_log.exists(), \
            "ambient PATH impostor received body/title by default (must use absolute backend)"
        assert not explicit_log.exists(), \
            "explicit fake received the default invocation"
    for argv in ([str(helper)], [str(helper), "--"], [str(helper), "--", "only"],
                [str(helper), "x", "y", "z"], [str(helper), "--", "t", "b", "extra"]):
        result = run(argv, forward)
        assert result.returncode != 0 and not result.stdout, "invalid notify input emitted output"
        assert result.stderr == FAIL, "invalid notify input exposed variable text"
    missing = dict(env)
    if is_darwin:
        missing["BIRC_OSASCRIPT"] = str(root / "no-such-osascript")
    else:
        missing["BIRC_NOTIFY_SEND"] = str(root / "no-such-notify-send")
    result = run([str(helper), "--", "t", "b"], missing)
    assert result.returncode != 0 and not result.stdout, "missing platform helper emitted output"
    assert result.stderr == FAIL, "missing platform helper exposed variable text"


def main(argument: str) -> None:
    target = Path(argument).resolve()
    binary = target / "bin/birc" if target.is_dir() else target
    helper, _, script = provenance(binary)
    backend_provenance(helper.read_text(), script)
    with tempfile.TemporaryDirectory(prefix="birc-notify-package-") as temporary:
        root = Path(temporary)
        fake_bin = root / "fake-bin"
        fake_bin.mkdir()
        env = environment(root, fake_bin)
        helper_controls(helper, root, env)
    print("notify_package=ok")


if __name__ == "__main__":
    try:
        assert len(sys.argv) == 2, "expected installed package or birc wrapper path"
        main(sys.argv[1])
    except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"notify_package: {error}", file=sys.stderr)
        raise SystemExit(1)
