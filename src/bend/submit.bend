# Composer submit (M2). Pure: Client -> input -> (Client & List<&2, String>) outbound.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./links.bend as Links
import ./args.bend as Args

def empty_out() -> List<&2, String>:
  Nil{}

def one_out(+s: String) -> List<&2, String>:
  Irc.clamp_line(Irc.strip_ctl(s)) <> Nil{}

# ---- take_verb / take_word (structural; helper never calls back) --------

def take_verb.cons(+h: Char, r: String & String) -> String & String:
  match r:
    case (tok, rest):
      (SCon{h, tok}, rest)

def take_verb.fin(+h: Char, +t: String, r: String & String, space: Bool) -> String & String:
  match space:
    case True{}:
      ("", t)
    case False{}:
      take_verb.cons(h, r)

def take_verb(s: String) -> String & String:
  match s:
    case SNil{}:
      ("", "")
    case SCon{+h, +t}:
      take_verb.fin(h, t, take_verb(t), Irc.is_space(h))

def skip_slash.on(+h: Char, +t: String, slash: Bool) -> String:
  match slash:
    case True{}:
      t
    case False{}:
      SCon{h, t}

def skip_slash(+s: String) -> String:
  match s:
    case SCon{+h, t}:
      skip_slash.on(h, t, Irc.code_is(h, 47))
    case SNil{}:
      SNil{}

def active_idx(+cl: Cl.Client) -> Nat:
  match cl:
    case Cl.Client{_, _, _, +active, _, _, +auth, +log_seq}:
      active

def active_name.on(+got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}:
      "server"
    case Some{b}:
      match b:
        case Cl.Buffer{+name, _, _, _, _, _}:
          name

def active_name(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, +active, _, _, +auth, +log_seq}:
      active_name.on(Cl.nth_buf(bufs, active))

def echo_self(+cl: Cl.Client, +bi: Nat, +body: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, _, _, _, _, _, +auth, +log_seq}:
      Cl.client_log_author_ts(cl, bi, Cl.Self{}, "", Feed.fmt_msg(nick, body), nick)

def echo_action(+cl: Cl.Client, +bi: Nat, +body: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, _, _, _, _, _, +auth, +log_seq}:
      Cl.client_log_author_ts(cl, bi, Cl.Action{}, "", Feed.fmt_action(nick, body), nick)

def echo_err(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, active_idx(cl), Cl.Error{}, msg)

def echo_info(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, active_idx(cl), Cl.System{}, msg)

def echo_sys(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, 0n, Cl.System{}, msg)

def echo_err_server(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, 0n, Cl.Error{}, msg)

# ---- /join --------------------------------------------------------------

def submit_join.got.on(+cl2: Cl.Client, +bi: Nat, +rest: String, +nick: String) -> Cl.Client & List<&2, String>:
  (Cl.set_active(Cl.nick_add_idx(cl2, bi, nick), bi), one_out(Irc.format_join(rest)))

def submit_join.got.cl(+cl2: Cl.Client, +bi: Nat, +rest: String) -> Cl.Client & List<&2, String>:
  match cl2:
    case Cl.Client{+nick, _, _, _, _, _, +auth, +log_seq}:
      submit_join.got.on(cl2, bi, rest, nick)

def submit_join.got(pair: Cl.Client & Maybe<&2, Nat>, +rest: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      submit_join.got.cl(cl2, bi, rest)

def submit_join.on(+cl: Cl.Client, +rest: String, chan: Bool) -> Cl.Client & List<&2, String>:
  match chan:
    case False{}:
      (echo_err(cl, "usage: /join #chan"), empty_out())
    case True{}:
      submit_join.got(Cl.buf_get(cl, rest, True{}, True{}), rest)

def submit_join(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_join.on(cl, rest, Irc.starts_channel(rest))

# ---- /part --------------------------------------------------------------

def submit_part.drop.pick(+cl: Cl.Client, +chan: String, +bi: Nat, is_server: Bool) -> Cl.Client & List<&2, String>:
  match is_server:
    case True{}:
      (cl, one_out(Irc.format_part(chan)))
    case False{}:
      (Cl.drop_buf(cl, bi), one_out(Irc.format_part(chan)))

def submit_part.drop(+cl: Cl.Client, +chan: String, +bi: Nat) -> Cl.Client & List<&2, String>:
  submit_part.drop.pick(cl, chan, bi, Nat.is_eq(bi, 0n))

def submit_part.on(+cl: Cl.Client, +chan: String, found: Maybe<&2, Nat>) -> Cl.Client & List<&2, String>:
  match found:
    case None{}:
      (cl, one_out(Irc.format_part(chan)))
    case Some{+bi}:
      submit_part.drop(cl, chan, bi)

def submit_part.with(+cl: Cl.Client, +chan: String) -> Cl.Client & List<&2, String>:
  submit_part.on(cl, chan, Cl.buf_find(cl, chan))

def submit_part.is_ch(+cl: Cl.Client, +chan: String, is_chan: Bool) -> Cl.Client & List<&2, String>:
  match is_chan:
    case True{}:
      submit_part.with(cl, chan)
    case False{}:
      (echo_err(cl, "not a channel — use /close"), empty_out())

def submit_part.empty.on(+cl: Cl.Client, +rest: String, server: Bool) -> Cl.Client & List<&2, String>:
  match server:
    case True{}:
      (echo_err(cl, "usage: /part #chan"), empty_out())
    case False{}:
      submit_part.is_ch(cl, active_name(cl), Irc.starts_channel(active_name(cl)))

def submit_part.empty(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      submit_part.empty.on(cl, rest, Nat.is_eq(active_idx(cl), 0n))
    case False{}:
      submit_part.is_ch(cl, rest, Irc.starts_channel(rest))

def submit_part(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_part.empty(cl, rest, String.is_empty(rest))

# ---- /close -------------------------------------------------------------

def submit_close.out(+tgt: String, is_chan: Bool) -> List<&2, String>:
  match is_chan:
    case True{}:
      one_out(Irc.format_part(tgt))
    case False{}:
      empty_out()

def submit_close.fin(+cl: Cl.Client, +tgt: String, +bi: Nat, is_chan: Bool) -> Cl.Client & List<&2, String>:
  (Cl.drop_buf(cl, bi), submit_close.out(tgt, is_chan))

def submit_close.drop(+cl: Cl.Client, +tgt: String, +bi: Nat, is_server: Bool) -> Cl.Client & List<&2, String>:
  match is_server:
    case True{}:
      (echo_err(cl, "cannot close server buffer"), empty_out())
    case False{}:
      submit_close.fin(cl, tgt, bi, Irc.starts_channel(tgt))

def submit_close.miss(+cl: Cl.Client, +tgt: String, is_chan: Bool) -> Cl.Client & List<&2, String>:
  match is_chan:
    case True{}:
      (cl, one_out(Irc.format_part(tgt)))
    case False{}:
      (echo_err(cl, "no such buffer: " ++ tgt), empty_out())

def submit_close.on(+cl: Cl.Client, +tgt: String, found: Maybe<&2, Nat>) -> Cl.Client & List<&2, String>:
  match found:
    case None{}:
      submit_close.miss(cl, tgt, Irc.starts_channel(tgt))
    case Some{+bi}:
      submit_close.drop(cl, tgt, bi, Nat.is_eq(bi, 0n))

def submit_close.with(+cl: Cl.Client, +tgt: String) -> Cl.Client & List<&2, String>:
  submit_close.on(cl, tgt, Cl.buf_find(cl, tgt))

def submit_close.empty(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      submit_close.drop(cl, active_name(cl), active_idx(cl), Nat.is_eq(active_idx(cl), 0n))
    case False{}:
      submit_close.with(cl, rest)

def submit_close(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_close.empty(cl, rest, String.is_empty(rest))

# ---- /msg ---------------------------------------------------------------

def take_word.cons(+h: Char, r: String & String) -> String & String:
  match r:
    case (tok, rest):
      (SCon{h, tok}, rest)

def take_word.fin(+h: Char, +t: String, r: String & String, space: Bool) -> String & String:
  match space:
    case True{}:
      ("", Irc.drop_spaces(t))
    case False{}:
      take_word.cons(h, r)

def take_word(s: String) -> String & String:
  match s:
    case SNil{}:
      ("", "")
    case SCon{+h, +t}:
      take_word.fin(h, t, take_word(t), Irc.is_space(h))

def submit_msg.got(pair: Cl.Client & Maybe<&2, Nat>, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      +cl3 = Cl.set_active(echo_self(cl2, bi, body), bi)
      (cl3, one_out(Irc.format_privmsg(who, body)))

def submit_msg.bad(+cl: Cl.Client, bad: Bool, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match bad:
    case True{}:
      (echo_err(cl, "usage: /msg nick text"), empty_out())
    case False{}:
      submit_msg.got(Cl.buf_get(cl, who, False{}, True{}), who, body)

def submit_msg.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+who, +body):
      submit_msg.bad(cl, String.is_empty(who) || String.is_empty(body), who, body)

def submit_msg(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_msg.words(cl, take_word(rest))

def submit_query.send(has_text: Bool, +cl: Cl.Client, +bi: Nat, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match has_text:
    case False{}:
      (cl, empty_out())
    case True{}:
      (echo_self(cl, bi, body), one_out(Irc.format_privmsg(who, body)))

def submit_query.found(+cl2: Cl.Client, +bi: Nat, +who: String, +body: String, has_text: Bool) -> Cl.Client & List<&2, String>:
  submit_query.send(has_text, Cl.set_active(cl2, bi), bi, who, body)

def submit_query.text(pair: Cl.Client & Maybe<&2, Nat>, +who: String, +body: String, has_text: Bool) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      submit_query.found(cl2, bi, who, body, has_text)

def submit_query.empty(+cl: Cl.Client, empty: Bool, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /query <nick> [text]"), empty_out())
    case False{}:
      submit_query.text(Cl.buf_get(cl, who, False{}, True{}), who, body, Bool.not(String.is_empty(body)))

def submit_query.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+who, +body):
      submit_query.empty(cl, String.is_empty(who), who, body)

def submit_query(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_query.words(cl, take_word(Irc.drop_spaces(rest)))

# ---- /nick /me /quit /unknown -------------------------------------------

def submit_nick.on(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /nick name"), empty_out())
    case False{}:
      (cl, one_out(Irc.format_nick(rest)))

def submit_nick(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_nick.on(cl, rest, String.is_empty(rest))

def ctcp_action(+rest: String) -> String:
  SCon{Chr{1}, "ACTION " ++ rest ++ SCon{Chr{1}, SNil{}}}

def submit_me.chan(+cl: Cl.Client, +rest: String, on_server: Bool) -> Cl.Client & List<&2, String>:
  match on_server:
    case True{}:
      (echo_err(cl, "not in a channel — /join #chan first"), empty_out())
    case False{}:
      +tgt = active_name(cl)
      +bi = active_idx(cl)
      (echo_action(cl, bi, rest), one_out(Irc.format_privmsg(tgt, ctcp_action(rest))))

def active_is_synthetic(+cl: Cl.Client) -> Bool:
  String.starts_with(active_name(cl), "*")

def submit_me.target(+cl: Cl.Client, +rest: String, synthetic: Bool) -> Cl.Client & List<&2, String>:
  match synthetic:
    case True{}: (echo_err(cl, "read-only buffer"), empty_out())
    case False{}: submit_me.chan(cl, rest, Nat.is_eq(active_idx(cl), 0n))

def submit_me.on(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /me action"), empty_out())
    case False{}:
      submit_me.target(cl, rest, active_is_synthetic(cl))

def submit_me(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_me.on(cl, rest, String.is_empty(rest))

def submit_quit.reason(+rest: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "birc"
    case False{}:
      rest

def submit_quit(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  (cl, one_out(Irc.format_quit(submit_quit.reason(rest, String.is_empty(rest)))))

def submit_unknown(+cl: Cl.Client, +verb: String) -> Cl.Client & List<&2, String>:
  (echo_err(cl, "unknown command: /" ++ verb), empty_out())

# Session handles connection commands as Dial, not IRC wire output.

type Conn is Data:
  ConnBad{}
  ConnOk{host: String, port: U32}
  ConnReconnect{}

def connect_port.range(+host: String, +p: U32, bad: Bool) -> Conn:
  match bad:
    case True{}:
      ConnBad{}
    case False{}:
      ConnOk{host, p}

def connect_port.num(+host: String, got: Maybe<&2, U32>) -> Conn:
  match got:
    case None{}:
      ConnBad{}
    case Some{+p}:
      connect_port.range(host, p, U32.is_eq(p, 0) || U32.is_gt(p, Args.PORT_MAX()))

def connect_port.on(+host: String, +more: String, empty: Bool) -> Conn:
  match empty:
    case True{}:
      ConnOk{host, 6667}
    case False{}:
      connect_port.num(host, U32.read(more))

def connect_parse.host(+host: String, +more: String, empty: Bool) -> Conn:
  match empty:
    case True{}:
      ConnBad{}
    case False{}:
      connect_port.on(host, more, String.is_empty(more))

def connect_parse.words(pair: String & String) -> Conn:
  match pair:
    case (+host, +more):
      connect_parse.host(host, more, String.is_empty(host))

def connect_parse(+rest: String) -> Conn:
  connect_parse.words(take_word(Irc.drop_spaces(rest)))

# ---- /settings, /set, /toggle -------------------------------------------

def bool_str(b: Bool) -> String:
  match b:
    case True{}:
      "ON"
    case False{}:
      "OFF"

def populate_settings(+cl: Cl.Client, +bi: Nat) -> Cl.Client:
  +stg = Cl.get_settings(cl)
  +c1 = Cl.buf_clear_at(cl, bi)
  +c2 = Cl.client_log(c1, bi, Cl.System{}, "=== BIRC SETTINGS ===")
  +c3 = Cl.client_log(c2, bi, Cl.System{}, "  joins     : " ++ bool_str(Cl.settings_joins(stg)) ++ "  (show join/part/quit messages)")
  +c4 = Cl.client_log(c3, bi, Cl.System{}, "  ts        : " ++ bool_str(Cl.settings_ts(stg)) ++ "  (show message timestamps)")
  +c5 = Cl.client_log(c4, bi, Cl.System{}, "  motd      : " ++ bool_str(Cl.settings_motd(stg)) ++ "  (show server motd on connect)")
  +c6 = Cl.client_log(c5, bi, Cl.System{}, "  history   : " ++ bool_str(Cl.settings_history(stg)) ++ "  (persist chat scrollback to disk)")
  +c7 = Cl.client_log(c6, bi, Cl.System{}, "  hist_cap  : " ++ U32.show(Cl.settings_hist_cap(stg)) ++ "  (lines of history per channel/server)")
  +c8 = Cl.client_log(c7, bi, Cl.System{}, "  autoreconn: " ++ bool_str(Cl.settings_autoreconn(stg)) ++ "  (auto-reconnect on unexpected disconnect)")
  +c9 = Cl.client_log(c8, bi, Cl.System{}, "  bell      : " ++ bool_str(Cl.settings_bell(stg)) ++ "  (terminal bell on mentions/highlights)")
  +c10 = Cl.client_log(c9, bi, Cl.System{}, "  mutes     : " ++ Nat.show(List.length(&2, String, Cl.settings_mutes(stg))) ++ " active rule(s)")
  +c11 = Cl.client_log(c10, bi, Cl.System{}, "")
  +c12 = Cl.client_log(c11, bi, Cl.System{}, "Commands:")
  +c13 = Cl.client_log(c12, bi, Cl.System{}, "  /set <setting> <value>    — change a setting")
  +c14 = Cl.client_log(c13, bi, Cl.System{}, "  /toggle <setting>         — toggle a boolean setting")
  +c15 = Cl.client_log(c14, bi, Cl.System{}, "  /query <nick> [text]      — open 1-on-1 private chat tab")
  +c16 = Cl.client_log(c15, bi, Cl.System{}, "  /mute <nick>              — mute nick on active channel/server")
  +c17 = Cl.client_log(c16, bi, Cl.System{}, "  /unmute <nick>            — remove nick from mute list")
  +c18 = Cl.client_log(c17, bi, Cl.System{}, "  /mutes                    — show active mute rules")
  +c19 = Cl.client_log(c18, bi, Cl.System{}, "  /reconnect                — reconnect to current server")
  Cl.client_log(c19, bi, Cl.System{}, "  /close                    — close settings buffer")

def refresh_settings_if_open.found(+cl: Cl.Client, found: Maybe<&2, Nat>) -> Cl.Client:
  match found:
    case None{}:
      cl
    case Some{+bi}:
      populate_settings(cl, bi)

def refresh_settings_if_open(+cl: Cl.Client) -> Cl.Client:
  refresh_settings_if_open.found(cl, Cl.buf_find(cl, "*settings*"))

def submit_settings.got(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      (populate_settings(Cl.set_active(cl2, bi), bi), empty_out())

def submit_settings(+cl: Cl.Client) -> Cl.Client & List<&2, String>:
  submit_settings.got(Cl.buf_get(cl, "*settings*", False{}, True{}))

type SettingKey is Data:
  KeyJoins{}
  KeyTs{}
  KeyMotd{}
  KeyHist{}
  KeyHistCap{}
  KeyAutoreconn{}
  KeyBell{}
  KeyBad{}

def parse_key.bell(hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyBell{}
    case False{}:
      KeyBad{}

def parse_key.bad(hit: Bool, +s: String) -> SettingKey:
  match hit:
    case True{}:
      KeyAutoreconn{}
    case False{}:
      parse_key.bell(Irc.ieq(s, "bell") || Irc.ieq(s, "beep") || Irc.ieq(s, "alert"))

def parse_key.cap(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyHistCap{}
    case False{}:
      parse_key.bad(Irc.ieq(s, "autoreconn") || Irc.ieq(s, "autoreconnect") || Irc.ieq(s, "reconn"), s)

def parse_key.hist(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyHist{}
    case False{}:
      parse_key.cap(s, Irc.ieq(s, "hist_cap") || Irc.ieq(s, "histcap") || Irc.ieq(s, "lines") || Irc.ieq(s, "history_cap"))

def parse_key.motd(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyMotd{}
    case False{}:
      parse_key.hist(s, Irc.ieq(s, "history") || Irc.ieq(s, "hist"))

def parse_key.ts(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyTs{}
    case False{}:
      parse_key.motd(s, Irc.ieq(s, "motd"))

def parse_key.joins(+s: String, hit: Bool) -> SettingKey:
  match hit:
    case True{}:
      KeyJoins{}
    case False{}:
      parse_key.ts(s, Irc.ieq(s, "ts") || Irc.ieq(s, "timestamp") || Irc.ieq(s, "timestamps"))

def parse_key(+s: String) -> SettingKey:
  parse_key.joins(s, Irc.ieq(s, "joins") || Irc.ieq(s, "join"))

def is_bool_true(+s: String) -> Bool:
  Irc.ieq(s, "on") || Irc.ieq(s, "true") || Irc.ieq(s, "yes") || Irc.ieq(s, "1")

def is_bool_false(+s: String) -> Bool:
  Irc.ieq(s, "off") || Irc.ieq(s, "false") || Irc.ieq(s, "no") || Irc.ieq(s, "0")

def parse_bool.false(hit: Bool) -> Maybe<&2, Bool>:
  match hit:
    case True{}:
      Some{False{}}
    case False{}:
      None{}

def parse_bool.true(+s: String, hit: Bool) -> Maybe<&2, Bool>:
  match hit:
    case True{}:
      Some{True{}}
    case False{}:
      parse_bool.false(is_bool_false(s))

def parse_bool(+s: String) -> Maybe<&2, Bool>:
  parse_bool.true(s, is_bool_true(s))

def apply_set_key.joins(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_joins(stg, b))
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "setting 'joins' is now " ++ bool_str(b)), empty_out())

def apply_set_key.ts(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_ts(stg, b))
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "setting 'ts' is now " ++ bool_str(b)), empty_out())

def apply_set_key.motd(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_motd(stg, b))
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "setting 'motd' is now " ++ bool_str(b)), empty_out())

def apply_set_key.hist(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_history(stg, b))
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "setting 'history' is now " ++ bool_str(b)), empty_out())

def apply_set_key.cap(+cl: Cl.Client, +cap: U32) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_hist_cap(stg, cap))
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "setting 'hist_cap' is now " ++ U32.show(cap)), empty_out())

def apply_set_key.autoreconn(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_autoreconn(stg, b))
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "setting 'autoreconn' is now " ++ bool_str(b)), empty_out())

def apply_set_key.bell(+cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  +cl2 = Cl.set_settings(cl, Cl.set_bell(stg, b))
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "setting 'bell' is now " ++ bool_str(b)), empty_out())

def apply_set_key(k: SettingKey, +cl: Cl.Client, +b: Bool) -> Cl.Client & List<&2, String>:
  match k:
    case KeyJoins{}:
      apply_set_key.joins(cl, b)
    case KeyTs{}:
      apply_set_key.ts(cl, b)
    case KeyMotd{}:
      apply_set_key.motd(cl, b)
    case KeyHist{}:
      apply_set_key.hist(cl, b)
    case KeyHistCap{}:
      (echo_err(cl, "hist_cap expects a number: /set hist_cap <number>"), empty_out())
    case KeyAutoreconn{}:
      apply_set_key.autoreconn(cl, b)
    case KeyBell{}:
      apply_set_key.bell(cl, b)
    case KeyBad{}:
      (echo_err(cl, "unknown setting (valid: joins, ts, motd, history, hist_cap, autoreconn, bell)"), empty_out())

def apply_toggle_key(k: SettingKey, +cl: Cl.Client) -> Cl.Client & List<&2, String>:
  match k:
    case KeyJoins{}:
      apply_set_key.joins(cl, Bool.not(Cl.settings_joins(Cl.get_settings(cl))))
    case KeyTs{}:
      apply_set_key.ts(cl, Bool.not(Cl.settings_ts(Cl.get_settings(cl))))
    case KeyMotd{}:
      apply_set_key.motd(cl, Bool.not(Cl.settings_motd(Cl.get_settings(cl))))
    case KeyHist{}:
      apply_set_key.hist(cl, Bool.not(Cl.settings_history(Cl.get_settings(cl))))
    case KeyHistCap{}:
      (echo_err(cl, "cannot toggle hist_cap: use /set hist_cap <number>"), empty_out())
    case KeyAutoreconn{}:
      apply_set_key.autoreconn(cl, Bool.not(Cl.settings_autoreconn(Cl.get_settings(cl))))
    case KeyBell{}:
      apply_set_key.bell(cl, Bool.not(Cl.settings_bell(Cl.get_settings(cl))))
    case KeyBad{}:
      (echo_err(cl, "usage: /toggle <joins|ts|motd|history|autoreconn|bell>"), empty_out())

def show_setting_key(k: SettingKey, +cl: Cl.Client) -> Cl.Client & List<&2, String>:
  match k:
    case KeyJoins{}:
      (echo_info(cl, "joins is " ++ bool_str(Cl.settings_joins(Cl.get_settings(cl)))), empty_out())
    case KeyTs{}:
      (echo_info(cl, "ts is " ++ bool_str(Cl.settings_ts(Cl.get_settings(cl)))), empty_out())
    case KeyMotd{}:
      (echo_info(cl, "motd is " ++ bool_str(Cl.settings_motd(Cl.get_settings(cl)))), empty_out())
    case KeyHist{}:
      (echo_info(cl, "history is " ++ bool_str(Cl.settings_history(Cl.get_settings(cl)))), empty_out())
    case KeyHistCap{}:
      (echo_info(cl, "hist_cap is " ++ U32.show(Cl.settings_hist_cap(Cl.get_settings(cl)))), empty_out())
    case KeyAutoreconn{}:
      (echo_info(cl, "autoreconn is " ++ bool_str(Cl.settings_autoreconn(Cl.get_settings(cl)))), empty_out())
    case KeyBell{}:
      (echo_info(cl, "bell is " ++ bool_str(Cl.settings_bell(Cl.get_settings(cl)))), empty_out())
    case KeyBad{}:
      (echo_err(cl, "unknown setting (valid: joins, ts, motd, history, hist_cap, autoreconn, bell)"), empty_out())

def submit_set.cap(+cl: Cl.Client, mb: Maybe<&2, U32>) -> Cl.Client & List<&2, String>:
  match mb:
    case None{}:
      (echo_err(cl, "invalid value: expected number (e.g. 50, 100, 200)"), empty_out())
    case Some{cap}:
      apply_set_key.cap(cl, cap)

def submit_set.parsed(mb: Maybe<&2, Bool>, k: SettingKey, +cl: Cl.Client) -> Cl.Client & List<&2, String>:
  match mb:
    case None{}:
      (echo_err(cl, "invalid value: expected on|off"), empty_out())
    case Some{+b}:
      apply_set_key(k, cl, b)

def submit_set.dispatch(k: SettingKey, +cl: Cl.Client, +val: String) -> Cl.Client & List<&2, String>:
  match k:
    case KeyHistCap{}:
      submit_set.cap(cl, U32.read(val))
    case _:
      submit_set.parsed(parse_bool(val), k, cl)

def submit_set.val(+cl: Cl.Client, +key: String, +val: String, empty_val: Bool) -> Cl.Client & List<&2, String>:
  match empty_val:
    case True{}:
      show_setting_key(parse_key(key), cl)
    case False{}:
      submit_set.dispatch(parse_key(key), cl, val)

def submit_set.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+key, +val_raw):
      +val = Irc.drop_spaces(val_raw)
      submit_set.val(cl, key, val, String.is_empty(val))

def submit_set.empty(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      submit_settings(cl)
    case False{}:
      submit_set.words(cl, take_word(rest))

def submit_set(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_set.empty(cl, rest, String.is_empty(rest))

def submit_toggle.word(+cl: Cl.Client, +key: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /toggle <joins|ts|motd>"), empty_out())
    case False{}:
      apply_toggle_key(parse_key(key), cl)

def submit_toggle.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+key, _):
      submit_toggle.word(cl, key, String.is_empty(key))

def submit_toggle(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_toggle.words(cl, take_word(Irc.drop_spaces(rest)))

def submit_mute.pat(+cl: Cl.Client, +nick: String, is_chan: Bool) -> String:
  match is_chan:
    case True{}:
      nick ++ Cl.active_buf_name(cl) ++ "@" ++ Cl.server_of(cl)
    case False{}:
      nick ++ "*@" ++ Cl.server_of(cl)

def submit_mute.nick(+cl: Cl.Client, +nick: String) -> Cl.Client & List<&2, String>:
  +pat = submit_mute.pat(cl, nick, Irc.starts_channel(Cl.active_buf_name(cl)))
  +cl2 = Cl.add_mute_client(cl, pat)
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "muted " ++ nick ++ " (" ++ pat ++ ")"), empty_out())

def submit_mute.word(+cl: Cl.Client, +nick: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /mute <nick>"), empty_out())
    case False{}:
      submit_mute.nick(cl, nick)

def submit_mute.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+nick, _):
      submit_mute.word(cl, nick, String.is_empty(nick))

def submit_mute(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_mute.words(cl, take_word(Irc.drop_spaces(rest)))

def submit_unmute.nick(+cl: Cl.Client, +nick: String) -> Cl.Client & List<&2, String>:
  +cl2 = Cl.del_mute_client(cl, nick)
  +cl3 = refresh_settings_if_open(cl2)
  (echo_info(cl3, "unmuted " ++ nick), empty_out())

def submit_unmute.word(+cl: Cl.Client, +nick: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /unmute <nick>"), empty_out())
    case False{}:
      submit_unmute.nick(cl, nick)

def submit_unmute.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+nick, _):
      submit_unmute.word(cl, nick, String.is_empty(nick))

def submit_unmute(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_unmute.words(cl, take_word(Irc.drop_spaces(rest)))

def submit_mutes.go(+cl: Cl.Client, mutes: List<&2, String>) -> Cl.Client & List<&2, String>:
  match mutes:
    case Nil{}:
      (echo_info(cl, "no active mutes"), empty_out())
    case Con{+m, t}:
      (echo_info(cl, "active mutes: " ++ String.join(m <> t, ", ")), empty_out())

def submit_mutes(+cl: Cl.Client) -> Cl.Client & List<&2, String>:
  +stg = Cl.get_settings(cl)
  submit_mutes.go(cl, Cl.settings_mutes(stg))

def submit.is_slash.on(+h: Char) -> Bool:
  Irc.code_is(h, 47)

def submit.is_slash(+s: String) -> Bool:
  match s:
    case SCon{+h, _}:
      submit.is_slash.on(h)
    case SNil{}:
      False{}

def is_http_pfx(+s: String) -> Bool:
  Links.is_url_prefix(s)

def extract_urls(+s: String) -> List<&2, String>:
  Links.extract(s)

def lines_urls.line(skip: Bool, +text: String) -> List<&2, String>:
  match skip:
    case True{}: Nil{}
    case False{}: Links.extract(text)

def lines_urls.go(fuel: Nat, lines: List<&2, Cl.Line>) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match lines:
        case Nil{}: Nil{}
        case Con{ln, t}:
          match ln:
            case Cl.Line{+kind, _, +text, _, _}:
              List.append(&2, String, lines_urls.line(Cl.is_link_result(kind) || Cl.is_reconnect(kind), text), lines_urls.go(p, t))

def active_buf_urls(+cl: Cl.Client) -> List<&2, String>:
  +rev_lines = List.reverse(&2, Cl.Line, Cl.active_buf_lines(cl))
  lines_urls.go(Nat.add(1n, List.length(&2, Cl.Line, rev_lines)), rev_lines)

def nth_link.go(fuel: Nat, xs: List<&2, String>, n: Nat) -> Maybe<&2, String>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      match xs:
        case Nil{}: None{}
        case Con{+h, t}:
          match n:
            case 0n: Some{h}
            case 1n+pn: nth_link.go(p, t, pn)

def nth_link(xs: List<&2, String>, +n: Nat) -> Maybe<&2, String>:
  nth_link.go(Nat.add(1n, n), xs, n)

def echo_link_result(+cl: Cl.Client, +text: String) -> Cl.Client:
  Cl.client_log(cl, active_idx(cl), Cl.LinkResult{}, text)

def clear_link_results.keep(skip: Bool, line: Cl.Line, rest: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match skip:
    case True{}: rest
    case False{}: line <> rest

def clear_link_results.lines(lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+line, t}:
      match line:
        case Cl.Line{kind, _, _, _, _}:
          clear_link_results.keep(Cl.is_link_result(kind), line, clear_link_results.lines(t))

def clear_link_results.buf(b: Cl.Buffer) -> Cl.Buffer:
  match b:
    case Cl.Buffer{name, channel, topic, lines, nicks, scroll}:
      Cl.Buffer{name, channel, topic, clear_link_results.lines(lines), nicks, scroll}

def clear_link_results(+cl: Cl.Client) -> Cl.Client:
  Cl.buf_modify_client(cl, active_idx(cl), clear_link_results.buf)

def echo_links.go(fuel: Nat, cl: Cl.Client, xs: List<&2, String>, +idx: Nat) -> Cl.Client:
  match fuel:
    case 0n: cl
    case 1n+p:
      match xs:
        case Nil{}: cl
        case Con{+h, t}:
          +msg = "[" ++ Nat.show(idx) ++ "] " ++ h
          echo_links.go(p, echo_link_result(cl, msg), t, Nat.add(idx, 1n))

def submit_links.on(+cl: Cl.Client, urls: List<&2, String>) -> Cl.Client & List<&2, String>:
  match urls:
    case Nil{}:
      (echo_link_result(cl, "no links found in buffer"), empty_out())
    case Con{+h, t}:
      +cl2 = echo_link_result(cl, "recent links:")
      (echo_links.go(100n, cl2, h <> t, 1n), empty_out())

def submit_links(+cl: Cl.Client) -> Cl.Client & List<&2, String>:
  +source = clear_link_results(cl)
  submit_links.on(source, active_buf_urls(source))

def open_parse_arg.zero(is_zero: Bool, +cl: Cl.Client, n: U32) -> Maybe<&2, String>:
  match is_zero:
    case True{}: None{}
    case False{}:
      nth_link(active_buf_urls(cl), U32.to_nat(U32.sub(n, 1)))

def open_parse_arg.num(+cl: Cl.Client, num_mb: Maybe<&2, U32>) -> Maybe<&2, String>:
  match num_mb:
    case None{}:
      None{}
    case Some{+n}:
      open_parse_arg.zero(U32.is_eq(n, 0), cl, n)

def open_resolve_target.http(is_http: Bool, +cl: Cl.Client, +arg: String) -> Maybe<&2, String>:
  match is_http:
    case True{}:
      Some{arg}
    case False{}:
      open_parse_arg.num(cl, U32.read(arg))

def open_resolve_target.empty(empty: Bool, +cl: Cl.Client, +arg: String) -> Maybe<&2, String>:
  match empty:
    case True{}:
      nth_link(active_buf_urls(cl), 0n)
    case False{}:
      open_resolve_target.http(is_http_pfx(arg), cl, arg)

def open_resolve_target(+cl: Cl.Client, +arg: String) -> Maybe<&2, String>:
  open_resolve_target.empty(String.is_empty(arg), cl, arg)

def submit_open_cmd.got(+cl: Cl.Client, mb: Maybe<&2, String>) -> Cl.Client & List<&2, String>:
  match mb:
    case None{}:
      (echo_err(cl, "no link found"), empty_out())
    case Some{+url}:
      (echo_link_result(cl, "opening " ++ url), empty_out())

def submit_open_cmd(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_open_cmd.got(cl, open_resolve_target(cl, Irc.drop_spaces(rest)))

# ---- /search ------------------------------------------------------------

def submit_search.on(empty: Bool, +cl: Cl.Client, +query: String) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /search <query>"), empty_out())
    case False{}:
      (Feed.search_and_open(cl, query), empty_out())

def submit_search(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_search.on(String.is_empty(rest), cl, rest)

# ---- /preview -----------------------------------------------------------

def preview_local_path.file(file_url: Bool, +arg: String) -> String:
  match file_url:
    case True{}: String.drop(arg, 7n)
    case False{}: arg

def preview_local_path(+arg: String) -> String:
  preview_local_path.file(String.starts_with(arg, "file://"), arg)

def preview_file_url_ok() -> Bool:
  String.eq(preview_local_path("file:///tmp/image.png"), "/tmp/image.png")

def submit_preview.open(pair: Cl.Client & Maybe<&2, Nat>, +path: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+cl, None{}):
      (echo_err(cl, "preview unavailable: buffer limit reached"), empty_out())
    case (cl, Some{+i}):
      +cl2 = Cl.set_topic_at(cl, i, path)
      (Cl.set_active(cl2, i), empty_out())

def submit_preview.local(+cl: Cl.Client, +path: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /preview <local-path>"), empty_out())
    case False{}:
      submit_preview.open(Cl.buf_get(cl, "*preview*", False{}, True{}), path)

def submit_preview.remote(+cl: Cl.Client, +arg: String, remote: Bool) -> Cl.Client & List<&2, String>:
  match remote:
    case True{}:
      (echo_err(cl, "remote previews are unavailable; use a local path or file://-prefixed local path"), empty_out())
    case False{}:
      +path = preview_local_path(arg)
      submit_preview.local(cl, path, String.is_empty(path))

def submit_preview(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  +arg = Irc.drop_spaces(rest)
  submit_preview.remote(cl, arg, is_http_pfx(arg))

type Slash is Data:
  Join{}
  Part{}
  CloseCmd{}
  Msg{}
  QueryCmd{}
  Nick{}
  Me{}
  Quit{}
  SettingsCmd{}
  SetCmd{}
  ToggleCmd{}
  MuteCmd{}
  UnmuteCmd{}
  MutesCmd{}
  LinksCmd{}
  OpenCmd{}
  SearchCmd{}
  PreviewCmd{}
  Unknown{}

type SlashRow is Data:
  SlashRow{name: String, cmd: Slash}

def slash_rows() -> List<&2, SlashRow>:
  SlashRow{"join", Join{}}
    <> SlashRow{"part", Part{}}
    <> SlashRow{"close", CloseCmd{}}
    <> SlashRow{"msg", Msg{}}
    <> SlashRow{"query", QueryCmd{}}
    <> SlashRow{"nick", Nick{}}
    <> SlashRow{"me", Me{}}
    <> SlashRow{"quit", Quit{}}
    <> SlashRow{"settings", SettingsCmd{}}
    <> SlashRow{"set", SetCmd{}}
    <> SlashRow{"toggle", ToggleCmd{}}
    <> SlashRow{"mute", MuteCmd{}}
    <> SlashRow{"unmute", UnmuteCmd{}}
    <> SlashRow{"mutes", MutesCmd{}}
    <> SlashRow{"links", LinksCmd{}}
    <> SlashRow{"open", OpenCmd{}}
    <> SlashRow{"search", SearchCmd{}}
    <> SlashRow{"preview", PreviewCmd{}}
    <> Nil{}

def slash_lookup(xs: List<&2, SlashRow>, +verb: String) -> Slash:
  match xs:
    case Nil{}:
      Unknown{}
    case Con{row, t}:
      match row:
        case SlashRow{+name, +c}:
          Bool.pick(Slash, Irc.ieq(name, verb), c, slash_lookup(t, verb))

def slash_of(+verb: String) -> Slash:
  slash_lookup(slash_rows(), verb)

type Input is Data:
  EmptyInput{}
  PlainInput{text: String}
  CommandInput{cmd: Slash, verb: String, rest: String}

def parse_input.words(pair: String & String) -> Input:
  match pair:
    case (+verb, +rest): CommandInput{slash_of(verb), verb, Irc.drop_spaces(rest)}

def parse_input.slash(+input: String, slash: Bool) -> Input:
  match slash:
    case True{}: parse_input.words(take_verb(skip_slash(input)))
    case False{}: PlainInput{input}

def parse_input.empty(+input: String, empty: Bool) -> Input:
  match empty:
    case True{}: EmptyInput{}
    case False{}: parse_input.slash(input, submit.is_slash(input))

def parse_input(+input: String) -> Input:
  parse_input.empty(input, String.is_empty(input))

def submit_is_open.parsed(input: Input) -> Bool:
  match input:
    case CommandInput{OpenCmd{}, _, _}: True{}
    case _: False{}

def submit_is_open(+input: String) -> Bool:
  submit_is_open.parsed(parse_input(input))

def open_arg_from_input.parsed(input: Input) -> String:
  match input:
    case CommandInput{OpenCmd{}, _, rest}: rest
    case _: ""

def open_arg_from_input(+input: String) -> String:
  open_arg_from_input.parsed(parse_input(input))

def query_needs_connection(pair: String & String) -> Bool:
  match pair:
    case (_, +body): Bool.not(String.is_empty(body))

def command_needs_connection(cmd: Slash, +rest: String) -> Bool:
  match cmd:
    case Join{}: True{}
    case Part{}: True{}
    case Msg{}: True{}
    case Nick{}: True{}
    case Me{}: True{}
    case QueryCmd{}: query_needs_connection(take_word(rest))
    case _: False{}

def needs_connection(input: Input) -> Bool:
  match input:
    case PlainInput{_}: True{}
    case CommandInput{cmd, _, +rest}: command_needs_connection(cmd, rest)
    case EmptyInput{}: False{}

def submit_cmd.do(+cl: Cl.Client, +verb: String, +rest: String, cmd: Slash) -> Cl.Client & List<&2, String>:
  match cmd:
    case Join{}:
      submit_join(cl, rest)
    case Part{}:
      submit_part(cl, rest)
    case CloseCmd{}:
      submit_close(cl, rest)
    case Msg{}:
      submit_msg(cl, rest)
    case QueryCmd{}:
      submit_query(cl, rest)
    case Nick{}:
      submit_nick(cl, rest)
    case Me{}:
      submit_me(cl, rest)
    case Quit{}:
      submit_quit(cl, rest)
    case SettingsCmd{}:
      submit_settings(cl)
    case SetCmd{}:
      submit_set(cl, rest)
    case ToggleCmd{}:
      submit_toggle(cl, rest)
    case MuteCmd{}:
      submit_mute(cl, rest)
    case UnmuteCmd{}:
      submit_unmute(cl, rest)
    case MutesCmd{}:
      submit_mutes(cl)
    case LinksCmd{}:
      submit_links(cl)
    case OpenCmd{}:
      submit_open_cmd(cl, rest)
    case SearchCmd{}:
      submit_search(cl, rest)
    case PreviewCmd{}:
      submit_preview(cl, rest)
    case Unknown{}:
      submit_unknown(cl, verb)

def submit_plain.on(+cl: Cl.Client, +input: String, on_server: Bool) -> Cl.Client & List<&2, String>:
  match on_server:
    case True{}:
      (echo_err(cl, "not in a channel — /join #chan first"), empty_out())
    case False{}:
      +tgt = active_name(cl)
      +bi = active_idx(cl)
      (echo_self(cl, bi, input), one_out(Irc.format_privmsg(tgt, input)))

def submit_plain.virtual(virtual: Bool, +cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  match virtual:
    case True{}:
      (echo_err(cl, "read-only buffer"), empty_out())
    case False{}:
      submit_plain.on(cl, input, Nat.is_eq(active_idx(cl), 0n))

def submit_plain(+cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  submit_plain.virtual(active_is_synthetic(cl), cl, input)

def submit_parsed(+cl: Cl.Client, input: Input) -> Cl.Client & List<&2, String>:
  match input:
    case EmptyInput{}: (cl, empty_out())
    case PlainInput{+text}: submit_plain(cl, text)
    case CommandInput{cmd, +verb, +rest}: submit_cmd.do(cl, verb, rest, cmd)

def submit(+cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  submit_parsed(cl, parse_input(input))

def out_all_ok.go(+xs: List<&2, String>, ok: Bool) -> Bool:
  match xs:
    case Nil{}:
      ok
    case Con{+h, t}:
      match ok:
        case False{}:
          False{}
        case True{}:
          out_all_ok.go(t, Irc.line_ok(h))

def out_all_ok(+xs: List<&2, String>) -> Bool:
  out_all_ok.go(xs, True{})

def submit_ok.fin(outs: List<&2, String>) -> Bool:
  out_all_ok(outs)

def submit_ok.pair(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, outs):
      submit_ok.fin(outs)

def submit_ok(+cl: Cl.Client, +input: String) -> Bool:
  submit_ok.pair(submit(cl, input))

def submit_is_quit.parsed(input: Input) -> Bool:
  match input:
    case CommandInput{Quit{}, _, _}: True{}
    case _: False{}

def submit_is_quit(+input: String) -> Bool:
  submit_is_quit.parsed(parse_input(input))

def submit_halt_ok() -> Bool:
  submit_is_quit("/quit") && submit_is_quit("/quit bye") && Bool.not(submit_is_quit("hello")) && Bool.not(submit_is_quit("/join #x"))

def submit_is_connect.parsed(input: Input) -> Bool:
  match input:
    case CommandInput{_, +verb, _}: Irc.ieq(verb, "connect") || Irc.ieq(verb, "reconnect")
    case _: False{}

def submit_is_connect(+input: String) -> Bool:
  submit_is_connect.parsed(parse_input(input))

def connect_from_input.verb(is_recon: Bool, +rest: String) -> Conn:
  match is_recon:
    case True{}:
      ConnReconnect{}
    case False{}:
      connect_parse(Irc.drop_spaces(rest))

def connect_from_input.parsed(input: Input) -> Conn:
  match input:
    case CommandInput{_, +verb, +rest}:
      connect_from_input.verb(Irc.ieq(verb, "reconnect"), rest)
    case _: ConnBad{}

def connect_from_input(+input: String) -> Conn:
  connect_from_input.parsed(parse_input(input))

def connect_parse_ok.on(c: Conn) -> Bool:
  match c:
    case ConnOk{+host, port}:
      String.eq(host, "irc.example.net") && U32.is_eq(port, 6668)
    case ConnBad{}:
      False{}
    case ConnReconnect{}:
      False{}

def connect_default_ok.on(c: Conn) -> Bool:
  match c:
    case ConnOk{_, p}:
      U32.is_eq(p, 6667)
    case ConnBad{}:
      False{}
    case ConnReconnect{}:
      False{}

def connect_bad.on(c: Conn) -> Bool:
  match c:
    case ConnBad{}:
      True{}
    case ConnOk{_, _}:
      False{}
    case ConnReconnect{}:
      False{}

def connect_port_range_ok() -> Bool:
  connect_bad.on(connect_parse("h 0"))
    && connect_bad.on(connect_parse("h 99999"))
    && connect_bad.on(connect_parse("h 4294967295"))
    && connect_parse_ok.on(connect_parse("irc.example.net 6668"))

def connect_parse_ok() -> Bool:
  connect_parse_ok.on(connect_parse("irc.example.net 6668"))
    && connect_default_ok.on(connect_parse("irc.example.net"))
    && connect_port_range_ok()
