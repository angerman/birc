# Demo fixtures must use the requested identity; real welcomes still own it.
import Base
import ./expect.bend as E
import ../../src/bend/app.bend as App
import ../../src/bend/client.bend as Feed
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess

def dial_nick(got: Sess.Session & Sess.NetCmd & Bool, +nick: String) -> Bool:
  match got:
    case (_, Sess.Dial{"127.0.0.1", 16667, _, +got_nick}, False{}):
      String.eq(nick, got_nick)
    case _: False{}

def check(+nick: String) -> IO(Unit):
  do IO<Unit>:
    +cl : Cl.Client <- App.demo_client(nick)
    Unit <- E.must("demo welcome preserves requested nick", String.eq(Cl.nick_of(cl), nick))
    Unit <- E.must("demo dial uses the client identity", dial_nick(Sess.step_enter(Sess.session_demo(cl, "#t"), "/connect 127.0.0.1 16667"), nick))
    +conflict : Cl.Client = Feed.feed(cl, ":irc.birc.dev 001 accepted :Welcome")
    Unit <- E.must("later conflicting welcome keeps first nick", String.eq(Cl.nick_of(conflict), nick))
    +fresh : Cl.Client = Feed.feed(Cl.init(nick, "s"), ":irc.birc.dev 001 accepted :Welcome")
    Unit <- E.must("first real welcome can change the nick", String.eq(Cl.nick_of(fresh), "accepted"))
    E.must("later dial uses first welcome identity", dial_nick(Sess.step_enter(Sess.session_demo(conflict, "#t"), "/connect 127.0.0.1 16667"), nick))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- check("bob")
    Unit <- check("me")
    Unit <- check("probe^")
    IO.print("demo_identity=ok")
