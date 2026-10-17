#!/bin/sh
# Before/after structural diff for the 2026-10-16 simplification review.
# Read-only: uses `git show`/`git ls-tree`/`git grep` only, never touches the
# working tree and never builds.
#
#   Usage: sh scripts/review-baseline-diff.sh [baseline-rev]
#
# Defaults to the review baseline 208f7c9. Run it from a birc checkout.
#
# The effect count is taken from the authoritative source -- `io_eff(CID_`
# registrations in src/ffi -- not from docs/FFI.md prose, which is exactly what
# drifted in 8aa65ec (the table was regenerated to 42 rows while two prose
# sentences kept saying 44).
set -u
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 2
BASE=${1:-208f7c9}
NOW=$(git rev-parse --short HEAD)

lines_at() { # <rev> <path> -> line count, 0 if absent
  git show "$1:$2" 2>/dev/null | wc -l | tr -d ' '
}

total_lines() { # <rev> <grep-pattern>
  t=0
  for f in $(git ls-tree -r --name-only "$1" | grep -E "$2"); do
    t=$((t + $(lines_at "$1" "$f")))
  done
  echo "$t"
}

count_at() { # <rev> -> distinct CIDs actually registered by io_eff in src/ffi
  git grep -hoE 'io_eff\(\s*CID_[A-Z0-9_]+' "$1" -- 'src/ffi/*.c' 'src/ffi/*.h' 2>/dev/null \
    | grep -oE 'CID_[A-Z0-9_]+' | sort -u | wc -l | tr -d ' '
}

cids_at() { # <rev> <outfile> -> every distinct CID_ token appearing in src/ffi
  git grep -hoE 'CID_[A-Z0-9_]+' "$1" -- 'src/ffi/*.c' 'src/ffi/*.h' 2>/dev/null \
    | sort -u > "$2"
}

echo "baseline=$BASE  final=$NOW"
echo

echo "=== src/bend total ==="
b_n=$(git ls-tree -r --name-only "$BASE" | grep -cE '^src/bend/.*\.bend$')
n_n=$(git ls-tree -r --name-only "$NOW"  | grep -cE '^src/bend/.*\.bend$')
b_tot=$(total_lines "$BASE" '^src/bend/.*\.bend$')
n_tot=$(total_lines "$NOW"  '^src/bend/.*\.bend$')
printf 'modules %s -> %s   lines %s -> %s   delta %+d\n' \
  "$b_n" "$n_n" "$b_tot" "$n_tot" "$((n_tot - b_tot))"
echo

echo "=== largest modules, before -> after ==="
printf '%-22s %8s %8s %9s\n' module base final delta
for f in session view client submit buffer wsnet workspace irc net cards media auth; do
  p="src/bend/$f.bend"
  a=$(lines_at "$BASE" "$p"); c=$(lines_at "$NOW" "$p")
  [ "$a" = 0 ] && [ "$c" = 0 ] && continue
  printf '%-22s %8s %8s %+9d\n' "$f.bend" "$a" "$c" "$((c - a))"
done
echo

echo "=== modules that disappeared (deleted/merged) ==="
for f in $(git ls-tree -r --name-only "$BASE" | grep -E '^src/bend/.*\.bend$'); do
  git cat-file -e "$NOW:$f" 2>/dev/null || echo "  - $f ($(lines_at "$BASE" "$f") lines)"
done
echo "=== modules that appeared ==="
for f in $(git ls-tree -r --name-only "$NOW" | grep -E '^src/bend/.*\.bend$'); do
  git cat-file -e "$BASE:$f" 2>/dev/null || echo "  + $f ($(lines_at "$NOW" "$f") lines)"
done
echo

echo "=== tests/bend total ==="
t_bn=$(git ls-tree -r --name-only "$BASE" | grep -cE '^tests/bend/.*\.bend$')
t_tn=$(git ls-tree -r --name-only "$NOW"  | grep -cE '^tests/bend/.*\.bend$')
t_b=$(total_lines "$BASE" '^tests/bend/.*\.bend$')
t_n=$(total_lines "$NOW"  '^tests/bend/.*\.bend$')
printf 'files %s -> %s   lines %s -> %s   delta %+d\n' \
  "$t_bn" "$t_tn" "$t_b" "$t_n" "$((t_n - t_b))"
echo

echo "=== C FFI surface ==="
printf 'src/ffi/*.c files %s -> %s\n' \
  "$(git ls-tree -r --name-only "$BASE" | grep -cE '^src/ffi/.*\.c$')" \
  "$(git ls-tree -r --name-only "$NOW"  | grep -cE '^src/ffi/.*\.c$')"
printf 'src/ffi C/H lines  %s -> %s\n' \
  "$(total_lines "$BASE" '^src/ffi/.*\.[ch]$')" \
  "$(total_lines "$NOW"  '^src/ffi/.*\.[ch]$')"
printf 'io_eff registrations %s -> %s\n' "$(count_at "$BASE")" "$(count_at "$NOW")"
# Temp files, not process substitution: this runs under /bin/sh, where `<(...)`
# is not available in POSIX mode.
CB=$(mktemp) || exit 2
CN=$(mktemp) || exit 2
trap 'rm -f "$CB" "$CN"' EXIT INT TERM
cids_at "$BASE" "$CB"
cids_at "$NOW" "$CN"
echo "  removed CIDs:"
comm -23 "$CB" "$CN" | sed 's/^/    - /'
echo "  added CIDs:"
comm -13 "$CB" "$CN" | sed 's/^/    + /'
echo

echo "=== proof invariant (must stay equal on both sides) ==="
printf 'LAWS.bend laws   %s -> %s\n' \
  "$(git show "$BASE:LAWS.bend" | grep -c '^law ')" \
  "$(git show "$NOW:LAWS.bend"  | grep -c '^law ')"
printf 'PROOF.bend defs  %s -> %s\n' \
  "$(git show "$BASE:PROOF.bend" | grep -c '^def Laws\.')" \
  "$(git show "$NOW:PROOF.bend"  | grep -c '^def Laws\.')"
echo

echo "=== whole-repo churn since baseline ==="
git diff --shortstat "$BASE" "$NOW"
printf 'commits: %s\n' "$(git rev-list --count "$BASE..$NOW")"
