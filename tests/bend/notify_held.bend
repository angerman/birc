# SPDX-License-Identifier: Apache-2.0
# n9-bind3 GATE 1: R1 held-helper lease qualification (physical spawn counts).
# Blocked ticket + reset/off/on/cancel + new ticket NEVER spawns 2 workers;
# old exact completion runs the current FIFO exactly once. Owned physical test
# with a real helper (logs start/done), not a pure model. JS backend (spawns
# run to completion before returning; the log still proves never-2-workers
# via spawn counts and FIFO-once via exact log match). Synthetic fixtures
# only. The helper path comes from BIRC_NOTIFY_HELPER (the Makefile recipe
# creates a notify-send fake); the log is helper ++ ".log". Wrong-ticket
# then wrong-origin negatives thread forward on returned state, and the
# received completion runs on their returned state (never a reconstituted
# nl_c()), mirroring the held-blocked threading.
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
# by rebuilding the live state. Same threading as notify_held_blocked.
def comp_wrong_chained() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(comp_nl(comp_wrong_ticket()), 1n, other_scope())

def comp_received(+ticket: Nat, +endpoint: String) -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(comp_nl(comp_wrong_chained()), ticket, endpoint)

def recv_ticket(+m: Sess.UiMsg) -> Nat:
  match m:
    case Sess.NotifyDone{+ticket, _}: ticket
    case _: 0n

def recv_endpoint(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{_, +ep}: ep
    case _: "other"

# The received message is returned (not discarded): the release threads
# its ticket/origin through current state.
def check_done(+evt: Chan(Sess.UiMsg), +ticket: String, +endpoint: String, +tag_t: String, +tag_e: String) -> IO(Sess.UiMsg):
  do IO<Sess.UiMsg>:
    +done : Sess.UiMsg <- recv_done(evt)
    Unit <- E.must_eq(tag_t, done_ticket(done), ticket)
    Unit <- E.must_eq(tag_e, done_endpoint(done), endpoint)
    IO.pure(Sess.UiMsg, done)

def check_log(+h: String, +want: String, +tag: String) -> IO(Unit):
  do IO<Unit>:
    got : String <- read_log(h)
    E.must_eq(tag, got, want)

def check_reset(+h: String, +evt: Chan(Sess.UiMsg), +log1: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("reset keeps no second worker",
      nl_active_shown(live_nl(step_reset())), "1")
    Unit <- E.must_eq("reset hands nothing while blocked",
      req_titles(live_handed_list(step_reset())), "")
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, live_nl(step_reset()), sess_r(), live_outs_list(step_reset()), live_handed_list(step_reset()), Some{evt})
    Unit <- IO.sleep(100)
    logx : String <- read_log(h)
    E.must_eq("reset spawns no second worker", logx, log1)

def check_off(+h: String, +evt: Chan(Sess.UiMsg), +log1: String) -> IO(Unit):
  do IO<Unit>:
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, live_nl(step_off()), sess_o(), live_outs_list(step_off()), live_handed_list(step_off()), Some{evt})
    Unit <- IO.sleep(100)
    logx : String <- read_log(h)
    E.must_eq("off spawns no second worker", logx, log1)

def check_on(+h: String, +evt: Chan(Sess.UiMsg), +log1: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("on keeps no second worker",
      nl_active_shown(live_nl(step_on())), "1")
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, live_nl(step_on()), sess_n(), live_outs_list(step_on()), live_handed_list(step_on()), Some{evt})
    Unit <- IO.sleep(100)
    logx : String <- read_log(h)
    E.must_eq("on spawns no second worker", logx, log1)

def check_cancel(+h: String, +evt: Chan(Sess.UiMsg), +log1: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("cancel keeps no second worker",
      nl_active_shown(nl_c()), "1")
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, nl_c(), sess_c(), live_outs_list(step_cancel()), live_handed_list(step_cancel()), Some{evt})
    Unit <- IO.sleep(100)
    logx : String <- read_log(h)
    E.must_eq("cancel spawns no second worker", logx, log1)

def run_blocked(+h: String, +evt: Chan(Sess.UiMsg), +log1: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- check_reset(h, evt, log1)
    Unit <- check_off(h, evt, log1)
    Unit <- check_on(h, evt, log1)
    Unit <- check_cancel(h, evt, log1)
    IO.pure(Unit, Unit{})

def run_released(+h: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(100)
    +done : Sess.UiMsg <- check_done(evt, "1", scope(), "old completion ticket exact", "old completion origin exact")
    Unit <- check_log(h, "start -- bob in #room <bob> hi me\ndone -- bob in #room <bob> hi me\n", "worker1 done once")
    +ticket : Nat <- IO.pure(Nat, recv_ticket(done))
    +endpoint : String <- IO.pure(String, recv_endpoint(done))
    Unit <- E.must_eq("old wrong ticket latches nothing",
      comp_rel_shown(comp_wrong_ticket()), "false")
    Unit <- E.must_eq("old wrong ticket runs nothing",
      req_titles(comp_jobs_list(comp_wrong_ticket())), "")
    Unit <- E.must_eq("old wrong origin latches nothing",
      comp_rel_shown(comp_wrong_origin()), "false")
    Unit <- E.must_eq("old wrong origin keeps worker",
      nl_active_shown(comp_nl(comp_wrong_origin())), "1")
    Unit <- E.must_eq("old chained wrong keeps worker",
      nl_active_shown(comp_nl(comp_wrong_chained())), "1")
    Unit <- E.must_eq("old chained wrong runs nothing",
      req_titles(comp_jobs_list(comp_wrong_chained())), "")
    +jobs : List<&2, Notify.Req> <- IO.pure(List<&2, Notify.Req>, comp_jobs_list(comp_received(ticket, endpoint)))
    +fnl : Sess.NotifyLive <- IO.pure(Sess.NotifyLive, comp_nl(comp_received(ticket, endpoint)))
    Unit <- E.must_eq("old exact runs fifo once", req_titles(jobs), "frank in #room;")
    Unit <- E.must_eq("old exact releases", comp_rel_shown(comp_received(ticket, endpoint)), "true")
    sc : Sess.Session <- IO.pure(Sess.Session, sess_c())
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, fnl, sc, Nil{}, jobs, Some{evt})
    Unit <- IO.sleep(100)
    _ : Sess.UiMsg <- check_done(evt, "2", other_scope(), "fifo completion ticket", "fifo completion endpoint")
    Unit <- check_log(h, "start -- bob in #room <bob> hi me\ndone -- bob in #room <bob> hi me\nstart -- frank in #room <frank> ping me\ndone -- frank in #room <frank> ping me\n", "two workers total, fifo once")
    IO.print("notify_held=ok")

def run_spawned(+h: String, +evt: Chan(Sess.UiMsg), +log1: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- run_blocked(h, evt, log1)
    run_released(h, evt)

def run_held(+h: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("helper nonempty", Bool.not(String.is_empty(h)))
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    Unit <- E.must_eq("first hands bob", req_titles(live_handed_list(step1())), "bob in #room;")
    Unit <- E.must_eq("first worker ticket 1", nl_active_shown(nl1()), "1")
    _ : Sess.NotifyLive & Sess.Session & List<&2, String> <- NotifyIO.notify_live_spawn(h, nl1(), sess1(), live_outs_list(step1()), live_handed_list(step1()), Some{evt})
    Unit <- IO.sleep(100)
    +log1 : String <- read_log(h)
    Unit <- E.must_eq("one worker ran once",
      log1, "start -- bob in #room <bob> hi me\ndone -- bob in #room <bob> hi me\n")
    run_spawned(h, evt, log1)

def deliver(helper: Maybe<&2, String>) -> IO(Unit):
  match helper:
    case None{}: IO.die(Unit, 1, "no helper resolved")
    case Some{+h}: run_held(h)

def main() -> IO(Unit):
  do IO<Unit>:
    helper : Maybe<&2, String> <- NotifyIO.program_or_default("fallback-default")
    deliver(helper)
