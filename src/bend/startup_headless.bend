# SPDX-License-Identifier: Apache-2.0
# Headless preparation precedes actor registration. It performs one preference
# read, then imports an auth-free archive using the resolved history policy.
import Base
import ./buffer.bend as Cl
import ./session.bend as S
import ./preferences.bend as P
import ./preferences_runtime.bend as R
import ./preferences_live.bend as LP
import ./preferences_worker.bend as W
import ./preferences_io.bend as F
import ./history_startup.bend as H
import ./history_startup_io.bend as Archive
import ./live_context.bend as LC

def resolve.finished(result: LP.Context & S.Session & List<&2, String> & Bool, +code: U32) -> LP.Context & S.Session & Bool:
  match result:
    # This module requires a preconnect Session. There is no welcome to flush.
    case (ctx, +st, _, _): (ctx, st, U32.is_zero(code) || LC.explicit_history(st))

def resolve.read(got: Maybe<&2, P.Preferences> & U32, ctx: LP.Context, st: S.Session, gen: U32, ticket: Nat) -> LP.Context & S.Session & Bool:
  match got:
    case (prefs, +code): resolve.finished(LP.loaded(ctx, st, gen, ticket, prefs, code), code)

def resolve.taken(pair: R.State & Maybe<&2, R.Job>, st: S.Session, gen: U32, got: Maybe<&2, P.Preferences> & U32) -> LP.Context & S.Session & Bool:
  match pair:
    case (state, None{}): (LP.wrap(state), st, True{})
    case (state, Some{R.Read{ticket, _, _, _, _}}): resolve.read(got, LP.wrap(state), st, gen, ticket)
    case (state, Some{_}): (LP.wrap(state), LP.notice(2, "read", st), False{})

# Pure characterization seam: identical ownership/merge path to prepare,
# without launching a second worker or touching configuration/history files.
def resolve(options: W.Options, +st: S.Session, +gen: U32, got: Maybe<&2, P.Preferences> & U32) -> LP.Context & S.Session & Bool:
  resolve.taken(R.take(LP.state(LP.initial(options, st, gen))), st, gen, got)

def archive.install(+snapshot: Cl.Client, ctx: LP.Context, +st: S.Session, allowed: Bool) -> LP.Context & S.Session & Bool:
  (ctx, S.session_set_client(st, H.install_startup(H.report_diagnostics(S.session_cl(st), snapshot), snapshot)), allowed)

def archive.pick(read: Bool, ctx: LP.Context, +st: S.Session, +path: String, allowed: Bool) -> IO(LP.Context & S.Session & Bool):
  match read:
    case False{}: IO.pure(LP.Context & S.Session & Bool, (ctx, st, allowed))
    case True{}:
      +cl = S.session_cl(st)
      do IO<LP.Context & S.Session & Bool>:
        snapshot : Cl.Client <- Archive.load(path, LC.endpoint(st), Cl.settings_hist_cap(Cl.get_settings(cl)), Cl.nick_of(cl), Cl.server_of(cl), LC.now(cl))
        return archive.install(snapshot, ctx, st, allowed)

def archive.current(ctx: LP.Context, +st: S.Session, +allowed: Bool, +path: String) -> IO(LP.Context & S.Session & Bool):
  archive.pick(allowed && Bool.not(String.is_empty(path)) && Cl.settings_history(Cl.get_settings(S.session_cl(st)))
    && Bool.not(U32.is_zero(Cl.settings_hist_cap(Cl.get_settings(S.session_cl(st))))), ctx, st, path, allowed)

def archive.prepared(result: LP.Context & S.Session & Bool, path: String) -> IO(LP.Context & S.Session & Bool):
  match result:
    case (ctx, st, allowed): archive.current(ctx, st, allowed, path)

def prepare.taken(pair: R.State & Maybe<&2, R.Job>, st: S.Session, gen: U32, path: String) -> IO(LP.Context & S.Session & Bool):
  match pair:
    case (state, None{}): archive.prepared((LP.wrap(state), st, True{}), path)
    case (state, Some{R.Read{ticket, host, port, _, _}}):
      do IO<LP.Context & S.Session & Bool>:
        loaded : Maybe<&2, P.Preferences> & U32 <- F.load(host, port)
        archive.prepared(resolve.read(loaded, LP.wrap(state), st, gen, ticket), path)
    case (state, Some{_}): archive.prepared((LP.wrap(state), LP.notice(2, "read", st), False{}), path)

def prepare(options: W.Options, +st: S.Session, +gen: U32, path: String) -> IO(LP.Context & S.Session & Bool):
  prepare.taken(R.take(LP.state(LP.initial(options, st, gen))), st, gen, path)
