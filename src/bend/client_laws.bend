# Inspectors and law predicates for Client (I15a).
import Base
import ./irc.bend as Irc
import ./client.bend as Cl

def show_nicks.go(fuel: Nat, +ns: List<&2, String>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match ns:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_nicks.go(p, t, acc ++ h ++ " ")

def show_nicks(+ns: List<&2, String>) -> String:
  show_nicks.go(Nat.add(1n, List.length(&2, String, ns)), ns, "")

def show_buf.chan(+ch: Bool) -> String:
  match ch:
    case True{}:
      "#"
    case False{}:
      ""

def show_buf(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, +ch, +topic, +lines, +nicks, _}:
      name
        ++ show_buf.chan(ch)
        ++ "{" ++ topic ++ "|"
        ++ Nat.show(List.length(&2, Cl.Line, lines)) ++ "|"
        ++ show_nicks(nicks) ++ "}"

def show_bufs.go(fuel: Nat, +xs: List<&2, Cl.Buffer>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_bufs.go(p, t, acc ++ show_buf(h) ++ ";")

def show_bufs(+xs: List<&2, Cl.Buffer>) -> String:
  show_bufs.go(Nat.add(1n, Cl.buf_count(xs)), xs, "")

def show_client(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _}:
      nick ++ "@" ++ server ++ "[" ++ Nat.show(active) ++ "]:" ++ show_bufs(bufs)

def nbuf(+cl: Cl.Client) -> Nat:
  match cl:
    case Cl.Client{_, _, +bufs, _, _}:
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
    case Cl.Client{_, _, +bufs, _, _}:
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
    case Cl.Client{_, _, +bufs, _, _}:
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
  String.eq(show_client(cl), show_client(Cl.feed(cl, line)))

# M7.2 — flood JOIN past MAX_BUFFERS; buffer count stays capped.
def flood_join_line(+i: Nat) -> String:
  ":me!me@localhost JOIN #c" ++ Nat.show(i)

def flood_joins.go(fuel: Nat, +i: Nat, acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+p:
      flood_joins.go(p, 1n+i, flood_join_line(i) <> acc)

def flood_joins(+n: Nat) -> List<&2, String>:
  flood_joins.go(n, 0n, Nil{})

# Extra self-JOINs past the cap log "buffer limit reached" on the server buffer.
def flood_server_clean() -> Bool:
  +one = Cl.feed(Cl.init("me", "s"), flood_join_line(0n))
  +many = Cl.feed_all(Cl.init("me", "s"), flood_joins(24n))
  Nat.is_gt(buf_nlines(many, 0n), buf_nlines(one, 0n))

def flood_buffers_capped() -> Bool:
  +many = Cl.feed_all(Cl.init("me", "s"), flood_joins(24n))
  Nat.is_le(nbuf(many), Cl.MAX_BUFFERS()) && flood_server_clean()

def notice_star_server() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":irc.example.net NOTICE * :*** Looking up")
  Nat.is_eq(nbuf(cl), 1n) && Nat.is_eq(buf_nlines(cl, 0n), 1n)

def privmsg_query_opens() -> Bool:
  Nat.is_eq(nbuf(Cl.feed(Cl.init("me", "s"), ":alice!a@h PRIVMSG me :hi")), 2n)

def lines_pipe.go(fuel: Nat, +xs: List<&2, Cl.Line>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{Cl.Line{_, _, +text}, t}:
          lines_pipe.go(p, t, acc ++ text ++ "|")

def lines_pipe(+xs: List<&2, Cl.Line>) -> String:
  lines_pipe.go(Nat.add(1n, List.length(&2, Cl.Line, xs)), xs, "")

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
    case Cl.Client{_, _, +bufs, _, _}:
      buf_texts.on(Cl.nth_buf(bufs, i))

# Self JOIN focuses #birc (index 1); next wraps to server (0), next again to 1.
def scroll_page_ok() -> Bool:
  +cl0 = Cl.set_active(Cl.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc"), 1n)
  +cl1 = Cl.apply_active_scroll(cl0, 3n, 0n)
  Nat.is_eq(Cl.buf_scroll_of(cl1, 1n), 1n)

def nick_query_renames() -> Bool:
  +cl0 = Cl.feed(Cl.init("me", "s"), ":alice!a@h PRIVMSG me :hi")
  +cl = Cl.feed(cl0, ":alice!a@h NICK bob")
  has_buf(cl, "bob")
    && Bool.not(has_buf(cl, "alice"))
    && Nat.is_eq(nbuf(cl), 2n)

def quit_query_logs() -> Bool:
  +cl0 = Cl.feed(Cl.init("me", "s"), ":alice!a@h PRIVMSG me :hi")
  +cl = Cl.feed(cl0, ":alice!a@h QUIT :bye")
  Nat.is_eq(buf_nlines(cl, 1n), 2n)

def mode_channel_logs() -> Bool:
  +cl0 = Cl.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc")
  +cl = Cl.feed(cl0, ":op!u@h MODE #birc +o alice")
  Nat.is_eq(buf_nlines(cl, 1n), 2n) && Nat.is_eq(buf_nlines(cl, 0n), 0n)

def part_nonmember_silent() -> Bool:
  +cl0 = Cl.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc")
  +cl1 = Cl.feed(cl0, ":alice!a@h JOIN #birc")
  +cl = Cl.feed(cl1, ":bob!b@h PART #birc")
  Nat.is_eq(buf_nlines(cl, 1n), 2n)

def server_nick_query() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":server!s@h PRIVMSG me :hi")
  Nat.is_eq(nbuf(cl), 2n) && has_buf(cl, "server") && Nat.is_eq(buf_nlines(cl, 0n), 0n)

def ieq_rfc1459_ok() -> Bool:
  Irc.ieq("foo[]", "foo{}") && Irc.ieq("A\\B", "a|b")

def self_priv_query() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":me!me@h PRIVMSG alice :hi")
  has_buf(cl, "alice") && Bool.not(has_buf(cl, "me"))

def scroll_clamp_ok() -> Bool:
  +cl0 = Cl.set_active(Cl.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc"), 1n)
  +cl1 = Cl.apply_active_scroll(cl0, 50n, 0n)
  Nat.is_eq(Cl.buf_scroll_of(cl1, 1n), buf_nlines(cl1, 1n))

def bare_join_ok() -> Bool:
  Nat.is_eq(nbuf(Cl.feed(Cl.init("me", "s"), ":me!me@localhost JOIN")), 1n)

def snap_ok() -> Bool:
  +clq = Cl.set_active(Cl.feed(Cl.init("me", "s"), ":alice!a@h PRIVMSG me :hi"), 1n)
  +cl1 = Cl.apply_active_scroll(clq, 2n, 0n)
  +cl2 = Cl.snap_active(cl1)
  Nat.is_eq(Cl.buf_scroll_of(cl1, 1n), 1n) && Nat.is_eq(Cl.buf_scroll_of(cl2, 1n), 0n)

def cycle_ok() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc")
  +c1 = Cl.cycle_tab(cl, 1)
  +c2 = Cl.cycle_tab(c1, 1)
  Nat.is_eq(Cl.active_of(cl), 1n) && Nat.is_eq(Cl.active_of(c1), 0n) && Nat.is_eq(Cl.active_of(c2), 1n)

# Newest line is last. Two query messages stay chronological.
def log_chrono_ok() -> Bool:
  String.eq(
    buf_texts(
      Cl.feed(Cl.feed(Cl.init("me", "s"), ":a!a@h PRIVMSG me :one"), ":a!a@h PRIVMSG me :two"),
      1n
    ),
    "<a> one|<a> two|"
  )

def welcome_server_line() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":irc.example.net 001 me :Welcome")
  Nat.is_eq(nbuf(cl), 1n) && Nat.is_eq(buf_nlines(cl, 0n), 1n)

def names_1459_ok() -> Bool:
  +cl = Cl.feed_all(
    Cl.init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":irc.birc.dev 353 me #birc :me alice" <> Nil{})
  Nat.is_eq(nbuf(cl), 2n) && has_buf(cl, "#birc") && Bool.not(has_buf(cl, "me alice")) && String.eq(buf_nicks(cl, "#birc"), "me alice ")

def statusmsg_ok() -> Bool:
  +cl = Cl.feed_all(
    Cl.init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":op!u@h PRIVMSG @#birc :ops" <> Nil{})
  Nat.is_eq(nbuf(cl), 2n) && has_buf(cl, "#birc") && Bool.not(has_buf(cl, "@#birc")) && Nat.is_eq(buf_nlines(cl, 1n), 2n)

def notice_auth_ok() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":irc NOTICE AUTH :hi")
  Nat.is_eq(nbuf(cl), 1n) && Nat.is_eq(buf_nlines(cl, 0n), 1n)

def kick_self_drops() -> Bool:
  +cl = Cl.feed_all(
    Cl.init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":op!u@h KICK #birc me :bye" <> Nil{})
  Nat.is_eq(nbuf(cl), 1n) && Bool.not(has_buf(cl, "#birc"))

def self_part_drops() -> Bool:
  +cl = Cl.feed_all(
    Cl.init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":me!me@localhost PART #birc" <> Nil{})
  Nat.is_eq(nbuf(cl), 1n) && Bool.not(has_buf(cl, "#birc"))


def numeric_last_ok() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":irc.example.net 403 me #nope :No such channel")
  String.eq(buf_texts(cl, 0n), "[403] No such channel|")

# After registration, 433 me newnick is a rejected /nick: stay me, only log.
def nick433_ok() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":irc.example.net 433 me newnick :Nickname is already in use")
  String.eq(Cl.nick_of(cl), "me") && String.eq(buf_texts(cl, 0n), "[433] Nickname is already in use|")

# Registration: 433 * me and 433 me me mean our nick is taken; retry as me_.
def nick433_star_ok() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":irc.example.net 433 * me :Nickname is already in use")
  String.eq(Cl.nick_of(cl), "me_") && String.eq(buf_texts(cl, 0n), "[433] Nickname is already in use|")

def nick433_same_ok() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":irc.example.net 433 me me :Nickname is already in use")
  String.eq(Cl.nick_of(cl), "me_") && String.eq(buf_texts(cl, 0n), "[433] Nickname is already in use|")

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
    case Cl.Client{_, _, +bufs, _, _}:
      log_ts_ok.feed.got(Cl.nth_buf(bufs, 0n))

def log_ts_ok.feed() -> Bool:
  log_ts_ok.feed.on(Cl.feed(Cl.set_now(Cl.init("me", "s"), "12:00:00"), ":irc.example.net NOTICE * :hi"))

def log_ts_ok() -> Bool:
  +b1 = Cl.buf_log_ts(Cl.server_buf(), Cl.Msg{}, "01:02:03", "old")
  log_ts_ok.buf(Cl.buf_log_ts(b1, Cl.Msg{}, "12:00:00", "new")) && log_ts_ok.feed()
