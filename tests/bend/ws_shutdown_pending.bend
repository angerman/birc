# SPDX-License-Identifier: Apache-2.0
# Pure predicate characterization for the actual multiserver shutdown set.
# No actor, terminal, helper, socket, or timer is started by this fixture.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/drafts.bend as Drafts
import ../../src/bend/wsnet.bend as WsNet

def part(+id: Nat, net: Sess.NetState) -> W.Part:
  +st = Sess.session_set_net(Sess.session_demo(Cl.init("probe", "shutdown.test"), "#t"), net)
  W.Part{Key.ServerId{id}, 7, Sid.Scope{"shutdown.test", 6697, False{}}, st}

def ws(+parts: List<&2, W.Part>) -> W.Workspace:
  W.Workspace{parts, Key.first(), Drafts.empty(), Nil{}}

def ids.go(+ids: List<&2, Key.ServerId>, +acc: String) -> String:
  match ids:
    case Nil{}: acc
    case Con{+id, +tail}: ids.go(tail, acc ++ U32.show(Key.slot(id)) ++ ",")

def pending_ids(+parts: List<&2, W.Part>) -> String:
  ids.go(WsNet.ws_pending(ws(parts)), "")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("connecting dial cannot delay teardown", pending_ids([part(0n, Sess.Connecting{})]), "")
    Unit <- E.must_eq("reconnecting dial cannot delay teardown", pending_ids([part(1n, Sess.Reconnecting{})]), "")
    Unit <- E.must_eq("healthy online writer must acknowledge", pending_ids([part(0n, Sess.Online{})]), "0,")
    Unit <- E.must_eq("offline idle writer must acknowledge", pending_ids([part(1n, Sess.Offline{})]), "1,")
    Unit <- E.must_eq("demo idle writer must acknowledge", pending_ids([part(2n, Sess.Demo{})]), "2,")
    Unit <- E.must_eq("stopping true retains the existing default policy", pending_ids([part(0n, Sess.Stopping{True{}})]), "0,")
    Unit <- E.must_eq("stopping false retains the existing default policy", pending_ids([part(1n, Sess.Stopping{False{}})]), "1,")
    Unit <- E.must_eq("mixed set retains only owned ready writers", pending_ids([part(0n, Sess.Online{}), part(1n, Sess.Connecting{}), part(2n, Sess.Offline{}), part(3n, Sess.Reconnecting{})]), "0,2,")
    Unit <- E.must_eq("all pending dials permit immediate teardown", pending_ids([part(0n, Sess.Connecting{}), part(1n, Sess.Reconnecting{})]), "")
    Unit <- E.must_eq("empty set remains empty", pending_ids(Nil{}), "")
    Unit <- E.must("idle prefs with history drain still arms a deadline", WsNet.ws_shut.need(False{}, True{}, False{}))
    Unit <- E.must("idle prefs with a writer still arms a deadline", WsNet.ws_shut.need(False{}, False{}, True{}))
    Unit <- E.must("idle prefs and no drain skip the deadline", Bool.not(WsNet.ws_shut.need(False{}, False{}, False{})))
    Unit <- E.must("other part hold does not floor slot 0", Nat.is_eq(WsNet.ws_history.hold_in(Nat.add(W.id_base(Key.ServerId{1n}), 5n), Key.ServerId{0n}), 0n))
    Unit <- E.must("same part hold stays", Nat.is_eq(WsNet.ws_history.hold_in(6n, Key.ServerId{0n}), 6n))
    IO.print("ws_shutdown_pending=ok")
