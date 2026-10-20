# SPDX-License-Identifier: Apache-2.0
# Multiserver workspace partitions (pure).
#
# ADAPTER BOUNDARY (branch adapter/session-workspace-drafts-multiserver, from
# parent HEAD ca30774): per-server partitions over Session + the shared
# server-scoped Drafts store, with explicit ServerId + generation routing.
# Parent owns merges; this file is new and disjoint by construction. FROZEN
# at parent HEAD (signatures never edited here): Drafts, server_key,
# server_id, ipv6. Session/server_id/drafts/session_drafts are consumed,
# never modified, so each partition keeps today's single-server bounds
# (16 buffers, bounded plans, 512-byte wire cap) and semantics (reconnect
# dividers, global IDs, unread/alerts, scroll anchors).
#
# Wiring contract:
# - At most Key.MAX_SERVERS (4) parts; ids are the canonical Key.ServerId.
#   Allocation takes the lowest free slot and fails closed when full; the
#   final part cannot be removed. Removed slots leave bounded tombstones so
#   a reused id starts a non-reused incarnation (bumped past the retired
#   generation, seeded past the retired ID high-water mark); stale
#   Chunk/WriterDone/Intent from the old epoch drops.
# - step_keys routes one frame to the current part through the AD adapter
#   (focus gating, submit clearing, multiline, modal stash all apply) and
#   returns a server-tagged RoutedCmd. Generations mirror net.bend emit_cmd:
#   the workspace owns per-part generations starting at 0; a produced Dial
#   bumps and carries the new generation, Pump/Begin are rewritten to the
#   current one, and the dialed host/port refresh the part scope (host
#   spelling preserved; v6 refines at dial-plan time by the integrator).
# - Admission mirrors the actor guards exactly: cmd_admitted is
#   Sid.cmd_current (server + generation for Dial/Pump/Begin), msg_admitted
#   is Sid.evt_current, writer_done_acked is Sid.writer_done_current. Cross-
#   server, stale-generation, unknown-part, and invalid-id traffic is
#   dropped (fail closed); reader EOF never acknowledges shutdown.
# - replace_server models endpoint/slot replacement: Session's exact
#   endpoint transition (credentials cleared on any exact config mismatch,
#   buffers rebuilt unless exactly same), Drafts.replace_endpoint with the
#   same exact predicate, a refreshed scope, and a generation bump so all
#   in-flight traffic for the old epoch drops. Same-endpoint replacement
#   keeps drafts and credentials.
# - Credential checks use Sid.credential_scope_ok (exact host spelling and
#   bounded port); history checks use Sid.history_admits (case-insensitive
#   stored scope, like the archive reader) over per-part scope_key values.
#   History file IO stays in history_io.bend; this module owns only the
#   pure partition identity and admission.
# - Reconnect intent is generation- plus exact-endpoint-scoped via
#   Sid.reconnect_ok; dial_intent snapshots the current part epoch.
#
# Out of scope (flagged for the integrator, not widened here): Net/Actor IO
# threading and per-server channels; native Af/inet6 sockets, DNS, and TLS
# (see the ipv6-transport-adapter lane); native/PTY qualification.
#
# Layout is bottom-up: Bend forbids same-module forward references, so every
# helper precedes its callers and recursion recurs in the match arm.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client_laws.bend as CL
import ./frame.bend as Fr
import ./media.bend as M
import ./session.bend as Sess
import ./submit.bend as Sub
import ./session_drafts.bend as AD
import ./drafts.bend as Drafts
import ./server_key.bend as Key
import ./server_id.bend as Sid
import ./history.bend as Hist
import ./history_search.bend as Hs
import ./isupport.bend as Isupport

type Part is Data:
  Part{id: Key.ServerId, gen: U32, scope: Sid.Scope, st: Sess.Session}

type SlotEpoch is Data:
  SlotEpoch{id: Key.ServerId, gen: U32, mark: Nat}

type Workspace is Data:
  Workspace{parts: List<&2, Part>, current: Key.ServerId, drafts: Drafts.Drafts, retired: List<&2, SlotEpoch>}

def part_id(+p: Part) -> Key.ServerId:
  match p:
    case Part{+id, _, _, _}: id

def part_gen(+p: Part) -> U32:
  match p:
    case Part{_, +gen, _, _}: gen

def part_scope(+p: Part) -> Sid.Scope:
  match p:
    case Part{_, _, +scope, _}: scope

def part_session(+p: Part) -> Sess.Session:
  match p:
    case Part{_, _, _, +st}: st

def part_seq(+p: Part) -> Nat:
  match p:
    case Part{_, _, _, +st}: Cl.log_seq_of(Sess.session_cl(st))

def ws_parts(+ws: Workspace) -> List<&2, Part>:
  match ws:
    case Workspace{+parts, _, _, _}: parts

def ws_current(+ws: Workspace) -> Key.ServerId:
  match ws:
    case Workspace{_, +cur, _, _}: cur

def ws_drafts(+ws: Workspace) -> Drafts.Drafts:
  match ws:
    case Workspace{_, _, +ds, _}: ds

def ws_retired(+ws: Workspace) -> List<&2, SlotEpoch>:
  match ws:
    case Workspace{_, _, _, +rt}: rt

def ws_nparts(+ws: Workspace) -> Nat:
  List.length(&2, Part, ws_parts(ws))

# ---- part lookup --------------------------------------------------------

def find_part.pick(hit: Bool, +h: Part, +cont: Maybe<&2, Part>) -> Maybe<&2, Part>:
  match hit:
    case True{}: Some{h}
    case False{}: cont

def find_part.buf(+h: Part, +cont: Maybe<&2, Part>, +id: Key.ServerId) -> Maybe<&2, Part>:
  match h:
    case Part{+pid, _, _, _}:
      find_part.pick(Key.eq(pid, id), h, cont)

def find_part.go(+xs: List<&2, Part>, +id: Key.ServerId) -> Maybe<&2, Part>:
  match xs:
    case Nil{}: None{}
    case Con{+h, +t}:
      +cont = find_part.go(t, id)
      find_part.buf(h, cont, id)

def find_part(+ws: Workspace, +id: Key.ServerId) -> Maybe<&2, Part>:
  match ws:
    case Workspace{+parts, _, _, _}: find_part.go(parts, id)

def replace_part.pick(hit: Bool, +p: Part, +h: Part, +rest: List<&2, Part>) -> List<&2, Part>:
  match hit:
    case True{}: p <> rest
    case False{}: h <> rest

def replace_part.buf(+h: Part, +rest: List<&2, Part>, +id: Key.ServerId, +p: Part) -> List<&2, Part>:
  match h:
    case Part{+pid, _, _, _}:
      replace_part.pick(Key.eq(pid, id), p, h, rest)

def replace_part.go(+xs: List<&2, Part>, +id: Key.ServerId, +p: Part) -> List<&2, Part>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      +rest = replace_part.go(t, id, p)
      replace_part.buf(h, rest, id, p)

def replace_part(+ws: Workspace, +p: Part) -> Workspace:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      Workspace{replace_part.go(parts, part_id(p), p), cur, ds, rt}

def drop_part.pick(hit: Bool, +h: Part, +rest: List<&2, Part>) -> List<&2, Part>:
  match hit:
    case True{}: rest
    case False{}: h <> rest

def drop_part.buf(+h: Part, +rest: List<&2, Part>, +id: Key.ServerId) -> List<&2, Part>:
  match h:
    case Part{+pid, _, _, _}:
      drop_part.pick(Key.eq(pid, id), h, rest)

def drop_part.go(+xs: List<&2, Part>, +id: Key.ServerId) -> List<&2, Part>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      +rest = drop_part.go(t, id)
      drop_part.buf(h, rest, id)

def head_id(+xs: List<&2, Part>) -> Key.ServerId:
  match xs:
    case Nil{}: Key.first()
    case Con{+h, _}: part_id(h)

# ---- membership ---------------------------------------------------------

# Event-ID ranges: each server owns a disjoint 2^44 slice of Nat space, so
# admitted line IDs are globally unique across Sids by construction (s0
# keeps the single-server 0-based space; no stamped ID is ever renumbered).
# Stale traffic never stamps, so it never allocates.
#
# Seeding is monotonic per slot and has one owner: these constructors seed
# through seed_floor (max of range base, retired high-water mark, and any
# supplied rows); Buffer only advances from the seeded value and never
# reseeds. A re-added slot therefore starts above the retired incarnation's
# accepted IDs, so fresh events never reuse old ones, on the same endpoint
# or a changed one. History restore binds must seed the same way, at
# max(range base, restored max, live seq): binding never rewinds.
#
# IDs run base+1 .. base+2^44-1. Stamping at the cap would wrap into the
# sibling range, so inbound entries refuse a capped part fail-closed
# (dropped like stale: workspace unchanged, no outs); see seq_full.
def id_range.pow2(n: Nat) -> Nat:
  match n:
    case 0n: 1n
    case 1n+p: Nat.mul(id_range.pow2(p), 2n)

def id_range() -> Nat:
  id_range.pow2(44n)

def id_base(+id: Key.ServerId) -> Nat:
  match id:
    case Key.ServerId{+n}: Nat.mul(n, id_range())

def id_ceiling(+id: Key.ServerId) -> Nat:
  Nat.add(id_base(id), id_range())

def seq_full(+seq: Nat, +id: Key.ServerId) -> Bool:
  Bool.not(Nat.is_lt(Nat.add(seq, 1n), id_ceiling(id)))

def part_full(+st: Sess.Session, +id: Key.ServerId) -> Bool:
  seq_full(Cl.log_seq_of(Sess.session_cl(st)), id)

def ids_admitted(admitted: Bool, +st: Sess.Session, +id: Key.ServerId) -> Bool:
  match admitted:
    case False{}: False{}
    case True{}: Bool.not(part_full(st, id))

def nat_max.pick(lt: Bool, +a: Nat, +b: Nat) -> Nat:
  match lt:
    case True{}: b
    case False{}: a

def nat_max(+a: Nat, +b: Nat) -> Nat:
  nat_max.pick(Nat.is_lt(a, b), a, b)

def seed_floor(+id: Key.ServerId, +mark: Nat, +cur: Nat) -> Nat:
  nat_max(id_base(id), nat_max(mark, cur))

def seed_at(+st: Sess.Session, +id: Key.ServerId, +mark: Nat) -> Sess.Session:
  Sess.session_set_client(st, Cl.set_log_seq(Sess.session_cl(st), seed_floor(id, mark, Cl.log_seq_of(Sess.session_cl(st)))))

# Shared allocation-bound owner: the per-Sid ceiling admits only ids below
# it. Inbound entries clamp overflow suffixes (admitting the fitting prefix);
# keys/history/diagnostics fail closed atomically when they would overflow.
def seq_overflows(+seq: Nat, +id: Key.ServerId) -> Bool:
  Bool.not(Nat.is_lt(seq, id_ceiling(id)))

def part_overflows(+st: Sess.Session, +id: Key.ServerId) -> Bool:
  seq_overflows(Cl.log_seq_of(Sess.session_cl(st)), id)

def clamp_part(+st: Sess.Session, +id: Key.ServerId) -> Sess.Session:
  Sess.session_set_client(st, Cl.clamp_client_ceiling(Sess.session_cl(st), id_ceiling(id)))

def bind_history.pick(overflows: Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st2: Sess.Session) -> Workspace:
  match overflows:
    case True{}: Workspace{parts, cur, ds, rt}
    case False{}: Workspace{replace_part.go(parts, id, Part{id, gen, scope, st2}), cur, ds, rt}

def bind_history.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +p: Part, entries: List<&2, Hist.HistEntry>, +now: String, +cap: U32) -> Workspace:
  match p:
    case Part{_, +gen, +scope, +st}:
      +bound = Hist.apply_history_iso(Sess.session_cl(st), entries, now, cap, Isupport.as_iso(Sess.session_iso(st)))
      +st2 = Sess.session_set_client(st, bound)
      bind_history.pick(part_overflows(st2, id), parts, cur, ds, rt, id, gen, scope, st2)

def bind_history.got(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, entries: List<&2, Hist.HistEntry>, +now: String, +cap: U32, +got: Maybe<&2, Part>) -> Workspace:
  match got:
    case None{}: Workspace{parts, cur, ds, rt}
    case Some{+p}: bind_history.part(parts, cur, ds, rt, id, p, entries, now, cap)

def bind_history(+ws: Workspace, +id: Key.ServerId, entries: List<&2, Hist.HistEntry>, +now: String, +cap: U32) -> Workspace:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      bind_history.got(parts, cur, ds, rt, id, entries, now, cap, find_part.go(parts, id))

def single(+host: String, +port: U32, v6: Bool, +nick: String, +chan: String) -> Workspace:
  +id = Key.first()
  +st = seed_at(Sess.session_with_client_at(Cl.init(nick, host), chan, port), id, 0n)
  Workspace{Part{id, 0, Sid.Scope{host, port, v6}, st} <> Nil{}, id, Drafts.empty(), Nil{}}

# Primary with a caller-supplied client: the live loop passes the exact
# launch-endpoint credentialed client here, so only the primary part can
# complete the launch-profile SASL/NickServ exchange. Extras added with
# do_add stay bare; the launch profile is never copied to them. Supplied
# rows and their sequence are preserved (never rewound to the base).
def single_client(+host: String, +port: U32, v6: Bool, +cl: Cl.Client, +chan: String) -> Workspace:
  +id = Key.first()
  +st = seed_at(Sess.session_with_client_at(cl, chan, port), id, 0n)
  Workspace{Part{id, 0, Sid.Scope{host, port, v6}, st} <> Nil{}, id, Drafts.empty(), Nil{}}

def retired_get.pick(hit: Bool, +gen: U32, +cont: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{gen}
    case False{}: cont

def retired_get.buf(+h: SlotEpoch, +cont: Maybe<&2, U32>, +id: Key.ServerId) -> Maybe<&2, U32>:
  match h:
    case SlotEpoch{+eid, +gen, _}:
      retired_get.pick(Key.eq(eid, id), gen, cont)

def retired_get.go(+xs: List<&2, SlotEpoch>, +id: Key.ServerId) -> Maybe<&2, U32>:
  match xs:
    case Nil{}: None{}
    case Con{+h, +t}:
      +cont = retired_get.go(t, id)
      retired_get.buf(h, cont, id)

def fresh_gen(+got: Maybe<&2, U32>) -> U32:
  match got:
    case None{}: 0
    case Some{+g}: Sid.bump(g)

def fresh_gen_for(+rt: List<&2, SlotEpoch>, +id: Key.ServerId) -> U32:
  fresh_gen(retired_get.go(rt, id))

def retired_mark.pick(hit: Bool, +mark: Nat, +cont: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}: Some{mark}
    case False{}: cont

def retired_mark.buf(+h: SlotEpoch, +cont: Maybe<&2, Nat>, +id: Key.ServerId) -> Maybe<&2, Nat>:
  match h:
    case SlotEpoch{+eid, _, +mark}:
      retired_mark.pick(Key.eq(eid, id), mark, cont)

def retired_mark.go(+xs: List<&2, SlotEpoch>, +id: Key.ServerId) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}: None{}
    case Con{+h, +t}:
      +cont = retired_mark.go(t, id)
      retired_mark.buf(h, cont, id)

def retired_marked(+got: Maybe<&2, Nat>) -> Nat:
  match got:
    case None{}: 0n
    case Some{+m}: m

def retired_mark_for(+rt: List<&2, SlotEpoch>, +id: Key.ServerId) -> Nat:
  retired_marked(retired_mark.go(rt, id))

def retired_drop.pick(hit: Bool, +h: SlotEpoch, +rest: List<&2, SlotEpoch>) -> List<&2, SlotEpoch>:
  match hit:
    case True{}: rest
    case False{}: h <> rest

def retired_drop.buf(+h: SlotEpoch, +rest: List<&2, SlotEpoch>, +id: Key.ServerId) -> List<&2, SlotEpoch>:
  match h:
    case SlotEpoch{+eid, +gen, +mark}:
      retired_drop.pick(Key.eq(eid, id), SlotEpoch{eid, gen, mark}, rest)

def retired_drop.go(+xs: List<&2, SlotEpoch>, +id: Key.ServerId) -> List<&2, SlotEpoch>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      +rest = retired_drop.go(t, id)
      retired_drop.buf(h, rest, id)

def retired_put(+rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +mark: Nat) -> List<&2, SlotEpoch>:
  SlotEpoch{id, gen, mark} <> retired_drop.go(rt, id)

def id_used.pick(hit: Bool, +tail: Bool) -> Bool:
  match hit:
    case True{}: True{}
    case False{}: tail

def id_used.buf(+h: Part, +tail: Bool, +n: Nat) -> Bool:
  match h:
    case Part{+pid, _, _, _}:
      id_used.pick(Key.eq(pid, Key.ServerId{n}), tail)

def id_used.go(+xs: List<&2, Part>, +n: Nat) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, +t}:
      +tail = id_used.go(t, n)
      id_used.buf(h, tail, n)

def free_id.used(used: Bool, +next: Maybe<&2, Key.ServerId>, +n: Nat) -> Maybe<&2, Key.ServerId>:
  match used:
    case True{}: next
    case False{}: Some{Key.ServerId{n}}

def free_id.pick(room: Bool, used: Bool, +next: Maybe<&2, Key.ServerId>, +n: Nat) -> Maybe<&2, Key.ServerId>:
  match room:
    case False{}: None{}
    case True{}: free_id.used(used, next, n)

def free_id.go(fuel: Nat, +parts: List<&2, Part>, +n: Nat) -> Maybe<&2, Key.ServerId>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      +next = free_id.go(p, parts, Nat.add(n, 1n))
      free_id.pick(Nat.is_lt(n, Key.MAX_SERVERS()), id_used.go(parts, n), next, n)

def free_id(+ws: Workspace) -> Maybe<&2, Key.ServerId>:
  match ws:
    case Workspace{+parts, _, _, _}: free_id.go(4n, parts, 0n)

def add_server.free(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +host: String, +port: U32, v6: Bool, +nick: String, +chan: String, +free: Maybe<&2, Key.ServerId>) -> Workspace & Bool:
  match free:
    case None{}: (Workspace{parts, cur, ds, rt}, False{})
    case Some{+id}:
      +st = seed_at(Sess.session_with_client_at(Cl.init(nick, host), chan, port), id, retired_mark_for(rt, id))
      +gen = fresh_gen_for(rt, id)
      (Workspace{Part{id, gen, Sid.Scope{host, port, v6}, st} <> parts, cur, ds, retired_drop.go(rt, id)}, True{})

def add_server(+ws: Workspace, +host: String, +port: U32, v6: Bool, +nick: String, +chan: String) -> Workspace & Bool:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      add_server.free(parts, cur, ds, rt, host, port, v6, nick, chan, free_id.go(4n, parts, 0n))

def switch_server.valid(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, valid: Bool) -> Workspace & Bool:
  match valid:
    case True{}: (Workspace{parts, id, ds, rt}, True{})
    case False{}: (Workspace{parts, cur, ds, rt}, False{})

def switch_server.got(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +got: Maybe<&2, Part>) -> Workspace & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, False{})
    case Some{_}: switch_server.valid(parts, cur, ds, rt, id, Key.valid(id))

def switch_server(+ws: Workspace, +id: Key.ServerId) -> Workspace & Bool:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      switch_server.got(parts, cur, ds, rt, id, find_part.go(parts, id))

def remove_server.cur(+kept: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, moved: Bool) -> Workspace & Bool:
  match moved:
    case False{}: (Workspace{kept, cur, Drafts.replace_endpoint(ds, id, False{}), rt}, True{})
    case True{}: (Workspace{kept, head_id(kept), Drafts.replace_endpoint(ds, id, False{}), rt}, True{})

def remove_server.last(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +p: Part, last: Bool) -> Workspace & Bool:
  match last:
    case True{}: (Workspace{parts, cur, ds, rt}, False{})
    case False{}:
      +kept = drop_part.go(parts, id)
      remove_server.cur(kept, cur, ds, retired_put(rt, id, part_gen(p), part_seq(p)), id, Key.eq(cur, id))

def remove_server.known(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +got: Maybe<&2, Part>) -> Workspace & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, False{})
    case Some{+p}: remove_server.last(parts, cur, ds, rt, id, p, Nat.is_le(List.length(&2, Part, parts), 1n))

def remove_server(+ws: Workspace, +id: Key.ServerId) -> Workspace & Bool:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      remove_server.known(parts, cur, ds, rt, id, find_part.go(parts, id))

# Endpoint/slot replacement in place: Session's exact endpoint transition
# (scope_auth_endpoint clears credentials on any exact config mismatch and
# rebuilds buffers unless exactly same), the same exact predicate for this
# server's drafts, a refreshed scope preserving host spelling, and a
# generation bump so the old epoch's in-flight traffic drops. A changed
# endpoint also resets the Session composer and reseeds, and resets the
# active completion word, so no typed text or Tab revival leaks to the new
# endpoint; same-endpoint keeps all three.
def replace_reset(+st2: Sess.Session, same: Bool) -> Sess.Session:
  match same:
    case True{}: st2
    case False{}: Sess.session_reset_completion(Sess.session_upload_draft(st2, "", 1))

def replace_server.st(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +st: Sess.Session, +host: String, +port: U32, v6: Bool) -> Workspace & Bool:
  match st:
    case Sess.Session{+cl, _, _, +draft, _, +chan, +net, +hist, +size, +seed, +comp, +split, _, +old_port, +media, +plan, +edits, +isobox, +hlbox, +cf, _, +theme, +labelsbox, _}:
      +same = Sess.endpoint_same(cl, host, old_port, port)
      +st2 = Sess.session_after.dial(cl, draft, chan, hist, size, seed, comp, split, host, port, old_port, net, Sess.unbox_media(media), plan, edits, Sess.unbox_iso(isobox), Sess.unbox_hist_live(hlbox), Sess.unbox_cards(cf), Sess.unbox_full(cf), theme, labelsbox)
      +st3 = replace_reset(st2, same)
      (Workspace{replace_part.go(parts, id, Part{id, Sid.bump(gen), Sid.Scope{host, port, v6}, st3}), cur, Drafts.replace_endpoint(ds, id, same), rt}, True{})

def replace_server.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +p: Part, +host: String, +port: U32, v6: Bool) -> Workspace & Bool:
  match p:
    case Part{+id, +gen, _, +st}:
      replace_server.st(parts, cur, ds, rt, id, gen, st, host, port, v6)

def replace_server.got(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +host: String, +port: U32, v6: Bool, +got: Maybe<&2, Part>) -> Workspace & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, False{})
    case Some{+p}: replace_server.part(parts, cur, ds, rt, p, host, port, v6)

def replace_server(+ws: Workspace, +id: Key.ServerId, +host: String, +port: U32, v6: Bool) -> Workspace & Bool:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      replace_server.got(parts, cur, ds, rt, id, host, port, v6, find_part.go(parts, id))

# ---- key routing --------------------------------------------------------
# One frame routes to the current part through the AD adapter. Generations
# mirror net.bend emit_cmd: a produced Dial bumps the part generation and
# carries it; Pump/Begin are rewritten to the current generation (Session
# never emits them; the rewrite keeps external demux checks total). Search
# is rewritten to the current generation too: the stamped incarnation
# travels to the worker and back, fencing delayed completions from a
# retired incarnation whose Session stamps the new part reuses. The
# dialed host/port refresh the part scope; v6 refines at dial-plan time.

def with_gen(+cmd: Sess.NetCmd, +gen: U32) -> Sess.NetCmd:
  match cmd:
    case Sess.Dial{+host, +port, _, +nick}: Sess.Dial{host, port, gen, nick}
    case Sess.Pump{_}: Sess.Pump{gen}
    case Sess.Begin{_}: Sess.Begin{gen}
    case Sess.Search{+text, +target, +cursor, +orig, +endpoint, +history_on, +ticket, +hgen, _}:
      Sess.Search{text, target, cursor, orig, endpoint, history_on, ticket, hgen, gen}
    case _: cmd

def v6_of_scope(+scope: Sid.Scope) -> Bool:
  match scope:
    case Sid.Scope{_, _, +v6}: v6

def step_keys.routed.normal(+parts: List<&2, Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st2: Sess.Session, +ds2: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +cmd: Sess.NetCmd, +halt: Bool) -> Workspace & Sid.RoutedCmd & Bool:
  match cmd:
    case Sess.Dial{+host, +port, _, +nick}:
      +gen2 = Sid.bump(gen)
      +keep_v6 = v6_of_scope(scope)
      +scope2 : Sid.Scope = Sid.Scope{host, port, keep_v6}
      (Workspace{replace_part.go(parts, id, Part{id, gen2, scope2, st2}), cur, ds2, rt}, Sid.RoutedCmd{id, Sess.Dial{host, port, gen2, nick}}, halt)
    case _:
      (Workspace{replace_part.go(parts, id, Part{id, gen, scope, st2}), cur, ds2, rt}, Sid.RoutedCmd{id, with_gen(cmd, gen)}, halt)

def step_keys.routed.pick(overflows: Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st2: Sess.Session, +ds2: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +cmd: Sess.NetCmd, +halt: Bool, +ds_orig: Drafts.Drafts) -> Workspace & Sid.RoutedCmd & Bool:
  match overflows:
    case True{}: (Workspace{parts, cur, ds_orig, rt}, Sid.RoutedCmd{id, Sess.Cont{Nil{}}}, False{})
    case False{}: step_keys.routed.normal(parts, cur, id, gen, scope, st2, ds2, rt, cmd, halt)

def step_keys.routed(+parts: List<&2, Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st2: Sess.Session, +ds2: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +cmd: Sess.NetCmd, +halt: Bool, +ds_orig: Drafts.Drafts) -> Workspace & Sid.RoutedCmd & Bool:
  step_keys.routed.pick(part_overflows(st2, id), parts, cur, id, gen, scope, st2, ds2, rt, cmd, halt, ds_orig)

def step_keys.emit(+parts: List<&2, Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +ad2: AD.AD, +rt: List<&2, SlotEpoch>, +cmd: Sess.NetCmd, +halt: Bool, +ds_orig: Drafts.Drafts) -> Workspace & Sid.RoutedCmd & Bool:
  +st2 = AD.ad_session(ad2)
  +ds2 = AD.ad_drafts(ad2)
  step_keys.routed(parts, cur, id, gen, scope, st2, ds2, rt, cmd, halt, ds_orig)

def step_keys.tripped(+parts: List<&2, Part>, +cur: Key.ServerId, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +rt: List<&2, SlotEpoch>, trip: AD.AD & Sess.NetCmd & Bool, +ds_orig: Drafts.Drafts) -> Workspace & Sid.RoutedCmd & Bool:
  match trip:
    case (ad2, cmd, halt):
      step_keys.emit(parts, cur, id, gen, scope, ad2, rt, cmd, halt, ds_orig)

def step_keys.run(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +keys: Sess.Keys, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session) -> Workspace & Sid.RoutedCmd & Bool:
  trip = AD.step_keys(AD.with_drafts(st, ds, id), keys)
  step_keys.tripped(parts, cur, id, gen, scope, rt, trip, ds)

def step_keys.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +keys: Sess.Keys, +p: Part) -> Workspace & Sid.RoutedCmd & Bool:
  match p:
    case Part{+id, +gen, +scope, +st}:
      step_keys.run(parts, cur, ds, rt, keys, id, gen, scope, st)

def step_keys.got(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +keys: Sess.Keys, +got: Maybe<&2, Part>) -> Workspace & Sid.RoutedCmd & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, Sid.drop_for(cur), False{})
    case Some{+p}: step_keys.part(parts, cur, ds, rt, keys, p)

def step_keys(+ws: Workspace, +keys: Sess.Keys) -> Workspace & Sid.RoutedCmd & Bool:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      step_keys.got(parts, cur, ds, rt, keys, find_part.go(parts, cur))

# ---- admission ----------------------------------------------------------
# Pure demux checks for the (future, IO-side) actor fan-out. Each mirrors
# the single-server guard exactly, with the part supplying server+gen.

def cmd_admitted.part(+rc: Sid.RoutedCmd, +p: Part) -> Bool:
  match p:
    case Part{+id, +gen, _, _}:
      Sid.cmd_current(rc, id, gen)

def cmd_admitted.got(+rc: Sid.RoutedCmd, +got: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: cmd_admitted.part(rc, p)

def cmd_admitted.parts(+parts: List<&2, Part>, +rc: Sid.RoutedCmd) -> Bool:
  match rc:
    case Sid.RoutedCmd{+s, _}:
      cmd_admitted.got(rc, find_part.go(parts, s))

def cmd_admitted(+ws: Workspace, +rc: Sid.RoutedCmd) -> Bool:
  match ws:
    case Workspace{+parts, _, _, _}:
      cmd_admitted.parts(parts, rc)

def msg_admitted.part(+rm: Sid.RoutedMsg, +p: Part) -> Bool:
  match p:
    case Part{+id, +gen, _, _}:
      Sid.evt_current(rm, id, gen)

def msg_admitted.got(+rm: Sid.RoutedMsg, +got: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: msg_admitted.part(rm, p)

def msg_admitted.parts(+parts: List<&2, Part>, +rm: Sid.RoutedMsg) -> Bool:
  match rm:
    case Sid.RoutedMsg{+s, _}:
      msg_admitted.got(rm, find_part.go(parts, s))

def msg_admitted(+ws: Workspace, +rm: Sid.RoutedMsg) -> Bool:
  match ws:
    case Workspace{+parts, _, _, _}:
      msg_admitted.parts(parts, rm)

def writer_done_acked.part(+rm: Sid.RoutedMsg, +p: Part) -> Bool:
  match p:
    case Part{+id, +gen, _, _}:
      Sid.writer_done_current(rm, id, gen)

def writer_done_acked.got(+rm: Sid.RoutedMsg, +got: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: writer_done_acked.part(rm, p)

def writer_done_acked.parts(+parts: List<&2, Part>, +rm: Sid.RoutedMsg) -> Bool:
  match rm:
    case Sid.RoutedMsg{+s, _}:
      writer_done_acked.got(rm, find_part.go(parts, s))

def writer_done_acked(+ws: Workspace, +rm: Sid.RoutedMsg) -> Bool:
  match ws:
    case Workspace{+parts, _, _, _}:
      writer_done_acked.parts(parts, rm)

# ---- scope partitions ---------------------------------------------------

def scope_of.got(+got: Maybe<&2, Part>) -> Maybe<&2, Sid.Scope>:
  match got:
    case None{}: None{}
    case Some{+p}: Some{part_scope(p)}

def scope_of(+ws: Workspace, +id: Key.ServerId) -> Maybe<&2, Sid.Scope>:
  scope_of.got(find_part(ws, id))

def history_key.of(+scope: Sid.Scope) -> String:
  Sid.scope_key(scope)

def history_key.got(+got: Maybe<&2, Part>) -> Maybe<&2, String>:
  match got:
    case None{}: None{}
    case Some{+p}: Some{history_key.of(part_scope(p))}

def history_key(+ws: Workspace, +id: Key.ServerId) -> Maybe<&2, String>:
  history_key.got(find_part(ws, id))

def history_admits.got(+stored: String, +got: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: Sid.history_admits(stored, part_scope(p))

def history_admits(+ws: Workspace, +id: Key.ServerId, +stored: String) -> Bool:
  match ws:
    case Workspace{+parts, _, _, _}:
      history_admits.got(stored, find_part.go(parts, id))

def credential_ok.part(+cfg_host: String, +cfg_port: U32, +scope: Sid.Scope) -> Bool:
  match scope:
    case Sid.Scope{+host, +port, _}:
      Sid.credential_scope_ok(cfg_host, cfg_port, host, port)

def credential_ok.got(+cfg_host: String, +cfg_port: U32, +got: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: credential_ok.part(cfg_host, cfg_port, part_scope(p))

def credential_ok(+ws: Workspace, +id: Key.ServerId, +cfg_host: String, +cfg_port: U32) -> Bool:
  match ws:
    case Workspace{+parts, _, _, _}:
      credential_ok.got(cfg_host, cfg_port, find_part.go(parts, id))

# ---- reconnect intent -----------------------------------------------------

def dial_intent(+p: Part) -> Sid.Intent:
  match p:
    case Part{+id, +gen, +scope, _}:
      match scope:
        case Sid.Scope{+host, +port, +v6}: Sid.Intent{id, gen, host, port, v6}

def dial_intent_of.got(+got: Maybe<&2, Part>) -> Maybe<&2, Sid.Intent>:
  match got:
    case None{}: None{}
    case Some{+p}: Some{dial_intent(p)}

def dial_intent_of(+ws: Workspace, +id: Key.ServerId) -> Maybe<&2, Sid.Intent>:
  dial_intent_of.got(find_part(ws, id))

def redial_ok.part(+intent: Sid.Intent, +id: Key.ServerId, +p: Part) -> Bool:
  match p:
    case Part{_, +gen, +scope, _}:
      Sid.reconnect_ok(intent, id, gen, scope)

def redial_ok.got(+intent: Sid.Intent, +id: Key.ServerId, +got: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: redial_ok.part(intent, id, p)

def redial_ok(+ws: Workspace, +id: Key.ServerId, +intent: Sid.Intent) -> Bool:
  match ws:
    case Workspace{+parts, _, _, _}:
      redial_ok.got(intent, id, find_part.go(parts, id))

# ---- routed runtime apply -------------------------------------------------
# Pure half of the multiserver frame loop: apply actor messages to the
# addressed part through Session's exact inbound paths. Every entry point is
# gated by the part's current server+generation (the Sid checks) and its ID
# range ceiling, so stale, cross-server, unknown-part, and capped-part
# traffic drops with the workspace unchanged and no actor reply. The IO loop
# owns channels/clocks only: it stamps lines,
# adopts the routed generation on Dial/redial (the workspace is the sole
# generation owner; the loop must not re-bump), and schedules the 2s
# reconnect watch from the Intent that on_routed_fail returns.

def routed_id(+rm: Sid.RoutedMsg) -> Key.ServerId:
  match rm:
    case Sid.RoutedMsg{+s, _}: s

# Q5 request identity: the carried PONG request ID survives the workspace
# dispatcher untouched (the loop traces it at dequeue). Non-chunk traffic
# carries no identity.
def chunk_req(+e: Sess.NetEvt) -> U32:
  match e:
    case Sess.Chunk{_, +req}: req
    case _: 0

def routed_chunk_req.msg(m: Sess.UiMsg) -> U32:
  match m:
    case Sess.FromNet{_, +e}: chunk_req(e)
    case _: 0

def routed_chunk_req(+rm: Sid.RoutedMsg) -> U32:
  match rm:
    case Sid.RoutedMsg{_, m}: routed_chunk_req.msg(m)

# Per-line admission: the Session ceiling fold reverts each overflowing
# line with no state/wire/alert effects; the fitting prefix stays. The
# chunk gate checks generation only so non-allocating lines (PING,
# consumed auth) still flow when full; allocating lines revert per-line.
# The drained entry then imports a completed chathistory batch once through
# the ceiling-gated completion owner, so --server mode matches single-server
# import; a drain that would overflow refuses atomically with live state kept.
# Admitted NICK lines also rename same-server drafts: the ceiling fold
# carries per-line NickRename effects (from, to) under the per-line CM
# for each live admitted NICK, and stored_drained folds them through
# Drafts.apply_renames in arrival order. Archived, unregistered,
# consumed, and ceiling-reverted NICKs emit no effect, mirroring the
# split-pane gate; no whole-chunk inference or second parse exists.
def on_routed_chunk.stored(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, gen: U32, scope: Sid.Scope, pair: Sess.Session & List<&2, String>) -> Workspace & List<&2, String>:
  match pair:
    case (+st2, +outs):
      (Workspace{replace_part.go(parts, id, Part{id, gen, scope, st2}), cur, ds, rt}, outs)

def on_routed_chunk.stored_drained.r4(rest: List<&2, Nat> & List<&2, Drafts.NickRename>, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, gen: U32, scope: Sid.Scope, +st2: Sess.Session, +outs: List<&2, String>) -> Workspace & List<&2, String>:
  match rest:
    case (_, +renames):
      on_routed_chunk.stored(parts, cur, Drafts.apply_renames(ds, id, renames), rt, id, gen, scope, (st2, outs))

def on_routed_chunk.stored_drained.r3(rest: Nat & List<&2, Nat> & List<&2, Drafts.NickRename>, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, gen: U32, scope: Sid.Scope, +st2: Sess.Session, +outs: List<&2, String>) -> Workspace & List<&2, String>:
  match rest:
    case (_, rest4): on_routed_chunk.stored_drained.r4(rest4, parts, cur, ds, rt, id, gen, scope, st2, outs)

def on_routed_chunk.stored_drained.r2(rest: List<&2, String> & Nat & List<&2, Nat> & List<&2, Drafts.NickRename>, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, gen: U32, scope: Sid.Scope, +st2: Sess.Session) -> Workspace & List<&2, String>:
  match rest:
    case (+outs, rest3): on_routed_chunk.stored_drained.r3(rest3, parts, cur, ds, rt, id, gen, scope, st2, outs)

def on_routed_chunk.stored_drained(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, gen: U32, scope: Sid.Scope, quint: Sess.Session & List<&2, String> & Nat & List<&2, Nat> & List<&2, Drafts.NickRename>) -> Workspace & List<&2, String>:
  match quint:
    case (+st2, rest2): on_routed_chunk.stored_drained.r2(rest2, parts, cur, ds, rt, id, gen, scope, st2)

def on_routed_chunk.gated(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +xs: List<&2, U32>, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32, admitted: Bool) -> Workspace & List<&2, String>:
  match admitted:
    case False{}: (Workspace{parts, cur, ds, rt}, Nil{})
    case True{}:
      on_routed_chunk.stored_drained(parts, cur, ds, rt, id, gen, scope, Sess.step_on_framed_drained_ceiling(st, Sess.frame_chunk(st, xs), stamps, now_ms, id_ceiling(id)))

def on_routed_chunk.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rm: Sid.RoutedMsg, +xs: List<&2, U32>, +p: Part, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Workspace & List<&2, String>:
  match p:
    case Part{+id, +gen, +scope, +st}:
      on_routed_chunk.gated(parts, cur, ds, rt, id, gen, scope, st, xs, stamps, now_ms, Sid.evt_current(rm, id, gen))

def on_routed_chunk.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rm: Sid.RoutedMsg, +xs: List<&2, U32>, +got: Maybe<&2, Part>, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Workspace & List<&2, String>:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, Nil{})
    case Some{+p}: on_routed_chunk.part(parts, cur, ds, rt, rm, xs, p, stamps, now_ms)

def on_routed_chunk.routed(ws: Workspace, +rm: Sid.RoutedMsg, +xs: List<&2, U32>, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Workspace & List<&2, String>:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      on_routed_chunk.found(parts, cur, ds, rt, rm, xs, find_part.go(parts, routed_id(rm)), stamps, now_ms)

def on_routed_chunk.from(ws: Workspace, +s: Key.ServerId, +got: U32, +e: Sess.NetEvt, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Workspace & List<&2, String>:
  match e:
    case Sess.Chunk{+xs, +req}: on_routed_chunk.routed(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.Chunk{xs, req}}}, xs, stamps, now_ms)
    case _: (ws, Nil{})

def on_routed_chunk.msg(ws: Workspace, +s: Key.ServerId, m: Sess.UiMsg, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Workspace & List<&2, String>:
  match m:
    case Sess.FromNet{+got, +e}: on_routed_chunk.from(ws, s, got, e, stamps, now_ms)
    case _: (ws, Nil{})

def on_routed_chunk(ws: Workspace, +rm: Sid.RoutedMsg, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Workspace & List<&2, String>:
  match rm:
    case Sid.RoutedMsg{+s, m}: on_routed_chunk.msg(ws, s, m, stamps, now_ms)

def on_routed_up.gated(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +ts: String, admitted: Bool) -> Workspace:
  match admitted:
    case False{}: Workspace{parts, cur, ds, rt}
    case True{}:
      Workspace{replace_part.go(parts, id, Part{id, gen, scope, clamp_part(Sess.session_reconnected(st, ts), id)}), cur, ds, rt}

def on_routed_up.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rm: Sid.RoutedMsg, +p: Part, +ts: String) -> Workspace:
  match p:
    case Part{+id, +gen, +scope, +st}:
      on_routed_up.gated(parts, cur, ds, rt, id, gen, scope, st, ts, ids_admitted(Sid.evt_current(rm, id, gen), st, id))

def on_routed_up.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rm: Sid.RoutedMsg, +got: Maybe<&2, Part>, +ts: String) -> Workspace:
  match got:
    case None{}: Workspace{parts, cur, ds, rt}
    case Some{+p}: on_routed_up.part(parts, cur, ds, rt, rm, p, ts)

def on_routed_up.routed(ws: Workspace, +rm: Sid.RoutedMsg, +ts: String) -> Workspace:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      on_routed_up.found(parts, cur, ds, rt, rm, find_part.go(parts, routed_id(rm)), ts)

def on_routed_up.from(ws: Workspace, +s: Key.ServerId, +got: U32, +e: Sess.NetEvt, +ts: String) -> Workspace:
  match e:
    case Sess.Up{}: on_routed_up.routed(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.Up{}}}, ts)
    case _: ws

def on_routed_up.msg(ws: Workspace, +s: Key.ServerId, m: Sess.UiMsg, +ts: String) -> Workspace:
  match m:
    case Sess.FromNet{+got, +e}: on_routed_up.from(ws, s, got, e, ts)
    case _: ws

def on_routed_up(ws: Workspace, +rm: Sid.RoutedMsg, +ts: String) -> Workspace:
  match rm:
    case Sid.RoutedMsg{+s, m}: on_routed_up.msg(ws, s, m, ts)

# A failed connection reports Hangup when Session schedules automatic
# reconnect (flush then abandon; Drop would discard healthy pending), else
# Drop for cancel-without-redial. The Intent is what the loop's 2s watch
# must carry. The generation is not bumped here: like the single-server
# loop, the bump happens when the redial fires (on_redial), so the Intent
# carries the current generation for the scheduled-gen check.
type FailResult is Data:
  FailResult{ws: Workspace, cmd: Maybe<&2, Sid.RoutedCmd>, intent: Maybe<&2, Sid.Intent>}

def on_routed_fail.cmd(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, st3: Sess.Session, cmd: Sess.NetCmd) -> FailResult:
  match cmd:
    case Sess.Dial{host, port, _, _}:
      FailResult{Workspace{replace_part.go(parts, id, Part{id, gen, scope, clamp_part(st3, id)}), cur, ds, rt}, Some{Sid.RoutedCmd{id, Sess.Hangup{}}}, Some{Sid.Intent{id, gen, host, port, v6_of_scope(scope)}}}
    case _:
      FailResult{Workspace{replace_part.go(parts, id, Part{id, gen, scope, clamp_part(st3, id)}), cur, ds, rt}, Some{Sid.RoutedCmd{id, Sess.Drop{}}}, None{}}

def on_routed_fail.recon(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, recon: Sess.Session & Sess.NetCmd) -> FailResult:
  match recon:
    case (+st3, +cmd): on_routed_fail.cmd(parts, cur, ds, rt, id, gen, scope, st3, cmd)

def on_routed_fail.gated(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +ts: String, +fail_msg: String, admitted: Bool) -> FailResult:
  match admitted:
    case False{}: FailResult{Workspace{parts, cur, ds, rt}, None{}, None{}}
    case True{}:
      on_routed_fail.recon(parts, cur, ds, rt, id, gen, scope, Sess.session_autoreconnect(Sess.session_fail(Sess.session_set_now(st, ts), fail_msg)))

def on_routed_fail.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rm: Sid.RoutedMsg, +p: Part, +ts: String, +fail_msg: String) -> FailResult:
  match p:
    case Part{+id, +gen, +scope, +st}:
      on_routed_fail.gated(parts, cur, ds, rt, id, gen, scope, st, ts, fail_msg, ids_admitted(Sid.evt_current(rm, id, gen), st, id))

def on_routed_fail.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rm: Sid.RoutedMsg, +got: Maybe<&2, Part>, +ts: String, +fail_msg: String) -> FailResult:
  match got:
    case None{}: FailResult{Workspace{parts, cur, ds, rt}, None{}, None{}}
    case Some{+p}: on_routed_fail.part(parts, cur, ds, rt, rm, p, ts, fail_msg)

def on_routed_fail.routed(ws: Workspace, +rm: Sid.RoutedMsg, +ts: String, +fail_msg: String) -> FailResult:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      on_routed_fail.found(parts, cur, ds, rt, rm, find_part.go(parts, routed_id(rm)), ts, fail_msg)

def on_routed_fail.from(ws: Workspace, +s: Key.ServerId, +got: U32, +e: Sess.NetEvt, +ts: String) -> FailResult:
  match e:
    case Sess.Eof{}: on_routed_fail.routed(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.Eof{}}}, ts, "disconnected")
    case Sess.NetFail{+msg}: on_routed_fail.routed(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.NetFail{msg}}}, ts, "disconnected: " ++ msg)
    case _: FailResult{ws, None{}, None{}}

def on_routed_fail.msg(ws: Workspace, +s: Key.ServerId, m: Sess.UiMsg, +ts: String) -> FailResult:
  match m:
    case Sess.FromNet{+got, +e}: on_routed_fail.from(ws, s, got, e, ts)
    case _: FailResult{ws, None{}, None{}}

def on_routed_fail(ws: Workspace, +rm: Sid.RoutedMsg, +ts: String) -> FailResult:
  match rm:
    case Sid.RoutedMsg{+s, m}: on_routed_fail.msg(ws, s, m, ts)

# Fire a scheduled reconnect watch: only an Intent that matches the part's
# current server+generation and exact endpoint, with autoreconnect still
# enabled, emits. Emission bumps the part generation and carries it on the
# Dial; the loop adopts it (no re-bump), so in-flight stale traffic drops.
# A valid current Intent that finds the option off cancels the scheduled
# reconnect (Reconnecting -> Offline, no Dial), exactly like the
# single-server Net.on_reconnect path; otherwise the part would stay
# Reconnecting forever and reject manual /connect and /reconnect. Stale or
# foreign Intents leave the part untouched.
def on_redial.emit(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +pid: Key.ServerId, +gen: U32, scope: Sid.Scope, +st: Sess.Session, +intent: Sid.Intent) -> Workspace & Maybe<&2, Sid.RoutedCmd>:
  match intent:
    case Sid.Intent{_, _, host, port, _}:
      (Workspace{replace_part.go(parts, pid, Part{pid, Sid.bump(gen), scope, st}), cur, ds, rt}, Some{Sid.RoutedCmd{pid, Sess.Dial{host, port, Sid.bump(gen), Cl.nick_of(Sess.session_cl(st))}}})

def on_redial.enabled(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +pid: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +intent: Sid.Intent, auto: Bool) -> Workspace & Maybe<&2, Sid.RoutedCmd>:
  match auto:
    case True{}: on_redial.emit(parts, cur, ds, rt, pid, gen, scope, st, intent)
    case False{}:
      (Workspace{replace_part.go(parts, pid, Part{pid, gen, scope, Sess.session_cancel_reconnect(st)}), cur, ds, rt}, None{})

def on_redial.gated(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +pid: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +intent: Sid.Intent, valid: Bool, auto: Bool) -> Workspace & Maybe<&2, Sid.RoutedCmd>:
  match valid:
    case False{}: (Workspace{parts, cur, ds, rt}, None{})
    case True{}: on_redial.enabled(parts, cur, ds, rt, pid, gen, scope, st, intent, auto)

def on_redial.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +intent: Sid.Intent, +p: Part) -> Workspace & Maybe<&2, Sid.RoutedCmd>:
  match p:
    case Part{+pid, +gen, +scope, +st}:
      on_redial.gated(parts, cur, ds, rt, pid, gen, scope, st, intent, Sid.reconnect_ok(intent, pid, gen, scope), Sess.session_autoreconnect_on(st))

def on_redial.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +intent: Sid.Intent, +got: Maybe<&2, Part>) -> Workspace & Maybe<&2, Sid.RoutedCmd>:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, None{})
    case Some{+p}: on_redial.part(parts, cur, ds, rt, intent, p)

def on_redial(+ws: Workspace, +id: Key.ServerId, +intent: Sid.Intent) -> Workspace & Maybe<&2, Sid.RoutedCmd>:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      on_redial.found(parts, cur, ds, rt, intent, find_part.go(parts, id))

def current_session.got(+got: Maybe<&2, Part>) -> Sess.Session:
  match got:
    case None{}: Sess.session_demo(Cl.init("nobody", "nowhere.example"), "#lost")
    case Some{+p}: part_session(p)

def current_session(+ws: Workspace) -> Sess.Session:
  current_session.got(find_part(ws, ws_current(ws)))

# ---- global bell ----------------------------------------------------------
# Native keeps one last_bell_seq and rings on any painted change while the
# painted enable flag is set, then adopts the painted seq either way, so
# the multiserver loop paints one workspace-global sequence: it advances
# exactly once per inbound alert on any part and never on focus-only
# switches (unequal or equal local counters alike). Per-part locals keep
# counting under single-server View semantics; the loop carries the global
# and projects it onto the focused session at paint time. Stale, foreign,
# and non-highlight traffic never advances it.
#
# The global owner respects the EVENT-ORIGIN opt-in, never the focused
# preference: bell_after_on advances only when the routed part has bell
# enabled, and paint_session always paints enabled. A focused-off paint
# that adopted a fresh seq would swallow the ring unrecoverably (later
# focus paints repeat the same seq), while an opted-out background event
# must not ring a bell-enabled focus at all. Muted senders never reach
# the local counter (the feed drops them), so they never advance either.
def part_bell.got(+got: Maybe<&2, Part>) -> U32:
  match got:
    case None{}: 0
    case Some{+p}: Cl.client_bell_seq(Sess.session_cl(part_session(p)))

def part_bell(+ws: Workspace, +id: Key.ServerId) -> U32:
  part_bell.got(find_part(ws, id))

def part_bell_on.got(+got: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: Cl.settings_bell(Cl.get_settings(Sess.session_cl(part_session(p))))

def part_bell_on(+ws: Workspace, +id: Key.ServerId) -> Bool:
  part_bell_on.got(find_part(ws, id))

# Whether the addressed part currently holds SASL credentials: the live
# loop arms each actor's SASL request from its own part's client, so the
# request and the Session exchange always agree. Unknown parts answer no.
def part_has_sasl.got(+got: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: Cl.client_has_sasl(Sess.session_cl(part_session(p)))

def part_has_sasl(+ws: Workspace, +id: Key.ServerId) -> Bool:
  part_has_sasl.got(find_part(ws, id))

def bell_after.go(+after: U32, +before: U32, +bell: U32, ge: Bool) -> U32:
  match ge:
    case True{}: U32.add(bell, U32.sub(after, before))
    case False{}: bell

def bell_after(+before: U32, +after: U32, +bell: U32) -> U32:
  bell_after.go(after, before, bell, U32.is_ge(after, before))

def bell_after_on(+before: U32, +after: U32, +bell: U32, +on: Bool) -> U32:
  match on:
    case False{}: bell
    case True{}: bell_after(before, after, bell)

# Owned one-shot auth pipe (pure model of the FFI launch pipe): the first
# trusted edge writes once, later edges (duplicate/stale/foreign/reconnect)
# write zero. The live loop calls AuthBridge.observed on the edge; the FFI
# unsets the descriptor after the first frame, so the model and the pipe
# agree by construction.
def pipe_after.zero(+zero: Bool, +writes: Nat) -> Nat:
  match zero:
    case True{}: 1n
    case False{}: writes

def pipe_after.edge(+edge: Bool, +writes: Nat, +zero: Bool) -> Nat:
  match edge:
    case True{}: pipe_after.zero(zero, writes)
    case False{}: writes

def pipe_after(+writes: Nat, +edge: Bool) -> Nat:
  pipe_after.edge(edge, writes, Nat.is_eq(writes, 0n))

def paint_session.cl(+st: Sess.Session, +cl: Cl.Client, +bell: U32) -> Sess.Session:
  Sess.session_set_client(st, Cl.set_settings(cl, Cl.set_bell_seq(Cl.set_bell(Cl.get_settings(cl), True{}), bell)))

def paint_session(+ws: Workspace, +bell: U32) -> Sess.Session:
  +st = current_session(ws)
  paint_session.cl(st, Sess.session_cl(st), bell)

# ---- typing tick ----------------------------------------------------------
# The one-second loop tick expires inbound typing on every part (focused and
# background alike) and steps outbound typing through the shared G6 owner,
# collecting at most one TAGMSG wire per part for the bounded actor path.
# Changed reports inbound expiry only, so idle ticks skip the repaint exactly
# like the single-server loop. Offline/untagged/mistargeted ticks are quiet.
type ServerOuts is Data:
  ServerOuts{s: Key.ServerId, outs: List<&2, String>}

def tick_part.ticked(+id: Key.ServerId, +gen: U32, +scope: Sid.Scope, pair: Sess.Session & List<&2, String>, +ch: Bool) -> Part & Bool & List<&2, String>:
  match pair:
    case (+st3, +outs): (Part{id, gen, scope, st3}, ch, outs)

def tick_part.expired(+id: Key.ServerId, +gen: U32, +scope: Sid.Scope, pair: Sess.Session & Bool, +now_ms: U32) -> Part & Bool & List<&2, String>:
  match pair:
    case (+st2, +ch): tick_part.ticked(id, gen, scope, Sess.session_tick_typing(st2, now_ms), ch)

def tick_part(+p: Part, +now_ms: U32) -> Part & Bool & List<&2, String>:
  match p:
    case Part{+id, +gen, +scope, +st}:
      tick_part.expired(id, gen, scope, Sess.session_expire_typing(st, now_ms), now_ms)

def tick_typing.emit_rest(empty: Bool, +h2: Part, +outs1: List<&2, String>, +rest: List<&2, ServerOuts>) -> List<&2, ServerOuts>:
  match empty:
    case True{}: rest
    case False{}: ServerOuts{part_id(h2), outs1} <> rest

def tick_typing.emit(empty: Bool, +h2: Part, +ch1: Bool, +outs1: List<&2, String>, +t2: List<&2, Part>, +ch2: Bool, +rest: List<&2, ServerOuts>) -> List<&2, Part> & Bool & List<&2, ServerOuts>:
  (h2 <> t2, ch1 || ch2, tick_typing.emit_rest(empty, h2, outs1, rest))

def tick_typing.tail.r1(rest: Bool & List<&2, ServerOuts>, +h2: Part, +ch1: Bool, +outs1: List<&2, String>, +t2: List<&2, Part>) -> List<&2, Part> & Bool & List<&2, ServerOuts>:
  match rest:
    case (+ch2, +rest): tick_typing.emit(List.is_empty(&2, String, outs1), h2, ch1, outs1, t2, ch2, rest)

def tick_typing.tail(+h2: Part, +ch1: Bool, +outs1: List<&2, String>, tp: List<&2, Part> & Bool & List<&2, ServerOuts>) -> List<&2, Part> & Bool & List<&2, ServerOuts>:
  match tp:
    case (+t2, rest): tick_typing.tail.r1(rest, h2, ch1, outs1, t2)

def tick_typing.cons.r1(rest: Bool & List<&2, String>, +h2: Part, tp: List<&2, Part> & Bool & List<&2, ServerOuts>) -> List<&2, Part> & Bool & List<&2, ServerOuts>:
  match rest:
    case (+ch1, +outs1): tick_typing.tail(h2, ch1, outs1, tp)

def tick_typing.cons(hp: Part & Bool & List<&2, String>, tp: List<&2, Part> & Bool & List<&2, ServerOuts>) -> List<&2, Part> & Bool & List<&2, ServerOuts>:
  match hp:
    case (+h2, rest): tick_typing.cons.r1(rest, h2, tp)

def tick_typing.go(+xs: List<&2, Part>, +now_ms: U32) -> List<&2, Part> & Bool & List<&2, ServerOuts>:
  match xs:
    case Nil{}: (Nil{}, False{}, Nil{})
    case Con{+h, +t}: tick_typing.cons(tick_part(h, now_ms), tick_typing.go(t, now_ms))

type TickOut is Data:
  TickOut{ws: Workspace, changed: Bool, outs: List<&2, ServerOuts>}

def tick_typing.ws.r1(rest: Bool & List<&2, ServerOuts>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +parts2: List<&2, Part>) -> TickOut:
  match rest:
    case (+changed, +outs): TickOut{Workspace{parts2, cur, ds, rt}, changed, outs}

def tick_typing.ws(+cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, got: List<&2, Part> & Bool & List<&2, ServerOuts>) -> TickOut:
  match got:
    case (+parts2, rest): tick_typing.ws.r1(rest, cur, ds, rt, parts2)

def tick_typing(+ws: Workspace, +now_ms: U32) -> TickOut:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}: tick_typing.ws(cur, ds, rt, tick_typing.go(parts, now_ms))

def tick_ws(+o: TickOut) -> Workspace:
  match o:
    case TickOut{+ws2, _, _}: ws2

def tick_changed(+o: TickOut) -> Bool:
  match o:
    case TickOut{_, +changed, _}: changed

def tick_outs(+o: TickOut) -> List<&2, ServerOuts>:
  match o:
    case TickOut{_, _, +outs}: outs

# ---- auth-success edge ------------------------------------------------------
# The launcher bridge fires once when the primary part's auth-success
# sequence advances on an unchanged endpoint. Background parts never feed
# it; a failed notification lands as a primary-part diagnostic only.
def auth_edge.st(+a: Sess.Session, +b: Sess.Session) -> Bool:
  String.eq(Cl.server_of(Sess.session_cl(a)), Cl.server_of(Sess.session_cl(b)))
    && U32.is_eq(Sess.session_port(a), Sess.session_port(b))
    && Nat.is_lt(Cl.auth_success_seq(Sess.session_cl(a)), Cl.auth_success_seq(Sess.session_cl(b)))

def auth_edge.got2(+st: Sess.Session, +got2: Maybe<&2, Part>) -> Bool:
  match got2:
    case None{}: False{}
    case Some{+q}: auth_edge.st(st, part_session(q))

def auth_edge.got(+got: Maybe<&2, Part>, +got2: Maybe<&2, Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}: auth_edge.got2(part_session(p), got2)

def auth_edge(+before: Workspace, +after: Workspace) -> Bool:
  auth_edge.got(find_part(before, Key.first()), find_part(after, Key.first()))

def auth_noticed.pick(full: Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +code: U32) -> Workspace:
  match full:
    case True{}: Workspace{parts, cur, ds, rt}
    case False{}: Workspace{replace_part.go(parts, id, Part{id, gen, scope, Sess.session_set_client(st, Cl.diagnostic(Sess.session_cl(st), Cl.Error{}, "authentication notification failed (code: " ++ U32.show(code) ++ ")"))}), cur, ds, rt}

def auth_noticed.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +p: Part, +code: U32) -> Workspace:
  match p:
    case Part{+id, +gen, +scope, +st}:
      auth_noticed.pick(part_full(st, id), parts, cur, ds, rt, id, gen, scope, st, code)

def auth_noticed.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +got: Maybe<&2, Part>, +code: U32) -> Workspace:
  match got:
    case None{}: Workspace{parts, cur, ds, rt}
    case Some{+p}: auth_noticed.part(parts, cur, ds, rt, p, code)

def auth_noticed.gated(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +code: U32, zero: Bool) -> Workspace:
  match zero:
    case True{}: Workspace{parts, cur, ds, rt}
    case False{}: auth_noticed.found(parts, cur, ds, rt, id, find_part.go(parts, id), code)

def auth_noticed.code(+ws: Workspace, +id: Key.ServerId, +code: U32, zero: Bool) -> Workspace:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      auth_noticed.gated(parts, cur, ds, rt, id, code, zero)

def auth_noticed(+ws: Workspace, +id: Key.ServerId, +code: U32) -> Workspace:
  auth_noticed.code(ws, id, code, U32.is_zero(code))

# ---- live loop entries --------------------------------------------------
# The multiserver IO loop calls exactly these entries (plus on_redial for
# the reconnect watch and writer_done_acked for shutdown fencing); goldens
# pin them as call paths, not just the leaf applies.
type LiveMsgOut is Data:
  LiveMsgOut{ws: Workspace, outs: List<&2, String>, cmd: Maybe<&2, Sid.RoutedCmd>, intent: Maybe<&2, Sid.Intent>}

def live_none(+ws: Workspace) -> LiveMsgOut:
  LiveMsgOut{ws, Nil{}, None{}, None{}}

def live_chunked(pair: Workspace & List<&2, String>) -> LiveMsgOut:
  match pair:
    case (+ws2, +outs): LiveMsgOut{ws2, outs, None{}, None{}}

def live_upped(+ws2: Workspace) -> LiveMsgOut:
  LiveMsgOut{ws2, Nil{}, None{}, None{}}

def live_failed(+res: FailResult) -> LiveMsgOut:
  match res:
    case FailResult{+ws2, +cmd, +intent}: LiveMsgOut{ws2, Nil{}, cmd, intent}

# A failed initial dial quarantines only its own part: echo the reason and
# park it Offline for a later manual /connect. No Drop (the actor never
# armed a socket for this generation), no reconnect Intent: like the
# single-server path, an initial failure never auto-retries. Sibling parts
# are unaffected.
def live_initial.gated(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +msg: String, admitted: Bool) -> LiveMsgOut:
  match admitted:
    case False{}: LiveMsgOut{Workspace{parts, cur, ds, rt}, Nil{}, None{}, None{}}
    case True{}:
      +err = Sess.session_cancel_reconnect(Sess.session_error(st, msg))
      LiveMsgOut{Workspace{replace_part.go(parts, id, Part{id, gen, scope, clamp_part(err, id)}), cur, ds, rt}, Nil{}, None{}, None{}}

def live_initial.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rm: Sid.RoutedMsg, +p: Part, +msg: String) -> LiveMsgOut:
  match p:
    case Part{+id, +gen, +scope, +st}:
      live_initial.gated(parts, cur, ds, rt, id, gen, scope, st, msg, ids_admitted(Sid.evt_current(rm, id, gen), st, id))

def live_initial.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rm: Sid.RoutedMsg, +got: Maybe<&2, Part>, +msg: String) -> LiveMsgOut:
  match got:
    case None{}: LiveMsgOut{Workspace{parts, cur, ds, rt}, Nil{}, None{}, None{}}
    case Some{+p}: live_initial.part(parts, cur, ds, rt, rm, p, msg)

def live_initial(+ws: Workspace, +rm: Sid.RoutedMsg, +msg: String) -> LiveMsgOut:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      live_initial.found(parts, cur, ds, rt, rm, find_part.go(parts, routed_id(rm)), msg)

def live_on_msg.from(+ws: Workspace, +s: Key.ServerId, +got: U32, +e: Sess.NetEvt, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32, +ts: String) -> LiveMsgOut:
  match e:
    case Sess.Chunk{+xs, +req}: live_chunked(on_routed_chunk(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.Chunk{xs, req}}}, stamps, now_ms))
    case Sess.Up{}: live_upped(on_routed_up(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.Up{}}}, ts))
    case Sess.Eof{}: live_failed(on_routed_fail(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.Eof{}}}, ts))
    case Sess.NetFail{+msg}: live_failed(on_routed_fail(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.NetFail{msg}}}, ts))
    case Sess.InitialFail{+msg}: live_initial(ws, Sid.RoutedMsg{s, Sess.FromNet{got, Sess.InitialFail{msg}}}, msg)
    case _: live_none(ws)

def live_on_msg.msg(+ws: Workspace, +s: Key.ServerId, m: Sess.UiMsg, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32, +ts: String) -> LiveMsgOut:
  match m:
    case Sess.FromNet{+got, +e}: live_on_msg.from(ws, s, got, e, stamps, now_ms, ts)
    case _: live_none(ws)

def live_on_msg(+ws: Workspace, +rm: Sid.RoutedMsg, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32, +ts: String) -> LiveMsgOut:
  match rm:
    case Sid.RoutedMsg{+s, m}: live_on_msg.msg(ws, s, m, stamps, now_ms, ts)

# ---- search completion ----------------------------------------------------
# Async disk-search completion against the addressed part through Session's
# exact completion owner (ticket/gen/endpoint must match the live owner).
# The carried wgen incarnation must equal the live part generation first:
# remove/readd reuses the Sid with a fresh Session, so a retired part's
# first search and the new part's first search share ticket/gen/endpoint
# and Session stamps alone cannot fence the delayed old completion.
# Unknown parts, fenced incarnations, stale/refused completions, and
# ceiling overflows stay quiet with the workspace unchanged and no repaint.
def on_search_done.fit(overflows: Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st2: Sess.Session) -> Workspace & Bool:
  match overflows:
    case True{}: (Workspace{parts, cur, ds, rt}, False{})
    case False{}: (Workspace{replace_part.go(parts, id, Part{id, gen, scope, st2}), cur, ds, rt}, True{})

def on_search_done.landed(imported: Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st2: Sess.Session) -> Workspace & Bool:
  match imported:
    case False{}: (Workspace{parts, cur, ds, rt}, False{})
    case True{}: on_search_done.fit(part_overflows(st2, id), parts, cur, ds, rt, id, gen, scope, st2)

def on_search_done.rest(rest: Nat & Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st2: Sess.Session) -> Workspace & Bool:
  match rest:
    case (_, +imported): on_search_done.landed(imported, parts, cur, ds, rt, id, gen, scope, st2)

def on_search_done.done(pair: Sess.Session & Nat & Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope) -> Workspace & Bool:
  match pair:
    case (+st2, rest): on_search_done.rest(rest, parts, cur, ds, rt, id, gen, scope, st2)

def on_search_done.gated(admitted: Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +ticket: Nat, +hgen: Nat, +endpoint: String, +orig: String, +result: Hs.DiskResult) -> Workspace & Bool:
  match admitted:
    case False{}: (Workspace{parts, cur, ds, rt}, False{})
    case True{}:
      on_search_done.done(Sess.history_search_done(st, ticket, hgen, endpoint, orig, result), parts, cur, ds, rt, id, gen, scope)

def on_search_done.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +p: Part, +ticket: Nat, +hgen: Nat, +wgen: U32, +endpoint: String, +orig: String, +result: Hs.DiskResult) -> Workspace & Bool:
  match p:
    case Part{+id, +gen, +scope, +st}:
      on_search_done.gated(U32.is_eq(gen, wgen), parts, cur, ds, rt, id, gen, scope, st, ticket, hgen, endpoint, orig, result)

def on_search_done.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +got: Maybe<&2, Part>, +ticket: Nat, +hgen: Nat, +wgen: U32, +endpoint: String, +orig: String, +result: Hs.DiskResult) -> Workspace & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, False{})
    case Some{+p}: on_search_done.part(parts, cur, ds, rt, p, ticket, hgen, wgen, endpoint, orig, result)

def on_search_done(+ws: Workspace, +s: Key.ServerId, +ticket: Nat, +hgen: Nat, +wgen: U32, +endpoint: String, +orig: String, +result: Hs.DiskResult) -> Workspace & Bool:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      on_search_done.found(parts, cur, ds, rt, find_part.go(parts, s), ticket, hgen, wgen, endpoint, orig, result)

def search_ws(pair: Workspace & Bool) -> Workspace:
  match pair:
    case (+ws2, _): ws2

def search_landed(pair: Workspace & Bool) -> Bool:
  match pair:
    case (_, +landed): landed

def live_ws(+o: LiveMsgOut) -> Workspace:
  match o:
    case LiveMsgOut{+ws, _, _, _}: ws

def live_outs.go(+outs: List<&2, String>) -> String:
  String.join(outs, "|")

def live_outs(+o: LiveMsgOut) -> String:
  match o:
    case LiveMsgOut{_, +outs, _, _}: live_outs.go(outs)

def live_cmd(+o: LiveMsgOut) -> Maybe<&2, Sid.RoutedCmd>:
  match o:
    case LiveMsgOut{_, _, +cmd, _}: cmd

def live_intent(+o: LiveMsgOut) -> Maybe<&2, Sid.Intent>:
  match o:
    case LiveMsgOut{_, _, _, +intent}: intent

# ---- live focus entries ---------------------------------------------------
# /server N (exact, 1-based) switches the current server; F7 cycles to the
# next present server with draft stash/load. The stash folds under the
# outgoing part's negotiated CASEMAPPING and the load under the target
# part's, so ascii-distinct rooms keep distinct drafts across a cycle.
# Anything else falls through to the current part.
def server_index(+rest: String) -> Maybe<&2, Nat>:
  match rest:
    case "1": Some{1n}
    case "2": Some{2n}
    case "3": Some{3n}
    case "4": Some{4n}
    case _: None{}

def server_arg.verb(+verb: String, +rest: String, +server: Bool) -> Maybe<&2, Nat>:
  match server:
    case False{}: None{}
    case True{}: server_index(rest)

def server_arg.parsed(+input: Sub.Input) -> Maybe<&2, Nat>:
  match input:
    case Sub.CommandInput{_, +verb, +rest}: server_arg.verb(verb, rest, Irc.ieq(verb, "server"))
    case _: None{}

def server_arg(+typed: String) -> Maybe<&2, Nat>:
  server_arg.parsed(Sub.parse_input(typed))

def live_server.absent.pick(full: Bool, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +n: Nat) -> Workspace & Sid.RoutedCmd & Bool:
  match full:
    case True{}: (Workspace{parts, cur, ds, rt}, Sid.RoutedCmd{cur, Sess.Cont{Nil{}}}, False{})
    case False{}:
      +err = Sess.session_upload_draft(Sess.session_error(st, "no such server: " ++ Nat.show(n)), "", Sess.session_seed(st))
      (Workspace{replace_part.go(parts, id, Part{id, gen, scope, err}), cur, ds, rt}, Sid.RoutedCmd{cur, Sess.Cont{Nil{}}}, False{})

def live_server.absent(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +n: Nat) -> Workspace & Sid.RoutedCmd & Bool:
  live_server.absent.pick(part_full(st, id), parts, cur, ds, rt, id, gen, scope, st, n)

def live_server.present(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +target: Key.ServerId) -> Workspace & Sid.RoutedCmd & Bool:
  +cleared = Sess.session_upload_draft(st, "", Sess.session_seed(st))
  +ws2 : Workspace = Workspace{replace_part.go(parts, id, Part{id, gen, scope, cleared}), target, ds, rt}
  (ws2, Sid.RoutedCmd{target, Sess.Cont{Nil{}}}, False{})

def live_server.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +st: Sess.Session, +n: Nat, +got: Maybe<&2, Part>) -> Workspace & Sid.RoutedCmd & Bool:
  match got:
    case None{}: live_server.absent(parts, cur, ds, rt, id, gen, scope, st, n)
    case Some{+p}: live_server.present(parts, cur, ds, rt, id, gen, scope, st, part_id(p))

def live_server.cur(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +n: Nat, +got: Maybe<&2, Part>) -> Workspace & Sid.RoutedCmd & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, Sid.RoutedCmd{cur, Sess.Cont{Nil{}}}, False{})
    case Some{+p}:
      match p:
        case Part{+id, +gen, +scope, +st}:
          live_server.found(parts, cur, ds, rt, id, gen, scope, st, n, find_part.go(parts, Key.ServerId{Nat.sub(n, 1n)}))

def live_server(+ws: Workspace, +n: Nat) -> Workspace & Sid.RoutedCmd & Bool:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      live_server.cur(parts, cur, ds, rt, n, find_part.go(parts, cur))

def live_step.arg(+ws: Workspace, +keys: Sess.Keys, +got: Maybe<&2, Nat>) -> Workspace & Sid.RoutedCmd & Bool:
  match got:
    case None{}: step_keys(ws, keys)
    case Some{+n}: live_server(ws, n)

def live_step.enter(+ws: Workspace, +keys: Sess.Keys, +typed: String, enter: Bool) -> Workspace & Sid.RoutedCmd & Bool:
  match enter:
    case False{}: step_keys(ws, keys)
    case True{}: live_step.arg(ws, keys, server_arg(typed))

def live_step_keys(+ws: Workspace, +keys: Sess.Keys) -> Workspace & Sid.RoutedCmd & Bool:
  match keys:
    case Sess.Keys{+typed, enter, _, _, _, _, _, _, _}: live_step.enter(ws, keys, typed, enter)

# Quit broadcast. step_keys.routed still returns one RoutedCmd for the
# focused part (the isolation proof mirrors that shape). A /quit Cont
# also needs the same QUIT lines on every other live part's current
# writer; generations stay on those writers, so this list carries no bump.
def quit_line(+line: String) -> Bool:
  String.eq(String.take(line, 5n), "QUIT ")

def quit_lines.keep(hit: Bool, +h: String, +rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}: h <> rest
    case False{}: rest

def quit_lines(+xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, +t}: quit_lines.keep(quit_line(h), h, quit_lines(t))

def quit_broadcast.skip(same: Bool, +id: Key.ServerId, +outs: List<&2, String>, +rest: List<&2, Sid.RoutedCmd>) -> List<&2, Sid.RoutedCmd>:
  match same:
    case True{}: rest
    case False{}: Sid.RoutedCmd{id, Sess.Cont{outs}} <> rest

def quit_broadcast.parts(+parts: List<&2, Part>, +focus: Key.ServerId, +outs: List<&2, String>) -> List<&2, Sid.RoutedCmd>:
  match parts:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      quit_broadcast.skip(Key.eq(part_id(h), focus), part_id(h), outs, quit_broadcast.parts(t, focus, outs))

def quit_broadcast.lines(empty: Bool, +parts: List<&2, Part>, +focus: Key.ServerId, +outs: List<&2, String>) -> List<&2, Sid.RoutedCmd>:
  match empty:
    case True{}: Nil{}
    case False{}: quit_broadcast.parts(parts, focus, outs)

def quit_broadcast.cmd(+cmd: Sess.NetCmd, +parts: List<&2, Part>, +focus: Key.ServerId) -> List<&2, Sid.RoutedCmd>:
  match cmd:
    case Sess.Cont{+outs}:
      +lines = quit_lines(outs)
      quit_broadcast.lines(List.is_empty(&2, String, lines), parts, focus, lines)
    case _: Nil{}

def quit_broadcast(+ws: Workspace, +rc: Sid.RoutedCmd) -> List<&2, Sid.RoutedCmd>:
  match ws:
    case Workspace{+parts, _, _, _}:
      match rc:
        case Sid.RoutedCmd{+s, +cmd}: quit_broadcast.cmd(cmd, parts, s)

# Frame-path typing tick through the shared G6 owner: after keys apply, step
# the current part's stored Reg and merge at most one TAGMSG wire into the
# frame's own Cont output. Halt frames and non-Cont commands return untouched
# (no stepping, no wire), so a live span survives for the next tick.
def live_frame_tick.applied(pair: Sess.Session & Sess.NetCmd, +parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +id: Key.ServerId, +gen: U32, +scope: Sid.Scope, +s: Key.ServerId, +halt: Bool) -> Workspace & Sid.RoutedCmd & Bool:
  match pair:
    case (+st3, +cmd3):
      (Workspace{replace_part.go(parts, id, Part{id, gen, scope, st3}), cur, ds, rt}, Sid.RoutedCmd{s, cmd3}, halt)

def live_frame_tick.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +p: Part, +cmd: Sess.NetCmd, +s: Key.ServerId, +halt: Bool, +now_ms: U32) -> Workspace & Sid.RoutedCmd & Bool:
  match p:
    case Part{+id, +gen, +scope, +st}:
      live_frame_tick.applied(Sess.frame_tick_typing(cmd, st, now_ms, halt), parts, cur, ds, rt, id, gen, scope, s, halt)

def live_frame_tick.found(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +got: Maybe<&2, Part>, +cmd: Sess.NetCmd, +s: Key.ServerId, +halt: Bool, +now_ms: U32) -> Workspace & Sid.RoutedCmd & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, Sid.RoutedCmd{s, cmd}, halt)
    case Some{+p}: live_frame_tick.part(parts, cur, ds, rt, p, cmd, s, halt, now_ms)

def live_frame_tick.ws(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rc: Sid.RoutedCmd, +halt: Bool, +now_ms: U32) -> Workspace & Sid.RoutedCmd & Bool:
  match rc:
    case Sid.RoutedCmd{+s, +cmd}: live_frame_tick.found(parts, cur, ds, rt, find_part.go(parts, s), cmd, s, halt, now_ms)

def live_frame_tick.rc(+ws2: Workspace, +rc: Sid.RoutedCmd, +halt: Bool, +now_ms: U32) -> Workspace & Sid.RoutedCmd & Bool:
  match ws2:
    case Workspace{+parts, +cur, +ds, +rt}: live_frame_tick.ws(parts, cur, ds, rt, rc, halt, now_ms)

def live_step_keys_typing.go.r1(rest: Sid.RoutedCmd & Bool, +ws2: Workspace, +now_ms: U32) -> Workspace & Sid.RoutedCmd & Bool:
  match rest:
    case (+rc, +halt): live_frame_tick.rc(ws2, rc, halt, now_ms)

def live_step_keys_typing.go(trip: Workspace & Sid.RoutedCmd & Bool, +now_ms: U32) -> Workspace & Sid.RoutedCmd & Bool:
  match trip:
    case (+ws2, rest): live_step_keys_typing.go.r1(rest, ws2, now_ms)

def live_step_keys_typing(+ws: Workspace, +keys: Sess.Keys, +now_ms: U32) -> Workspace & Sid.RoutedCmd & Bool:
  live_step_keys_typing.go(live_step_keys(ws, keys), now_ms)

def live_do_step.got(trip: Workspace & Sid.RoutedCmd & Bool) -> Workspace:
  match trip:
    case (ws2, _): ws2

def live_do_step(+ws: Workspace, +keys: Sess.Keys) -> Workspace:
  live_do_step.got(live_step_keys(ws, keys))

def live_step_routed.got.r1(rest: Sid.RoutedCmd & Bool) -> Sid.RoutedCmd:
  match rest:
    case (+rc, _): rc

def live_step_routed.got(trip: Workspace & Sid.RoutedCmd & Bool) -> Sid.RoutedCmd:
  match trip:
    case (_, rest): live_step_routed.got.r1(rest)

def live_step_routed(+ws: Workspace, +keys: Sess.Keys) -> Sid.RoutedCmd:
  live_step_routed.got(live_step_keys(ws, keys))

def live_step_halt.got.r1(rest: Sid.RoutedCmd & Bool) -> Bool:
  match rest:
    case (_, +halt): halt

def live_step_halt.got(trip: Workspace & Sid.RoutedCmd & Bool) -> Bool:
  match trip:
    case (_, rest): live_step_halt.got.r1(rest)

def live_step_halt(+ws: Workspace, +keys: Sess.Keys) -> Bool:
  live_step_halt.got(live_step_keys(ws, keys))

def id_nat(+id: Key.ServerId) -> Nat:
  match id:
    case Key.ServerId{+n}: n

def next_above.pick(hit: Bool, +n: Nat, +cont: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}: Some{n}
    case False{}: cont

def next_above.go(fuel: Nat, +parts: List<&2, Part>, +cur: Nat, +n: Nat) -> Maybe<&2, Nat>:
  match fuel:
    case 0n: None{}
    case 1n+p: next_above.pick(Nat.is_gt(n, cur) && id_used.go(parts, n), n, next_above.go(p, parts, cur, Nat.add(n, 1n)))

def next_first.pick(used: Bool, +n: Nat, +cont: Nat) -> Nat:
  match used:
    case True{}: n
    case False{}: cont

def next_first.go(fuel: Nat, +parts: List<&2, Part>, +n: Nat) -> Nat:
  match fuel:
    case 0n: 0n
    case 1n+p: next_first.pick(id_used.go(parts, n), n, next_first.go(p, parts, Nat.add(n, 1n)))

def next_id.above(+parts: List<&2, Part>, +above: Maybe<&2, Nat>) -> Nat:
  match above:
    case Some{+n}: n
    case None{}: next_first.go(4n, parts, 0n)

def next_id(+parts: List<&2, Part>, +cur: Nat) -> Nat:
  next_id.above(parts, next_above.go(4n, parts, cur, 0n))

def cycle_server.switched(+parts: List<&2, Part>, +cur: Key.ServerId, +ds2: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +nxt: Nat, +got: Maybe<&2, Part>) -> Workspace & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds2, rt}, False{})
    case Some{+p}:
      match p:
        case Part{+nid, +ngen, +nscope, +nst}:
          +loaded = Drafts.get_cm(ds2, nid, AD.active_key(Sess.session_cl(nst)), Sess.session_cm(nst))
          +reseeded = Sess.session_upload_draft(nst, loaded, 1)
          (Workspace{replace_part.go(parts, nid, Part{nid, ngen, nscope, reseeded}), nid, ds2, rt}, True{})

def cycle_server.admits(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +typed: String, +oldkey: String, +nxt: Nat, +cm: String, admits: Bool) -> Workspace & Bool:
  match admits:
    case False{}: (Workspace{parts, cur, ds, rt}, False{})
    case True{}:
      +ds2 = Drafts.set_cm(ds, cur, oldkey, typed, cm)
      cycle_server.switched(parts, cur, ds2, rt, nxt, find_part.go(parts, Key.ServerId{nxt}))

def cycle_server.same(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +typed: String, +oldkey: String, +nxt: Nat, +cm: String, same: Bool) -> Workspace & Bool:
  match same:
    case True{}: (Workspace{parts, cur, ds, rt}, False{})
    case False{}: cycle_server.admits(parts, cur, ds, rt, typed, oldkey, nxt, cm, Drafts.focus_admits_cm(ds, cur, oldkey, typed, cm))

def cycle_server.cur(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +typed: String, +got: Maybe<&2, Part>) -> Workspace & Bool:
  match got:
    case None{}: (Workspace{parts, cur, ds, rt}, False{})
    case Some{+p}:
      match p:
        case Part{_, _, _, +st}:
          cycle_server.same(parts, cur, ds, rt, typed, AD.active_key(Sess.session_cl(st)), next_id(parts, id_nat(cur)), Sess.session_cm(st), Nat.is_eq(next_id(parts, id_nat(cur)), id_nat(cur)))

def cycle_server(+ws: Workspace, +typed: String) -> Workspace & Bool:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      cycle_server.cur(parts, cur, ds, rt, typed, find_part.go(parts, cur))

def cycle_ws(pair: Workspace & Bool) -> Workspace:
  match pair:
    case (+ws2, _): ws2

def cycle_moved(pair: Workspace & Bool) -> Bool:
  match pair:
    case (_, moved): moved

# The live loop applies the painted rows/cols to the current part every
# frame (mirroring single-server step_size); siblings keep their sizes.
def set_current_size.part(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rows: U32, +cols: U32, +p: Part) -> Workspace:
  match p:
    case Part{+id, +gen, +scope, +st}:
      Workspace{replace_part.go(parts, id, Part{id, gen, scope, Sess.session_set_size(st, rows, cols)}), cur, ds, rt}

def set_current_size.got(+parts: List<&2, Part>, +cur: Key.ServerId, +ds: Drafts.Drafts, +rt: List<&2, SlotEpoch>, +rows: U32, +cols: U32, +got: Maybe<&2, Part>) -> Workspace:
  match got:
    case None{}: Workspace{parts, cur, ds, rt}
    case Some{+p}: set_current_size.part(parts, cur, ds, rt, rows, cols, p)

def set_current_size(+ws: Workspace, +rows: U32, +cols: U32) -> Workspace:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      set_current_size.got(parts, cur, ds, rt, rows, cols, find_part.go(parts, cur))

# The live loop queries terminal image support once after opening the UI
# and applies it to every part (mirroring single-server open_watch).
def set_media_supported.go(fuel: Nat, +parts: List<&2, Part>, +on: Bool) -> List<&2, Part>:
  match fuel:
    case 0n: parts
    case 1n+p:
      match parts:
        case Nil{}: Nil{}
        case Con{+h, +t}:
          match h:
            case Part{+id, +gen, +scope, +st}:
              Part{id, gen, scope, Sess.session_set_media(st, M.set_supported(Sess.session_media(st), on))} <> set_media_supported.go(p, t, on)

def set_media_supported(+ws: Workspace, +on: Bool) -> Workspace:
  match ws:
    case Workspace{+parts, +cur, +ds, +rt}:
      Workspace{set_media_supported.go(4n, parts, on), cur, ds, rt}

# ---- stepping helpers (shared with goldens) -------------------------------

def do_step.got(trip: Workspace & Sid.RoutedCmd & Bool) -> Workspace:
  match trip:
    case (ws2, _): ws2

def do_step(+ws: Workspace, +keys: Sess.Keys) -> Workspace:
  do_step.got(step_keys(ws, keys))

def do_enter(+ws: Workspace, +line: String) -> Workspace:
  do_step(ws, Sess.keys_enter(line))

def step_routed.got.r1(rest: Sid.RoutedCmd & Bool) -> Sid.RoutedCmd:
  match rest:
    case (+rc, _): rc

def step_routed.got(trip: Workspace & Sid.RoutedCmd & Bool) -> Sid.RoutedCmd:
  match trip:
    case (_, rest): step_routed.got.r1(rest)

def step_routed(+ws: Workspace, +keys: Sess.Keys) -> Sid.RoutedCmd:
  step_routed.got(step_keys(ws, keys))

def do_add.got(pair: Workspace & Bool) -> Workspace:
  match pair:
    case (ws2, _): ws2

def do_add(+ws: Workspace, +host: String, +port: U32, v6: Bool, +nick: String, +chan: String) -> Workspace:
  do_add.got(add_server(ws, host, port, v6, nick, chan))

def do_switch.got(pair: Workspace & Bool) -> Workspace:
  match pair:
    case (ws2, _): ws2

def do_switch(+ws: Workspace, +id: Key.ServerId) -> Workspace:
  do_switch.got(switch_server(ws, id))

def do_replace.got(pair: Workspace & Bool) -> Workspace:
  match pair:
    case (ws2, _): ws2

def do_replace(+ws: Workspace, +id: Key.ServerId, +host: String, +port: U32, v6: Bool) -> Workspace:
  do_replace.got(replace_server(ws, id, host, port, v6))

def do_remove.got(pair: Workspace & Bool) -> Workspace:
  match pair:
    case (ws2, _): ws2

def do_remove(+ws: Workspace, +id: Key.ServerId) -> Workspace:
  do_remove.got(remove_server(ws, id))

def do_on_chunk.got(pair: Workspace & List<&2, String>) -> Workspace:
  match pair:
    case (+ws2, _): ws2

def do_on_chunk(+ws: Workspace, +rm: Sid.RoutedMsg, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Workspace:
  do_on_chunk.got(on_routed_chunk(ws, rm, stamps, now_ms))

def on_chunk_outs.got(pair: Workspace & List<&2, String>) -> String:
  match pair:
    case (ws2, +outs): String.join(outs, "|")

def on_chunk_outs(+ws: Workspace, +rm: Sid.RoutedMsg, +stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> String:
  on_chunk_outs.got(on_routed_chunk(ws, rm, stamps, now_ms))

def do_on_fail.got(+res: FailResult) -> Workspace:
  match res:
    case FailResult{+ws2, _, _}: ws2

def do_on_fail(+ws: Workspace, +rm: Sid.RoutedMsg, +ts: String) -> Workspace:
  do_on_fail.got(on_routed_fail(ws, rm, ts))

def on_fail_cmd.got(+res: FailResult) -> Maybe<&2, Sid.RoutedCmd>:
  match res:
    case FailResult{_, +cmd, _}: cmd

def on_fail_cmd(+ws: Workspace, +rm: Sid.RoutedMsg, +ts: String) -> Maybe<&2, Sid.RoutedCmd>:
  on_fail_cmd.got(on_routed_fail(ws, rm, ts))

def on_fail_intent.got(+res: FailResult) -> Maybe<&2, Sid.Intent>:
  match res:
    case FailResult{_, _, +intent}: intent

def on_fail_intent(+ws: Workspace, +rm: Sid.RoutedMsg, +ts: String) -> Maybe<&2, Sid.Intent>:
  on_fail_intent.got(on_routed_fail(ws, rm, ts))

def do_redial.got(pair: Workspace & Maybe<&2, Sid.RoutedCmd>) -> Workspace:
  match pair:
    case (+ws2, _): ws2

def do_redial(+ws: Workspace, +id: Key.ServerId, +intent: Sid.Intent) -> Workspace:
  do_redial.got(on_redial(ws, id, intent))

def redial_cmd.got(pair: Workspace & Maybe<&2, Sid.RoutedCmd>) -> Maybe<&2, Sid.RoutedCmd>:
  match pair:
    case (ws2, +cmd): cmd

def redial_cmd(+ws: Workspace, +id: Key.ServerId, +intent: Sid.Intent) -> Maybe<&2, Sid.RoutedCmd>:
  redial_cmd.got(on_redial(ws, id, intent))

# ---- proof-facing fixtures and predicates ---------------------------------
# Small fixed fixtures mirroring the golden assertions. Nullary like the
# sibling Drafts/Sid predicates.

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

def bad4() -> Key.ServerId:
  Key.ServerId{4n}

def fx_pair() -> Workspace:
  do_add(single("a.example", 6697, False{}, "me", "#a"), "b.example", 6697, False{}, "me", "#b")

def fx_online.got(+got: Maybe<&2, Part>, +ws: Workspace) -> Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case Part{+id, +gen, +scope, +st}:
          replace_part(ws, Part{id, gen, scope, Sess.session_online(st)})

def fx_online(+ws: Workspace, +id: Key.ServerId) -> Workspace:
  fx_online.got(find_part(ws, id), ws)

def fx_rooms() -> Workspace:
  +ws = fx_online(fx_online(fx_pair(), s0()), s1())
  do_enter(do_switch(do_enter(ws, "/join #a"), s1()), "/join #b")

def isolation.client_of.got(+got: Maybe<&2, Part>) -> Cl.Client:
  match got:
    case None{}: Cl.init("nobody", "nowhere.example")
    case Some{+p}: Sess.session_cl(part_session(p))

def isolation.client_of(+ws: Workspace, +id: Key.ServerId) -> Cl.Client:
  isolation.client_of.got(find_part(ws, id))

def routed_cmd(+rc: Sid.RoutedCmd) -> Sess.NetCmd:
  match rc:
    case Sid.RoutedCmd{_, +cmd}: cmd

def routed_server(+rc: Sid.RoutedCmd) -> Key.ServerId:
  match rc:
    case Sid.RoutedCmd{+s, _}: s

def part_gen_of.got(+got: Maybe<&2, Part>) -> U32:
  match got:
    case None{}: 0
    case Some{+p}: part_gen(p)

def part_gen_of(+ws: Workspace, +id: Key.ServerId) -> U32:
  part_gen_of.got(find_part(ws, id))

def isolation_ok.step(+ws: Workspace, trip: Workspace & Sid.RoutedCmd & Bool) -> Bool:
  match trip:
    case (+stepped, +rc, _):
      +a_before = isolation.client_of(ws, s0())
      +a_after = isolation.client_of(stepped, s0())
      +b_bufs = List.length(&2, Cl.Buffer, Cl.client_bufs(isolation.client_of(stepped, s1())))
      Nat.is_eq(List.length(&2, Cl.Buffer, Cl.client_bufs(a_before)), List.length(&2, Cl.Buffer, Cl.client_bufs(a_after)))
        && Nat.is_eq(b_bufs, 3n)
        && String.eq(Sess.show_netcmd(routed_cmd(rc)), "cont")

def isolation_ok() -> Bool:
  +ws = fx_rooms()
  isolation_ok.step(ws, step_keys(ws, Sess.keys_enter("/join #extra")))

def generation_ok() -> Bool:
  +ws = fx_online(fx_pair(), s0())
  +dialed = do_enter(ws, "/connect c.example 6697")
  +gen1 = part_gen_of(dialed, s0())
  +stale_dial = Sid.dial_for(s0(), "c.example", 6697, 0, "me")
  +fresh_dial = Sid.dial_for(s0(), "c.example", 6697, gen1, "me")
  +stale_msg : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Eof{}}}
  +fresh_msg : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{gen1, Sess.Eof{}}}
  +done : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{gen1, Sess.WriterDone{}}}
  +done_stale : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.WriterDone{}}}
  +done_other : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{gen1, Sess.WriterDone{}}}
  +cross : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{gen1, Sess.Eof{}}}
  U32.is_eq(gen1, 1)
    && Bool.not(cmd_admitted(dialed, stale_dial))
    && cmd_admitted(dialed, fresh_dial)
    && Bool.not(cmd_admitted(dialed, Sid.dial_for(bad4(), "c.example", 6697, gen1, "me")))
    && Bool.not(msg_admitted(dialed, stale_msg))
    && msg_admitted(dialed, fresh_msg)
    && Bool.not(msg_admitted(dialed, cross))
    && writer_done_acked(dialed, done)
    && Bool.not(writer_done_acked(dialed, done_stale))
    && Bool.not(writer_done_acked(dialed, done_other))

def endpoint_ok() -> Bool:
  +ws = fx_pair()
  +typed = do_step(ws, AD.typing_keys("aa"))
  +same = do_replace(typed, s0(), "a.example", 6697, False{})
  +moved = do_replace(typed, s0(), "c.example", 6697, False{})
  +cased = do_replace(typed, s0(), "A.example", 6697, False{})
  Drafts.has(ws_drafts(same), s0(), AD.active_key(isolation.client_of(same, s0())))
    && Bool.not(Drafts.has(ws_drafts(moved), s0(), AD.active_key(isolation.client_of(typed, s0()))))
    && Bool.not(credential_ok(moved, s0(), "a.example", 6697))
    && credential_ok(same, s0(), "a.example", 6697)
    && Bool.not(credential_ok(cased, s0(), "a.example", 6697))
    && history_admits(same, s0(), "A.Example:6697")
    && Bool.not(history_admits(same, s0(), "b.example:6697"))

def s3_composer.got(+got: Maybe<&2, Part>) -> String:
  match got:
    case None{}: "[none]"
    case Some{+p}: Sess.session_draft(part_session(p))

def s3_composer(+ws: Workspace, +id: Key.ServerId) -> String:
  s3_composer.got(find_part(ws, id))

def s3_seed.got(+got: Maybe<&2, Part>) -> U32:
  match got:
    case None{}: 0
    case Some{+p}: Sess.session_seed(part_session(p))

def s3_seed(+ws: Workspace, +id: Key.ServerId) -> U32:
  s3_seed.got(find_part(ws, id))

def s3_tab_keys(+typed: String) -> Sess.Keys:
  Sess.Keys{typed, False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 1, 0}

def s3_comp.show(+c: Sess.Comp) -> String:
  match c:
    case Sess.CompNone{}: "N"
    case Sess.CompActive{+pre, +word, idx}: "A:" ++ pre ++ "|" ++ word ++ "|" ++ Nat.show(idx)
    case Sess.CompUpload{_, _, _}: "U"
    case Sess.CompHelp{_}: "H"
    case Sess.CompHidden{}: "D"
    case Sess.CompPick{idx}: "P:" ++ Nat.show(idx)

def s3_comp.st(+st: Sess.Session) -> String:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, _, _, _, +comp, _, _, _, _, _, _, _, _, _, _, _, _, _}: s3_comp.show(comp)

def s3_comp.got(+got: Maybe<&2, Part>) -> String:
  match got:
    case None{}: "[none]"
    case Some{+p}: s3_comp.st(part_session(p))

def s3_comp(+ws: Workspace, +id: Key.ServerId) -> String:
  s3_comp.got(find_part(ws, id))

def epoch_readd_ok() -> Bool:
  +base = fx_pair()
  +removed = do_remove(base, s1())
  +readded = do_add(removed, "b.example", 6697, False{}, "me", "#b")
  +newgen = part_gen_of(readded, s1())
  +old_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{Nil{}, 0}}}
  +old_done : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.WriterDone{}}}
  +old_intent : Sid.Intent = Sid.Intent{s1(), 0, "b.example", 6697, False{}}
  +fresh_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{newgen, Sess.Chunk{Nil{}, 0}}}
  +sib_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{Nil{}, 0}}}
  Bool.not(U32.is_eq(newgen, 0))
    && Bool.not(msg_admitted(readded, old_chunk))
    && Bool.not(writer_done_acked(readded, old_done))
    && Bool.not(redial_ok(readded, s1(), old_intent))
    && msg_admitted(readded, fresh_chunk)
    && msg_admitted(readded, sib_chunk)

def epoch_redial_setup() -> Workspace:
  +on = fx_online(fx_pair(), s1())
  +dialed = do_enter(do_switch(on, s1()), "/connect c.example 6697")
  +removed2 = do_remove(dialed, s1())
  +readded2 = do_add(removed2, "c.example", 6697, False{}, "me", "#c")
  do_enter(do_switch(readded2, s1()), "/connect c.example 6697")

def epoch_redial_gen_ok() -> Bool:
  Bool.not(U32.is_eq(part_gen_of(epoch_redial_setup(), s1()), 1))

def epoch_redial_stale_chunk_ok() -> Bool:
  +redialed = epoch_redial_setup()
  Bool.not(msg_admitted(redialed, Sid.RoutedMsg{s1(), Sess.FromNet{1, Sess.Chunk{Nil{}, 0}}}))

def epoch_redial_stale_done_ok() -> Bool:
  +redialed = epoch_redial_setup()
  Bool.not(writer_done_acked(redialed, Sid.RoutedMsg{s1(), Sess.FromNet{1, Sess.WriterDone{}}}))

def epoch_redial_stale_intent_ok() -> Bool:
  +redialed = epoch_redial_setup()
  Bool.not(redial_ok(redialed, s1(), Sid.Intent{s1(), 1, "c.example", 6697, False{}}))

def epoch_redial_fresh_ok() -> Bool:
  +redialed = epoch_redial_setup()
  msg_admitted(redialed, Sid.RoutedMsg{s1(), Sess.FromNet{part_gen_of(redialed, s1()), Sess.Chunk{Nil{}, 0}}})

def epoch_redial_sibling_ok() -> Bool:
  msg_admitted(epoch_redial_setup(), Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{Nil{}, 0}}})

def epoch_redial_ok() -> Bool:
  epoch_redial_gen_ok()
    && epoch_redial_stale_chunk_ok()
    && epoch_redial_stale_done_ok()
    && epoch_redial_stale_intent_ok()
    && epoch_redial_fresh_ok()
    && epoch_redial_sibling_ok()

def epoch_reuse_ok() -> Bool:
  epoch_readd_ok() && epoch_redial_ok()

def composer_text_ok() -> Bool:
  +base = fx_rooms()
  +s0sw = do_switch(base, s0())
  +typed = do_step(s0sw, AD.typing_keys("aa"))
  +both = do_step(do_switch(typed, s1()), AD.typing_keys("bb"))
  +moved = do_replace(both, s0(), "c.example", 6697, False{})
  +same = do_replace(both, s0(), "a.example", 6697, False{})
  +port = do_replace(both, s0(), "a.example", 6698, False{})
  +back = do_switch(moved, s0())
  Bool.not(Drafts.has(ws_drafts(moved), s0(), "#a"))
    && String.eq(s3_composer(moved, s0()), "")
    && U32.is_eq(s3_seed(moved, s0()), 1)
    && String.eq(s3_composer(back, s0()), "")
    && String.eq(s3_composer(port, s0()), "")
    && Drafts.has(ws_drafts(same), s0(), "#a")
    && String.eq(s3_composer(same, s0()), "aa")
    && String.eq(Drafts.get(ws_drafts(moved), s1(), "#b"), "bb")
    && String.eq(s3_composer(moved, s1()), "bb")

def composer_completion_ok() -> Bool:
  +base = fx_rooms()
  +c_tab0 = do_step(do_switch(base, s0()), s3_tab_keys("old /j"))
  +c_both = do_step(do_switch(c_tab0, s1()), s3_tab_keys("old /j"))
  +c_moved = do_replace(c_both, s0(), "c.example", 6697, False{})
  +c_port = do_replace(c_both, s0(), "a.example", 6698, False{})
  +c_same = do_replace(c_both, s0(), "a.example", 6697, False{})
  +c_next = do_step(do_switch(c_moved, s0()), s3_tab_keys(""))
  +c_next_port = do_step(do_switch(c_port, s0()), s3_tab_keys(""))
  +c_next_same = do_step(do_switch(c_same, s0()), s3_tab_keys(""))
  +c_next_sib = do_step(do_switch(c_moved, s1()), s3_tab_keys(""))
  String.eq(s3_comp(c_both, s0()), "A:old |/j|0")
    && String.eq(s3_comp(c_moved, s0()), "N")
    && Bool.not(String.eq(s3_composer(c_next, s0()), "old /join "))
    && String.eq(s3_composer(c_next, s0()), "")
    && String.eq(s3_comp(c_port, s0()), "N")
    && Bool.not(String.eq(s3_composer(c_next_port, s0()), "old /join "))
    && String.eq(s3_comp(c_same, s0()), "A:old |/j|0")
    && String.eq(s3_composer(c_next_same, s0()), "old /join ")
    && String.eq(s3_comp(c_moved, s1()), "A:old |/j|0")
    && String.eq(s3_composer(c_next_sib, s1()), "old /join ")

def composer_reset_ok() -> Bool:
  composer_text_ok() && composer_completion_ok()

def rt_session.got(+got: Maybe<&2, Part>) -> Sess.Session:
  match got:
    case None{}: Sess.session_demo(Cl.init("nobody", "nowhere.example"), "#lost")
    case Some{+p}: part_session(p)

def rt_session(+ws: Workspace, +id: Key.ServerId) -> Sess.Session:
  rt_session.got(find_part(ws, id))

def rt_net(+ws: Workspace, +id: Key.ServerId) -> String:
  Sess.net_label(Sess.session_net(rt_session(ws, id)))

def rt_texts(+ws: Workspace, +id: Key.ServerId, +i: Nat) -> String:
  CL.buf_texts(Sess.session_cl(rt_session(ws, id)), i)

def rt_nbufs(+ws: Workspace, +id: Key.ServerId) -> Nat:
  List.length(&2, Cl.Buffer, Cl.client_bufs(Sess.session_cl(rt_session(ws, id))))

def dial_exact(+cmd: Sess.NetCmd, +host: String, +port: U32, +gen: U32, +nick: String) -> Bool:
  match cmd:
    case Sess.Dial{+h, p, g, +n}: String.eq(h, host) && U32.is_eq(p, port) && U32.is_eq(g, gen) && String.eq(n, nick)
    case _: False{}

def routed_dial_exact(+rc: Sid.RoutedCmd, +id: Key.ServerId, +host: String, +port: U32, +gen: U32, +nick: String) -> Bool:
  match rc:
    case Sid.RoutedCmd{+s, +cmd}: Key.eq(s, id) && dial_exact(cmd, host, port, gen, nick)

def drop_cmd(+cmd: Sess.NetCmd) -> Bool:
  match cmd:
    case Sess.Drop{}: True{}
    case _: False{}

def hangup_cmd(+cmd: Sess.NetCmd) -> Bool:
  match cmd:
    case Sess.Hangup{}: True{}
    case _: False{}

def routed_drop.rc(+rc: Sid.RoutedCmd, +id: Key.ServerId) -> Bool:
  match rc:
    case Sid.RoutedCmd{+s, +cmd}: Key.eq(s, id) && drop_cmd(cmd)

def routed_drop(+got: Maybe<&2, Sid.RoutedCmd>, +id: Key.ServerId) -> Bool:
  match got:
    case None{}: False{}
    case Some{+rc}: routed_drop.rc(rc, id)

def redial_emits(+got: Maybe<&2, Sid.RoutedCmd>, +id: Key.ServerId, +host: String, +port: U32, +gen: U32, +nick: String) -> Bool:
  match got:
    case None{}: False{}
    case Some{+rc}: routed_dial_exact(rc, id, host, port, gen, nick)

def intent_fields(+i: Sid.Intent, +id: Key.ServerId, +gen: U32, +host: String, +port: U32, +v6: Bool) -> Bool:
  match i:
    case Sid.Intent{+s, g, +h, p, +v}:
      Key.eq(s, id) && U32.is_eq(g, gen) && String.eq(h, host) && U32.is_eq(p, port) && Sid.bool_eq(v, v6)

def intent_exact(+got: Maybe<&2, Sid.Intent>, +id: Key.ServerId, +gen: U32, +host: String, +port: U32, +v6: Bool) -> Bool:
  match got:
    case None{}: False{}
    case Some{+i}: intent_fields(i, id, gen, host, port, v6)

def is_none.rc(+got: Maybe<&2, Sid.RoutedCmd>) -> Bool:
  match got:
    case None{}: True{}
    case Some{_}: False{}

def is_none.intent(+got: Maybe<&2, Sid.Intent>) -> Bool:
  match got:
    case None{}: True{}
    case Some{_}: False{}

def intent_or_live(+got: Maybe<&2, Sid.Intent>) -> Sid.Intent:
  match got:
    case None{}: Sid.Intent{bad4(), 0, "dead.invalid", 0, False{}}
    case Some{+i}: i

def runtime_up_s0_ok() -> Bool:
  +up0 = on_routed_up(fx_pair(), Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}, "00:00:01")
  String.eq(rt_net(up0, s0()), "online")

def runtime_up_s1_connecting_ok() -> Bool:
  +up0 = on_routed_up(fx_pair(), Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}, "00:00:01")
  String.eq(rt_net(up0, s1()), "connecting")

def runtime_up_s1_bufs_ok() -> Bool:
  +up0 = on_routed_up(fx_pair(), Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}, "00:00:01")
  Nat.is_eq(rt_nbufs(up0, s1()), 1n)

def runtime_up_s1_online_ok() -> Bool:
  +up0 = on_routed_up(fx_pair(), Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}, "00:00:01")
  +up1 = on_routed_up(do_switch(up0, s1()), Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Up{}}}, "00:00:02")
  String.eq(rt_net(up1, s1()), "online")

def runtime_up_ok() -> Bool:
  runtime_up_s0_ok()
    && runtime_up_s1_connecting_ok()
    && runtime_up_s1_bufs_ok()
    && runtime_up_s1_online_ok()

def runtime_submit_ok() -> Bool:
  +pair = fx_pair()
  +up0 = on_routed_up(pair, Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}, "00:00:01")
  +up1 = on_routed_up(do_switch(up0, s1()), Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Up{}}}, "00:00:02")
  +j0 = do_enter(do_switch(up1, s0()), "/join #a")
  +j1 = do_enter(do_switch(j0, s1()), "/join #b")
  +hi = do_enter(j1, "s1hi")
  String.eq(rt_texts(hi, s1(), 1n), "<me> s1hi|")

def runtime_chunk_ok() -> Bool:
  +pair = fx_pair()
  +up0 = on_routed_up(pair, Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}, "00:00:01")
  +up1 = on_routed_up(do_switch(up0, s1()), Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Up{}}}, "00:00:02")
  +j0 = do_enter(do_switch(up1, s0()), "/join #a")
  +j1 = do_enter(do_switch(j0, s1()), "/join #b")
  +hi = do_enter(j1, "s1hi")
  +stamps : List<&2, Maybe<&2, String>> = None{} <> Nil{}
  +chunk : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{Fr.string_to_octets(":alice!x@y PRIVMSG #a :hi\r\n"), 0}}}
  +in0 = do_on_chunk(hi, chunk, stamps, 0)
  +stale : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{7, Sess.Chunk{Fr.string_to_octets(":mallory!x@y PRIVMSG #a :yo\r\n"), 0}}}
  +unk : Sid.RoutedMsg = Sid.RoutedMsg{bad4(), Sess.FromNet{0, Sess.Chunk{Fr.string_to_octets(":mallory!x@y PRIVMSG #a :yo\r\n"), 0}}}
  String.eq(on_chunk_outs(hi, chunk, stamps, 0), "")
    && String.eq(rt_texts(in0, s0(), 1n), "<alice> hi|")
    && String.eq(rt_texts(in0, s1(), 1n), "<me> s1hi|")
    && String.eq(on_chunk_outs(in0, stale, stamps, 0), "")
    && String.eq(rt_texts(do_on_chunk(in0, stale, stamps, 0), s0(), 1n), "<alice> hi|")
    && String.eq(rt_texts(do_on_chunk(in0, unk, stamps, 0), s0(), 1n), "<alice> hi|")

def runtime_inbound_ok() -> Bool:
  runtime_up_ok() && runtime_submit_ok() && runtime_chunk_ok()

def runtime_redial_ok() -> Bool:
  +pair = fx_pair()
  +up0 = on_routed_up(pair, Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}, "00:00:01")
  +set0 = do_enter(up0, "/set autoreconn on")
  +dialed = do_step(set0, Sess.keys_enter("/connect d.example 6697"))
  +rc = step_routed(set0, Sess.keys_enter("/connect d.example 6697"))
  +up_stale = on_routed_up(dialed, Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}, "00:00:03")
  +up_fresh = on_routed_up(dialed, Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Up{}}}, "00:00:04")
  +eof : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Eof{}}}
  +eof_stale : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Eof{}}}
  +fail = do_on_fail(up_fresh, eof, "00:00:05")
  +fail_stale = do_on_fail(up_fresh, eof_stale, "00:00:05")
  +intent = on_fail_intent(up_fresh, eof, "00:00:05")
  +red = do_redial(fail, s0(), intent_or_live(intent))
  +fail_off = do_enter(fail, "/set autoreconn off")
  +red_off = do_redial(fail_off, s0(), intent_or_live(intent))
  +conn_after = step_routed(red_off, Sess.keys_enter("/connect d.example 6697"))
  +stale_red = do_redial(fail, s0(), Sid.Intent{s0(), 0, "d.example", 6697, False{}})
  +stale_off = do_redial(fail_off, s0(), Sid.Intent{s0(), 0, "d.example", 6697, False{}})
  routed_dial_exact(rc, s0(), "d.example", 6697, 1, "me")
    && U32.is_eq(part_gen_of(dialed, s0()), 1)
    && Nat.is_eq(rt_nbufs(dialed, s0()), 1n)
    && String.eq(rt_net(up_stale, s0()), "connecting")
    && String.eq(rt_net(up_fresh, s0()), "online")
    && routed_drop(on_fail_cmd(up_fresh, eof, "00:00:05"), s0())
    && intent_exact(intent, s0(), 1, "d.example", 6697, False{})
    && String.eq(rt_net(fail, s0()), "connecting")
    && String.eq(rt_net(fail_stale, s0()), "online")
    && is_none.rc(on_fail_cmd(up_fresh, eof_stale, "00:00:05"))
    && is_none.intent(on_fail_intent(up_fresh, eof_stale, "00:00:05"))
    && redial_emits(redial_cmd(fail, s0(), intent_or_live(intent)), s0(), "d.example", 6697, 2, "me")
    && U32.is_eq(part_gen_of(red, s0()), 2)
    && is_none.rc(redial_cmd(fail, s0(), Sid.Intent{s0(), 0, "d.example", 6697, False{}}))
    && is_none.rc(redial_cmd(red, s0(), Sid.Intent{s0(), 2, "evil.example", 6697, False{}}))
    && is_none.rc(redial_cmd(fail_off, s0(), intent_or_live(intent)))
    && String.eq(rt_net(red_off, s0()), "offline")
    && routed_dial_exact(conn_after, s0(), "d.example", 6697, 2, "me")
    && String.eq(rt_net(stale_red, s0()), "connecting")
    && U32.is_eq(part_gen_of(stale_red, s0()), 1)
    && String.eq(rt_net(stale_off, s0()), "connecting")
    && String.eq(Cl.server_of(Sess.session_cl(current_session(dialed))), "d.example")
    && String.eq(Cl.server_of(Sess.session_cl(current_session(do_switch(dialed, s1())))), "b.example")
