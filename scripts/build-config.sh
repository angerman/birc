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
    # Capture here, after NIXRUN enters the shell, not in Make's outer env.
    printf 'tls-dev=%s\ntls-lib=%s\ntls-cflags=%s\ntls-ldflags=%s\ntls-ca=%s\ntls-ca-dir=%s\n' \
        "${BIRC_OPENSSL_DEV:-}" "${BIRC_OPENSSL_LIB:-}" \
        "${BIRC_TLS_CFLAGS:-}" "${BIRC_TLS_LDFLAGS:-}" "${SSL_CERT_FILE:-}" "${SSL_CERT_DIR:-}"
    suffix=${BIRC_NIX_CC_SUFFIX:-}
    case "$suffix" in
        *[!A-Za-z0-9_]*) printf '%s\n' 'invalid Nix compiler suffix' >&2; exit 2 ;;
    esac
    # No eval or shell expansion of environment values.
    env | LC_ALL=C sort | sed -n \
        -e "/^NIX_CFLAGS_COMPILE_$suffix=/p" -e "/^NIX_LDFLAGS_$suffix=/p"
} >"$candidate"
if ! cmp -s "$candidate" "$output"; then
    mv "$candidate" "$output"
fi
