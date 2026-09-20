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
    export BUN_INSTALL_CACHE_DIR="''${TMPDIR:-/tmp}/birc-bun-cache"
    export BUN_RUNTIME_TRANSPILER_CACHE_PATH="''${TMPDIR:-/tmp}/birc-bun-cache/transpiler"
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
