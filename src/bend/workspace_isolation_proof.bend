# SPDX-License-Identifier: Apache-2.0
# Proof-only complete Workspace isolation proposition and proof.
import Base
import ./buffer.bend as Cl
import ./session.bend as Sess
import ./session_drafts.bend as AD
import ./drafts.bend as Drafts
import ./server_key.bend as Key
import ./server_id.bend as Sid
import ./workspace.bend as WS
import ./workspace_isolation_selectors.bend as Sel
import ./workspace_isolation_route.bend as Rt
import ./workspace_isolation_arithmetic.bend as Arith

# Both B steps use this exact branch-preserving dispatch with an OPEN cap.
# In the actual law each selected B id is s1, and cap is its ORIGINAL ceiling.
def step.part(+cap: Nat, +parts: List<&2, WS.Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, WS.SlotEpoch>, +keys: Sess.Keys, +p: WS.Part) -> WS.Workspace & Sid.RoutedCmd & Bool:
  match p:
    case WS.Part{+id, +gen, +scope, +st}:
      Rt.route.guarded(cap, parts, cur, id, gen, scope, rt, AD.step_keys(AD.with_drafts(st, ds, id), keys), ds)

def step.found(+cap: Nat, +parts: List<&2, WS.Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, WS.SlotEpoch>, +keys: Sess.Keys, +got: Maybe<&2, WS.Part>) -> WS.Workspace & Sid.RoutedCmd & Bool:
  match got:
    case None{}: (WS.Workspace{parts, cur, ds, rt}, Sid.drop_for(cur), False{})
    case Some{+p}: step.part(cap, parts, cur, ds, rt, keys, p)

def step.at(+cap: Nat, +ws: WS.Workspace, +keys: Sess.Keys) -> WS.Workspace & Sid.RoutedCmd & Bool:
  match ws:
    case WS.Workspace{+parts, +cur, +ds, +rt}:
      step.found(cap, parts, cur, ds, rt, keys, WS.find_part.go(parts, cur))

def scope_a() -> Sid.Scope:
  Sid.Scope{"a.example", 6697, False{}}

def scope_b() -> Sid.Scope:
  Sid.Scope{"b.example", 6697, False{}}

def initial_parts(+q: Nat) -> List<&2, WS.Part>:
  WS.Part{WS.s1(), 0, scope_b(), Sel.online_at("b.example", "#b", q)} <> WS.Part{WS.s0(), 0, scope_a(), Sel.online_at("a.example", "#a", 0n)} <> Nil{}

# Project complete ACTUAL AD results; do not rebuild any Session/Client.
def a_session() -> Sess.Session:
  AD.ad_session(AD.do_step.got(Sel.a_trip()))

def b_session(q: Nat) -> Sess.Session:
  AD.ad_session(AD.do_step.got(Sel.b_first(q)))

def a_parts(+q: Nat) -> List<&2, WS.Part>:
  WS.Part{WS.s1(), 0, scope_b(), Sel.online_at("b.example", "#b", q)} <> WS.Part{WS.s0(), 0, scope_a(), a_session()} <> Nil{}

def a_workspace(+q: Nat) -> WS.Workspace:
  WS.Workspace{a_parts(q), WS.s0(), Sel.post_drafts(Sel.a_trip()), Nil{}}

def b_parts(+q: Nat) -> List<&2, WS.Part>:
  WS.Part{WS.s1(), 0, scope_b(), b_session(q)} <> WS.Part{WS.s0(), 0, scope_a(), a_session()} <> Nil{}

def b_workspace(+q: Nat) -> WS.Workspace:
  WS.Workspace{b_parts(q), WS.s1(), Sel.post_drafts(Sel.b_first(q)), Nil{}}

# These complete contexts retain BOTH B steps and all three observations.
# Workspace is Data; each actual returned affine route product is consumed once.
def after_b1(+cb: Nat, +w: WS.Workspace) -> Bool:
  WS.isolation_ok.step(w, step.at(cb, w, Sess.keys_enter("/join #extra")))

def after_a(+cb: Nat, +wa: WS.Workspace) -> Bool:
  after_b1(cb, WS.do_step.got(step.at(cb, WS.do_switch(wa, WS.s1()), Sess.keys_enter("/join #b"))))

# Derived normal-state/lookup equalities. q and cb remain OPEN while checked.
# Metadata is preserved by the actual non-Dial JOIN command derivation here,
# not by an assumed tuple or reconstructed two-buffer Client.
def a_normal_state(+q: Nat) -> {WS.do_step.got(Rt.route.normal(initial_parts(q), WS.s0(), WS.s0(), 0, scope_a(), Nil{}, Sel.a_trip())) == a_workspace(q) : WS.Workspace}:
  {==}

def b_first_lookup(+q: Nat, +cb: Nat) -> {step.at(cb, WS.do_switch(a_workspace(q), WS.s1()), Sess.keys_enter("/join #b")) == Rt.route.guarded(cb, a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_first(q), Sel.post_drafts(Sel.a_trip())) : WS.Workspace & Sid.RoutedCmd & Bool}:
  {==}

def a_handoff(+q: Nat, +cb: Nat) -> {after_a(cb, a_workspace(q)) == after_b1(cb, WS.do_step.got(Rt.route.guarded(cb, a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_first(q), Sel.post_drafts(Sel.a_trip())))) : Bool}:
  Equal.cong(WS.Workspace & Sid.RoutedCmd & Bool, Bool, trip => after_b1(cb, WS.do_step.got(trip)), step.at(cb, WS.do_switch(a_workspace(q), WS.s1()), Sess.keys_enter("/join #b")), Rt.route.guarded(cb, a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_first(q), Sel.post_drafts(Sel.a_trip())), b_first_lookup(q, cb))

def b_normal_state(+q: Nat) -> {WS.do_step.got(Rt.route.normal(a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_first(q))) == b_workspace(q) : WS.Workspace}:
  {==}

def b_second_lookup(+q: Nat, +cb: Nat) -> {step.at(cb, b_workspace(q), Sess.keys_enter("/join #extra")) == Rt.route.guarded(cb, b_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_second.from(Sel.b_first(q)), Sel.post_drafts(Sel.b_first(q))) : WS.Workspace & Sid.RoutedCmd & Bool}:
  {==}

def b_handoff(+q: Nat, +cb: Nat) -> {after_b1(cb, b_workspace(q)) == WS.isolation_ok.step(b_workspace(q), Rt.route.guarded(cb, b_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_second.from(Sel.b_first(q)), Sel.post_drafts(Sel.b_first(q)))) : Bool}:
  Equal.cong(WS.Workspace & Sid.RoutedCmd & Bool, Bool, trip => WS.isolation_ok.step(b_workspace(q), trip), step.at(cb, b_workspace(q), Sess.keys_enter("/join #extra")), Rt.route.guarded(cb, b_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_second.from(Sel.b_first(q)), Sel.post_drafts(Sel.b_first(q))), b_second_lookup(q, cb))

# ALL THREE original observations on the SAME actual final tuple, with q OPEN.
# The actual final tuple supplies every original observation.
def observations(+q: Nat) -> {WS.isolation_ok.step(b_workspace(q), Rt.route.normal(b_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_second.from(Sel.b_first(q)))) == True{} : Bool}:
  {==}

# Complete generalized proof. Each guard is still present in its proposition.
# Two independent B proof arguments avoid relying on any live-proof copying.
def whole_case(+q: Nat, +ca: Nat, +cb: Nat, bound_a: {Bool.not(Nat.is_lt(0n, ca)) == False{} : Bool}, bound_b1: {Bool.not(Nat.is_lt(q, cb)) == False{} : Bool}, bound_b2: {Bool.not(Nat.is_lt(q, cb)) == False{} : Bool}) -> {after_a(cb, WS.do_step.got(Rt.route.guarded(ca, initial_parts(q), WS.s0(), WS.s0(), 0, scope_a(), Nil{}, Sel.a_trip(), Drafts.empty()))) == True{} : Bool}:
  %Equal.sym(WS.Workspace & Sid.RoutedCmd & Bool, Rt.route.guarded(ca, initial_parts(q), WS.s0(), WS.s0(), 0, scope_a(), Nil{}, Sel.a_trip(), Drafts.empty()), Rt.route.normal(initial_parts(q), WS.s0(), WS.s0(), 0, scope_a(), Nil{}, Sel.a_trip()), Rt.a_route(ca, initial_parts(q), WS.s0(), WS.s0(), 0, scope_a(), Nil{}, Drafts.empty(), bound_a)) : {after_a(cb, WS.do_step.got(_)) == True{} : Bool}
  %Equal.sym(WS.Workspace, WS.do_step.got(Rt.route.normal(initial_parts(q), WS.s0(), WS.s0(), 0, scope_a(), Nil{}, Sel.a_trip())), a_workspace(q), a_normal_state(q)) : {after_a(cb, _) == True{} : Bool}
  %Equal.sym(Bool, after_a(cb, a_workspace(q)), after_b1(cb, WS.do_step.got(Rt.route.guarded(cb, a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_first(q), Sel.post_drafts(Sel.a_trip())))), a_handoff(q, cb)) : {_ == True{} : Bool}
  %Equal.sym(WS.Workspace & Sid.RoutedCmd & Bool, Rt.route.guarded(cb, a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_first(q), Sel.post_drafts(Sel.a_trip())), Rt.route.normal(a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_first(q)), Rt.b_first_route(q, cb, a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.post_drafts(Sel.a_trip()), bound_b1)) : {after_b1(cb, WS.do_step.got(_)) == True{} : Bool}
  %Equal.sym(WS.Workspace, WS.do_step.got(Rt.route.normal(a_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_first(q))), b_workspace(q), b_normal_state(q)) : {after_b1(cb, _) == True{} : Bool}
  %Equal.sym(Bool, after_b1(cb, b_workspace(q)), WS.isolation_ok.step(b_workspace(q), Rt.route.guarded(cb, b_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_second.from(Sel.b_first(q)), Sel.post_drafts(Sel.b_first(q)))), b_handoff(q, cb)) : {_ == True{} : Bool}
  %Equal.sym(WS.Workspace & Sid.RoutedCmd & Bool, Rt.route.guarded(cb, b_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_second.from(Sel.b_first(q)), Sel.post_drafts(Sel.b_first(q))), Rt.route.normal(b_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.b_second.from(Sel.b_first(q))), Rt.b_second_route(q, cb, b_parts(q), WS.s1(), WS.s1(), 0, scope_b(), Nil{}, Sel.post_drafts(Sel.b_first(q)), bound_b2)) : {WS.isolation_ok.step(b_workspace(q), _) == True{} : Bool}
  observations(q)

# Original unbounded-Nat floor and strict-ceiling proofs. No machine seed.
def floor_zero(+base: Nat) -> {WS.nat_max(base, WS.nat_max(0n, 0n)) == base : Nat}:
  match base:
    case 0n: {==}
    case 1n+p: {==}

def range_positive() -> {Nat.is_lt(0n, WS.id_range()) == True{} : Bool}:
  {==}

def prefix_positive(+prefix: Nat, +range: Nat, positive: {Nat.is_lt(0n, range) == True{} : Bool}) -> {Nat.is_lt(prefix, Nat.add(prefix, range)) == True{} : Bool}:
  %Arith.add_zero(prefix) : {Nat.is_lt(_, Nat.add(prefix, range)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_lt(Nat.add(prefix, 0n), Nat.add(prefix, range)), Nat.is_lt(0n, range), Arith.prefix_lt(prefix, 0n, range)) : {_ == True{} : Bool}
  positive

def original_a_bound() -> {Bool.not(Nat.is_lt(0n, Nat.add(WS.id_base(WS.s0()), WS.id_range()))) == False{} : Bool}:
  {==}

def original_b_bound() -> {Bool.not(Nat.is_lt(WS.nat_max(WS.id_base(WS.s1()), WS.nat_max(0n, 0n)), Nat.add(WS.id_base(WS.s1()), WS.id_range()))) == False{} : Bool}:
  %Equal.sym(Nat, WS.nat_max(WS.id_base(WS.s1()), WS.nat_max(0n, 0n)), WS.id_base(WS.s1()), floor_zero(WS.id_base(WS.s1()))) : {Bool.not(Nat.is_lt(_, Nat.add(WS.id_base(WS.s1()), WS.id_range()))) == False{} : Bool}
  %Equal.sym(Bool, Nat.is_lt(WS.id_base(WS.s1()), Nat.add(WS.id_base(WS.s1()), WS.id_range())), True{}, prefix_positive(WS.id_base(WS.s1()), WS.id_range(), range_positive())) : {Bool.not(_) == False{} : Bool}
  {==}

# Original fx_pair/fx_online gives [B,A], current s0, empty drafts/retired.
# Sessions initialize BEFORE seeding. A's floor is 0; B's is max(b,max(0,0)).
# after_a keeps A JOIN, switch s1, B JOIN and extra B JOIN, with all three
# original observations. Every routed leaf preserves slot IDs; therefore
# the open caps specialize to the original post-AD id_ceiling expressions.
# ACTUAL complete proposition spelling. Do not replace this endpoint with
# {WS.isolation_ok()==True}: that would restore the old nullary conversion seam.
# R=id_range.pow2(44), b=id_base(s1), q=expanded seed_floor(s1,0,0).
law case_b_isolation:
  {after_a(Nat.add(WS.id_base(WS.s1()), WS.id_range()), WS.do_step.got(Rt.route.guarded(Nat.add(WS.id_base(WS.s0()), WS.id_range()), initial_parts(WS.nat_max(WS.id_base(WS.s1()), WS.nat_max(0n, 0n))), WS.s0(), WS.s0(), 0, scope_a(), Nil{}, Sel.a_trip(), Drafts.empty()))) == True{} : Bool}

def case_b_isolation():
  whole_case(WS.nat_max(WS.id_base(WS.s1()), WS.nat_max(0n, 0n)), Nat.add(WS.id_base(WS.s0()), WS.id_range()), Nat.add(WS.id_base(WS.s1()), WS.id_range()), original_a_bound(), original_b_bound(), original_b_bound())
