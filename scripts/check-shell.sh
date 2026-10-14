#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Fail fast when run outside the locked `make shell` environment.
#
# The Makefile (lines 20-24) empties NIXRUN only when BIRC_NIX_SHELL=1,
# which flake.nix sets inside `nix develop`. Outside the shell every
# command pays a fresh `nix develop` startup cost, so catch that early.
#
# Usage: scripts/check-shell.sh [--warn]
#   default: exit 2 when BIRC_NIX_SHELL != 1 (fail fast for Make guards)
#   --warn:  print the warning but always exit 0 (advisory DX check)
#
# Bounded: no loops, no network, no subprocesses. Prints fixed next
# commands only; never dumps the environment (no secrets).
set -eu

warn_only=0
if [ "${1:-}" = "--warn" ]; then
    warn_only=1
elif [ $# -gt 0 ]; then
    printf 'usage: %s [--warn]\n' "scripts/check-shell.sh" >&2
    exit 2
fi

if [ "${BIRC_NIX_SHELL:-0}" = "1" ]; then
    printf 'check-shell: inside locked nix shell (BIRC_NIX_SHELL=1)\n'
    exit 0
fi

cat >&2 <<'EOF'
check-shell: NOT inside `make shell` (BIRC_NIX_SHELL!=1).
Every make target will re-enter `nix develop`; enter the shell once instead:
  make shell
  make -n check
EOF

if [ "$warn_only" = "1" ]; then
    exit 0
fi
exit 2
