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

# Requested set, in stable wire order. Outbound typing rides on message-tags.
def wanted.sasl(want: Bool) -> List<&2, String>:
  match want:
    case True{}:
      CAP_SASL() <> CAP_SERVER_TIME() <> CAP_MESSAGE_TAGS() <> CAP_ACCOUNT() <> CAP_AWAY() <> Nil{}
    case False{}:
      CAP_SERVER_TIME() <> CAP_MESSAGE_TAGS() <> CAP_ACCOUNT() <> CAP_AWAY() <> Nil{}

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
  CapOther{}

type CapEvent is Data:
  CapEvent{kind: CapKind, caps: List<&2, String>}

def cap_kind.ls(+sub: String, ls: Bool) -> CapKind:
  match ls:
    case True{}: CapLs{}
    case False{}: CapOther{}

def cap_kind.nak(+sub: String, nak: Bool) -> CapKind:
  match nak:
    case True{}: CapNak{}
    case False{}: cap_kind.ls(sub, Irc.ieq(sub, "LS"))

def cap_kind.ack(+sub: String, ack: Bool) -> CapKind:
  match ack:
    case True{}: CapAck{}
    case False{}: cap_kind.nak(sub, Irc.ieq(sub, "NAK"))

def cap_kind(+sub: String) -> CapKind:
  cap_kind.ack(sub, Irc.ieq(sub, "ACK"))

# Multi-line LS marks continuation with '*'; the caps are the last parameter.
def cap_caps_text.star(+m: Irc.Message, star: Bool) -> String:
  match star:
    case True{}: Irc.msg_param(m, 3n)
    case False{}: Irc.msg_param(m, 2n)

def cap_caps_text(+m: Irc.Message) -> String:
  cap_caps_text.star(m, Irc.ieq(Irc.msg_param(m, 1n), "LS") && String.eq(Irc.msg_param(m, 2n), "*"))

def cap_event.gated(+m: Irc.Message, ok: Bool) -> CapEvent:
  match ok:
    case False{}: CapEvent{CapOther{}, Nil{}}
    case True{}: CapEvent{cap_kind(Irc.msg_param(m, 1n)), Commands.words(cap_caps_text(m))}

def cap_event(+m: Irc.Message) -> CapEvent:
  cap_event.gated(m, Irc.ieq(Irc.msg_command(m), "CAP"))

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
  Caps{server_time: Bool, message_tags: Bool, account: Bool, away: Bool, sasl: Bool}

def caps0() -> Caps:
  Caps{False{}, False{}, False{}, False{}, False{}}

def caps_enable(+caps: Caps, +name: String) -> Caps:
  match caps:
    case Caps{+st, +mt, +ac, +aw, +sa}:
      Caps{st || cap_match.one(name, CAP_SERVER_TIME()), mt || cap_match.one(name, CAP_MESSAGE_TAGS()), ac || cap_match.one(name, CAP_ACCOUNT()), aw || cap_match.one(name, CAP_AWAY()), sa || cap_match.one(name, CAP_SASL())}

def caps_apply_list(xs: List<&2, String>, +caps: Caps) -> Caps:
  match xs:
    case Nil{}: caps
    case Con{+h, t}: caps_apply_list(t, caps_enable(caps, h))

def caps_apply.kind(+caps: Caps, +xs: List<&2, String>, kind: CapKind) -> Caps:
  match kind:
    case CapAck{}: caps_apply_list(xs, caps)
    case _: caps

def caps_apply(+caps: Caps, e: CapEvent) -> Caps:
  match e:
    case CapEvent{+kind, +xs}: caps_apply.kind(caps, xs, kind)

def caps_apply_line.parsed(+caps: Caps, m: Maybe<&2, Irc.Message>) -> Caps:
  match m:
    case None{}: caps
    case Some{+msg}: caps_apply(caps, cap_event(msg))

def caps_apply_line(+caps: Caps, +line: String) -> Caps:
  caps_apply_line.parsed(caps, Irc.parse(line))

def tags_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, +mt, _, _, _}: mt

def account_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, _, +ac, _, _}: ac

def away_ok(+caps: Caps) -> Bool:
  match caps:
    case Caps{_, _, _, +aw, _}: aw

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

def notify_event.checked(+m: Irc.Message, +nick: String, ok: Bool) -> NotifyEvent:
  match ok:
    case True{}: notify_event.cmd(nick, m, Irc.ieq(Irc.msg_command(m), "ACCOUNT"))
    case False{}: NotifyOther{}

def notify_event(+m: Irc.Message) -> NotifyEvent:
  +nick = notify_nick(m)
  notify_event.checked(m, nick, notify_nick_ok(nick))

def is_notify.event(e: NotifyEvent) -> Bool:
  match e:
    case NotifyOther{}: False{}
    case _: True{}

def is_notify(+m: Irc.Message) -> Bool:
  is_notify.event(notify_event(m))

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
  Out{target: String, live: Bool, sent_ms: U32}

def out0() -> OutState:
  Out{"", False{}, 0}

def OUT_REFRESH_MS() -> U32:
  3000

def typing_tag_line(+target: String, +status: String) -> String:
  "@+typing=" ++ status ++ " TAGMSG " ++ target

# 'active' is the longest status we send, so one bound check covers done too.
def out_target_ok(+target: String) -> Bool:
  Commands.word(target) && Cl.target_wire(target) && Irc.line_ok(typing_tag_line(target, "active"))

def out_live(+st: OutState) -> Bool:
  match st:
    case Out{_, +live, _}: live

def out_target(+st: OutState) -> String:
  match st:
    case Out{+target, _, _}: target

def step_out.refresh_due(+target: String, +sent_ms: U32, +now_ms: U32, +elapsed: U32, due: Bool) -> OutState & List<&2, String>:
  match due:
    case True{}: (Out{target, True{}, now_ms}, typing_tag_line(target, "active") <> Nil{})
    case False{}: (Out{target, True{}, sent_ms}, Nil{})

def step_out.refresh(+target: String, +sent_ms: U32, +now_ms: U32, +elapsed: U32, stale: Bool) -> OutState & List<&2, String>:
  match stale:
    case True{}: (Out{target, True{}, sent_ms}, Nil{})
    case False{}: step_out.refresh_due(target, sent_ms, now_ms, elapsed, U32.is_ge(elapsed, OUT_REFRESH_MS()))

def step_out.compose(+target: String, live: Bool, +sent_ms: U32, +now_ms: U32, +elapsed: U32) -> OutState & List<&2, String>:
  match live:
    case False{}: (Out{target, True{}, now_ms}, typing_tag_line(target, "active") <> Nil{})
    case True{}: step_out.refresh(target, sent_ms, now_ms, elapsed, U32.is_ge(elapsed, 2147483648))

def step_out.idle(+target: String, live: Bool, +now_ms: U32) -> OutState & List<&2, String>:
  match live:
    case True{}: (Out{target, False{}, now_ms}, typing_tag_line(target, "done") <> Nil{})
    case False{}: (Out{target, False{}, now_ms}, Nil{})

def step_out.same(+target: String, live: Bool, +sent_ms: U32, +now_ms: U32, composing: Bool) -> OutState & List<&2, String>:
  match composing:
    case True{}: step_out.compose(target, live, sent_ms, now_ms, U32.sub(now_ms, sent_ms))
    case False{}: step_out.idle(target, live, now_ms)

def step_out.moved_idle(+target: String, +now_ms: U32, composing: Bool) -> OutState & List<&2, String>:
  match composing:
    case True{}: (Out{target, True{}, now_ms}, typing_tag_line(target, "active") <> Nil{})
    case False{}: (Out{target, False{}, now_ms}, Nil{})

def step_out.moved(+cur: String, live: Bool, +now_ms: U32, +target: String, composing: Bool) -> OutState & List<&2, String>:
  match live:
    case True{}: (Out{target, False{}, now_ms}, typing_tag_line(cur, "done") <> Nil{})
    case False{}: step_out.moved_idle(target, now_ms, composing)

def step_out.target(+cur: String, live: Bool, +sent_ms: U32, +now_ms: U32, +target: String, composing: Bool, same: Bool) -> OutState & List<&2, String>:
  match same:
    case True{}: step_out.same(target, live, sent_ms, now_ms, composing)
    case False{}: step_out.moved(cur, live, now_ms, target, composing)

def step_out.scope(+cur: String, live: Bool, +sent_ms: U32, +now_ms: U32, valid: Bool, +target: String, composing: Bool) -> OutState & List<&2, String>:
  match valid:
    case True{}: step_out.target(cur, live, sent_ms, now_ms, target, composing, Irc.ieq(cur, target))
    case False{}: (Out{"", False{}, now_ms}, Nil{})

def step_out(+st: OutState, +now_ms: U32, online: Bool, tags_ok: Bool, +target: String, composing: Bool) -> OutState & List<&2, String>:
  match st:
    case Out{+cur, +live, +sent}:
      step_out.scope(cur, live, sent, now_ms, online && tags_ok && out_target_ok(target), target, composing)

# ---- session-owned registration state -------------------------------------
# One value for the integrator to store: negotiated caps plus outbound typing.
# Caps update on every wire line; outbound sends only through reg_out, which
# gates on negotiated message-tags. No stored state, no sends.

type Reg is Data:
  Reg{caps: Caps, out: OutState}

def reg0() -> Reg:
  Reg{caps0(), out0()}

def reg_on_line(+reg: Reg, +line: String) -> Reg:
  match reg:
    case Reg{+caps, +out}: Reg{caps_apply_line(caps, line), out}

def reg_out.done(+caps: Caps, pair: OutState & List<&2, String>) -> Reg & List<&2, String>:
  match pair:
    case (+out, +outs): (Reg{caps, out}, outs)

def reg_out(+reg: Reg, +now_ms: U32, online: Bool, +target: String, composing: Bool) -> Reg & List<&2, String>:
  match reg:
    case Reg{+caps, +out}:
      reg_out.done(caps, step_out(out, now_ms, online, tags_ok(caps), target, composing))

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

def caps_parse_ok() -> Bool:
  +acked = caps_apply_line(caps0(), ":s CAP me ACK :message-tags account-notify")
  +lsed = caps_apply_line(caps0(), ":s CAP me LS * :away-notify")
  +naked = caps_apply_line(caps0(), ":s CAP me NAK :message-tags")
  +chat = caps_apply_line(caps0(), ":alice!u@h PRIVMSG me :CAP ACK message-tags")
  tags_ok(acked) && account_ok(acked) && Bool.not(away_ok(acked))
    && Bool.not(tags_ok(lsed) || account_ok(lsed) || away_ok(lsed))
    && Bool.not(tags_ok(naked))
    && Bool.not(tags_ok(chat))

def caps_ack_only_ok() -> Bool:
  Bool.not(tags_ok(caps0())) && Bool.not(account_ok(caps0())) && Bool.not(away_ok(caps0()))
    && tags_ok(caps_apply(caps0(), CapEvent{CapAck{}, "message-tags" <> Nil{}}))
    && account_ok(caps_apply(caps0(), CapEvent{CapAck{}, "account-notify" <> Nil{}}))
    && away_ok(caps_apply(caps0(), CapEvent{CapAck{}, "away-notify" <> Nil{}}))
    && Bool.not(tags_ok(caps_apply(caps0(), CapEvent{CapLs{}, "message-tags" <> Nil{}})))
    && Bool.not(tags_ok(caps_apply(caps0(), CapEvent{CapNak{}, "message-tags" <> Nil{}})))
    && Bool.not(tags_ok(caps_apply(caps0(), CapEvent{CapOther{}, "message-tags" <> Nil{}})))
    && has_cap(Commands.words("sasl=PLAIN message-tags"), "sasl")
    && Bool.not(has_cap(Commands.words("not-sasl"), "sasl"))
    && caps_parse_ok()

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
  is_account_on(notify_event(Irc.Message{"", "alice", "ACCOUNT", 0, "alice123" <> Nil{}}), "alice", "alice123")
    && is_account_off(notify_event(Irc.Message{"", "alice", "ACCOUNT", 0, "*" <> Nil{}}), "alice")
    && is_away_on(notify_event(Irc.Message{"", "bob", "AWAY", 0, "out to lunch" <> Nil{}}), "bob", "out to lunch")
    && is_away_off(notify_event(Irc.Message{"", "bob", "AWAY", 0, Nil{}}), "bob")
    && is_account_on(notify_event(Irc.Message{"", "alice", "account", 0, "alice123" <> Nil{}}), "alice", "alice123")
    && String.eq(notify_text(AccountOn{"alice", "alice123"}), "alice signed in as alice123")
    && String.eq(notify_text(AccountOff{"alice"}), "alice signed out")
    && String.eq(notify_text(AwayOn{"bob", "out to lunch"}), "bob is away: out to lunch")
    && String.eq(notify_text(AwayOn{"bob", ""}), "bob is away")
    && String.eq(notify_text(AwayOff{"bob"}), "bob is back")
    && String.eq(notify_text(NotifyOther{}), "")

def notify_reject_ok() -> Bool:
  is_other(notify_event(Irc.Message{"", "", "ACCOUNT", 0, "alice123" <> Nil{}}))
    && is_other(notify_event(Irc.Message{"", "#room", "ACCOUNT", 0, "alice123" <> Nil{}}))
    && is_other(notify_event(Irc.Message{"", "*", "AWAY", 0, "gone" <> Nil{}}))
    && is_other(notify_event(Irc.Message{"", "a b", "AWAY", 0, "gone" <> Nil{}}))
    && is_other(notify_event(Irc.Message{"", "alice", "ACCOUNT", 0, Nil{}}))
    && is_other(notify_event(Irc.Message{"", "alice", "ACCOUNT", 0, "a" <> "b" <> Nil{}}))
    && is_other(notify_event(Irc.Message{"", "alice", "ACCOUNT", 0, "" <> Nil{}}))
    && is_other(notify_event(Irc.Message{"", "bob", "AWAY", 0, "a" <> "b" <> Nil{}}))
    && is_other(notify_event(Irc.Message{"", "alice", "PRIVMSG", 0, "me" <> "hi" <> Nil{}}))
    && Bool.not(is_notify(Irc.Message{"", "alice", "PRIVMSG", 0, "me" <> "hi" <> Nil{}}))
    && is_notify(Irc.Message{"", "alice", "ACCOUNT", 0, "alice123" <> Nil{}})

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

def long_target.go(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "x" ++ long_target.go(p)

def out_bound_ok() -> Bool:
  +live: OutState = Out{"#a", True{}, 1000}
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
# after it, and a NAK-only server stays quiet.
def reg_gating_ok() -> Bool:
  +bare = reg0()
  +acked = reg_on_line(reg_on_line(bare, ":s CAP me LS :message-tags"), ":s CAP me ACK :message-tags")
  +naked = reg_on_line(bare, ":s CAP me NAK :message-tags")
  +bare_quiet = reg_quiet(reg_out(bare, 1000, True{}, "#a", True{}))
  bare_quiet && reg_denied(reg_out(naked, 1000, True{}, "#a", True{})) && reg_live(reg_out(acked, 1000, True{}, "#a", True{}))

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
