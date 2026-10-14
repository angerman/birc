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

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("unknown endpoint retains launch default", names(L.loaded(context(), session(), 1, 1n, Some{snapshot(False{}, Nil{})}, 0)), "channel\t#initial\n")
    Unit <- E.must_eq("saved empty channel list disables startup autojoin", names(L.loaded(context(), session(), 1, 1n, Some{snapshot(True{}, Nil{})}, 0)), "")
    Unit <- E.must_eq("known endpoint loads exact saved names", names(L.loaded(context(), session(), 1, 1n, Some{snapshot(True{}, "+#saved" <> Nil{})}, 0)), "channel\t+#saved\n")
    Unit <- E.must("accepted same-value Session timestamp edit wins late stored off", ts(L.loaded(context(), S.st_of_keys(S.step_enter(session(), "/set ts on")), 1, 1n, Some{snapshot(True{}, Nil{})}, 0)))
    Unit <- E.must("invalid timestamp command does not block stored off", Bool.not(ts(L.loaded(context(), S.st_of_keys(S.step_enter(session(), "/set ts invalid")), 1, 1n, Some{snapshot(True{}, Nil{})}, 0))))
    IO.print("preferences_live_demo=ok\n")
