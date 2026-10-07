# SPDX-License-Identifier: Apache-2.0
# Workspace isolation observes A's buffer count, B's three buffers, and
# the routed command kind. It does not compare the full Workspace state.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/server_key.bend as Key
import ../../src/bend/drafts.bend as Drafts
import ../../src/bend/workspace.bend as WS

def a_same(+before: WS.Workspace, +after: WS.Workspace) -> Bool:
  Nat.is_eq(
    List.length(&2, Cl.Buffer, Cl.client_bufs(WS.isolation.client_of(before, WS.s0()))),
    List.length(&2, Cl.Buffer, Cl.client_bufs(WS.isolation.client_of(after, WS.s0()))))

def b_three(+after: WS.Workspace) -> Bool:
  Nat.is_eq(List.length(&2, Cl.Buffer, Cl.client_bufs(WS.isolation.client_of(after, WS.s1()))), 3n)

def is_cont(+rc: Sid.RoutedCmd) -> Bool:
  String.eq(Sess.show_netcmd(WS.routed_cmd(rc)), "cont")

def observed(+before: WS.Workspace, +after: WS.Workspace, +rc: Sid.RoutedCmd) -> Bool:
  a_same(before, after) && b_three(after) && is_cont(rc)

def wrapped() -> Bool:
  +ws = WS.fx_rooms()
  observed(ws, WS.do_enter(ws, "/join #extra"), WS.step_routed(ws, Sess.keys_enter("/join #extra")))

def once.got(+ws: WS.Workspace, trip: WS.Workspace & Sid.RoutedCmd & Bool) -> Bool:
  match trip:
    case (+after, +rc, _): observed(ws, after, rc)

def once() -> Bool:
  +ws = WS.fx_rooms()
  once.got(ws, WS.step_keys(ws, Sess.keys_enter("/join #extra")))

# Keep the other two criteria true in each rejection guard.
def rejects_b_without_extra() -> Bool:
  +ws = WS.fx_rooms()
  +rc = WS.step_routed(ws, Sess.keys_enter("/join #extra"))
  a_same(ws, ws) && is_cont(rc) && Bool.not(observed(ws, ws, rc))

def rejects_changed_a.got(+ws: WS.Workspace, trip: WS.Workspace & Sid.RoutedCmd & Bool) -> Bool:
  match trip:
    case (+stepped, +rc, _):
      +after = WS.do_enter(WS.do_switch(stepped, WS.s0()), "/join #wrong")
      b_three(after) && is_cont(rc) && Bool.not(observed(ws, after, rc))

def rejects_changed_a() -> Bool:
  +ws = WS.fx_rooms()
  rejects_changed_a.got(ws, WS.step_keys(ws, Sess.keys_enter("/join #extra")))

def rejects_non_cont() -> Bool:
  +ws = WS.fx_rooms()
  +after = WS.do_enter(ws, "/join #extra")
  +rc = Sid.drop_for(WS.s1())
  a_same(ws, after) && b_three(after) && Bool.not(observed(ws, after, rc))

# Use the actual admitted A/#a and B/#b fixture. Mark original drafts so a
# speculative successful JOIN's changed draft store differs from rollback.
def join_boundary.install(+ws: WS.Workspace, +q: Nat, +got: Maybe<&2, WS.Part>) -> WS.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case WS.Part{+id, +gen, +scope, +st}:
          +cl = Cl.set_log_seq(Sess.session_cl(st), q)
          WS.replace_part(ws, WS.Part{id, gen, scope, Sess.session_set_client(st, cl)})

def join_boundary.prepared(+q: Nat) -> WS.Workspace:
  +ws = WS.fx_rooms()
  +ds = Drafts.set(Drafts.set(WS.ws_drafts(ws), WS.s0(), "#a", "A original"), WS.s1(), "#b", "B original")
  +marked = WS.Workspace{WS.ws_parts(ws), WS.ws_current(ws), ds, WS.ws_retired(ws)}
  join_boundary.install(marked, q, WS.find_part(marked, WS.s1()))

def join_boundary.nbufs(+ws: WS.Workspace, +id: Key.ServerId) -> Nat:
  List.length(&2, Cl.Buffer, Cl.client_bufs(WS.isolation.client_of(ws, id)))

def join_boundary.seq(+ws: WS.Workspace, +id: Key.ServerId) -> Nat:
  Cl.log_seq_of(WS.isolation.client_of(ws, id))

def join_boundary.no_extra.got(got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: True{}
    case Some{_}: False{}

def join_boundary.no_extra(+ws: WS.Workspace) -> Bool:
  join_boundary.no_extra.got(Cl.buf_find(WS.isolation.client_of(ws, WS.s1()), "#extra"))

def join_boundary.empty_cont(+rc: Sid.RoutedCmd) -> Bool:
  match rc:
    case Sid.RoutedCmd{+id, +cmd}:
      match cmd:
        case Sess.Cont{+outs}: Key.eq(id, WS.s1()) && List.is_empty(&2, String, outs)
        case _: False{}

def join_boundary.accepted.got(+before: WS.Workspace, +q: Nat, trip: WS.Workspace & Sid.RoutedCmd & Bool) -> Bool:
  match trip:
    case (+after, +rc, _):
      Nat.is_eq(join_boundary.nbufs(before, WS.s0()), join_boundary.nbufs(after, WS.s0()))
        && Nat.is_eq(join_boundary.nbufs(after, WS.s1()), 3n)
        && String.eq(Sess.show_netcmd(WS.routed_cmd(rc)), "cont")
        && Key.eq(WS.routed_server(rc), WS.s1())
        && Nat.is_eq(join_boundary.seq(after, WS.s1()), q)
        && String.eq(Drafts.get(WS.ws_drafts(after), WS.s0(), "#a"), "A original")

def join_boundary.accepted(+q: Nat) -> Bool:
  +before = join_boundary.prepared(q)
  join_boundary.accepted.got(before, q, WS.step_keys(before, Sess.keys_enter("/join #extra")))

def join_boundary.rejected.got(+before: WS.Workspace, +q: Nat, trip: WS.Workspace & Sid.RoutedCmd & Bool) -> Bool:
  match trip:
    case (+after, +rc, halt):
      Nat.is_eq(join_boundary.nbufs(before, WS.s0()), join_boundary.nbufs(after, WS.s0()))
        && Nat.is_eq(join_boundary.nbufs(after, WS.s1()), 2n)
        && join_boundary.no_extra(after)
        && Nat.is_eq(join_boundary.seq(after, WS.s1()), q)
        && Key.eq(WS.ws_current(after), WS.ws_current(before))
        && U32.is_eq(WS.part_gen_of(after, WS.s1()), WS.part_gen_of(before, WS.s1()))
        && Nat.is_eq(WS.ws_nparts(after), WS.ws_nparts(before))
        && Nat.is_eq(List.length(&2, WS.SlotEpoch, WS.ws_retired(after)), List.length(&2, WS.SlotEpoch, WS.ws_retired(before)))
        && String.eq(Drafts.get(WS.ws_drafts(after), WS.s0(), "#a"), "A original")
        && String.eq(Drafts.get(WS.ws_drafts(after), WS.s1(), "#b"), "B original")
        && join_boundary.empty_cont(rc)
        && Bool.not(halt)

def join_boundary.rejected(+q: Nat) -> Bool:
  +before = join_boundary.prepared(q)
  join_boundary.rejected.got(before, q, WS.step_keys(before, Sess.keys_enter("/join #extra")))


def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("isolation predicate accepts the fixed rooms", WS.isolation_ok())
    Unit <- E.must("separate public step projections accept", wrapped())
    Unit <- E.must("one step result accepts", once())
    Unit <- E.must("isolation rejects missing B extra buffer", rejects_b_without_extra())
    Unit <- E.must("isolation rejects changed A buffer count", rejects_changed_a())
    Unit <- E.must("isolation rejects non-Cont command", rejects_non_cont())
    Unit <- E.must("JOIN at base admits with three observations", join_boundary.accepted(WS.id_base(WS.s1())))
    Unit <- E.must("nonallocating JOIN at ceiling minus one admits", join_boundary.accepted(Nat.sub(WS.id_ceiling(WS.s1()), 1n)))
    Unit <- E.must("JOIN at exact ceiling rolls back original drafts", join_boundary.rejected(WS.id_ceiling(WS.s1())))
    Unit <- E.must("JOIN beyond ceiling rolls back original drafts", join_boundary.rejected(Nat.add(WS.id_ceiling(WS.s1()), 1n)))
    IO.print("workspace_isolation_step=ok")
