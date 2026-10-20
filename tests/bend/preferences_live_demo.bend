# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/preferences.bend as P
import ../../src/bend/preferences_runtime.bend as R
import ../../src/bend/preferences_live.bend as L
import ../../src/bend/session.bend as S
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/theme.bend as Theme

def session() -> S.Session:
  S.session_demo_at(Cl.init("me", "irc.example"), "#initial", 6697)

def snapshot(known: Bool, channels: List<&2, String>) -> P.Preferences:
  P.Preferences{False{}, False{}, False{}, True{}, 200, True{}, False{}, False{}, Nil{}, channels, known, Theme.Dark{}, True{}}

def started(pair: R.State & Maybe<&2, R.Job>) -> L.Context:
  match pair:
    case (state, _): L.wrap(state)

def context() -> L.Context:
  started(R.take(R.initial(True{}, "irc.example", 6697, L.capture(session(), 1), 0n, False{}, False{}, False{})))

def names(result: L.Context & S.Session & List<&2, String> & Bool) -> String:
  match result:
    case (_, st, _, _): P.records_text(S.session_desired_channels(st), "channel")

def ts(result: L.Context & S.Session & List<&2, String> & Bool) -> Bool:
  match result:
    case (_, st, _, _): Cl.settings_ts(Cl.get_settings(S.session_cl(st)))

def idle() -> L.Context:
  L.wrap(R.Disabled{})

def log_n(+st: S.Session) -> Nat:
  List.length(&2, Cl.Buffer, Cl.log_buffers(S.session_cl(st)))

def deadline_ok(result: S.Session & Bool) -> Bool:
  match result:
    case (_, ok): ok

def deadline_quiet(result: S.Session & Bool) -> Bool:
  match result:
    case (st, ok): ok && Nat.is_eq(log_n(st), 0n)

def deadline_failed_quiet(result: S.Session & Bool) -> Bool:
  match result:
    case (st, False{}): Nat.is_eq(log_n(st), 0n)
    case _: False{}

def deadline_blamed(result: S.Session & Bool) -> Bool:
  match result:
    case (st, False{}): Nat.is_eq(log_n(st), 1n)
    case _: False{}

def loaded_ctx(result: L.Context & S.Session & List<&2, String> & Bool) -> L.Context:
  match result:
    case (ctx, _, _, _): ctx

def loaded_st(result: L.Context & S.Session & List<&2, String> & Bool) -> S.Session:
  match result:
    case (_, st, _, _): st

# Failed read without accepted edits: R.clean stays true (runtime oracle), but
# drain.ok threads the non-zero code so finish/deadline exit false — matching
# ws_shut.applied, not prefs-only R.clean alone.
def failed_read() -> L.Context & S.Session & List<&2, String> & Bool:
  L.loaded(context(), session(), 1, 1n, None{}, 2)

def ok_read() -> L.Context & S.Session & List<&2, String> & Bool:
  L.loaded(context(), session(), 1, 1n, Some{snapshot(True{}, Nil{})}, 0)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("unknown endpoint retains launch default", names(L.loaded(context(), session(), 1, 1n, Some{snapshot(False{}, Nil{})}, 0)), "channel\t#initial\n")
    Unit <- E.must_eq("saved empty channel list disables startup autojoin", names(L.loaded(context(), session(), 1, 1n, Some{snapshot(True{}, Nil{})}, 0)), "")
    Unit <- E.must_eq("known endpoint loads exact saved names", names(L.loaded(context(), session(), 1, 1n, Some{snapshot(True{}, "+#saved" <> Nil{})}, 0)), "channel\t+#saved\n")
    Unit <- E.must("accepted same-value Session timestamp edit wins late stored off", ts(L.loaded(context(), S.st_of_keys(S.step_enter(session(), "/set ts on")), 1, 1n, Some{snapshot(True{}, Nil{})}, 0)))
    Unit <- E.must("invalid timestamp command does not block stored off", Bool.not(ts(L.loaded(context(), S.st_of_keys(S.step_enter(session(), "/set ts invalid")), 1, 1n, Some{snapshot(True{}, Nil{})}, 0))))
    Unit <- E.must("settle tracks live busy not sticky latch", L.settle(idle()) && Bool.not(L.settle(context())))
    Unit <- E.must("deadline while idle does not sticky-blame prefs", deadline_quiet(L.drain.deadline(idle(), session(), True{})))
    Unit <- E.must("deadline while busy blames prefs", deadline_blamed(L.drain.deadline(context(), session(), True{})))
    Unit <- E.must("deadline idle after failed ok stays quiet", deadline_failed_quiet(L.expired(True{}, session(), False{})))
    Unit <- E.must("deadline idle after failed ok keeps ok false", Bool.not(deadline_ok(L.expired(True{}, session(), False{}))))
    Unit <- E.must("expired busy still blames despite prior ok", deadline_blamed(L.expired(False{}, session(), True{})))
    Unit <- E.must("failed read without edits is runtime-clean", R.clean(L.state(loaded_ctx(failed_read()))))
    Unit <- E.must("failed read drain finish exits false", Bool.not(deadline_ok(L.drain.finish(loaded_ctx(failed_read()), loaded_st(failed_read()), L.drain.ok(True{}, 2)))))
    Unit <- E.must("deadline idle after failed code keeps ok false", Bool.not(deadline_ok(L.drain.deadline(idle(), session(), L.drain.ok(True{}, 2)))))
    Unit <- E.must("ok read drain finish exits clean", deadline_ok(L.drain.finish(loaded_ctx(ok_read()), loaded_st(ok_read()), L.drain.ok(True{}, 0))))
    Unit <- E.must("deadline idle after ok code keeps ok true", deadline_quiet(L.drain.deadline(idle(), session(), L.drain.ok(True{}, 0))))
    IO.print("preferences_live_demo=ok\n")
