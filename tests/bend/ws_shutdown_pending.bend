# SPDX-License-Identifier: Apache-2.0
# Pure predicate characterization for the actual multiserver shutdown set.
# No actor, terminal, helper, socket, or timer is started by this fixture.
# Singleton-list Part boxes keep Session captures out of IO continuations;
# multi-part lists are consed one unbox at a time so four live Parts never
# share one flat environment (Client.welcomed pushed Session past the old
# phase-split budget). Main only sequences phases.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/drafts.bend as Drafts
import ../../src/bend/wsnet.bend as WsNet

type PBox is Data:
  PBox{cell: List<&2, W.Part>}

# Singleton-list box: a live Part embeds Session by value, so a handful of
# Parts in one do-block flatten past 247 words. Boxing keeps bind captures
# narrow (media_history / session_drafts_demo idiom); use sites unbox
# transiently. The Nil arm is unreachable by construction.
def pbox(+p: W.Part) -> PBox:
  PBox{p <> Nil{}}

def dead_part() -> W.Part:
  W.Part{Key.ServerId{0n}, 0, Sid.Scope{"", 0, False{}}, Sess.session_demo(Cl.init("x", "x"), "#x")}

def punbox.cell(+cell: List<&2, W.Part>) -> W.Part:
  match cell:
    case Con{+p, _}: p
    case Nil{}: dead_part()

def punbox(+b: PBox) -> W.Part:
  match b:
    case PBox{+cell}: punbox.cell(cell)

def part(+id: Nat, net: Sess.NetState) -> PBox:
  +st = Sess.session_set_net(Sess.session_demo(Cl.init("probe", "shutdown.test"), "#t"), net)
  pbox(W.Part{Key.ServerId{id}, 7, Sid.Scope{"shutdown.test", 6697, False{}}, st})

def ws(+parts: List<&2, W.Part>) -> W.Workspace:
  W.Workspace{parts, Key.first(), Drafts.empty(), Nil{}}

def ids.go(+ids: List<&2, Key.ServerId>, +acc: String) -> String:
  match ids:
    case Nil{}: acc
    case Con{+id, +tail}: ids.go(tail, acc ++ U32.show(Key.slot(id)) ++ ",")

def pending_ids(+parts: List<&2, W.Part>) -> String:
  ids.go(WsNet.ws_pending(ws(parts)), "")

# Unbox at most one Part per call so list construction never holds several
# live Sessions in one flat environment.
def push(+b: PBox, +xs: List<&2, W.Part>) -> List<&2, W.Part>:
  punbox(b) <> xs

def pending1(+b: PBox) -> String:
  pending_ids(push(b, Nil{}))

def ph_connecting() -> IO(Unit):
  +p = part(0n, Sess.Connecting{})
  do IO<Unit>:
    Unit <- E.must_eq("connecting dial cannot delay teardown", pending1(p), "")
    return Unit{}

def ph_reconnecting() -> IO(Unit):
  +p = part(1n, Sess.Reconnecting{})
  do IO<Unit>:
    Unit <- E.must_eq("reconnecting dial cannot delay teardown", pending1(p), "")
    return Unit{}

def ph_online() -> IO(Unit):
  +p = part(0n, Sess.Online{})
  do IO<Unit>:
    Unit <- E.must_eq("healthy online writer must acknowledge", pending1(p), "0,")
    return Unit{}

def ph_offline() -> IO(Unit):
  +p = part(1n, Sess.Offline{})
  do IO<Unit>:
    Unit <- E.must_eq("offline idle writer must acknowledge", pending1(p), "1,")
    return Unit{}

def ph_demo() -> IO(Unit):
  +p = part(2n, Sess.Demo{})
  do IO<Unit>:
    Unit <- E.must_eq("demo idle writer must acknowledge", pending1(p), "2,")
    return Unit{}

def ph_stopping_t() -> IO(Unit):
  +p = part(0n, Sess.Stopping{True{}})
  do IO<Unit>:
    Unit <- E.must_eq("stopping true retains the existing default policy", pending1(p), "0,")
    return Unit{}

def ph_stopping_f() -> IO(Unit):
  +p = part(1n, Sess.Stopping{False{}})
  do IO<Unit>:
    Unit <- E.must_eq("stopping false retains the existing default policy", pending1(p), "1,")
    return Unit{}

# Nested push: each Part is unboxed only inside push, then stored on the
# heap List before the next Part is built.
def mixed_ids() -> String:
  pending_ids(
    push(part(0n, Sess.Online{}),
    push(part(1n, Sess.Connecting{}),
    push(part(2n, Sess.Offline{}),
    push(part(3n, Sess.Reconnecting{}), Nil{})))))

def dials_ids() -> String:
  pending_ids(
    push(part(0n, Sess.Connecting{}),
    push(part(1n, Sess.Reconnecting{}), Nil{})))

def ph_mixed() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("mixed set retains only owned ready writers", mixed_ids(), "0,2,")
    Unit <- E.must_eq("all pending dials permit immediate teardown", dials_ids(), "")
    Unit <- E.must_eq("empty set remains empty", pending_ids(Nil{}), "")
    return Unit{}

def ph_ready() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("idle prefs with history drain still arms a deadline", WsNet.ws_shut.need(False{}, True{}, False{}))
    Unit <- E.must("idle prefs with a writer still arms a deadline", WsNet.ws_shut.need(False{}, False{}, True{}))
    Unit <- E.must("idle prefs and no drain skip the deadline", Bool.not(WsNet.ws_shut.need(False{}, False{}, False{})))
    Unit <- E.must("ready only when prefs hist and writers are clear", WsNet.ws_shut.ready(True{}, False{}, False{}))
    Unit <- E.must("ready rejects unsettled prefs", Bool.not(WsNet.ws_shut.ready(False{}, False{}, False{})))
    Unit <- E.must("ready rejects outstanding history", Bool.not(WsNet.ws_shut.ready(True{}, True{}, False{})))
    Unit <- E.must("ready rejects outstanding writers", Bool.not(WsNet.ws_shut.ready(True{}, False{}, True{})))
    Unit <- E.must("other part hold does not floor slot 0", Nat.is_eq(WsNet.ws_history.hold_in(Nat.add(W.id_base(Key.ServerId{1n}), 5n), Key.ServerId{0n}), 0n))
    Unit <- E.must("same part hold stays", Nat.is_eq(WsNet.ws_history.hold_in(6n, Key.ServerId{0n}), 6n))
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- ph_connecting()
    Unit <- ph_reconnecting()
    Unit <- ph_online()
    Unit <- ph_offline()
    Unit <- ph_demo()
    Unit <- ph_stopping_t()
    Unit <- ph_stopping_f()
    Unit <- ph_mixed()
    Unit <- ph_ready()
    IO.print("ws_shutdown_pending=ok")
