#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Deliver one desktop notification without a shell.

The UI owns scheduling and retention. This helper takes the notify-send
shape ("--", title, body) and dispatches to a platform backend. Backend
policy (n9-bind3 R4): on Linux the installed backend is absolute via
BIRC_NOTIFY_SEND_DEFAULT (set by the nix wrapper to the provisioned
libnotify notify-send), ignoring ambient PATH by default; only an explicit
BIRC_NOTIFY_SEND override selects another backend. The bare "notify-send"
PATH fallback remains for dev/uninstalled runs with no wrapper (no DEFAULT).
An ambient PATH impostor must never receive body/title by default. On macOS
the backend is the OS-owned /usr/bin/osascript pinned absolutely (never
nix-provisioned), with BIRC_OSASCRIPT as the only override (tests always set
it, so the real system backend is never touched). Failures use one fixed
diagnostic; no title/body bytes are echoed.
"""

from __future__ import annotations

import os
import subprocess
import sys

FAIL = "birc-notify: notification unavailable\n"
TIMEOUT = 1
OSASCRIPT_SYSTEM = "/usr/bin/osascript"
LINUX_DEFAULT_ENV = "BIRC_NOTIFY_SEND_DEFAULT"


def esc(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def linux_backend() -> str:
    explicit = os.environ.get("BIRC_NOTIFY_SEND")
    if explicit:
        return explicit
    pinned = os.environ.get(LINUX_DEFAULT_ENV)
    if pinned:
        return pinned
    return "notify-send"


def darwin_backend() -> str:
    return os.environ.get("BIRC_OSASCRIPT") or OSASCRIPT_SYSTEM


def main(argv: list[str]) -> int:
    if len(argv) != 4 or argv[1] != "--":
        sys.stderr.write(FAIL)
        return 1
    title, body = argv[2], argv[3]
    try:
        if sys.platform == "darwin":
            script = f'display notification "{esc(body)}" with title "{esc(title)}"'
            subprocess.run([darwin_backend(), "-e", script], stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=TIMEOUT, check=True)
        else:
            subprocess.run([linux_backend(), "--", title, body], stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=TIMEOUT, check=True)
    except Exception:
        sys.stderr.write(FAIL)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
