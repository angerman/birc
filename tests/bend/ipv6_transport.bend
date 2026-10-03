# SPDX-License-Identifier: Apache-2.0
# IPv6 transport glue: AAAA-first query order and A/AAAA dispatch. Pure
# only, so the JS backend runs this without sockets. Literal resolution,
# native dial, and TLS checks live in ipv6_transport_native.
# Dual fallback ordering, explicit-port admission, and stale generation
# guards are pinned here; native dial/TLS exercise owned loopback peers.
import Base
import ./expect.bend as E
import ../../src/bend/dns_wire.bend as Wire
import ../../src/bend/dns_query.bend as Dq
import ../../src/bend/ipv6.bend as V6
import ../../src/bend/session.bend as Sess
import ../../src/bend/actor.bend as Act

def show_res(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{(_, +msg)}: "fail:" ++ msg
    case Done{+ip}: "ok:" ++ ip

def show_take(t: Wire.Take) -> String:
  match t:
    case Wire.Miss{}: "miss"
    case Wire.HitOk{+ip}: "ok:" ++ ip
    case Wire.HitErr{+msg}: "err:" ++ msg

def show_enc(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> String:
  match r:
    case Fail{(_, +msg)}: "fail:" ++ msg
    case Done{+q}: "len:" ++ Nat.show(List.length(&2, U32, q))

def hdr(+b0: U32, +b1: U32, +fb: U32, +sb: U32, +an0: U32, +an1: U32) -> List<&2, U32>:
  b0 <> b1 <> fb <> sb <> 0 <> 1 <> an0 <> an1 <> 0 <> 0 <> 0 <> 0 <> Nil{}

def qsec_aaaa() -> List<&2, U32>:
  1 <> 97 <> 0 <> 0 <> 28 <> 0 <> 1 <> Nil{}

def qsec_a() -> List<&2, U32>:
  1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> Nil{}

def rdata16() -> List<&2, U32>:
  32 <> 1 <> 13 <> 184 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 0 <> 1 <> Nil{}

def ans_aaaa_ptr() -> List<&2, U32>:
  List.append(&2, U32, 192 <> 12 <> 0 <> 28 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 16 <> Nil{}, rdata16())

def ans_a_ptr() -> List<&2, U32>:
  192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

def pkt_of(+h: List<&2, U32>, +q: List<&2, U32>, +a: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, h, List.append(&2, U32, q, a))

def resp_aaaa() -> List<&2, U32>:
  pkt_of(hdr(0, 1, 129, 128, 0, 1), qsec_aaaa(), ans_aaaa_ptr())

def resp_a() -> List<&2, U32>:
  pkt_of(hdr(0, 1, 129, 128, 0, 1), qsec_a(), ans_a_ptr())

def order_first(+o: V6.QueryOrder) -> U32:
  match o:
    case V6.QueryOrder{+first, _}: first

def order_second(+o: V6.QueryOrder) -> U32:
  match o:
    case V6.QueryOrder{_, +second}: second

def show_maybe(m: Maybe<&2, String>) -> String:
  match m:
    case None{}: "none"
    case Some{+ip}: "some:" ++ ip

def show_plan(p: Dq.DialPlan) -> String:
  match p:
    case Dq.DialNone{}: "none"
    case Dq.DialOne{+ip}: "one:" ++ ip
    case Dq.DialDual{+v6, +v4}: "dual:" ++ v6 ++ "+" ++ v4

def show_deferred_start(dial: Act.PendingDial, +gen: U32) -> String:
  match dial:
    case Act.PendingDial{+host, +port, _}: "starting:" ++ host ++ ":" ++ U32.show(port) ++ ":" ++ U32.show(gen)

def show_deferred(s: Act.DeferredStep) -> String:
  match s:
    case Act.Waiting{_}: "waiting"
    case Act.Starting{dial, +gen, _, _}: show_deferred_start(dial, gen)
    case Act.Released{+gen, _}: "released:" ++ U32.show(gen)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("aaaa qtype", U32.is_eq(V6.AAAA_QTYPE(), 28))
    Unit <- E.must("order first aaaa", U32.is_eq(order_first(V6.query_order()), 28))
    Unit <- E.must("order second a", U32.is_eq(order_second(V6.query_order()), 1))
    Unit <- E.must("prefer v6", V6.prefer_v6())
    Unit <- E.must_eq("enc aaaa", show_enc(Dq.encode_for(True{}, 1, "example.com")), "len:40")
    Unit <- E.must_eq("enc a", show_enc(Dq.encode_for(False{}, 1, "example.com")), "len:40")
    Unit <- E.must_eq("enc aaaa bad", show_enc(Dq.encode_for(True{}, 1, "")), "fail:bad name")
    Unit <- E.must_eq("enc a bad", show_enc(Dq.encode_for(False{}, 1, "")), "fail:bad name")
    Unit <- E.must_eq("take aaaa", show_take(Dq.take_for(True{}, "1.1.1.1", 1, "a", "1.1.1.1", 53, resp_aaaa())), "ok:2001:db8:0:0:0:0:0:1")
    Unit <- E.must_eq("take a", show_take(Dq.take_for(False{}, "1.1.1.1", 1, "a", "1.1.1.1", 53, resp_a())), "ok:1.2.3.4")
    Unit <- E.must_eq("take aaaa on a", show_take(Dq.take_for(True{}, "1.1.1.1", 1, "a", "1.1.1.1", 53, resp_a())), "miss")
    Unit <- E.must_eq("take a on aaaa", show_take(Dq.take_for(False{}, "1.1.1.1", 1, "a", "1.1.1.1", 53, resp_aaaa())), "miss")
    Unit <- E.must_eq("take peer miss", show_take(Dq.take_for(True{}, "1.1.1.1", 1, "a", "9.9.9.9", 53, resp_aaaa())), "miss")
    Unit <- E.must_eq("take port miss", show_take(Dq.take_for(True{}, "1.1.1.1", 1, "a", "1.1.1.1", 5353, resp_aaaa())), "miss")
    Unit <- E.must_eq("tcp aaaa", show_res(Dq.tcp_parse(True{}, 1, "a", resp_aaaa())), "ok:2001:db8:0:0:0:0:0:1")
    Unit <- E.must_eq("tcp a", show_res(Dq.tcp_parse(False{}, 1, "a", resp_a())), "ok:1.2.3.4")
    Unit <- E.must("peer at ok", Dq.peer_ok_at("127.0.0.1", 5353, "127.0.0.1", 5353))
    Unit <- E.must("peer at ip miss", Bool.not(Dq.peer_ok_at("127.0.0.1", 5353, "127.0.0.2", 5353)))
    Unit <- E.must("peer at port miss", Bool.not(Dq.peer_ok_at("127.0.0.1", 5353, "127.0.0.1", 53)))
    Unit <- E.must_eq("take at aaaa", show_take(Dq.take_for_at(True{}, "127.0.0.1", 5353, 1, "a", "127.0.0.1", 5353, resp_aaaa())), "ok:2001:db8:0:0:0:0:0:1")
    Unit <- E.must_eq("take at a", show_take(Dq.take_for_at(False{}, "127.0.0.1", 5353, 1, "a", "127.0.0.1", 5353, resp_a())), "ok:1.2.3.4")
    Unit <- E.must_eq("take at miss", show_take(Dq.take_for_at(True{}, "127.0.0.1", 5353, 1, "a", "127.0.0.1", 53, resp_aaaa())), "miss")
    Unit <- E.must_eq("first v6 wins", show_maybe(Dq.first_of(Some{"::1"}, Some{"127.0.0.1"})), "some:::1")
    Unit <- E.must_eq("first v4 only", show_maybe(Dq.first_of(None{}, Some{"127.0.0.1"})), "some:127.0.0.1")
    Unit <- E.must_eq("first none", show_maybe(Dq.first_of(None{}, None{})), "none")
    Unit <- E.must("fallback needs fail+second", Dq.should_fallback(True{}, Some{"127.0.0.1"}))
    Unit <- E.must("fallback no second", Bool.not(Dq.should_fallback(True{}, None{})))
    Unit <- E.must("fallback no fail", Bool.not(Dq.should_fallback(False{}, Some{"127.0.0.1"})))
    Unit <- E.must_eq("plan dual", show_plan(Dq.dial_plan(Some{"::1"}, Some{"127.0.0.1"})), "dual:::1+127.0.0.1")
    Unit <- E.must_eq("plan v6 only", show_plan(Dq.dial_plan(Some{"::1"}, None{})), "one:::1")
    Unit <- E.must_eq("plan v4 only", show_plan(Dq.dial_plan(None{}, Some{"127.0.0.1"})), "one:127.0.0.1")
    Unit <- E.must_eq("plan none", show_plan(Dq.dial_plan(None{}, None{})), "none")
    Unit <- E.must("event current", Sess.event_current(Sess.FromNet{2, Sess.Chunk{Nil{}}} , 2))
    Unit <- E.must("event stale", Bool.not(Sess.event_current(Sess.FromNet{1, Sess.Chunk{Nil{}}} , 2)))
    Unit <- E.must("writerdone current", Sess.writer_done_current(Sess.FromNet{2, Sess.WriterDone{}} , 2))
    Unit <- E.must("writerdone stale", Bool.not(Sess.writer_done_current(Sess.FromNet{1, Sess.WriterDone{}} , 2)))
    Unit <- E.must("writerdone not eof", Bool.not(Sess.writer_done_current(Sess.FromNet{2, Sess.Eof{}} , 2)))
    Unit <- E.must_eq("deferred stale begin", show_deferred(Act.deferred_command(Sess.Begin{2}, Act.deferred_initial("::1", 6697, "n", True{}))), "waiting")
    Unit <- E.must_eq("deferred dial v6", show_deferred(Act.deferred_command(Sess.Dial{"::1", 6697, 2, "n"}, Act.deferred_initial("h", 6667, "n", False{}))), "waiting")
    IO.print("ipv6_transport=ok")
