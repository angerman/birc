# SPDX-License-Identifier: Apache-2.0
# Desktop-notification policy: per-event identity, bounds, redaction, helpers.
import Base
import ./expect.bend as E
import ../../src/bend/notify.bend as Notify
import ../../src/bend/notify_io.bend as NotifyIO

def ev(+id: Nat, +dm: Bool, +men: Bool) -> Notify.NotifyEvent:
  Notify.NotifyEvent{id, "bob", "#room", "hello", dm, men}

def shown(+got: Maybe<&2, Notify.Req>) -> String:
  match got:
    case None{}: "silent"
    case Some{r}: "notify:" ++ Notify.req_title(r) ++ "|" ++ Notify.req_body(r)

def decided.go(pair: Notify.State & Maybe<&2, Notify.Req>) -> String:
  match pair:
    case (_, got): shown(got)

def decided(+st: Notify.State, +event: Notify.NotifyEvent) -> String:
  decided.go(Notify.decide(st, event, "", ""))

def decided_cred(+st: Notify.State, +event: Notify.NotifyEvent, user: String, pass: String) -> String:
  decided.go(Notify.decide(st, event, user, pass))

def twice.second.go(pair: Notify.State & Maybe<&2, Notify.Req>, +first: Maybe<&2, Notify.Req>) -> String:
  match pair:
    case (_, second): shown(first) ++ "/" ++ shown(second)

def twice.second(+st: Notify.State, +first: Maybe<&2, Notify.Req>) -> String:
  twice.second.go(Notify.decide(st, ev(7n, False{}, True{}), "", ""), first)

def twice.go(pair: Notify.State & Maybe<&2, Notify.Req>) -> String:
  match pair:
    case (st2, first): twice.second(st2, first)

def twice() -> String:
  twice.go(Notify.decide(Notify.on(), ev(7n, False{}, True{}), "", ""))

def fresh.second(+st: Notify.State, +first: Maybe<&2, Notify.Req>) -> String:
  twice.second.go(Notify.decide(st, ev(8n, False{}, True{}), "", ""), first)

def fresh.go(pair: Notify.State & Maybe<&2, Notify.Req>) -> String:
  match pair:
    case (st2, first): fresh.second(st2, first)

def fresh_ids() -> String:
  fresh.go(Notify.decide(Notify.on(), ev(7n, False{}, True{}), "", ""))

def flood(left: Nat, +st: Notify.State, +id: Nat) -> Notify.State:
  match left:
    case 0n: st
    case 1n+p:
      flood(p, Notify.step(st, Notify.NotifyEvent{id, "a", "#t", "x", False{}, True{}}, "", ""), Nat.add(id, 1n))

def chars(left: Nat) -> String:
  match left:
    case 0n: ""
    case 1n+p: "x" ++ chars(p)

def body_len.go(pair: Notify.State & Maybe<&2, Notify.Req>) -> String:
  match pair:
    case (_, Some{r}): Nat.show(String.length(Notify.req_body(r)))
    case (_, None{}): "silent"

def body_len(+text: String) -> String:
  body_len.go(Notify.decide(Notify.on(), Notify.NotifyEvent{1n, "a", "#t", text, False{}, True{}}, "", ""))

def maybe_str(+got: Maybe<&2, String>) -> String:
  match got:
    case None{}: "none"
    case Some{s}: s

def join1.tail(xs: List<&1, String>, +sep: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: sep ++ h ++ join1.tail(t, sep)

def join1.go(xs: List<&1, String>, +sep: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: h ++ join1.tail(t, sep)

def join1(xs: List<&1, String>, +sep: String) -> String:
  join1.go(xs, sep)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("disabled mention silent", decided(Notify.off(), ev(1n, False{}, True{})), "silent")
    Unit <- E.must_eq("disabled direct silent", decided(Notify.off(), ev(1n, True{}, False{})), "silent")
    Unit <- E.must_eq("channel chatter silent", decided(Notify.on(), ev(1n, False{}, False{})), "silent")
    Unit <- E.must_eq("mention notifies", decided(Notify.on(), ev(1n, False{}, True{})), "notify:bob in #room|hello")
    Unit <- E.must_eq("direct notifies", decided(Notify.on(), ev(1n, True{}, False{})), "notify:bob (private)|hello")
    Unit <- E.must_eq("event notifies once", twice(), "notify:bob in #room|hello/silent")
    Unit <- E.must_eq("fresh id notifies again", fresh_ids(), "notify:bob in #room|hello/notify:bob in #room|hello")
    Unit <- E.must_eq("seen stays bounded", Nat.show(List.length(&2, Nat, Notify.seen(flood(70n, Notify.on(), 0n)))), "64")
    Unit <- E.must_eq("evicted id notifies again", decided(flood(70n, Notify.on(), 0n), ev(0n, False{}, True{})),
      "notify:bob in #room|hello")
    Unit <- E.must_eq("body bound is 160 chars", body_len(chars(200n)), "160")
    Unit <- E.must_eq("short body kept whole", body_len("hi"), "2")
    Unit <- E.must_eq("credentials redacted",
      decided_cred(Notify.on(), Notify.NotifyEvent{3n, "alice", "#t", "hi alice s3cret", True{}, False{}}, "alice", "s3cret"),
      "notify:alice (private)|hi [redacted] [redacted]")
    Unit <- E.must_eq("urls elided", Notify.body_of("see https://x.test/a ok", "", ""), "see [url] ok")
    Unit <- E.must_eq("apply on enables", Notify.status(Notify.apply(Notify.off(), "on")), "notifications: on (0 recent)")
    Unit <- E.must_eq("apply off disables", Notify.status(Notify.apply(Notify.on(), "OFF")), "notifications: off")
    Unit <- E.must_eq("apply unknown preserves", Notify.status(Notify.apply(Notify.on(), "maybe")), "notifications: on (0 recent)")
    Unit <- E.must_eq("status off", Notify.status(Notify.off()), "notifications: off")
    Unit <- E.must_eq("notify-send args", join1(NotifyIO.args_for("notify-send", Notify.Req{"T", "B"}), "|"), "T|B")
    Unit <- E.must_eq("absolute notify-send args",
      join1(NotifyIO.args_for("/usr/bin/notify-send", Notify.Req{"T", "B"}), "|"), "T|B")
    Unit <- E.must_eq("osascript args",
      join1(NotifyIO.args_for("osascript", Notify.Req{"T", "B"}), "|"),
      "-e|display notification \"B\" with title \"T\"")
    Unit <- E.must_eq("osascript escaping",
      NotifyIO.script("a\"b", "c\\d"),
      "display notification \"c\\\\d\" with title \"a\\\"b\"")
    Unit <- E.must_eq("unknown helper has no args", join1(NotifyIO.args_for("x-notify", Notify.Req{"T", "B"}), "|"), "")
    Unit <- E.must_eq("helper unset sends nothing", maybe_str(NotifyIO.program.env(Fail{(2, "private error")})), "none")
    Unit <- E.must_eq("helper empty sends nothing", maybe_str(NotifyIO.program.env(Done{""})), "none")
    Unit <- E.must_eq("helper path is literal", maybe_str(NotifyIO.program.env(Done{"/owned/notify"})), "/owned/notify")
    Unit <- E.must_eq("helper success is silent", maybe_str(NotifyIO.send_result(Done{(0, ("private out", "private err"))})), "none")
    Unit <- E.must_eq("helper exit code kept", maybe_str(NotifyIO.send_result(Done{(3, ("private out", "private err"))})),
      "notify failed (exit 3)")
    Unit <- E.must_eq("helper os code kept", maybe_str(NotifyIO.send_result(Fail{(5, "private os error")})),
      "notify failed (OS 5)")
    IO.print("theme_notify=ok")
