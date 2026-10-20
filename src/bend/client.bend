# IRC feed dispatcher (M1). Container types live in buffer.bend.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./irc_commands.bend as Commands
import ./cap_notify.bend as CapNotify
import ./wire_style.bend as Ws

# ---- format helpers -----------------------------------------------------

def msg_nick(+m: Irc.Message) -> String:
  Cl.target_name(Irc.msg_nick(m))

def fmt_msg.empty(empty: Bool, +nick: String, +body: String) -> String:
  match empty:
    case True{}:
      "<*> " ++ body
    case False{}:
      "<" ++ nick ++ "> " ++ body

def fmt_msg(+nick: String, +body: String) -> String:
  fmt_msg.empty(String.is_empty(nick), nick, body)

def fmt_action(+nick: String, +body: String) -> String:
  "* " ++ nick ++ " " ++ body

def fmt_join(+nick: String, +chan: String) -> String:
  "-> " ++ nick ++ " joined " ++ chan

def fmt_part(+nick: String, +chan: String) -> String:
  "<- " ++ nick ++ " left " ++ chan

def fmt_quit(+nick: String, +reason: String) -> String:
  "<- " ++ nick ++ " quit (" ++ reason ++ ")"

def fmt_nick_chg(+from: String, +to: String) -> String:
  from ++ " is now known as " ++ to

def fmt_topic_set(+nick: String, +topic: String) -> String:
  nick ++ " set topic: " ++ topic

def fmt_num(+code: U32, +text: String) -> String:
  "[" ++ U32.show(code) ++ "] " ++ text

def fmt_err(+text: String) -> String:
  "ERROR " ++ text

def fmt_unk(+cmd: String, +p0: String) -> String:
  cmd ++ " " ++ p0

def join_sp.go(+ps: List<&2, String>, +acc: String) -> String:
  match ps:
    case Nil{}:
      acc
    case Con{+h, t}:
      join_sp.go(t, acc ++ " " ++ h)

def join_sp(+ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{+h, t}:
      h ++ join_sp.go(t, "")

def fmt_mode(+from: String, +ps: List<&2, String>) -> String:
  from ++ " MODE " ++ join_sp(ps)

# CTCP ACTION: \x01ACTION text\x01  (SOH = 1)
def is_action(+body: String) -> Bool:
  String.starts_with(body, SCon{Chr{1}, "ACTION "})

def action_text.soh(soh: Bool, +rest: String, t: String) -> String:
  match soh:
    case True{}:
      String.reverse(t)
    case False{}:
      rest

def action_text.fin(+rest: String, rev: String) -> String:
  match rev:
    case SCon{+h, t}:
      action_text.soh(Irc.code_is(h, 1), rest, t)
    case SNil{}:
      SNil{}

def action_text(+body: String) -> String:
  +rest = String.drop(body, 8n)
  action_text.fin(rest, String.reverse(rest))

# ---- feed arms ----------------------------------------------------------

# Synthetic names belong to local commands, never wire buffer identity.
# Generic container/focus lookup still accepts local tabs.
def wire_name(+name: String) -> Bool:
  Cl.target_wire(name)

def wire_find.on(allowed: Bool, cl: Cl.Client, name: String) -> Maybe<&2, Nat>:
  match allowed:
    case False{}: None{}
    case True{}: Cl.buf_find(cl, name)

def wire_find(+cl: Cl.Client, +name: String) -> Maybe<&2, Nat>:
  +canonical = Cl.target_name(name)
  wire_find.on(wire_name(canonical) && Bool.not(String.is_empty(canonical)), cl, canonical)

def wire_get.on(allowed: Bool, cl: Cl.Client, name: String, channel: Bool, create: Bool) -> Cl.Client & Maybe<&2, Nat>:
  match allowed:
    case False{}: (cl, None{})
    case True{}: Cl.buf_get(cl, name, channel, create)

def wire_get(+cl: Cl.Client, +name: String, channel: Bool, create: Bool) -> Cl.Client & Maybe<&2, Nat>:
  +canonical = Cl.target_name(name)
  wire_get.on(wire_name(canonical) && Bool.not(String.is_empty(canonical)), cl, canonical, channel, create)

def wire_find_with.on(allowed: Bool, cl: Cl.Client, +cm: String, name: String) -> Maybe<&2, Nat>:
  match allowed:
    case False{}: None{}
    case True{}: Cl.buf_find_cm(cl, cm, name)

def wire_find_with(+cl: Cl.Client, +cm: String, +name: String) -> Maybe<&2, Nat>:
  +canonical = Cl.target_name(name)
  wire_find_with.on(wire_name(canonical) && Bool.not(String.is_empty(canonical)), cl, cm, canonical)

def wire_get_with.on(allowed: Bool, cl: Cl.Client, +isc: Cl.Iso, name: String, channel: Bool, create: Bool) -> Cl.Client & Maybe<&2, Nat>:
  match allowed:
    case False{}: (cl, None{})
    case True{}: Cl.buf_get_with(cl, isc, name, channel, create)

def wire_get_with(+cl: Cl.Client, +isc: Cl.Iso, +name: String, channel: Bool, create: Bool) -> Cl.Client & Maybe<&2, Nat>:
  +canonical = Cl.target_name(name)
  wire_get_with.on(wire_name(canonical) && Bool.not(String.is_empty(canonical)), cl, isc, canonical, channel, create)

def feed_ping(+cl: Cl.Client) -> Cl.Client:
  cl

# Keepalive PONGs stay quiet like PINGs: every server PONG would
# otherwise log an unknown-command server row per keepalive. RTT is
# still measured by the fold lag arm off the raw line before feed.
def feed_pong(+cl: Cl.Client) -> Cl.Client:
  cl

def feed_priv.write.msg.kind(is_hl: Bool) -> Cl.LineKind:
  match is_hl:
    case True{}: Cl.Highlight{}
    case False{}: Cl.Msg{}

def feed_priv.write.msg.body(+cl: Cl.Client, +bi: Nat, +from: String, +body: String, +ts: String, is_hl: Bool) -> Cl.Client:
  Cl.client_log_author_ts(cl, bi, feed_priv.write.msg.kind(is_hl), ts, fmt_msg(from, body), from)

def feed_priv.write.msg(+cl: Cl.Client, +bi: Nat, +from: String, +body: String, +ts: String, act: Bool, is_hl: Bool) -> Cl.Client:
  match act:
    case True{}:
      Cl.client_log_author_ts(cl, bi, Cl.Action{}, ts, fmt_action(from, action_text(body)), from)
    case False{}:
      feed_priv.write.msg.body(cl, bi, from, body, ts, is_hl)

def feed_priv.write.body.bell(+cl: Cl.Client, is_hl: Bool) -> Cl.Client:
  match is_hl:
    case True{}: Cl.advance_client_bell(cl)
    case False{}: cl

def feed_priv.write.notice(+cl: Cl.Client, +bi: Nat, +from: String, +body: String, +ts: String) -> Cl.Client:
  +cl2 = Cl.client_log_author_ts(cl, bi, Cl.Notice{}, ts, fmt_msg(from, body), from)
  Cl.mark_unread_idx(cl2, bi, False{})

# Negotiated unread mark (I2-dynamic4 G2C): body/notice thread cm to the
# shared mark_unread_idx_cm owner; no copied write/msg/bell logic. Fixed
# body/notice keep law behavior; negotiated route/private call the _cm owner.
def feed_priv.write.body_cm(+cm: String, +cl: Cl.Client, +bi: Nat, +from: String, +body: String, +ts: String, act: Bool, +is_hl: Bool) -> Cl.Client:
  +cl2 = feed_priv.write.msg(cl, bi, from, body, ts, act, is_hl)
  feed_priv.write.body.bell(Cl.mark_unread_idx_cm(cm, cl2, bi, is_hl), is_hl)

def feed_priv.write.notice_cm(+cm: String, +cl: Cl.Client, +bi: Nat, +from: String, +body: String, +ts: String) -> Cl.Client:
  +cl2 = Cl.client_log_author_ts(cl, bi, Cl.Notice{}, ts, fmt_msg(from, body), from)
  Cl.mark_unread_idx_cm(cm, cl2, bi, False{})

# Negotiated channel write (I2-dynamic3 R3): the mention check folds under
# the Session CASEMAPPING through the shared is_mention_cm owner. Fixed
# route/write/write_got keep law behavior by delegating with the default
# mapping; the negotiated route calls the _with entries directly.
# I2-dynamic4 G2C: route also threads cm to the shared unread mark owner.
def feed_priv.write.route_with(+cm: String, notice: Bool, +cl: Cl.Client, +bi: Nat, +from: String, +body: String, +ts: String) -> Cl.Client:
  match notice:
    case True{}:
      feed_priv.write.notice_cm(cm, cl, bi, from, body, ts)
    case False{}:
      feed_priv.write.body_cm(cm, cl, bi, from, body, ts, is_action(body), Cl.is_mention_cm(cm, body, Cl.nick_of(cl)))

def feed_priv.write_with(+cm: String, +cl: Cl.Client, +bi: Nat, +from: String, notice: Bool, +body: String, +ts: String) -> Cl.Client:
  feed_priv.write.route_with(cm, notice, cl, bi, from, body, ts)

def feed_priv.drop_log.on(+cl: Cl.Client, on_server: Bool, +from: String) -> Cl.Client:
  match on_server:
    case True{}:
      cl
    case False{}:
      Cl.client_log(cl, Cl.active_of(cl), Cl.Error{}, "buffer limit reached — dropped message from " ++ from)

def feed_priv.drop_log(+cl: Cl.Client, +from: String) -> Cl.Client:
  feed_priv.drop_log.on(cl, Nat.is_eq(Cl.active_of(cl), 0n), from)

def feed_priv.write_got_with(+cm: String, pair: Cl.Client & Maybe<&2, Nat>, +from: String, notice: Bool, +body: String, +ts: String) -> Cl.Client:
  match pair:
    case (cl2, Some{+bi}):
      feed_priv.write_with(cm, cl2, bi, from, notice, body, ts)
    case (cl2, None{}):
      feed_priv.drop_log(cl2, from)

def feed_priv.key.on(+from: String, +target: String, self: Bool) -> String:
  match self:
    case True{}:
      target
    case False{}:
      from

def feed_priv.key_with(+cm: String, +cl: Cl.Client, +from: String, +target: String) -> String:
  match cl:
    case Cl.Client{+nick, _, _, _, _, _, +auth, +log_seq, _}:
      feed_priv.key.on(from, target, Cl.buf_eq_cm(cm, Irc.proto_atom(from), nick))

def feed_priv.private_got_with(+cm: String, pair: Cl.Client & Maybe<&2, Nat>, +from: String, notice: Bool, +body: String, +ts: String) -> Cl.Client:
  match pair:
    case (+cl2, Some{+bi}):
      match notice:
        case True{}:
          feed_priv.write.notice_cm(cm, cl2, bi, from, body, ts)
        case False{}:
          feed_priv.write.body_cm(cm, cl2, bi, from, body, ts, is_action(body), Bool.not(Cl.buf_eq_cm(cm, Irc.proto_atom(from), Cl.nick_of(cl2))))
    case (cl2, None{}):
      feed_priv.drop_log(cl2, from)

def feed_priv.to_server.on(empty: Bool, broadcast: Bool) -> Bool:
  match empty:
    case True{}:
      True{}
    case False{}:
      broadcast

def feed_priv.to_server_with(+cm: String, +cl: Cl.Client, +from: String, +target: String, notice: Bool) -> Bool:
  feed_priv.to_server.on(String.is_empty(from), notice && (Irc.ieq(target, "*")
    || (Irc.ieq(target, "AUTH") && Bool.not(Cl.buf_eq_cm(cm, target, Cl.nick_of(cl)) || Cl.buf_eq_cm(cm, Irc.proto_atom(from), Cl.nick_of(cl))))))

def feed_priv.nonchan_with(
  +cl: Cl.Client,
  +isc: Cl.Iso,
  +from: String,
  notice: Bool,
  +body: String,
  empty: Bool,
  +target: String,
  +ts: String
) -> Cl.Client:
  match empty:
    case True{}:
      feed_priv.write_with(Cl.iso_cm(isc), cl, 0n, from, notice, body, ts)
    case False{}:
      feed_priv.private_got_with(Cl.iso_cm(isc), wire_get_with(cl, isc, feed_priv.key_with(Cl.iso_cm(isc), cl, from, target), False{}, True{}), from, notice, body, ts)

def feed_priv.route_with.on(+cl: Cl.Client, +isc: Cl.Iso, +target: String, +from: String, +notice: Bool, +body: String, +ts: String, chan: Bool) -> Cl.Client:
  match chan:
    case True{}:
      feed_priv.write_got_with(Cl.iso_cm(isc), wire_get_with(cl, isc, target, True{}, False{}), from, notice, body, ts)
    case False{}:
      feed_priv.nonchan_with(cl, isc, from, notice, body, feed_priv.to_server_with(Cl.iso_cm(isc), cl, from, target, notice), target, ts)

def feed_priv.route_with.mute(muted: Bool, +cl: Cl.Client, +isc: Cl.Iso, +target: String, +from: String, notice: Bool, +body: String, +ts: String) -> Cl.Client:
  match muted:
    case True{}: cl
    case False{}:
      feed_priv.route_with.on(cl, isc, target, from, notice, body, ts, Cl.target_channel_with(Cl.iso_types(isc), Cl.iso_status(isc), Cl.iso_sigils(isc), target))

def feed_priv.route_with(+cl: Cl.Client, +isc: Cl.Iso, +target: String, +from: String, +notice: Bool, +body: String, +ts: String) -> Cl.Client:
  +tgt = Cl.message_key_with(cl, isc, target)
  feed_priv.route_with.mute(Cl.is_muted_client_cm(Cl.iso_cm(isc), cl, from, tgt) || Bool.not(wire_name(from))
    || (Bool.not(wire_name(tgt)) && Bool.not(notice && Irc.ieq(tgt, "*"))), cl, isc, tgt, from, notice, body, ts)

def feed_join.self(+cl: Cl.Client, +bi: Nat, self: Bool) -> Cl.Client:
  match self:
    case True{}:
      Cl.set_active(cl, bi)
    case False{}:
      cl

def join_upd.log(b: Cl.Buffer, +from: String, +chan: String, +now: String) -> Cl.Buffer:
  Cl.buf_log_ts(b, Cl.Presence{}, now, fmt_join(from, Cl.target_name(chan)))

def join_upd_with(+isc: Cl.Iso, +from: String, +chan: String, +now: String, b: Cl.Buffer) -> Cl.Buffer:
  join_upd.log(Cl.nick_add_cm(b, Cl.iso_cm(isc), Cl.iso_strip(isc), from), from, chan, now)

def feed_join_with.from_cl(+isc: Cl.Iso, +cl2: Cl.Client, +bi: Nat, +from: String, +chan: String, self: Bool) -> Cl.Client:
  match cl2:
    case Cl.Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq, welcomed}:
      feed_join.self(
        Cl.Client{nick, server, Cl.buf_modify(bufs, bi, join_upd_with(isc, from, chan, now)), active, now, stg, auth, log_seq, welcomed},
        bi,
        self
      )

def feed_join_with.from_pair(+isc: Cl.Iso, pair: Cl.Client & Maybe<&2, Nat>, +from: String, +chan: String, self: Bool) -> Cl.Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_join_with.from_cl(isc, cl2, bi, from, chan, self)

def feed_join_with.with.on(+cl: Cl.Client, +isc: Cl.Iso, +from: String, +chan: String, +self: Bool, empty: Bool) -> Cl.Client:
  match empty:
    case True{}:
      cl
    case False{}:
      feed_join_with.from_pair(isc, wire_get_with(cl, isc, chan, True{}, self), from, chan, self)

def feed_join_with.with(+cl: Cl.Client, +isc: Cl.Iso, +from: String, +chan: String, +self: Bool) -> Cl.Client:
  feed_join_with.with.on(cl, isc, from, chan, self, String.is_empty(chan))

def feed_join_with(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message, self: Bool) -> Cl.Client:
  feed_join_with.with(cl, isc, msg_nick(m), Irc.msg_param(m, 0n), self)

# Extended-join (IRCv3): the JOIN path accepts the classic 1-param form and
# the 3-param form (channel, account, realname); any other arity stays on
# the unknown-command path. Render is unchanged; no account is stored.
def join_arity.n(+n: Nat) -> Bool:
  Nat.is_eq(n, 1n) || Nat.is_eq(n, 3n)

def join_arity_ok(+m: Irc.Message) -> Bool:
  join_arity.n(List.length(&2, String, Irc.msg_params(m)))

def part_upd.log(b: Cl.Buffer, +from: String, +chan: String, +now: String) -> Cl.Buffer:
  Cl.buf_log_ts(b, Cl.Presence{}, now, fmt_part(from, Cl.target_name(chan)))

def part_upd_with.on(+isc: Cl.Iso, +from: String, +chan: String, +now: String, +b: Cl.Buffer, has: Bool) -> Cl.Buffer:
  match has:
    case False{}:
      b
    case True{}:
      part_upd.log(Cl.nick_del_cm(b, Cl.iso_cm(isc), Cl.iso_strip(isc), from), from, chan, now)

def part_upd_with(+isc: Cl.Iso, +from: String, +chan: String, +now: String, b: Cl.Buffer) -> Cl.Buffer:
  +bb = b
  part_upd_with.on(isc, from, chan, now, bb, Cl.nick_has_cm(bb, Cl.iso_cm(isc), from))

def feed_part_with.at(+isc: Cl.Iso, +nick: String, +server: String, +bufs: List<&2, Cl.Buffer>, +active: Nat, +now: String, +stg: Cl.Settings, +auth: Cl.AuthPhase, +log_seq: Nat, welcomed: Bool, +bi: Nat, +from: String, +chan: String) -> Cl.Client:
  Cl.Client{nick, server, Cl.buf_modify(bufs, bi, part_upd_with(isc, from, chan, now)), active, now, stg, auth, log_seq, welcomed}

def feed_part_with.on(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +from: String, found: Maybe<&2, Nat>) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq, welcomed}:
      match found:
        case None{}:
          Cl.Client{nick, server, bufs, active, now, stg, auth, log_seq, welcomed}
        case Some{bi}:
          feed_part_with.at(isc, nick, server, bufs, active, now, stg, auth, log_seq, welcomed, bi, from, chan)

def feed_part_with.pick(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +from: String, self: Bool, found: Maybe<&2, Nat>) -> Cl.Client:
  match self:
    case True{}:
      Cl.drop_buf.at(cl, found)
    case False{}:
      feed_part_with.on(cl, isc, chan, from, found)

def feed_part_with.with(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +from: String, self: Bool) -> Cl.Client:
  feed_part_with.pick(cl, isc, chan, from, self, wire_find_with(cl, Cl.iso_cm(isc), chan))

def feed_part_with(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message, self: Bool) -> Cl.Client:
  feed_part_with.with(cl, isc, Irc.msg_param(m, 0n), msg_nick(m), self)

def fmt_kick(+victim: String, +chan: String) -> String:
  "<- " ++ victim ++ " kicked from " ++ Cl.target_name(chan)

def feed_self_cm.empty(empty: Bool, +cm: String, +cl: Cl.Client, +from: String) -> Bool:
  match empty:
    case True{}:
      False{}
    case False{}:
      match cl:
        case Cl.Client{+nick, _, _, _, _, _, +auth, +log_seq, _}:
          Cl.buf_eq_cm(cm, Irc.proto_atom(from), nick)

def feed_self_cm(+cm: String, +cl: Cl.Client, +from: String) -> Bool:
  feed_self_cm.empty(String.is_empty(from), cm, cl, from)

def kick_upd_with(+isc: Cl.Iso, +victim: String, +chan: String, +now: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.buf_log_ts(Cl.nick_del_cm(b, Cl.iso_cm(isc), Cl.iso_strip(isc), victim), Cl.System{}, now, fmt_kick(victim, chan))

def feed_kick_with.at(+isc: Cl.Iso, +nick: String, +server: String, +bufs: List<&2, Cl.Buffer>, +active: Nat, +now: String, +stg: Cl.Settings, +auth: Cl.AuthPhase, +log_seq: Nat, welcomed: Bool, +bi: Nat, +victim: String, +chan: String) -> Cl.Client:
  Cl.Client{nick, server, Cl.buf_modify(bufs, bi, kick_upd_with(isc, victim, chan, now)), active, now, stg, auth, log_seq, welcomed}

def feed_kick_with.other(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +victim: String, found: Maybe<&2, Nat>) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq, welcomed}:
      match found:
        case None{}:
          Cl.Client{nick, server, bufs, active, now, stg, auth, log_seq, welcomed}
        case Some{bi}:
          feed_kick_with.at(isc, nick, server, bufs, active, now, stg, auth, log_seq, welcomed, bi, victim, chan)

def feed_kick_with.pick(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +victim: String, self: Bool, found: Maybe<&2, Nat>) -> Cl.Client:
  match self:
    case True{}:
      Cl.drop_buf.at(cl, found)
    case False{}:
      feed_kick_with.other(cl, isc, chan, victim, found)

def feed_kick_with.with(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +victim: String, self: Bool) -> Cl.Client:
  feed_kick_with.pick(cl, isc, chan, victim, self, wire_find_with(cl, Cl.iso_cm(isc), chan))

def feed_kick_with(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message) -> Cl.Client:
  feed_kick_with.with(cl, isc, Irc.msg_param(m, 0n), Irc.proto_atom(Irc.msg_param(m, 1n)), feed_self_cm(Cl.iso_cm(isc), cl, Irc.proto_atom(Irc.msg_param(m, 1n))))

def is_channel_buf(+b: Cl.Buffer) -> Bool:
  match b:
    case Cl.Buffer{_, +ch, _, _, _, _, _, _}:
      ch

def feed_quit.one.log(b: Cl.Buffer, +from: String, +reason: String, +ts: String) -> Cl.Buffer:
  Cl.buf_log_ts(b, Cl.Presence{}, ts, fmt_quit(from, reason))

def feed_quit.query.on(+h: Cl.Buffer, +from: String, +reason: String, +ts: String, hit: Bool) -> Cl.Buffer:
  match hit:
    case True{}:
      Cl.buf_log_ts(h, Cl.Presence{}, ts, fmt_quit(from, reason))
    case False{}:
      h

def feed_quit_with.one.on(+isc: Cl.Iso, +b: Cl.Buffer, +from: String, +reason: String, +ts: String, has: Bool) -> Cl.Buffer:
  match has:
    case True{}:
      feed_quit.one.log(Cl.nick_del_cm(b, Cl.iso_cm(isc), Cl.iso_strip(isc), from), from, reason, ts)
    case False{}:
      b

def feed_quit_with.one(+isc: Cl.Iso, +b: Cl.Buffer, +from: String, +reason: String, +ts: String) -> Cl.Buffer:
  feed_quit_with.one.on(isc, b, from, reason, ts, Cl.nick_has_cm(b, Cl.iso_cm(isc), from))

def feed_quit_with.query(+cm: String, +h: Cl.Buffer, +from: String, +reason: String, +ts: String) -> Cl.Buffer:
  match h:
    case Cl.Buffer{+name, +ch, +topic, +lines, +nicks, +scroll, _, _}:
      feed_quit.query.on(
        Cl.buf_indexed(name, ch, topic, lines, nicks, scroll),
        from,
        reason,
        ts,
        Cl.buf_eq_cm(cm, name, from) && Cl.is_query_name(name)
      )

def feed_quit_with.apply.on(+isc: Cl.Iso, +h: Cl.Buffer, +from: String, +reason: String, +ts: String, ch: Bool) -> Cl.Buffer:
  match ch:
    case True{}:
      feed_quit_with.one(isc, h, from, reason, ts)
    case False{}:
      feed_quit_with.query(Cl.iso_cm(isc), h, from, reason, ts)

def feed_quit_with.apply(+isc: Cl.Iso, +h: Cl.Buffer, +from: String, +reason: String, +ts: String) -> Cl.Buffer:
  feed_quit_with.apply.on(isc, h, from, reason, ts, is_channel_buf(h))

def feed_quit_with.map.go(+isc: Cl.Iso, xs: List<&2, Cl.Buffer>, +from: String, +reason: String, +ts: String) -> List<&2, Cl.Buffer>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      feed_quit_with.apply(isc, h, from, reason, ts) <> feed_quit_with.map.go(isc, t, from, reason, ts)

def feed_quit_with.map(+isc: Cl.Iso, xs: List<&2, Cl.Buffer>, from: String, reason: String, ts: String) -> List<&2, Cl.Buffer>:
  match xs:
    case Nil{}: Nil{}
    case Con{server, t}: server <> feed_quit_with.map.go(isc, t, from, reason, ts)

def feed_quit_with.with(+cl: Cl.Client, +isc: Cl.Iso, +from: String, +reason: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq, welcomed}:
      Cl.Client{nick, server, feed_quit_with.map(isc, bufs, from, reason, now), active, now, stg, auth, log_seq, welcomed}

def feed_quit_with(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message) -> Cl.Client:
  feed_quit_with.with(cl, isc, msg_nick(m), Irc.msg_param(m, 0n))

# NICK rename has one parameterized owner, feed_nick_with below (I2-dynamic3
# R5): roster, query, focus, unreads, and coalescing compare under the given
# CASEMAPPING with the given PREFIX strip set. fin/focused stay shared and
# mapping-free; the fixed feed_nick entries delegate with the defaults.
def feed_nick.fin(+cl: Cl.Client, +to: String, self: Bool) -> Cl.Client:
  match self:
    case True{}:
      Cl.set_nick(cl, to)
    case False{}:
      cl

def feed_nick.focused(index: Maybe<&2, Nat>, +cl: Cl.Client, +to: String, self: Bool) -> Cl.Client:
  match index:
    case None{}: feed_nick.fin(Cl.set_active(cl, 0n), to, self)
    case Some{i}: feed_nick.fin(Cl.set_active(cl, i), to, self)

# Negotiated NICK rename (I2-dynamic2 F3, sole owner since I2-dynamic3 R5):
# roster, query, focus, unreads, and query coalescing all compare under the
# given CASEMAPPING with the given PREFIX strip set.
def feed_nick_with.one.on(+isc: Cl.Iso, +b: Cl.Buffer, +from: String, +to: String, +ts: String, has: Bool) -> Cl.Buffer:
  match has:
    case True{}:
      Cl.buf_log_ts(Cl.nick_rename_cm(b, Cl.iso_cm(isc), Cl.iso_strip(isc), from, to), Cl.Nick{}, ts, fmt_nick_chg(from, to))
    case False{}:
      b

def feed_nick_with.one(+isc: Cl.Iso, +b: Cl.Buffer, +from: String, +to: String, +ts: String) -> Cl.Buffer:
  feed_nick_with.one.on(isc, b, from, to, ts, Cl.nick_has_cm(b, Cl.iso_cm(isc), from))

def feed_nick_with.query.on(+isc: Cl.Iso, +h: Cl.Buffer, +from: String, +to: String, +ts: String, hit: Bool) -> Cl.Buffer:
  match hit:
    case True{}:
      Cl.buf_log_ts(Cl.nick_rename_cm(Cl.set_buf_name(h, to), Cl.iso_cm(isc), Cl.iso_strip(isc), from, to), Cl.Nick{}, ts, fmt_nick_chg(from, to))
    case False{}:
      h

def feed_nick_with.query(+isc: Cl.Iso, +h: Cl.Buffer, +from: String, +to: String, +ts: String) -> Cl.Buffer:
  match h:
    case Cl.Buffer{+name, +ch, +topic, +lines, +nicks, +scroll, _, _}:
      feed_nick_with.query.on(isc, Cl.buf_indexed(name, ch, topic, lines, nicks, scroll), from, to, ts, Cl.buf_eq_cm(Cl.iso_cm(isc), name, from) && Cl.is_query_name(name))

def feed_nick_with.apply.on(+isc: Cl.Iso, +h: Cl.Buffer, +from: String, +to: String, +ts: String, ch: Bool) -> Cl.Buffer:
  match ch:
    case True{}:
      feed_nick_with.one(isc, h, from, to, ts)
    case False{}:
      feed_nick_with.query(isc, h, from, to, ts)

def feed_nick_with.apply(+isc: Cl.Iso, +h: Cl.Buffer, +from: String, +to: String, +ts: String) -> Cl.Buffer:
  feed_nick_with.apply.on(isc, h, from, to, ts, is_channel_buf(h))

def feed_nick_with.map.go(+isc: Cl.Iso, xs: List<&2, Cl.Buffer>, +from: String, +to: String, +ts: String) -> List<&2, Cl.Buffer>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      feed_nick_with.apply(isc, h, from, to, ts) <> feed_nick_with.map.go(isc, t, from, to, ts)

def feed_nick_with.map(+isc: Cl.Iso, xs: List<&2, Cl.Buffer>, from: String, to: String, ts: String) -> List<&2, Cl.Buffer>:
  match xs:
    case Nil{}: Nil{}
    case Con{server, t}: server <> feed_nick_with.map.go(isc, t, from, to, ts)

def feed_nick_with.focus_control(+cm: String, control: Bool, +cl: Cl.Client, name: String, +to: String, self: Bool) -> Cl.Client:
  match control:
    case True{}: feed_nick.fin(Cl.set_active(cl, 0n), to, self)
    case False{}: feed_nick.focused(Cl.buf_find_cm(cl, cm, name), cl, to, self)

def feed_nick_with.coalesced(+cm: String, +cl: Cl.Client, +from: String, +to: String, +focus: String, self: Bool, control: Bool) -> Cl.Client:
  +stg = Cl.get_settings(cl)
  +stg2 = Cl.set_unreads(stg, Cl.rename_unreads_cm(cm, Cl.settings_unreads(stg), from, to))
  +merged = Cl.coalesce_queries_cm(cm, Cl.set_settings(cl, stg2), to)
  +name = Bool.pick(String, Cl.buf_eq_cm(cm, focus, from) && Cl.is_query_name(focus), to, focus)
  feed_nick_with.focus_control(cm, control, merged, name, to, self)

def feed_nick_with.with.valid(+isc: Cl.Iso, +cl: Cl.Client, +from: String, +to: String, self: Bool) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq, welcomed}:
      feed_nick_with.coalesced(Cl.iso_cm(isc), Cl.stamp_logs(Cl.Client{nick, server, feed_nick_with.map(isc, bufs, from, to, now), active, now, stg, auth, log_seq, welcomed}), from, to, Cl.active_buf_name(cl), self, Nat.is_eq(active, 0n))

def feed_nick_with.with.on(+isc: Cl.Iso, allowed: Bool, cl: Cl.Client, from: String, to: String, self: Bool) -> Cl.Client:
  match allowed:
    case False{}: cl
    case True{}: feed_nick_with.with.valid(isc, cl, from, to, self)

def feed_nick_with.with(+isc: Cl.Iso, +cl: Cl.Client, +from: String, +to: String, self: Bool) -> Cl.Client:
  feed_nick_with.with.on(isc, Cl.nick_rename_allowed(from, to), cl, Cl.target_name(from), Cl.target_name(to), self)

def feed_nick_with(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message, self: Bool) -> Cl.Client:
  feed_nick_with.with(isc, cl, msg_nick(m), Irc.msg_param(m, 0n), self)

def topic_upd(+from: String, +topic: String, +now: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.buf_log_ts(Cl.set_topic(b, Irc.sanitize_in(topic)), Cl.System{}, now, fmt_topic_set(from, topic))

def feed_topic.from_cl(+cl2: Cl.Client, +bi: Nat, +from: String, +topic: String) -> Cl.Client:
  match cl2:
    case Cl.Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq, welcomed}:
      Cl.Client{nick, server, Cl.buf_modify(bufs, bi, topic_upd(from, topic, now)), active, now, stg, auth, log_seq, welcomed}

def feed_topic.from_pair(pair: Cl.Client & Maybe<&2, Nat>, +from: String, +topic: String) -> Cl.Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_topic.from_cl(cl2, bi, from, topic)

def feed_topic.with(+cl: Cl.Client, +chan: String, +topic: String, +from: String) -> Cl.Client:
  feed_topic.from_pair(wire_get(cl, chan, True{}, False{}), from, topic)

def feed_topic.with_iso(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +topic: String, +from: String) -> Cl.Client:
  feed_topic.from_pair(wire_get_with(cl, isc, chan, True{}, False{}), from, topic)

def feed_topic(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  feed_topic.with(cl, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), msg_nick(m))

def feed_topic_with(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message) -> Cl.Client:
  feed_topic.with_iso(cl, isc, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), msg_nick(m))

# ---- names / numeric ----------------------------------------------------

def split_names.keep(s: String) -> Bool:
  Bool.not(String.is_empty(s))

def split_names(+s: String) -> List<&2, String>:
  List.filter(~String, ~split_names.keep, String.split(s, Chr{32}))

def topic_set(+topic: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.set_topic(b, Irc.sanitize_in(topic))

def feed_num.topic.cl(+cl2: Cl.Client, +bi: Nat, +topic: String) -> Cl.Client:
  match cl2:
    case Cl.Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq, welcomed}:
      Cl.Client{nick, server, Cl.buf_modify(bufs, bi, topic_set(topic)), active, now, stg, auth, log_seq, welcomed}

def feed_num.topic.pair(pair: Cl.Client & Maybe<&2, Nat>, +topic: String) -> Cl.Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_num.topic.cl(cl2, bi, topic)

def feed_num.topic(+cl: Cl.Client, +chan: String, +topic: String) -> Cl.Client:
  feed_num.topic.pair(wire_get(cl, chan, True{}, False{}), topic)

def feed_num.topic_with(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +topic: String) -> Cl.Client:
  feed_num.topic.pair(wire_get_with(cl, isc, chan, True{}, False{}), topic)

def names_upd_with(+isc: Cl.Iso, +names: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.nick_add_all_cm(b, Cl.iso_cm(isc), Cl.iso_strip(isc), split_names(Irc.sanitize_in(names)))

def feed_num.names_with.cl(+isc: Cl.Iso, +cl2: Cl.Client, +bi: Nat, +names: String) -> Cl.Client:
  match cl2:
    case Cl.Client{+nick, +server, +bufs, +active, +now, +stg, +auth, +log_seq, welcomed}:
      Cl.Client{nick, server, Cl.buf_modify(bufs, bi, names_upd_with(isc, names)), active, now, stg, auth, log_seq, welcomed}

def feed_num.names_with.pair(+isc: Cl.Iso, pair: Cl.Client & Maybe<&2, Nat>, +names: String) -> Cl.Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_num.names_with.cl(isc, cl2, bi, names)

def feed_num.names_with(+cl: Cl.Client, +isc: Cl.Iso, +chan: String, +names: String) -> Cl.Client:
  feed_num.names_with.pair(isc, wire_get_with(cl, isc, chan, True{}, False{}), names)

def feed_num.n353_with.body(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message, rfc2812: Bool) -> Cl.Client:
  match rfc2812:
    case True{}:
      feed_num.names_with(cl, isc, Irc.msg_param(m, 2n), Irc.msg_param(m, 3n))
    case False{}:
      feed_num.names_with(cl, isc, Irc.msg_param(m, 1n), Irc.msg_param(m, 2n))

def is_motd_num(+num: U32) -> Bool:
  U32.is_eq(num, 372) || U32.is_eq(num, 375) || U32.is_eq(num, 376)

def feed_num.other.log(cl: Cl.Client, +num: U32, +text: String, err: Bool) -> Cl.Client:
  match err:
    case True{}:
      Cl.client_log(cl, 0n, Cl.Error{}, fmt_num(num, text))
    case False{}:
      Cl.client_log(cl, 0n, Cl.System{}, fmt_num(num, text))

def feed_num.other.skip(cl: Cl.Client, +num: U32, +text: String, err: Bool, skip: Bool) -> Cl.Client:
  match skip:
    case True{}:
      cl
    case False{}:
      feed_num.other.log(cl, num, text, err)

def feed_num.other(+cl: Cl.Client, +num: U32, +text: String, err: Bool) -> Cl.Client:
  feed_num.other.skip(cl, num, text, err, is_motd_num(num) && Bool.not(Cl.settings_motd(Cl.get_settings(cl))))

def feed_num.n433.on(+cl: Cl.Client, +m: Irc.Message, +num: U32, +nick: String, retry: Bool) -> Cl.Client:
  match retry:
    case True{}:
      feed_num.other(Cl.set_nick(cl, nick ++ "_"), num, Irc.msg_last(m), True{})
    case False{}:
      feed_num.other(cl, num, Irc.msg_last(m), True{})

def feed_num.n433.cl(+cl: Cl.Client, +m: Irc.Message, +num: U32) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, _, _, _, _, _, +auth, +log_seq, _}:
      feed_num.n433.on(cl, m, num, nick, Irc.nick433_retry(m, nick))

def is_353_sym(+s: String) -> Bool:
  String.eq(s, "=") || String.eq(s, "*") || String.eq(s, "@")

type NumK is Data:
  N001{}
  N332{}
  N353{}
  N366{}
  N433{}
  NOther{}

type NumRow is Data:
  NumRow{code: U32, k: NumK}

def num_rows() -> List<&2, NumRow>:
  NumRow{1, N001{}} <> NumRow{332, N332{}} <> NumRow{353, N353{}} <> NumRow{366, N366{}} <> NumRow{433, N433{}} <> NumRow{437, N433{}} <> Nil{}

def num_kind(xs: List<&2, NumRow>, +n: U32) -> NumK:
  match xs:
    case Nil{}:
      NOther{}
    case Con{row, t}:
      match row:
        case NumRow{+code, +k}:
          Bool.pick(NumK, U32.is_eq(code, n), k, num_kind(t, n))

def feed_hidden() -> String:
  "[channel key hidden]"

# The hidden marker contains spaces, so a redacted wire splits it across
# params; rejoin to detect Session's precise redaction.
def has_hidden(+m: Irc.Message) -> Bool:
  String.contains(String.join(Irc.msg_params(m), " "), feed_hidden())

def feed_324_precise(+m: Irc.Message) -> String:
  Irc.msg_param(m, 1n) ++ " " ++ Irc.msg_param(m, 2n) ++ " " ++ String.join(List.drop(&2, String, Irc.msg_params(m), 3n), " ")

def feed_num.key_mode.redacted(+cl: Cl.Client, +m: Irc.Message, redacted: Bool) -> Cl.Client:
  match redacted:
    case True{}: feed_num.other(cl, 324, feed_324_precise(m), False{})
    case False{}: feed_num.other(cl, 324, Irc.msg_param(m, 1n) ++ " " ++ Irc.msg_param(m, 2n) ++ " [channel key hidden]", False{})

def feed_num.key_mode.reply(+cl: Cl.Client, +m: Irc.Message, key: Bool) -> Cl.Client:
  match key:
    case False{}: feed_num.other(cl, 324, Irc.msg_last(m), False{})
    case True{}: feed_num.key_mode.redacted(cl, m, has_hidden(m))

def feed_num.other_reply(+cl: Cl.Client, +m: Irc.Message, +num: U32) -> Cl.Client:
  match num:
    case 324:
      feed_num.key_mode.reply(cl, m, Commands.mode_has_key(Irc.Message{"", "", "MODE", 0,
        List.drop(&2, String, Irc.msg_params(m), 1n)}))
    case _: feed_num.other(cl, num, Irc.msg_last(m), U32.is_ge(num, 400))

# Pure 001 shape gate shared with Session.registration_client_iso. Session
# still owns the seen/CASEMAPPING barrier; Feed refuses peer/short/malformed
# welcomes when called directly (replay/demo/fold).
def welcome_nick(+nick: String) -> Bool:
  Commands.word(nick) && Bool.not(Irc.starts_channel(nick)
    || String.contains(nick, "*") || String.contains(nick, ",")
    || String.contains(nick, "!") || String.contains(nick, "@")
    || String.contains(nick, ":"))

def welcome_admit(+prefix: String, +m: Irc.Message) -> Bool:
  CapNotify.server_source(prefix)
    && Nat.is_eq(List.length(&2, String, Irc.msg_params(m)), 2n)
    && welcome_nick(Irc.proto_atom(Irc.msg_param(m, 0n)))
    && Bool.not(String.is_empty(Irc.msg_param(m, 1n)))

# Adopt the assigned nick only on the first admitted 001, or when a later
# admitted 001 repeats the current nick (Irc.ieq). Conflicting welcomes still
# log but leave Client.nick unchanged. Client.welcomed mirrors Session's seen
# gate so nested feed(feed(...)) and feed_all share one barrier.
def feed_n001.take(allow: Bool, +cl: Cl.Client, +nick: String) -> Cl.Client:
  match allow:
    case False{}: cl
    case True{}: Cl.set_welcomed(Cl.set_nick(cl, nick), True{})

def feed_n001.adopt(admitted: Bool, seen: Bool, same: Bool, +cl: Cl.Client, +nick: String) -> Cl.Client:
  match admitted:
    case False{}: cl
    case True{}: feed_n001.take(Bool.or(Bool.not(seen), same), cl, nick)

def feed_n001(+cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Cl.Client:
  # W3: identity adoption normalizes via the shared proto_atom seam;
  # the logged welcome body keeps its raw bytes even when nick is refused.
  +nick = Irc.proto_atom(Irc.msg_param(m, 0n))
  Cl.client_log(feed_n001.adopt(welcome_admit(prefix, m), Cl.welcomed_of(cl), Irc.ieq(Cl.nick_of(cl), nick), cl, nick), 0n, Cl.System{}, Irc.msg_param(m, 1n))

def feed_num_with.by(+cl: Cl.Client, +isc: Cl.Iso, +prefix: String, +m: Irc.Message, +num: U32, k: NumK) -> Cl.Client:
  match k:
    case N001{}:
      feed_n001(cl, prefix, m)
    case N332{}:
      feed_num.topic_with(cl, isc, Irc.msg_param(m, 1n), Irc.msg_param(m, 2n))
    case N353{}:
      feed_num.n353_with.body(cl, isc, m, is_353_sym(Irc.msg_param(m, 1n)))
    case N366{}:
      cl
    case N433{}:
      feed_num.n433.cl(cl, m, num)
    case NOther{}:
      feed_num.other_reply(cl, m, num)

def feed_numeric_with(+cl: Cl.Client, +isc: Cl.Iso, +prefix: String, +m: Irc.Message) -> Cl.Client:
  match m:
    case Irc.Message{_, _, _, +num, _}:
      feed_num_with.by(cl, isc, prefix, m, num, num_kind(num_rows(), num))

def feed_mode.got(+cl: Cl.Client, +from: String, +ps: List<&2, String>, found: Maybe<&2, Nat>) -> Cl.Client:
  match found:
    case None{}:
      cl
    case Some{+bi}:
      Cl.client_log(cl, bi, Cl.System{}, fmt_mode(from, ps))

def first_param(+ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{+h, _}:
      h

# Session supplies precise redaction via the negotiated CHANMODES map before
# the feed runs (session_redact_wire). When the wire already carries the
# hidden marker, preserve its precise tail (limit 50 survives, key stays
# hidden); otherwise collapse key-bearing args (fail closed, never guess).
def feed_mode.collapsed(+m: Irc.Message, redacted: Bool) -> List<&2, String>:
  match redacted:
    case True{}: Irc.msg_params(m)
    case False{}: [Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), "[channel key hidden]"]

def feed_mode.params(key: Bool, +m: Irc.Message) -> List<&2, String>:
  match key:
    case False{}: Irc.msg_params(m)
    case True{}: feed_mode.collapsed(m, has_hidden(m))

def feed_mode(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  match m:
    case Irc.Message{_, +nick, _, _, +ps}:
      feed_mode.got(cl, nick, feed_mode.params(Commands.mode_has_key(m), m), wire_find(cl, first_param(ps)))

def feed_mode_with(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message) -> Cl.Client:
  match m:
    case Irc.Message{_, +nick, _, _, +ps}:
      feed_mode.got(cl, nick, feed_mode.params(Commands.mode_has_key(m), m), wire_find_with(cl, Cl.iso_cm(isc), first_param(ps)))

def feed_unk(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  match m:
    case Irc.Message{_, _, +cmd, _, _}:
      Cl.client_log(cl, 0n, Cl.System{}, fmt_unk(cmd, Irc.msg_param(m, 0n)))

def feed_join_with.gated.on(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message, self: Bool, ok: Bool) -> Cl.Client:
  match ok:
    case True{}:
      feed_join_with(cl, isc, m, self)
    case False{}:
      feed_unk(cl, m)

def feed_join_with.gated(+cl: Cl.Client, +isc: Cl.Iso, +m: Irc.Message, self: Bool) -> Cl.Client:
  feed_join_with.gated.on(cl, isc, m, self, join_arity_ok(m))

# Labeled-response ACK: a bare or labeled server acknowledgement renders one
# server-log info line so the user can correlate it visually with the labeled
# request. Overlong ACK arities stay on the unknown-command path. The label
# arrives from the wire tags (Message carries no tags); both dispatchers
# thread it from raw_tags at the feed entry.
def ack_text.labeled(+label: String) -> String:
  "acknowledged " ++ label

def ack_text(label: Maybe<&2, String>) -> String:
  match label:
    case None{}:
      "acknowledged"
    case Some{+l}:
      ack_text.labeled(l)

def ack_ok(+m: Irc.Message) -> Bool:
  Nat.is_le(List.length(&2, String, Irc.msg_params(m)), 1n)

def feed_ack.render(+cl: Cl.Client, +m: Irc.Message, label: Maybe<&2, String>, ok: Bool) -> Cl.Client:
  match ok:
    case True{}:
      Cl.client_log(cl, 0n, Cl.System{}, ack_text(label))
    case False{}:
      feed_unk(cl, m)

def feed_ack(+cl: Cl.Client, +m: Irc.Message, label: Maybe<&2, String>) -> Cl.Client:
  feed_ack.render(cl, m, label, ack_ok(m))

# IRCv3 standard replies: FAIL/WARN/NOTE render on the server log; anything
# malformed or peer-forged falls through to the unknown-command path.
def feed_stdreply.text(+m: Irc.Message, +label: Maybe<&2, String>, +verb: String) -> String:
  Irc.stdreply_text_verb(verb, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), Irc.stdreply_context(m), Irc.msg_last(m), label)

def feed_stdreply.gated(+cl: Cl.Client, +m: Irc.Message, +label: Maybe<&2, String>, +verb: String, kind: Cl.LineKind, ok: Bool) -> Cl.Client:
  match ok:
    case True{}:
      Cl.client_log(cl, 0n, kind, feed_stdreply.text(m, label, verb))
    case False{}:
      feed_unk(cl, m)

def feed_stdreply(+cl: Cl.Client, +prefix: String, +label: Maybe<&2, String>, +verb: String, kind: Cl.LineKind, +m: Irc.Message) -> Cl.Client:
  feed_stdreply.gated(cl, m, label, verb, kind, CapNotify.server_source(prefix) && Irc.stdreply_ok(m))

def feed_stdreply_with(+cl: Cl.Client, +isc: Cl.Iso, +prefix: String, +label: Maybe<&2, String>, +verb: String, kind: Cl.LineKind, +m: Irc.Message) -> Cl.Client:
  feed_stdreply(cl, prefix, label, verb, kind, m)

def feed_notify.event(+cl: Cl.Client, e: CapNotify.NotifyEvent) -> Cl.Client:
  match e:
    case CapNotify.NotifyOther{}: cl
    case CapNotify.AccountOn{+nick, +account}: Cl.client_log(cl, 0n, Cl.System{}, CapNotify.account_on_text(nick, account))
    case CapNotify.AccountOff{+nick}: Cl.client_log(cl, 0n, Cl.System{}, CapNotify.account_off_text(nick))
    case CapNotify.AwayOn{+nick, +message}: Cl.client_log(cl, 0n, Cl.System{}, CapNotify.away_on_text(nick, message))
    case CapNotify.AwayOff{+nick}: Cl.client_log(cl, 0n, Cl.System{}, CapNotify.away_off_text(nick))

def feed_notify(+cl: Cl.Client, +prefix: String, +m: Irc.Message) -> Cl.Client:
  feed_notify.event(cl, CapNotify.notify_event(Cl.server_of(cl), prefix, m))

def feed_msg_with.cmd(+cl: Cl.Client, +isc: Cl.Iso, +prefix: String, +m: Irc.Message, +from: String, self: Bool, c: Irc.Cmd, label: Maybe<&2, String>) -> Cl.Client:
  match c:
    case Irc.Ping{}:
      feed_ping(cl)
    case Irc.Pong{}:
      feed_pong(cl)
    case Irc.Privmsg{}:
      feed_priv.route_with(cl, isc, Irc.msg_param(m, 0n), from, False{}, Irc.msg_param(m, 1n), Irc.msg_time(m))
    case Irc.Notice{}:
      feed_priv.route_with(cl, isc, Irc.msg_param(m, 0n), from, True{}, Irc.msg_param(m, 1n), Irc.msg_time(m))
    case Irc.Join{}:
      feed_join_with.gated(cl, isc, m, self)
    case Irc.Part{}:
      feed_part_with(cl, isc, m, self)
    case Irc.Kick{}:
      feed_kick_with(cl, isc, m)
    case Irc.Quit{}:
      feed_quit_with(cl, isc, m)
    case Irc.Nick{}:
      feed_nick_with(cl, isc, m, self)
    case Irc.Topic{}:
      feed_topic_with(cl, isc, m)
    case Irc.Mode{}:
      feed_mode_with(cl, isc, m)
    case Irc.Numeric{_}:
      feed_numeric_with(cl, isc, prefix, m)
    case Irc.Cap{}:
      cl
    case Irc.Tagmsg{}:
      cl
    case Irc.Ack{}:
      feed_ack(cl, m, label)
    case Irc.Error{}:
      Cl.client_log(cl, 0n, Cl.Error{}, fmt_err(Irc.msg_param(m, 0n)))
    case Irc.StdFail{}:
      feed_stdreply_with(cl, isc, prefix, label, "FAIL", Cl.Error{}, m)
    case Irc.StdWarn{}:
      feed_stdreply_with(cl, isc, prefix, label, "WARN", Cl.System{}, m)
    case Irc.StdNote{}:
      feed_stdreply_with(cl, isc, prefix, label, "NOTE", Cl.System{}, m)
    case _:
      feed_unk(cl, m)

def feed_msg_with.notify(+cl: Cl.Client, +isc: Cl.Iso, +prefix: String, +m: Irc.Message, +from: String, notify: Bool, label: Maybe<&2, String>) -> Cl.Client:
  match notify:
    case True{}: feed_notify(cl, prefix, m)
    case False{}: feed_msg_with.cmd(cl, isc, prefix, m, from, feed_self_cm(Cl.iso_cm(isc), cl, from), Irc.classify(m), label)

def feed_msg_with.with(+cl: Cl.Client, +isc: Cl.Iso, +prefix: String, +m: Irc.Message, +from: String, label: Maybe<&2, String>) -> Cl.Client:
  feed_msg_with.notify(cl, isc, prefix, m, from, CapNotify.is_notify(Cl.server_of(cl), prefix, m), label)

def feed_msg_with(+cl: Cl.Client, +isc: Cl.Iso, +prefix: String, +m: Irc.Message, label: Maybe<&2, String>) -> Cl.Client:
  feed_msg_with.with(cl, isc, prefix, m, msg_nick(m), label)

def feed_with.server_notice.on(server_notice: Bool, +cl: Cl.Client, +isc: Cl.Iso, +prefix: String, +m: Irc.Message, label: Maybe<&2, String>) -> Cl.Client:
  match server_notice:
    case False{}: feed_msg_with(cl, isc, prefix, m, label)
    case True{}:
      feed_priv.write.notice(cl, 0n, msg_nick(m), Irc.msg_param(m, 1n), Irc.msg_time(m))

def feed_with.server_notice(+cl: Cl.Client, +isc: Cl.Iso, +prefix: String, m: Maybe<&2, Irc.Message>, label: Maybe<&2, String>) -> Cl.Client:
  match m:
    case None{}: cl
    case Some{+msg}:
      +from = msg_nick(msg)
      +target = Cl.message_key_with(cl, isc, Irc.msg_param(msg, 0n))
      feed_with.server_notice.on(Irc.ieq(Irc.msg_command(msg), "NOTICE")
        && Cl.buf_eq_cm(Cl.iso_cm(isc), target, Cl.nick_of(cl)) && Irc.source_is_server(prefix, Cl.server_of(cl))
        && wire_name(from) && Bool.not(Cl.is_muted_client_cm(Cl.iso_cm(isc), cl, from, target)), cl, isc, prefix, msg, label)

def feed_with(+cl: Cl.Client, +isc: Cl.Iso, +line: String) -> Cl.Client:
  Cl.stamp_logs(feed_with.server_notice(cl, isc, Irc.source_prefix(line), Irc.parse(line), Irc.label_tag(Irc.raw_tags(line))))

def feed(+cl: Cl.Client, +line: String) -> Cl.Client:
  feed_with(cl, Cl.Iso.defaults(), line)

# Live IO resolves UTC server-time into local time without changing the wire
# line used by authentication, typing, and connection recovery. None leaves
# the pure parser unchanged; Some{""} uses the receipt-time fallback.
def feed_at.message(m: Maybe<&2, Irc.Message>, +stamp: String) -> Maybe<&2, Irc.Message>:
  match m:
    case None{}: None{}
    case Some{msg}:
      match msg:
        case Irc.Message{_, nick, command, numeric, params}:
          Some{Irc.Message{stamp, nick, command, numeric, params}}

def feed_at_with.stamped(+cl: Cl.Client, +isc: Cl.Iso, +line: String, +stamp: String) -> Cl.Client:
  match cl:
    case Cl.Client{_, _, _, _, +now, _, _, _, _}:
      +use = Cl.stamp_combine(now, stamp)
      Cl.set_now(Cl.stamp_logs(feed_with.server_notice(Cl.set_now(cl, use), isc, Irc.source_prefix(line), feed_at.message(Irc.parse(line), use), Irc.label_tag(Irc.raw_tags(line)))), now)

def feed_at_with(+cl: Cl.Client, +isc: Cl.Iso, +line: String, stamp: Maybe<&2, String>) -> Cl.Client:
  match stamp:
    case None{}: feed_with(cl, isc, line)
    case Some{value}: feed_at_with.stamped(cl, isc, line, value)

def feed_at(+cl: Cl.Client, +line: String, stamp: Maybe<&2, String>) -> Cl.Client:
  feed_at_with(cl, Cl.Iso.defaults(), line, stamp)

# ---- demo / show --------------------------------------------------------

def demo_lines_for(+nick: String) -> List<&2, String>:
  (":irc.birc.dev 001 " ++ nick ++ " :Welcome to the birc IRC Network " ++ nick)
    <> (":" ++ nick ++ "!me@localhost JOIN #birc")
    <> (":irc.birc.dev 353 " ++ nick ++ " = #birc :" ++ nick ++ " @alice bob carol")
    <> (":irc.birc.dev 366 " ++ nick ++ " #birc :End of /NAMES list.")
    <> (":irc.birc.dev 332 " ++ nick ++ " #birc :birc — Bend 2 + timui.h IRC")
    <> ":alice!a@host PRIVMSG #birc :hi everyone"
    <> ":bob!b@host PRIVMSG #birc :morning — *bold* _em_ and `code`"
    <> ":carol!c@host PRIVMSG #birc :see https://timui.dev docs"
    <> Nil{}

def demo_lines() -> List<&2, String>:
  demo_lines_for("me")

def feed_step(cl: Cl.Client, line: String) -> Cl.Client:
  feed(cl, line)

def feed_all(+cl: Cl.Client, +xs: List<&2, String>) -> Cl.Client:
  List.foldl(~&2, ~String, ~Cl.Client, ~feed_step, xs, cl)

# ---- scrollback search & fuzzy grep (M16.3) -----------------------------

type SearchTree is Data:
  STLeaf{}
  STOne{buf_name: String, line: Cl.Line}
  STNode{left: SearchTree, right: SearchTree}

type FuzzyStep is Data:
  FuzzyScan{hay: String, needle: String}
  FuzzyDecide{hay: String, needle_head: Char, needle_tail: String, equal: Bool}

# Fuel selects between Scan and Decide because Bend cannot match the computed
# character equality in Scan. Each character uses at most two decreasing calls.
def fuzzy_contains.go(fuel: Nat, step: FuzzyStep) -> Bool:
  match fuel:
    case 0n:
      False{}
    case 1n+p:
      match step:
        case FuzzyScan{hay, needle}:
          match hay:
            case SNil{}:
              match needle:
                case SNil{}:
                  True{}
                case SCon{_, _}:
                  False{}
            case SCon{hh, ht}:
              match needle:
                case SNil{}:
                  True{}
                case SCon{+nh, nt}:
                  fuzzy_contains.go(p, FuzzyDecide{ht, nh, nt, Char.is_eq(hh, nh)})
        case FuzzyDecide{hay, needle_head, needle_tail, equal}:
          match equal:
            case True{}:
              fuzzy_contains.go(p, FuzzyScan{hay, needle_tail})
            case False{}:
              fuzzy_contains.go(p, FuzzyScan{hay, SCon{needle_head, needle_tail}})

def fuzzy_contains(+hay: String, +needle: String) -> Bool:
  fuzzy_contains.go(Nat.mul(2n, Nat.add(String.length(hay), 1n)), FuzzyScan{hay, needle})

# W2: match against the shared visible-text haystack (style controls and
# color parameters never match); stored rows and results keep raw bytes.
def search_text_matches(+text: String, +q: String) -> Bool:
  fuzzy_contains(Irc.rfc1459(Ws.rendered_text(Ws.render(text))), Irc.rfc1459(q))

def search_line_matches(+text: String, +q: String, empty: Bool) -> Bool:
  match empty:
    case True{}:
      False{}
    case False{}:
      search_text_matches(text, q)

def line_matches_query(+ln: Cl.Line, +q: String) -> Bool:
  match ln:
    case Cl.Line{_, _, +text, +author, +id}:
      search_line_matches(text, q, String.is_empty(q))

def format_search_match(+buf_name: String, +ln: Cl.Line) -> Cl.Line:
  match ln:
    case Cl.Line{_, +ts, +text, +author, +id}:
      Cl.Line{Cl.Msg{}, ts, "[" ++ buf_name ++ "] " ++ text, author, id}

def search_match_line.on(+buf_name: String, +ln: Cl.Line, hit: Bool) -> List<&2, Cl.Line>:
  match hit:
    case True{}:
      format_search_match(buf_name, ln) <> Nil{}
    case False{}:
      Nil{}

def search_match_line(+buf_name: String, +ln: Cl.Line, +q: String) -> List<&2, Cl.Line>:
  search_match_line.on(buf_name, ln, line_matches_query(ln, q))

def search_tree(t: SearchTree, +q: String) -> List<&2, Cl.Line>:
  match t:
    case STLeaf{}:
      Nil{}
    case STOne{+buf_name, +ln}:
      search_match_line(buf_name, ln, q)
    case STNode{left, right}:
      l r = search_tree(left, q) search_tree(right, q)
      List.append(&2, Cl.Line, l, r)

def lines_to_trees.go(fuel: Nat, +buf_name: String, xs: List<&2, Cl.Line>) -> List<&2, SearchTree>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      match xs:
        case Nil{}:
          Nil{}
        case Con{+h, t}:
          STOne{buf_name, h} <> lines_to_trees.go(p, buf_name, t)

def lines_to_trees(+buf_name: String, +xs: List<&2, Cl.Line>) -> List<&2, SearchTree>:
  lines_to_trees.go(Nat.add(1n, List.length(&2, Cl.Line, xs)), buf_name, xs)

def pair_trees(xs: List<&2, SearchTree>) -> List<&2, SearchTree>:
  match xs:
    case Nil{}:
      Nil{}
    case t1 <> Nil{}:
      t1 <> Nil{}
    case t1 <> t2 <> rest:
      STNode{t1, t2} <> pair_trees(rest)

def trees_to_tree.go(fuel: Nat, xs: List<&2, SearchTree>) -> SearchTree:
  match fuel:
    case 0n:
      STLeaf{}
    case 1n+p:
      match xs:
        case Nil{}:
          STLeaf{}
        case t <> Nil{}:
          t
        case _:
          trees_to_tree.go(p, pair_trees(xs))

def trees_to_tree(+xs: List<&2, SearchTree>) -> SearchTree:
  trees_to_tree.go(Nat.add(2n, List.length(&2, SearchTree, xs)), xs)

def buf_to_tree(+b: Cl.Buffer) -> SearchTree:
  match b:
    case Cl.Buffer{+name, _, _, +lines, _, _, _, _}:
      trees_to_tree(lines_to_trees(name, lines))

def is_search_buf(+name: String) -> Bool:
  String.eq(name, "*search*")

def buf_collect_trees.cons(tree: SearchTree, rest: List<&2, SearchTree>, is_search: Bool) -> List<&2, SearchTree>:
  match is_search:
    case True{}:
      rest
    case False{}:
      tree <> rest

def buf_collect_trees(xs: List<&2, Cl.Buffer>) -> List<&2, SearchTree>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{b, t}:
      match b:
        case Cl.Buffer{+name, _, _, _, _, _, _, _}:
          buf_collect_trees.cons(buf_to_tree(b), buf_collect_trees(t), is_search_buf(name))

def bufs_to_tree(+bufs: List<&2, Cl.Buffer>) -> SearchTree:
  trees_to_tree(buf_collect_trees(bufs))

def search_buf(+b: Cl.Buffer, +q: String) -> List<&2, Cl.Line>:
  Cl.take_last(search_tree(buf_to_tree(b), q), Cl.SCROLL_CAP())

def search_bufs(+bufs: List<&2, Cl.Buffer>, +q: String) -> List<&2, Cl.Line>:
  Cl.take_last(search_tree(bufs_to_tree(bufs), q), Cl.SCROLL_CAP())

def search_and_open.at(+cl: Cl.Client, +bi: Nat, +q: String) -> Cl.Client:
  +matches = search_bufs(Cl.client_bufs(cl), q)
  +cl2 = Cl.buf_set_lines_at(cl, bi, matches)
  Cl.set_active(cl2, bi)

def search_and_open.full(+cl: Cl.Client, server: Bool) -> Cl.Client:
  match server:
    case True{}:
      cl
    case False{}:
      Cl.client_log(cl, Cl.active_of(cl), Cl.Error{}, "search unavailable: buffer limit reached")

def search_and_open.got(pair: Cl.Client & Maybe<&2, Nat>, +q: String) -> Cl.Client:
  match pair:
    case (+cl2, None{}):
      search_and_open.full(cl2, Nat.is_eq(Cl.active_of(cl2), 0n))
    case (cl2, Some{+bi}):
      search_and_open.at(cl2, bi, q)

def search_and_open(+cl: Cl.Client, +q: String) -> Cl.Client:
  search_and_open.got(Cl.buf_get(cl, "*search*", False{}, True{}), q)
