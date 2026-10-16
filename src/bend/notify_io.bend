# SPDX-License-Identifier: Apache-2.0
# Bounded desktop-notification delivery through an explicit helper program.
# Unconfigured (no BIRC_NOTIFY_HELPER) sends nothing and reports nothing:
# notifications are opt-in until a default helper is provisioned. Unknown
# helper names fail closed without spawning. Helper output is never copied
# into diagnostics; only the safe stage label and numeric code are kept.
#
# Async delivery (N9 full): the frame path never runs Process.run. The
# bounded queue drains through ONE detached worker per handoff (never one
# spawn per request); the worker reuses the same bounded argv, bounded run,
# and stage-label-only diagnostics as send(), delivering jobs in FIFO order.
# Failures post Sess.UiError through the supplied notice channel (the
# existing lazy-log path); success stays silent. Marks are consumed only for
# reqs handed to the worker: staged dispatch (Notify.stage) advances a mark
# only when its req is admitted, and the live step retains the queue across
# undeliverable chunks, so nothing is lost. Unconfigured (no helper) or an
# unknown helper spawns nothing and retains the queue, quiet.
import Base
import ./notify.bend as Notify
import ./diagnostic.bend as Diagnostic
import ./session.bend as Sess
import ./helper_io.bend as H

# Empty default: a missing or blank BIRC_NOTIFY_HELPER stays unconfigured.
def spec() -> H.Spec:
  H.Spec{"BIRC_NOTIFY_HELPER", "", 512, 2000}

def program.env(got: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  H.name_opt_got(got, "")

def program() -> IO(Maybe<&2, String>):
  H.name_opt(spec())

# Basename of a helper path: the segment after the last slash. Suffix
# matching is forbidden: x-notify-send must not select notify-send.
def base_last.go(xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{h, t}: base_last.go(t, h)

def base_of(+program: String) -> String:
  base_last.go(String.split(program, Chr{47}), "")

def is_helper(+program: String, +name: String) -> Bool:
  String.eq(base_of(program), name)

def known_base(+base: String) -> Bool:
  String.eq(base, "notify-send") || String.eq(base, "osascript") || String.eq(base, "birc-notify")

def known_helper(+helper: String) -> Bool:
  known_base(base_of(helper))

def can_deliver(+helper: Maybe<&2, String>) -> Bool:
  match helper:
    case None{}: False{}
    case Some{+h}: known_helper(h)

# AppleScript string escaping: backslash and double quote only.
def esc.go(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{92}, t}: SCon{Chr{92}, SCon{Chr{92}, esc.go(t)}}
    case SCon{Chr{34}, t}: SCon{Chr{92}, SCon{Chr{34}, esc.go(t)}}
    case SCon{h, t}: SCon{h, esc.go(t)}

def quote(+s: String) -> String:
  SCon{Chr{34}, ""} ++ s ++ SCon{Chr{34}, ""}

def script(+title: String, +body: String) -> String:
  "display notification " ++ quote(esc.go(body)) ++ " with title " ++ quote(esc.go(title))

# notify-send takes "--" before title/body so a literal "--help" title is
# data, never a flag.
def args_for.kind(+req: Notify.Req, send: Bool, osa: Bool) -> List<&1, String>:
  match send:
    case True{}: "--" <> Notify.req_title(req) <> Notify.req_body(req) <> Nil{}
    case False{}:
      match osa:
        case True{}: "-e" <> script(Notify.req_title(req), Notify.req_body(req)) <> Nil{}
        case False{}: Nil{}

def args_for.base(+base: String, +req: Notify.Req) -> List<&1, String>:
  args_for.kind(req, String.eq(base, "notify-send") || String.eq(base, "birc-notify"), String.eq(base, "osascript"))

def args_for(+program: String, +req: Notify.Req) -> List<&1, String>:
  args_for.base(base_of(program), req)

def send_result(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Maybe<&2, String>:
  Diagnostic.process_result("notify", got)

def send.run(+program: String, args: List<&1, String>) -> IO(Maybe<&2, String>):
  match args:
    case Nil{}: IO.pure(Maybe<&2, String>, Some{"notify failed (unknown helper)"})
    case Con{h, t}:
      do IO<Maybe<&2, String>>:
        got : Result<&1, &1, U32 & String, U32 & (String & String)> <- H.run_named(program, spec(), h <> t, "")
        return send_result(got)

def send.with(+program: Maybe<&2, String>, +req: Notify.Req) -> IO(Maybe<&2, String>):
  match program:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{+helper}: send.run(helper, args_for(helper, req))

def send(+req: Notify.Req) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    helper : Maybe<&2, String> <- program()
    send.with(helper, req)

# Default-helper resolution: an explicit BIRC_NOTIFY_HELPER wins; otherwise
# the caller-supplied platform default applies (the live loop passes
# Sys.notify_default: osascript on macOS, notify-send elsewhere). Either way
# args_for still gates delivery on the known-helper basename, and an
# undeliverable helper keeps the queue quiet and retained.
def with_default(+explicit: Maybe<&2, String>, +default: String) -> Maybe<&2, String>:
  match explicit:
    case Some{+h}: Some{h}
    case None{}: Some{default}

def program_or_default(+default: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    helper : Maybe<&2, String> <- program()
    return with_default(helper, default)

def post_msg(+evt: Chan(Sess.UiMsg), +m: Sess.UiMsg) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, Sess.UiMsg, Unit> <- Chan.send(Sess.UiMsg, evt, m)
    return Unit{}

def post_diag(diag: Maybe<&2, String>, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match diag:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+msg}: post_msg(evt, Sess.UiError{msg})

def post_on_failure(diag: Maybe<&2, String>, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match notice:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+evt}: post_diag(diag, evt)

def run_async(+helper: String, +req: Notify.Req, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  do IO<Unit>:
    diag : Maybe<&2, String> <- send.run(helper, args_for(helper, req))
    post_on_failure(diag, notice)

def send_async.with(+helper: Maybe<&2, String>, +req: Notify.Req, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match helper:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+h}: IO.spawn(Unit, run_async(h, req, notice))

# Off-frame-path send: resolves the explicit helper, then hands the bounded
# run to a detached worker. No helper means no spawn and no diagnostic.
def send_async(+req: Notify.Req, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  do IO<Unit>:
    helper : Maybe<&2, String> <- program()
    send_async.with(helper, req, notice)

# Single-worker body: deliver every handed job in FIFO order on one
# detached worker, reusing the bounded run and stage-label-only diagnostics.
def run_jobs.go(fuel: Nat, +helper: String, +jobs: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+p:
      match jobs:
        case Nil{}: IO.pure(Unit, Unit{})
        case Con{+r, t}:
          do IO<Unit>:
            diag : Maybe<&2, String> <- send.run(helper, args_for(helper, r))
            Unit <- post_on_failure(diag, notice)
            run_jobs.go(p, helper, t, notice)

def run_jobs(+helper: String, +jobs: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  run_jobs.go(List.length(&2, Notify.Req, jobs), helper, jobs, notice)

def post_done(notice: Maybe<&2, Chan(Sess.UiMsg)>, +ticket: Nat, +endpoint: String) -> IO(Unit):
  match notice:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+evt}: post_msg(evt, Sess.NotifyDone{ticket, endpoint})

def run_jobs_done(+helper: String, +jobs: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>, +ticket: Nat, +endpoint: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- run_jobs(helper, jobs, notice)
    post_done(notice, ticket, endpoint)

def send_many.nonempty(empty: Bool, +helper: String, +reqs: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match empty:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.spawn(Unit, run_jobs(helper, reqs, notice))

def send_many.known(known: Bool, +helper: String, +reqs: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match known:
    case True{}: send_many.nonempty(List.is_empty(&2, Notify.Req, reqs), helper, reqs, notice)
    case False{}: post_on_failure(Some{"notify failed (unknown helper)"}, notice)

def send_many.with(+helper: Maybe<&2, String>, +reqs: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match helper:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+h}: send_many.known(known_helper(h), h, reqs, notice)

# One detached worker drains the whole staged list in FIFO order; unconfigured
# sends nothing. An unknown helper reports one stage-label diagnostic without
# spawning; an empty list spawns nothing.
def send_many(+reqs: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  do IO<Unit>:
    helper : Maybe<&2, String> <- program()
    send_many.with(helper, reqs, notice)

def send_queued.jobs(+helper: String, +kept: Notify.Queue, +jobs: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Notify.Queue):
  match jobs:
    case Nil{}: IO.pure(Notify.Queue, kept)
    case Con{_, _}:
      do IO<Notify.Queue>:
        Unit <- IO.spawn(Unit, run_jobs(helper, jobs, notice))
        return kept

def send_queued.drained(pair: Notify.Queue & List<&2, Notify.Req>, +helper: String, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Notify.Queue):
  match pair:
    case (+kept, +jobs): send_queued.jobs(helper, kept, jobs, notice)

def send_queued.known(known: Bool, +helper: String, +q: Notify.Queue, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Notify.Queue):
  match known:
    case True{}: send_queued.drained(Notify.drain_all(q), helper, notice)
    case False{}: IO.pure(Notify.Queue, q)

# Single-worker queue drain: hand every pending job to ONE detached worker in
# FIFO order and return the kept queue (empty after a handoff). No helper or
# an unknown helper spawns nothing and retains the full queue, quiet.
def send_queued.with(+helper: Maybe<&2, String>, +q: Notify.Queue, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Notify.Queue):
  match helper:
    case None{}: IO.pure(Notify.Queue, q)
    case Some{+h}: send_queued.known(known_helper(h), h, q, notice)

def send_queued(+q: Notify.Queue, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Notify.Queue):
  do IO<Notify.Queue>:
    helper : Maybe<&2, String> <- program()
    send_queued.with(helper, q, notice)

def notify_live_spawn.active(active: Maybe<&2, Nat>, +h: String, +nl2: Sess.NotifyLive, +sess2: Sess.Session, +outs: List<&2, String>, +handed: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>, +endpoint: String) -> IO(Sess.NotifyLive & Sess.Session & List<&2, String>):
  match active:
    case None{}:
      do IO<(Sess.NotifyLive & Sess.Session & List<&2, String>)>:
        Unit <- IO.spawn(Unit, run_jobs(h, handed, notice))
        return (nl2, sess2, outs)
    case Some{+ticket}:
      do IO<(Sess.NotifyLive & Sess.Session & List<&2, String>)>:
        Unit <- IO.spawn(Unit, run_jobs_done(h, handed, notice, ticket, endpoint))
        return (nl2, sess2, outs)

def notify_live_spawn(+h: String, +nl2: Sess.NotifyLive, +sess2: Sess.Session, +outs: List<&2, String>, +handed: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Sess.NotifyLive & Sess.Session & List<&2, String>):
  match handed:
    case Nil{}: IO.pure(Sess.NotifyLive & Sess.Session & List<&2, String>, (nl2, sess2, outs))
    case Con{_, _}:
      +active = Sess.notify_live_active(nl2)
      +endpoint = Sess.notify_live_endpoint(nl2)
      notify_live_spawn.active(active, h, nl2, sess2, outs, handed, notice, endpoint)

def notify_live_handed(deliver: Bool, +helper: Maybe<&2, String>, +nl2: Sess.NotifyLive, +sess2: Sess.Session, +outs: List<&2, String>, +handed: List<&2, Notify.Req>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Sess.NotifyLive & Sess.Session & List<&2, String>):
  match deliver:
    case False{}: IO.pure(Sess.NotifyLive & Sess.Session & List<&2, String>, (nl2, sess2, outs))
    case True{}:
      match helper:
        case None{}: IO.pure(Sess.NotifyLive & Sess.Session & List<&2, String>, (nl2, sess2, outs))
        case Some{+h}: notify_live_spawn(h, nl2, sess2, outs, handed, notice)

def notify_live_wrapped(stepped: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>, deliver: Bool, +helper: Maybe<&2, String>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Sess.NotifyLive & Sess.Session & List<&2, String>):
  match stepped:
    case (nl2, sess2, outs, handed):
      notify_live_handed(deliver, helper, nl2, sess2, outs, handed, notice)

# Live per-chunk entry: resolve deliverability once from the caller-resolved
# helper, feed + stage the chunk, and hand newly staged jobs to ONE worker.
# Undeliverable (or empty) steps spawn nothing: the queue retains admitted
# reqs and the floor keeps unadmitted rows for retry, so nothing is lost.
# Net-loop adoption resolves the helper, then calls this per chunk:
#   default : String <- T.Sys.notify_default()
#   helper : Maybe<String> <- NotifyIO.program_or_default(default)
#   ... NotifyIO.notify_live_io(nl, st, chunk, now_ms, helper, notice) ...
def notify_live_io(+nl: Sess.NotifyLive, +sess: Sess.Session, +chunk: List<&2, U32>, +now_ms: U32, +helper: Maybe<&2, String>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Sess.NotifyLive & Sess.Session & List<&2, String>):
  +deliver = can_deliver(helper)
  notify_live_wrapped(Sess.notify_live_step(nl, sess, chunk, now_ms, deliver), deliver, helper, notice)
