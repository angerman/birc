# SPDX-License-Identifier: Apache-2.0
# A previous connection's auth success cannot release this connection's JOINs.
import Base
import ./expect.bend as E
import ./reconnect_recovery.bend as R
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess

def prefix() -> String:
  "NickServ!service@services.example"

def profile(mode: Cl.AuthMode) -> Sess.Session:
  Sess.session_reconnected(Sess.session_with_client_at(Cl.client_set_auth(Cl.init("me", "irc.example"), mode, "irc.example", 6667, prefix(), "Account confirmed", "account", "test-secret"), "#start", 6667), "12:00:00")

def notice(body: String) -> String:
  ":" ++ prefix() ++ " NOTICE me :" ++ body ++ "\r\n"

def seq(st: Sess.Session) -> String:
  Nat.show(Cl.auth_success_seq(Sess.session_cl(st)))

def sasl() -> String:
  ":irc.example CAP me ACK :sasl\r\nAUTHENTICATE +\r\n:irc.example 903 me :authenticated\r\n"

def nick_good(st: Sess.Session) -> Sess.Session:
  R.state(R.chunk(R.state(R.chunk(R.state(R.chunk(st, R.welcome())), notice("Help"))), notice("Account confirmed")))

def phase_name(phase: Cl.AuthPhase) -> String:
  match phase:
    case Cl.AuthCap{}: "sasl"
    case Cl.AuthNickWait{}: "nickserv"
    case _: "other"

def sasl_reset_controls() -> IO(Unit):
  +sasl_good = R.state(R.chunk(profile(Cl.SaslOnly{}), sasl() ++ R.welcome()))
  +sasl_again = Sess.session_reconnected(R.enter(sasl_good, "/reconnect"), "12:01:00")
  do IO<Unit>:
    Unit <- E.must_eq("SASL auth reset preserves credential for same endpoint", Cl.client_sasl_pass(Sess.session_cl(sasl_again)), "test-secret")
    Unit <- E.must_eq("SASL auth reset restores negotiation phase", phase_name(Cl.get_auth(Sess.session_cl(sasl_again))), "sasl")
    Unit <- E.must_eq("SASL reset preserves monotonic success count", seq(sasl_again), "1")
    Unit <- E.must_eq("new SASL success advances count once", seq(R.state(R.chunk(sasl_again, sasl() ++ R.welcome()))), "2")
    IO.pure(Unit, Unit{})

def nick_reset_controls() -> IO(Unit):
  +good = nick_good(profile(Cl.NickServOnly{}))
  +again = Sess.session_reconnected(R.enter(good, "/reconnect"), "12:01:00")
  do IO<Unit>:
    Unit <- E.must_eq("NickServ reset restores welcome-wait phase", phase_name(Cl.get_auth(Sess.session_cl(again))), "nickserv")
    Unit <- E.must_eq("NickServ reset preserves monotonic success count", seq(again), "1")
    Unit <- E.must_eq("every reconnect re-identifies and advances once", seq(nick_good(again)), "2")
    IO.pure(Unit, Unit{})

def nick_join_controls() -> IO(Unit):
  +nick = profile(Cl.NickServOnly{})
  +probe = R.state(R.chunk(nick, R.welcome()))
  +identifying = R.state(R.chunk(probe, notice("Help")))
  do IO<Unit>:
    Unit <- E.must_eq("NickServ welcome probes identity but holds JOIN", R.wire(R.chunk(nick, R.welcome())), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("untrusted probe cannot release credentials or JOIN", R.wire(R.chunk(probe, ":NickServ!impostor@evil.example NOTICE me :Help\r\n")), "")
    Unit <- E.must_eq("trusted probe sends only IDENTIFY", R.wire(R.chunk(probe, notice("Help"))), "PRIVMSG NickServ :IDENTIFY account test-secret")
    Unit <- E.must_eq("untrusted confirmation cannot release JOIN", R.wire(R.chunk(identifying, ":NickServ!impostor@evil.example NOTICE me :Account confirmed\r\n")), "")
    Unit <- E.must_eq("wrong recipient cannot release JOIN", R.wire(R.chunk(identifying, ":" ++ prefix() ++ " NOTICE other :Account confirmed\r\n")), "")
    Unit <- E.must_eq("verified confirmation releases deferred JOIN", R.wire(R.chunk(identifying, notice("Account confirmed"))), "JOIN #start")
    Unit <- E.must_eq("explicit JOIN is deferred behind configured auth", R.wire(R.chunk(R.enter(probe, "/join #other key"), notice("Help") ++ notice("Account confirmed"))), "PRIVMSG NickServ :IDENTIFY account test-secret|JOIN #start|JOIN #other key")
    IO.pure(Unit, Unit{})

def reconnect_join_controls() -> IO(Unit):
  +good = nick_good(profile(Cl.NickServOnly{}))
  +again = Sess.session_reconnected(R.enter(good, "/reconnect"), "12:01:00")
  +fallback = R.state(R.chunk(profile(Cl.SaslNickServ{}), ":irc.example CAP me NAK :sasl\r\n"))
  do IO<Unit>:
    Unit <- E.must_eq("last connection success cannot release next welcome JOIN", R.wire(R.chunk(again, R.welcome())), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("fallback welcome probes identity but holds JOIN", R.wire(R.chunk(fallback, R.welcome())), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("changed endpoint clears authentication credentials", Cl.client_sasl_pass(Sess.session_cl(R.enter(good, "/connect other.example 6667"))), "")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- sasl_reset_controls()
    Unit <- nick_reset_controls()
    Unit <- nick_join_controls()
    Unit <- reconnect_join_controls()
    IO.print("reconnect_auth=ok")
