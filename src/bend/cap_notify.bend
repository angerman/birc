# SPDX-License-Identifier: Apache-2.0
# IRCv3 capability registry, account/away notify, and outbound typing (pure).
# This module is the single registration/CAP-END owner shared with SASL: every
# CAP END line, whether from the SASL exchange or the no-SASL handshake, is
# decided by cap_end_for/cap_end_handshake below. At-most-once emission follows
# from those entry-transition predicates plus the terminal AuthDone/AuthNickWait
# phases; no other module may emit the CAP END literal.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./irc_commands.bend as Commands
import ./endpoint.bend as Endpoint

# ---- capability registry ------------------------------------------------

def CAP_SASL() -> String:
  "sasl"

def CAP_SERVER_TIME() -> String:
  "server-time"

def CAP_MESSAGE_TAGS() -> String:
  "message-tags"

def CAP_ACCOUNT() -> String:
  "account-notify"

def CAP_AWAY() -> String:
  "away-notify"

# Single owner of the chathistory capability name and negotiated bit. The
# history-search policy matches through this registry (never a second
# owner); the live session reads chathistory_ok as `negotiated`.
def CAP_CHATHISTORY() -> String:
  "draft/chathistory"

# Single owner of the echo-message capability name and negotiated bit. When
# negotiated, the server echoes our own PRIVMSG/NOTICE back; the send path
# suppresses its local echo and the wire echo renders exactly once.
def CAP_ECHO() -> String:
  "echo-message"

def CAP_NOTIFY() -> String:
  "cap-notify"

# Requested set, in stable wire order. Outbound typing rides on message-tags.
def wanted.sasl(want: Bool) -> List<&2, String>:
  match want:
    case True{}:
      CAP_SASL() <> CAP_SERVER_TIME() <> CAP_MESSAGE_TAGS() <> CAP_ACCOUNT() <> CAP_AWAY() <> CAP_CHATHISTORY() <> CAP_ECHO() <> CAP_NOTIFY() <> Nil{}
    case False{}:
      CAP_SERVER_TIME() <> CAP_MESSAGE_TAGS() <> CAP_ACCOUNT() <> CAP_AWAY() <> CAP_CHATHISTORY() <> CAP_ECHO() <> CAP_NOTIFY() <> Nil{}

def wanted(+has_sasl: Bool) -> List<&2, String>:
  wanted.sasl(has_sasl)

def req_lines.go(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Irc.format_cap_req(h) <> req_lines.go(t)

def req_lines(+has_sasl: Bool) -> List<&2, String>:
  req_lines.go(wanted(has_sasl))

# ---- CAP END owner ------------------------------------------------------

def cap_end_line() -> String:
  Irc.format_cap_end()

def cap_end_before(before: Cl.AuthPhase) -> Bool:
  match before:
    case Cl.AuthCap{}: True{}
    case Cl.AuthChallenge{}: True{}
    case Cl.AuthResult{}: True{}
    case _: False{}

def cap_end_after(after: Cl.AuthPhase) -> Bool:
  match after:
    case Cl.AuthDone{}: True{}
    case Cl.AuthNickWait{}: True{}
    case _: False{}

# Phases here are unwrapped: auth.bend decides before Cl.set_auth wraps them.
def cap_end_due(before: Cl.AuthPhase, after: Cl.AuthPhase) -> Bool:
  cap_end_before(before) && cap_end_after(after)

def cap_end_for.emit(due: Bool) -> List<&2, String>:
  match due:
    case True{}: cap_end_line() <> Nil{}
    case False{}: Nil{}

def cap_end_for(before: Cl.AuthPhase, after: Cl.AuthPhase) -> List<&2, String>:
  cap_end_for.emit(cap_end_due(before, after))

def cap_end_handshake.emit(+has_sasl: Bool) -> List<&2, String>:
  match has_sasl:
    case True{}: Nil{}
    case False{}: cap_end_line() <> Nil{}

def cap_end_handshake(+has_sasl: Bool) -> List<&2, String>:
  cap_end_handshake.emit(has_sasl)

# ---- CAP wire events and enabled set ------------------------------------

type CapKind is Data:
  CapLs{}
  CapAck{}
  CapNak{}
  CapDel{}
  CapNew{}
  CapOther{}

type CapEvent is Data:
  CapEvent{kind: CapKind, caps: List<&2, String>}

def cap_kind.del(+sub: String, del: Bool) -> CapKind:
  match del:
    case True{}: CapDel{}
    case False{}: CapOther{}

def cap_kind.ls(+sub: String, ls: Bool) -> CapKind:
  match ls:
    case True{}: CapLs{}
    case False{}: cap_kind.del(sub, Irc.ieq(sub, "DEL"))

def cap_kind.nak(+sub: String, nak: Bool) -> CapKind:
  match nak:
    case True{}: CapNak{}
    case False{}: cap_kind.ls(sub, Irc.ieq(sub, "LS"))

def cap_kind.new_cap(+sub: String, is_new: Bool) -> CapKind:
  match is_new:
    case True{}: CapNew{}
    case False{}: cap_kind.nak(sub, Irc.ieq(sub, "NAK"))

def cap_kind.ack(+sub: String, ack: Bool) -> CapKind:
  match ack:
    case True{}: CapAck{}
    case False{}: cap_kind.new_cap(sub, Irc.ieq(sub, "NEW"))

def cap_kind(+sub: String) -> CapKind:
  cap_kind.ack(sub, Irc.ieq(sub, "ACK"))

# Multi-line LS marks continuation with '*'; the caps are the last parameter.
def cap_caps_text.star(+m: Irc.Message, star: Bool) -> String:
  match star:
    case True{}: Irc.msg_param(m, 3n)
    case False{}: Irc.msg_param(m, 2n)

def cap_caps_text(+m: Irc.Message) -> String:
  cap_caps_text.star(m, Irc.ieq(Irc.msg_param(m, 1n), "LS") && String.eq(Irc.msg_param(m, 2n), "*"))

# G6.1: CAP state changes only on lines from a validated server source
# addressed to our current nick. The established '*' recipient is the
# pre-registration broadcast address: the single CAP/registration owner
# supplies `registered`, and a registered session must see its own current
# nick. A peer user cannot set our caps, and another recipient's
# negotiation is not ours. An empty prefix carries no attestation and stays
# shut. This name-level gate is the shared owner (history_search delegates
# here); no second recipient rule may fork it.
def cap_recipient_name_ok(+recipient: String, +nick: String, registered: Bool) -> Bool:
  Irc.ieq(recipient, nick) || (Bool.not(registered) && String.eq(recipient, "*"))

def cap_recipient_ok(+m: Irc.Message, +nick: String, registered: Bool) -> Bool:
  cap_recipient_name_ok(Irc.msg_param(m, 0n), nick, registered)

# Source validation mirrors Auth.server_source through the shared
# Endpoint.host_ok primitive: single-label and dotted servers alike are
# well-formed (RFC 2812); URLs, delimiters, and empty labels fail. (auth.bend
# already depends on this module for CAP END, so the shared piece is the
# Endpoint primitive, not the module.) Peer binding stays at the transport
# and endpoint scope, not in this name. server remains in the signature for
# the integrator's endpoint scope; the trust decision is the host validation.
def server_source(+prefix: String) -> Bool:
  Endpoint.host_ok(prefix)

def cap_trusted(+prefix: String, +server: String, +nick: String, +m: Irc.Message, registered: Bool) -> Bool:
  server_source(prefix) && cap_recipient_ok(m, nick, registered)

def cap_event.gated(+m: Irc.Message, ok: Bool) -> CapEvent:
  match ok:
    case False{}: CapEvent{CapOther{}, Nil{}}
    case True{}: CapEvent{cap_kind(Irc.msg_param(m, 1n)), Commands.words(cap_caps_text(m))}

def cap_event(+server: String, +nick: String, +prefix: String, +m: Irc.Message, registered: Bool) -> CapEvent:
  cap_event.gated(m, Irc.ieq(Irc.msg_command(m), "CAP") && cap_trusted(prefix, server, nick, m, registered))

def cap_kind_of(e: CapEvent) -> CapKind:
  match e:
    case CapEvent{+kind, _}: kind

def cap_is_ls(k: CapKind) -> Bool:
  match k:
    case CapLs{}: True{}
    case _: False{}

def cap_kind_line.parsed(+server: String, +nick: String, +line: String, m: Maybe<&2, Irc.Message>, registered: Bool) -> CapKind:
  match m:
    case None{}: CapOther{}
    case Some{+msg}: cap_kind_of(cap_event(server, nick, Irc.source_prefix(line), msg, registered))

def cap_kind_line(+server: String, +nick: String, +line: String, registered: Bool) -> CapKind:
  cap_kind_line.parsed(server, nick, line, Irc.parse(line), registered)

# Servers may advertise values ('sasl=PLAIN'); match the bare name too.
def cap_match.one(+have: String, +want: String) -> Bool:
  Irc.ieq(have, want) || String.starts_with(Irc.rfc1459(have), Irc.rfc1459(want) ++ "=")

def has_cap.go(xs: List<&2, String>, +want: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}: cap_match.one(h, want) || has_cap.go(t, want)

def has_cap(+xs: List<&2, String>, +want: String) -> Bool:
  has_cap.go(xs, want)

type Caps is Data:
  Caps{server_time: Bool, message_tags: Bool, account: Bool, away: Bool, sasl: Bool, chathistory: Bool, echo: Bool, notify: Bool}

def caps0() -> Caps:
  Caps{False{}, False{}, False{}, False{}, False{}, False{}, False{}, False{}}

def caps_enable(+caps: Caps, +name: String) -> Caps:
  match caps:
    case Caps{+st, +mt, +ac, +aw, +sa, +ch, +ec, +no}:
      Caps{st || cap_match.one(name, CAP_SERVER_TIME()), mt || cap_match.one(name, CAP_MESSAGE_TAGS()), ac || cap_match.one(name, CAP_ACCOUNT()), aw || cap_match.one(name, CAP_AWAY()), sa || cap_match.one(name, CAP_SASL()), ch || cap_match.one(name, CAP_CHATHISTORY()), ec || cap_match.one(name, CAP_ECHO()), no || cap_match.one(name, CAP_NOTIFY())}

# G6.2: removal mirrors enable. A DEL line clears every listed cap, and a
# '-' entry inside an ACK clears that one cap; other caps are untouched.
def caps_disable(+caps: Caps, +name: String) -> Caps:
  match caps:
    case Caps{+st, +mt, +ac, +aw, +sa, +ch, +ec, +no}:
      Caps{st && Bool.not(cap_match.one(name, CAP_SERVER_TIME())), mt && Bool.not(cap_match.one(name, CAP_MESSAGE_TAGS())), ac && Bool.not(cap_match.one(name, CAP_ACCOUNT())), aw && Bool.not(cap_match.one(name, CAP_AWAY())), sa && Bool.not(cap_match.one(name, CAP_SASL())), ch && Bool.not(cap_match.one(name, CAP_CHATHISTORY())), ec && Bool.not(cap_match.one(name, CAP_ECHO())), no && Bool.not(cap_match.one(name, CAP_NOTIFY()))}

def cap_negated(+name: String) -> Bool:
  String.starts_with(name, "-")

def cap_bare.neg(+name: String, neg: Bool) -> String:
  match neg:
    case True{}: String.drop(name, 1n)
    case False{}: name

def cap_bare(+name: String) -> String:
  cap_bare.neg(name, cap_negated(name))

def caps_apply_entry.neg(+caps: Caps, +bare: String, neg: Bool) -> Caps:
  match neg:
    case True{}: caps_disable(caps, bare)
    case False{}: caps_enable(caps, bare)

def caps_apply_entry(+caps: Caps, +name: String) -> Caps:
  caps_apply_entry.neg(caps, cap_bare(name), cap_negated(name))

def caps_apply_list(xs: List<&2, String>, +caps: Caps) -> Caps:
  match xs:
    case Nil{}: caps
    case Con{+h, t}: caps_apply_list(t, caps_apply_entry(caps, h))

def caps_clear_list(xs: List<&2, String>, +caps: Caps) -> Caps:
  match xs:
    case Nil{}: caps
    case Con{+h, t}: caps_clear_list(t, caps_disable(caps, cap_bare(h)))

def caps_apply.kind(+caps: Caps, +xs: List<&2, String>, kind: CapKind) -> Caps:
  match kind:
    case CapAck{}: caps_apply_list(xs, caps)
    case CapNew{}: caps_apply_list(xs, caps)
    case CapDel{}: caps_clear_list(xs, caps)
    case _: caps

def caps_apply(+caps: Caps, e: CapEvent) -> Caps:
  match e:
    case CapEvent{+kind, +xs}: caps_apply.kind(caps, xs, kind)

def caps_apply_line.parsed(+caps: Caps, +server: String, +nick: String, +line: String, m: Maybe<&2, Irc.Message>, registered: Bool) -> Caps:
  match m:
    case None{}: caps
    case Some{+msg}: caps_apply(caps, cap_event(server, nick, Irc.source_prefix(line), msg, registered))

def caps_apply_line(+caps: Caps, +server: String, +nick: String, +line: String, registered: Bool) -> Caps:
  caps_apply_line.parsed(caps, server, nick, line, Irc.parse(line), registered)

def tags_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, +mt, _, _, _, _, _, _}: mt

def account_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, _, +ac, _, _, _, _, _}: ac

def away_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, _, _, +aw, _, _, _, _}: aw

def chathistory_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, _, _, _, _, +ch, _, _}: ch

def echo_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, _, _, _, _, _, +ec, _}: ec

def notify_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, _, _, _, _, _, _, +no}: no

# ---- account/away notify --------------------------------------------------
# The server only sends these about visible users, so no roster check is
# needed. The subject nick is the message source; server-like or malformed
# subjects stay on the existing unknown-command path.

type NotifyEvent is Data:
  AccountOn{nick: String, account: String}
  AccountOff{nick: String}
  AwayOn{nick: String, message: String}
  AwayOff{nick: String}
  NotifyOther{}

def notify_nick(+m: Irc.Message) -> String:
  Cl.target_name(Irc.msg_nick(m))

def notify_nick_ok(+nick: String) -> Bool:
  Commands.word(nick) && Bool.not(Irc.starts_channel(nick)) && Bool.not(String.eq(nick, "*"))

def account_event.is_off(+nick: String, +account: String, off: Bool) -> NotifyEvent:
  match off:
    case True{}: AccountOff{nick}
    case False{}: AccountOn{nick, account}

def account_event.valid(+nick: String, +account: String, valid: Bool) -> NotifyEvent:
  match valid:
    case True{}: account_event.is_off(nick, account, String.eq(account, "*"))
    case False{}: NotifyOther{}

def account_event.clean(+nick: String, +account: String) -> NotifyEvent:
  account_event.valid(nick, account, Bool.not(String.is_empty(account)))

def account_event.arity_ok(+nick: String, +m: Irc.Message, ok: Bool) -> NotifyEvent:
  match ok:
    case True{}: account_event.clean(nick, Irc.sanitize_in(Irc.msg_param(m, 0n)))
    case False{}: NotifyOther{}

def account_event(+nick: String, +m: Irc.Message) -> NotifyEvent:
  +params = Irc.msg_params(m)
  account_event.arity_ok(nick, m, Nat.is_eq(List.length(&2, String, params), 1n))

def away_event.one(+nick: String, +m: Irc.Message, one: Bool) -> NotifyEvent:
  match one:
    case True{}: AwayOn{nick, Irc.sanitize_in(Irc.msg_param(m, 0n))}
    case False{}: NotifyOther{}

def away_event.none(+nick: String, +m: Irc.Message, none: Bool) -> NotifyEvent:
  match none:
    case True{}: AwayOff{nick}
    case False{}: away_event.one(nick, m, Nat.is_eq(List.length(&2, String, Irc.msg_params(m)), 1n))

def away_event(+nick: String, +m: Irc.Message) -> NotifyEvent:
  +params = Irc.msg_params(m)
  away_event.none(nick, m, Nat.is_eq(List.length(&2, String, params), 0n))

def notify_event.away(+nick: String, +m: Irc.Message, away: Bool) -> NotifyEvent:
  match away:
    case True{}: away_event(nick, m)
    case False{}: NotifyOther{}

def notify_event.cmd(+nick: String, +m: Irc.Message, account: Bool) -> NotifyEvent:
  match account:
    case True{}: account_event(nick, m)
    case False{}: notify_event.away(nick, m, Irc.ieq(Irc.msg_command(m), "AWAY"))

# G6.3: presence is a user statement. A validated server source (dotted or
# single-label alike) can never be an ACCOUNT/AWAY subject, even when its
# bare nick looks innocent. Bare ambiguous nicks stay users, matching the
# shared host gate; empty nicks still fail below.
def notify_prefix_ok(+prefix: String, +server: String) -> Bool:
  Bool.not(server_source(prefix))

def notify_event.checked(+m: Irc.Message, +nick: String, ok: Bool) -> NotifyEvent:
  match ok:
    case True{}: notify_event.cmd(nick, m, Irc.ieq(Irc.msg_command(m), "ACCOUNT"))
    case False{}: NotifyOther{}

def notify_event(+server: String, +prefix: String, +m: Irc.Message) -> NotifyEvent:
  +nick = notify_nick(m)
  notify_event.checked(m, nick, notify_nick_ok(nick) && notify_prefix_ok(prefix, server))

def is_notify.event(e: NotifyEvent) -> Bool:
  match e:
    case NotifyOther{}: False{}
    case _: True{}

def is_notify(+server: String, +prefix: String, +m: Irc.Message) -> Bool:
  is_notify.event(notify_event(server, prefix, m))

def account_on_text(+nick: String, +account: String) -> String:
  nick ++ " signed in as " ++ account

def account_off_text(+nick: String) -> String:
  nick ++ " signed out"

def away_on_text.msg(+nick: String, +message: String, empty: Bool) -> String:
  match empty:
    case True{}: nick ++ " is away"
    case False{}: nick ++ " is away: " ++ message

def away_on_text(+nick: String, +message: String) -> String:
  away_on_text.msg(nick, message, String.is_empty(message))

def away_off_text(+nick: String) -> String:
  nick ++ " is back"

def notify_text(e: NotifyEvent) -> String:
  match e:
    case AccountOn{+nick, +account}: account_on_text(nick, account)
    case AccountOff{+nick}: account_off_text(nick)
    case AwayOn{+nick, +message}: away_on_text(nick, message)
    case AwayOff{+nick}: away_off_text(nick)
    case NotifyOther{}: ""

# ---- outbound typing ------------------------------------------------------
# Active refreshes at most every 3 s; done is sent at most once per live span.
# At most one wire line per step. Entering an invalid scope (offline, tags not
# negotiated, bad target) resets silently: no stale or offline sends. Paused is
# intentionally not sent: without a keystroke clock the pure policy cannot tell
# idle-composing from idle-empty, and active refresh plus done covers the UX.

type OutState is Data:
  Out{target: String, live: Bool, sent_ms: U32, seen: Bool}

def out0() -> OutState:
  Out{"", False{}, 0, False{}}

def OUT_REFRESH_MS() -> U32:
  3000

def typing_tag_line(+target: String, +status: String) -> String:
  "@+typing=" ++ status ++ " TAGMSG " ++ target

# 'active' is the longest status we send, so one bound check covers done too.
def out_target_ok(+target: String) -> Bool:
  Commands.word(target) && Cl.target_wire(target) && Irc.line_ok(typing_tag_line(target, "active"))

def out_live(+st: OutState) -> Bool:
  match st:
    case Out{_, +live, _, _}: live

def out_target(+st: OutState) -> String:
  match st:
    case Out{+target, _, _, _}: target

def out_sent_ms(+st: OutState) -> U32:
  match st:
    case Out{_, _, +sent, _}: sent

def out_seen(+st: OutState) -> Bool:
  match st:
    case Out{_, _, _, +seen}: seen

def step_out.refresh_due(+target: String, +sent_ms: U32, +now_ms: U32, +elapsed: U32, due: Bool) -> OutState & List<&2, String>:
  match due:
    case True{}: (Out{target, True{}, now_ms, True{}}, typing_tag_line(target, "active") <> Nil{})
    case False{}: (Out{target, True{}, sent_ms, True{}}, Nil{})

def step_out.refresh(+target: String, +sent_ms: U32, +now_ms: U32, +elapsed: U32, stale: Bool) -> OutState & List<&2, String>:
  match stale:
    case True{}: (Out{target, True{}, sent_ms, True{}}, Nil{})
    case False{}: step_out.refresh_due(target, sent_ms, now_ms, elapsed, U32.is_ge(elapsed, OUT_REFRESH_MS()))

def step_out.compose(+target: String, live: Bool, +sent_ms: U32, +now_ms: U32, +elapsed: U32) -> OutState & List<&2, String>:
  match live:
    case False{}: (Out{target, True{}, now_ms, True{}}, typing_tag_line(target, "active") <> Nil{})
    case True{}: step_out.refresh(target, sent_ms, now_ms, elapsed, U32.is_ge(elapsed, 2147483648))

def step_out.idle(+target: String, live: Bool, +now_ms: U32) -> OutState & List<&2, String>:
  match live:
    case True{}: (Out{target, False{}, now_ms, True{}}, typing_tag_line(target, "done") <> Nil{})
    case False{}: (Out{target, False{}, now_ms, True{}}, Nil{})

def step_out.same(+target: String, live: Bool, +sent_ms: U32, +now_ms: U32, composing: Bool) -> OutState & List<&2, String>:
  match composing:
    case True{}: step_out.compose(target, live, sent_ms, now_ms, U32.sub(now_ms, sent_ms))
    case False{}: step_out.idle(target, live, now_ms)

def step_out.moved_idle(+target: String, +now_ms: U32, composing: Bool) -> OutState & List<&2, String>:
  match composing:
    case True{}: (Out{target, True{}, now_ms, True{}}, typing_tag_line(target, "active") <> Nil{})
    case False{}: (Out{target, False{}, now_ms, True{}}, Nil{})

def step_out.moved(+cur: String, live: Bool, +now_ms: U32, +target: String, composing: Bool) -> OutState & List<&2, String>:
  match live:
    case True{}: (Out{target, False{}, now_ms, True{}}, typing_tag_line(cur, "done") <> Nil{})
    case False{}: step_out.moved_idle(target, now_ms, composing)

def step_out.target(+cur: String, live: Bool, +sent_ms: U32, +now_ms: U32, +target: String, composing: Bool, same: Bool) -> OutState & List<&2, String>:
  match same:
    case True{}: step_out.same(target, live, sent_ms, now_ms, composing)
    case False{}: step_out.moved(cur, live, now_ms, target, composing)

# Negotiated target comparison: the same/different-target decision folds under
# the caller's CASEMAPPING through the shared Cl.buf_eq_cm comparator (one
# fold owner: Irc.fold_casemap), matching the cards/message `_cm` threading.
# Fixed wrappers below delegate with Cl.dflt_cm() ("rfc1459"), which folds
# exactly like Irc.ieq, so an absent 005 burst changes nothing.
def step_out.scope_cm(+cm: String, +cur: String, live: Bool, +sent_ms: U32, +now_ms: U32, valid: Bool, +target: String, composing: Bool) -> OutState & List<&2, String>:
  match valid:
    case True{}: step_out.target(cur, live, sent_ms, now_ms, target, composing, Cl.buf_eq_cm(cm, cur, target))
    case False{}: (Out{"", False{}, now_ms, True{}}, Nil{})

def step_out.scope(+cur: String, live: Bool, +sent_ms: U32, +now_ms: U32, valid: Bool, +target: String, composing: Bool) -> OutState & List<&2, String>:
  step_out.scope_cm(Cl.dflt_cm(), cur, live, sent_ms, now_ms, valid, target, composing)

# G6.5: the uninitialized state is unobserved, not a timestamp. sent_ms only
# becomes a baseline after a first tick; without that, the half-range stale
# veto would mistake the first observation at/after 2^31 for clock skew and
# hold the span quiet until the clock wraps. G6.6: observed-ness is an
# explicit bit, not a field sniff: an observed offline reset lands on the
# same Out{"",False{},0} shape as out0, so sniffing would mistake a backward
# observed tick for a first observation and emit.
def step_out.unseen(seen: Bool) -> Bool:
  match seen:
    case True{}: False{}
    case False{}: True{}

def step_out.stale(+sent_ms: U32, +now_ms: U32, seen: Bool) -> Bool:
  U32.is_ge(U32.sub(now_ms, sent_ms), 2147483648) && Bool.not(step_out.unseen(seen))

# G6.4: a tick older than the last send (clock skew) stays quiet AND keeps
# its state on every path: no done/active send, no live flip, no sent_ms move.
def step_out.fresh_cm(+cm: String, +cur: String, +live: Bool, +sent_ms: U32, +now_ms: U32, valid: Bool, +target: String, composing: Bool, stale: Bool) -> OutState & List<&2, String>:
  match stale:
    case True{}: (Out{cur, live, sent_ms, True{}}, Nil{})
    case False{}: step_out.scope_cm(cm, cur, live, sent_ms, now_ms, valid, target, composing)

def step_out.fresh(+cur: String, +live: Bool, +sent_ms: U32, +now_ms: U32, valid: Bool, +target: String, composing: Bool, stale: Bool) -> OutState & List<&2, String>:
  step_out.fresh_cm(Cl.dflt_cm(), cur, live, sent_ms, now_ms, valid, target, composing, stale)

def step_out_cm(+cm: String, +st: OutState, +now_ms: U32, online: Bool, tags_ok: Bool, +target: String, composing: Bool) -> OutState & List<&2, String>:
  match st:
    case Out{+cur, +live, +sent, +seen}:
      step_out.fresh_cm(cm, cur, live, sent, now_ms, online && tags_ok && out_target_ok(target), target, composing, step_out.stale(sent, now_ms, seen))

def step_out(+st: OutState, +now_ms: U32, online: Bool, tags_ok: Bool, +target: String, composing: Bool) -> OutState & List<&2, String>:
  step_out_cm(Cl.dflt_cm(), st, now_ms, online, tags_ok, target, composing)

# ---- session-owned registration state -------------------------------------
# One value for the integrator to store: negotiated caps plus outbound typing.
# Caps update on every wire line; outbound sends only through reg_out, which
# gates on negotiated message-tags. No stored state, no sends.

type Reg is Data:
  Reg{caps: Caps, out: OutState}

def reg0() -> Reg:
  Reg{caps0(), out0()}

def reg_on_line(+reg: Reg, +server: String, +nick: String, +line: String, registered: Bool) -> Reg:
  match reg:
    case Reg{+caps, +out}: Reg{caps_apply_line(caps, server, nick, line, registered), out}

def reg_out.done(+caps: Caps, pair: OutState & List<&2, String>) -> Reg & List<&2, String>:
  match pair:
    case (+out, +outs): (Reg{caps, out}, outs)

def reg_out_cm(+cm: String, +reg: Reg, +now_ms: U32, online: Bool, +target: String, composing: Bool) -> Reg & List<&2, String>:
  match reg:
    case Reg{+caps, +out}:
      reg_out.done(caps, step_out_cm(cm, out, now_ms, online, tags_ok(caps), target, composing))

def reg_out(+reg: Reg, +now_ms: U32, online: Bool, +target: String, composing: Bool) -> Reg & List<&2, String>:
  reg_out_cm(Cl.dflt_cm(), reg, now_ms, online, target, composing)

def step_reg(pair: Reg & List<&2, String>) -> Reg:
  match pair:
    case (+reg, _): reg

def reg_text(pair: Reg & List<&2, String>) -> String:
  match pair:
    case (_, +xs): String.concat(xs)

def reg_target(+reg: Reg) -> String:
  match reg:
    case Reg{_, +out}: out_target(out)

# Session send-path gate: when True, local echoes are suppressed and the
# server's echo-message copy is the single rendered confirmation.
def reg_echo_ok(+reg: Reg) -> Bool:
  match reg:
    case Reg{+caps, _}: echo_ok(caps)

# Live tick bundle for the Session/Net binding: composing is a nonempty
# composer on a valid target. The binding stores the returned Reg and sends
# at most one wire through the bounded actor path.
def live_composing(+target: String, +draft: String) -> Bool:
  out_target_ok(target) && Bool.not(String.is_empty(draft))

def live_tick_cm(+cm: String, +reg: Reg, +now_ms: U32, online: Bool, +target: String, +draft: String) -> Reg & List<&2, String>:
  reg_out_cm(cm, reg, now_ms, online, target, live_composing(target, draft))

def live_tick(+reg: Reg, +now_ms: U32, online: Bool, +target: String, +draft: String) -> Reg & List<&2, String>:
  live_tick_cm(Cl.dflt_cm(), reg, now_ms, online, target, draft)

# ---- law/test predicates ---------------------------------------------------

def list_has.go(xs: List<&2, String>, +want: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}: String.eq(h, want) || list_has.go(t, want)

def list_has(+xs: List<&2, String>, +want: String) -> Bool:
  list_has.go(xs, want)

def outs_text(+xs: List<&2, String>) -> String:
  String.concat(xs)

def outs_bounded(+xs: List<&2, String>) -> Bool:
  Nat.is_le(List.length(&2, String, xs), 1n)

def cap_end_single_owner_ok() -> Bool:
  String.eq(outs_text(cap_end_for(Cl.AuthCap{}, Cl.AuthDone{})), "CAP END")
    && String.eq(outs_text(cap_end_for(Cl.AuthChallenge{}, Cl.AuthDone{})), "CAP END")
    && String.eq(outs_text(cap_end_for(Cl.AuthResult{}, Cl.AuthDone{})), "CAP END")
    && String.eq(outs_text(cap_end_for(Cl.AuthCap{}, Cl.AuthNickWait{})), "CAP END")
    && String.is_empty(outs_text(cap_end_for(Cl.AuthDone{}, Cl.AuthDone{})))
    && String.is_empty(outs_text(cap_end_for(Cl.AuthIdle{}, Cl.AuthIdle{})))
    && String.is_empty(outs_text(cap_end_for(Cl.AuthCap{}, Cl.AuthCap{})))
    && String.is_empty(outs_text(cap_end_for(Cl.AuthIdle{}, Cl.AuthDone{})))
    && String.is_empty(outs_text(cap_end_for(Cl.AuthNickWait{}, Cl.AuthNickWait{})))
    && String.is_empty(outs_text(cap_end_handshake(True{})))
    && String.eq(outs_text(cap_end_handshake(False{})), "CAP END")
    && list_has(req_lines(True{}), "CAP REQ :sasl")
    && list_has(req_lines(True{}), "CAP REQ :server-time")
    && list_has(req_lines(True{}), "CAP REQ :message-tags")
    && list_has(req_lines(True{}), "CAP REQ :account-notify")
    && list_has(req_lines(True{}), "CAP REQ :away-notify")
    && Bool.not(list_has(req_lines(False{}), "CAP REQ :sasl"))
    && list_has(req_lines(False{}), "CAP REQ :account-notify")
    && list_has(req_lines(False{}), "CAP REQ :away-notify")
    && String.eq(Irc.format_cap_req(CAP_NOTIFY()), "CAP REQ :cap-notify")

def caps_parse_ok() -> Bool:
  +acked = caps_apply_line(caps0(), "s", "me", ":s CAP me ACK :message-tags account-notify", True{})
  +lsed = caps_apply_line(caps0(), "s", "me", ":s CAP me LS * :away-notify", True{})
  +naked = caps_apply_line(caps0(), "s", "me", ":s CAP me NAK :message-tags", True{})
  +chat = caps_apply_line(caps0(), "s", "me", ":alice!u@h PRIVMSG me :CAP ACK message-tags", True{})
  +newed = caps_apply_line(caps0(), "s", "me", ":s CAP me NEW :cap-notify", True{})
  +new_other = caps_apply_line(caps0(), "s", "me", ":s CAP me LS :cap-notify", True{})
  +echo = caps_apply_line(caps0(), "s", "me", ":s CAP me ACK :echo-message", True{})
  tags_ok(acked) && account_ok(acked) && Bool.not(away_ok(acked))
    && Bool.not(tags_ok(lsed) || account_ok(lsed) || away_ok(lsed))
    && Bool.not(tags_ok(naked))
    && Bool.not(tags_ok(chat))
    && notify_ok(newed) && Bool.not(notify_ok(new_other))
    && echo_ok(echo)

# G6.1 guards: user prefixes and foreign recipients never enable; our server
# addressing us (or the '*' registration recipient while unregistered) does.
# A registered '*' line is rejected: caps stay unchanged.
def cap_trust_ok() -> Bool:
  +legit = caps_apply_line(caps0(), "s", "me", ":s CAP me ACK :message-tags", True{})
  +star = caps_apply_line(caps0(), "s", "me", ":s CAP * ACK :message-tags", False{})
  +star_reg = caps_apply_line(caps0(), "s", "me", ":s CAP * ACK :message-tags", True{})
  +spoof = caps_apply_line(caps0(), "s", "me", ":alice!u@h CAP me ACK :message-tags", True{})
  +other = caps_apply_line(caps0(), "s", "me", ":s CAP other ACK :message-tags", True{})
  +bare = caps_apply_line(caps0(), "s", "me", "CAP me ACK :message-tags", True{})
  tags_ok(legit) && tags_ok(star)
    && Bool.not(tags_ok(star_reg)) && Bool.not(tags_ok(spoof)) && Bool.not(tags_ok(other)) && Bool.not(tags_ok(bare))

# G6.2 guards: DEL clears, '-cap' inside ACK clears, enable still works, and
# untouched caps survive a removal.
def caps_removal_ok() -> Bool:
  +on = caps_apply_line(caps0(), "s", "me", ":s CAP me ACK :message-tags account-notify away-notify", True{})
  +neg = caps_apply_line(on, "s", "me", ":s CAP me ACK :-message-tags", True{})
  +del = caps_apply_line(on, "s", "me", ":s CAP me DEL :account-notify away-notify", True{})
  +reack = caps_apply_line(neg, "s", "me", ":s CAP me ACK :message-tags", True{})
  +direct = caps_apply(caps_apply(caps0(), CapEvent{CapAck{}, "message-tags" <> Nil{}}), CapEvent{CapDel{}, "message-tags" <> Nil{}})
  +direct_neg = caps_apply(caps_apply(caps0(), CapEvent{CapAck{}, "message-tags" <> Nil{}}), CapEvent{CapAck{}, "-message-tags" <> Nil{}})
  +new_on = caps_apply_line(caps0(), "s", "me", ":s CAP me NEW :cap-notify", True{})
  +new_del = caps_apply_line(new_on, "s", "me", ":s CAP me DEL :cap-notify", True{})
  +direct_new = caps_apply(caps0(), CapEvent{CapNew{}, "cap-notify" <> Nil{}})
  +eon = caps_apply_line(caps0(), "s", "me", ":s CAP me ACK :echo-message message-tags", True{})
  +eneg = caps_apply_line(eon, "s", "me", ":s CAP me ACK :-echo-message", True{})
  +edel = caps_apply_line(eon, "s", "me", ":s CAP me DEL :echo-message", True{})
  tags_ok(on) && account_ok(on) && away_ok(on)
    && Bool.not(tags_ok(neg)) && account_ok(neg) && away_ok(neg)
    && tags_ok(del) && Bool.not(account_ok(del)) && Bool.not(away_ok(del))
    && tags_ok(reack)
    && Bool.not(tags_ok(direct)) && Bool.not(tags_ok(direct_neg))
    && notify_ok(new_on) && Bool.not(notify_ok(new_del)) && notify_ok(direct_new)
    && echo_ok(eon) && Bool.not(echo_ok(eneg)) && tags_ok(eneg)
    && Bool.not(echo_ok(edel)) && tags_ok(edel)

def caps_ack_only_ok() -> Bool:
  Bool.not(tags_ok(caps0())) && Bool.not(account_ok(caps0())) && Bool.not(away_ok(caps0())) && Bool.not(notify_ok(caps0())) && Bool.not(echo_ok(caps0()))
    && tags_ok(caps_apply(caps0(), CapEvent{CapAck{}, "message-tags" <> Nil{}}))
    && account_ok(caps_apply(caps0(), CapEvent{CapAck{}, "account-notify" <> Nil{}}))
    && away_ok(caps_apply(caps0(), CapEvent{CapAck{}, "away-notify" <> Nil{}}))
    && notify_ok(caps_apply(caps0(), CapEvent{CapAck{}, "cap-notify" <> Nil{}}))
    && notify_ok(caps_apply(caps0(), CapEvent{CapNew{}, "cap-notify" <> Nil{}}))
    && echo_ok(caps_apply(caps0(), CapEvent{CapAck{}, "echo-message" <> Nil{}}))
    && Bool.not(tags_ok(caps_apply(caps0(), CapEvent{CapLs{}, "message-tags" <> Nil{}})))
    && Bool.not(tags_ok(caps_apply(caps0(), CapEvent{CapNak{}, "message-tags" <> Nil{}})))
    && Bool.not(tags_ok(caps_apply(caps0(), CapEvent{CapOther{}, "message-tags" <> Nil{}})))
    && Bool.not(notify_ok(caps_apply(caps0(), CapEvent{CapNak{}, "cap-notify" <> Nil{}})))
    && Bool.not(notify_ok(caps_apply(caps0(), CapEvent{CapOther{}, "cap-notify" <> Nil{}})))
    && Bool.not(echo_ok(caps_apply(caps0(), CapEvent{CapLs{}, "echo-message" <> Nil{}})))
    && Bool.not(echo_ok(caps_apply(caps0(), CapEvent{CapNak{}, "echo-message" <> Nil{}})))
    && Bool.not(echo_ok(caps_apply(caps0(), CapEvent{CapOther{}, "echo-message" <> Nil{}})))
    && has_cap(Commands.words("sasl=PLAIN message-tags"), "sasl")
    && Bool.not(has_cap(Commands.words("not-sasl"), "sasl"))
    && caps_parse_ok() && cap_trust_ok() && caps_removal_ok()

# echo-message guards: plain 302 name on the wire, ACK-only enable through
# the shared trust gate (hostile post-register lines never arm it), DEL and
# '-' removal mirror enable, and the Reg-level send gate follows the bit.
def caps_echo_ok() -> Bool:
  +on = caps_apply_line(caps0(), "s", "me", ":s CAP me ACK :echo-message", True{})
  +valued = caps_apply(caps0(), CapEvent{CapAck{}, "echo-message=1" <> Nil{}})
  +upper = caps_apply(caps0(), CapEvent{CapAck{}, "ECHO-MESSAGE" <> Nil{}})
  +star_reg = caps_apply_line(caps0(), "s", "me", ":s CAP * ACK :echo-message", True{})
  +spoof = caps_apply_line(caps0(), "s", "me", ":alice!u@h CAP me ACK :echo-message", True{})
  +del = caps_apply_line(on, "s", "me", ":s CAP me DEL :echo-message", True{})
  +neg = caps_apply_line(on, "s", "me", ":s CAP me ACK :-echo-message", True{})
  String.eq(CAP_ECHO(), "echo-message")
    && String.eq(Irc.format_cap_req(CAP_ECHO()), "CAP REQ :echo-message")
    && Bool.not(echo_ok(caps0()))
    && echo_ok(on) && echo_ok(valued) && echo_ok(upper)
    && Bool.not(echo_ok(star_reg)) && Bool.not(echo_ok(spoof))
    && Bool.not(echo_ok(del)) && Bool.not(echo_ok(neg))
    && Bool.not(reg_echo_ok(reg0()))
    && reg_echo_ok(Reg{on, out0()})

def is_account_on(e: NotifyEvent, +nick: String, +account: String) -> Bool:
  match e:
    case AccountOn{+n, +a}: String.eq(n, nick) && String.eq(a, account)
    case _: False{}

def is_account_off(e: NotifyEvent, +nick: String) -> Bool:
  match e:
    case AccountOff{+n}: String.eq(n, nick)
    case _: False{}

def is_away_on(e: NotifyEvent, +nick: String, +message: String) -> Bool:
  match e:
    case AwayOn{+n, +msg}: String.eq(n, nick) && String.eq(msg, message)
    case _: False{}

def is_away_off(e: NotifyEvent, +nick: String) -> Bool:
  match e:
    case AwayOff{+n}: String.eq(n, nick)
    case _: False{}

def is_other(e: NotifyEvent) -> Bool:
  match e:
    case NotifyOther{}: True{}
    case _: False{}

def notify_parse_ok() -> Bool:
  is_account_on(notify_event("s", "alice!u@h", Irc.Message{"", "alice", "ACCOUNT", 0, "alice123" <> Nil{}}), "alice", "alice123")
    && is_account_off(notify_event("s", "alice!u@h", Irc.Message{"", "alice", "ACCOUNT", 0, "*" <> Nil{}}), "alice")
    && is_away_on(notify_event("s", "bob!u@h", Irc.Message{"", "bob", "AWAY", 0, "out to lunch" <> Nil{}}), "bob", "out to lunch")
    && is_away_off(notify_event("s", "bob!u@h", Irc.Message{"", "bob", "AWAY", 0, Nil{}}), "bob")
    && is_account_on(notify_event("s", "alice!u@h", Irc.Message{"", "alice", "account", 0, "alice123" <> Nil{}}), "alice", "alice123")
    && String.eq(notify_text(AccountOn{"alice", "alice123"}), "alice signed in as alice123")
    && String.eq(notify_text(AccountOff{"alice"}), "alice signed out")
    && String.eq(notify_text(AwayOn{"bob", "out to lunch"}), "bob is away: out to lunch")
    && String.eq(notify_text(AwayOn{"bob", ""}), "bob is away")
    && String.eq(notify_text(AwayOff{"bob"}), "bob is back")
    && String.eq(notify_text(NotifyOther{}), "")

# G6.3 guards: server-like full prefixes never become user presence, for both
# ACCOUNT and AWAY; user prefixes still do.
def notify_source_ok() -> Bool:
  is_other(notify_event("s", "s", Irc.Message{"", "s", "AWAY", 0, "maintenance" <> Nil{}}))
    && is_other(notify_event("irc.example.com", "irc.example.com", Irc.Message{"", "irc.example.com", "AWAY", 0, "maintenance" <> Nil{}}))
    && is_other(notify_event("s", "s", Irc.Message{"", "s", "ACCOUNT", 0, "alice123" <> Nil{}}))
    && is_away_on(notify_event("s", "bob!u@h", Irc.Message{"", "bob", "AWAY", 0, "out" <> Nil{}}), "bob", "out")
    && is_account_on(notify_event("s", "alice!u@h", Irc.Message{"", "alice", "ACCOUNT", 0, "alice123" <> Nil{}}), "alice", "alice123")

def notify_reject_ok() -> Bool:
  is_other(notify_event("s", "alice!u@h", Irc.Message{"", "", "ACCOUNT", 0, "alice123" <> Nil{}}))
    && is_other(notify_event("s", "alice!u@h", Irc.Message{"", "#room", "ACCOUNT", 0, "alice123" <> Nil{}}))
    && is_other(notify_event("s", "bob!u@h", Irc.Message{"", "*", "AWAY", 0, "gone" <> Nil{}}))
    && is_other(notify_event("s", "bob!u@h", Irc.Message{"", "a b", "AWAY", 0, "gone" <> Nil{}}))
    && is_other(notify_event("s", "alice!u@h", Irc.Message{"", "alice", "ACCOUNT", 0, Nil{}}))
    && is_other(notify_event("s", "alice!u@h", Irc.Message{"", "alice", "ACCOUNT", 0, "a" <> "b" <> Nil{}}))
    && is_other(notify_event("s", "alice!u@h", Irc.Message{"", "alice", "ACCOUNT", 0, "" <> Nil{}}))
    && is_other(notify_event("s", "bob!u@h", Irc.Message{"", "bob", "AWAY", 0, "a" <> "b" <> Nil{}}))
    && is_other(notify_event("s", "alice!u@h", Irc.Message{"", "alice", "PRIVMSG", 0, "me" <> "hi" <> Nil{}}))
    && Bool.not(is_notify("s", "alice!u@h", Irc.Message{"", "alice", "PRIVMSG", 0, "me" <> "hi" <> Nil{}}))
    && is_notify("s", "alice!u@h", Irc.Message{"", "alice", "ACCOUNT", 0, "alice123" <> Nil{}})
    && notify_source_ok()

def step_text(pair: OutState & List<&2, String>) -> String:
  match pair:
    case (_, +xs): String.concat(xs)

def step_live(pair: OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, _): out_live(st)

def step_target(pair: OutState & List<&2, String>) -> String:
  match pair:
    case (+st, _): out_target(st)

def step_bounded(pair: OutState & List<&2, String>) -> Bool:
  match pair:
    case (_, +xs): outs_bounded(xs)

def step_state(pair: OutState & List<&2, String>) -> OutState:
  match pair:
    case (+st, _): st

def step_sent_ms(pair: OutState & List<&2, String>) -> U32:
  match pair:
    case (+st, _): out_sent_ms(st)

def long_target.go(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "x" ++ long_target.go(p)

# G6.4 guards: stale ticks are quiet and preserve live/sent on the completion,
# activation, and refresh paths; fresh completion/refresh still fire.
def out_stale_ok() -> Bool:
  +live: OutState = Out{"#a", True{}, 1000, True{}}
  +idle: OutState = Out{"#a", False{}, 1000, True{}}
  String.is_empty(step_text(step_out(live, 999, True{}, True{}, "#a", False{})))
    && step_live(step_out(live, 999, True{}, True{}, "#a", False{}))
    && U32.is_eq(step_sent_ms(step_out(live, 999, True{}, True{}, "#a", False{})), 1000)
    && String.is_empty(step_text(step_out(idle, 999, True{}, True{}, "#a", True{})))
    && Bool.not(step_live(step_out(idle, 999, True{}, True{}, "#a", True{})))
    && U32.is_eq(step_sent_ms(step_out(idle, 999, True{}, True{}, "#a", True{})), 1000)
    && String.is_empty(step_text(step_out(live, 999, True{}, True{}, "#a", True{})))
    && step_live(step_out(live, 999, True{}, True{}, "#a", True{}))
    && U32.is_eq(step_sent_ms(step_out(live, 999, True{}, True{}, "#a", True{})), 1000)
    && String.eq(step_text(step_out(live, 2000, True{}, True{}, "#a", False{})), "@+typing=done TAGMSG #a")
    && String.eq(step_text(step_out(live, 4000, True{}, True{}, "#a", True{})), "@+typing=active TAGMSG #a")

def out_bound_ok() -> Bool:
  +live: OutState = Out{"#a", True{}, 1000, True{}}
  String.is_empty(step_text(step_out(out0(), 2000, False{}, True{}, "#a", True{})))
    && String.is_empty(step_text(step_out(out0(), 2000, True{}, False{}, "#a", True{})))
    && String.is_empty(step_text(step_out(out0(), 2000, True{}, True{}, "", True{})))
    && String.is_empty(step_text(step_out(out0(), 2000, True{}, True{}, "*log*", True{})))
    && String.is_empty(step_text(step_out(out0(), 2000, True{}, True{}, "a b", True{})))
    && String.is_empty(step_text(step_out(out0(), 2000, True{}, True{}, long_target.go(600n), True{})))
    && Bool.not(out_target_ok(long_target.go(600n)))
    && out_target_ok(long_target.go(487n))
    && String.is_empty(step_text(step_out(live, 1000, True{}, True{}, "#a", True{})))
    && step_live(step_out(live, 1000, True{}, True{}, "#a", True{}))
    && Bool.not(step_live(step_out(live, 2000, False{}, True{}, "#a", True{})))
    && step_bounded(step_out(out0(), 2000, True{}, True{}, "#a", True{}))
    && step_bounded(step_out(live, 2000, True{}, True{}, "#a", False{}))
    && step_bounded(step_out(live, 2000, True{}, True{}, "#b", True{}))
    && out_stale_ok()

def reg_quiet(pair: Reg & List<&2, String>) -> Bool:
  match pair:
    case (_, +xs): String.is_empty(String.concat(xs))

def reg_denied(pair: Reg & List<&2, String>) -> Bool:
  match pair:
    case (_, +xs): String.is_empty(String.concat(xs))

def reg_live(pair: Reg & List<&2, String>) -> Bool:
  match pair:
    case (_, +xs): String.eq(String.concat(xs), "@+typing=active TAGMSG #a")

# No negotiated tags, no sends: the same tick is quiet before ACK and live
# after it, and a NAK-only server stays quiet. Hostile CAP lines never arm it.
def reg_gating_ok() -> Bool:
  +bare = reg0()
  +acked = reg_on_line(reg_on_line(bare, "s", "me", ":s CAP me LS :message-tags", True{}), "s", "me", ":s CAP me ACK :message-tags", True{})
  +naked = reg_on_line(bare, "s", "me", ":s CAP me NAK :message-tags", True{})
  +spoofed = reg_on_line(bare, "s", "me", ":alice!u@h CAP me ACK :message-tags", True{})
  +bare_quiet = reg_quiet(reg_out(bare, 1000, True{}, "#a", True{}))
  bare_quiet && reg_denied(reg_out(naked, 1000, True{}, "#a", True{})) && reg_denied(reg_out(spoofed, 1000, True{}, "#a", True{})) && reg_live(reg_out(acked, 1000, True{}, "#a", True{}))

def out_lifecycle.after_retarget(pair: OutState & List<&2, String>, +acc: Bool) -> Bool:
  match pair:
    case (_, +xs):
      acc && String.eq(String.concat(xs), "@+typing=active TAGMSG #b") && reg_gating_ok()

def out_lifecycle.after_moved(pair: OutState & List<&2, String>, +acc: Bool) -> Bool:
  match pair:
    case (+st, +xs):
      out_lifecycle.after_retarget(step_out(st, 4200, True{}, True{}, "#b", True{}), acc && String.eq(String.concat(xs), "@+typing=done TAGMSG #a") && String.eq(out_target(st), "#b"))

def out_lifecycle.after_quiet(pair: OutState & List<&2, String>, +prev: OutState, +acc: Bool) -> Bool:
  match pair:
    case (+st, +xs):
      out_lifecycle.after_moved(step_out(prev, 4100, True{}, True{}, "#b", True{}), acc && String.is_empty(String.concat(xs)) && Bool.not(out_live(st)))

def out_lifecycle.after_done(pair: OutState & List<&2, String>, +prev: OutState, +acc: Bool) -> Bool:
  match pair:
    case (+st, +xs):
      out_lifecycle.after_quiet(step_out(st, 4200, True{}, True{}, "#a", False{}), prev, acc && String.eq(String.concat(xs), "@+typing=done TAGMSG #a") && Bool.not(out_live(st)))

def out_lifecycle.after_refresh(pair: OutState & List<&2, String>, +acc: Bool) -> Bool:
  match pair:
    case (+st, +xs):
      out_lifecycle.after_done(step_out(st, 4100, True{}, True{}, "#a", False{}), st, acc && String.eq(String.concat(xs), "@+typing=active TAGMSG #a") && out_live(st))

def out_lifecycle.after_throttle(pair: OutState & List<&2, String>, +prev: OutState, +acc: Bool) -> Bool:
  match pair:
    case (+st, +xs):
      out_lifecycle.after_refresh(step_out(prev, 4000, True{}, True{}, "#a", True{}), acc && String.is_empty(String.concat(xs)) && out_live(st))

def out_lifecycle.after_start(pair: OutState & List<&2, String>, +acc: Bool) -> Bool:
  match pair:
    case (+st, +xs):
      out_lifecycle.after_throttle(step_out(st, 1500, True{}, True{}, "#a", True{}), st, acc && String.eq(String.concat(xs), "@+typing=active TAGMSG #a") && out_live(st))

def out_lifecycle_ok() -> Bool:
  out_lifecycle.after_start(step_out(out0(), 1000, True{}, True{}, "#a", True{}), True{})

def first_tick_ok(pair: OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, +xs):
      String.eq(String.concat(xs), "@+typing=active TAGMSG #a") && out_live(st) && U32.is_eq(out_sent_ms(st), 2147483648)

def stale_kept_ok(pair: OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, +xs):
      String.is_empty(String.concat(xs)) && out_live(st) && U32.is_eq(out_sent_ms(st), 1000)

def wrap_quiet_ok(pair: OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, +xs):
      String.is_empty(String.concat(xs)) && out_live(st) && U32.is_eq(out_sent_ms(st), 4294967295)

def wrap_fire_ok(pair: OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, +xs):
      String.eq(String.concat(xs), "@+typing=active TAGMSG #a") && out_live(st) && U32.is_eq(out_sent_ms(st), 4000)

# G6.5 guards: the first tick from the uninitialized state is a live
# observation at any clock value; an established backward tick stays quiet
# and unchanged; genuine forward U32 wrap stays live.
def out_unseen_ok() -> Bool:
  first_tick_ok(step_out(out0(), 2147483648, True{}, True{}, "#a", True{}))
    && stale_kept_ok(step_out(Out{"#a", True{}, 1000, True{}}, 999, True{}, True{}, "#a", True{}))
    && wrap_quiet_ok(step_out(Out{"#a", True{}, 4294967295, True{}}, 100, True{}, True{}, "#a", True{}))
    && wrap_fire_ok(step_out(Out{"#a", True{}, 4294967295, True{}}, 4000, True{}, True{}, "#a", True{}))

# G6.6 guards: an observed offline reset (same shape as out0) stays quiet on
# a backward tick to max; a truly fresh out0 at max still fires; a genuine
# forward max -> 4000 wrap still fires.
def out_sentinel_ok() -> Bool:
  +obs = step_state(step_out(out0(), 0, False{}, True{}, "#a", False{}))
  String.is_empty(step_text(step_out(obs, 4294967295, True{}, True{}, "#a", True{})))
    && String.eq(step_text(step_out(out0(), 4294967295, True{}, True{}, "#a", True{})), "@+typing=active TAGMSG #a")
    && wrap_fire_ok(step_out(Out{"#a", True{}, 4294967295, True{}}, 4000, True{}, True{}, "#a", True{}))

# Malformed-source guards: the shared host validation admits a configured
# single-label server and a valid dotted server, preserves prereg star LS/ACK,
# and rejects URL, delimiter, and empty-label sources; peer prefixes and a
# valid single-label server never drive CAP state or user presence.
def cap_source_ok() -> Bool:
  +single = caps_apply_line(caps0(), "s", "me", ":s CAP me ACK :message-tags", True{})
  +dotted = caps_apply_line(caps0(), "irc.example.com", "me", ":irc.example.com CAP me ACK :message-tags", True{})
  +url = caps_apply_line(caps0(), "s", "me", ":http://evil.com/x CAP me ACK :message-tags", True{})
  +colon = caps_apply_line(caps0(), "s", "me", ":a:b.c CAP me ACK :message-tags", True{})
  +comma = caps_apply_line(caps0(), "s", "me", ":a,b.c CAP me ACK :message-tags", True{})
  +empty_label = caps_apply_line(caps0(), "s", "me", ":a..b CAP me ACK :message-tags", True{})
  tags_ok(single) && tags_ok(dotted)
    && Bool.not(tags_ok(url)) && Bool.not(tags_ok(colon)) && Bool.not(tags_ok(comma)) && Bool.not(tags_ok(empty_label))
    && cap_is_ls(cap_kind_line("s", "me", ":s CAP * LS :sasl message-tags", False{}))
    && Bool.not(cap_is_ls(cap_kind_line("s", "me", ":alice!u@h CAP * LS :sasl", False{})))
    && is_other(notify_event("s", "hub", Irc.Message{"", "hub", "AWAY", 0, "nightly restart" <> Nil{}}))
    && is_away_on(notify_event("s", "bob!u@h", Irc.Message{"", "bob", "AWAY", 0, "out" <> Nil{}}), "bob", "out")
