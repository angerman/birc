# SPDX-License-Identifier: Apache-2.0
# Pure desktop-notification policy. A request fires at most once per
# (server scope, event id), only for mentions and direct messages, and
# only while enabled. Identity is server-scoped: Client log_seq is
# per-Client, so a bare id would collide across servers; the scope is the
# exact endpoint spelling (host:port), never case-folded.
#
# Bounded state: one high-water mark per scope (at most SCOPE_CAP scopes).
# Live event ids are monotonic per scope, so an id at or below the mark is
# old, replayed, or historical and stays silent; an id above the mark is a
# new live event and notifies exactly once. Eviction of a scope entry only
# forgets that scope's mark; ids within a retained scope never renotify.
# Session seeds the mark from history before live dispatch (see seed), so
# restored rows stay silent without a per-event table.
#
# Titles and bodies both pass the diagnostic redaction (credentials and
# URLs never leak) and are bounded before any metadata handoff. Delivery
# lives in notify_io.bend; this module stays pure and proof-facing.
# Session dispatch, default helper provisioning, and async delivery are
# open runtime gates (N9.3), not a completed desktop feature.
import Base
import ./irc.bend as Irc
import ./diagnostic.bend as Diagnostic

def BODY_CAP() -> Nat:
  160n

def TITLE_CAP() -> Nat:
  80n

def SCOPE_CAP() -> Nat:
  8n

# id mirrors the chat row's stable event id within srv. dm marks a direct
# (query) message; mention marks a highlight in any buffer.
type NotifyEvent is Data:
  NotifyEvent{id: Nat, srv: String, author: String, target: String, text: String, dm: Bool, mention: Bool}

type Req is Data:
  Req{title: String, body: String}

# hi is the highest notified id for scope; every id at or below it is
# treated as already seen (old, replayed, or historical).
type Mark is Data:
  Mark{scope: String, hi: Nat}

type State is Data:
  Notify{enabled: Bool, marks: List<&2, Mark>}

def off() -> State:
  Notify{False{}, Nil{}}

def on() -> State:
  Notify{True{}, Nil{}}

def enabled(+st: State) -> Bool:
  match st:
    case Notify{en, _}: en

def marks(+st: State) -> List<&2, Mark>:
  match st:
    case Notify{_, marks}: marks

def event_id(+ev: NotifyEvent) -> Nat:
  match ev:
    case NotifyEvent{id, _, _, _, _, _, _}: id

def event_scope(+ev: NotifyEvent) -> String:
  match ev:
    case NotifyEvent{_, srv, _, _, _, _, _}: srv

def event_text(+ev: NotifyEvent) -> String:
  match ev:
    case NotifyEvent{_, _, _, _, text, _, _}: text

def req_title(+r: Req) -> String:
  match r:
    case Req{title, _}: title

def req_body(+r: Req) -> String:
  match r:
    case Req{_, body}: body

def want(+ev: NotifyEvent) -> Bool:
  match ev:
    case NotifyEvent{_, _, _, _, _, dm, mention}: dm || mention

def title_raw.dm(+dm: Bool, +author: String, +target: String) -> String:
  match dm:
    case True{}: author ++ " (private)"
    case False{}: author ++ " in " ++ target

def title_raw(+ev: NotifyEvent) -> String:
  match ev:
    case NotifyEvent{_, _, author, target, _, dm, _}: title_raw.dm(dm, author, target)

# Titles cross the same metadata handoff as bodies, so they get the same
# sanitize/redact treatment plus their own bound.
def title_of(+ev: NotifyEvent, user: String, pass: String) -> String:
  String.take(Diagnostic.text(title_raw(ev), user, pass), TITLE_CAP())

def body_of(+text: String, user: String, pass: String) -> String:
  String.take(Diagnostic.text(text, user, pass), BODY_CAP())

def hi_of.hit(hit: Bool, +hi: Nat, other: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}: Some{hi}
    case False{}: other

def hi_of.go(xs: List<&2, Mark>, +scope: String) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}: None{}
    case Con{Mark{+s, hi}, t}: hi_of.hit(String.eq(s, scope), hi, hi_of.go(t, scope))

def hi_of(+st: State, +scope: String) -> Maybe<&2, Nat>:
  hi_of.go(marks(st), scope)

def fresh.hi(+id: Nat, +hi: Nat) -> Bool:
  Nat.is_gt(id, hi)

def fresh.got(+id: Nat, got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: True{}
    case Some{hi}: fresh.hi(id, hi)

# Unknown scopes are new (first contact notifies); known scopes notify
# only above their high-water mark.
def fresh(+st: State, +scope: String, +id: Nat) -> Bool:
  fresh.got(id, hi_of(st, scope))

def bump.set(hit: Bool, +s: String, +hi: Nat, +id: Nat) -> Mark:
  match hit:
    case True{}: Mark{s, Nat.max(hi, id)}
    case False{}: Mark{s, hi}

def bump.one(+mark: Mark, +scope: String, +id: Nat) -> Mark:
  match mark:
    case Mark{+s, hi}: bump.set(String.eq(s, scope), s, hi, id)

def bumped(xs: List<&2, Mark>, +scope: String, +id: Nat) -> List<&2, Mark>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: bump.one(h, scope, id) <> bumped(t, scope, id)

def remember.known(+st: State, +scope: String, +id: Nat, known: Bool) -> State:
  match st:
    case Notify{en, seen}:
      match known:
        case True{}: Notify{en, bumped(seen, scope, id)}
        case False{}: Notify{en, List.take(&2, Mark, Mark{scope, id} <> seen, SCOPE_CAP())}

# Recording an id advances that scope's mark (never backwards) and keeps
# the table bounded. Within a retained scope, eviction cannot renotify:
# evicted ids sit at or below the mark.
def remember.got(+st: State, +scope: String, +id: Nat, got: Maybe<&2, Nat>) -> State:
  match got:
    case None{}: remember.known(st, scope, id, False{})
    case Some{_}: remember.known(st, scope, id, True{})

def remember(+st: State, +scope: String, +id: Nat) -> State:
  remember.got(st, scope, id, hi_of(st, scope))

# History cutoff without notifying: Session marks restored rows as seen
# before live dispatch so replayed history stays silent.
def seed(+st: State, +scope: String, +hi: Nat) -> State:
  remember(st, scope, hi)

def decide.send(+st: State, +ev: NotifyEvent, +user: String, +pass: String, send: Bool) -> State & Maybe<&2, Req>:
  match send:
    case True{}: (remember(st, event_scope(ev), event_id(ev)), Some{Req{title_of(ev, user, pass), body_of(event_text(ev), user, pass)}})
    case False{}: (st, None{})

def decide(+st: State, +ev: NotifyEvent, user: String, pass: String) -> State & Maybe<&2, Req>:
  +send = enabled(st) && want(ev) && fresh(st, event_scope(ev), event_id(ev))
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

def apply.set.go(enabled: Bool, +seen: List<&2, Mark>, set: Maybe<&2, Bool>) -> State:
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
        case True{}: "notifications: on (" ++ Nat.show(List.length(&2, Mark, seen)) ++ " scopes)"
        case False{}: "notifications: off"
