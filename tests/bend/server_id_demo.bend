# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/session.bend as Sess

def s0() -> Sid.ServerId:
  Sid.ServerId{0n}

def s1() -> Sid.ServerId:
  Sid.ServerId{1n}

def s2() -> Sid.ServerId:
  Sid.ServerId{2n}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("first valid", Sid.valid(Sid.first()))
    Unit <- E.must("slot0", U32.is_eq(Sid.slot(Sid.first()), 0))
    Unit <- E.must("slot3", U32.is_eq(Sid.slot(Sid.next(Sid.next(Sid.next(Sid.first())))), 3))
    Unit <- E.must("chain valid", Sid.valid(Sid.next(Sid.next(Sid.next(Sid.first())))))
    Unit <- E.must("bound refused", Bool.not(Sid.valid(Sid.next(Sid.next(Sid.next(Sid.next(Sid.first())))))))
    Unit <- E.must("eq self", Sid.eq(s0(), s0()))
    Unit <- E.must("eq other", Bool.not(Sid.eq(s0(), s1())))
    Unit <- E.must_eq("bump", U32.show(Sid.bump(7)), "8")
    Unit <- E.must("stale", Sid.is_stale(7, 8))
    Unit <- E.must("current gen", Bool.not(Sid.is_stale(8, 8)))
    Unit <- E.must("route hit", Sid.route_current(Sid.Routed{s1(), 7}, s1(), 7))
    Unit <- E.must("route server miss", Bool.not(Sid.route_current(Sid.Routed{s1(), 7}, s2(), 7)))
    Unit <- E.must("route gen miss", Bool.not(Sid.route_current(Sid.Routed{s1(), 7}, s1(), 8)))
    Unit <- E.must("dial hit", Sid.cmd_current(Sid.dial_for(s0(), "h", 6697, 3, "me"), s0(), 3))
    Unit <- E.must("dial gen miss", Bool.not(Sid.cmd_current(Sid.dial_for(s0(), "h", 6697, 3, "me"), s0(), 4)))
    Unit <- E.must("dial server miss", Bool.not(Sid.cmd_current(Sid.dial_for(s0(), "h", 6697, 3, "me"), s1(), 3)))
    Unit <- E.must("cont hit", Sid.cmd_current(Sid.cont_for(s1(), "PING x" <> Nil{}), s1(), 9))
    Unit <- E.must("cont server miss", Bool.not(Sid.cmd_current(Sid.cont_for(s1(), "PING x" <> Nil{}), s0(), 9)))
    Unit <- E.must("pump gen hit", Sid.cmd_current(Sid.RoutedCmd{s0(), Sess.Pump{5}}, s0(), 5))
    Unit <- E.must("pump gen miss", Bool.not(Sid.cmd_current(Sid.RoutedCmd{s0(), Sess.Pump{5}}, s0(), 6)))
    Unit <- E.must("begin hit", Sid.cmd_current(Sid.begin_for(s0(), 5), s0(), 5))
    Unit <- E.must("begin gen miss", Bool.not(Sid.cmd_current(Sid.begin_for(s0(), 5), s0(), 6)))
    Unit <- E.must("drop hit", Sid.cmd_current(Sid.drop_for(s2()), s2(), 1))
    Unit <- E.must("drop server miss", Bool.not(Sid.cmd_current(Sid.drop_for(s2()), s1(), 1)))
    Unit <- E.must("openurl hit", Sid.cmd_current(Sid.RoutedCmd{s0(), Sess.OpenUrl{"https://example.com"}}, s0(), 1))
    Unit <- E.must("openurl server miss", Bool.not(Sid.cmd_current(Sid.RoutedCmd{s0(), Sess.OpenUrl{"https://example.com"}}, s1(), 1)))
    Unit <- E.must("evt hit", Sid.evt_current(Sid.RoutedMsg{s0(), Sess.FromNet{4, Sess.Chunk{1 <> 2 <> Nil{}}}}, s0(), 4))
    Unit <- E.must("evt gen miss", Bool.not(Sid.evt_current(Sid.RoutedMsg{s0(), Sess.FromNet{4, Sess.Chunk{Nil{}}}}, s0(), 5)))
    Unit <- E.must("evt server miss", Bool.not(Sid.evt_current(Sid.RoutedMsg{s0(), Sess.FromNet{4, Sess.Eof{}}}, s1(), 4)))
    Unit <- E.must("evt key gated", Sid.evt_current(Sid.RoutedMsg{s1(), Sess.UiKey{}}, s1(), 4))
    Unit <- E.must("evt key server miss", Bool.not(Sid.evt_current(Sid.RoutedMsg{s1(), Sess.UiKey{}}, s0(), 4)))
    Unit <- E.must("done hit", Sid.writer_done_current(Sid.RoutedMsg{s0(), Sess.FromNet{4, Sess.WriterDone{}}}, s0(), 4))
    Unit <- E.must("done gen miss", Bool.not(Sid.writer_done_current(Sid.RoutedMsg{s0(), Sess.FromNet{4, Sess.WriterDone{}}}, s0(), 5)))
    Unit <- E.must("done server miss", Bool.not(Sid.writer_done_current(Sid.RoutedMsg{s0(), Sess.FromNet{4, Sess.WriterDone{}}}, s1(), 4)))
    Unit <- E.must("eof never acks", Bool.not(Sid.writer_done_current(Sid.RoutedMsg{s0(), Sess.FromNet{4, Sess.Eof{}}}, s0(), 4)))
    Unit <- E.must_eq("key v4", Sid.scope_key(Sid.Scope{"irc.example", 6697, False{}}), "irc.example:6697")
    Unit <- E.must_eq("key v6", Sid.scope_key(Sid.Scope{"::1", 6697, True{}}), "[::1]:6697")
    Unit <- E.must("same scope", Sid.same_scope(Sid.Scope{"irc.example", 6697, False{}}, Sid.Scope{"irc.example", 6697, False{}}))
    Unit <- E.must("scope case folds", Sid.same_scope(Sid.Scope{"IRC.Example", 6697, False{}}, Sid.Scope{"irc.example", 6697, False{}}))
    Unit <- E.must("scope v6 case folds", Sid.same_scope(Sid.Scope{"FD00::1", 6697, True{}}, Sid.Scope{"fd00::1", 6697, True{}}))
    Unit <- E.must("scope port differs", Bool.not(Sid.same_scope(Sid.Scope{"h", 6697, False{}}, Sid.Scope{"h", 7000, False{}})))
    Unit <- E.must("scope host differs", Bool.not(Sid.same_scope(Sid.Scope{"a.example", 6697, False{}}, Sid.Scope{"b.example", 6697, False{}})))
    Unit <- E.must("scope root dot differs", Bool.not(Sid.same_scope(Sid.Scope{"h.", 6697, False{}}, Sid.Scope{"h", 6697, False{}})))
    Unit <- E.must("scope family differs", Bool.not(Sid.same_scope(Sid.Scope{"::1", 6697, True{}}, Sid.Scope{"::1", 6697, False{}})))
    Unit <- E.must("changed", Sid.scope_changed(Sid.Scope{"a", 1, False{}}, Sid.Scope{"b", 1, False{}}))
    Unit <- E.must("unchanged", Bool.not(Sid.scope_changed(Sid.Scope{"a", 1, False{}}, Sid.Scope{"A", 1, False{}})))
    Unit <- E.must("cred hit", Sid.credential_scope_ok("h", 6697, "h", 6697))
    Unit <- E.must("cred case exact", Bool.not(Sid.credential_scope_ok("h", 6697, "H", 6697)))
    Unit <- E.must("cred port", Bool.not(Sid.credential_scope_ok("h", 6697, "h", 7000)))
    Unit <- E.must("cred zero port", Bool.not(Sid.credential_scope_ok("h", 0, "h", 0)))
    Unit <- E.must("history hit", Sid.history_admits("IRC.Example:6697", Sid.Scope{"irc.example", 6697, False{}}))
    Unit <- E.must("history port miss", Bool.not(Sid.history_admits("irc.example:7000", Sid.Scope{"irc.example", 6697, False{}})))
    Unit <- E.must("history host miss", Bool.not(Sid.history_admits("other.example:6697", Sid.Scope{"irc.example", 6697, False{}})))
    Unit <- E.must("history v6 hit", Sid.history_admits("[::1]:6697", Sid.Scope{"::1", 6697, True{}}))
    Unit <- E.must("history v6 bare miss", Bool.not(Sid.history_admits("::1:6697", Sid.Scope{"::1", 6697, True{}})))
    Unit <- E.must("reconnect hit", Sid.reconnect_ok(Sid.Intent{s0(), 4, "h", 6697, False{}}, s0(), 4, Sid.Scope{"h", 6697, False{}}))
    Unit <- E.must("reconnect gen miss", Bool.not(Sid.reconnect_ok(Sid.Intent{s0(), 4, "h", 6697, False{}}, s0(), 5, Sid.Scope{"h", 6697, False{}})))
    Unit <- E.must("reconnect server miss", Bool.not(Sid.reconnect_ok(Sid.Intent{s0(), 4, "h", 6697, False{}}, s1(), 4, Sid.Scope{"h", 6697, False{}})))
    Unit <- E.must("reconnect endpoint miss", Bool.not(Sid.reconnect_ok(Sid.Intent{s0(), 4, "h", 6697, False{}}, s0(), 4, Sid.Scope{"other", 6697, False{}})))
    Unit <- E.must("reconnect port miss", Bool.not(Sid.reconnect_ok(Sid.Intent{s0(), 4, "h", 6697, False{}}, s0(), 4, Sid.Scope{"h", 7000, False{}})))
    Unit <- E.must("routing ok", Sid.routing_ok())
    Unit <- E.must("isolation ok", Sid.isolation_ok())
    Unit <- E.must("generation ok", Sid.generation_ok())
    IO.print("server_id_demo=ok")
