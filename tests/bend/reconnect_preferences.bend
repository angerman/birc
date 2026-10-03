# SPDX-License-Identifier: Apache-2.0
# Late names-only settings loads cannot overwrite explicit channel edits/keys.
import Base
import ./expect.bend as E
import ./reconnect_recovery.bend as R
import ./reconnect_auth.bend as A
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/preferences.bend as Prefs

def names(st: Sess.Session) -> String:
  String.join(Sess.session_desired_channels(st), "|")

def entered_wire(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (_, Sess.Cont{outs}, _): String.join(outs, "|")
    case _: "unexpected command"

def plan_controls() -> IO(Unit):
  +base = R.channels()
  +revision = Sess.session_channel_revision(base)
  do IO<Unit>:
    Unit <- E.must_eq("unchanged startup revision accepts names", names(Sess.session_seed_channels_if(base, revision, "#saved" <> Nil{})), "#saved")
    Unit <- E.must_eq("same-name explicit key change rejects stale settings", R.wire(R.manual(Sess.session_seed_channels_if(R.enter(base, "/join #other changed-key"), revision, "#saved" <> Nil{}))), "JOIN #start|JOIN #other changed-key|JOIN +#third")
    Unit <- E.must_eq("PART/rejoin round trip rejects stale settings", names(Sess.session_seed_channels_if(R.enter(R.enter(base, "/part #other"), "/join #other secret-key"), revision, "#saved" <> Nil{})), "#start|+#third|#other")
    Unit <- E.must_eq("names-only seed preserves matching runtime key", R.wire(R.manual(Sess.session_seed_channels_if(base, revision, "#other" <> Nil{}))), "JOIN #other secret-key")
    Unit <- E.must("reset does not consume explicit edit revision", Nat.is_eq(Sess.session_channel_revision(R.state(R.manual(base))), revision))
    Unit <- E.must("keys never enter preferences serialization", Bool.not(String.contains(Prefs.show(Prefs.capture(Sess.session_cl(base), True{}, Sess.session_desired_channels(base))), "secret-key")))
    IO.pure(Unit, Unit{})

def local_controls() -> IO(Unit):
  +offline = Sess.session_fail(R.channels(), "test disconnect")
  do IO<Unit>:
    Unit <- E.must_eq("offline PART cancels intent without wire", entered_wire(Sess.step_enter(offline, "/part #other")), "")
    Unit <- E.must_eq("offline PART stays removed after reconnect", R.wire(R.manual(R.enter(offline, "/part #other"))), "JOIN #start|JOIN +#third")
    Unit <- E.must_eq("offline close stays removed after reconnect", R.wire(R.manual(R.enter(offline, "/close #other"))), "JOIN #start|JOIN +#third")
    Unit <- E.must_eq("invalid offline PART preserves all intent", R.wire(R.manual(R.enter(offline, "/part someone"))), "JOIN #start|JOIN #other secret-key|JOIN +#third")
    Unit <- E.must_eq("connecting PART cancels intent without wire", entered_wire(Sess.step_enter(R.enter(R.channels(), "/reconnect"), "/part #other")), "")
    Unit <- E.must_eq("connecting PART stays removed after Up", R.wire(R.chunk(Sess.session_reconnected(R.enter(R.enter(R.channels(), "/reconnect"), "/part #other"), "12:01:00"), R.welcome())), "JOIN #start|JOIN +#third")
    IO.pure(Unit, Unit{})

def held() -> Sess.Session:
  Sess.session_hold_joins(Sess.session_with_client_at(Cl.init("me", "irc.example"), "#start", 6667))

def held_nick() -> Sess.Session:
  Sess.session_hold_joins(A.profile(Cl.NickServOnly{}))

def hold_controls() -> IO(Unit):
  +welcome = R.state(R.chunk(Sess.session_reconnected(held(), "12:00:00"), R.welcome()))
  do IO<Unit>:
    Unit <- E.must_eq("startup hold survives Up and welcome", R.wire(R.chunk(Sess.session_reconnected(held(), "12:00:00"), R.welcome())), "")
    Unit <- E.must_eq("loaded names replace unsent launch seed", R.wire(Sess.session_resume_joins(Sess.session_seed_channels(welcome, "#saved" <> "#second" <> Nil{}))), "JOIN #saved|JOIN #second")
    IO.pure(Unit, Unit{})

def auth_hold_controls() -> IO(Unit):
  +authenticated = A.nick_good(held_nick())
  do IO<Unit>:
    Unit <- E.must_eq("resume before auth confirmation emits no JOIN", R.wire(Sess.session_resume_joins(R.state(R.chunk(held_nick(), R.welcome())))), "")
    Unit <- E.must_eq("auth progresses while held; resume flushes once", R.wire(Sess.session_resume_joins(authenticated)), "JOIN #start")
    Unit <- E.must_eq("second resume does not repeat JOIN", R.wire(Sess.session_resume_joins(R.state(Sess.session_resume_joins(authenticated)))), "")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- plan_controls()
    Unit <- local_controls()
    Unit <- hold_controls()
    Unit <- auth_hold_controls()
    IO.print("reconnect_preferences=ok")
