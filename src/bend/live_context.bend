# SPDX-License-Identifier: Apache-2.0
# Outer-loop settings and initial-history gate. No IRC traffic precedes Begin.
# Box the record to stay below Bend's flattened continuation capture limit.
import Base
import ./buffer.bend as Cl
import ./session.bend as S
import ./preferences_live.bend as L
import ./preferences_worker.bend as W
import ./preferences.bend as P
import ./preferences_runtime.bend as R
import ./history_startup.bend as H
import ./history_startup_io.bend as F
import ./history_io.bend as Save

type Gate is Data:
  Open{}
  Waiting{gen: U32, endpoint: String}

type Archive is Data:
  Archive{ticket: Nat, gen: U32, endpoint: String, cap: U32, read: Bool, nick: String, host: String, now: String, started: Bool}

type Details is Data:
  Details{prefs: L.Context, gate: Gate, decision: Maybe<&2, Bool>, path: String, archive: Maybe<&2, Archive>, next: Nat}

type Context is Data:
  Context{cell: List<&2, Details>}

def wrap(details: Details) -> Context:
  Context{details <> Nil{}}

def details(ctx: Context) -> Details:
  match ctx:
    case Context{value <> Nil{}}: value
    case _: Details{L.wrap(R.Disabled{}), Open{}, Some{True{}}, "", None{}, 0n}

def now(cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, _, _, value, _, _, _}: value

def endpoint(+st: S.Session) -> String:
  Cl.server_of(S.session_cl(st)) ++ ":" ++ U32.show(S.session_port(st))

def initial(options: W.Options, +st: S.Session, +gen: U32, path: String) -> Context:
  match options:
    case W.Options{+on, explicit, images, cap}:
      wrap(Details{L.initial(W.Options{on, explicit, images, cap}, st, gen),
        Bool.pick(Gate, on && Bool.not(U32.is_zero(gen)), Waiting{gen, endpoint(st)}, Open{}),
        Bool.pick(Maybe<&2, Bool>, on, None{}, Some{True{}}), path, None{}, 0n})

def prepared(prefs: L.Context, path: String, known: Bool) -> Context:
  wrap(Details{prefs, Open{}, Some{known}, path, None{}, 0n})

def explicit_history(+st: S.Session) -> Bool:
  List.contains(~String, ~String.eq, S.session_preference_edits(st), "history")

def decision_known(got: Maybe<&2, Bool>) -> Bool:
  match got:
    case Some{known}: known
    case None{}: False{}

def gate_ready(gate: Gate) -> Bool:
  match gate:
    case Open{}: True{}
    case _: False{}

def gate_matches(gate: Gate, +gen: U32, +ep: String) -> Bool:
  match gate:
    case Waiting{wanted, scope}: U32.is_eq(wanted, gen) && String.eq(scope, ep)
    case Open{}: False{}

def gate_of.details(value: Details) -> Gate:
  match value:
    case Details{_, gate, _, _, _, _}: gate

def gate_of(ctx: Context) -> Gate:
  gate_of.details(details(ctx))

# Acceptance is exactly the Waiting->Ready resolve: every reject path (stale
# ticket, wrong gen/endpoint, changed settings, waiting prefs) keeps the
# gate, so a stale completion can never seed notify state.
def history_accepted(before: Context, after: Context) -> Bool:
  gate_ready(gate_of(after)) && Bool.not(gate_ready(gate_of(before)))

def history_allowed.details(value: Details, +st: S.Session) -> Bool:
  match value:
    case Details{_, gate, decision, _, _, _}:
      gate_ready(gate) && (decision_known(decision) || explicit_history(st))

def history_allowed(ctx: Context, st: S.Session) -> Bool:
  history_allowed.details(details(ctx), st)

def hold(on: Bool, st: S.Session) -> S.Session:
  L.hold(on, st)

def waiting.details(value: Details) -> Bool:
  match value:
    case Details{prefs, _, _, _, _, _}: L.waiting(prefs)

def waiting(ctx: Context) -> Bool:
  waiting.details(details(ctx))

def busy.details(value: Details) -> Bool:
  match value:
    case Details{prefs, _, _, _, _, _}: L.busy(prefs)

def busy(ctx: Context) -> Bool:
  busy.details(details(ctx))

def active.details(value: Details) -> Bool:
  match value:
    case Details{prefs, _, _, _, _, _}: L.active(prefs)

def active(ctx: Context) -> Bool:
  active.details(details(ctx))

def clean.details(value: Details) -> Bool:
  match value:
    case Details{prefs, _, _, _, _, _}: R.clean(L.state(prefs))

def clean(ctx: Context) -> Bool:
  clean.details(details(ctx))

def gate_scope(gate: Gate, +st: S.Session, gen: U32) -> Gate:
  match gate:
    case Open{}: Open{}
    case Waiting{_, _}: Waiting{gen, endpoint(st)}

def archive_needed(gate: Gate, prefs: L.Context, active: Maybe<&2, Archive>) -> Bool:
  match active:
    case Some{_}: False{}
    case None{}: Bool.not(gate_ready(gate) || L.waiting(prefs))

def archive_queue(on: Bool, ctx: Details, +st: S.Session) -> Context:
  match on:
    case False{}: wrap(ctx)
    case True{}:
      match ctx:
        case Details{prefs, Waiting{+gen, +ep}, +decision, path, _, +next}:
          +cl = S.session_cl(st)
          wrap(Details{prefs, Waiting{gen, ep}, decision, path,
            Some{Archive{next, gen, ep, Cl.settings_hist_cap(Cl.get_settings(cl)),
              (decision_known(decision) || explicit_history(st)) && Cl.settings_history(Cl.get_settings(cl)),
              Cl.nick_of(cl), Cl.server_of(cl), now(cl), False{}}}, 1n+next})
        case _: wrap(ctx)

def observe.pair(pair: L.Context & S.Session, gate: Gate, decision: Maybe<&2, Bool>, path: String, +active: Maybe<&2, Archive>, next: Nat, +gen: U32) -> Context & S.Session:
  match pair:
    case (+prefs, +st):
      +scope = gate_scope(gate, st, gen)
      (archive_queue(archive_needed(scope, prefs, active), Details{prefs, scope, decision, path, active, next}, st), st)

def observe.details(value: Details, st: S.Session, +gen: U32) -> Context & S.Session:
  match value:
    case Details{prefs, gate, decision, path, active, next}:
      observe.pair(L.observe(prefs, st, gen), gate, decision, path, active, next, gen)

def observe(ctx: Context, st: S.Session, gen: U32) -> Context & S.Session:
  observe.details(details(ctx), st, gen)

def decision_complete(prior: Maybe<&2, Bool>, settled: Bool, code: U32) -> Maybe<&2, Bool>:
  match prior:
    case Some{value}: Some{value}
    case None{}: Bool.pick(Maybe<&2, Bool>, settled, Some{U32.is_zero(code)}, None{})

def completion(result: L.Context & S.Session & List<&2, String> & Bool, gate: Gate, decision: Maybe<&2, Bool>, path: String, active: Maybe<&2, Archive>, next: Nat, +code: U32, was_waiting: Bool) -> Context & S.Session & List<&2, String> & Bool:
  match result:
    case (+prefs, st, outs, paint):
      (wrap(Details{prefs, gate, decision_complete(decision, was_waiting && Bool.not(L.waiting(prefs)), code), path, active, next}), st, outs, paint)

def loaded.details(value: Details, st: S.Session, gen: U32, ticket: Nat, got: Maybe<&2, P.Preferences>, +code: U32) -> Context & S.Session & List<&2, String> & Bool:
  match value:
    case Details{+prefs, gate, decision, path, active, next}:
      completion(L.loaded(prefs, st, gen, ticket, got, code), gate, decision, path, active, next, code, L.waiting(prefs))

def loaded(ctx: Context, st: S.Session, gen: U32, ticket: Nat, got: Maybe<&2, P.Preferences>, code: U32) -> Context & S.Session & List<&2, String> & Bool:
  loaded.details(details(ctx), st, gen, ticket, got, code)

def saved.details(value: Details, st: S.Session, ticket: Nat, code: U32) -> Context & S.Session & List<&2, String> & Bool:
  match value:
    case Details{prefs, gate, decision, path, active, next}:
      completion(L.saved(prefs, st, ticket, code), gate, decision, path, active, next, 0, False{})

def saved(ctx: Context, st: S.Session, ticket: Nat, code: U32) -> Context & S.Session & List<&2, String> & Bool:
  saved.details(details(ctx), st, ticket, code)

# Retire only the physical preference ticket. Stale origins cannot resolve
# history policy, install settings, resume JOINs, or add Session diagnostics.
def retire.details(value: Details, m: S.UiMsg) -> Context:
  match value:
    case Details{prefs, gate, decision, path, active, next}:
      wrap(Details{L.retire(prefs, m), gate, decision, path, active, next})

def retire(ctx: Context, m: S.UiMsg) -> Context:
  retire.details(details(ctx), m)

def start.archive(active: Maybe<&2, Archive>, prefs: L.Context, gate: Gate, decision: Maybe<&2, Bool>, +path: String, next: Nat, evt: Chan(S.UiMsg)) -> IO(Context):
  match active:
    case Some{Archive{+ticket, +gen, +ep, +cap, +read, +nick, +host, +now, False{}}}:
      do IO<Context>:
        Unit <- F.start(ticket, gen, Bool.pick(String, read, path, ""), ep, cap, nick, host, now, evt)
        return wrap(Details{prefs, gate, decision, path, Some{Archive{ticket, gen, ep, cap, read, nick, host, now, True{}}}, next})
    case _: IO.pure(Context, wrap(Details{prefs, gate, decision, path, active, next}))

def start.details(value: Details, +evt: Chan(S.UiMsg)) -> IO(Context):
  match value:
    case Details{prefs, gate, decision, path, active, next}:
      do IO<Context>:
        prefs : L.Context <- L.start(prefs, evt)
        start.archive(active, prefs, gate, decision, path, next, evt)

def start(ctx: Context, evt: Chan(S.UiMsg)) -> IO(Context):
  start.details(details(ctx), evt)

def archive_owned(active: Maybe<&2, Archive>, ticket: Nat) -> Bool:
  match active:
    case Some{Archive{owned, _, _, _, _, _, _, _, _}}: Nat.is_eq(owned, ticket)
    case None{}: False{}

def archive_current(active: Maybe<&2, Archive>, gate: Gate, +decision: Maybe<&2, Bool>, +st: S.Session, +gen: U32, +ep: String) -> Bool:
  match active:
    case Some{Archive{_, +got, +scope, cap, read, _, _, _, _}}:
      U32.is_eq(got, gen) && String.eq(scope, ep) && String.eq(ep, endpoint(st)) && gate_matches(gate, gen, ep)
        && U32.is_eq(cap, Cl.settings_hist_cap(Cl.get_settings(S.session_cl(st))))
        && Bool.not(R.changed_bool(read, (decision_known(decision) || explicit_history(st)) && Cl.settings_history(Cl.get_settings(S.session_cl(st)))))
    case None{}: False{}

def history_notice(got: Maybe<&2, String>, cl: Cl.Client) -> Cl.Client:
  match got:
    case None{}: cl
    case Some{msg}: Cl.diagnostic(cl, Cl.Error{}, msg)

def history.flush(on: Bool, +path: String, +ep: String, +cl: Cl.Client) -> IO(Cl.Client):
  match on:
    case False{}: IO.pure(Cl.Client, cl)
    case True{}:
      do IO<Cl.Client>:
        notice : Maybe<&2, String> <- Save.maybe_save_history(path, ep, Cl.init(Cl.nick_of(cl), Cl.server_of(cl)), cl)
        return history_notice(notice, cl)

def history.install(current: Bool, prefs: L.Context, gate: Gate, +decision: Maybe<&2, Bool>, +path: String, next: Nat, +st: S.Session, +gen: U32, +ep: String, +snapshot: Cl.Client, cmd: Chan(S.NetCmd)) -> IO(Context & S.Session):
  match current:
    case False{}: IO.pure(Context & S.Session, (wrap(Details{prefs, gate, decision, path, None{}, next}), st))
    case True{}:
      do IO<Context & S.Session>:
        local : Cl.Client <- history.flush(decision_known(decision) || explicit_history(st), path, ep, S.session_cl(st))
        _ : Result<&1, &1, S.NetCmd, Unit> <- Chan.send(S.NetCmd, cmd, S.Begin{gen})
        return (wrap(Details{prefs, Open{}, decision, path, None{}, next}), S.session_set_client(st, H.install_startup(H.report_diagnostics(local, snapshot), snapshot)))

def history.result(owned: Bool, ctx: Details, +st: S.Session, +gen: U32, got_gen: U32, +ep: String, snapshot: Cl.Client, cmd: Chan(S.NetCmd)) -> IO(Context & S.Session):
  match owned:
    case False{}: IO.pure(Context & S.Session, (wrap(ctx), st))
    case True{}:
      match ctx:
        case Details{+prefs, +gate, +decision, path, +active, next}:
          history.install(U32.is_eq(gen, got_gen) && archive_current(active, gate, decision, st, gen, ep) && Bool.not(L.waiting(prefs)), prefs, gate, decision, path, next, st, gen, ep, snapshot, cmd)

def history.details(value: Details, st: S.Session, gen: U32, got_gen: U32, +ticket: Nat, ep: String, snapshot: Cl.Client, cmd: Chan(S.NetCmd)) -> IO(Context & S.Session):
  match value:
    case Details{prefs, gate, decision, path, +active, next}:
      history.result(archive_owned(active, ticket), Details{prefs, gate, decision, path, active, next}, st, gen, got_gen, ep, snapshot, cmd)

def history(ctx: Context, st: S.Session, gen: U32, got_gen: U32, ticket: Nat, ep: String, snapshot: Cl.Client, cmd: Chan(S.NetCmd)) -> IO(Context & S.Session):
  history.details(details(ctx), st, gen, got_gen, ticket, ep, snapshot, cmd)

def drain.details(value: Details, st: S.Session, evt: Chan(S.UiMsg), gen: U32) -> IO(S.Session & Bool):
  match value:
    case Details{prefs, _, _, _, _, _}: L.drain(prefs, st, evt, gen)

def drain(ctx: Context, st: S.Session, evt: Chan(S.UiMsg), gen: U32) -> IO(S.Session & Bool):
  drain.details(details(ctx), st, evt, gen)
