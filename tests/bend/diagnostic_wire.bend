# SPDX-License-Identifier: Apache-2.0
# Wire names cannot create, mutate, rename, close, or focus synthetic buffers.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/diagnostic.bend as D
import ../../src/bend/history.bend as H

def lines_signature(xs: List<&2, Cl.Line>) -> String:
  match xs:
    case Nil{}: ""
    case Con{Cl.Line{kind, ts, text, author, id}, tail}:
      H.serialize_kind(kind) ++ "|" ++ ts ++ "|" ++ text ++ "|" ++ author
        ++ "|" ++ Nat.show(id) ++ ";" ++ lines_signature(tail)

def buffers_signature(xs: List<&2, Cl.Buffer>) -> String:
  match xs:
    case Nil{}: ""
    case Con{Cl.Buffer{name, ch, topic, lines, nicks, Cl.ScrollAt{after, tail}, _, _}, rest}:
      name ++ Bool.pick(String, ch, "#", "-") ++ "{" ++ topic ++ "|"
        ++ String.join(nicks, ",") ++ "|" ++ Nat.show(after) ++ ":" ++ Nat.show(tail)
        ++ "|" ++ lines_signature(lines) ++ "}" ++ buffers_signature(rest)

def signature(cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{nick, server, bufs, active, now, _, _, seq}:
      nick ++ "@" ++ server ++ ":" ++ Nat.show(active) ++ ":" ++ now
        ++ ":" ++ Nat.show(seq) ++ ":" ++ buffers_signature(bufs)

def notices(+n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p: notices(p, Cl.diagnostic(cl, Cl.System{}, "safe " ++ Nat.show(n)))

def full_log() -> Cl.Client:
  Cl.set_active(notices(D.ROW_CAP(), Cl.client_set_sasl(
    Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #log"), "user", "secret")), 1n)

def topic() -> String:
  ":alice!u@h TOPIC *log* :secret https://offline.invalid/private"

def join() -> String:
  ":secret!u@h JOIN *LOG*"

def hostile() -> List<&2, String>:
  [topic(), join(), ":me!u@h JOIN *log*", ":alice!u@h PART *log* :secret",
   ":me!u@h PART *log*", ":alice!u@h KICK *log* alice :secret",
   ":alice!u@h KICK *log* me :secret",
   ":s 332 me *log* :secret https://offline.invalid/private",
   ":s 353 me = *log* :@secret alice", ":alice!u@h MODE *log* +o secret",
   ":me!u@h PRIVMSG *log* :secret https://offline.invalid/private",
   ":*log*!u@h PRIVMSG me :secret", ":*log*!u@h QUIT :secret",
   ":me!u@h JOIN *preview*",
   ":me!u@h JOIN *search*", ":me!u@h JOIN *settings*"]

def unchanged(+cl: Cl.Client, line: String) -> Bool:
  String.eq(signature(Feed.feed(cl, line)), signature(cl))

def blocked(lines: List<&2, String>, +cl: Cl.Client) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{+line, rest}:
      do IO<Unit>:
        Unit <- E.must("reserved wire event changed buffers: " ++ line, unchanged(cl, line))
        blocked(rest, cl)

def wire_get.got(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def last_text(xs: List<&2, Cl.Line>) -> String:
  match xs:
    case Nil{}: ""
    case Con{Cl.Line{_, _, text, _, _}, Nil{}}: text
    case Con{_, rest}: last_text(rest)

def lines_at.got(got: Maybe<&2, Cl.Buffer>) -> List<&2, Cl.Line>:
  match got:
    case None{}: Nil{}
    case Some{Cl.Buffer{_, _, _, lines, _, _, _, _}}: lines

def lines_at(cl: Cl.Client, i: Nat) -> List<&2, Cl.Line>:
  lines_at.got(Cl.nth_buf(Cl.client_bufs(cl), i))

def active_topic.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{_, _, topic, _, _, _, _, _}}: topic

def active_topic(+cl: Cl.Client) -> String:
  active_topic.got(Cl.nth_buf(Cl.client_bufs(cl), Cl.active_of(cl)))

def log_guard(+cl: Cl.Client) -> IO(Unit):
  +topic_ok = unchanged(cl, topic())
  +join_ok = unchanged(cl, join())
  do IO<Unit>:
    Unit <- E.must("TOPIC/JOIN isolation topic=" ++ Bool.pick(String, topic_ok, "ok", "bad")
      ++ " join=" ++ Bool.pick(String, join_ok, "ok", "bad"), topic_ok && join_ok)
    Unit <- E.must("fixture starts at full diagnostic cap", Nat.is_eq(CL.buf_nlines(cl, 2n), D.ROW_CAP()))
    Unit <- E.must_eq("log starts without a wire topic or nicks", CL.show_bufs(Cl.log_buffers(cl)), "*log*{|128|};")
    Unit <- blocked(hostile(), cl)
    Unit <- blocked(hostile(), Cl.drop_buf(cl, 2n))
    # Characterize a pre-fix contaminated log too: a non-self PART must not
    # delete its retained nick or add another raw System row.
    Unit <- E.must("PART cannot mutate a retained synthetic nick", unchanged(
      Cl.buf_modify_client(cl, 2n, b => Cl.nick_add(b, "alice")), ":alice!u@h PART *log*"))
    Unit <- E.must("wire cannot steal focus from active log", unchanged(Cl.log_open(cl), ":me!u@h PART *log*"))
    IO.pure(Unit, Unit{})

def nick_guard(+cl: Cl.Client) -> IO(Unit):
  +present = Feed.feed(cl, ":alice!u@h PRIVMSG me :query")
  +absent = Feed.feed(Cl.init("me", "s"), ":alice!u@h PRIVMSG me :query")
  +focused = Cl.log_open(present)
  +renamed = Feed.feed(focused, ":alice!u@h NICK :bob")
  do IO<Unit>:
    Unit <- E.must("NICK cannot duplicate existing log identity", unchanged(present, ":alice!u@h NICK :*log*"))
    Unit <- E.must("NICK cannot create absent log identity", unchanged(absent, ":alice!u@h NICK :*log*"))
    Unit <- E.must("self NICK cannot become a synthetic name", unchanged(cl, ":me!u@h NICK :*preview*"))
    Unit <- E.must("normal query rename still works", CL.has_buf(Feed.feed(absent, ":alice!u@h NICK :bob"), "bob"))
    Unit <- E.must("valid rename retains ordinary query text", String.contains(
      lines_signature(lines_at(Feed.feed(absent, ":alice!u@h NICK :bob"), 1n)), "<alice> query"))
    Unit <- E.must_eq("normal NICK preserves active synthetic focus", Cl.active_buf_name(renamed), "*log*")
    Unit <- E.must("normal NICK still renames while log is focused", CL.has_buf(renamed, "bob"))
    Unit <- E.must_eq("normal NICK leaves log rows unchanged", buffers_signature(Cl.log_buffers(renamed)), buffers_signature(Cl.log_buffers(focused)))
    IO.pure(Unit, Unit{})

def valid_channel() -> IO(Unit):
  +joined = Feed.feed(Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #log"), ":alice!u@h JOIN #log")
  +topic_set = Feed.feed(joined, ":alice!u@h TOPIC #log :ordinary topic")
  +numeric = Feed.feed(topic_set, ":s 332 me #log :numeric topic")
  +names = Feed.feed(numeric, ":s 353 me = #log :@bob alice")
  +mode = Feed.feed(names, ":alice!u@h MODE #log +o bob")
  do IO<Unit>:
    Unit <- E.must("valid self JOIN focuses #log", Nat.is_eq(Cl.active_of(joined), 1n))
    Unit <- E.must_eq("valid TOPIC is unchanged", active_topic(topic_set), "ordinary topic")
    Unit <- E.must_eq("valid 332 is unchanged", active_topic(numeric), "numeric topic")
    Unit <- E.must("valid 353 retains nicks", String.contains(CL.buf_nicks.idx(names, 1n), "bob "))
    Unit <- E.must_eq("valid MODE still logs", last_text(lines_at(mode, 1n)), "alice MODE #log +o bob")
    Unit <- E.must("valid PART removes a nick", Bool.not(String.contains(CL.buf_nicks.idx(Feed.feed(mode, ":alice!u@h PART #log"), 1n), "alice ")))
    Unit <- E.must("valid KICK removes a nick", Bool.not(String.contains(CL.buf_nicks.idx(Feed.feed(mode, ":alice!u@h KICK #log bob :bye"), 1n), "bob ")))
    Unit <- E.must("valid self PART closes channel", Bool.not(CL.has_buf(Feed.feed(mode, ":me!u@h PART #log"), "#log")))
    Unit <- E.must("ordinary channel events keep log lazy", Nat.is_eq(List.length(&2, Cl.Buffer, Cl.log_buffers(mode)), 0n))
    IO.pure(Unit, Unit{})

def valid_query_and_notice(+cl: Cl.Client) -> IO(Unit):
  +query = Feed.feed(Cl.init("me", "s"), ":server!u@h PRIVMSG me :query")
  +notice = Feed.feed(cl, ":server!u@h NOTICE * :maintenance")
  +local = wire_get.got(Cl.buf_get(Cl.init("me", "s"), "*search*", False{}, True{}))
  do IO<Unit>:
    Unit <- E.must("query named server remains distinct", CL.has_buf(query, "server") && Nat.is_eq(CL.nbuf(query), 2n))
    Unit <- E.must_eq("query named server receives messages", last_text(lines_at(query, 1n)), "<server> query")
    Unit <- E.must_eq("NOTICE star remains a server broadcast", last_text(lines_at(notice, 0n)), "<server> maintenance")
    Unit <- E.must("NOTICE star creates no buffer", Nat.is_eq(CL.nbuf(notice), CL.nbuf(cl)))
    Unit <- E.must("NOTICE star does not steal focus", Nat.is_eq(Cl.active_of(notice), Cl.active_of(cl)))
    Unit <- E.must_eq("NOTICE star does not change retained log", buffers_signature(Cl.log_buffers(notice)), buffers_signature(Cl.log_buffers(cl)))
    Unit <- E.must("local synthetic creation remains available", CL.has_buf(local, "*search*") && Nat.is_eq(CL.nbuf(local), 2n))
    Unit <- E.must_eq("local log can still open and focus", Cl.active_buf_name(Cl.log_open(local)), "*log*")
    IO.pure(Unit, Unit{})

def quit_while_log_focused(+cl: Cl.Client) -> IO(Unit):
  +focused = Cl.log_open(Feed.feed(cl, ":alice!u@h JOIN #log"))
  +left = Feed.feed(focused, ":alice!u@h QUIT :bye")
  do IO<Unit>:
    Unit <- E.must("reserved source QUIT leaves active log intact", unchanged(focused, ":*log*!u@h QUIT :secret"))
    Unit <- E.must_eq("normal source QUIT keeps log focused", Cl.active_buf_name(left), "*log*")
    Unit <- E.must_eq("normal source QUIT leaves log rows intact", buffers_signature(Cl.log_buffers(left)), buffers_signature(Cl.log_buffers(focused)))
    Unit <- E.must("normal source QUIT still removes channel nick", Bool.not(String.contains(CL.buf_nicks.idx(left, 1n), "alice ")))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  +cl = full_log()
  do IO<Unit>:
    Unit <- log_guard(cl)
    Unit <- nick_guard(cl)
    Unit <- valid_channel()
    Unit <- valid_query_and_notice(cl)
    Unit <- quit_while_log_focused(cl)
    IO.print("diagnostic_wire=ok\n")
