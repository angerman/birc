#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Fail closed if LAWS.bend or PROOF.bend import closures reach IO/effect modules.
#
# Verify:
#   make lint-laws-io
#   # or: sh scripts/check-laws-io.sh
# Self-test (synthetic notify_io import must fail):
#   sh scripts/check-laws-io.sh --self-test
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# AGENTS.md IO/effect row: exact names plus *_io / *_live / *_worker / *_runtime.
# dns.bend is the effect module; dns_wire.bend / dns_query.bend stay pure.
forbidden_name() {
  case "$1" in
    actor.bend|app.bend|auth_bridge.bend|net.bend|wsnet.bend|timui.bend|dns.bend|tls.bend|transport.bend|clock.bend)
      return 0
      ;;
    *_io.bend|*_live.bend|*_worker.bend|*_runtime.bend)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Transitive .bend import closure (same rules as scripts/bend-deps.sh).
closure() {
  entry=$1
  python3 - "$entry" <<'PY'
import os, sys
from pathlib import Path

def fail(msg):
    print(f"check-laws-io: {msg}", file=sys.stderr)
    sys.exit(1)

def import_spec(line):
    stripped = line.strip()
    if not stripped.startswith("import "):
        return None
    spec = stripped[len("import "):].strip()
    if not spec or spec.startswith("#"):
        return None
    if spec[0] in "\"'":
        quote = spec[0]
        end = spec.find(quote, 1)
        if end < 0:
            return None
        spec = spec[1:end]
    else:
        spec = spec.split()[0]
    if spec == "Base" or spec.startswith("Base/"):
        return None
    if not spec.endswith(".bend"):
        return None
    return spec

def closure(entry):
    entry = Path(entry)
    if not entry.is_file():
        fail(f"missing entry {entry}")
    seen = set()
    stack = [entry.resolve()]
    files = []
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        if not current.is_file():
            fail(f"missing import target {current}")
        files.append(current)
        text = current.read_text(encoding="utf-8", errors="replace")
        for line in text.splitlines():
            spec = import_spec(line)
            if spec is None:
                continue
            nxt = (current.parent / spec).resolve()
            if not nxt.is_file():
                fail(f"{current} imports missing {spec}")
            stack.append(nxt)
    return files

for path in closure(sys.argv[1]):
    print(path.as_posix())
PY
}

check_entry() {
  entry=$1
  label=$2
  hits=
  # shellcheck disable=SC2046
  for path in $(closure "$entry"); do
    base=$(basename "$path")
    if forbidden_name "$base"; then
      hits="$hits $base"
    fi
  done
  if [ -n "$hits" ]; then
    printf '%s\n' "check-laws-io: $label import closure hits IO/effect modules:$hits" >&2
    return 1
  fi
  printf '%s\n' "check-laws-io: $label ok"
  return 0
}

self_test() {
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT INT TERM
  printf '%s\n' 'import Base' 'import ./src/bend/notify_io.bend as N' >"$tmp/bad.bend"
  mkdir -p "$tmp/src/bend"
  # Minimal stub so the walker can resolve the forbidden import.
  printf '%s\n' 'import Base' >"$tmp/src/bend/notify_io.bend"
  if (
    cd "$tmp"
    check_entry bad.bend "synthetic" >/dev/null 2>&1
  ); then
    printf '%s\n' 'check-laws-io: self-test expected synthetic notify_io import to fail' >&2
    return 1
  fi
  printf '%s\n' 'check-laws-io: self-test ok (synthetic notify_io rejected)'
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  -h|--help)
    sed -n '2,12p' "$0"
    ;;
  "")
    check_entry LAWS.bend LAWS.bend
    check_entry PROOF.bend PROOF.bend
    self_test
    ;;
  *)
    printf '%s\n' "usage: $0 [--self-test]" >&2
    exit 2
    ;;
esac
