# SPDX-License-Identifier: Apache-2.0
# n9-final R1: held-lease latch with received completion (physical, C backend).
# The JS held suite (notify_held.bend) proves lease retention across
# reset/off/on/cancel with spawn counts, but its helper completes before the
# teardowns run, so the "blocked" ticket is purely logical there. Here the
# fake helper BLOCKS on a release latch (logs start, waits for the test to
# create helper ++ ".release", logs done) on the C backend with real thread
# concurrency, always inside the production 2s helper timeout. The test takes
# an actual child start ACK (polls the owned log until the start line lands),
# then runs reset/off/on/cancel plus wrong-ticket/origin completions while
# demonstrably blocked (log pinned at the bare start line: no second worker,
# nothing latched), releases the latch, and threads the RECEIVED exact
# completion (ticket, origin) through the current state to run the FIFO
# exactly once. Wrong-ticket/origin received completions latch nothing (pure
# gates also pinned in notify_full.bend). Synthetic fixtures only. The helper
# path comes from BIRC_NOTIFY_HELPER (the Makefile recipe creates the
# latch-blocking notify-send fake); the log is helper ++ ".log". The
# no-release negative uses BIRC_NOTIFY_HELPER_UNREL: a fresh owned
# directory holding the SAME admitted basename (production gates
# delivery on the exact basename, so a renamed copy would never
# spawn); its latch is never created, so worker3 genuinely expires.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/frame.bend as Fr
import ../../src/bend/notify.bend as Notify
import ../../src/bend/notify_io.bend as NotifyIO
import ../../src/bend/session.bend as Sess

def scope() -> String:
  "irc.test:6697"

def other_scope() -> String:
  "other.test:6697"

def st0() -> Sess.Session:
  Sess.session_with_client(Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #room"), "#room")

def floor0() -> Nat:
  Cl.log_seq_of(Sess.session_cl(st0()))

def chunk1() -> List<&2, U32>:
  Fr.string_to_octets(":bob!u@h PRIVMSG #room :hi me\r\n")

def chunk_new() -> List<&2, U32>:
  Fr.string_to_octets(":frank!u@h PRIVMSG #room :ping me\r\n")

def nl_ep() -> Sess.NotifyLive:
  Sess.notify_live_init_ep(Notify.on(), floor0(), scope())

def live_nl(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> Sess.NotifyLive:
  match r:
    case (nl, _, _, _): nl

def live_sess(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> Sess.Session:
  match r:
    case (_, st, _, _): st

def live_outs_list(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> List<&2, String>:
  match r:
    case (_, _, outs, _): outs

def live_handed_list(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> List<&2, Notify.Req>:
  match r:
    case (_, _, _, handed): handed

def comp_nl(r: Sess.NotifyLive & List<&2, Notify.Req> & Bool) -> Sess.NotifyLive:
  match r:
    case (nl, _, _): nl

def comp_jobs_list(r: Sess.NotifyLive & List<&2, Notify.Req> & Bool) -> List<&2, Notify.Req>:
  match r:
    case (_, jobs, _): jobs

def comp_rel_shown(r: Sess.NotifyLive & List<&2, Notify.Req> & Bool) -> String:
  match r:
    case (_, _, True{}): "true"
    case (_, _, False{}): "false"

def req_titles(rs: List<&2, Notify.Req>) -> String:
  match rs:
    case Nil{}: ""
    case Con{r, t}: Notify.req_title(r) ++ ";" ++ req_titles(t)

def active_shown(+got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "none"
    case Some{n}: Nat.show(n)

def nl_active_shown(+nl: Sess.NotifyLive) -> String:
  active_shown(Sess.notify_live_active(nl))

# Manual re-enable after off (same active/origin, queue empty, enabled).
# There is no production notify_live_on; the test rebuilds the NL to model
# off->on while the physical worker stays blocked.
def nl_on(+nl: Sess.NotifyLive) -> Sess.NotifyLive:
  match nl:
    case Sess.NotifyLive{_, +q, +scanned, +active, +next, +endpoint, +origin, +claimed}:
      Sess.NotifyLive{Notify.on(), q, scanned, active, next, endpoint, origin, claimed}

def cancel_nl(r: Sess.NotifyLive & Bool) -> Sess.NotifyLive:
  match r:
    case (nl, _): nl

def log_got(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(String):
  match pair:
    case (f, Fail{_}):
      do IO<String>:
        Unit <- File.close(f)
        IO.pure(String, "")
    case (f, Done{+bytes}):
      do IO<String>:
        Unit <- File.close(f)
        IO.pure(String, Fr.octets_to_string(bytes))

def log_opened(result: Result<&1, &1, U32 & String, File>) -> IO(String):
  match result:
    case Fail{_}: IO.pure(String, "")
    case Done{f}:
      do IO<String>:
        pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 4096)
        log_got(pair)

def read_log(+h: String) -> IO(String):
  do IO<String>:
    result : Result<&1, &1, U32 & String, File> <- File.open(h ++ ".log", "r")
    log_opened(result)

def recv_got(g: Maybe<&1, Sess.UiMsg>) -> IO(Sess.UiMsg):
  match g:
    case None{}: IO.die(Sess.UiMsg, 1, "completion missing")
    case Some{+m}: IO.pure(Sess.UiMsg, m)

def recv_done(+evt: Chan(Sess.UiMsg)) -> IO(Sess.UiMsg):
  do IO<Sess.UiMsg>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    recv_got(g)

def done_ticket(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{+ticket, _}: Nat.show(ticket)
    case _: "other"

def done_endpoint(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{_, +ep}: ep
    case _: "other"

def recv_ticket(+m: Sess.UiMsg) -> Nat:
  match m:
    case Sess.NotifyDone{+ticket, _}: ticket
    case _: 0n

def recv_endpoint(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{_, +ep}: ep
    case _: "other"

def step1() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_ep(), st0(), chunk1(), 0, True{})

def nl1() -> Sess.NotifyLive:
  live_nl(step1())

def sess1() -> Sess.Session:
  live_sess(step1())

def nl_reset() -> Sess.NotifyLive:
  Sess.notify_live_reset_endpoint(nl1(), other_scope(), Cl.log_seq_of(Sess.session_cl(sess1())))

def step_reset() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_reset(), sess1(), chunk_new(), 0, True{})

def sess_r() -> Sess.Session:
  live_sess(step_reset())

def nl_off() -> Sess.NotifyLive:
  Sess.notify_live_off(live_nl(step_reset()))

def step_off() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_off(), sess_r(), chunk_new(), 0, True{})

def sess_o() -> Sess.Session:
  live_sess(step_off())

def nl_reon() -> Sess.NotifyLive:
  nl_on(live_nl(step_off()))

def step_on() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_reon(), sess_o(), chunk_new(), 0, True{})

def sess_n() -> Sess.Session:
  live_sess(step_on())

def nl_cancelled() -> Sess.NotifyLive:
  cancel_nl(Sess.notify_live_cancel(live_nl(step_on()), other_scope()))

def step_cancel() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_cancelled(), sess_n(), chunk_new(), 0, True{})

def sess_c() -> Sess.Session:
  live_sess(step_cancel())

def nl_c() -> Sess.NotifyLive:
  live_nl(step_cancel())

def comp_wrong_ticket() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(nl_c(), 99n, scope())

def comp_wrong_origin() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(nl_c(), 1n, other_scope())

# Negatives thread forward: wrong-ticket then wrong-origin completions
# latch nothing, and the received completion runs on their RETURNED state
# (not a reconstituted nl_c()), so negative callbacks cannot be bypassed
# by rebuilding the live state.
def comp_wrong_chained() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(comp_nl(comp_wrong_ticket()), 1n, other_scope())

def comp_received(+ticket: Nat, +endpoint: String) -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(comp_nl(comp_wrong_chained()), ticket, endpoint)

def held_start() -> String:
  "start -- bob in #room <bob> hi me\n"

def held_released() -> String:
  held_start() ++ "done -- bob in #room <bob> hi me\n"

def held_final() -> String:
  held_released() ++ "start -- frank in #room <frank> ping me\ndone -- frank in #room <frank> ping me\n"

# Fresh-namespace negative log: h2.log carries ONLY worker3 (the released
# phase's cumulative lines live in h.log, untouched by the negative).
def held_unrel_expired() -> String:
  "start -- bob in #room <bob> hi me\nexpired -- bob in #room <bob> hi me\n"

# The latch-blocking helper always finishes inside send.run's 2s helper
# timeout, so each worker posts exactly one message: its ticket completion
# (NotifyDone), never a timeout diagnostic. The channel is FIFO, so a single
# receive that pins (ticket, origin) proves both the exact completion AND the
# absence of any diagnostic. The received message is returned (not
# discarded): the release threads its ticket/origin through current state.
def check_exact_done(+evt: Chan(Sess.UiMsg), +ticket: String, +endpoint: String, +tag_t: String, +tag_e: String) -> IO(Sess.UiMsg):
  do IO<Sess.UiMsg>:
    +done : Sess.UiMsg <- recv_done(evt)
    Unit <- E.must_eq(tag_t, done_ticket(done), ticket)
    Unit <- E.must_eq(tag_e, done_endpoint(done), endpoint)
    IO.pure(Sess.UiMsg, done)

# Child start ACK: poll the owned log until the helper's start line lands
# (bounded fuel, 50ms beats). The lazy continuation keeps the single
# self-recursive shape the backend accepts (no forward refs).
def await_start.branch(ready: Bool, retry: Unit -> IO(Unit)) -> IO(Unit):
  match ready:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: retry(Unit{})

def await_start.go(fuel: Nat, +h: String) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "worker never started")
    case 1n+p:
      do IO<Unit>:
        Unit <- IO.sleep(50)
        got : String <- read_log(h)
        await_start.branch(String.eq(got, held_start()), _u => await_start.go(p, h))

# Release latch: creating helper ++ ".release" unblocks the helper, which
# then logs done and exits 0 inside the timeout.
def release_opened(result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "release latch failed")
    case Done{f}: File.close(f)

def release_worker(+h: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1, &1, U32 & String, File> <- File.open(h ++ ".release", "w")
    release_opened(result)

def check_log(+h: String, +want: String, +tag: String) -> IO(Unit):
  do IO<Unit>:
    got : String <- read_log(h)
    E.must_eq(tag, got, want)

def check_hold(+h: String, +want: String, +tag: String) -> IO(Unit):
  do IO<Unit>:
    got : String <- read_log(h)
    E.must_eq(tag, got, want)

# Spawn arguments are bound before the call: nesting several pure step
# projections directly inside the spawn application trips the C backend's
# arity limit, while pre-bound arguments compile fine.
def check_reset(+h: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    +rnl : Sess.NotifyLive <- IO.pure(Sess.NotifyLive, live_nl(step_reset()))
    +routs : List<&2, String> <- IO.pure(List<&2, String>, live_outs_list(step_reset()))
    +rhanded : List<&2, Notify.Req> <- IO.pure(List<&2, Notify.Req>, live_handed_list(step_reset()))
    Unit <- E.must_eq("held reset keeps no second worker",
      nl_active_shown(rnl), "1")
    Unit <- E.must_eq("held reset hands nothing while blocked",
      req_titles(rhanded), "")
    sr : Sess.Session <- IO.pure(Sess.Session, sess_r())
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, rnl, sr, routs, rhanded, Some{evt})
    check_hold(h, held_start(), "held reset spawns no second worker")

def check_off(+h: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    +onl : Sess.NotifyLive <- IO.pure(Sess.NotifyLive, live_nl(step_off()))
    +oouts : List<&2, String> <- IO.pure(List<&2, String>, live_outs_list(step_off()))
    +ohanded : List<&2, Notify.Req> <- IO.pure(List<&2, Notify.Req>, live_handed_list(step_off()))
    so : Sess.Session <- IO.pure(Sess.Session, sess_o())
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, onl, so, oouts, ohanded, Some{evt})
    check_hold(h, held_start(), "held off spawns no second worker")

def check_on(+h: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    +nnl : Sess.NotifyLive <- IO.pure(Sess.NotifyLive, live_nl(step_on()))
    +nouts : List<&2, String> <- IO.pure(List<&2, String>, live_outs_list(step_on()))
    +nhanded : List<&2, Notify.Req> <- IO.pure(List<&2, Notify.Req>, live_handed_list(step_on()))
    Unit <- E.must_eq("held on keeps no second worker",
      nl_active_shown(nnl), "1")
    sn : Sess.Session <- IO.pure(Sess.Session, sess_n())
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, nnl, sn, nouts, nhanded, Some{evt})
    check_hold(h, held_start(), "held on spawns no second worker")

def check_cancel(+h: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    +cnl : Sess.NotifyLive <- IO.pure(Sess.NotifyLive, nl_c())
    +couts : List<&2, String> <- IO.pure(List<&2, String>, live_outs_list(step_cancel()))
    +chanded : List<&2, Notify.Req> <- IO.pure(List<&2, Notify.Req>, live_handed_list(step_cancel()))
    Unit <- E.must_eq("held cancel keeps no second worker",
      nl_active_shown(cnl), "1")
    sc : Sess.Session <- IO.pure(Sess.Session, sess_c())
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, cnl, sc, couts, chanded, Some{evt})
    check_hold(h, held_start(), "held cancel spawns no second worker")

def check_wrong(+h: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("held wrong ticket latches nothing",
      comp_rel_shown(comp_wrong_ticket()), "false")
    Unit <- E.must_eq("held wrong ticket runs nothing",
      req_titles(comp_jobs_list(comp_wrong_ticket())), "")
    Unit <- E.must_eq("held wrong origin latches nothing",
      comp_rel_shown(comp_wrong_origin()), "false")
    Unit <- E.must_eq("held wrong origin keeps worker",
      nl_active_shown(comp_nl(comp_wrong_origin())), "1")
    Unit <- E.must_eq("held chained wrong keeps worker",
      nl_active_shown(comp_nl(comp_wrong_chained())), "1")
    Unit <- E.must_eq("held chained wrong runs nothing",
      req_titles(comp_jobs_list(comp_wrong_chained())), "")
    check_hold(h, held_start(), "held wrong-ticket checks spawn nothing")

def run_teardowns(+h: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- check_reset(h, evt)
    Unit <- check_off(h, evt)
    Unit <- check_on(h, evt)
    Unit <- check_cancel(h, evt)
    Unit <- check_wrong(h)
    IO.pure(Unit, Unit{})

# No-release negative: a third worker runs the same jobs with no release
# latch, on a FRESH exact owned helper path h2 (BIRC_NOTIFY_HELPER_UNREL:
# a fresh owned directory holding the SAME admitted notify-send
# basename). The released phase leaves h.release behind and the fake
# never consumes it, so reusing h would hand worker3 a stale release
# (done, not expired); a renamed copy would never spawn at all
# (production gates on the exact basename). The fresh latch h2.release
# is never created: the helper expires distinctly (expired line,
# exit 1, inside the 2s production deadline), the worker posts its
# diagnostic FIRST (never a done-stamped success), and h2.log carries
# no done line.
def run_unreleased(+h2: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    +jobs3 : List<&2, Notify.Req> <- IO.pure(List<&2, Notify.Req>, live_handed_list(step1()))
    Unit <- NotifyIO.run_jobs_done(h2, jobs3, Some{evt}, 3n, scope())
    +first : Sess.UiMsg <- recv_done(evt)
    Unit <- E.must_eq("held unreleased posts diagnostic first", done_ticket(first), "other")
    Unit <- E.must_eq("held unreleased diagnostic not done", done_endpoint(first), "other")
    check_log(h2, held_unrel_expired(), "held unreleased logs expired, no done")

def run_released(+h: String, +h2: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- release_worker(h)
    +done : Sess.UiMsg <- check_exact_done(evt, "1", scope(), "held completion ticket exact", "held completion origin exact")
    Unit <- check_log(h, held_released(), "held worker1 released within timeout")
    +ticket : Nat <- IO.pure(Nat, recv_ticket(done))
    +endpoint : String <- IO.pure(String, recv_endpoint(done))
    +jobs : List<&2, Notify.Req> <- IO.pure(List<&2, Notify.Req>, comp_jobs_list(comp_received(ticket, endpoint)))
    +fnl : Sess.NotifyLive <- IO.pure(Sess.NotifyLive, comp_nl(comp_received(ticket, endpoint)))
    Unit <- E.must_eq("held exact runs fifo once", req_titles(jobs), "frank in #room;")
    Unit <- E.must_eq("held exact releases", comp_rel_shown(comp_received(ticket, endpoint)), "true")
    sc : Sess.Session <- IO.pure(Sess.Session, sess_c())
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, fnl, sc, Nil{}, jobs, Some{evt})
    _ : Sess.UiMsg <- check_exact_done(evt, "2", other_scope(), "held fifo completion ticket", "held fifo completion endpoint")
    Unit <- check_log(h, held_final(), "held two workers total, fifo once")
    Unit <- run_unreleased(h2, evt)
    IO.print("notify_held_blocked=ok")

def run_spawned(+h: String, +h2: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- run_teardowns(h, evt)
    # One beat for any stray second spawn to hit the log; the helper still
    # holds the first worker until its timeout.
    Unit <- IO.sleep(300)
    Unit <- check_hold(h, held_start(), "held across teardowns: still one worker")
    run_released(h, h2, evt)

def run_held(+h: String, +h2: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("helper nonempty", Bool.not(String.is_empty(h)))
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +fnl : Sess.NotifyLive <- IO.pure(Sess.NotifyLive, nl1())
    +fouts : List<&2, String> <- IO.pure(List<&2, String>, live_outs_list(step1()))
    +fhanded : List<&2, Notify.Req> <- IO.pure(List<&2, Notify.Req>, live_handed_list(step1()))
    Unit <- E.must_eq("held first hands bob", req_titles(fhanded), "bob in #room;")
    Unit <- E.must_eq("held first worker ticket 1", nl_active_shown(fnl), "1")
    s1 : Sess.Session <- IO.pure(Sess.Session, sess1())
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, fnl, s1, fouts, fhanded, Some{evt})
    # Actual child start ACK: the blocked helper holds the worker on the
    # release latch, so this poll lands strictly between start and done.
    Unit <- await_start.go(40n, h)
    +log1 : String <- read_log(h)
    Unit <- E.must_eq("worker held: started, not done", log1, held_start())
    run_spawned(h, h2, evt)

# Second owned helper for the no-release negative: exact path from
# BIRC_NOTIFY_HELPER_UNREL (fresh directory, same admitted basename).
def unrel_program.env(got: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match got:
    case Fail{_}: None{}
    case Done{+value}: Bool.pick(Maybe<&2, String>, String.is_empty(value), None{}, Some{value})

def unrel_program() -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    got : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_NOTIFY_HELPER_UNREL")
    return unrel_program.env(got)

def deliver_unrel(+h: String, unrel: Maybe<&2, String>) -> IO(Unit):
  match unrel:
    case None{}: IO.die(Unit, 1, "no unreleased helper resolved")
    case Some{+h2}: run_held(h, h2)

def deliver(helper: Maybe<&2, String>, unrel: Maybe<&2, String>) -> IO(Unit):
  match helper:
    case None{}: IO.die(Unit, 1, "no helper resolved")
    case Some{+h}: deliver_unrel(h, unrel)

def main() -> IO(Unit):
  do IO<Unit>:
    helper : Maybe<&2, String> <- NotifyIO.program_or_default("fallback-default")
    unrel : Maybe<&2, String> <- unrel_program()
    deliver(helper, unrel)
