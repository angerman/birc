#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Discharge every law in its own small book. The monolithic PROOF.bend import
# closure does not finish under Bun; these shards are the full law set.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Makefile always exports PROOF_TIMEOUT; default 180 matches PROOF_TIMEOUT ?=.
TIMEOUT=${PROOF_TIMEOUT:?PROOF_TIMEOUT must be set (Makefile passes it)}
FLAGS=${PROOF_FLAGS:-}
python3 scripts/split-proof.py

fail=0
n=0
for proof in build/proof/proof-*.bend; do
  # Unmatched globs must not count as a shard.
  test -e "$proof" || continue
  n=$((n + 1))
  echo "proof shard $proof"
  # shellcheck disable=SC2086
  if ! timeout -k 10 "$TIMEOUT" bend $FLAGS "$proof"; then
    echo "proof shard failed: $proof" >&2
    fail=1
  fi
done

count=$(grep -h '^law ' build/proof/laws-*.bend | wc -l | tr -d ' ')
expected=$(grep -c '^law ' LAWS.bend)
if [ "$count" -ne "$expected" ]; then
  echo "proof shards discharged $count laws, expected $expected" >&2
  exit 1
fi

if [ "$n" -eq 0 ]; then
  echo "proof shards: none generated" >&2
  exit 1
fi

exit "$fail"
