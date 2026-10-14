# SPDX-License-Identifier: Apache-2.0
# Bend 2 CLI from the pinned upstream source.
#
# Upstream layout (bendlang/bend @ pinned rev):
#   bend2/main.ts   the CLI (#!/usr/bin/env bun); check/run/build
#   bend2/bend.ts   parser, theory, checker
#   bend2/comp.ts   compiler + C/JS runtimes (one C file per program)
#   bend2/base.bend prelude, resolved relative to main.ts
#   bend2/effs/     one .c/.js per IO effect
#
# Native binaries are produced by `bend x.bend -o x`, which invokes
# $CC (or clang on PATH, >= 14) with `-std=c11 -O3 -lpthread -lm`.
{ lib, writeShellApplication, bun, clang, bend-src }:

writeShellApplication {
  name = "bend";
  runtimeInputs = [ bun clang ];
  text = ''
    export CC="''${CC:-${clang}/bin/clang}"
    # Persistent Bun cache: XDG_CACHE_HOME (or ~/.cache) survives sessions so
    # the Bend CLI transpiler cache is reused across builds. Precedence:
    #   1. BUN_INSTALL_CACHE_DIR (explicit; existing sessions keep working)
    #   2. BIRC_BUN_CACHE (explicit persistent-location override)
    #   3. TMPDIR session cache when BIRC_BUN_TMPDIR_CACHE=1 (old behavior)
    #   4. $XDG_CACHE_HOME/birc/bun, then $HOME/.cache/birc/bun
    #   5. TMPDIR fallback when no home/XDG cache is usable (Nix builds)
    if [ -z "''${BUN_INSTALL_CACHE_DIR:-}" ]; then
      if [ -n "''${BIRC_BUN_CACHE:-}" ]; then
        BUN_INSTALL_CACHE_DIR="$BIRC_BUN_CACHE"
      elif [ "''${BIRC_BUN_TMPDIR_CACHE:-0}" = "1" ]; then
        BUN_INSTALL_CACHE_DIR="''${TMPDIR:-/tmp}/birc-bun-cache"
      elif [ -n "''${XDG_CACHE_HOME:-}" ]; then
        BUN_INSTALL_CACHE_DIR="$XDG_CACHE_HOME/birc/bun"
      elif [ -n "''${HOME:-}" ]; then
        BUN_INSTALL_CACHE_DIR="$HOME/.cache/birc/bun"
      else
        BUN_INSTALL_CACHE_DIR="''${TMPDIR:-/tmp}/birc-bun-cache"
      fi
      export BUN_INSTALL_CACHE_DIR
    fi
    if [ -z "''${BUN_RUNTIME_TRANSPILER_CACHE_PATH:-}" ]; then
      BUN_RUNTIME_TRANSPILER_CACHE_PATH="$BUN_INSTALL_CACHE_DIR/transpiler"
      export BUN_RUNTIME_TRANSPILER_CACHE_PATH
    fi
    # Nix build sandboxes set HOME=/homeless-shelter (unwritable). If the
    # chosen cache is not creatable, fall back to the session TMPDIR instead
    # of failing the build or writing outside the sandbox.
    if ! mkdir -p "$BUN_INSTALL_CACHE_DIR" "$BUN_RUNTIME_TRANSPILER_CACHE_PATH" 2>/dev/null; then
      BUN_INSTALL_CACHE_DIR="''${TMPDIR:-/tmp}/birc-bun-cache"
      BUN_RUNTIME_TRANSPILER_CACHE_PATH="$BUN_INSTALL_CACHE_DIR/transpiler"
      export BUN_INSTALL_CACHE_DIR BUN_RUNTIME_TRANSPILER_CACHE_PATH
      mkdir -p "$BUN_INSTALL_CACHE_DIR" "$BUN_RUNTIME_TRANSPILER_CACHE_PATH" 2>/dev/null || true
    fi
    # Bend's version check has a separate opt-out from Bun's crash telemetry.
    export BEND_NO_TELEMETRY=1
    export DO_NOT_TRACK=1
    exec bun run "${bend-src}/bend2/main.ts" "$@"
  '';
  meta = {
    description = "Bend 2 compiler/checker CLI (pinned upstream source)";
    homepage = "https://github.com/bendlang/bend";
    license = lib.licenses.asl20;
    mainProgram = "bend";
  };
}
