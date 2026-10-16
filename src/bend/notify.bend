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
# new live event and notifies exactly once. Admission fails closed: an
# unknown scope past the bound is neither notified nor tracked, so the
# table never evicts (and never forgets) an admitted scope's mark.
# Session seeds the mark from history before live dispatch (see seed), so
# restored rows stay silent without a per-event table.
#
# Titles and bodies both pass the diagnostic redaction (credentials and
# URLs never leak) and are bounded before any metadata handoff. Delivery
# lives in notify_io.bend; this module stays pure and proof-facing.
#
# Collection walks buffers in buffer order, but event ids are global per
# scope: folding buffer-ordered events through a per-scope hi-watermark lets
# a higher id in an earlier buffer shadow lower fresh ids collected later.
# Sorting by (scope, id) before decide makes collection+dispatch
# order-independent: every fresh event notifies exactly once in ascending id
# order, and the mark still owns at-most-once (replays stay silent).
# Session dispatch and async delivery have pure seams here and in
# session.bend/notify_io.bend; threading Notify.State through the live loop
# and default helper provisioning stay parent merge points (N9.3).
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
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

def is_known.got(got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def is_known(+st: State, +scope: String) -> Bool:
  is_known.got(hi_of(st, scope))

def room_for(+st: State) -> Bool:
  Nat.is_lt(List.length(&2, Mark, marks(st)), SCOPE_CAP())

# A scope is admitted when already tracked, or when the table has room.
# Unknown scopes past the bound fail closed: silent and untracked.
def admitted(+st: State, +scope: String) -> Bool:
  is_known(st, scope) || room_for(st)

# Unknown scopes are new (first contact notifies) only while admitted;
# past the bound they stay silent. Known scopes notify only above their
# high-water mark.
def fresh.ok(+st: State, +scope: String, +id: Nat, ok: Bool) -> Bool:
  match ok:
    case True{}: fresh.got(id, hi_of(st, scope))
    case False{}: False{}

def fresh(+st: State, +scope: String, +id: Nat) -> Bool:
  fresh.ok(st, scope, id, admitted(st, scope))

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

def bumped_state(+st: State, +scope: String, +id: Nat) -> State:
  match st:
    case Notify{en, seen}: Notify{en, bumped(seen, scope, id)}

def prepended_state(+st: State, +scope: String, +id: Nat) -> State:
  match st:
    case Notify{en, seen}: Notify{en, List.take(&2, Mark, Mark{scope, id} <> seen, SCOPE_CAP())}

def remember.admit(+st: State, +scope: String, +id: Nat, room: Bool) -> State:
  match room:
    case True{}: prepended_state(st, scope, id)
    case False{}: st

def remember.known(+st: State, +scope: String, +id: Nat, hit: Bool) -> State:
  match hit:
    case True{}: bumped_state(st, scope, id)
    case False{}: remember.admit(st, scope, id, room_for(st))

# Recording an id advances that scope's mark (never backwards) and keeps
# the table bounded. A full table rejects unknown scopes instead of
# evicting: admitted marks are never forgotten, so replays stay silent.
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

def chr_lt.le(+a: U32, +b: U32, le: Bool) -> Bool:
  match le:
    case True{}: Bool.not(U32.is_eq(a, b))
    case False{}: False{}

def chr_lt(+a: U32, +b: U32) -> Bool:
  chr_lt.le(a, b, U32.is_le(a, b))

def str_lt.cmp(lt: Bool, gt: Bool, +tail_lt: Bool) -> Bool:
  match lt:
    case True{}: True{}
    case False{}:
      match gt:
        case True{}: False{}
        case False{}: tail_lt

def str_lt.go(+a: String, +b: String) -> Bool:
  match a:
    case SNil{}:
      match b:
        case SNil{}: False{}
        case SCon{_, _}: True{}
    case SCon{+ha, +ta}:
      match b:
        case SNil{}: False{}
        case SCon{+hb, +tb}:
          +ca = Char.to_u32(ha)
          +cb = Char.to_u32(hb)
          str_lt.cmp(chr_lt(ca, cb), chr_lt(cb, ca), str_lt.go(ta, tb))

def str_lt(+a: String, +b: String) -> Bool:
  str_lt.go(a, b)

def ev_lt.scope(+ida: Nat, +sa: String, +idb: Nat, +sb: String) -> Bool:
  str_lt.cmp(str_lt(sa, sb), str_lt(sb, sa), Nat.is_lt(ida, idb))

def ev_lt.b(+b: NotifyEvent, +ida: Nat, +sa: String) -> Bool:
  match b:
    case NotifyEvent{+idb, +sb, _, _, _, _, _}: ev_lt.scope(ida, sa, idb, sb)

def ev_lt(+a: NotifyEvent, +b: NotifyEvent) -> Bool:
  match a:
    case NotifyEvent{+ida, +sa, _, _, _, _, _}: ev_lt.b(b, ida, sa)

def sort_inserted(lt: Bool, +ev: NotifyEvent, +h: NotifyEvent, +t: List<&2, NotifyEvent>, +rec: List<&2, NotifyEvent>) -> List<&2, NotifyEvent>:
  match lt:
    case True{}: ev <> h <> t
    case False{}: rec

def sort_insert(+ev: NotifyEvent, +sorted: List<&2, NotifyEvent>) -> List<&2, NotifyEvent>:
  match sorted:
    case Nil{}: ev <> Nil{}
    case Con{+h, +t}: sort_inserted(ev_lt(ev, h), ev, h, t, h <> sort_insert(ev, t))

def sort_events(+evs: List<&2, NotifyEvent>) -> List<&2, NotifyEvent>:
  match evs:
    case Nil{}: Nil{}
    case Con{+h, +t}: sort_insert(h, sort_events(t))

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

# ---- bounded async-delivery queue -------------------------------------------
# decide() stays the at-most-once gate: every queued Req already advanced its
# scope mark, so queued Reqs are unique per scope+id by construction. The queue
# is fail-closed (reject-new past QUEUE_CAP, never evict) and FIFO; the frame
# path stages at most a bounded handful per frame into detached workers.
def QUEUE_CAP() -> Nat:
  8n

type Queue is Data:
  Queue{pending: List<&2, Req>}

def queue_empty() -> Queue:
  Queue{Nil{}}

def queue_len(+q: Queue) -> Nat:
  match q:
    case Queue{+pending}: List.length(&2, Req, pending)

def enqueue.admit(full: Bool, +pending: List<&2, Req>, +r: Req) -> Queue:
  match full:
    case True{}: Queue{pending}
    case False{}: Queue{List.append(&2, Req, pending, r <> Nil{})}

def enqueue(q: Queue, r: Req) -> Queue:
  match q:
    case Queue{+pending}:
      enqueue.admit(Nat.is_ge(List.length(&2, Req, pending), QUEUE_CAP()), pending, r)

def enqueue_all(+q: Queue, +rs: List<&2, Req>) -> Queue:
  List.foldl(~&2, ~Req, ~Queue, ~enqueue, rs, q)

def take_jobs(+q: Queue, +n: Nat) -> Queue & List<&2, Req>:
  match q:
    case Queue{+pending}:
      (Queue{List.drop(&2, Req, pending, n)}, List.take(&2, Req, pending, n))

# Single-handoff drain: one call hands the whole bounded queue to the single
# worker, FIFO. The worker delivers the handed list one job at a time; the
# queue keeps only what was never handed (nothing here: drain_all takes all).
def drain_all(+q: Queue) -> Queue & List<&2, Req>:
  take_jobs(q, queue_len(q))

# ---- staged dispatch (marks on admit) ----------------------------------------
# decide() advances marks for every fresh event, even when the bounded queue
# has no room left: dropped reqs would consume at-most-once without ever
# reaching the worker. The staged fold instead admits each fresh event into
# the queue first and advances that scope's mark only on admit; a full queue
# leaves state, queue, and scan floor untouched so a later step can retry.
# hi tracks the highest admitted id (seeded with the scan floor); the live
# step stores it back as the new floor, so only admitted rows advance.
type Stage is Data:
  Stage{st: State, queue: Queue, reqs: List<&2, Req>, hi: Nat, user: String, pass: String}

def stage_st(+s: Stage) -> State:
  match s:
    case Stage{+st, _, _, _, _, _}: st

def stage_queue(+s: Stage) -> Queue:
  match s:
    case Stage{_, +q, _, _, _, _}: q

def stage_reqs(+s: Stage) -> List<&2, Req>:
  match s:
    case Stage{_, _, +reqs, _, _, _}: reqs

def stage_hi(+s: Stage) -> Nat:
  match s:
    case Stage{_, _, _, +hi, _, _}: hi

def stage_admitted(full: Bool, +st: State, +q: Queue, +reqs: List<&2, Req>, +hi: Nat, +ev: NotifyEvent, +user: String, +pass: String) -> Stage:
  match full:
    case True{}: Stage{st, q, reqs, hi, user, pass}
    case False{}:
      +req : Req = Req{title_of(ev, user, pass), body_of(event_text(ev), user, pass)}
      Stage{remember(st, event_scope(ev), event_id(ev)), enqueue(q, req), List.append(&2, Req, reqs, req <> Nil{}), Nat.max(hi, event_id(ev)), user, pass}

def stage_send(send: Bool, +st: State, +q: Queue, +reqs: List<&2, Req>, +hi: Nat, +ev: NotifyEvent, +user: String, +pass: String) -> Stage:
  match send:
    case False{}: Stage{st, q, reqs, hi, user, pass}
    case True{}: stage_admitted(Nat.is_ge(queue_len(q), QUEUE_CAP()), st, q, reqs, hi, ev, user, pass)

def stage_step.ev(+st: State, +q: Queue, +reqs: List<&2, Req>, +hi: Nat, +ev: NotifyEvent, +user: String, +pass: String) -> Stage:
  stage_send(enabled(st) && want(ev) && fresh(st, event_scope(ev), event_id(ev)), st, q, reqs, hi, ev, user, pass)

def stage_step(acc: Stage, ev: NotifyEvent) -> Stage:
  match acc:
    case Stage{+st, +q, +reqs, +hi, +user, +pass}:
      stage_step.ev(st, q, reqs, hi, ev, user, pass)

def stage(+st: State, +events: List<&2, NotifyEvent>, +user: String, +pass: String, +q: Queue, +floor: Nat) -> Stage:
  List.foldl(~&2, ~NotifyEvent, ~Stage, ~stage_step, sort_events(events), Stage{st, q, Nil{}, floor, user, pass})

# ---- batch-claimed archive exclusion (per-ID, no floor bump) ------------------
# H5's batch claim arrives as an ID set at the dispatch seam. Claimed rows are
# filtered before sort/stage, so marks and the scan floor advance only for
# admitted live rows. A chunk-level or global-floor bump would suppress
# interleaved live rows with lower IDs; per-ID filtering does not. The set is
# a plain List<Nat> so the seam works whether or not H5's claim type has
# merged; H5 maps its batch IDs through claimed_from_ids (identity).
def claimed_from_ids(+ids: List<&2, Nat>) -> List<&2, Nat>:
  ids

def claimed_hit(ids: List<&2, Nat>, +id: Nat) -> Bool:
  match ids:
    case Nil{}: False{}
    case Con{+h, t}: Nat.is_eq(h, id) || claimed_hit(t, id)

def claimed_filter.keep(hit: Bool, +ev: NotifyEvent, +tail: List<&2, NotifyEvent>) -> List<&2, NotifyEvent>:
  match hit:
    case True{}: tail
    case False{}: ev <> tail

def claimed_filter(events: List<&2, NotifyEvent>, +claimed: List<&2, Nat>) -> List<&2, NotifyEvent>:
  match events:
    case Nil{}: Nil{}
    case Con{+ev, t}:
      +hit = claimed_hit(claimed, event_id(ev))
      claimed_filter.keep(hit, ev, claimed_filter(t, claimed))

def stage_claimed(+st: State, +events: List<&2, NotifyEvent>, +user: String, +pass: String, +q: Queue, +floor: Nat, +claimed: List<&2, Nat>) -> Stage:
  stage(st, claimed_filter(events, claimed), user, pass, q, floor)

# ---- durable claim set (bounded union, floor prune) ---------------------------
# Stored exclusions survive across chunks until the scan floor passes them;
# the floor itself never bumps for archive rows, so interleaved live rows
# stay eligible. The bound covers every single accepted import in full: an
# install restores at most MAX_BUFFERS targets of at most SCROLL_CAP rows
# each (history.bend reader bound; per-target room clamps to spare scroll),
# dividers never qualify as mentions/DMs, and installed ids are fresh and
# sequential above the pre-import sequence -- so qualifying installed ids
# never exceed MAX_BUFFERS * SCROLL_CAP. Union keeps stored-first order and
# prunes stored ids at/below the scan floor BEFORE capping (proven
# exclusions: the floor and marks already cover them), dedups fresh against
# the pruned set (dupes use no capacity, last wins), and rejects-new past
# the cap (drops newest, never evicts stored): the same fail-closed
# in-lane policy as the bounded notify queue, which also rejects-new past
# QUEUE_CAP instead of evicting. Stored claims are therefore never evicted
# for fresh ones; past-cap fresh ids stay unclaimed (a later scan may
# notify them) rather than silently displacing proven exclusions.
def CLAIM_CAP() -> Nat:
  Nat.mul(Cl.MAX_BUFFERS(), Cl.SCROLL_CAP())

def claim_prune.keep(keep: Bool, +id: Nat, +tail: List<&2, Nat>) -> List<&2, Nat>:
  match keep:
    case True{}: id <> tail
    case False{}: tail

def claim_prune(+xs: List<&2, Nat>, +floor: Nat) -> List<&2, Nat>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}: claim_prune.keep(Nat.is_gt(h, floor), h, claim_prune(t, floor))

def claim_fresh.keep(hit: Bool, +h: Nat, +tail: List<&2, Nat>) -> List<&2, Nat>:
  match hit:
    case True{}: tail
    case False{}: h <> tail

def claim_fresh(fresh: List<&2, Nat>, +stored: List<&2, Nat>) -> List<&2, Nat>:
  match fresh:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +tail = claim_fresh(t, stored)
      claim_fresh.keep(claimed_hit(stored, h) || claimed_hit(tail, h), h, tail)

def claim_union(+stored: List<&2, Nat>, +fresh: List<&2, Nat>) -> List<&2, Nat>:
  +combined = List.append(&2, Nat, stored, claim_fresh(fresh, stored))
  List.take(&2, Nat, combined, CLAIM_CAP())

def claim_union_floor(+stored: List<&2, Nat>, +fresh: List<&2, Nat>, +floor: Nat) -> List<&2, Nat>:
  claim_union(claim_prune(stored, floor), fresh)

# Session-free mention/DM classification. Moved from session.bend;
# session keeps Sess.notify_* wrappers.
def notify_is_highlight(k: Cl.LineKind) -> Bool:
  match k:
    case Cl.Highlight{}: True{}
    case Cl.Pending{+inner}: notify_is_highlight(inner)
    case _: False{}

def notify_is_action(k: Cl.LineKind) -> Bool:
  match k:
    case Cl.Action{}: True{}
    case Cl.Pending{+inner}: notify_is_action(inner)
    case _: False{}

# Peer-authored chat kinds that can page a query owner. Notices stay silent to
# match the bell/Mention-unread signal (feed never highlights a NOTICE).
def notify_is_dm_kind(k: Cl.LineKind) -> Bool:
  match k:
    case Cl.Msg{}: True{}
    case Cl.Action{}: True{}
    case Cl.Highlight{}: True{}
    case Cl.Pending{+inner}: notify_is_dm_kind(inner)
    case _: False{}

# A peer Highlight, or a peer channel /me naming our nick (feed keeps Action
# kind there but still raises Mention unread + bell).
def notify_is_mention(+author: String, +text: String, +nick: String, +k: Cl.LineKind) -> Bool:
  Bool.not(Irc.ieq(author, nick)) && (notify_is_highlight(k) || (notify_is_action(k) && Cl.is_mention(text, nick)))

# Peer query buffer: never the server buffer (index 0), never synthetic, never
# a channel. The stored name "server" would otherwise pass is_query_name.
def notify_is_query(+name: String, is_channel: Bool, index: Nat) -> Bool:
  Bool.not(Nat.is_eq(index, 0n)) && Bool.not(is_channel) && Cl.is_query_name(name)

def notify_line_dm(query: Bool, +author: String, +nick: String, k: Cl.LineKind) -> Bool:
  query && notify_is_dm_kind(k) && Bool.not(Irc.ieq(author, nick))

def notify_line_hits(query: Bool, +author: String, +text: String, +nick: String, +k: Cl.LineKind) -> Bool:
  notify_line_dm(query, author, nick, k) || notify_is_mention(author, text, nick, k)

def notify_collect_line.keep(keep: Bool, +scope: String, +author: String, +target: String, +text: String, +id: Nat, +dm: Bool, +mention: Bool, tail: List<&2, NotifyEvent>) -> List<&2, NotifyEvent>:
  match keep:
    case True{}: NotifyEvent{id, scope, author, target, text, dm, mention} <> tail
    case False{}: tail

def notify_collect_lines(lines: List<&2, Cl.Line>, +scope: String, +target: String, +nick: String, +cutoff: Nat, +query: Bool) -> List<&2, NotifyEvent>:
  match lines:
    case Nil{}: Nil{}
    case Con{Cl.Line{+k, _, +text, +author, +id}, t}:
      +dm = notify_line_dm(query, author, nick, k)
      +men = notify_is_mention(author, text, nick, k)
      +tail = notify_collect_lines(t, scope, target, nick, cutoff, query)
      notify_collect_line.keep(Nat.is_gt(id, cutoff) && (men || dm), scope, author, target, text, id, dm, men, tail)

def notify_collect_bufs(bufs: List<&2, Cl.Buffer>, +scope: String, +nick: String, +cutoff: Nat, +index: Nat) -> List<&2, NotifyEvent>:
  match bufs:
    case Nil{}: Nil{}
    case Con{Cl.Buffer{+name, is_channel, _, lines, _, _}, t}:
      +head = notify_collect_lines(lines, scope, name, nick, cutoff, notify_is_query(name, is_channel, index))
      +tail = notify_collect_bufs(t, scope, nick, cutoff, Nat.add(index, 1n))
      List.append(&2, NotifyEvent, head, tail)

def notify_collect(+cl: Cl.Client, +scope: String, +cutoff: Nat) -> List<&2, NotifyEvent>:
  match cl:
    case Cl.Client{+nick, _, +bufs, _, _, _, _, _}:
      notify_collect_bufs(bufs, scope, nick, cutoff, 0n)

# Fold accumulator threads the redaction credentials: a fold step cannot close
# over runtime values, so user/pass ride along and are returned untouched.
