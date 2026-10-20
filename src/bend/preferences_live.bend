# SPDX-License-Identifier: Apache-2.0
# Small outer-loop context. The list boxes the wide queue record: Bend's
# flattened continuation capture limit is 247 words, not a source arg count.
import Base
import ./buffer.bend as Cl
import ./preferences.bend as P
import ./preferences_runtime.bend as R
import ./preferences_worker.bend as W
import ./session.bend as Sess
import ./media.bend as M
import ./clock.bend as Clock

type Context is Data:
  Context{cell: List<&2, R.State>}

def wrap(state: R.State) -> Context:
  Context{state <> Nil{}}

def state(ctx: Context) -> R.State:
  match ctx:
    case Context{value <> Nil{}}: value
    case _: R.Disabled{}

def mark(ctx: Context, names: List<&2, String>) -> Context:
  wrap(R.mark(state(ctx), names))

def host(st: Sess.Session, gen: U32) -> String:
  Bool.pick(String, U32.is_zero(gen), "", Cl.server_of(Sess.session_cl(st)))

def port(st: Sess.Session, gen: U32) -> U32:
  Bool.pick(U32, U32.is_zero(gen), 0, Sess.session_port(st))

def capture(+st: Sess.Session, +gen: U32) -> P.Preferences:
  P.capture_themed(Sess.session_cl(st), M.enabled(Sess.session_media(st)),
    Bool.pick(List<&2, String>, U32.is_zero(gen), Nil{}, Sess.session_desired_channels(st)),
    Sess.session_theme(st))

def initial(options: W.Options, +st: Sess.Session, +gen: U32) -> Context:
  match options:
    case W.Options{on, explicit, images, cap}:
      wrap(R.initial(on, host(st, gen), port(st, gen), capture(st, gen), Sess.session_channel_revision(st), explicit, images, cap))

def hold(on: Bool, st: Sess.Session) -> Sess.Session:
  match on:
    case False{}: st
    case True{}: Sess.session_hold_joins(st)

def start.pair(pair: R.State & Maybe<&2, R.Job>, evt: Chan(Sess.UiMsg)) -> IO(Context):
  match pair:
    case (next, job):
      do IO<Context>:
        Unit <- W.start(job, evt)
        return wrap(next)

def start(ctx: Context, evt: Chan(Sess.UiMsg)) -> IO(Context):
  start.pair(R.take(state(ctx)), evt)

def busy(ctx: Context) -> Bool:
  R.busy(state(ctx))

def active(ctx: Context) -> Bool:
  R.active(state(ctx))

def waiting(ctx: Context) -> Bool:
  R.waiting(state(ctx))

# Prefs settle is live !busy — never a sticky latch past a later start.
def settle(+ctx: Context) -> Bool:
  Bool.not(busy(ctx))

def notice(code: U32, +stage: String, +st: Sess.Session) -> Sess.Session:
  match code:
    case 0: st
    case _:
      Sess.session_set_client(st, Cl.diagnostic(Sess.session_cl(st), Cl.Error{},
        "preferences " ++ stage ++ " failed (code: " ++ U32.show(code) ++ ")"))

# Drain timeout / PreferencesDeadline may arrive after prefs already idle
# (ws_shut arms for hist/writers too). Blame prefs (408 notice + ok=False)
# only when still busy; idle keeps the prior ok without a manufactured notice.
def expired(+settled: Bool, +st: Sess.Session, +ok: Bool) -> Sess.Session & Bool:
  match settled:
    case True{}: (st, ok)
    case False{}: (notice(408, "drain", st), False{})

def observe.returned(names: Maybe<&2, List<&2, String>>, +st: Sess.Session) -> Sess.Session:
  match names:
    case None{}: st
    case Some{channels}: Sess.session_seed_channels_if(st, Sess.session_channel_revision(st), channels)

def observe.ready(+ctx: Context, +st: Sess.Session, +gen: U32) -> Context & Sess.Session:
  +next = R.observe(R.mark(state(ctx), Sess.session_preference_edits(st)), host(st, gen), port(st, gen), capture(st, gen), Sess.session_channel_revision(st))
  (wrap(R.clear_notice(next)), notice(R.queue_code(next), "queue", hold(R.waiting(next), st)))

def observe(+ctx: Context, +st: Sess.Session, +gen: U32) -> Context & Sess.Session:
  observe.ready(ctx, observe.returned(R.returning_channels(state(ctx), host(st, gen), port(st, gen), Sess.session_channel_revision(st)), st), gen)

def apply(got: Maybe<&2, P.Preferences>, +st: Sess.Session) -> Sess.Session:
  match got:
    case None{}: st
    case Some{+prefs}:
      Sess.session_set_theme(Sess.session_set_media(Sess.session_set_client(st, P.apply(Sess.session_cl(st), prefs)),
        M.set_enabled(Sess.session_media(st), P.images(prefs))), P.theme(prefs))

def seed(on: Bool, st: Sess.Session, baseline: Nat, got: Maybe<&2, P.Preferences>) -> Sess.Session:
  match on:
    case False{}: st
    case True{}:
      match got:
        case None{}: st
        case Some{prefs}: Sess.session_seed_channels_if(st, baseline, P.channels(prefs))

def resume(on: Bool, st: Sess.Session) -> Sess.Session & List<&2, String>:
  match on:
    case False{}: (st, Nil{})
    case True{}: Sess.session_resume_joins(st)

def loaded.resumed(pair: Sess.Session & List<&2, String>, ctx: Context, paint: Bool) -> Context & Sess.Session & List<&2, String> & Bool:
  match pair:
    case (st, outs): (ctx, st, outs, paint)

def loaded.completion(result: R.Completion, st: Sess.Session, baseline: Nat, +code: U32, +owned: Bool) -> Context & Sess.Session & List<&2, String> & Bool:
  match result:
    case R.Completion{next, +prefs, on, +current}:
      loaded.resumed(resume(current, notice(Bool.pick(U32, owned, code, 0), "read", seed(on, apply(prefs, st), baseline, prefs))), wrap(next), current || (owned && Bool.not(U32.is_zero(code))))

def loaded(+ctx: Context, +st: Sess.Session, +gen: U32, +ticket: Nat, got: Maybe<&2, P.Preferences>, +code: U32) -> Context & Sess.Session & List<&2, String> & Bool:
  +observed = R.observe(R.mark(state(ctx), Sess.session_preference_edits(st)), host(st, gen), port(st, gen), capture(st, gen), Sess.session_channel_revision(st))
  # The observed scope includes gen-zero global jobs. Runtime still retires
  # exact stale tickets; only an actual current Read can add a Session notice.
  loaded.completion(R.loaded(observed, ticket, got, code), st, R.read_revision(observed), code, R.read_current(observed, ticket))

def saved_context(ctx: Context, ticket: Nat, code: U32) -> Context:
  wrap(R.saved_result(state(ctx), ticket, code))

def saved_admitted(ctx: Context, +st: Sess.Session, +ticket: Nat) -> Bool:
  +owned = state(ctx)
  # Focus may move the global Context without changing this original Session.
  # Global jobs have no Session endpoint; admit them only while still global.
  R.write_at(owned, ticket, Cl.server_of(Sess.session_cl(st)), Sess.session_port(st))
    || (R.write_current(owned, ticket) && R.write_at(owned, ticket, "", 0))

def saved(+ctx: Context, +st: Sess.Session, +ticket: Nat, +code: U32) -> Context & Sess.Session & List<&2, String> & Bool:
  +owned = saved_admitted(ctx, st, ticket)
  (saved_context(ctx, ticket, code), notice(Bool.pick(U32, owned, code, 0), "write", st), Nil{}, owned && Bool.not(U32.is_zero(code)))

def retired_read(result: R.Completion) -> Context:
  match result:
    case R.Completion{next, _, _, _}: wrap(next)

# Physical completion only: keep Runtime's exact ticket and reconciliation,
# but never accept a stale read as current settings or produce Session effects.
def retire(ctx: Context, m: Sess.UiMsg) -> Context:
  match m:
    case Sess.PreferencesLoaded{ticket, got, code}: retired_read(R.loaded.eligible(False{}, state(ctx), ticket, got, code))
    case Sess.PreferencesSaved{ticket, code}: saved_context(ctx, ticket, code)
    case _: ctx

def drain.result(result: Context & Sess.Session & List<&2, String> & Bool, k: Context -> Sess.Session -> IO(Sess.Session & Bool)) -> IO(Sess.Session & Bool):
  match result:
    case (ctx, st, _, _): k(ctx, st)

def drain.deadline(+ctx: Context, +st: Sess.Session) -> Sess.Session & Bool:
  expired(settle(ctx), st, R.clean(state(ctx)))

def drain.message(got: Maybe<&1, Sess.UiMsg>, +ctx: Context, +st: Sess.Session, +gen: U32, k: Context -> Sess.Session -> IO(Sess.Session & Bool)) -> IO(Sess.Session & Bool):
  match got:
    case None{}: IO.pure(Sess.Session & Bool, (notice(1, "drain", st), False{}))
    case Some{msg}:
      match msg:
        case Sess.PreferencesLoaded{ticket, prefs, code}: drain.result(loaded(ctx, st, gen, ticket, prefs, code), k)
        case Sess.PreferencesSaved{ticket, code}: drain.result(saved(ctx, st, ticket, code), k)
        case Sess.PreferencesDeadline{_}: IO.pure(Sess.Session & Bool, drain.deadline(ctx, st))
        case _: k(ctx, st)

def drain.within(ok: Bool, ctx: Context, +st: Sess.Session, +evt: Chan(Sess.UiMsg), gen: U32, k: Context -> Sess.Session -> IO(Sess.Session & Bool)) -> IO(Sess.Session & Bool):
  match ok:
    case False{}: IO.pure(Sess.Session & Bool, drain.deadline(ctx, st))
    case True{}:
      do IO<Sess.Session & Bool>:
        next : Context <- start(ctx, evt)
        got : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
        drain.message(got, next, st, gen, k)

def drain.busy(on: Bool, +ctx: Context, st: Sess.Session, evt: Chan(Sess.UiMsg), gen: U32, +started: U32, k: Context -> Sess.Session -> IO(Sess.Session & Bool)) -> IO(Sess.Session & Bool):
  match on:
    case False{}: IO.pure(Sess.Session & Bool, (st, R.clean(state(ctx))))
    case True{}:
      do IO<Sess.Session & Bool>:
        +now : U32 <- Clock.millis()
        drain.within(U32.is_lt(U32.sub(now, started), W.DRAIN_MS()) &&
          (R.active(state(ctx)) || U32.is_lt(U32.sub(now, started), W.DRAIN_START_MS())), ctx, st, evt, gen, k)

@unsafe
def drain_loop(+ctx: Context, st: Sess.Session, +evt: Chan(Sess.UiMsg), +gen: U32, +started: U32) -> IO(Sess.Session & Bool):
  drain.busy(busy(ctx), ctx, st, evt, gen, started, next => s => drain_loop(next, s, evt, gen, started))

def drain.start(on: Bool, ctx: Context, st: Sess.Session, +evt: Chan(Sess.UiMsg), gen: U32) -> IO(Sess.Session & Bool):
  match on:
    case False{}: IO.pure(Sess.Session & Bool, (st, R.clean(state(ctx))))
    case True{}:
      do IO<Sess.Session & Bool>:
        started : U32 <- Clock.millis()
        Unit <- IO.spawn(Unit, W.deadline(0n, evt))
        drain_loop(ctx, st, evt, gen, started)

def drain(+ctx: Context, st: Sess.Session, evt: Chan(Sess.UiMsg), gen: U32) -> IO(Sess.Session & Bool):
  drain.start(busy(ctx), ctx, st, evt, gen)
