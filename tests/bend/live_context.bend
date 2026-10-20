# SPDX-License-Identifier: Apache-2.0
# Independent pure controls for the initial preferences/archive actor gate.
import Base
import ./expect.bend as E
import ../../src/bend/live_context.bend as C
import ../../src/bend/preferences_live.bend as L
import ../../src/bend/preferences_runtime.bend as R
import ../../src/bend/preferences_worker.bend as W
import ../../src/bend/preferences.bend as P
import ../../src/bend/session.bend as S
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/theme.bend as Theme
import ../../src/bend/actor.bend as A

type Stage is Data:
  Stage{ctx: C.Context, st: S.Session}

def session() -> S.Session:
  S.session_with_client_at(Cl.init("me", "irc.example"), "#initial", 6697)

def initial(path: String) -> Stage:
  +st = session()
  Stage{C.initial(W.Options{True{}, False{}, False{}, False{}}, st, 1, path), st}

def observed(pair: C.Context & S.Session) -> Stage:
  match pair:
    case (ctx, st): Stage{ctx, st}

def observe(stage: Stage) -> Stage:
  match stage:
    case Stage{ctx, st}: observed(C.observe(ctx, st, 1))

def taken(pair: R.State & Maybe<&2, R.Job>, gate: C.Gate, decision: Maybe<&2, Bool>, path: String, archive: Maybe<&2, C.Archive>, next: Nat, st: S.Session) -> Stage:
  match pair:
    case (prefs, _): Stage{C.wrap(C.Details{L.wrap(prefs), gate, decision, path, archive, next}), st}

def reading.details(value: C.Details, st: S.Session) -> Stage:
  match value:
    case C.Details{prefs, gate, decision, path, archive, next}: taken(R.take(L.state(prefs)), gate, decision, path, archive, next, st)

def reading(stage: Stage) -> Stage:
  match stage:
    case Stage{ctx, st}: reading.details(C.details(ctx), st)

def completed(result: C.Context & S.Session & List<&2, String> & Bool) -> Stage:
  match result:
    case (ctx, st, _, _): Stage{ctx, st}

def load(stage: Stage, got: Maybe<&2, P.Preferences>, code: U32) -> Stage:
  match stage:
    case Stage{ctx, st}: completed(C.loaded(ctx, st, 1, 1n, got, code))

def stored(history: Bool, cap: U32) -> P.Preferences:
  P.Preferences{False{}, True{}, False{}, history, cap, True{}, False{}, False{}, Nil{}, "#saved" <> Nil{}, True{}, Theme.Dark{}, True{}}

def settled(history: Bool, cap: U32) -> Stage:
  observe(load(reading(initial("")), Some{stored(history, cap)}, 0))

def before_archive(value: C.Details) -> Bool:
  match value:
    case C.Details{prefs, C.Waiting{1, "irc.example:6697"}, None{}, _, None{}, _}: L.waiting(prefs)
    case _: False{}

def gate_before_prefs(stage: Stage) -> Bool:
  match stage:
    case Stage{+ctx, st}: before_archive(C.details(ctx)) && Bool.not(C.history_allowed(ctx, st))

def request(value: C.Details, +read: Bool, +cap: U32, known: Bool) -> Bool:
  match value:
    case C.Details{_, C.Waiting{1, "irc.example:6697"}, decision, _, Some{C.Archive{0n, 1, "irc.example:6697", gotcap, gotread, _, _, _, False{}}}, 1n}:
      U32.is_eq(gotcap, cap) && Bool.not(R.changed_bool(read, gotread)) && Bool.not(R.changed_bool(C.decision_known(decision), known))
    case _: False{}

def requested(stage: Stage, read: Bool, cap: U32, known: Bool) -> Bool:
  match stage:
    case Stage{ctx, _}: request(C.details(ctx), read, cap, known)

def command(stage: Stage, text: String) -> Stage:
  match stage:
    case Stage{ctx, st}: Stage{ctx, S.st_of_keys(S.step_enter(st, text))}

def current.details(value: C.Details, +st: S.Session, gen: U32, ep: String) -> Bool:
  match value:
    case C.Details{_, gate, decision, _, archive, _}: C.archive_current(archive, gate, decision, st, gen, ep)

def current(stage: Stage, gen: U32, ep: String) -> Bool:
  match stage:
    case Stage{ctx, st}: current.details(C.details(ctx), st, gen, ep)

def same_archive(value: C.Details) -> Bool:
  match value:
    case C.Details{_, _, _, _, Some{C.Archive{0n, _, _, 3, True{}, _, _, _, _}}, 1n}: True{}
    case _: False{}

def retained_owned(stage: Stage) -> Bool:
  match stage:
    case Stage{ctx, _}: same_archive(C.details(ctx))

def ready_permission(stage: Stage) -> Bool:
  match stage:
    case Stage{ctx, +st}: C.history_allowed(C.prepared(L.wrap(R.Disabled{}), "", False{}), st)

def drop.waiting(step: A.DeferredStep) -> A.Deferred:
  match step:
    case A.Waiting{st}: st
    case _: A.Deferred{None{}, 0, A.AuthScope{"", 0, False{}}}

def drop.released(step: A.DeferredStep) -> Bool:
  match step:
    case A.Released{1, _}: True{}
    case _: False{}

def drop() -> Bool:
  drop.released(A.deferred_command(S.Begin{1}, drop.waiting(A.deferred_command(S.Drop{}, A.deferred_initial("irc.example", 6697, "me", False{})))))

# Production history.merge seam with outer archive_current bypassed: current_ep
# comes from Session (6697); snapshot_ep is an independent HistoryLoaded claim.
def merge_snap() -> Cl.Client:
  Cl.Client{"archive", "irc.example", Cl.buf_indexed("server", False{}, "", Cl.Line{Cl.Msg{}, "12:00:00", "archived", "alice", 1n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}) <> Nil{}, 0n, "old", Cl.settings0(), Cl.AuthIdle{}, 1n, False{}}

def merge_ports() -> Bool:
  +st = session()
  +local = Cl.init_with_cap("me", "irc.example", 1)
  +snap = merge_snap()
  +ok = C.history.merge(local, st, snap, "irc.example:6697")
  +bad = C.history.merge(local, st, snap, "irc.example:6667")
  +diag_bad = C.history.merge(local, st, Cl.client_log(snap, 0n, Cl.Error{}, "history read failed (5)"), "irc.example:6667")
  # Matching snapshot_ep imports (+ divider); mismatched port leaves local untouched.
  Bool.not(String.eq(CL.buf_texts(ok, 0n), CL.buf_texts(local, 0n)))
    && String.eq(CL.buf_texts(bad, 0n), CL.buf_texts(local, 0n))
    && Nat.is_eq(Cl.log_seq_of(diag_bad), Cl.log_seq_of(local))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("before prefs resolution no archive or history-save permission", gate_before_prefs(observe(initial(""))))
    Unit <- E.must("stored history off queues a no-read completion", requested(settled(False{}, 3), False{}, 3, True{}))
    Unit <- E.must("failed initial policy queues no archive read", requested(observe(load(reading(initial("")), None{}, 2)), False{}, Cl.settings_hist_cap(Cl.settings0()), False{}))
    Unit <- E.must("absent code0 permits original history defaults", requested(observe(load(reading(initial("")), None{}, 0)), True{}, Cl.settings_hist_cap(Cl.settings0()), True{}))
    Unit <- E.must("current exact scope and policy may complete", current(settled(True{}, 3), 1, "irc.example:6697"))
    Unit <- E.must("wrong gen or endpoint cannot complete", Bool.not(current(settled(True{}, 3), 2, "irc.example:6697") || current(settled(True{}, 3), 1, "IRC.EXAMPLE:6697")))
    Unit <- E.must("history-cap or enabled-policy edit invalidates owned completion", Bool.not(current(command(settled(True{}, 3), "/set hist_cap 1"), 1, "irc.example:6697") || current(command(settled(True{}, 3), "/set history off"), 1, "irc.example:6697")))
    Unit <- E.must("changed policy retains one owned archive until completion", retained_owned(observe(command(settled(True{}, 3), "/set hist_cap 1"))))
    Unit <- E.must("failed read is not retroactively authorized without explicit edit", Bool.not(ready_permission(load(reading(initial("")), None{}, 2))))
    Unit <- E.must("accepted history on can authorize later IO after failed read", ready_permission(command(load(reading(initial("")), None{}, 2), "/set history on")))
    Unit <- E.must("Drop then matching Begin releases idle without dialing", drop())
    Unit <- E.must("history.merge matching port imports; mismatched port fail-closed", merge_ports())
    IO.print("live_context=ok\n")
