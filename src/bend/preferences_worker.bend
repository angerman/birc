# SPDX-License-Identifier: Apache-2.0
# The UI owns the bounded pure queue. Workers post only typed values/codes.
import Base
import ./preferences.bend as P
import ./preferences_io.bend as F
import ./preferences_runtime.bend as R
import ./session.bend as Sess
import ./args.bend as Args

type Options is Data:
  Options{on: Bool, explicit: Bool, images: Bool, cap: Bool}

def enabled.env(got: Result<&1, &1, U32 & String, String>) -> Bool:
  match got:
    case Fail{_}: True{}
    case Done{+value}: Bool.not(String.is_empty(value) || String.eq(value, "none"))

def present(got: Result<&1, &1, U32 & String, String>) -> Bool:
  match got:
    case Fail{_}: False{}
    case Done{_}: True{}

def options() -> IO(Options):
  do IO<Options>:
    enabled : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_PREFERENCES")
    images : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_IMAGES")
    cap : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_HISTORY_LINES")
    raw : List<&1, String> <- IO.args()
    return Options{enabled.env(enabled), R.channel_explicit(Args.copy_args(Args.drop_prog(raw), Nil{})), present(images), present(cap)}

def loaded(pair: Maybe<&2, P.Preferences> & U32, ticket: Nat, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match pair:
    case (prefs, code):
      do IO<Unit>:
        _ : Result<&1, &1, Sess.UiMsg, Unit> <- Chan.send(Sess.UiMsg, evt, Sess.PreferencesLoaded{ticket, prefs, code})
        return Unit{}

def run(job: R.Job, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match job:
    case R.Read{ticket, host, port, _, _}:
      do IO<Unit>:
        result : Maybe<&2, P.Preferences> & U32 <- F.load(host, port)
        loaded(result, ticket, evt)
    case R.Write{ticket, host, port, prefs}:
      do IO<Unit>:
        code : U32 <- F.save(host, port, prefs)
        _ : Result<&1, &1, Sess.UiMsg, Unit> <- Chan.send(Sess.UiMsg, evt, Sess.PreferencesSaved{ticket, code})
        return Unit{}

def start(got: Maybe<&2, R.Job>, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match got:
    case None{}: IO.pure(Unit, Unit{})
    case Some{job}: IO.spawn(Unit, run(job, evt))

# A hard total quit deadline, not a promise to complete all 16 scopes when
# helpers are slow. A timeout reports failure; it does not claim a saved snapshot.
def DRAIN_MS() -> U32:
  22000

# Reserve more than the helper's five-second timeout before starting another.
def DRAIN_START_MS() -> U32:
  16000

def deadline(ticket: Nat, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(DRAIN_MS())
    _ : Result<&1, &1, Sess.UiMsg, Unit> <- Chan.send(Sess.UiMsg, evt, Sess.PreferencesDeadline{ticket})
    return Unit{}
