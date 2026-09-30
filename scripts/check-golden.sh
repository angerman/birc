#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# A matching token is not success unless the program also exits successfully.
set -eu
token=$1
shift
log_dir=${GOLDEN_LOG_DIR:-build/test-logs}
mkdir -p "$log_dir"
log=$(mktemp "$log_dir/golden.XXXXXX")
status=0
timeout "${TEST_TIMEOUT_SECONDS:-30}" "$@" >"$log" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
    cat "$log" >&2
    printf 'golden: command exited %s; log: %s\n' "$status" "$log" >&2
    exit "$status"
fi
if ! grep -F -x -q -- "$token" "$log"; then
    cat "$log" >&2
    printf 'golden: missing token %s; log: %s\n' "$token" "$log" >&2
    exit 1
fi
printf '%s\n' "$token"
