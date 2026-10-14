#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# shard-pty.sh: deterministic sharding of the `test-pty` suite over make targets.
#
# The suite is sharded by target (not by python invocation): this script only
# selects `test-pty-*` target names, and the caller runs them via `make`, so
# every recipe keeps its own `timeout` bound (25-150 s) and owned loopback
# peers by construction. This script never runs tests itself (except `--exec`,
# which delegates to `make`) and never touches the network.
#
# Shard selection (0-based, fail-closed):
#   PTY_SHARD="I/N"              single-var form, e.g. PTY_SHARD=1/4
#   PTY_SHARD=I PTY_SHARDS=N     split form (PTY_TOTAL / PTY_N alias PTY_SHARDS)
#   --shard I/N | --shard I --total N   CLI overrides env
# Selection rule: sorted_manifest_index % N == I. Exit 2 on any malformed,
# conflicting, or out-of-range value. An empty shard (N > suite size) prints
# nothing and exits 0; it never silently expands to the full suite.
set -eu

MODE=print
SHARD_CLI=
TOTAL_CLI=

usage() {
  cat <<'EOF'
usage: shard-pty.sh [--shard I[/N]] [--total N] [--print|--list|--dry-run|--stamp|--exec]
       PTY_SHARD="I/N" shard-pty.sh [--print|--dry-run|--stamp|--exec]

Select the deterministic subset of `test-pty` make targets for shard I of N
(0-based; sorted index % N == I). Only prints names; run them with `make`
so each recipe keeps its own timeout and loopback peers.

modes:
  --print     one target per line (default)
  --list      print all suite targets, ignoring any shard selection
  --dry-run   print the single `make ...` command for the shard
  --stamp     print the cache key `shard-I-of-N`
  --exec      exec `make` on the shard's targets (empty shard: no-op, exit 0)
  --help      this text

env: PTY_SHARD ("I/N" or "I"), PTY_SHARDS (aliases: PTY_TOTAL, PTY_N).
exit: 0 ok (empty shard included), 2 usage/config error.
EOF
}

die() {
  printf '%s\n' "shard-pty: $*" >&2
  exit 2
}

is_uint() {
  case "${1:-}" in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

# Exact `test-pty` closure (sorted): `make test-pty` prerequisites from the
# root Makefile. Standalone PTY targets NOT in the suite stay out of scope:
# test-pty-auth, test-pty-upload-preferences-private, test-pty-recovery-settings
# (meta), test-pty-deadlines (static check) keep their own recipes.
TARGETS='test-pty-alerts
test-pty-autoreconnect
test-pty-bpaste
test-pty-closequit
test-pty-composer
test-pty-connect
test-pty-deferred-redraw
test-pty-demo-nick
test-pty-diagnostic
test-pty-disconnect-cleanup
test-pty-eof
test-pty-esc-resize-wake
test-pty-escup
test-pty-flood
test-pty-frame-links
test-pty-geneof
test-pty-history
test-pty-history-endpoints
test-pty-history-images
test-pty-hostile
test-pty-image-marker
test-pty-input-fairness
test-pty-joinlat
test-pty-launchers
test-pty-linger
test-pty-linkclick
test-pty-local-time
test-pty-m20-media-cache
test-pty-manyeof
test-pty-media
test-pty-minus
test-pty-mixburst
test-pty-mouseselect
test-pty-output-failure
test-pty-output-progress
test-pty-output-recovery
test-pty-output-stall
test-pty-paintwake
test-pty-paste50
test-pty-preferences
test-pty-preferences-history
test-pty-preview
test-pty-preview-retry
test-pty-quitcap
test-pty-reconnect-nick
test-pty-reconnect-recovery
test-pty-redial
test-pty-resize
test-pty-restore
test-pty-rows
test-pty-rst
test-pty-scroll-wrap
test-pty-send-stall
test-pty-session-links
test-pty-settings
test-pty-softwrap
test-pty-split
test-pty-split-identity
test-pty-stall
test-pty-startup-connect
test-pty-tabcut
test-pty-tabswitch
test-pty-tall
test-pty-tickrate
test-pty-tinyquit
test-pty-tls
test-pty-typing
test-pty-ui-review-media
test-pty-ui-review-selection
test-pty-upload
test-pty-upload-diagnostics
test-pty-utf8
test-pty-wrapped-spans'

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help | -h)
      usage
      exit 0
      ;;
    --print) MODE=print ;;
    --list | --all) MODE=list ;;
    --dry-run) MODE=dryrun ;;
    --stamp) MODE=stamp ;;
    --exec) MODE=exec ;;
    --shard)
      [ "$#" -ge 2 ] || die "missing value for --shard"
      SHARD_CLI=$2
      shift
      ;;
    --shard=*) SHARD_CLI=${1#--shard=} ;;
    --total | --shards)
      [ "$#" -ge 2 ] || die "missing value for $1"
      TOTAL_CLI=$2
      shift
      ;;
    --total=* | --shards=*) TOTAL_CLI=${1#*=} ;;
    --)
      shift
      break
      ;;
    -*) die "unknown option: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
  shift
done
[ "$#" -eq 0 ] || die "unexpected argument: $1"

if [ "$MODE" = list ]; then
  printf '%s\n' "$TARGETS"
  exit 0
fi

SPEC=${SHARD_CLI:-${PTY_SHARD:-}}
[ -n "$SPEC" ] || die "no shard selected (want --shard I/N or PTY_SHARD=I/N)"

TOTAL_ENV=
for var in PTY_SHARDS PTY_TOTAL PTY_N; do
  val=
  eval "val=\${$var:-}"
  [ -n "$val" ] || continue
  if [ -n "$TOTAL_ENV" ] && [ "$TOTAL_ENV" != "$val" ]; then
    die "conflicting totals: $TOTAL_ENV vs $var=$val"
  fi
  TOTAL_ENV=$val
done
TOTAL_WANT=${TOTAL_CLI:-$TOTAL_ENV}

case "$SPEC" in
  */*)
    IDX=${SPEC%%/*}
    TOT=${SPEC##*/}
    case "$SPEC" in
      */*/*) die "malformed shard: $SPEC (want I/N)" ;;
    esac
    if [ -n "$TOTAL_WANT" ] && [ "$TOTAL_WANT" != "$TOT" ]; then
      die "conflicting totals: $SPEC vs total $TOTAL_WANT"
    fi
    ;;
  *)
    IDX=$SPEC
    TOT=$TOTAL_WANT
    [ -n "$TOT" ] || die "shard $IDX needs a total (want I/N or --total N)"
    ;;
esac

is_uint "$IDX" || die "shard index is not a number: $IDX"
is_uint "$TOT" || die "shard total is not a number: $TOT"
[ "$TOT" -ge 1 ] || die "shard total must be >= 1: $TOT"
[ "$TOT" -le 256 ] || die "shard total over cap 256: $TOT"
[ "$IDX" -lt "$TOT" ] || die "shard index $IDX out of range for total $TOT (0-based)"

if [ "$MODE" = stamp ]; then
  printf 'shard-%s-of-%s\n' "$IDX" "$TOT"
  exit 0
fi

SELECTED=
i=0
while IFS= read -r target; do
  [ -n "$target" ] || continue
  if [ "$((i % TOT))" -eq "$IDX" ]; then
    if [ -z "$SELECTED" ]; then
      SELECTED=$target
    else
      SELECTED="$SELECTED
$target"
    fi
  fi
  i=$((i + 1))
done <<EOF
$TARGETS
EOF

case "$MODE" in
  print)
    [ -n "$SELECTED" ] || exit 0
    printf '%s\n' "$SELECTED"
    ;;
  dryrun)
    if [ -z "$SELECTED" ]; then
      printf '# shard %s/%s selects 0 targets (nothing to run)\n' "$IDX" "$TOT"
    else
      printf 'make'
      # shellcheck disable=SC2086
      printf ' %s' $SELECTED
      printf '\n'
    fi
    ;;
  exec)
    if [ -z "$SELECTED" ]; then
      printf '%s\n' "shard-pty: shard $IDX/$TOT is empty, nothing to run" >&2
      exit 0
    fi
    # shellcheck disable=SC2086
    exec "${MAKE:-make}" $SELECTED
    ;;
esac
