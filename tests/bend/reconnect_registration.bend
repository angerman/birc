# SPDX-License-Identifier: Apache-2.0
# The first trusted welcome establishes our nick, including on reconnect.
import Base
import ./expect.bend as E
import ./reconnect_recovery.bend as R
import ./reconnect_auth.bend as A
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess

# JOIN flush needs post-welcome MOTD (376/422), not 001 alone.
def welcome(+nick: String) -> String:
  ":irc.example 001 " ++ nick ++ " :welcome\r\n:irc.example 376 " ++ nick ++ " :end of MOTD\r\n"

def nick(st: Sess.Session) -> String:
  Cl.nick_of(Sess.session_cl(st))

def initial() -> Sess.Session:
  Sess.session_reconnected(Sess.session_with_client_at(Cl.init("me", "irc.example"), "#start", 6667), "12:00:00")

def automatic(+st: Sess.Session) -> Sess.Session:
  +cl = Sess.session_cl(st)
  +enabled = Sess.session_set_client(st, Cl.set_settings(cl, Cl.set_autoreconn(Cl.get_settings(cl), True{})))
  R.auto.up(Sess.session_autoreconnect(Sess.session_fail(enabled, "test disconnect")))

def sasl_waiting() -> Sess.Session:
  +good = R.state(R.chunk(A.profile(Cl.SaslOnly{}), A.sasl() ++ R.welcome()))
  +rooms = R.enter(good, "/join #other runtime-key")
  R.state(R.chunk(automatic(rooms), ":irc.example CAP me ACK :sasl\r\nAUTHENTICATE +\r\n"))

def success() -> String:
  ":irc.example 903 me :authenticated\r\n"

def notice(+recipient: String, +body: String) -> String:
  ":" ++ A.prefix() ++ " NOTICE " ++ recipient ++ " :" ++ body ++ "\r\n"

def registration_controls() -> IO(Unit):
  +st = initial()
  +assigned = R.state(R.chunk(st, welcome("Guest42")))
  do IO<Unit>:
    Unit <- E.must_eq("first trusted welcome accepts server-assigned nick and joins", R.wire(R.chunk(st, welcome("Guest42"))), "JOIN #start")
    Unit <- E.must_eq("assigned nick becomes our current identity", nick(assigned), "Guest42")
    Unit <- E.must_eq("duplicate welcome never rejoins", R.wire(R.chunk(assigned, welcome("Guest42"))), "")
    Unit <- E.must_eq("later welcome cannot change current identity", nick(R.state(R.chunk(assigned, welcome("other")))), "Guest42")
    Unit <- E.must_eq("peer-forged welcome cannot change identity", nick(R.state(R.chunk(st, ":peer!u@h 001 Guest42 :fake\r\n"))), "me")
    Unit <- E.must_eq("peer-forged welcome does not consume real welcome", R.wire(R.chunk(R.state(R.chunk(st, ":peer!u@h 001 Guest42 :fake\r\n")), R.welcome())), "JOIN #start")
    Unit <- E.must_eq("malformed server source cannot assign nick", nick(R.state(R.chunk(st, ":https://evil.test 001 Guest42 :fake\r\n"))), "me")
    Unit <- E.must_eq("missing welcome body does not release JOIN", R.wire(R.chunk(st, ":irc.example 001 me\r\n")), "")
    Unit <- E.must_eq("empty welcome body cannot assign nick", nick(R.state(R.chunk(st, ":irc.example 001 Guest42 :\r\n"))), "me")
    Unit <- E.must_eq("extra welcome parameters cannot assign nick", nick(R.state(R.chunk(st, ":irc.example 001 Guest42 extra :welcome\r\n"))), "me")
    Unit <- E.must_eq("channel is not a registration nickname", nick(R.state(R.chunk(st, welcome("#wrong")))), "me")
    Unit <- E.must_eq("broadcast is not a registration nickname", nick(R.state(R.chunk(st, welcome("*")))), "me")
    IO.pure(Unit, Unit{})

def framed_controls() -> IO(Unit):
  +partial = R.state(R.chunk(initial(), ":irc.example 001 Guest42 :wel"))
  +held = R.state(R.chunk(Sess.session_hold_joins(initial()), welcome("Guest42")))
  do IO<Unit>:
    Unit <- E.must_eq("partial welcome emits no JOIN", R.wire(R.chunk(initial(), ":irc.example 001 Guest42 :wel")), "")
    Unit <- E.must_eq("partial welcome leaves requested nick unchanged", nick(partial), "me")
    Unit <- E.must_eq("completed partial welcome assigns nick and joins", R.wire(R.chunk(partial, "come\r\n:irc.example 376 Guest42 :end of MOTD\r\n")), "JOIN #start")
    Unit <- E.must_eq("held welcome still establishes nickname", nick(held), "Guest42")
    Unit <- E.must_eq("held welcome cannot be replaced by a second assignment", nick(R.state(R.chunk(held, welcome("other")))), "Guest42")
    Unit <- E.must_eq("settings release uses accepted held welcome", R.wire(Sess.session_resume_joins(held)), "JOIN #start")
    IO.pure(Unit, Unit{})

def collision_controls() -> IO(Unit):
  +text: String = ":irc.example 433 * me :busy\r\n:irc.example 433 * me_ :busy\r\n"
  +collision = R.state(R.chunk(initial(), text))
  do IO<Unit>:
    Unit <- E.must_eq("nickname collisions send both retries", R.wire(R.chunk(initial(), text)), "NICK me_|NICK me__")
    Unit <- E.must_eq("nickname collision updates requested identity before welcome", nick(collision), "me__")
    Unit <- E.must_eq("nickname collision retry still rejoins", R.wire(R.chunk(collision, welcome("me__"))), "JOIN #start")
    IO.pure(Unit, Unit{})

def sasl_controls() -> IO(Unit):
  +waiting = sasl_waiting()
  +authenticated = R.state(R.chunk(waiting, success()))
  do IO<Unit>:
    Unit <- E.must_eq("automatic SASL reconnect coalesced assigned welcome rejoins all rooms and keys", R.wire(R.chunk(waiting, success() ++ welcome("Guest42"))), "CAP END|JOIN #start|JOIN #other runtime-key")
    Unit <- E.must_eq("automatic SASL reconnect split assigned welcome rejoins all rooms and keys", R.wire(R.chunk(authenticated, welcome("Guest42"))), "JOIN #start|JOIN #other runtime-key")
    Unit <- E.must_eq("SASL completes again on this connection", A.seq(R.state(R.chunk(authenticated, welcome("Guest42")))), "2")
    Unit <- E.must_eq("new nickname alone cannot bypass SASL confirmation", R.wire(R.chunk(waiting, welcome("Guest42"))), "")
    IO.pure(Unit, Unit{})

def nickserv_controls() -> IO(Unit):
  +st = A.profile(Cl.NickServOnly{})
  +probe = R.state(R.chunk(st, welcome("Guest42")))
  +identifying = R.state(R.chunk(probe, notice("Guest42", "Help")))
  do IO<Unit>:
    Unit <- E.must_eq("assigned nickname starts NickServ verification", R.wire(R.chunk(st, welcome("Guest42"))), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("old-recipient service probe cannot release password", R.wire(R.chunk(probe, notice("me", "Help"))), "")
    Unit <- E.must_eq("current-recipient service probe starts identify", R.wire(R.chunk(probe, notice("Guest42", "Help"))), "PRIVMSG NickServ :IDENTIFY account test-secret")
    Unit <- E.must_eq("old-recipient confirmation cannot release JOIN", R.wire(R.chunk(identifying, notice("me", "Account confirmed"))), "")
    Unit <- E.must_eq("current-recipient confirmation releases JOIN", R.wire(R.chunk(identifying, notice("Guest42", "Account confirmed"))), "JOIN #start")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- registration_controls()
    Unit <- framed_controls()
    Unit <- collision_controls()
    Unit <- sasl_controls()
    Unit <- nickserv_controls()
    IO.print("reconnect_registration=ok")
