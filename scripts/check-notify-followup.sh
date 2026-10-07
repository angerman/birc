#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Lightweight static pins for the notify follow-up repairs (no compiler).
set -euo pipefail

fail=0
pass() { printf 'pin ok: %s\n' "$1"; }
miss() { printf 'pin FAIL: %s\n' "$1"; fail=1; }
present() { # name file pattern...
  local name="$1" file="$2"; shift 2
  if grep -qF -- "$1" "$file"; then pass "$name"; else miss "$name ($1 missing in $file)"; fi
}
absent() { # name file pattern
  local name="$1" file="$2" pat="$3"
  if grep -qF -- "$pat" "$file"; then miss "$name ($pat present in $file)"; else pass "$name"; fi
}

WS=src/bend/wsnet.bend
HELD=tests/bend/notify_held.bend
HELD808=tests/bend/notify_held_blocked.bend
BIND=tests/bend/notify_binding_gates.bend
GUARDS=tests/bend/notify_followup_guards.bend
ATTR=tests/bend/notify_attr_blocked.bend
FULL=tests/bend/notify_full.bend

# Repair 1: reconnect floor reconciles from the pre-accept snapshot.
present "r1 fresh pre/post owner" "$WS" "def ws_notify.fresh_nl_pre(+pre: Sess.Session, +post: Sess.Session)"
present "r1 scope gate" "$WS" "String.eq(Sess.notify_scope_of(pre), Sess.notify_scope_of(post))"
present "r1 fire threads pre/post" "$WS" "ws_notify.observed_pre(nnot, s, gen, pre, post"
present "r1 pre snapshot lookup" "$WS" "ws_net_painted.pre_parts(W.find_part(ws, s), post)"
present "r1 observed shim kept" "$WS" "def ws_notify.observed(+nnot: WsNotify, +s: Key.ServerId, +gen: U32, +pst: Sess.Session, +deliver: Bool)"
present "r1 guards file" "$GUARDS" "notify_followup_guards=ok"

# Repair 2: completions thread the received state, never reset nl_c.
if [ "$(git hash-object "$HELD808")" = "4c9da06e93f571dbce5d21195b5284edd1e51403" ]; then
  pass "r2 808 fixture byte-identical"
else
  miss "r2 808 fixture byte-identical"
fi
present "r2 808 chained negatives" "$HELD808" "def comp_wrong_chained()"
present "r2 808 received threading" "$HELD808" "def comp_received(+ticket: Nat, +endpoint: String)"
present "r2 held threads received" "$HELD" "def comp_received(+ticket: Nat, +endpoint: String)"
present "r2 held chained negatives" "$HELD" "def comp_wrong_chained()"
absent "r2 held no reconstituted fifo" "$HELD" "comp_fifo"
present "r2 ws chained guard" "$GUARDS" "def t_exact()"

# Repair 3: barrier routes through production spawn_ticket/completed.
present "r3 binding production spawn" "$BIND" "ws_notify.spawn_ticket"
absent "r3 binding no direct NIO spawn" "$BIND" "notify_live_spawn"
present "r3 binding threads received d0" "$BIND" "completed(nn0, g1_wsf(), s0(), t1, e1"
present "r3 attr qual file" "$ATTR" "notify_attr_blocked=ok"
present "r3 attr production spawn" "$ATTR" "ws_notify.spawn_ticket"
absent "r3 attr no direct NIO spawn" "$ATTR" "notify_live_spawn"
present "r3 attr START barrier" "$ATTR" "await_start.go(40n, h, start_a())"
present "r3 attr release latch" "$ATTR" "release_worker(h)"

# Kept positives: 120 production behavior retained, nothing weakened.
if [ "$(grep -c "Q4-HELD" "$FULL")" = "6" ]; then
  pass "positives six Q4 flips retained"
else
  miss "positives six Q4 flips retained"
fi
present "positives global lease owner" "$WS" "def ws_notify.completed(+nnot: WsNotify"
present "positives spawn owner" "$WS" "def ws_notify.spawn_ticket(+lease: Maybe<&2, WsNotifyLease>"
present "positives binding gates intact" "$BIND" "g1 steal hands carol"
if grep "BIRC_NOTIFY_HELPER_UNREL" Makefile | grep -q "notify_held_blocked"; then
  pass "positives 808 UNREL recipe kept"
else
  miss "positives 808 UNREL recipe kept"
fi
if grep "BIRC_NOTIFY_HELPER_UNREL" Makefile | grep -q -- "-lt 18" && grep "BIRC_NOTIFY_HELPER_UNREL" Makefile | grep -q -- "-lt 2"; then
  pass "positives 808 main18/negative2 recipe kept"
else
  miss "positives 808 main18/negative2 recipe kept"
fi

# Promoted gates must be defined and registered after their runtime/static admission.
registered_in_aggregate() {
  grep -E '^(test|test-pty|test-review-pure|check):' |
    sed 's/#.*//' |
    grep -E "(^|[[:space:]])$1([[:space:]]|$)" >/dev/null
}
if printf '%s\n' 'test-review-pure: test-notify-followup-guards' |
    registered_in_aggregate test-notify-followup-guards; then
  pass "registration exact positive control"
else
  miss "registration exact positive control"
fi
for row in 'test-review-pure: test-notify-followup-guards-extra' \
           'test-notify-followup-guards: other' \
           'test-review-pure: # test-notify-followup-guards'; do
  if printf '%s\n' "$row" | registered_in_aggregate test-notify-followup-guards; then
    miss "registration prefix/standalone/comment negative control"
  else
    pass "registration prefix/standalone/comment negative control"
  fi
done
for t in test-notify-followup-guards test-notify-attr-blocked test-notify-followup-static; do
  if grep -qE "^${t}:" Makefile; then pass "target $t defined"; else miss "target $t defined"; fi
  if registered_in_aggregate "$t" <Makefile; then
    pass "target $t registered"
  else
    miss "target $t registered"
  fi
done
if grep -q "notify_followup_guards=ok" Makefile && grep -q "notify_attr_blocked=ok" Makefile; then
  pass "targets check goldens"
else
  miss "targets check goldens"
fi

if [ "$fail" -ne 0 ]; then
  printf 'notify-followup static: FAIL\n'
  exit 1
fi
printf 'notify-followup static: ok\n'
