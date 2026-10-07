# SPDX-License-Identifier: Apache-2.0
# N9 full follow-up GATE 1 (red-first): collection walks buffers in buffer
# order while Notify marks are per-scope hi-watermarks, so a higher id in an
# earlier buffer shadows lower fresh ids later (fresh=False, silently dropped),
# and different buffer orders yield different notification sets. Dispatch must
# be order-independent while keeping at-most-once (replays silent).
# Synthetic fixtures only. Uses the existing API so it compiles (and fails)
# before the fix.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/notify.bend as Notify
import ../../src/bend/session.bend as Sess

def scope() -> String:
  "irc.test:6697"

def other_scope() -> String:
  "other.test:6697"

# JOIN #a(1) JOIN #b(2), then mention #b(3) and #a(4): buffer order collects
# the id-4 #a row before the id-3 #b row.
def cl_interleaved() -> Cl.Client:
  Feed.feed(Feed.feed(Feed.feed(Feed.feed(Cl.init("me", "irc.test"),
    ":me!u@h JOIN #a"), ":me!u@h JOIN #b"),
    ":bob!u@h PRIVMSG #b :hi me"), ":carol!u@h PRIVMSG #a :yo me")

def observed(+st: Notify.State, +cl: Cl.Client, +cutoff: Nat) -> Notify.State & List<&2, Notify.Req>:
  Sess.notify_observe(st, cl, scope(), cutoff, "", "")

def after.go(pair: Notify.State & List<&2, Notify.Req>) -> Notify.State:
  match pair:
    case (st2, _): st2

def after(+st: Notify.State, +cl: Cl.Client, +cutoff: Nat) -> Notify.State:
  after.go(observed(st, cl, cutoff))

def reqs_len(pair: Notify.State & List<&2, Notify.Req>) -> String:
  match pair:
    case (_, rs): Nat.show(List.length(&2, Notify.Req, rs))

def req_titles(rs: List<&2, Notify.Req>) -> String:
  match rs:
    case Nil{}: ""
    case Con{r, t}: Notify.req_title(r) ++ ";" ++ req_titles(t)

def reqs_titles(pair: Notify.State & List<&2, Notify.Req>) -> String:
  match pair:
    case (_, rs): req_titles(rs)

def req_bodies(rs: List<&2, Notify.Req>) -> String:
  match rs:
    case Nil{}: ""
    case Con{r, t}: Notify.req_body(r) ++ ";" ++ req_bodies(t)

def reqs_bodies(pair: Notify.State & List<&2, Notify.Req>) -> String:
  match pair:
    case (_, rs): req_bodies(rs)

def hi_shown(+got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "unknown"
    case Some{hi}: Nat.show(hi)

# Same event SET in both buffer orders (high id first = earlier buffer).
def ev_low() -> Notify.NotifyEvent:
  Notify.NotifyEvent{3n, scope(), "bob", "#b", "hi", False{}, True{}}

def ev_high() -> Notify.NotifyEvent:
  Notify.NotifyEvent{4n, scope(), "carol", "#a", "yo", False{}, True{}}

def disp(+st: Notify.State, +evs: List<&2, Notify.NotifyEvent>) -> Notify.State & List<&2, Notify.Req>:
  Sess.notify_dispatch(st, evs, "", "")

def disp_after.go(pair: Notify.State & List<&2, Notify.Req>) -> Notify.State:
  match pair:
    case (st2, _): st2

def ev_other() -> Notify.NotifyEvent:
  Notify.NotifyEvent{1n, other_scope(), "dan", "#c", "hey", False{}, True{}}

def ev_local() -> Notify.NotifyEvent:
  Notify.NotifyEvent{1n, scope(), "bob", "#b", "hi", False{}, True{}}

# Rejected nonpaging input has a higher id than the later valid mention.
def ev_rejected() -> Notify.NotifyEvent:
  Notify.NotifyEvent{2n, scope(), "carol", "#b", "ordinary chatter", False{}, False{}}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("interleaved two buffers notify twice",
      reqs_len(observed(Notify.on(), cl_interleaved(), 0n)), "2")
    Unit <- E.must_eq("interleaved titles follow id order",
      reqs_titles(observed(Notify.on(), cl_interleaved(), 0n)), "bob in #b;carol in #a;")
    Unit <- E.must_eq("interleaved bodies keep both rows",
      reqs_bodies(observed(Notify.on(), cl_interleaved(), 0n)), "<bob> hi me;<carol> yo me;")
    Unit <- E.must_eq("interleaved mark reaches max id",
      hi_shown(Notify.hi_of(after(Notify.on(), cl_interleaved(), 0n), scope())), "4")
    Unit <- E.must_eq("reversed buffer order notifies twice both ways",
      reqs_len(disp(Notify.on(), ev_high() <> ev_low() <> Nil{})) ++ "/" ++
      reqs_len(disp(Notify.on(), ev_low() <> ev_high() <> Nil{})), "2/2")
    Unit <- E.must_eq("reversed buffer order yields identical titles",
      reqs_titles(disp(Notify.on(), ev_high() <> ev_low() <> Nil{})),
      reqs_titles(disp(Notify.on(), ev_low() <> ev_high() <> Nil{})))
    Unit <- E.must_eq("reversed buffer order yields identical bodies",
      reqs_bodies(disp(Notify.on(), ev_high() <> ev_low() <> Nil{})),
      reqs_bodies(disp(Notify.on(), ev_low() <> ev_high() <> Nil{})))
    Unit <- E.must_eq("cross-scope orders yield identical titles",
      reqs_titles(disp(Notify.on(), ev_other() <> ev_local() <> Nil{})),
      reqs_titles(disp(Notify.on(), ev_local() <> ev_other() <> Nil{})))
    Unit <- E.must_eq("cross-scope orders notify both identities",
      reqs_len(disp(Notify.on(), ev_other() <> ev_local() <> Nil{})) ++ "/" ++
      reqs_len(disp(Notify.on(), ev_local() <> ev_other() <> Nil{})), "2/2")
    Unit <- E.must_eq("cross-scope titles keep both expected identities",
      reqs_titles(disp(Notify.on(), ev_other() <> ev_local() <> Nil{})), "bob in #b;dan in #c;")
    Unit <- E.must_eq("nonpaging input is rejected",
      reqs_len(disp(Notify.on(), ev_rejected() <> Nil{})), "0")
    Unit <- E.must_eq("rejected high id cannot shadow valid lower id",
      reqs_titles(disp(disp_after.go(disp(Notify.on(), ev_rejected() <> Nil{})), ev_local() <> Nil{})), "bob in #b;")
    Unit <- E.must_eq("duplicate replay stays silent",
      reqs_len(disp(disp_after.go(disp(Notify.on(), ev_high() <> ev_low() <> Nil{})), ev_low() <> ev_high() <> Nil{})), "0")
    Unit <- E.must_eq("new mention still notifies",
      reqs_len(disp(disp_after.go(disp(Notify.on(), ev_high() <> ev_low() <> Nil{})), Notify.NotifyEvent{5n, scope(), "erin", "#a", "hey me", False{}, True{}} <> Nil{})), "1")
    IO.print("notify_order=ok")
