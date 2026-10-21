#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Installed notify helper: absolute OS backend, no Python dispatcher.

No live IRC or desktop session is required, and no real desktop delivery is
attempted. The packaged client points BIRC_NOTIFY_HELPER at the platform
backend: /usr/bin/osascript on Darwin, the nix-provisioned libnotify
notify-send on Linux. Ambient PATH must not be appended with libnotify.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys


def provenance(binary: Path) -> str:
    wrapper = binary.read_text()
    assert "python3" not in wrapper, "installed birc wrapper still mentions python3 for notify"
    assert "birc-notify" not in wrapper, "installed birc wrapper still ships a notify dispatcher"
    found = re.findall(
        r"BIRC_NOTIFY_HELPER=\$\{BIRC_NOTIFY_HELPER-'([^']+)'\}", wrapper)
    assert len(found) == 1, "installed birc wrapper has no unique notify helper default"
    helper = found[0]
    if sys.platform == "darwin":
        assert helper == "/usr/bin/osascript", "darwin notify helper is not the owned system osascript"
        return helper
    assert helper.startswith("/nix/store/") and helper.endswith("/bin/notify-send"), \
        "linux notify helper is not an absolute provisioned notify-send"
    assert "libnotify" in helper, "linux notify helper is not libnotify"
    notify_send = Path(helper)
    assert notify_send.is_file(), "provisioned notify-send missing"
    for line in wrapper.splitlines():
        assert not ("PATH" in line and "libnotify" in line), \
            "installed notify wrapper still appends libnotify to PATH (ambient impostor wins)"
    return helper


def main(argument: str) -> None:
    target = Path(argument).resolve()
    binary = target / "bin/birc" if target.is_dir() else target
    provenance(binary)
    print("notify_package=ok")


if __name__ == "__main__":
    try:
        assert len(sys.argv) == 2, "expected installed package or birc wrapper path"
        main(sys.argv[1])
    except (AssertionError, OSError, ValueError) as error:
        print(f"notify_package: {error}", file=sys.stderr)
        raise SystemExit(1)
