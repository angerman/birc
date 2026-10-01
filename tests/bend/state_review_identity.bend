# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ./diagnostic_wire.bend as W
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as S
import ../../src/bend/session.bend as Sess

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def silent(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, Nil{}): True{}
    case _: False{}

def raw(+name: String) -> String:
  SCon{Chr{31}, name}

def wire_guards() -> IO(Unit):
  +base = Cl.client_set_sasl(Cl.init("account", "s"), "account", "secret")
  +logged = Cl.log_open(Cl.diagnostic(base, Cl.System{}, "account secret"))
  +ordinary = ":account!u@h JOIN #a" ++ raw("b")
  +joined = Feed.feed(Feed.feed(base, ordinary), ordinary)
  do IO<Unit>:
    Unit <- E.must("normalized reserved JOIN cannot create a local tab", W.unchanged(base, ":account!u@h JOIN " ++ raw("*log*")))
    Unit <- E.must("normalized reserved JOIN cannot mutate or duplicate existing log", W.unchanged(logged, ":account!u@h JOIN " ++ raw("*log*")))
    Unit <- E.must("normalized sender cannot create a local query", W.unchanged(base, ":" ++ raw("*settings*") ++ "!u@h PRIVMSG account :secret"))
    Unit <- E.must("normalized NICK cannot rename a query into log", W.unchanged(Feed.feed(base, ":alice!u@h PRIVMSG account :hi"), ":alice!u@h NICK :" ++ raw("*log*")))
    Unit <- E.must("literal reserved control stays blocked", W.unchanged(base, ":account!u@h JOIN *log*"))
    Unit <- E.must("normalization cannot create empty wire target", W.unchanged(base, ":account!u@h JOIN " ++ raw("")))
    Unit <- E.must("sanitized ordinary identity reuses one buffer", CL.has_buf(joined, "#ab") && Nat.is_eq(CL.nbuf(joined), 2n))
    Unit <- E.must("NOTICE star broadcast remains valid", String.contains(CL.buf_texts(Feed.feed(base, ":s NOTICE * :maintenance"), 0n), "maintenance"))
    Unit <- E.must_eq("diagnostic rows keep redaction", CL.buf_texts(logged, 1n), "[redacted] [redacted]|")
    IO.pure(Unit, Unit{})

def local_guards() -> IO(Unit):
  +base = Cl.init("me", "s")
  +search = client(S.submit(base, "/search hi"))
  +settings = client(S.submit(base, "/settings"))
  do IO<Unit>:
    Unit <- E.must("msg search is read-only", silent(S.submit(search, "/msg *search* text")))
    Unit <- E.must("query settings text is read-only", silent(S.submit(settings, "/query *settings* text")))
    Unit <- E.must("normalized msg local target is read-only", silent(S.submit(base, "/msg " ++ raw("*preview*") ++ " text")))
    Unit <- E.must("normalized empty msg target never sends", silent(S.submit(base, "/msg " ++ raw("") ++ " text")))
    Unit <- E.must("readonly rejection does not echo self", Bool.not(String.contains(CL.buf_texts(client(S.submit(search, "/msg *search* text")), 1n), "<me> text")))
    Unit <- E.must_eq("bodyless query can focus local log", Cl.active_buf_name(client(S.submit(Cl.log_open(base), "/query *log*"))), "*log*")
    Unit <- E.must("ordinary msg still sends", Bool.not(silent(S.submit(base, "/msg alice text"))))
    Unit <- E.must("ordinary channel query still sends", Bool.not(silent(S.submit(base, "/query #r text"))))
    IO.pure(Unit, Unit{})

def members(cl: Cl.Client) -> Cl.Client:
  Feed.feed_all(cl, [":me!u@h JOIN #r", ":s 353 me = #r :me alice bob", ":s 366 me #r :End", ":alice!u@h NICK :carol", ":bob!u@h QUIT :gone"])

def channel(got: Maybe<&2, Cl.Buffer>) -> Bool:
  match got:
    case Some{Cl.Buffer{_, ch, _, _, _, _}}: ch
    case None{}: False{}

def lifecycle(+command: String) -> IO(Unit):
  +created = client(S.submit(Cl.init("me", "s"), command))
  +after = members(client(S.submit(created, "/join #r")))
  do IO<Unit>:
    Unit <- E.must("channel identity at creation: " ++ command, channel(Cl.nth_buf(Cl.client_bufs(created), 1n)))
    Unit <- E.must_eq("channel lifecycle: " ++ command, CL.buf_nicks(after, "#r"), "me carol ")
    IO.pure(Unit, Unit{})

def unread(+cl: Cl.Client, name: String) -> U32:
  Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(cl)), name)

def close_guards() -> IO(Unit):
  +base = Cl.set_active(Feed.feed_all(Cl.init("me", "s"), [":alice!u@h PRIVMSG me :one", ":bob!u@h PRIVMSG me :two", ":carol!u@h PRIVMSG me :three"]), 1n)
  +closed = client(S.submit(base, "/close"))
  +last = Cl.drop_buf(Cl.set_active(base, 3n), 3n)
  +before = Cl.drop_buf(Cl.set_active(base, 2n), 1n)
  +session = Sess.session_cl(Sess.st_of_keys(Sess.step_enter(Sess.session_demo(base, "#r"), "/close")))
  do IO<Unit>:
    Unit <- E.must_eq("closing focused tab chooses next", Cl.active_buf_name(closed), "bob")
    Unit <- E.must("replacement is read; other tab remains unread", U32.is_eq(unread(closed, "bob"), 0) && U32.is_eq(unread(closed, "carol"), 2))
    Unit <- E.must_eq("closing last tab chooses previous", Cl.active_buf_name(last), "bob")
    Unit <- E.must("last replacement unread clears", U32.is_eq(unread(last, "bob"), 0))
    Unit <- E.must_eq("removing before active preserves focus", Cl.active_buf_name(before), "bob")
    Unit <- E.must("server cannot be removed", Nat.is_eq(CL.nbuf(Cl.drop_buf(base, 0n)), 4n))
    Unit <- E.must("Session close clears replacement unread", String.eq(Cl.active_buf_name(session), "bob") && U32.is_eq(unread(session, "bob"), 0))
    Unit <- E.must_eq("last chat falls back to server", Cl.active_buf_name(Cl.drop_buf(Feed.feed(Cl.init("me", "s"), ":alice!u@h PRIVMSG me :hi"), 1n)), "server")
    IO.pure(Unit, Unit{})

def promoted_fixture() -> Cl.Client:
  +base = Cl.init("me", "s")
  Cl.Client{"me", "s", Cl.server_buf() <> Cl.Buffer{"#r", False{}, "topic", Nil{}, ["#r", "alice"], Cl.ScrollAt{0n, 0n}} <> Nil{}, 0n, "", Cl.get_settings(base), Cl.AuthIdle{}, 0n}

def promotion_guard() -> IO(Unit):
  +after = members(Feed.feed(promoted_fixture(), ":me!u@h JOIN #r"))
  do IO<Unit>:
    Unit <- E.must("JOIN promotes retained legacy query channel", channel(Cl.nth_buf(Cl.client_bufs(after), 1n)))
    Unit <- E.must_eq("promotion removes query seed; member events work", CL.buf_nicks(after, "#r"), "carol me ")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    wire_guards()
    local_guards()
    lifecycle("/msg #r hi")
    lifecycle("/query #r hi")
    promotion_guard()
    close_guards()
    IO.print("state_review_identity=ok")
