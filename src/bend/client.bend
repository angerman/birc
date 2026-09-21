# IRC feed dispatcher (M1). Container types live in buffer.bend.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl

# ---- format helpers -----------------------------------------------------

def msg_nick(+m: Irc.Message) -> String:
  match m:
    case Irc.Message{+nick, _, _, _}:
      nick

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

def feed_none(+cl: Cl.Client) -> Cl.Client:
  cl

def feed_ping(+cl: Cl.Client) -> Cl.Client:
  cl

def feed_priv.write.msg(+cl: Cl.Client, +bi: Nat, +from: String, +body: String, act: Bool) -> Cl.Client:
  match act:
    case True{}:
      Cl.client_log(cl, bi, Cl.Action{}, fmt_action(from, action_text(body)))
    case False{}:
      Cl.client_log(cl, bi, Cl.Msg{}, fmt_msg(from, body))

def feed_priv.write(+cl: Cl.Client, +bi: Nat, +from: String, notice: Bool, +body: String) -> Cl.Client:
  match notice:
    case True{}:
      Cl.client_log(cl, bi, Cl.Notice{}, fmt_msg(from, body))
    case False{}:
      feed_priv.write.msg(cl, bi, from, body, is_action(body))

def feed_priv.write_got(pair: Cl.Client & Maybe<&2, Nat>, +from: String, notice: Bool, +body: String) -> Cl.Client:
  match pair:
    case (cl2, Some{+bi}):
      feed_priv.write(cl2, bi, from, notice, body)
    case (cl2, None{}):
      cl2

def feed_priv.key.on(+from: String, +target: String, self: Bool) -> String:
  match self:
    case True{}:
      target
    case False{}:
      from

def feed_priv.key(+cl: Cl.Client, +from: String, +target: String) -> String:
  match cl:
    case Cl.Client{+nick, _, _, _, _}:
      feed_priv.key.on(from, target, Irc.ieq(from, nick))

def feed_priv.nonchan(
  +cl: Cl.Client,
  +from: String,
  notice: Bool,
  +body: String,
  empty: Bool,
  +target: String
) -> Cl.Client:
  match empty:
    case True{}:
      feed_priv.write(cl, 0n, from, notice, body)
    case False{}:
      feed_priv.write_got(Cl.buf_get(cl, feed_priv.key(cl, from, target), False{}, True{}), from, notice, body)

def feed_priv.to_server.on(empty: Bool, broadcast: Bool) -> Bool:
  match empty:
    case True{}:
      True{}
    case False{}:
      broadcast

# NOTICE * / AUTH (and a missing nick) is a server broadcast, not a query.
def feed_priv.to_server(+from: String, +target: String) -> Bool:
  feed_priv.to_server.on(String.is_empty(from), Irc.ieq(target, "*") || Irc.ieq(target, "AUTH"))

def feed_priv.route.on(+cl: Cl.Client, +target: String, +from: String, notice: Bool, +body: String, chan: Bool) -> Cl.Client:
  match chan:
    case True{}:
      feed_priv.write_got(Cl.buf_get(cl, target, True{}, False{}), from, notice, body)
    case False{}:
      feed_priv.nonchan(cl, from, notice, body, feed_priv.to_server(from, target), target)

def feed_priv.route(+cl: Cl.Client, +target: String, +from: String, notice: Bool, +body: String) -> Cl.Client:
  +tgt = Irc.chan_target(target)
  feed_priv.route.on(cl, tgt, from, notice, body, Irc.starts_channel(tgt))

def feed_join.self(+cl: Cl.Client, +bi: Nat, self: Bool) -> Cl.Client:
  match self:
    case True{}:
      Cl.set_active(cl, bi)
    case False{}:
      cl

def join_upd(+from: String, +chan: String, +now: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.buf_log_ts(Cl.nick_add(b, from), Cl.System{}, now, fmt_join(from, chan))

def feed_join.from_cl(+cl2: Cl.Client, +bi: Nat, +from: String, +chan: String, self: Bool) -> Cl.Client:
  match cl2:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      feed_join.self(
        Cl.Client{nick, server, Cl.buf_modify(bufs, bi, join_upd(from, chan, now)), active, now},
        bi,
        self
      )

def feed_join.from_pair(pair: Cl.Client & Maybe<&2, Nat>, +from: String, +chan: String, self: Bool) -> Cl.Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_join.from_cl(cl2, bi, from, chan, self)

def feed_join.with.on(+cl: Cl.Client, +from: String, +chan: String, +self: Bool, empty: Bool) -> Cl.Client:
  match empty:
    case True{}:
      cl
    case False{}:
      feed_join.from_pair(Cl.buf_get(cl, chan, True{}, self), from, chan, self)

def feed_join.with(+cl: Cl.Client, +from: String, +chan: String, +self: Bool) -> Cl.Client:
  feed_join.with.on(cl, from, chan, self, String.is_empty(chan))

def feed_join(+cl: Cl.Client, +m: Irc.Message, self: Bool) -> Cl.Client:
  feed_join.with(cl, msg_nick(m), Irc.msg_param(m, 0n), self)

def part_upd.on(+from: String, +chan: String, +now: String, +b: Cl.Buffer, has: Bool) -> Cl.Buffer:
  match has:
    case False{}:
      b
    case True{}:
      Cl.buf_log_ts(Cl.nick_del(b, from), Cl.System{}, now, fmt_part(from, chan))

def part_upd(+from: String, +chan: String, +now: String, b: Cl.Buffer) -> Cl.Buffer:
  +bb = b
  part_upd.on(from, chan, now, bb, Cl.nick_has(bb, from))

def feed_part.at(+nick: String, +server: String, +bufs: List<&2, Cl.Buffer>, +active: Nat, +now: String, +bi: Nat, +from: String, +chan: String) -> Cl.Client:
  Cl.Client{nick, server, Cl.buf_modify(bufs, bi, part_upd(from, chan, now)), active, now}

def feed_part.on(+cl: Cl.Client, +chan: String, +from: String, found: Maybe<&2, Nat>) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      match found:
        case None{}:
          Cl.Client{nick, server, bufs, active, now}
        case Some{bi}:
          feed_part.at(nick, server, bufs, active, now, bi, from, chan)

def feed_part.pick(+cl: Cl.Client, +chan: String, +from: String, self: Bool, found: Maybe<&2, Nat>) -> Cl.Client:
  match self:
    case True{}:
      Cl.drop_buf.at(cl, found)
    case False{}:
      feed_part.on(cl, chan, from, found)

def feed_part.with(+cl: Cl.Client, +chan: String, +from: String, self: Bool) -> Cl.Client:
  feed_part.pick(cl, chan, from, self, Cl.buf_find(cl, chan))

def feed_part(+cl: Cl.Client, +m: Irc.Message, self: Bool) -> Cl.Client:
  feed_part.with(cl, Irc.msg_param(m, 0n), msg_nick(m), self)

def fmt_kick(+victim: String, +chan: String) -> String:
  "<- " ++ victim ++ " kicked from " ++ chan

def kick_upd(+victim: String, +chan: String, +now: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.buf_log_ts(Cl.nick_del(b, victim), Cl.System{}, now, fmt_kick(victim, chan))

def feed_kick.at(+nick: String, +server: String, +bufs: List<&2, Cl.Buffer>, +active: Nat, +now: String, +bi: Nat, +victim: String, +chan: String) -> Cl.Client:
  Cl.Client{nick, server, Cl.buf_modify(bufs, bi, kick_upd(victim, chan, now)), active, now}

def feed_kick.other(+cl: Cl.Client, +chan: String, +victim: String, found: Maybe<&2, Nat>) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      match found:
        case None{}:
          Cl.Client{nick, server, bufs, active, now}
        case Some{bi}:
          feed_kick.at(nick, server, bufs, active, now, bi, victim, chan)

def feed_kick.pick(+cl: Cl.Client, +chan: String, +victim: String, self: Bool, found: Maybe<&2, Nat>) -> Cl.Client:
  match self:
    case True{}:
      Cl.drop_buf.at(cl, found)
    case False{}:
      feed_kick.other(cl, chan, victim, found)

def is_channel_buf(+b: Cl.Buffer) -> Bool:
  match b:
    case Cl.Buffer{_, +ch, _, _, _, _}:
      ch

def feed_quit.one.on(+b: Cl.Buffer, +from: String, +reason: String, +ts: String, has: Bool) -> Cl.Buffer:
  match has:
    case True{}:
      Cl.buf_log_ts(Cl.nick_del(b, from), Cl.System{}, ts, fmt_quit(from, reason))
    case False{}:
      b

def feed_quit.one(+b: Cl.Buffer, +from: String, +reason: String, +ts: String) -> Cl.Buffer:
  feed_quit.one.on(b, from, reason, ts, Cl.nick_has(b, from))

def feed_quit.query.on(+h: Cl.Buffer, +from: String, +reason: String, +ts: String, hit: Bool) -> Cl.Buffer:
  match hit:
    case True{}:
      Cl.buf_log_ts(h, Cl.System{}, ts, fmt_quit(from, reason))
    case False{}:
      h

def feed_quit.query(+h: Cl.Buffer, +from: String, +reason: String, +ts: String) -> Cl.Buffer:
  match h:
    case Cl.Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      feed_quit.query.on(
        Cl.Buffer{name, ch, topic, lines, nicks, scroll},
        from,
        reason,
        ts,
        Irc.ieq(name, from)
      )

def feed_quit.apply.on(+h: Cl.Buffer, +from: String, +reason: String, +ts: String, ch: Bool) -> Cl.Buffer:
  match ch:
    case True{}:
      feed_quit.one(h, from, reason, ts)
    case False{}:
      feed_quit.query(h, from, reason, ts)

def feed_quit.apply(+h: Cl.Buffer, +from: String, +reason: String, +ts: String) -> Cl.Buffer:
  feed_quit.apply.on(h, from, reason, ts, is_channel_buf(h))

def feed_quit.map(xs: List<&2, Cl.Buffer>, +from: String, +reason: String, +ts: String) -> List<&2, Cl.Buffer>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      feed_quit.apply(h, from, reason, ts) <> feed_quit.map(t, from, reason, ts)

def feed_quit.with(+cl: Cl.Client, +from: String, +reason: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      Cl.Client{nick, server, feed_quit.map(bufs, from, reason, now), active, now}

def feed_quit(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  feed_quit.with(cl, msg_nick(m), Irc.msg_param(m, 0n))

def feed_nick.one.on(+b: Cl.Buffer, +from: String, +to: String, +ts: String, has: Bool) -> Cl.Buffer:
  match has:
    case True{}:
      Cl.buf_log_ts(Cl.nick_rename(b, from, to), Cl.System{}, ts, fmt_nick_chg(from, to))
    case False{}:
      b

def feed_nick.one(+b: Cl.Buffer, +from: String, +to: String, +ts: String) -> Cl.Buffer:
  feed_nick.one.on(b, from, to, ts, Cl.nick_has(b, from))

def feed_nick.query.on(+h: Cl.Buffer, +from: String, +to: String, +ts: String, hit: Bool) -> Cl.Buffer:
  match hit:
    case True{}:
      Cl.buf_log_ts(Cl.set_buf_name(h, to), Cl.System{}, ts, fmt_nick_chg(from, to))
    case False{}:
      h

def feed_nick.query(+h: Cl.Buffer, +from: String, +to: String, +ts: String) -> Cl.Buffer:
  match h:
    case Cl.Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      feed_nick.query.on(
        Cl.Buffer{name, ch, topic, lines, nicks, scroll},
        from,
        to,
        ts,
        Irc.ieq(name, from)
      )

def feed_nick.apply.on(+h: Cl.Buffer, +from: String, +to: String, +ts: String, ch: Bool) -> Cl.Buffer:
  match ch:
    case True{}:
      feed_nick.one(h, from, to, ts)
    case False{}:
      feed_nick.query(h, from, to, ts)

def feed_nick.apply(+h: Cl.Buffer, +from: String, +to: String, +ts: String) -> Cl.Buffer:
  feed_nick.apply.on(h, from, to, ts, is_channel_buf(h))

def feed_nick.map(xs: List<&2, Cl.Buffer>, +from: String, +to: String, +ts: String) -> List<&2, Cl.Buffer>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      feed_nick.apply(h, from, to, ts) <> feed_nick.map(t, from, to, ts)

def feed_nick.fin(+cl: Cl.Client, +to: String, self: Bool) -> Cl.Client:
  match self:
    case True{}:
      Cl.set_nick(cl, to)
    case False{}:
      cl

def feed_nick.with(+cl: Cl.Client, +from: String, +to: String, self: Bool) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      feed_nick.fin(Cl.Client{nick, server, feed_nick.map(bufs, from, to, now), active, now}, to, self)

def feed_nick(+cl: Cl.Client, +m: Irc.Message, self: Bool) -> Cl.Client:
  feed_nick.with(cl, msg_nick(m), Irc.msg_param(m, 0n), self)

def topic_upd(+from: String, +topic: String, +now: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.buf_log_ts(Cl.set_topic(b, topic), Cl.System{}, now, fmt_topic_set(from, topic))

def feed_topic.from_cl(+cl2: Cl.Client, +bi: Nat, +from: String, +topic: String) -> Cl.Client:
  match cl2:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      Cl.Client{nick, server, Cl.buf_modify(bufs, bi, topic_upd(from, topic, now)), active, now}

def feed_topic.from_pair(pair: Cl.Client & Maybe<&2, Nat>, +from: String, +topic: String) -> Cl.Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_topic.from_cl(cl2, bi, from, topic)

def feed_topic.with(+cl: Cl.Client, +chan: String, +topic: String, +from: String) -> Cl.Client:
  feed_topic.from_pair(Cl.buf_get(cl, chan, True{}, False{}), from, topic)

def feed_topic(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  feed_topic.with(cl, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), msg_nick(m))

# ---- names / numeric ----------------------------------------------------

def split_names.keep(s: String) -> Bool:
  Bool.not(String.is_empty(s))

def split_names(+s: String) -> List<&2, String>:
  List.filter(~String, ~split_names.keep, String.split(s, Chr{32}))

def topic_set(+topic: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.set_topic(b, topic)

def feed_num.topic.cl(+cl2: Cl.Client, +bi: Nat, +topic: String) -> Cl.Client:
  match cl2:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      Cl.Client{nick, server, Cl.buf_modify(bufs, bi, topic_set(topic)), active, now}

def feed_num.topic.pair(pair: Cl.Client & Maybe<&2, Nat>, +topic: String) -> Cl.Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_num.topic.cl(cl2, bi, topic)

def feed_num.topic(+cl: Cl.Client, +chan: String, +topic: String) -> Cl.Client:
  feed_num.topic.pair(Cl.buf_get(cl, chan, True{}, False{}), topic)

def names_upd(+names: String, b: Cl.Buffer) -> Cl.Buffer:
  Cl.nick_add_all(b, split_names(names))

def feed_num.names.cl(+cl2: Cl.Client, +bi: Nat, +names: String) -> Cl.Client:
  match cl2:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      Cl.Client{nick, server, Cl.buf_modify(bufs, bi, names_upd(names)), active, now}

def feed_num.names.pair(pair: Cl.Client & Maybe<&2, Nat>, +names: String) -> Cl.Client:
  match pair:
    case (cl2, None{}):
      cl2
    case (cl2, Some{+bi}):
      feed_num.names.cl(cl2, bi, names)

def feed_num.names(+cl: Cl.Client, +chan: String, +names: String) -> Cl.Client:
  feed_num.names.pair(Cl.buf_get(cl, chan, True{}, False{}), names)

def feed_num.other(+cl: Cl.Client, +num: U32, +text: String, err: Bool) -> Cl.Client:
  match err:
    case True{}:
      Cl.client_log(cl, 0n, Cl.Error{}, fmt_num(num, text))
    case False{}:
      Cl.client_log(cl, 0n, Cl.System{}, fmt_num(num, text))

def feed_num.433.on(+cl: Cl.Client, +m: Irc.Message, +num: U32, +nick: String, retry: Bool) -> Cl.Client:
  match retry:
    case True{}:
      feed_num.other(Cl.set_nick(cl, nick ++ "_"), num, Irc.msg_last(m), True{})
    case False{}:
      feed_num.other(cl, num, Irc.msg_last(m), True{})

def feed_num.433.cl(+cl: Cl.Client, +m: Irc.Message, +num: U32) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, _, _, _, _}:
      feed_num.433.on(cl, m, num, nick, Irc.nick433_retry(m, nick))

def feed_num.433(hit: Bool, +cl: Cl.Client, +m: Irc.Message, +num: U32) -> Cl.Client:
  match hit:
    case True{}:
      feed_num.433.cl(cl, m, num)
    case False{}:
      feed_num.other(cl, num, Irc.msg_last(m), U32.is_ge(num, 400))

def feed_num.tail(+cl: Cl.Client, +m: Irc.Message, +num: U32, is366: Bool) -> Cl.Client:
  match is366:
    case True{}:
      cl
    case False{}:
      feed_num.433(U32.is_eq(num, 433), cl, m, num)

def is_353_sym(+s: String) -> Bool:
  String.eq(s, "=") || String.eq(s, "*") || String.eq(s, "@")

def feed_num.353.body(+cl: Cl.Client, +m: Irc.Message, rfc2812: Bool) -> Cl.Client:
  match rfc2812:
    case True{}:
      feed_num.names(cl, Irc.msg_param(m, 2n), Irc.msg_param(m, 3n))
    case False{}:
      feed_num.names(cl, Irc.msg_param(m, 1n), Irc.msg_param(m, 2n))

def feed_num.353(+cl: Cl.Client, +m: Irc.Message, +num: U32, is353: Bool) -> Cl.Client:
  match is353:
    case True{}:
      feed_num.353.body(cl, m, is_353_sym(Irc.msg_param(m, 1n)))
    case False{}:
      feed_num.tail(cl, m, num, U32.is_eq(num, 366))

def feed_num.332(+cl: Cl.Client, +m: Irc.Message, +num: U32, is332: Bool) -> Cl.Client:
  match is332:
    case True{}:
      feed_num.topic(cl, Irc.msg_param(m, 1n), Irc.msg_param(m, 2n))
    case False{}:
      feed_num.353(cl, m, num, U32.is_eq(num, 353))

def feed_num.001(+cl: Cl.Client, +m: Irc.Message, +num: U32, is001: Bool) -> Cl.Client:
  match is001:
    case True{}:
      Cl.client_log(Cl.set_nick(cl, Irc.msg_param(m, 0n)), 0n, Cl.System{}, Irc.msg_param(m, 1n))
    case False{}:
      feed_num.332(cl, m, num, U32.is_eq(num, 332))

def feed_numeric(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  match m:
    case Irc.Message{_, _, +num, _}:
      feed_num.001(cl, m, num, U32.is_eq(num, 1))

def feed_self.empty(empty: Bool, +cl: Cl.Client, +from: String) -> Bool:
  match empty:
    case True{}:
      False{}
    case False{}:
      match cl:
        case Cl.Client{+nick, _, _, _, _}:
          Irc.ieq(from, nick)

def feed_self(+cl: Cl.Client, +from: String) -> Bool:
  feed_self.empty(String.is_empty(from), cl, from)

def feed_kick.with(+cl: Cl.Client, +chan: String, +victim: String) -> Cl.Client:
  feed_kick.pick(cl, chan, victim, feed_self(cl, victim), Cl.buf_find(cl, chan))

def feed_kick(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  feed_kick.with(cl, Irc.msg_param(m, 0n), Irc.msg_param(m, 1n))

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

def feed_mode(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  match m:
    case Irc.Message{+nick, _, _, +ps}:
      feed_mode.got(cl, nick, ps, Cl.buf_find(cl, first_param(ps)))

def feed_unk(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  match m:
    case Irc.Message{_, +cmd, _, _}:
      Cl.client_log(cl, 0n, Cl.System{}, fmt_unk(cmd, Irc.msg_param(m, 0n)))

def feed_msg.cmd(+cl: Cl.Client, +m: Irc.Message, +from: String, self: Bool, c: Irc.Cmd) -> Cl.Client:
  match c:
    case Irc.Ping{}:
      feed_ping(cl)
    case Irc.Privmsg{}:
      feed_priv.route(cl, Irc.msg_param(m, 0n), from, False{}, Irc.msg_param(m, 1n))
    case Irc.Notice{}:
      feed_priv.route(cl, Irc.msg_param(m, 0n), from, True{}, Irc.msg_param(m, 1n))
    case Irc.Join{}:
      feed_join(cl, m, self)
    case Irc.Part{}:
      feed_part(cl, m, self)
    case Irc.Kick{}:
      feed_kick(cl, m)
    case Irc.Quit{}:
      feed_quit(cl, m)
    case Irc.Nick{}:
      feed_nick(cl, m, self)
    case Irc.Topic{}:
      feed_topic(cl, m)
    case Irc.Mode{}:
      feed_mode(cl, m)
    case Irc.Numeric{_}:
      feed_numeric(cl, m)
    case Irc.Error{}:
      Cl.client_log(cl, 0n, Cl.Error{}, fmt_err(Irc.msg_param(m, 0n)))
    case _:
      feed_unk(cl, m)

def feed_msg.with(+cl: Cl.Client, +m: Irc.Message, +from: String) -> Cl.Client:
  feed_msg.cmd(cl, m, from, feed_self(cl, from), Irc.classify(m))

def feed_msg(+cl: Cl.Client, +m: Irc.Message) -> Cl.Client:
  feed_msg.with(cl, m, msg_nick(m))

def feed.on(+cl: Cl.Client, m: Maybe<&2, Irc.Message>) -> Cl.Client:
  match m:
    case None{}:
      feed_none(cl)
    case Some{msg}:
      feed_msg(cl, msg)

def feed(+cl: Cl.Client, +line: String) -> Cl.Client:
  feed.on(cl, Irc.parse(line))

# ---- demo / show --------------------------------------------------------

def demo_lines() -> List<&2, String>:
  ":irc.birc.dev 001 me :Welcome to the birc IRC Network me"
    <> ":me!me@localhost JOIN #birc"
    <> ":irc.birc.dev 353 me = #birc :me @alice bob carol"
    <> ":irc.birc.dev 366 me #birc :End of /NAMES list."
    <> ":irc.birc.dev 332 me #birc :birc — Bend 2 + timui.h IRC"
    <> ":alice!a@host PRIVMSG #birc :hi everyone"
    <> ":bob!b@host PRIVMSG #birc :morning — *bold* _em_ and `code`"
    <> ":carol!c@host PRIVMSG #birc :see https://timui.dev docs"
    <> Nil{}

def feed_step(cl: Cl.Client, line: String) -> Cl.Client:
  feed(cl, line)

def feed_all(+cl: Cl.Client, +xs: List<&2, String>) -> Cl.Client:
  List.foldl(~&2, ~String, ~Cl.Client, ~feed_step, xs, cl)


