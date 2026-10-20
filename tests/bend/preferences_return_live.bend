# SPDX-License-Identifier: Apache-2.0
# Actual Session holds must release when a cached write returns to its scope.
import Base
import ./expect.bend as E
import ./reconnect_recovery.bend as Rec
import ../../src/bend/preferences.bend as P
import ../../src/bend/preferences_runtime.bend as R
import ../../src/bend/preferences_live.bend as L
import ../../src/bend/session.bend as S
import ../../src/bend/buffer.bend as Cl

type Stage is Data:
  Stage{ctx: L.Context, st: S.Session}

def observed(pair: L.Context & S.Session) -> Stage:
  match pair:
    case (ctx, st): Stage{ctx, st}

def completed(result: L.Context & S.Session & List<&2, String> & Bool) -> Stage:
  match result:
    case (ctx, st, _, _): Stage{ctx, st}

def taken(pair: R.State & Maybe<&2, R.Job>, st: S.Session) -> Stage:
  match pair:
    case (state, _): Stage{L.wrap(state), st}

def start(stage: Stage) -> Stage:
  match stage:
    case Stage{ctx, st}: taken(R.take(L.state(ctx)), st)

def initial() -> Stage:
  +st = S.session_with_client_at(Cl.init("me", "irc.example"), "#initial", 6697)
  start(Stage{L.wrap(R.initial(True{}, "irc.example", 6697, L.capture(st, 1), 0n, False{}, False{}, False{})), st})

def load(stage: Stage, ticket: Nat, prefs: Maybe<&2, P.Preferences>) -> Stage:
  match stage:
    case Stage{ctx, st}: completed(L.loaded(ctx, st, 1, ticket, prefs, 0))

def up(stage: Stage, +host: String) -> Stage:
  match stage:
    # JOIN flush needs post-welcome MOTD; hold/release still owned by prefs write.
    case Stage{ctx, st}: Stage{ctx, Rec.state(Rec.chunk(S.session_reconnected(st, ""), ":" ++ host ++ " 001 me :welcome\r\n:" ++ host ++ " 376 me :end of MOTD\r\n"))}

def command(stage: Stage, text: String) -> Stage:
  match stage:
    case Stage{ctx, st}: observed(L.observe(ctx, Rec.enter(st, text), 1))

def saved(stage: Stage, ticket: Nat) -> Stage:
  match stage:
    case Stage{ctx, st}: completed(L.saved(ctx, st, ticket, 0))

def snapshot(stage: Stage) -> P.Preferences:
  match stage:
    case Stage{_, st}: L.capture(st, 1)

def writing_a() -> Stage:
  start(command(up(load(initial(), 1n, None{}), "irc.example"), "/join #a-edit"))

def held_c() -> Stage:
  up(command(writing_a(), "/connect c.example 6697"), "c.example")

def return_a() -> Stage:
  up(command(held_c(), "/connect irc.example 6697"), "irc.example")

def return_after_kick(stage: Stage) -> Stage:
  match stage:
    case Stage{ctx, st}:
      # Both inbound membership and physical Enter occur before one observe.
      observed(L.observe(ctx, Rec.enter(Rec.state(Rec.chunk(st, ":me!u@h JOIN #initial\r\n:op!u@h KICK #initial me :gone\r\n")), "/connect irc.example 6697"), 1))

def next_read_a() -> Stage:
  start(load(start(saved(return_a(), 2n)), 3n, None{}))

def flush(stage: Stage) -> L.Context & S.Session & List<&2, String> & Bool:
  match stage:
    case Stage{ctx, +st}: L.loaded(ctx, st, 1, 4n, Some{L.capture(st, 1)}, 0)

def flush_wire(result: L.Context & S.Session & List<&2, String> & Bool) -> String:
  match result:
    case (_, st, outs, _): String.join(outs, "|") ++ "/" ++ Rec.wire(S.session_resume_joins(st))

def held_wire(stage: Stage, +host: String) -> String:
  match stage:
    case Stage{_, st}: Rec.wire(Rec.chunk(st, ":" ++ host ++ " 001 me :welcome\r\n:" ++ host ++ " 376 me :end of MOTD\r\n"))

def names(stage: Stage) -> String:
  match stage:
    case Stage{_, st}: String.join(S.session_desired_channels(st), "|")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("C welcome remains held behind active A write", held_wire(held_c(), "c.example"), "")
    Unit <- E.must_eq("return to A restores cached desired names", names(return_a()), "#initial|#a-edit")
    Unit <- E.must_eq("return A welcome stays held until confirmation read", held_wire(return_a(), "irc.example"), "")
    Unit <- E.must_eq("current read releases return A JOIN exactly once", flush_wire(flush(next_read_a())), "JOIN #initial|JOIN #a-edit/")
    Unit <- E.must_eq("old C self-KICK plus connect A cannot erase cached A names", names(return_after_kick(held_c())), "#initial|#a-edit")
    IO.print("preferences_return_live=ok\n")
