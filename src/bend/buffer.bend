# Buffer container: types, nick lists, find/get/modify, scroll, take_last.
import Base
import ./irc.bend as Irc


def MAX_BUFFERS() -> Nat:
  16n

def SCROLL_CAP() -> Nat:
  1024n

def MAX_NICKS() -> Nat:
  256n

type LineKind is Data:
  Msg{}
  Self{}
  System{}
  Action{}
  Notice{}
  Error{}
  Highlight{}

type Line is Data:
  Line{kind: LineKind, ts: String, text: String}

type Buffer is Data:
  Buffer{
    name: String,
    is_channel: Bool,
    topic: String,
    lines: List<&2, Line>,
    nicks: List<&2, String>,
    scroll: Nat
  }

type Settings is Data:
  Settings{joins: Bool, ts: Bool, motd: Bool, history: Bool, hist_cap: U32, autoreconn: Bool, bell: Bool, mutes: List<&2, String>, unreads: List<&2, String>, sasl_user: String, sasl_pass: String, lag: U32}

def settings0() -> Settings:
  Settings{True{}, True{}, True{}, True{}, 500, False{}, True{}, Nil{}, Nil{}, "", "", 0}

def settings_with_cap(cap: U32) -> Settings:
  Settings{True{}, True{}, True{}, True{}, cap, False{}, True{}, Nil{}, Nil{}, "", "", 0}

def settings_joins(+s: Settings) -> Bool:
  match s:
    case Settings{joins, _, _, _, _, _, _, _, _, _, _, _}:
      joins

def settings_ts(+s: Settings) -> Bool:
  match s:
    case Settings{_, ts, _, _, _, _, _, _, _, _, _, _}:
      ts

def settings_motd(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, motd, _, _, _, _, _, _, _, _, _}:
      motd

def settings_history(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, _, history, _, _, _, _, _, _, _, _}:
      history

def settings_hist_cap(+s: Settings) -> U32:
  match s:
    case Settings{_, _, _, _, cap, _, _, _, _, _, _, _}:
      cap

def settings_autoreconn(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, _, _, _, auto, _, _, _, _, _, _}:
      auto

def settings_bell(+s: Settings) -> Bool:
  match s:
    case Settings{_, _, _, _, _, _, bell, _, _, _, _, _}:
      bell

def settings_mutes(+s: Settings) -> List<&2, String>:
  match s:
    case Settings{_, _, _, _, _, _, _, +mutes, _, _, _, _}:
      mutes

def settings_unreads(+s: Settings) -> List<&2, String>:
  match s:
    case Settings{_, _, _, _, _, _, _, _, +unreads, _, _, _}:
      unreads

def settings_sasl_user(+s: Settings) -> String:
  match s:
    case Settings{_, _, _, _, _, _, _, _, _, +su, _, _}:
      su

def settings_sasl_pass(+s: Settings) -> String:
  match s:
    case Settings{_, _, _, _, _, _, _, _, _, _, +sp, _}:
      sp

def settings_lag(+s: Settings) -> U32:
  match s:
    case Settings{_, _, _, _, _, _, _, _, _, _, _, lag}:
      lag

def set_joins(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{_, ts, motd, history, cap, auto, bell, +mutes, +unreads, +su, +sp, lag}:
      Settings{val, ts, motd, history, cap, auto, bell, mutes, unreads, su, sp, lag}

def set_ts(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, _, motd, history, cap, auto, bell, +mutes, +unreads, +su, +sp, lag}:
      Settings{joins, val, motd, history, cap, auto, bell, mutes, unreads, su, sp, lag}

def set_motd(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, _, history, cap, auto, bell, +mutes, +unreads, +su, +sp, lag}:
      Settings{joins, ts, val, history, cap, auto, bell, mutes, unreads, su, sp, lag}

def set_history(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, motd, _, cap, auto, bell, +mutes, +unreads, +su, +sp, lag}:
      Settings{joins, ts, motd, val, cap, auto, bell, mutes, unreads, su, sp, lag}

def set_hist_cap(+s: Settings, val: U32) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, _, auto, bell, +mutes, +unreads, +su, +sp, lag}:
      Settings{joins, ts, motd, history, val, auto, bell, mutes, unreads, su, sp, lag}

def set_autoreconn(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, _, bell, +mutes, +unreads, +su, +sp, lag}:
      Settings{joins, ts, motd, history, cap, val, bell, mutes, unreads, su, sp, lag}

def set_bell(+s: Settings, val: Bool) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, _, +mutes, +unreads, +su, +sp, lag}:
      Settings{joins, ts, motd, history, cap, auto, val, mutes, unreads, su, sp, lag}

def set_mutes(+s: Settings, +val: List<&2, String>) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, bell, _, +unreads, +su, +sp, lag}:
      Settings{joins, ts, motd, history, cap, auto, bell, val, unreads, su, sp, lag}

def set_unreads(+s: Settings, +val: List<&2, String>) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, bell, +mutes, _, +su, +sp, lag}:
      Settings{joins, ts, motd, history, cap, auto, bell, mutes, val, su, sp, lag}

def set_sasl_user(+s: Settings, +val: String) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, bell, +mutes, +unreads, _, +sp, lag}:
      Settings{joins, ts, motd, history, cap, auto, bell, mutes, unreads, val, sp, lag}

def set_sasl_pass(+s: Settings, +val: String) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, bell, +mutes, +unreads, +su, _, lag}:
      Settings{joins, ts, motd, history, cap, auto, bell, mutes, unreads, su, val, lag}

def set_lag(+s: Settings, lag: U32) -> Settings:
  match s:
    case Settings{joins, ts, motd, history, cap, auto, bell, +mutes, +unreads, +su, +sp, _}:
      Settings{joins, ts, motd, history, cap, auto, bell, mutes, unreads, su, sp, lag}

def mute_match(+m: String, +from: String, +chan: String, +server: String) -> Bool:
  Irc.ieq(m, from)
    || Irc.ieq(m, from ++ chan)
    || Irc.ieq(m, from ++ "@" ++ server)
    || Irc.ieq(m, from ++ chan ++ "@" ++ server)
    || Irc.ieq(m, from ++ "*@" ++ server)

def is_muted_list(mutes: List<&2, String>, +from: String, +chan: String, +server: String) -> Bool:
  match mutes:
    case Nil{}: False{}
    case Con{+m, t}:
      mute_match(m, from, chan, server) || is_muted_list(t, from, chan, server)

def add_mute_list(mutes: List<&2, String>, +pat: String) -> List<&2, String>:
  pat <> mutes

def del_mute_list.rest(tail: List<&2, String>, +m: String, hit: Bool) -> List<&2, String>:
  match hit:
    case True{}:
      tail
    case False{}:
      m <> tail

def del_mute_list(mutes: List<&2, String>, +pat: String) -> List<&2, String>:
  match mutes:
    case Nil{}: Nil{}
    case Con{+m, t}:
      +hit = Irc.ieq(m, pat) || String.starts_with(m, pat ++ "#") || String.starts_with(m, pat ++ "*")
      del_mute_list.rest(del_mute_list(t, pat), m, hit)

def line_from_nick(+ln: Line, +nick: String) -> Bool:
  match ln:
    case Line{kind, _, +text}:
      match kind:
        case Msg{}: String.starts_with(text, "<" ++ nick ++ ">")
        case Self{}: String.starts_with(text, "<" ++ nick ++ ">")
        case Action{}: String.starts_with(text, "* " ++ nick ++ " ")
        case Notice{}: String.starts_with(text, "-" ++ nick ++ "-")
        case Highlight{}: String.starts_with(text, "<" ++ nick ++ ">")
        case _: False{}

def is_mute_sep(+c: Char) -> Bool:
  Char.is_eq(c, '#') || Char.is_eq(c, '*') || Char.is_eq(c, '@')

def mute_pat_nick.fin(+h: Char, r: String, is_sep: Bool) -> String:
  match is_sep:
    case True{}: ""
    case False{}: SCon{h, r}

def mute_pat_nick(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+h, +t}:
      mute_pat_nick.fin(h, mute_pat_nick(t), is_mute_sep(h))

def is_line_muted_pat(+m: String, +ln: Line, +chan: String, +server: String) -> Bool:
  +nick = mute_pat_nick(m)
  mute_match(m, nick, chan, server) && line_from_nick(ln, nick)

def is_line_muted(mutes: List<&2, String>, +ln: Line, +chan: String, +server: String) -> Bool:
  match mutes:
    case Nil{}: False{}
    case Con{+m, t}:
      is_line_muted_pat(m, ln, chan, server) || is_line_muted(t, ln, chan, server)

def filter_muted_lines.rest(tail: List<&2, Line>, +ln: Line, muted: Bool) -> List<&2, Line>:
  match muted:
    case True{}: tail
    case False{}: ln <> tail

def filter_muted_lines(lines: List<&2, Line>, +mutes: List<&2, String>, +chan: String, +server: String) -> List<&2, Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+ln, t}:
      filter_muted_lines.rest(filter_muted_lines(t, mutes, chan, server), ln, is_line_muted(mutes, ln, chan, server))

def str_contains.step(hit: Bool, rest: Bool) -> Bool:
  match hit:
    case True{}: True{}
    case False{}: rest

def str_contains(haystack: String, +needle: String) -> Bool:
  match haystack:
    case SNil{}: False{}
    case SCon{+h, +t}:
      str_contains.step(String.starts_with(SCon{h, t}, needle), str_contains(t, needle))

def is_mention.on(empty: Bool, +body: String, +nick: String) -> Bool:
  match empty:
    case True{}: False{}
    case False{}:
      str_contains(Irc.rfc1459(body), Irc.rfc1459(nick))

def is_mention(+body: String, +nick: String) -> Bool:
  is_mention.on(String.is_empty(nick), body, nick)

def buf_unread_status.norm(is_norm: Bool) -> U32:
  match is_norm:
    case True{}: 1
    case False{}: 0

def buf_unread_status.hl(is_hl: Bool, is_norm: Bool) -> U32:
  match is_hl:
    case True{}: 2
    case False{}: buf_unread_status.norm(is_norm)

def buf_unread_status.item(+u: String, +name: String) -> U32:
  buf_unread_status.hl(String.eq(u, "!" ++ name), String.eq(u, name))

def buf_unread_status.pick(ge: Bool, +s1: U32, +s2: U32) -> U32:
  match ge:
    case True{}: s1
    case False{}: s2

def buf_unread_status.max(+s1: U32, +s2: U32) -> U32:
  buf_unread_status.pick(U32.is_ge(s1, s2), s1, s2)

def buf_unread_status(unreads: List<&2, String>, +name: String) -> U32:
  match unreads:
    case Nil{}: 0
    case Con{+u, t}:
      buf_unread_status.max(buf_unread_status.item(u, name), buf_unread_status(t, name))

def has_unread_item(unreads: List<&2, String>, +item: String) -> Bool:
  match unreads:
    case Nil{}: False{}
    case Con{+u, t}:
      String.eq(u, item) || has_unread_item(t, item)

def add_unread_item.on(has: Bool, unreads: List<&2, String>, +item: String) -> List<&2, String>:
  match has:
    case True{}: unreads
    case False{}: item <> unreads

def add_unread_item(+unreads: List<&2, String>, +item: String) -> List<&2, String>:
  add_unread_item.on(has_unread_item(unreads, item), unreads, item)

def del_unread_items.hit(tail: List<&2, String>, +u: String, hit: Bool) -> List<&2, String>:
  match hit:
    case True{}: tail
    case False{}: u <> tail

def del_unread_items(unreads: List<&2, String>, +name: String) -> List<&2, String>:
  match unreads:
    case Nil{}: Nil{}
    case Con{+u, t}:
      del_unread_items.hit(del_unread_items(t, name), u, String.eq(u, name) || String.eq(u, "!" ++ name))

def purge_nick_lines.rest(tail: List<&2, Line>, +h: Line, hit: Bool) -> List<&2, Line>:
  match hit:
    case True{}:
      tail
    case False{}:
      h <> tail

def purge_nick_lines(lines: List<&2, Line>, +nick: String) -> List<&2, Line>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      purge_nick_lines.rest(purge_nick_lines(t, nick), h, line_from_nick(h, nick))

def purge_nick_buf(b: Buffer, +nick: String) -> Buffer:
  match b:
    case Buffer{+name, is_ch, +topic, lines, +nicks, scroll}:
      Buffer{name, is_ch, topic, purge_nick_lines(lines, nick), nicks, scroll}

type Client is Data:
  Client{
    nick: String,
    server: String,
    bufs: List<&2, Buffer>,
    active: Nat,
    now: String,
    settings: Settings
  }

def is_muted_client(+cl: Client, +from: String, +chan: String) -> Bool:
  match cl:
    case Client{_, +server, _, _, _, +stg}:
      is_muted_list(settings_mutes(stg), from, chan, server)

def add_mute_client(+cl: Client, +pat: String) -> Client:
  match cl:
    case Client{+nick, +server, bufs, active, now, +stg}:
      Client{nick, server, bufs, active, now, set_mutes(stg, add_mute_list(settings_mutes(stg), pat))}

def del_mute_client(+cl: Client, +pat: String) -> Client:
  match cl:
    case Client{+nick, +server, bufs, active, now, +stg}:
      Client{nick, server, bufs, active, now, set_mutes(stg, del_mute_list(settings_mutes(stg), pat))}

# ---- init ---------------------------------------------------------------

def server_buf() -> Buffer:
  Buffer{"server", False{}, "", Nil{}, Nil{}, 0n}

def init(+nick: String, +server: String) -> Client:
  Client{nick, server, server_buf() <> Nil{}, 0n, "", settings0()}

def init_with_cap(+nick: String, +server: String, cap: U32) -> Client:
  Client{nick, server, server_buf() <> Nil{}, 0n, "", settings_with_cap(cap)}

def get_settings(+cl: Client) -> Settings:
  match cl:
    case Client{_, _, _, _, _, +stg}:
      stg

def set_settings(+cl: Client, +stg: Settings) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, _}:
      Client{nick, server, bufs, active, now, stg}

def client_sasl_user(+cl: Client) -> String:
  settings_sasl_user(get_settings(cl))

def client_sasl_pass(+cl: Client) -> String:
  settings_sasl_pass(get_settings(cl))

def client_lag(+cl: Client) -> U32:
  settings_lag(get_settings(cl))

def client_set_lag(+cl: Client, lag: U32) -> Client:
  set_settings(cl, set_lag(get_settings(cl), lag))

def client_set_sasl(+cl: Client, +u: String, +p: String) -> Client:
  set_settings(cl, set_sasl_pass(set_sasl_user(get_settings(cl), u), p))

def client_has_sasl(+cl: Client) -> Bool:
  Bool.not(String.is_empty(client_sasl_user(cl))) && Bool.not(String.is_empty(client_sasl_pass(cl)))

# ---- list helpers -------------------------------------------------------

def nth_buf(+bufs: List<&2, Buffer>, +i: Nat) -> Maybe<&2, Buffer>:
  List.get(&2, Buffer, bufs, i)

def buf_modify(xs: List<&2, Buffer>, n: Nat, f: Buffer -> Buffer) -> List<&2, Buffer>:
  match xs n:
    case Nil{} _:
      Nil{}
    case h <> t 0n:
      f(h) <> t
    case h <> t 1n+p:
      h <> buf_modify(t, p, f)

def buf_count(+bufs: List<&2, Buffer>) -> Nat:
  List.length(&2, Buffer, bufs)

def buf_clear(b: Buffer) -> Buffer:
  match b:
    case Buffer{+name, is_channel, +topic, _, +nicks, _}:
      Buffer{name, is_channel, topic, Nil{}, nicks, 0n}

def buf_clear_at(+cl: Client, +i: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      Client{nick, server, buf_modify(bufs, i, buf_clear), active, now, stg}

def buf_set_lines(lines: List<&2, Line>, b: Buffer) -> Buffer:
  match b:
    case Buffer{+name, is_channel, +topic, _, +nicks, _}:
      Buffer{name, is_channel, topic, lines, nicks, 0n}

def buf_set_lines_fn(lines: List<&2, Line>, b: Buffer) -> Buffer:
  buf_set_lines(lines, b)

def buf_set_lines_at(+cl: Client, +i: Nat, lines: List<&2, Line>) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      Client{nick, server, buf_modify(bufs, i, buf_set_lines_fn(lines)), active, now, stg}

def mark_unread.tag(is_hl: Bool, +name: String) -> String:
  match is_hl:
    case True{}: "!" ++ name
    case False{}: name

def mark_unread.check(is_server: Bool, is_hl: Bool, +name: String, +stg: Settings) -> Settings:
  match is_server:
    case True{}: stg
    case False{}:
      set_unreads(stg, add_unread_item(settings_unreads(stg), mark_unread.tag(is_hl, name)))

def mark_unread.buf(got: Maybe<&2, Buffer>, is_hl: Bool, +stg: Settings) -> Settings:
  match got:
    case None{}: stg
    case Some{b}:
      match b:
        case Buffer{+name, _, _, _, _, _}:
          mark_unread.check(String.eq(name, "server"), is_hl, name, stg)

def mark_unread_idx.on(is_active: Bool, got: Maybe<&2, Buffer>, is_hl: Bool, +stg: Settings) -> Settings:
  match is_active:
    case True{}: stg
    case False{}: mark_unread.buf(got, is_hl, stg)

def mark_unread_idx(+cl: Client, +i: Nat, is_hl: Bool) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +act, +now, +stg}:
      +stg2 = mark_unread_idx.on(Nat.is_eq(i, act), nth_buf(bufs, i), is_hl, stg)
      Client{nick, server, bufs, act, now, stg2}

def clear_unread(+cl: Client, +name: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +act, +now, +stg}:
      +stg2 = set_unreads(stg, del_unread_items(settings_unreads(stg), name))
      Client{nick, server, bufs, act, now, stg2}

# ---- buffer find/get ----------------------------------------------------

# Skip index 0 (the server buffer). First later match wins.
# One recursive call per step: Bool.pick evaluates both arms, so a recurse
# in each arm is exponential in the buffer count (X1 / I7).
def buf_find.rest(cont: Maybe<&2, Nat>, hit: Bool, +i: Nat) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      cont

def buf_find.go(xs: List<&2, Buffer>, +name: String, +i: Nat) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case Con{h, +t}:
      match h:
        case Buffer{+n, _, _, _, _, _}:
          buf_find.rest(buf_find.go(t, name, 1n+i), Irc.ieq(n, name), i)

def buf_find.skip0(xs: List<&2, Buffer>, +name: String) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case Con{_, t}:
      buf_find.go(t, name, 1n)

def buf_find(+cl: Client, +name: String) -> Maybe<&2, Nat>:
  match cl:
    case Client{_, _, +bufs, _, _, _}:
      buf_find.skip0(bufs, name)

def empty_buf.nicks.server(is_srv: Bool, +name: String) -> List<&2, String>:
  match is_srv:
    case True{}: Nil{}
    case False{}: Irc.sanitize_in(name) <> Nil{}

def empty_buf.nicks(+name: String, is_channel: Bool) -> List<&2, String>:
  match is_channel:
    case True{}: Nil{}
    case False{}:
      empty_buf.nicks.server(String.eq(name, "server") || String.starts_with(name, "*"), name)

def empty_buf(+name: String, +is_channel: Bool) -> Buffer:
  Buffer{Irc.sanitize_in(name), is_channel, "", Nil{}, empty_buf.nicks(name, is_channel), 0n}

def cap_note(+b: Buffer, +now: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, List.append(&2, Line, lines, Line{Error{}, Irc.sanitize_in(now), "buffer limit reached"} <> Nil{}), nicks, scroll}

def cap_at(+now: String, b: Buffer) -> Buffer:
  cap_note(b, now)

def buf_get.full(got: Maybe<&2, Buffer>, +nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings) -> Client & Maybe<&2, Nat>:
  match got:
    case None{}:
      (Client{nick, server, bufs, active, now, stg}, None{})
    case Some{_}:
      (Client{nick, server, buf_modify(bufs, 0n, cap_at(now)), active, now, stg}, None{})

def buf_get.create.cap(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +name: String, is_channel: Bool, full: Bool) -> Client & Maybe<&2, Nat>:
  match full:
    case True{}:
      buf_get.full(nth_buf(bufs, 0n), nick, server, bufs, active, now, stg)
    case False{}:
      +b = empty_buf(name, is_channel)
      +i = buf_count(bufs)
      +bufs2 = List.append(&2, Buffer, bufs, b <> Nil{})
      (Client{nick, server, bufs2, active, now, stg}, Some{i})

def buf_get.create(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +name: String, is_channel: Bool) -> Client & Maybe<&2, Nat>:
  buf_get.create.cap(nick, server, bufs, active, now, stg, name, is_channel, Nat.is_ge(buf_count(bufs), MAX_BUFFERS()))

def buf_get.miss(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +name: String, is_channel: Bool, create: Bool) -> Client & Maybe<&2, Nat>:
  match create:
    case False{}:
      (Client{nick, server, bufs, active, now, stg}, None{})
    case True{}:
      buf_get.create(nick, server, bufs, active, now, stg, name, is_channel)

def buf_get.found(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +name: String, is_channel: Bool, create: Bool, found: Maybe<&2, Nat>) -> Client & Maybe<&2, Nat>:
  match found:
    case Some{i}:
      (Client{nick, server, bufs, active, now, stg}, Some{i})
    case None{}:
      buf_get.miss(nick, server, bufs, active, now, stg, name, is_channel, create)

def buf_get.fin(+cl: Client, +name: String, is_channel: Bool, create: Bool, found: Maybe<&2, Nat>) -> Client & Maybe<&2, Nat>:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      buf_get.found(nick, server, bufs, active, now, stg, name, is_channel, create, found)

def buf_get(+cl: Client, +name: String, is_channel: Bool, create: Bool) -> Client & Maybe<&2, Nat>:
  buf_get.fin(cl, name, is_channel, create, buf_find(cl, name))

# ---- scrollback ---------------------------------------------------------

# Keep the last n lines in original order (oldest → newest).
def take_last(+xs: List<&2, Line>, n: Nat) -> List<&2, Line>:
  List.drop(&2, Line, xs, Nat.sub(List.length(&2, Line, xs), n))

def buf_log.scroll.on(gt: Bool, +scroll: Nat) -> Nat:
  match gt:
    case True{}:
      1n+scroll
    case False{}:
      0n

def buf_log.scroll(+scroll: Nat) -> Nat:
  buf_log.scroll.on(Nat.is_gt(scroll, 0n), scroll)

def buf_log_ts(+b: Buffer, kind: LineKind, +ts: String, +text: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      +lines2 = take_last(List.append(&2, Line, lines, Line{kind, Irc.sanitize_in(ts), Irc.sanitize_in(text)} <> Nil{}), SCROLL_CAP())
      Buffer{name, ch, topic, lines2, nicks, buf_log.scroll(scroll)}

# Tests pass ts="" (init.now is empty). Live/demo set Client.now at the IO
# edge before feed/submit so buf_log_ts stores HH:MM:SS at log time.
def buf_log(+b: Buffer, kind: LineKind, +text: String) -> Buffer:
  buf_log_ts(b, kind, "", text)

def buf_log_at(kind: LineKind, +ts: String, +text: String, b: Buffer) -> Buffer:
  buf_log_ts(b, kind, ts, text)

def client_log_ts.pick(empty: Bool, +ts: String, +now: String) -> String:
  match empty:
    case True{}:
      now
    case False{}:
      ts

def client_log_ts(+cl: Client, +i: Nat, kind: LineKind, +ts: String, +text: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      +ts_use = client_log_ts.pick(String.is_empty(ts), ts, now)
      Client{nick, server, buf_modify(bufs, i, buf_log_at(kind, ts_use, text)), active, now, stg}

def client_log(+cl: Client, +i: Nat, kind: LineKind, +text: String) -> Client:
  client_log_ts(cl, i, kind, "", text)

def buf_modify_client(+cl: Client, +i: Nat, f: Buffer -> Buffer) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      Client{nick, server, buf_modify(bufs, i, f), active, now, stg}

def purge_nick_from_active_buf(+cl: Client, +nick: String) -> Client:
  match cl:
    case Client{_, _, _, +active, _, _}:
      buf_modify_client(cl, active, b => purge_nick_buf(b, nick))

def set_now(+cl: Client, +ts: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, _, +stg}:
      Client{nick, server, bufs, active, ts, stg}

def replay_keep.cons(acc: List<&2, String>, +s: String, empty: Bool) -> List<&2, String>:
  match empty:
    case True{}:
      acc
    case False{}:
      s <> acc

def replay_step(acc: List<&2, String>, h: String) -> List<&2, String>:
  +s = Irc.strip_cr(h)
  replay_keep.cons(acc, s, String.is_empty(s))

def replay_lines(+text: String) -> List<&2, String>:
  List.reverse(&2, String, List.foldl(~&2, ~String, ~List<&2, String>, ~replay_step, String.lines(text), Nil{}))

# ---- nicks --------------------------------------------------------------

def is_sigil(+c: Char) -> Bool:
  Irc.code_is(c, 64) || Irc.code_is(c, 43) || Irc.code_is(c, 126) || Irc.code_is(c, 38) || Irc.code_is(c, 37)

def nick_strip(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, +t}:
      Bool.pick(String, is_sigil(h), nick_strip(t), SCon{h, t})

def nick_eq(a: String, b: String) -> Bool:
  Irc.ieq(a, b)

def nick_has(+b: Buffer, +nick: String) -> Bool:
  match b:
    case Buffer{_, _, _, _, +nicks, _}:
      List.contains(~String, ~nick_eq, nicks, nick)

def nick_add.keep(+b: Buffer, skip: Bool, +nick: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      match skip:
        case True{}:
          Buffer{name, ch, topic, lines, nicks, scroll}
        case False{}:
          Buffer{name, ch, topic, lines, List.append(&2, String, nicks, nick <> Nil{}), scroll}

def nick_add.body(+b: Buffer, +nick: String, empty: Bool) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      match empty:
        case True{}:
          Buffer{name, ch, topic, lines, nicks, scroll}
        case False{}:
          nick_add.keep(
            Buffer{name, ch, topic, lines, nicks, scroll},
            nick_has(Buffer{name, ch, topic, lines, nicks, scroll}, nick) || Nat.is_ge(List.length(&2, String, nicks), MAX_NICKS()),
            nick)

def nick_add(+b: Buffer, +raw: String) -> Buffer:
  +n = nick_strip(raw)
  nick_add.body(b, n, String.is_empty(n))

def nick_add_who(+who: String, b: Buffer) -> Buffer:
  nick_add(b, who)

def nick_add_idx(+cl: Client, +i: Nat, +who: String) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      Client{nick, server, buf_modify(bufs, i, nick_add_who(who)), active, now, stg}

def nick_add_step(b: Buffer, h: String) -> Buffer:
  +bb = b
  nick_add(bb, h)

def nick_add_all(+b: Buffer, +ns: List<&2, String>) -> Buffer:
  List.foldl(~&2, ~String, ~Buffer, ~nick_add_step, ns, b)

def nick_del.go(xs: List<&2, String>, +nick: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, +t}:
      Bool.pick(List<&2, String>, Irc.ieq(h, nick), t, h <> nick_del.go(t, nick))

def nick_del(+b: Buffer, +raw: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, lines, nick_del.go(nicks, nick_strip(raw)), scroll}

def nick_rename.go(xs: List<&2, String>, +from: String, +to: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, +t}:
      Bool.pick(List<&2, String>, Irc.ieq(h, from), to <> t, h <> nick_rename.go(t, from, to))

def nick_rename(+b: Buffer, +from: String, +to: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, lines, nick_rename.go(nicks, nick_strip(from), nick_strip(to)), scroll}

# ---- set topic / active / nick ------------------------------------------

def set_topic(+b: Buffer, +topic: String) -> Buffer:
  match b:
    case Buffer{+name, +ch, _, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, lines, nicks, scroll}

def set_active(+cl: Client, +i: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, _, +now, +stg}:
      Client{nick, server, bufs, i, now, stg}

def set_active_clamp.on(+cl: Client, +i: Nat, ok: Bool) -> Client:
  match ok:
    case True{}:
      set_active(cl, i)
    case False{}:
      cl

def set_active_clamp(+cl: Client, +i: Nat) -> Client:
  match cl:
    case Client{_, _, +bufs, _, _, _}:
      set_active_clamp.on(cl, i, Nat.is_lt(i, buf_count(bufs)))

def set_buf_scroll(+b: Buffer, +sc: Nat) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, _}:
      Buffer{name, ch, topic, lines, nicks, sc}

def set_buf_name(+b: Buffer, +name: String) -> Buffer:
  match b:
    case Buffer{_, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{name, ch, topic, lines, nicks, scroll}

def scroll_zero(b: Buffer) -> Buffer:
  set_buf_scroll(b, 0n)

def snap_active(+cl: Client) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      Client{nick, server, buf_modify(bufs, active, scroll_zero), active, now, stg}

def scroll_add_nat(+scroll: Nat, +up: Nat, +dn: Nat) -> Nat:
  Nat.sub(Nat.add(scroll, up), dn)

def clamp_nat.on(+n: Nat, +maxs: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      maxs
    case False{}:
      n

def clamp_nat(+n: Nat, +maxs: Nat) -> Nat:
  clamp_nat.on(n, maxs, Nat.is_ge(n, maxs))

def apply_buf_scroll.on(+b: Buffer, +up: Nat, +dn: Nat) -> Buffer:
  match b:
    case Buffer{+name, +ch, +topic, +lines, +nicks, +scroll}:
      Buffer{
        name,
        ch,
        topic,
        lines,
        nicks,
        clamp_nat(scroll_add_nat(scroll, up, dn), List.length(&2, Line, lines))
      }

def scroll_delta(+up: Nat, +dn: Nat, b: Buffer) -> Buffer:
  apply_buf_scroll.on(b, up, dn)

def apply_active_scroll(+cl: Client, +up: Nat, +dn: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      Client{nick, server, buf_modify(bufs, active, scroll_delta(up, dn)), active, now, stg}

def buf_scroll_of.on(got: Maybe<&2, Buffer>) -> Nat:
  match got:
    case None{}:
      0n
    case Some{b}:
      match b:
        case Buffer{_, _, _, _, _, +scroll}:
          scroll

def buf_scroll_of(+cl: Client, +i: Nat) -> Nat:
  match cl:
    case Client{_, _, +bufs, _, _, _}:
      buf_scroll_of.on(nth_buf(bufs, i))

def active_of(+cl: Client) -> Nat:
  match cl:
    case Client{_, _, _, +active, _, _}:
      active

def cycle_next.i.on(wrap: Bool, +active: Nat) -> Nat:
  match wrap:
    case True{}:
      0n
    case False{}:
      Nat.add(active, 1n)

def cycle_next.i(+active: Nat, +n: Nat) -> Nat:
  cycle_next.i.on(Nat.is_eq(Nat.add(active, 1n), n), active)

def cycle_prev.i.on(z: Bool, +active: Nat, +n: Nat) -> Nat:
  match z:
    case True{}:
      Nat.sub(n, 1n)
    case False{}:
      Nat.sub(active, 1n)

def cycle_prev.i(+active: Nat, +n: Nat) -> Nat:
  cycle_prev.i.on(Nat.is_eq(active, 0n), active, n)

def cycle_next(+cl: Client) -> Client:
  match cl:
    case Client{_, _, +bufs, +active, _, _}:
      set_active(cl, cycle_next.i(active, buf_count(bufs)))

def cycle_prev(+cl: Client) -> Client:
  match cl:
    case Client{_, _, +bufs, +active, _, _}:
      set_active(cl, cycle_prev.i(active, buf_count(bufs)))

type TabDir is Data:
  TabStay{}
  TabNext{}
  TabPrev{}

def tab_dir.on(+n: U32, next: Bool, prev: Bool) -> TabDir:
  match next:
    case True{}:
      TabNext{}
    case False{}:
      match prev:
        case True{}:
          TabPrev{}
        case False{}:
          TabStay{}

def tab_dir(+n: U32) -> TabDir:
  tab_dir.on(n, U32.is_eq(n, 1), U32.is_eq(n, 2))

def cycle_tab(+cl: Client, dir: TabDir) -> Client:
  match dir:
    case TabStay{}:
      cl
    case TabNext{}:
      cycle_next(cl)
    case TabPrev{}:
      cycle_prev(cl)

def set_nick(+cl: Client, +nick: String) -> Client:
  match cl:
    case Client{_, +server, +bufs, +active, +now, +stg}:
      Client{nick, server, bufs, active, now, stg}

def set_server(+cl: Client, +server: String) -> Client:
  match cl:
    case Client{+nick, _, +bufs, +active, +now, +stg}:
      Client{nick, server, bufs, active, now, stg}

# ---- drop buffer (PART/KICK self) ---------------------------------------

def remove_buf(+bufs: List<&2, Buffer>, +i: Nat) -> List<&2, Buffer>:
  +xs = bufs
  List.append(&2, Buffer, List.take(&2, Buffer, xs, i), List.drop(&2, Buffer, xs, 1n+i))

def clamp_active.pick(+last: Nat, +active: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      last
    case False{}:
      active

def clamp_active.ge(+nbufs: Nat, +active: Nat, ge: Bool) -> Nat:
  match nbufs:
    case 0n:
      0n
    case 1n+p:
      clamp_active.pick(p, active, ge)

def clamp_active(+nbufs: Nat, +active: Nat) -> Nat:
  clamp_active.ge(nbufs, active, Nat.is_ge(active, nbufs))

def drop_buf.act(+active: Nat, +bi: Nat, +nbufs2: Nat, shift: Bool) -> Nat:
  match shift:
    case True{}:
      Nat.sub(active, 1n)
    case False{}:
      clamp_active(nbufs2, active)

def drop_buf.go(+nick: String, +server: String, +bufs: List<&2, Buffer>, +active: Nat, +now: String, +stg: Settings, +bi: Nat) -> Client:
  +bufs2 = remove_buf(bufs, bi)
  Client{nick, server, bufs2, drop_buf.act(active, bi, buf_count(bufs2), Nat.is_gt(active, bi)), now, stg}

def drop_buf.body(+cl: Client, +bi: Nat) -> Client:
  match cl:
    case Client{+nick, +server, +bufs, +active, +now, +stg}:
      drop_buf.go(nick, server, bufs, active, now, stg, bi)

def drop_buf.keep(+cl: Client, +bi: Nat, is_server: Bool) -> Client:
  match is_server:
    case True{}:
      cl
    case False{}:
      drop_buf.body(cl, bi)

def drop_buf(+cl: Client, +bi: Nat) -> Client:
  drop_buf.keep(cl, bi, Nat.is_eq(bi, 0n))

def drop_buf.at(+cl: Client, found: Maybe<&2, Nat>) -> Client:
  match found:
    case None{}:
      cl
    case Some{+bi}:
      drop_buf(cl, bi)


def nick_of(+cl: Client) -> String:
  match cl:
    case Client{+nick, _, _, _, _, _}:
      nick

def server_of(+cl: Client) -> String:
  match cl:
    case Client{_, +server, _, _, _, _}:
      server

def active_nicks.on(got: Maybe<&2, Buffer>) -> List<&2, String>:
  match got:
    case None{}:
      Nil{}
    case Some{b}:
      match b:
        case Buffer{_, _, _, _, +nicks, _}:
          nicks

def active_nicks(+cl: Client) -> List<&2, String>:
  match cl:
    case Client{_, _, +bufs, +active, _, _}:
      active_nicks.on(nth_buf(bufs, active))

def active_buf_name.on(got: Maybe<&2, Buffer>) -> String:
  match got:
    case None{}:
      "server"
    case Some{b}:
      match b:
        case Buffer{+name, _, _, _, _, _}:
          name

def active_buf_name(+cl: Client) -> String:
  match cl:
    case Client{_, _, +bufs, +active, _, _}:
      active_buf_name.on(nth_buf(bufs, active))

def active_buf_lines.on(got: Maybe<&2, Buffer>) -> List<&2, Line>:
  match got:
    case None{}:
      Nil{}
    case Some{b}:
      match b:
        case Buffer{_, _, _, +lines, _, _}:
          lines

def active_buf_lines(+cl: Client) -> List<&2, Line>:
  match cl:
    case Client{_, _, +bufs, +active, _, _}:
      active_buf_lines.on(nth_buf(bufs, active))

def client_bufs(+cl: Client) -> List<&2, Buffer>:
  match cl:
    case Client{_, _, +bufs, _, _, _}:
      bufs


