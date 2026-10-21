#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Content-hash cache for the build-ui single-TU artifact.
#
# build-ui compiles one ~33MB Bend-emitted TU (build/birc_bend.c) into
# build/birc (Makefile: build/birc_bend.c + build/birc recipes). Both steps
# are slow; this script caches their outputs under a content-hash key so an
# unchanged tree restores the artifact instead of rebuilding it.
#
# The Makefile calls restore before bend/clang and store after a real link.
# BIRC_UI_CACHE=0 forces a miss so `make -n` still shows the compiler recipes.
#
# Usage:
#   sh scripts/build-ui-cache.sh key                  # print cache key
#   sh scripts/build-ui-cache.sh restore [blddir]     # 0=hit, 1=miss, 2=error
#   sh scripts/build-ui-cache.sh store [blddir]       # save current outputs
#
# Environment:
#   BIRC_UI_CACHE=1            Enable restore/store. This is the default.
#                              BIRC_UI_CACHE=0 reports a miss (caller builds
#                              normally) and makes store a no-op. `key` always
#                              works.
#   BIRC_UI_CACHE_DIR          Cache root. Default:
#                              ${XDG_CACHE_HOME:-$HOME/.cache}/birc/ui-cache.
#                              Unset HOME or HOME=/homeless-shelter uses
#                              build/ui-cache. CI should override this.
#   BEND_CORE_CFLAGS           Must match the Makefile value (default there:
#                              -std=c11 -O2 -pthread -w). Part of the key.
#   BIRC_BEND_VERSION          Bend identity override (dry-run/CI). Default:
#                              `bend version` plus ${BIRC_BEND_REV:-}.
#   BIRC_UI_CC_IDENTITY        C compiler identity override. Default: first
#                              line of `${CC:-cc} --version`.
#
# Fail-closed rules: an uncomputable key (missing inputs, no hasher, unknown
# toolchain) exits 2 and never touches the cache or build outputs. A restore
# whose payload hashes mismatch the key exits 1 (miss), removes the corrupt
# entry, and installs nothing, so the caller rebuilds from source.
set -eu

# Default outside build/ so `make clean` keeps hits. Nix sandboxes and an
# unset HOME fall back to build/ui-cache.
default_cache_dir() {
    case "${HOME:-}" in
        ""|/homeless-shelter)
            printf '%s\n' "build/ui-cache"
            ;;
        *)
            printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/birc/ui-cache"
            ;;
    esac
}

CACHE_DIR=${BIRC_UI_CACHE_DIR:-$(default_cache_dir)}
CACHE_ON=${BIRC_UI_CACHE:-1}
CFLAGS_VAL=${BEND_CORE_CFLAGS:-'-std=c11 -O2 -pthread -w'}
BLD_DEFAULT=build

die() { printf '%s\n' "build-ui-cache: $*" >&2; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }

# Print the hex digest of stdin, hasher-portable.
hash_stdin() {
    if have sha256sum; then sha256sum | awk '{print $1}';
    elif have shasum; then shasum -a 256 | awk '{print $1}';
    else return 1;
    fi
}
hash_files() {
    if have sha256sum; then sha256sum "$@";
    elif have shasum; then shasum -a 256 "$@";
    else return 1;
    fi
}

# Mirror BEND_UI_SRCS exactly: src/bend/*.bend src/ffi/*.[ch] src/ui/timui.h.
# Prints the sorted source list; fails closed on empty globs/unreadable files.
source_list() {
    tmp=$(mktemp) || die "mktemp failed"
    : >"$tmp"
    for pattern in 'src/bend/*.bend' 'src/ffi/*.c' 'src/ffi/*.h' 'src/ui/timui.h'; do
        # Expand one glob without nullglob: an unexpanded pattern is a miss.
        # shellcheck disable=SC2086
        set -- $pattern
        case "$1" in
            *'*'*) rm -f "$tmp"; die "no files match $pattern" ;;
        esac
        for f in "$@"; do
            [ -f "$f" ] || { rm -f "$tmp"; die "not a regular file: $f"; }
            [ -r "$f" ] || { rm -f "$tmp"; die "unreadable file: $f"; }
            printf '%s\n' "$f" >>"$tmp"
        done
    done
    LC_ALL=C sort -u "$tmp"
    rm -f "$tmp"
}

bend_identity() {
    if [ -n "${BIRC_BEND_VERSION:-}" ]; then
        printf '%s\n' "$BIRC_BEND_VERSION"
    elif have bend; then
        id=$(bend version 2>/dev/null | head -1) || die "bend version failed"
        [ -n "$id" ] || die "empty bend version"
        printf '%s rev=%s\n' "$id" "${BIRC_BEND_REV:-unknown}"
    else
        die "unknown Bend toolchain (no bend on PATH, BIRC_BEND_VERSION unset)"
    fi
}

cc_identity() {
    if [ -n "${BIRC_UI_CC_IDENTITY:-}" ]; then
        printf '%s\n' "$BIRC_UI_CC_IDENTITY"
    else
        cc=${CC:-cc}
        have "$cc" || die "unknown C compiler ($cc not found, BIRC_UI_CC_IDENTITY unset)"
        id=$("$cc" --version 2>/dev/null | head -1) || die "$cc --version failed"
        [ -n "$id" ] || die "empty $cc --version"
        printf '%s: %s\n' "$cc" "$id"
    fi
}

# Content-hash key over sources + flags + toolchain identities.
cache_key() {
    have sha256sum || have shasum || die "need sha256sum or shasum"
    list=$(source_list) || exit 2
    # shellcheck disable=SC2086
    src_hash=$(hash_files $list | hash_stdin) || die "source hashing failed"
    [ -n "$src_hash" ] || die "source hashing failed"
    {
        printf 'sources=%s\n' "$src_hash"
        printf 'flags=%s\n' "$CFLAGS_VAL"
        printf 'bend=%s\n' "$(bend_identity)"
        printf 'cc=%s\n' "$(cc_identity)"
    } | hash_stdin | sed 's/^/birc-ui-/'
}

cmd_key() { cache_key; }

# Artifacts covered: the 33MB TU, the linked binary, and the toolchain record.
artifacts() {
    blddir=$1
    printf '%s\n' "$blddir/birc_bend.c" "$blddir/birc" "$blddir/build-config"
}

cmd_restore() {
    blddir=${1:-$BLD_DEFAULT}
    [ -n "$blddir" ] || blddir=$BLD_DEFAULT
    [ "$CACHE_ON" = 1 ] || exit 1  # disabled: plain miss, caller builds
    key=$(cache_key)
    entry=$CACHE_DIR/$key
    manifest=$entry/MANIFEST.sha256
    [ -f "$manifest" ] || exit 1   # miss: no entry
    # Fail closed: verify every payload before installing anything.
    ok=1
    while read -r want path; do
        case "$want" in
            ''|'#'*) continue ;;
        esac
        base=$(basename "$path")
        cached=$entry/$base
        [ -f "$cached" ] || { ok=0; break; }
        got=$(hash_files "$cached" | awk '{print $1}') || { ok=0; break; }
        [ "$got" = "$want" ] || { ok=0; break; }
    done <"$manifest"
    if [ "$ok" != 1 ]; then
        rm -rf "$entry"  # corrupt entry: self-heal, caller rebuilds
        exit 1
    fi
    mkdir -p "$blddir"
    while read -r want path; do
        case "$want" in
            ''|'#'*) continue ;;
        esac
        base=$(basename "$path")
        cp "$entry/$base" "$blddir/$base"
    done <"$manifest"
    printf '%s\n' "build-ui-cache: hit $key" >&2
    exit 0
}

cmd_store() {
    blddir=${1:-$BLD_DEFAULT}
    [ -n "$blddir" ] || blddir=$BLD_DEFAULT
    [ "$CACHE_ON" = 1 ] || exit 0  # disabled: no-op
    key=$(cache_key)
    entry=$CACHE_DIR/$key
    # All artifacts must exist; a partial build must not poison the cache.
    # (No pipelines here: die/cp failures must exit this shell, not a subshell.)
    for f in "$blddir/birc_bend.c" "$blddir/birc" "$blddir/build-config"; do
        [ -f "$f" ] || die "missing build output for store: $f"
    done
    tmp_entry=$CACHE_DIR/.tmp.$key.$$
    rm -rf "$tmp_entry"
    mkdir -p "$tmp_entry"
    trap 'rm -rf "$tmp_entry"' EXIT HUP INT TERM
    for f in "$blddir/birc_bend.c" "$blddir/birc" "$blddir/build-config"; do
        cp "$f" "$tmp_entry/$(basename "$f")"
    done
    (cd "$tmp_entry" && hash_files birc_bend.c birc build-config >MANIFEST.sha256)
    rm -rf "$entry"
    mv "$tmp_entry" "$entry"
    trap - EXIT HUP INT TERM
    printf '%s\n' "build-ui-cache: stored $key" >&2
    exit 0
}

case "${1:-}" in
    key) cmd_key ;;
    restore) cmd_restore "${2:-}" ;;
    store) cmd_store "${2:-}" ;;
    *) die "usage: $0 {key|restore|store} [blddir]" ;;
esac
