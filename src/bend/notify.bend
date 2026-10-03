# SPDX-License-Identifier: Apache-2.0
# Pure desktop-notification policy. A request fires at most once per event
# id, only for mentions and direct messages, and only while enabled. Bodies
# reuse the diagnostic redaction (credentials and URLs never leak) and are
# bounded to one short line. Delivery lives in notify_io.bend; this module
# stays pure and proof-facing.
import Base
import ./irc.bend as Irc
import ./diagnostic.bend as Diagnostic

def BODY_CAP() -> Nat:
  160n

def SEEN_CAP() -> Nat:
  64n

# id mirrors the chat row's stable global event id. dm marks a direct
# (query) message; mention marks a highlight in any buffer.
type NotifyEvent is Data:
  NotifyEvent{id: Nat, author: String, target: String, text: String, dm: Bool, mention: Bool}

type Req is Data:
  Req{title: String, body: String}

type State is Data:
  Notify{enabled: Bool, seen: List<&2, Nat>}

def off() -> State:
  Notify{False{}, Nil{}}

def on() -> State:
  Notify{True{}, Nil{}}

def enabled(+st: State) -> Bool:
  match st:
    case Notify{en, _}: en

def seen(+st: State) -> List<&2, Nat>:
  match st:
    case Notify{_, seen}: seen

def event_id(+ev: NotifyEvent) -> Nat:
  match ev:
    case NotifyEvent{id, _, _, _, _, _}: id

def event_text(+ev: NotifyEvent) -> String:
  match ev:
    case NotifyEvent{_, _, _, text, _, _}: text

def req_title(+r: Req) -> String:
  match r:
    case Req{title, _}: title

def req_body(+r: Req) -> String:
  match r:
    case Req{_, body}: body

def want(+ev: NotifyEvent) -> Bool:
  match ev:
    case NotifyEvent{_, _, _, _, dm, mention}: dm || mention

def title_of.dm(+dm: Bool, +author: String, +target: String) -> String:
  match dm:
    case True{}: author ++ " (private)"
    case False{}: author ++ " in " ++ target

def title_of(+ev: NotifyEvent) -> String:
  match ev:
    case NotifyEvent{_, author, target, _, dm, _}: title_of.dm(dm, author, target)

def body_of(+text: String, user: String, pass: String) -> String:
  String.take(Diagnostic.text(text, user, pass), BODY_CAP())

def seen_has.go(xs: List<&2, Nat>, +id: Nat) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, t}: Nat.is_eq(h, id) || seen_has.go(t, id)

def seen_has(+st: State, +id: Nat) -> Bool:
  seen_has.go(seen(st), id)

def remember(+st: State, +id: Nat) -> State:
  match st:
    case Notify{en, seen}: Notify{en, List.take(&2, Nat, id <> seen, SEEN_CAP())}

def decide.send(+st: State, +ev: NotifyEvent, user: String, pass: String, send: Bool) -> State & Maybe<&2, Req>:
  match send:
    case True{}: (remember(st, event_id(ev)), Some{Req{title_of(ev), body_of(event_text(ev), user, pass)}})
    case False{}: (st, None{})

def decide(+st: State, +ev: NotifyEvent, user: String, pass: String) -> State & Maybe<&2, Req>:
  +send = enabled(st) && want(ev) && Bool.not(seen_has(st, event_id(ev)))
  decide.send(st, ev, user, pass, send)

def step.after(pair: State & Maybe<&2, Req>) -> State:
  match pair:
    case (st2, _): st2

# State half of decide, for callers that already handled the request.
def step(+st: State, +ev: NotifyEvent, user: String, pass: String) -> State:
  step.after(decide(st, ev, user, pass))

def parse.go(+is_on: Bool, +is_off: Bool) -> Maybe<&2, Bool>:
  match is_on:
    case True{}: Some{True{}}
    case False{}:
      match is_off:
        case True{}: Some{False{}}
        case False{}: None{}

def parse(+arg: String) -> Maybe<&2, Bool>:
  parse.go(Irc.ieq(arg, "on"), Irc.ieq(arg, "off"))

def apply.set.go(enabled: Bool, +seen: List<&2, Nat>, set: Maybe<&2, Bool>) -> State:
  match set:
    case Some{b}: Notify{b, seen}
    case None{}: Notify{enabled, seen}

def apply.set(+st: State, set: Maybe<&2, Bool>) -> State:
  match st:
    case Notify{en, seen}: apply.set.go(en, seen, set)

# Unknown arguments preserve the current state (for a future /notify switch).
def apply(+st: State, +arg: String) -> State:
  apply.set(st, parse(arg))

def status(+st: State) -> String:
  match st:
    case Notify{en, seen}:
      match en:
        case True{}: "notifications: on (" ++ Nat.show(List.length(&2, Nat, seen)) ++ " recent)"
        case False{}: "notifications: off"
