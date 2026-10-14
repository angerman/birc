# SPDX-License-Identifier: Apache-2.0
# Pure controls for the single bounded headless preference read.
import Base
import ./expect.bend as E
import ../../src/bend/startup_headless.bend as H
import ../../src/bend/preferences.bend as P
import ../../src/bend/preferences_live.bend as LP
import ../../src/bend/preferences_runtime.bend as R
import ../../src/bend/preferences_worker.bend as W
import ../../src/bend/session.bend as S
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/theme.bend as Theme

def session() -> S.Session:
  S.session_with_client_at(Cl.client_set_auth(Cl.init("me", "irc.example"), Cl.SaslOnly{}, "irc.example", 6697,
    "NickServ!service@services.example", "confirmed", "synthetic-account", "synthetic-secret"), "#initial", 6697)

def stored(history: Bool) -> P.Preferences:
  P.Preferences{False{}, False{}, False{}, history, 1, False{}, False{}, False{}, Nil{}, "#saved" <> Nil{}, True{}, Theme.Dark{}, True{}}

def options(on: Bool, explicit: Bool) -> W.Options:
  W.Options{on, explicit, False{}, False{}}

def allow(result: LP.Context & S.Session & Bool) -> Bool:
  match result:
    case (_, _, allowed): allowed

def retained(result: LP.Context & S.Session & Bool) -> Bool:
  match result:
    case (_, +st, _):
      String.eq(Cl.client_sasl_user(S.session_cl(st)), "synthetic-account")
        && String.eq(Cl.client_sasl_pass(S.session_cl(st)), "synthetic-secret")
        && U32.is_eq(S.session_port(st), 6697)
        && String.eq(Cl.server_of(S.session_cl(st)), "irc.example")

def draft(result: LP.Context & S.Session & Bool) -> String:
  match result:
    case (_, st, _): S.session_draft(st)

def with_draft() -> S.Session:
  S.st_of_keys(S.step_keys(session(), S.keys_of("unsent draft", False{}, 0, 0, 0, 0, 0, 0, 0)))

def queue_write(pair: R.State & Maybe<&2, R.Job>) -> Bool:
  match pair:
    case (_, Some{R.Write{_, host, port, prefs}}): String.eq(host, "irc.example") && U32.is_eq(port, 6697) && String.eq(String.join(P.channels(prefs), "|"), "#initial")
    case _: False{}

def queued(result: LP.Context & S.Session & Bool) -> Bool:
  match result:
    case (ctx, _, _): queue_write(R.take(LP.state(ctx)))

def resolved_cap(result: LP.Context & S.Session & Bool) -> Bool:
  match result:
    case (_, st, _): U32.is_eq(Cl.settings_hist_cap(Cl.get_settings(S.session_cl(st))), 1)

def history_off(result: LP.Context & S.Session & Bool) -> Bool:
  match result:
    case (_, st, _): Bool.not(Cl.settings_history(Cl.get_settings(S.session_cl(st))))

def disabled(result: LP.Context & S.Session & Bool) -> Bool:
  match result:
    case (ctx, st, allowed): Bool.not(LP.busy(ctx)) && allowed && String.eq(String.join(S.session_desired_channels(st), "|"), "#initial")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("resolved saved cap precedes archive restore", resolved_cap(H.resolve(options(True{}, False{}), session(), 1, (Some{stored(True{})}, 0))))
    Unit <- E.must("saved history off disables archive restore", history_off(H.resolve(options(True{}, False{}), session(), 1, (Some{stored(False{})}, 0))))
    Unit <- E.must("preparation preserves SASL endpoint and credentials", retained(H.resolve(options(True{}, False{}), session(), 1, (Some{stored(True{})}, 0))))
    Unit <- E.must_eq("preparation preserves original unsent composer draft", draft(H.resolve(options(True{}, False{}), with_draft(), 1, (Some{stored(True{})}, 0))), "unsent draft")
    Unit <- E.must("explicit channel snapshot write survives preparation", queued(H.resolve(options(True{}, True{}), session(), 1, (Some{stored(True{})}, 0))))
    Unit <- E.must("failed prefs read without explicit history edit denies archive", Bool.not(allow(H.resolve(options(True{}, False{}), session(), 1, (None{}, 2)))))
    Unit <- E.must("failed prefs read plus accepted history edit permits explicit policy", allow(H.resolve(options(True{}, False{}), S.st_of_keys(S.step_enter(session(), "/set history on")), 1, (None{}, 2))))
    Unit <- E.must("absent prefs read allows unchanged defaults", allow(H.resolve(options(True{}, False{}), session(), 1, (None{}, 0))))
    Unit <- E.must("disabled preferences retain original Session without worker", disabled(H.resolve(options(False{}, False{}), session(), 1, (Some{stored(False{})}, 2))))
    IO.print("startup_headless=ok\n")
