#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Update a generated dependency only when the effective toolchain changes.
set -eu
output=$1
shift
mkdir -p "$(dirname "$output")"
candidate=$(mktemp "$output.XXXXXX")
trap 'rm -f "$candidate"' EXIT HUP INT TERM
{
    printf 'bend-rev=%s\nbend-src=%s\nCC=%s\n' \
        "${BIRC_BEND_REV:?use the pinned Nix shell}" \
        "${BIRC_BEND_SRC:?use the pinned Nix shell}" "${CC:?}"
    "$CC" --version
    printf 'flags=%s\n' "$@"
} >"$candidate"
if ! cmp -s "$candidate" "$output"; then
    mv "$candidate" "$output"
fi
