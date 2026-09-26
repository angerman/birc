# Inspectors and law predicates for Client (I15a).
import Base
import ./buffer.bend as Cl
import ./client.bend as Feed

# Trailing space is part of the feed_demo golden (`me alice `).
def show_nicks.chunks(+ns: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      (h ++ " ") <> show_nicks.chunks(t)

def show_nicks(+ns: List<&2, String>) -> String:
  String.concat(show_nicks.chunks(ns))

def show_buf.chan(+ch: Bool) -> String:
  match ch:
    case True{}:
      "#"
    case False{}:
      ""

def show_buf(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, +ch, +topic, +lines, +nicks, _}:
      String.concat(
        name
          <> show_buf.chan(ch)
          <> "{"
          <> topic
          <> "|"
          <> Nat.show(List.length(&2, Cl.Line, lines))
          <> "|"
          <> show_nicks(nicks)
          <> "}"
          <> Nil{}
      )

def show_bufs.chunks(+xs: List<&2, Cl.Buffer>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      (show_buf(h) ++ ";") <> show_bufs.chunks(t)

def show_bufs(+xs: List<&2, Cl.Buffer>) -> String:
  String.concat(show_bufs.chunks(xs))

def show_client(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, _}:
      String.concat(
        nick
          <> "@"
          <> server
          <> "["
          <> Nat.show(active)
          <> "]:"
          <> show_bufs(bufs)
          <> Nil{}
      )

def nbuf(+cl: Cl.Client) -> Nat:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _}:
      Cl.buf_count(bufs)

def buf_nlines.on(got: Maybe<&2, Cl.Buffer>) -> Nat:
  match got:
    case None{}:
      0n
    case Some{b}:
      match b:
        case Cl.Buffer{_, _, _, +lines, _, _}:
          List.length(&2, Cl.Line, lines)

def buf_nlines(+cl: Cl.Client, +i: Nat) -> Nat:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _}:
      buf_nlines.on(Cl.nth_buf(bufs, i))

def has_buf.on(found: Maybe<&2, Nat>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{_}:
      True{}

def has_buf(+cl: Cl.Client, +name: String) -> Bool:
  has_buf.on(Cl.buf_find(cl, name))

def buf_nicks.text(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _}:
      show_nicks(nicks)

def buf_nicks.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}:
      ""
    case Some{b}:
      buf_nicks.text(b)

def buf_nicks.idx(+cl: Cl.Client, +i: Nat) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _}:
      buf_nicks.got(Cl.nth_buf(bufs, i))

def buf_nicks.at(+cl: Cl.Client, found: Maybe<&2, Nat>) -> String:
  match found:
    case None{}:
      ""
    case Some{+i}:
      buf_nicks.idx(cl, i)

def buf_nicks(+cl: Cl.Client, +name: String) -> String:
  buf_nicks.at(cl, Cl.buf_find(cl, name))

# ---- law helpers (pure predicates) --------------------------------------

def feed_id(+cl: Cl.Client, +line: String) -> Bool:
  String.eq(show_client(cl), show_client(Feed.feed(cl, line)))

# M7.2 — flood JOIN past MAX_BUFFERS; buffer count stays capped.
def flood_join_line(+i: Nat) -> String:
  ":me!me@localhost JOIN #c" ++ Nat.show(i)

def flood_joins.go(n: Nat, +i: Nat, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+p:
      flood_joins.go(p, 1n+i, flood_join_line(i) <> acc)

def flood_joins(+n: Nat) -> List<&2, String>:
  flood_joins.go(n, 0n, Nil{})

# Extra self-JOINs past the cap log "buffer limit reached" on the server buffer.
def flood_server_clean() -> Bool:
  +one = Feed.feed(Cl.init("me", "s"), flood_join_line(0n))
  +many = Feed.feed_all(Cl.init("me", "s"), flood_joins(24n))
  Nat.is_gt(buf_nlines(many, 0n), buf_nlines(one, 0n))

def flood_buffers_capped() -> Bool:
  +many = Feed.feed_all(Cl.init("me", "s"), flood_joins(24n))
  Nat.is_le(nbuf(many), Cl.MAX_BUFFERS()) && flood_server_clean()

def notice_star_server() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":irc.example.net NOTICE * :*** Looking up")
  Nat.is_eq(nbuf(cl), 1n) && Nat.is_eq(buf_nlines(cl, 0n), 1n)

def privmsg_query_opens() -> Bool:
  Nat.is_eq(nbuf(Feed.feed(Cl.init("me", "s"), ":alice!a@h PRIVMSG me :hi")), 2n)

def lines_pipe.chunks(+xs: List<&2, Cl.Line>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{Cl.Line{_, _, +text}, t}:
      (text ++ "|") <> lines_pipe.chunks(t)

def lines_pipe(+xs: List<&2, Cl.Line>) -> String:
  String.concat(lines_pipe.chunks(xs))

def buf_texts.on(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}:
      ""
    case Some{b}:
      match b:
        case Cl.Buffer{_, _, _, +lines, _, _}:
          lines_pipe(lines)

def buf_texts(+cl: Cl.Client, +i: Nat) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _}:
      buf_texts.on(Cl.nth_buf(bufs, i))

# Self JOIN focuses #birc (index 1); next wraps to server (0), next again to 1.
def scroll_page_ok() -> Bool:
  +cl0 = Cl.set_active(Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc"), 1n)
  +cl1 = Cl.apply_active_scroll(cl0, 3n, 0n)
  Nat.is_eq(Cl.buf_scroll_of(cl1, 1n), 1n)

def nick_query_renames() -> Bool:
  +cl0 = Feed.feed(Cl.init("me", "s"), ":alice!a@h PRIVMSG me :hi")
  +cl = Feed.feed(cl0, ":alice!a@h NICK bob")
  has_buf(cl, "bob")
    && Bool.not(has_buf(cl, "alice"))
    && Nat.is_eq(nbuf(cl), 2n)

def quit_query_logs() -> Bool:
  +cl0 = Feed.feed(Cl.init("me", "s"), ":alice!a@h PRIVMSG me :hi")
  +cl = Feed.feed(cl0, ":alice!a@h QUIT :bye")
  Nat.is_eq(buf_nlines(cl, 1n), 2n)

def mode_channel_logs() -> Bool:
  +cl0 = Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc")
  +cl = Feed.feed(cl0, ":op!u@h MODE #birc +o alice")
  Nat.is_eq(buf_nlines(cl, 1n), 2n) && Nat.is_eq(buf_nlines(cl, 0n), 0n)

def part_nonmember_silent() -> Bool:
  +cl0 = Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc")
  +cl1 = Feed.feed(cl0, ":alice!a@h JOIN #birc")
  +cl = Feed.feed(cl1, ":bob!b@h PART #birc")
  Nat.is_eq(buf_nlines(cl, 1n), 2n)

def server_nick_query() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":server!s@h PRIVMSG me :hi")
  Nat.is_eq(nbuf(cl), 2n) && has_buf(cl, "server") && Nat.is_eq(buf_nlines(cl, 0n), 0n)

def self_priv_query() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":me!me@h PRIVMSG alice :hi")
  has_buf(cl, "alice") && Bool.not(has_buf(cl, "me"))

def snap_ok() -> Bool:
  +clq = Cl.set_active(Feed.feed(Cl.init("me", "s"), ":alice!a@h PRIVMSG me :hi"), 1n)
  +cl1 = Cl.apply_active_scroll(clq, 2n, 0n)
  +cl2 = Cl.snap_active(cl1)
  Nat.is_eq(Cl.buf_scroll_of(cl1, 1n), 1n) && Nat.is_eq(Cl.buf_scroll_of(cl2, 1n), 0n)

def cycle_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc")
  +c1 = Cl.cycle_tab(cl, Cl.TabNext{})
  +c2 = Cl.cycle_tab(c1, Cl.TabNext{})
  Nat.is_eq(Cl.active_of(cl), 1n) && Nat.is_eq(Cl.active_of(c1), 0n) && Nat.is_eq(Cl.active_of(c2), 1n)

# Newest line is last. Two query messages stay chronological.
def log_chrono_ok() -> Bool:
  String.eq(
    buf_texts(
      Feed.feed(Feed.feed(Cl.init("me", "s"), ":a!a@h PRIVMSG me :one"), ":a!a@h PRIVMSG me :two"),
      1n
    ),
    "<a> one|<a> two|"
  )

def welcome_server_line() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":irc.example.net 001 me :Welcome")
  Nat.is_eq(nbuf(cl), 1n) && Nat.is_eq(buf_nlines(cl, 0n), 1n)

def names_1459_ok() -> Bool:
  +cl = Feed.feed_all(
    Cl.init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":irc.birc.dev 353 me #birc :me alice" <> Nil{})
  Nat.is_eq(nbuf(cl), 2n) && has_buf(cl, "#birc") && Bool.not(has_buf(cl, "me alice")) && String.eq(buf_nicks(cl, "#birc"), "me alice ")

def kick_self_drops() -> Bool:
  +cl = Feed.feed_all(
    Cl.init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":op!u@h KICK #birc me :bye" <> Nil{})
  Nat.is_eq(nbuf(cl), 1n) && Bool.not(has_buf(cl, "#birc"))

def self_part_drops() -> Bool:
  +cl = Feed.feed_all(
    Cl.init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":me!me@localhost PART #birc" <> Nil{})
  Nat.is_eq(nbuf(cl), 1n) && Bool.not(has_buf(cl, "#birc"))


def log_ts_ok.pair(+ts0: String, rest: List<&2, Cl.Line>) -> Bool:
  match rest:
    case Con{Cl.Line{_, +ts1, _}, _}:
      String.eq(ts0, "01:02:03") && String.eq(ts1, "12:00:00")
    case _:
      False{}

def log_ts_ok.lines(+xs: List<&2, Cl.Line>) -> Bool:
  match xs:
    case Con{Cl.Line{_, +ts0, _}, rest}:
      log_ts_ok.pair(ts0, rest)
    case _:
      False{}

def log_ts_ok.buf(+b: Cl.Buffer) -> Bool:
  match b:
    case Cl.Buffer{_, _, _, +lines, _, _}:
      log_ts_ok.lines(lines)

def log_ts_ok.feed.got(got: Maybe<&2, Cl.Buffer>) -> Bool:
  match got:
    case Some{b}:
      match b:
        case Cl.Buffer{_, _, _, +lines, _, _}:
          match lines:
            case Con{Cl.Line{_, +ts, _}, _}:
              String.eq(ts, "12:00:00")
            case _:
              False{}
    case None{}:
      False{}

def log_ts_ok.feed.on(+cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _}:
      log_ts_ok.feed.got(Cl.nth_buf(bufs, 0n))

def log_ts_ok.feed() -> Bool:
  log_ts_ok.feed.on(Feed.feed(Cl.set_now(Cl.init("me", "s"), "12:00:00"), ":irc.example.net NOTICE * :hi"))

def log_ts_ok() -> Bool:
  +b1 = Cl.buf_log_ts(Cl.server_buf(), Cl.Msg{}, "01:02:03", "old")
  log_ts_ok.buf(Cl.buf_log_ts(b1, Cl.Msg{}, "12:00:00", "new")) && log_ts_ok.feed()
