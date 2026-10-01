# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/history.bend as H

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def wire(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, outs): String.join(outs, "|")

def text.got(+cl: Cl.Client, got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: ""
    case Some{i}: CL.buf_texts(cl, i)

def text(+cl: Cl.Client, +name: String) -> String:
  text.got(cl, Cl.buf_find(cl, name))

def join_guards() -> IO(Unit):
  +base = Cl.init("me", "irc.example")
  +sent = client(Sub.submit(base, "/join #a,#b keya,keyb"))
  +after = Feed.feed_all(sent, [":me!u@h JOIN #a", ":me!u@h JOIN #b", ":s 353 me = #b :me alice"])
  do IO<Unit>:
    Unit <- E.must("list JOIN creates actual targets, not a comma tab", CL.has_buf(sent, "#a") && CL.has_buf(sent, "#b") && Bool.not(CL.has_buf(sent, "#a,#b")))
    Unit <- E.must_eq("list JOIN keeps target/key order", wire(Sub.submit(base, "/join #a,#b keya,keyb")), "JOIN #a,#b keya,keyb")
    Unit <- E.must_eq("self JOIN/NAMES reuse both targets", Nat.show(CL.nbuf(after)), "3")
    Unit <- E.must_eq("NAMES applies to real channel", CL.buf_nicks(after, "#b"), "me alice ")
    Unit <- E.must_eq("empty key preserves positional mapping", wire(Sub.submit(base, "/join #a,#b ,keyb")), "JOIN #a,#b ,keyb")
    Unit <- E.must_eq("fewer keys remain legal", wire(Sub.submit(base, "/join #a,#b keya")), "JOIN #a,#b keya")
    Unit <- E.must_eq("ordinary keyed channel unchanged", wire(Sub.submit(base, "/join #a keya")), "JOIN #a keya")
    Unit <- E.must_eq("masked channel remains legal", wire(Sub.submit(base, "/join #room:*.fi")), "JOIN #room:*.fi")
    Unit <- E.must_eq("masked list target keeps key alignment", wire(Sub.submit(base, "/join #room:*.fi,#b keya,keyb")), "JOIN #room:*.fi,#b keya,keyb")
    Unit <- E.must_eq("empty target is rejected", wire(Sub.submit(base, "/join #a,,#b")), "")
    Unit <- E.must_eq("nonchannel list member is rejected", wire(Sub.submit(base, "/join #a,alice")), "")
    Unit <- E.must_eq("colon-led target is not a channel", wire(Sub.submit(base, "/join :#a")), "")
    Unit <- E.must_eq("bare channel prefix has no wire target", wire(Sub.submit(base, "/join #")), "")
    Unit <- E.must("bare prefix does not create a chat tab", Bool.not(CL.has_buf(client(Sub.submit(base, "/join #")), "#")))
    Unit <- E.must_eq("too many keys are rejected", wire(Sub.submit(base, "/join #a one,two")), "")
    Unit <- E.must("invalid list makes no partial chat tabs", Bool.not(CL.has_buf(client(Sub.submit(base, "/join #a,alice")), "#a")))
    IO.pure(Unit, Unit{})

def status_guards() -> IO(Unit):
  +base = Feed.feed(Cl.init("me", "irc.example"), ":me!u@h JOIN #room")
  +msg = client(Sub.submit(base, "/msg @#room ops only"))
  +query = client(Sub.submit(msg, "/query +#room voiced only"))
  +fresh = client(Sub.submit(Cl.init("me", "irc.example"), "/query @#room"))
  +incoming = Feed.feed(query, ":alice!u@h PRIVMSG @#room :reply")
  +restored = H.apply_history(base, H.parse_history_text("@#room\tMSG\t\told\n"), "", 10)
  do IO<Unit>:
    Unit <- E.must_eq("status msg preserves wire audience", wire(Sub.submit(base, "/msg @#room ops only")), "PRIVMSG @#room :ops only")
    Unit <- E.must_eq("status query preserves wire audience", wire(Sub.submit(msg, "/query +#room voiced only")), "PRIVMSG +#room :voiced only")
    Unit <- E.must_eq("status sends reuse channel identity", Nat.show(CL.nbuf(query)), "2")
    Unit <- E.must_eq("status query focuses canonical channel", Cl.active_buf_name(query), "#room")
    Unit <- E.must_eq("new status query stores canonical channel", Cl.active_buf_name(fresh), "#room")
    Unit <- E.must("generic lookup does not alias wire spelling", Bool.not(CL.has_buf(fresh, "@#room")))
    Unit <- E.must("incoming reply and local echo share channel", String.contains(text(incoming, "#room"), "ops only") && String.contains(text(incoming, "#room"), "voiced only") && String.contains(text(incoming, "#room"), "reply"))
    Unit <- E.must_eq("history uses the same channel key", Nat.show(CL.nbuf(restored)), "2")
    Unit <- E.must("restored status row enters the actual channel", String.contains(text(restored, "#room"), "old"))
    Unit <- E.must_eq("close parts the actual channel", wire(Sub.submit(fresh, "/close")), "PART #room")
    Unit <- E.must_eq("ordinary channel unchanged", wire(Sub.submit(base, "/msg #room all")), "PRIVMSG #room :all")
    Unit <- E.must_eq("plus CHANTYPE is not STATUSMSG", Cl.active_buf_name(client(Sub.submit(base, "/query +local"))), "+local")
    IO.pure(Unit, Unit{})

def notice_guards() -> IO(Unit):
  +base = Cl.init("me", "irc.example")
  +server = Feed.feed(base, ":irc.example NOTICE me :maintenance")
  +user = Feed.feed(base, ":irc.example!u@h NOTICE me :private user notice")
  +existing = client(Sub.submit(base, "/query irc.example"))
  +both = Feed.feed(existing, ":irc.example NOTICE me :server only")
  do IO<Unit>:
    Unit <- E.must_eq("directed server NOTICE does not create a writable query", Nat.show(CL.nbuf(server)), "1")
    Unit <- E.must("directed server NOTICE appears in control buffer", String.contains(CL.buf_texts(server, 0n), "maintenance"))
    Unit <- E.must("user notice with server-like nick stays private", CL.has_buf(user, "irc.example") && String.contains(text(user, "irc.example"), "private user notice"))
    Unit <- E.must("ambiguous bare nickname NOTICE stays private", CL.has_buf(Feed.feed(base, ":alice NOTICE me :bare user"), "alice"))
    Unit <- E.must("configured single-label server is a server source", Nat.is_eq(CL.nbuf(Feed.feed(Cl.init("me", "s"), ":s NOTICE me :single-label server")), 1n))
    Unit <- E.must("existing legal server-name query is not mutated", String.is_empty(text(both, "irc.example")))
    Unit <- E.must("tagged server NOTICE routes to control buffer", String.contains(CL.buf_texts(Feed.feed(base, "@time=2026-10-02T12:00:00Z :irc.example NOTICE me :tagged"), 0n), "tagged"))
    Unit <- E.must("NOTICE star broadcast preserved", String.contains(CL.buf_texts(Feed.feed(base, ":s NOTICE * :broadcast"), 0n), "broadcast"))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- join_guards()
    Unit <- status_guards()
    Unit <- notice_guards()
    IO.print("m21_targets=ok")
