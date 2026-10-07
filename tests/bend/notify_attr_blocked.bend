# Blocked attribution qualification: START/release barrier through the
# actual production spawn_ticket/completed path (C backend, real thread
# concurrency), in actual order: START, then B queues while A is blocked,
# then A retires (Dial-gen bump) and the reused slot quiet-stages, then a
# wrong-stale arrival retains with no spawn, then the exact A done frees
# and the staged mention fires once, then the second release steals B. The
# failing B helper diagnoses ONLY to B's owner channel (no log run, and
# A's owner channel stays quiet under a bounded close+recv).
# An eight-plus-one burst drains via
# completion rescan with no new chunk. Unknown and consumed-exact replays
# stay quiet. Every production-owner call threads its returned state
# (never precomputed-only values). Paired framed-burst guards pin selected
# event IDs (never synthetic counts). The helper path comes from
# BIRC_NOTIFY_HELPER (the Makefile recipe creates the latch-blocking
# notify-send fake); the log is helper ++ ".log". Synthetic fixtures only.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/frame.bend as Fr
import ../../src/bend/notify.bend as N
import ../../src/bend/notify_io.bend as NIO
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/wsnet.bend as WsNet

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

def ep_a() -> String:
  "h.example:6697"

def ep_b() -> String:
  "i.example:6697"

# Actual framed burst through the real workspace dispatch: generation fence,
# Sid ceiling, and disjoint-range stamping. Never synthetic counts.
# req 0: synthetic non-PING chunk (sibling idiom; Q5 request identity).
def framed(+ws: W.Workspace, +s: Key.ServerId, +text: String) -> W.Workspace:
  W.do_on_chunk(ws, Sid.RoutedMsg{s, Sess.FromNet{W.part_gen_of(ws, s), Sess.Chunk{Fr.string_to_octets(text), 0}}}, Nil{}, 0)

def bumped.found(+got: Maybe<&2, W.Part>, +ws: W.Workspace) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{W.Part{+id, +gen, +scope, +st}}: W.replace_part(ws, W.Part{id, Sid.bump(gen), scope, st})

def bumped(+ws: W.Workspace, +id: Key.ServerId) -> W.Workspace:
  bumped.found(W.find_part(ws, id), ws)

def req_titles(rs: List<&2, N.Req>) -> String:
  match rs:
    case Nil{}: ""
    case Con{r, t}: N.req_title(r) ++ ";" ++ req_titles(t)

def ev_ids(+evs: List<&2, N.NotifyEvent>) -> String:
  match evs:
    case Nil{}: ""
    case Con{N.NotifyEvent{+id, _, _, _, _, _, _}, +t}: Nat.show(id) ++ "," ++ ev_ids(t)

# Test-only Data snapshots for results reused after IO.bind.
type ObsOut is Data:
  ObsOut{nnot: WsNet.WsNotify, jobs: List<&2, N.Req>}

type CompOut is Data:
  CompOut{nnot: WsNet.WsNotify, jobs: List<&2, N.Req>, released: Bool}

def ObsOut.from(pair: WsNet.WsNotify & List<&2, N.Req>) -> ObsOut:
  match pair:
    case (+nnot, +jobs): ObsOut{nnot, jobs}

def CompOut.from.r1(rest: List<&2, N.Req> & Bool, +nnot: WsNet.WsNotify) -> CompOut:
  match rest:
    case (+jobs, +released): CompOut{nnot, jobs, released}

def CompOut.from(pair: WsNet.WsNotify & (List<&2, N.Req> & Bool)) -> CompOut:
  match pair:
    case (+nnot, rest): CompOut.from.r1(rest, nnot)

def obs_nnot(pair: ObsOut) -> WsNet.WsNotify:
  match pair:
    case ObsOut{+nnot, _}: nnot

def obs_jobs(pair: ObsOut) -> Nat:
  match pair:
    case ObsOut{_, +jobs}: List.length(&2, N.Req, jobs)

def obs_titles(pair: ObsOut) -> String:
  match pair:
    case ObsOut{_, +jobs}: req_titles(jobs)

def comp_nnot(t: CompOut) -> WsNet.WsNotify:
  match t:
    case CompOut{+nnot, _, _}: nnot

def comp_jobs(t: CompOut) -> Nat:
  match t:
    case CompOut{_, +jobs, _}: List.length(&2, N.Req, jobs)

def comp_titles(t: CompOut) -> String:
  match t:
    case CompOut{_, +jobs, _}: req_titles(jobs)

def comp_rel(t: CompOut) -> Bool:
  match t:
    case CompOut{_, _, +released}: released

def trip_jobs(t: CompOut) -> List<&2, N.Req>:
  match t:
    case CompOut{_, +jobs, _}: jobs

def obs_jobs_list(pair: ObsOut) -> List<&2, N.Req>:
  match pair:
    case ObsOut{_, +jobs}: jobs

def sp_nnot(p: WsNet.WsNotify & W.Workspace) -> WsNet.WsNotify:
  match p:
    case (+nnot, _): nnot

def lease_held(+held: WsNet.WsNotifyLease) -> String:
  match held:
    case WsNet.WsNotifyLease{+owner, _, +ticket, +endpoint}:
      Nat.show(WsNet.ws_id_nat(owner)) ++ ":" ++ Nat.show(ticket) ++ ":" ++ endpoint

def lease_shown(+got: Maybe<&2, WsNet.WsNotifyLease>) -> String:
  match got:
    case None{}: "none"
    case Some{+held}: lease_held(held)

def lease_of(+nnot: WsNet.WsNotify) -> String:
  lease_shown(WsNet.ws_notify.lease(nnot))

def entry_found(+got: Maybe<&2, WsNet.WsNotifyPart>) -> Sess.NotifyLive:
  match got:
    case None{}: Sess.notify_live_init(N.off(), 0n)
    case Some{+e}: WsNet.ws_npart.nl(e)

def entry_nl(+nnot: WsNet.WsNotify, +id: Key.ServerId) -> Sess.NotifyLive:
  entry_found(WsNet.ws_npart.find(WsNet.ws_notify.parts(nnot), id))

def entry_floor(+nnot: WsNet.WsNotify, +id: Key.ServerId) -> Nat:
  Sess.notify_live_scanned(entry_nl(nnot, id))

def entry_qlen(+nnot: WsNet.WsNotify, +id: Key.ServerId) -> Nat:
  N.queue_len(Sess.notify_live_queue(entry_nl(nnot, id)))

def part_seq(+ws: W.Workspace, +id: Key.ServerId) -> Nat:
  Cl.log_seq_of(Sess.session_cl(WsNet.ws_part.st(ws, id)))

def duo_unjoined() -> W.Workspace:
  W.do_add(W.single_client("h.example", 6697, False{}, Feed.feed(Cl.init("me", "h.example"), ":me!u@h JOIN #a"), "#a"), "i.example", 6697, False{}, "me", "#b")

def duo_ws() -> W.Workspace:
  framed(duo_unjoined(), s1(), ":me!u@h JOIN #b\r\n")

def duo_nnot0() -> WsNet.WsNotify:
  WsNet.ws_notify.seed_all(duo_ws())

# ---- A: burst, retire/reuse while blocked, release, redeliver -------------
def a_wsf() -> W.Workspace:
  framed(duo_ws(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")

def a_pre() -> Sess.Session:
  WsNet.ws_part.st(duo_ws(), s0())

def a_post() -> Sess.Session:
  WsNet.ws_part.st(a_wsf(), s0())

def a_ids() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(a_post()), ep_a(), part_seq(duo_ws(), s0())))

def a_wsr() -> W.Workspace:
  bumped(a_wsf(), s0())

def a_wsf2() -> W.Workspace:
  framed(a_wsr(), s0(), ":erin!u@h PRIVMSG #a :yo me\r\n")

def a_pre2() -> Sess.Session:
  WsNet.ws_part.st(a_wsr(), s0())

def a_post2() -> Sess.Session:
  WsNet.ws_part.st(a_wsf2(), s0())

def a_ids2() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(a_post2()), ep_a(), part_seq(a_wsr(), s0())))

# ---- B: failure diagnoses only to B ----------------------------------------
def b_wsf() -> W.Workspace:
  framed(a_wsf2(), s1(), ":carol!u@h PRIVMSG #b :yo me\r\n")

def b_pre() -> Sess.Session:
  WsNet.ws_part.st(a_wsf2(), s1())

def b_post() -> Sess.Session:
  WsNet.ws_part.st(b_wsf(), s1())

def b_ids() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(b_post()), ep_b(), part_seq(a_wsf2(), s1())))

# Desired membership is not a resident channel until the real self-JOIN.
def b_present.got(got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def b_present(+ws: W.Workspace) -> Bool:
  b_present.got(Cl.buf_find(Sess.session_cl(WsNet.ws_part.st(ws, s1())), "#b"))

def unjoined_b_wsf() -> W.Workspace:
  framed(duo_unjoined(), s1(), ":carol!u@h PRIVMSG #b :yo me\r\n")

def unjoined_b_ids() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(WsNet.ws_part.st(unjoined_b_wsf(), s1())), ep_b(), part_seq(duo_unjoined(), s1())))

# ---- all9: eight hands, ninth unadmitted, completion rescans ----------------
def b9_burst() -> String:
  ":a1!u@h PRIVMSG #b :hi me\r\n:a2!u@h PRIVMSG #b :hi me\r\n:a3!u@h PRIVMSG #b :hi me\r\n:a4!u@h PRIVMSG #b :hi me\r\n:a5!u@h PRIVMSG #b :hi me\r\n:a6!u@h PRIVMSG #b :hi me\r\n:a7!u@h PRIVMSG #b :hi me\r\n:a8!u@h PRIVMSG #b :hi me\r\n:a9!u@h PRIVMSG #b :hi me\r\n"

def b9_wsf() -> W.Workspace:
  framed(b_wsf(), s1(), b9_burst())

def b9_pre() -> Sess.Session:
  WsNet.ws_part.st(b_wsf(), s1())

def b9_post() -> Sess.Session:
  WsNet.ws_part.st(b9_wsf(), s1())

def b9_evs() -> List<&2, N.NotifyEvent>:
  Sess.notify_collect(Sess.session_cl(b9_post()), ep_b(), part_seq(b_wsf(), s1()))

def b9_count() -> Nat:
  List.length(&2, N.NotifyEvent, b9_evs())

def b9_ids() -> String:
  ev_ids(b9_evs())

def b9_ids_exp() -> String:
  +s = part_seq(b_wsf(), s1())
  Nat.show(Nat.add(s, 1n)) ++ "," ++ Nat.show(Nat.add(s, 2n)) ++ "," ++ Nat.show(Nat.add(s, 3n)) ++ "," ++ Nat.show(Nat.add(s, 4n)) ++ "," ++ Nat.show(Nat.add(s, 5n)) ++ "," ++ Nat.show(Nat.add(s, 6n)) ++ "," ++ Nat.show(Nat.add(s, 7n)) ++ "," ++ Nat.show(Nat.add(s, 8n)) ++ "," ++ Nat.show(Nat.add(s, 9n)) ++ ","

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

def recv_one(+evt: Chan(Sess.UiMsg)) -> IO(Sess.UiMsg):
  do IO<Sess.UiMsg>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    recv_got(g)

def msg_kind(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{_, _}: "done"
    case Sess.UiError{_}: "error"
    case _: "other"

def done_shown(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{+ticket, +ep}: Nat.show(ticket) ++ ":" ++ ep
    case _: "other"

def recv_ticket(+m: Sess.UiMsg) -> Nat:
  match m:
    case Sess.NotifyDone{+ticket, _}: ticket
    case _: 0n

def recv_endpoint(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{_, +ep}: ep
    case _: "other"

def no_event(got: Maybe<&1, Sess.UiMsg>) -> Bool:
  match got:
    case None{}: True{}
    case _: False{}

# Child start ACK: poll the owned log until the helper's start line lands
# (bounded fuel, 50ms beats). The lazy continuation keeps the single
# self-recursive shape the backend accepts (no forward refs).
def await_start.branch(ready: Bool, retry: Unit -> IO(Unit)) -> IO(Unit):
  match ready:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: retry(Unit{})

def await_start.go(fuel: Nat, +h: String, +want: String) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "worker never started")
    case 1n+p:
      do IO<Unit>:
        Unit <- IO.sleep(50)
        got : String <- read_log(h)
        await_start.branch(String.eq(got, want), _u => await_start.go(p, h, want))

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

def bad_helper() -> String:
  "/nonexistent-birc-dir/notify-send"

def start_a() -> String:
  "start -- bob in #a <bob> hi me\n"

def done_a() -> String:
  "done -- bob in #a <bob> hi me\n"

def start_a2() -> String:
  "start -- erin in #a <erin> yo me\n"

def done_a2() -> String:
  "done -- erin in #a <erin> yo me\n"

def log_a() -> String:
  start_a() ++ done_a() ++ start_a2() ++ done_a2()

def b9_titles8() -> String:
  "a1 in #b;a2 in #b;a3 in #b;a4 in #b;a5 in #b;a6 in #b;a7 in #b;a8 in #b;"

def log_b9() -> String:
  "start -- a1 in #b <a1> hi me\ndone -- a1 in #b <a1> hi me\nstart -- a2 in #b <a2> hi me\ndone -- a2 in #b <a2> hi me\nstart -- a3 in #b <a3> hi me\ndone -- a3 in #b <a3> hi me\nstart -- a4 in #b <a4> hi me\ndone -- a4 in #b <a4> hi me\nstart -- a5 in #b <a5> hi me\ndone -- a5 in #b <a5> hi me\nstart -- a6 in #b <a6> hi me\ndone -- a6 in #b <a6> hi me\nstart -- a7 in #b <a7> hi me\ndone -- a7 in #b <a7> hi me\nstart -- a8 in #b <a8> hi me\ndone -- a8 in #b <a8> hi me\nstart -- a9 in #b <a9> hi me\ndone -- a9 in #b <a9> hi me\n"

def log_full() -> String:
  log_a() ++ log_b9()

def run_replays(+h: String, +nnPrev: WsNet.WsNotify) -> IO(Unit):
  do IO<Unit>:
    +cU : CompOut <- IO.pure(CompOut, CompOut.from(WsNet.ws_notify.completed(nnPrev, b9_wsf(), s1(), 99n, ep_b(), True{})))
    +nnU : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(cU))
    Unit <- E.must("unknown ticket drops", Bool.not(comp_rel(cU)))
    Unit <- E.must_eq("unknown keeps lease clear", lease_of(nnU), "none")
    +cR : CompOut <- IO.pure(CompOut, CompOut.from(WsNet.ws_notify.completed(nnU, b9_wsf(), s1(), 5n, ep_b(), True{})))
    +nnR : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(cR))
    Unit <- E.must("consumed exact replay drops", Bool.not(comp_rel(cR)))
    Unit <- E.must_eq("replay keeps lease clear", lease_of(nnR), "none")
    Unit <- E.must("replay keeps floor", Nat.is_eq(entry_floor(nnR, s1()), part_seq(b9_wsf(), s1())))
    +logR : String <- read_log(h)
    Unit <- E.must_eq("replays spawn nothing", logR, log_full())
    IO.print("notify_attr_blocked=ok")

def run_all9(+h: String, +evts: WsNet.WsEvts, +evt1: Chan(Sess.UiMsg), +nnPrev: WsNet.WsNotify) -> IO(Unit):
  do IO<Unit>:
    +b9O : ObsOut <- IO.pure(ObsOut, ObsOut.from(WsNet.ws_notify.observed_pre(nnPrev, s1(), 0, b9_pre(), b9_post(), True{})))
    +nn9 : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, obs_nnot(b9O))
    +jobs9 : List<&2, N.Req> <- IO.pure(List<&2, N.Req>, obs_jobs_list(b9O))
    Unit <- E.must_eq("nine hands eight", Nat.show(List.length(&2, N.Req, jobs9)), "8")
    Unit <- E.must_eq("nine hands in order", req_titles(jobs9), b9_titles8())
    Unit <- E.must("nine floor below final", Nat.is_lt(entry_floor(nn9, s1()), part_seq(b9_wsf(), s1())))
    _ : WsNet.WsNotify & W.Workspace <- WsNet.ws_notify.spawn_ticket(WsNet.ws_notify.lease(nn9), h, jobs9, evts, nn9, b9_wsf())
    +d9 : Sess.UiMsg <- recv_one(evt1)
    Unit <- E.must_eq("done9 on owner channel", done_shown(d9), "4:" ++ ep_b())
    +t9 : Nat <- IO.pure(Nat, recv_ticket(d9))
    +e9 : String <- IO.pure(String, recv_endpoint(d9))
    +c9 : CompOut <- IO.pure(CompOut, CompOut.from(WsNet.ws_notify.completed(nn9, b9_wsf(), s1(), t9, e9, True{})))
    +nn9b : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(c9))
    +jobs9b : List<&2, N.Req> <- IO.pure(List<&2, N.Req>, trip_jobs(c9))
    Unit <- E.must("c9 releases", comp_rel(c9))
    Unit <- E.must_eq("rescan hands ninth", req_titles(jobs9b), "a9 in #b;")
    Unit <- E.must("nine floor reaches final", Nat.is_eq(entry_floor(nn9b, s1()), part_seq(b9_wsf(), s1())))
    _ : WsNet.WsNotify & W.Workspace <- WsNet.ws_notify.spawn_ticket(WsNet.ws_notify.lease(nn9b), h, jobs9b, evts, nn9b, b9_wsf())
    +d9b : Sess.UiMsg <- recv_one(evt1)
    Unit <- E.must_eq("done9b on owner channel", done_shown(d9b), "5:" ++ ep_b())
    +t9b : Nat <- IO.pure(Nat, recv_ticket(d9b))
    +e9b : String <- IO.pure(String, recv_endpoint(d9b))
    +c9b : CompOut <- IO.pure(CompOut, CompOut.from(WsNet.ws_notify.completed(nn9b, b9_wsf(), s1(), t9b, e9b, True{})))
    +nnEnd : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(c9b))
    Unit <- E.must("c9b releases", comp_rel(c9b))
    Unit <- E.must_eq("c9b drains nothing", Nat.show(comp_jobs(c9b)), "0")
    Unit <- E.must_eq("lease cleared nine", lease_of(nnEnd), "none")
    +log9 : String <- read_log(h)
    Unit <- E.must_eq("nine workers total, fifo once", log9, log_full())
    run_replays(h, nnEnd)

def run_failed_b(+h: String, +evts: WsNet.WsEvts, +evt0: Chan(Sess.UiMsg), +evt1: Chan(Sess.UiMsg), +nnB: WsNet.WsNotify, +jobsB: List<&2, N.Req>) -> IO(Unit):
  do IO<Unit>:
    spB : WsNet.WsNotify & W.Workspace <- WsNet.ws_notify.spawn_ticket(WsNet.ws_notify.lease(nnB), bad_helper(), jobsB, evts, nnB, b_wsf())
    +nnBs : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, sp_nnot(spB))
    +f0 : Sess.UiMsg <- recv_one(evt1)
    Unit <- E.must_eq("failed helper logs error on B", msg_kind(f0), "error")
    +f1 : Sess.UiMsg <- recv_one(evt1)
    Unit <- E.must_eq("failed worker still completes", done_shown(f1), "3:" ++ ep_b())
    +tB : Nat <- IO.pure(Nat, recv_ticket(f1))
    +eB : String <- IO.pure(String, recv_endpoint(f1))
    +cB : CompOut <- IO.pure(CompOut, CompOut.from(WsNet.ws_notify.completed(nnBs, b_wsf(), s1(), tB, eB, True{})))
    +nnB2 : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(cB))
    Unit <- E.must("cB releases", comp_rel(cB))
    Unit <- E.must_eq("cB drains nothing", Nat.show(comp_jobs(cB)), "0")
    Unit <- E.must_eq("lease cleared B", lease_of(nnB2), "none")
    +logB : String <- read_log(h)
    Unit <- E.must_eq("B failure logs only B (no helper run)", logB, log_a())
    # Bounded A-quiet CHANNEL assertion: one settle beat lets any stray
    # A-side send land, then close+recv proves the owner channel empty.
    # (recv blocks on an open channel, so the close bounds the check.)
    Unit <- IO.sleep(300)
    Unit <- Chan.close(Sess.UiMsg, evt0)
    qA : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt0)
    Unit <- E.must("A channel quiet across B failure", no_event(qA))
    run_all9(h, evts, evt1, nnB2)

def run_released(+h: String, +evts: WsNet.WsEvts, +evt0: Chan(Sess.UiMsg), +evt1: Chan(Sess.UiMsg), +nnBlocked: WsNet.WsNotify) -> IO(Unit):
  do IO<Unit>:
    Unit <- release_worker(h)
    +dA : Sess.UiMsg <- recv_one(evt0)
    Unit <- E.must_eq("doneA on owner channel", done_shown(dA), "1:" ++ ep_a())
    +tA : Nat <- IO.pure(Nat, recv_ticket(dA))
    +eA : String <- IO.pure(String, recv_endpoint(dA))
    # The exact A done runs on the stale arrival's RETURNED state.
    +cA : CompOut <- IO.pure(CompOut, CompOut.from(WsNet.ws_notify.completed(nnBlocked, a_wsf2(), s0(), tA, eA, True{})))
    +nnA : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(cA))
    +jobsA2 : List<&2, N.Req> <- IO.pure(List<&2, N.Req>, trip_jobs(cA))
    Unit <- E.must("cA releases", comp_rel(cA))
    Unit <- E.must_eq("staged erin fires once", req_titles(jobsA2), "erin in #a;")
    Unit <- E.must_eq("lease moves A2", lease_of(nnA), "0:2:" ++ ep_a())
    +log2 : String <- read_log(h)
    Unit <- E.must_eq("workerA released within timeout", log2, start_a() ++ done_a())
    spA2 : WsNet.WsNotify & W.Workspace <- WsNet.ws_notify.spawn_ticket(WsNet.ws_notify.lease(nnA), h, jobsA2, evts, nnA, a_wsf2())
    +nnA2s : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, sp_nnot(spA2))
    +dA2 : Sess.UiMsg <- recv_one(evt0)
    Unit <- E.must_eq("doneA2 on owner channel", done_shown(dA2), "2:" ++ ep_a())
    +tA2 : Nat <- IO.pure(Nat, recv_ticket(dA2))
    +eA2 : String <- IO.pure(String, recv_endpoint(dA2))
    +cA2 : CompOut <- IO.pure(CompOut, CompOut.from(WsNet.ws_notify.completed(nnA2s, a_wsf2(), s0(), tA2, eA2, True{})))
    +nnB : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(cA2))
    +jobsB : List<&2, N.Req> <- IO.pure(List<&2, N.Req>, trip_jobs(cA2))
    Unit <- E.must("cA2 releases", comp_rel(cA2))
    # The second A release steals B's retained request (no new chunk).
    Unit <- E.must_eq("B hands carol on steal", req_titles(jobsB), "carol in #b;")
    Unit <- E.must_eq("lease moves B", lease_of(nnB), "1:3:" ++ ep_b())
    +log3 : String <- read_log(h)
    Unit <- E.must_eq("two A workers total", log3, log_a())
    run_failed_b(h, evts, evt0, evt1, nnB, jobsB)

def run_blocked(+h: String, +evts: WsNet.WsEvts, +evt0: Chan(Sess.UiMsg), +evt1: Chan(Sess.UiMsg), +nnAS: WsNet.WsNotify) -> IO(Unit):
  do IO<Unit>:
    # B queues while A is blocked: B quiet-stages, the A lease stays.
    +bQ : ObsOut <- IO.pure(ObsOut, ObsOut.from(WsNet.ws_notify.observed_pre(nnAS, s1(), 0, b_pre(), b_post(), True{})))
    +nnBQ : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, obs_nnot(bQ))
    Unit <- E.must_eq("b quiets while A blocked", Nat.show(obs_jobs(bQ)), "0")
    Unit <- E.must_eq("b retains carol", Nat.show(entry_qlen(nnBQ, s1())), "1")
    Unit <- E.must_eq("b blocked keeps A lease", lease_of(nnBQ), "0:1:" ++ ep_a())
    # Retire/reuse A while blocked: the reused slot quiet-stages erin.
    +a2Q : ObsOut <- IO.pure(ObsOut, ObsOut.from(WsNet.ws_notify.observed_pre(nnBQ, s0(), 1, a_pre2(), a_post2(), True{})))
    +nnA2Q : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, obs_nnot(a2Q))
    Unit <- E.must_eq("a2 quiets while blocked", Nat.show(obs_jobs(a2Q)), "0")
    Unit <- E.must_eq("a2 retains erin", Nat.show(entry_qlen(nnA2Q, s0())), "1")
    Unit <- E.must_eq("a old lease stays", lease_of(nnA2Q), "0:1:" ++ ep_a())
    # Wrong-stale arrival while blocked: drops, retains both queues, and
    # spawns nothing (no B spawn off a stale ticket).
    +wS : CompOut <- IO.pure(CompOut, CompOut.from(WsNet.ws_notify.completed(nnA2Q, a_wsf2(), s0(), 99n, ep_a(), True{})))
    +nnWS : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(wS))
    Unit <- E.must("stale ticket drops", Bool.not(comp_rel(wS)))
    Unit <- E.must_eq("stale keeps lease", lease_of(nnWS), "0:1:" ++ ep_a())
    Unit <- E.must_eq("stale retains A", Nat.show(entry_qlen(nnWS, s0())), "1")
    Unit <- E.must_eq("stale retains B", Nat.show(entry_qlen(nnWS, s1())), "1")
    # One beat for any stray second spawn to hit the log; the helper still
    # holds the first worker until its timeout.
    Unit <- IO.sleep(300)
    +logPin : String <- read_log(h)
    Unit <- E.must_eq("held across retire: still one worker", logPin, start_a())
    run_released(h, evts, evt0, evt1, nnWS)

# Spawn arguments are bound before the call: nesting several pure step
# projections directly inside the spawn application trips the C backend's
# arity limit, while pre-bound arguments compile fine.
def run_phys(+h: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("missing-membership B stays absent", Bool.not(b_present(unjoined_b_wsf())))
    Unit <- E.must_eq("missing-membership B stays unselected", unjoined_b_ids(), "")
    Unit <- E.must("joined B is resident", b_present(b_wsf()))
    Unit <- E.must("joined B mention receives a fresh ID", Nat.is_gt(part_seq(b_wsf(), s1()), part_seq(a_wsf2(), s1())))
    Unit <- E.must("helper admitted", NIO.known_helper(h))
    Unit <- E.must_eq("queue cap eight", Nat.show(N.QUEUE_CAP()), "8")
    # Paired framed-burst guards: selected IDs pin the actual bursts.
    Unit <- E.must_eq("a selected id", a_ids(), Nat.show(part_seq(a_wsf(), s0())) ++ ",")
    Unit <- E.must_eq("a2 selected id", a_ids2(), Nat.show(part_seq(a_wsf2(), s0())) ++ ",")
    Unit <- E.must_eq("b selected id", b_ids(), Nat.show(part_seq(b_wsf(), s1())) ++ ",")
    Unit <- E.must_eq("b9 collects nine", Nat.show(b9_count()), "9")
    Unit <- E.must_eq("b9 selected ids", b9_ids(), b9_ids_exp())
    +evt0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +evt1 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +evt2 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +evt3 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +evts : WsNet.WsEvts <- IO.pure(WsNet.WsEvts, WsNet.WsEvts{evt0, evt1, evt2, evt3})
    # The first observation hands bob through the production owner; every
    # later leg threads the returned state of the call before it.
    +aO : ObsOut <- IO.pure(ObsOut, ObsOut.from(WsNet.ws_notify.observed_pre(duo_nnot0(), s0(), 0, a_pre(), a_post(), True{})))
    +nnA0 : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, obs_nnot(aO))
    +jobsA0 : List<&2, N.Req> <- IO.pure(List<&2, N.Req>, obs_jobs_list(aO))
    Unit <- E.must_eq("a first hands bob", req_titles(jobsA0), "bob in #a;")
    Unit <- E.must_eq("a lease taken", lease_of(nnA0), "0:1:" ++ ep_a())
    spA : WsNet.WsNotify & W.Workspace <- WsNet.ws_notify.spawn_ticket(WsNet.ws_notify.lease(nnA0), h, jobsA0, evts, nnA0, a_wsf())
    +nnAS : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, sp_nnot(spA))
    # Actual child start ACK: the blocked helper holds the worker on the
    # release latch, so this poll lands strictly between start and done.
    Unit <- await_start.go(40n, h, start_a())
    +log1 : String <- read_log(h)
    Unit <- E.must_eq("worker held: started, not done", log1, start_a())
    run_blocked(h, evts, evt0, evt1, nnAS)

def deliver(helper: Maybe<&2, String>) -> IO(Unit):
  match helper:
    case None{}: IO.die(Unit, 1, "no helper resolved")
    case Some{+h}: run_phys(h)

def main() -> IO(Unit):
  do IO<Unit>:
    helper : Maybe<&2, String> <- NIO.program_or_default("fallback-default")
    deliver(helper)
