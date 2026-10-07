# SPDX-License-Identifier: Apache-2.0
# Proof-only route transport for the actual Workspace JOIN fixture.
import Base
import ./buffer.bend as Cl
import ./session.bend as Sess
import ./session_drafts.bend as AD
import ./drafts.bend as Drafts
import ./server_key.bend as Key
import ./server_id.bend as Sid
import ./workspace.bend as WS
import ./workspace_isolation_selectors.bend as Sel

# Exact tripped/emit/routed expansion with ONLY its ceiling left open.
# The original routed.pick still owns both acceptance and rollback leaves.
def route.guarded(+ceiling: Nat, +parts: List<&2, WS.Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +rt: List<&2, WS.SlotEpoch>, trip: AD.AD & Sess.NetCmd & Bool, +ds_orig: Drafts.Drafts) -> WS.Workspace & Sid.RoutedCmd & Bool:
  match trip:
    case (+ad, cmd, halt):
      +st = AD.ad_session(ad)
      +ds = AD.ad_drafts(ad)
      WS.step_keys.routed.pick(Bool.not(Nat.is_lt(Cl.log_seq_of(Sess.session_cl(st)), ceiling)), parts, cur, id, gen, scope, st, ds, rt, cmd, halt, ds_orig)

# Same actual tuple/payloads, after a proved guard reduction to False.
def route.normal(+parts: List<&2, WS.Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +rt: List<&2, WS.SlotEpoch>, trip: AD.AD & Sess.NetCmd & Bool) -> WS.Workspace & Sid.RoutedCmd & Bool:
  match trip:
    case (+ad, cmd, halt):
      +st = AD.ad_session(ad)
      +ds = AD.ad_drafts(ad)
      WS.step_keys.routed.normal(parts, cur, id, gen, scope, st, ds, rt, cmd, halt)

law route_transport:
  for +ceiling: Nat
  for +parts: List<&2, WS.Part>
  for +cur: Key.ServerId
  for +id: Key.ServerId
  for +gen: U32
  for +scope: Sid.Scope
  for +rt: List<&2, WS.SlotEpoch>
  for trip: AD.AD & Sess.NetCmd & Bool
  for +ds_orig: Drafts.Drafts
  for e: {Bool.not(Nat.is_lt(Sel.post_seq(trip), ceiling)) == False{} : Bool}
  {route.guarded(ceiling, parts, cur, id, gen, scope, rt, trip, ds_orig) == route.normal(parts, cur, id, gen, scope, rt, trip) : WS.Workspace & Sid.RoutedCmd & Bool}

def route_transport(ceiling, parts, cur, id, gen, scope, rt, trip, ds_orig, e):
  match trip:
    case (+ad, cmd, halt):
      +st = AD.ad_session(ad)
      +ds = AD.ad_drafts(ad)
      %Equal.sym(Bool, Bool.not(Nat.is_lt(Cl.log_seq_of(Sess.session_cl(st)), ceiling)), False{}, e) : {WS.step_keys.routed.pick(_, parts, cur, id, gen, scope, st, ds, rt, cmd, halt, ds_orig) == WS.step_keys.routed.normal(parts, cur, id, gen, scope, st, ds, rt, cmd, halt) : WS.Workspace & Sid.RoutedCmd & Bool}
      {==}

# An explicit arithmetic proof, not an assumed AD admission witness, is the
# remaining input. Sequence equality comes from the actual AD selectors.
def guard_from_sequence(+seq: Nat, +q: Nat, +ceiling: Nat, sequence: {seq == q : Nat}, bound: {Bool.not(Nat.is_lt(q, ceiling)) == False{} : Bool}) -> {Bool.not(Nat.is_lt(seq, ceiling)) == False{} : Bool}:
  %Equal.sym(Nat, seq, q, sequence) : {Bool.not(Nat.is_lt(_, ceiling)) == False{} : Bool}
  bound

def a_route(+ceiling: Nat, +parts: List<&2, WS.Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +rt: List<&2, WS.SlotEpoch>, +ds_orig: Drafts.Drafts, bound: {Bool.not(Nat.is_lt(0n, ceiling)) == False{} : Bool}) -> {route.guarded(ceiling, parts, cur, id, gen, scope, rt, Sel.a_trip(), ds_orig) == route.normal(parts, cur, id, gen, scope, rt, Sel.a_trip()) : WS.Workspace & Sid.RoutedCmd & Bool}:
  route_transport(ceiling, parts, cur, id, gen, scope, rt, Sel.a_trip(), ds_orig, guard_from_sequence(Sel.post_seq(Sel.a_trip()), 0n, ceiling, Sel.a_actual_post_sequence(), bound))

def b_first_route(+q: Nat, +ceiling: Nat, +parts: List<&2, WS.Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +rt: List<&2, WS.SlotEpoch>, +ds_orig: Drafts.Drafts, bound: {Bool.not(Nat.is_lt(q, ceiling)) == False{} : Bool}) -> {route.guarded(ceiling, parts, cur, id, gen, scope, rt, Sel.b_first(q), ds_orig) == route.normal(parts, cur, id, gen, scope, rt, Sel.b_first(q)) : WS.Workspace & Sid.RoutedCmd & Bool}:
  route_transport(ceiling, parts, cur, id, gen, scope, rt, Sel.b_first(q), ds_orig, guard_from_sequence(Sel.post_seq(Sel.b_first(q)), q, ceiling, Sel.b_first_actual_post_sequence(q), bound))

def b_second_route(+q: Nat, +ceiling: Nat, +parts: List<&2, WS.Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +rt: List<&2, WS.SlotEpoch>, +ds_orig: Drafts.Drafts, bound: {Bool.not(Nat.is_lt(q, ceiling)) == False{} : Bool}) -> {route.guarded(ceiling, parts, cur, id, gen, scope, rt, Sel.b_second.from(Sel.b_first(q)), ds_orig) == route.normal(parts, cur, id, gen, scope, rt, Sel.b_second.from(Sel.b_first(q))) : WS.Workspace & Sid.RoutedCmd & Bool}:
  route_transport(ceiling, parts, cur, id, gen, scope, rt, Sel.b_second.from(Sel.b_first(q)), ds_orig, guard_from_sequence(Sel.post_seq(Sel.b_second.from(Sel.b_first(q))), q, ceiling, Sel.b_second_actual_post_sequence(q), bound))
