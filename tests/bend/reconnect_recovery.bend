# SPDX-License-Identifier: Apache-2.0
# Desired channel intent survives one endpoint, never a PART/close/self KICK.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/frame.bend as Fr

def state(pair: Sess.Session & List<&2, String>) -> Sess.Session:
  match pair:
    case (st, _): st

def wire(pair: Sess.Session & List<&2, String>) -> String:
  match pair:
    case (_, outs): String.join(outs, "|")

def entered(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match trip:
    case (st, _, _): st

def enter(st: Sess.Session, text: String) -> Sess.Session:
  entered(Sess.step_enter(st, text))

def chunk(st: Sess.Session, text: String) -> Sess.Session & List<&2, String>:
  Sess.step_on_chunk(st, Fr.string_to_octets(text))

def welcome() -> String:
  ":irc.example 001 me :welcome\r\n"

def online() -> Sess.Session:
  state(chunk(Sess.session_reconnected(Sess.session_with_client_at(Cl.init("me", "irc.example"), "#start", 6667), "12:00:00"), welcome()))

def channels() -> Sess.Session:
  enter(enter(online(), "/join #other secret-key"), "/join +#third")

def manual(st: Sess.Session) -> Sess.Session & List<&2, String>:
  chunk(Sess.session_reconnected(enter(st, "/reconnect"), "12:01:00"), welcome())

def auto.up(pair: Sess.Session & Sess.NetCmd) -> Sess.Session:
  match pair:
    case (st, _): Sess.session_reconnected(st, "12:01:00")

def auto(+st: Sess.Session) -> Sess.Session & List<&2, String>:
  +cl = Sess.session_cl(st)
  +enabled = Sess.session_set_client(st, Cl.set_settings(cl, Cl.set_autoreconn(Cl.get_settings(cl), True{})))
  chunk(auto.up(Sess.session_autoreconnect(Sess.session_fail(enabled, "disconnected"))), welcome())

def main() -> IO(Unit):
  +base = channels()
  do IO<Unit>:
    Unit <- E.must_eq("manual reconnect rejoins every desired channel and runtime key", wire(manual(base)), "JOIN #start|JOIN #other secret-key|JOIN +#third")
    Unit <- E.must_eq("automatic reconnect rejoins the same complete set", wire(auto(base)), "JOIN #start|JOIN #other secret-key|JOIN +#third")
    Unit <- E.must_eq("explicit PART removes launch-channel intent", wire(manual(enter(base, "/part #start"))), "JOIN #other secret-key|JOIN +#third")
    Unit <- E.must_eq("close removes channel intent", wire(manual(enter(base, "/close #other"))), "JOIN #start|JOIN +#third")
    Unit <- E.must_eq("self KICK does not revive channel on reconnect", wire(manual(state(chunk(base, ":op!u@h KICK #other me :removed\r\n")))), "JOIN #start|JOIN +#third")
    Unit <- E.must_eq("another nick KICK preserves our channel intent", wire(manual(state(chunk(base, ":op!u@h KICK #other someone :removed\r\n")))), "JOIN #start|JOIN #other secret-key|JOIN +#third")
    Unit <- E.must_eq("explicit JOIN restores removed intent", wire(manual(enter(state(chunk(base, ":op!u@h KICK #other me :removed\r\n")), "/join #other new-key"))), "JOIN #start|JOIN +#third|JOIN #other new-key")
    Unit <- E.must_eq("repeated welcome does not repeat JOIN", wire(chunk(state(manual(base)), welcome())), "")
    Unit <- E.must_eq("new endpoint does not inherit channel additions or keys", wire(chunk(Sess.session_reconnected(enter(base, "/connect other.example 6667"), "12:02:00"), ":other.example 001 me :welcome\r\n")), "JOIN #start")
    Unit <- E.must_eq("peer-prefixed welcome cannot trigger JOIN", wire(chunk(Sess.session_with_client_at(Cl.init("me", "irc.example"), "#start", 6667), ":peer!u@h 001 me :fake\r\n")), "")
    Unit <- E.must_eq("first server welcome can assign another nick and trigger JOIN", wire(chunk(Sess.session_with_client_at(Cl.init("me", "irc.example"), "#start", 6667), ":irc.example 001 someone :fake\r\n")), "JOIN #start")
    IO.print("reconnect_recovery=ok")
