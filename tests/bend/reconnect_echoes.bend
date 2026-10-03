# SPDX-License-Identifier: Apache-2.0
# Server echoes cannot replace newer accepted local membership intent.
import Base
import ./expect.bend as E
import ./reconnect_recovery.bend as R
import ./reconnect_auth.bend as A
import ../../src/bend/session.bend as Sess
import ../../src/bend/buffer.bend as Cl

def echo_controls() -> IO(Unit):
  +base = R.channels()
  do IO<Unit>:
    Unit <- E.must_eq("delayed self JOIN cannot revive explicit PART", R.wire(R.manual(R.state(R.chunk(R.enter(base, "/part #other"), ":me!u@h JOIN :#other\r\n")))), "JOIN #start|JOIN +#third")
    Unit <- E.must_eq("FIFO PART and JOIN echoes cannot erase newer key", R.wire(R.manual(R.state(R.chunk(R.enter(R.enter(base, "/part #other"), "/join #other new-key"), ":me!u@h PART #other\r\n:me!u@h JOIN :#other\r\n")))), "JOIN #start|JOIN +#third|JOIN #other new-key")
    Unit <- E.must_eq("normal JOIN echo preserves the accepted key", R.wire(R.manual(R.state(R.chunk(base, ":me!u@h JOIN :#other\r\n")))), "JOIN #start|JOIN #other secret-key|JOIN +#third")
    Unit <- E.must_eq("normal PART echo preserves removed intent", R.wire(R.manual(R.state(R.chunk(R.enter(base, "/part #other"), ":me!u@h PART #other\r\n")))), "JOIN #start|JOIN +#third")
    Unit <- E.must_eq("accepted raw JOIN also records runtime key", R.wire(R.manual(R.enter(base, "/raw JOIN #raw raw-key"))), "JOIN #start|JOIN #other secret-key|JOIN +#third|JOIN #raw raw-key")
    Unit <- E.must_eq("accepted raw PART also removes intent", R.wire(R.manual(R.enter(base, "/raw PART #other"))), "JOIN #start|JOIN +#third")
    IO.pure(Unit, Unit{})

def welcome_controls() -> IO(Unit):
  +st = Sess.session_with_client_at(Cl.init("me", "127.0.0.1"), "#start", 6667)
  do IO<Unit>:
    Unit <- E.must_eq("single-label server name may differ from dial host", R.wire(R.chunk(st, ":irc 001 me :welcome\r\n")), "JOIN #start")
    Unit <- E.must_eq("unprefixed welcome comes from the connection", R.wire(R.chunk(st, "001 me :welcome\r\n")), "JOIN #start")
    Unit <- E.must_eq("user-prefixed welcome cannot release JOIN", R.wire(R.chunk(st, ":peer!u@h 001 me :fake\r\n")), "")
    Unit <- E.must_eq("wrong recipient cannot release JOIN", R.wire(R.chunk(st, ":irc 001 other :fake\r\n")), "")
    Unit <- E.must_eq("malformed server prefix cannot release JOIN", R.wire(R.chunk(st, ":https://evil.test 001 me :fake\r\n")), "")
    IO.pure(Unit, Unit{})

def profile(mode: Cl.AuthMode) -> Sess.Session:
  Sess.session_reconnected(Sess.session_with_client_at(Cl.client_set_auth(Cl.init("me", "127.0.0.1"), mode, "127.0.0.1", 6667, A.prefix(), "Account confirmed", "account", "test-secret"), "#start", 6667), "12:00:00")

def nick_controls() -> IO(Unit):
  +st = profile(Cl.NickServOnly{})
  do IO<Unit>:
    Unit <- E.must_eq("NickServ probes for valid single-label welcome", R.wire(R.chunk(st, ":irc 001 me :welcome\r\n")), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("NickServ probes for valid unprefixed welcome", R.wire(R.chunk(st, "001 me :welcome\r\n")), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("peer welcome cannot trigger NickServ probe", R.wire(R.chunk(st, ":peer!u@h 001 me :fake\r\n")), "")
    Unit <- E.must_eq("other recipient cannot trigger NickServ probe", R.wire(R.chunk(st, ":irc 001 other :fake\r\n")), "")
    Unit <- E.must_eq("short-server welcome still requires exact NickServ identity", R.wire(R.chunk(R.state(R.chunk(st, ":irc 001 me :welcome\r\n")), ":NickServ!hostile@evil.test NOTICE me :Help\r\n")), "")
    Unit <- E.must_eq("valid service confirmation releases short-server welcome", R.wire(R.chunk(R.state(R.chunk(st, ":irc 001 me :welcome\r\n")), A.notice("Help") ++ A.notice("Account confirmed"))), "PRIVMSG NickServ :IDENTIFY account test-secret|JOIN #start")
    IO.pure(Unit, Unit{})

def sasl_controls() -> IO(Unit):
  +st = profile(Cl.SaslOnly{})
  +waiting = R.state(R.chunk(st, ":irc CAP me ACK :sasl\r\nAUTHENTICATE +\r\n"))
  do IO<Unit>:
    Unit <- E.must_eq("short-server SASL acknowledgement starts exchange", R.wire(R.chunk(st, ":irc CAP me ACK :sasl\r\n")), "AUTHENTICATE PLAIN")
    Unit <- E.must_eq("peer SASL acknowledgement cannot start exchange", R.wire(R.chunk(st, ":peer!u@h CAP me ACK :sasl\r\n")), "")
    Unit <- E.must_eq("wrong recipient SASL acknowledgement cannot start exchange", R.wire(R.chunk(st, ":irc CAP other ACK :sasl\r\n")), "")
    Unit <- E.must_eq("short-server SASL success advances once", A.seq(R.state(R.chunk(waiting, ":irc 903 me :ok\r\n:irc 903 me :duplicate\r\n"))), "1")
    Unit <- E.must_eq("unprefixed SASL success advances once", A.seq(R.state(R.chunk(waiting, "903 me :ok\r\n903 me :duplicate\r\n"))), "1")
    Unit <- E.must_eq("peer SASL success cannot advance", A.seq(R.state(R.chunk(waiting, ":peer!u@h 903 me :fake\r\n"))), "0")
    Unit <- E.must_eq("wrong recipient SASL success cannot advance", A.seq(R.state(R.chunk(waiting, ":irc 903 other :fake\r\n"))), "0")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- echo_controls()
    Unit <- welcome_controls()
    Unit <- nick_controls()
    Unit <- sasl_controls()
    IO.print("reconnect_echoes=ok")
