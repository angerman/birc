# SPDX-License-Identifier: Apache-2.0
# Desktop-notification policy: per-event identity, bounds, redaction, helpers.
import Base
import ./expect.bend as E
import ../../src/bend/notify.bend as Notify
import ../../src/bend/notify_io.bend as NotifyIO

def scope() -> String:
  "irc.test:6697"

def other_scope() -> String:
  "other.test:6697"

def ev(+id: Nat, +dm: Bool, +men: Bool) -> Notify.NotifyEvent:
  Notify.NotifyEvent{id, scope(), "bob", "#room", "hello", dm, men}

def ev_at(+srv: String, +id: Nat, +dm: Bool, +men: Bool) -> Notify.NotifyEvent:
  Notify.NotifyEvent{id, srv, "bob", "#room", "hello", dm, men}

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

def after(+st: Notify.State, +event: Notify.NotifyEvent) -> Notify.State:
  Notify.step(st, event, "", "")

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
      flood(p, Notify.step(st, Notify.NotifyEvent{id, scope(), "a", "#t", "x", False{}, True{}}, "", ""), Nat.add(id, 1n))

def flood_scopes(left: Nat, +st: Notify.State, +n: Nat) -> Notify.State:
  match left:
    case 0n: st
    case 1n+p:
      flood_scopes(p, Notify.step(st, Notify.NotifyEvent{1n, "s" ++ Nat.show(n) ++ ".test:6697", "a", "#t", "x", False{}, True{}}, "", ""), Nat.add(n, 1n))

def chars(left: Nat) -> String:
  match left:
    case 0n: ""
    case 1n+p: "x" ++ chars(p)

def body_len.go(pair: Notify.State & Maybe<&2, Notify.Req>) -> String:
  match pair:
    case (_, Some{r}): Nat.show(String.length(Notify.req_body(r)))
    case (_, None{}): "silent"

def body_len(+text: String) -> String:
  body_len.go(Notify.decide(Notify.on(), Notify.NotifyEvent{1n, scope(), "a", "#t", text, False{}, True{}}, "", ""))

def title_len.go(pair: Notify.State & Maybe<&2, Notify.Req>) -> String:
  match pair:
    case (_, Some{r}): Nat.show(String.length(Notify.req_title(r)))
    case (_, None{}): "silent"

def title_len(+author: String) -> String:
  title_len.go(Notify.decide(Notify.on(), Notify.NotifyEvent{1n, scope(), author, "#t", "hi", False{}, True{}}, "", ""))

def title_shown(+author: String, +target: String, user: String, pass: String) -> String:
  decided_cred(Notify.on(), Notify.NotifyEvent{1n, scope(), author, target, "hi", True{}, False{}}, user, pass)

def hi_shown(+got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "unknown"
    case Some{hi}: Nat.show(hi)

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
    Unit <- E.must_eq("old id stays silent", decided(after(Notify.on(), ev(5n, False{}, True{})), ev(3n, False{}, True{})), "silent")
    Unit <- E.must_eq("same id replays silent", decided(after(Notify.on(), ev(5n, False{}, True{})), ev(5n, False{}, True{})), "silent")
    Unit <- E.must_eq("history cutoff stays silent",
      decided(Notify.seed(Notify.on(), scope(), 9n), ev(9n, False{}, True{})), "silent")
    Unit <- E.must_eq("live id above cutoff notifies",
      decided(Notify.seed(Notify.on(), scope(), 9n), ev(10n, False{}, True{})), "notify:bob in #room|hello")
    Unit <- E.must_eq("first contact notifies", hi_shown(Notify.hi_of(Notify.on(), scope())), "unknown")
    Unit <- E.must_eq("mark records highest id",
      hi_shown(Notify.hi_of(after(Notify.on(), ev(4n, False{}, True{})), scope())), "4")
    Unit <- E.must_eq("mark never moves backwards",
      hi_shown(Notify.hi_of(Notify.seed(Notify.seed(Notify.on(), scope(), 9n), scope(), 3n), scope())), "9")
    Unit <- E.must_eq("same id on another scope notifies",
      decided(after(Notify.on(), ev(4n, False{}, True{})), ev_at(other_scope(), 4n, False{}, True{})),
      "notify:bob in #room|hello")
    Unit <- E.must_eq("scope spelling is exact",
      decided(after(Notify.on(), ev(4n, False{}, True{})), ev_at("IRC.TEST:6697", 4n, False{}, True{})),
      "notify:bob in #room|hello")
    Unit <- E.must_eq("marks stay bounded",
      Nat.show(List.length(&2, Notify.Mark, Notify.marks(flood_scopes(10n, Notify.on(), 0n)))), "8")
    Unit <- E.must_eq("one scope after flood",
      Nat.show(List.length(&2, Notify.Mark, Notify.marks(flood(70n, Notify.on(), 0n)))), "1")
    Unit <- E.must_eq("evicted id stays silent", decided(flood(70n, Notify.on(), 0n), ev(0n, False{}, True{})), "silent")
    Unit <- E.must_eq("body bound is 160 chars", body_len(chars(200n)), "160")
    Unit <- E.must_eq("short body kept whole", body_len("hi"), "2")
    Unit <- E.must_eq("title bound is 80 chars", title_len(chars(200n)), "80")
    Unit <- E.must_eq("short title kept whole", title_len("bo"), "8")
    Unit <- E.must_eq("title author redacted", title_shown("alice", "#t", "alice", "s3cret"), "notify:[redacted] (private)|hi")
    Unit <- E.must_eq("title url elided",
      decided(Notify.on(), Notify.NotifyEvent{1n, scope(), "a", "https://x.test/a", "hi", False{}, True{}}),
      "notify:a in [url]|hi")
    Unit <- E.must_eq("title control chars stripped",
      decided(Notify.on(), Notify.NotifyEvent{1n, scope(), "b\nob", "#t", "hi", False{}, True{}}),
      "notify:bob in #t|hi")
    Unit <- E.must_eq("credentials redacted",
      decided_cred(Notify.on(), Notify.NotifyEvent{3n, scope(), "alice", "#t", "hi alice s3cret", True{}, False{}}, "alice", "s3cret"),
      "notify:[redacted] (private)|hi [redacted] [redacted]")
    Unit <- E.must_eq("urls elided", Notify.body_of("see https://x.test/a ok", "", ""), "see [url] ok")
    Unit <- E.must_eq("apply on enables", Notify.status(Notify.apply(Notify.off(), "on")), "notifications: on (0 scopes)")
    Unit <- E.must_eq("apply off disables", Notify.status(Notify.apply(Notify.on(), "OFF")), "notifications: off")
    Unit <- E.must_eq("apply unknown preserves", Notify.status(Notify.apply(Notify.on(), "maybe")), "notifications: on (0 scopes)")
    Unit <- E.must_eq("status off", Notify.status(Notify.off()), "notifications: off")
    Unit <- E.must_eq("notify-send args", join1(NotifyIO.args_for("notify-send", Notify.Req{"T", "B"}), "|"), "--|T|B")
    Unit <- E.must_eq("absolute notify-send args",
      join1(NotifyIO.args_for("/usr/bin/notify-send", Notify.Req{"T", "B"}), "|"), "--|T|B")
    Unit <- E.must_eq("flag-like title stays literal",
      join1(NotifyIO.args_for("notify-send", Notify.Req{"--help", "B"}), "|"), "--|--help|B")
    Unit <- E.must_eq("suffix helper rejected", join1(NotifyIO.args_for("x-notify-send", Notify.Req{"T", "B"}), "|"), "")
    Unit <- E.must_eq("suffix osascript rejected", join1(NotifyIO.args_for("notosascript", Notify.Req{"T", "B"}), "|"), "")
    Unit <- E.must_eq("basename strips directories", NotifyIO.base_of("/usr/bin/notify-send"), "notify-send")
    Unit <- E.must_eq("basename keeps plain names", NotifyIO.base_of("osascript"), "osascript")
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
