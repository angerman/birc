#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
runner=scripts/check-golden.sh
sh "$runner" runner=ok sh -c 'printf "runner=ok\n"; exit 0'
status=0
sh "$runner" runner=ok sh -c 'printf "runner=ok\n"; exit 42' || status=$?
test "$status" -eq 42
status=0
sh "$runner" runner=ok sh -c 'printf "wrong-token\n"' || status=$?
test "$status" -eq 1
status=0
TEST_TIMEOUT_SECONDS=1 sh "$runner" runner=ok sh -c 'printf "runner=ok\n"; sleep 10' || status=$?
test "$status" -eq 124
printf 'golden_runner=ok\n'
