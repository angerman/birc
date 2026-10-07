# Notify binding gates: per-part NotifyLive + one global lease across parts.
# Gate 1: same-endpoint Sid1 IDs start at 2^44; both parts notify once each,
# replays quiet. Gate 2: ninth+ framed mentions overflow unadmitted, then one
# completion drains all nine with no new chunk; exact replay quiet. Gate 3:
# accepted history installs merge per-ID archive claims (archive DMs quiet,
# pending lower live kept, later live delivers); stale/refused installs are
# no-ops. Gate 4: redial/slot replacement drops replaced-part queued work and
# keeps unrelated work; the blocked worker releases exactly once. Attribution:
# every handoff spawns on its captured owner channel (wrong-sid/ticket/
# endpoint completions drop as hardening, never a release); a failed helper
# diagnoses to its owning part. Kept positives: per-event mention
# classification, detached IO spawn, single physical lease (sequential
# workers only; a post-completion handoff is replacement, never a double).
# Actual framed bursts through the real workspace dispatch (Sid ceilings and
# disjoint 2^44 ranges) plus a physical fake-helper barrier (spawn counts,
# exact start/done log, NotifyDone round-trips on owner channels). JS backend.
# The barrier routes through production spawn_ticket/completed: every spawn
# uses the captured owner channel/ticket/endpoint, and each received
# completion threads its own ticket/endpoint (never precomputed state).
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

def ep_h() -> String:
  "h.example:6697"

def ep_i() -> String:
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

def ev_flag(+ev: N.NotifyEvent) -> String:
  match ev:
    case N.NotifyEvent{_, _, _, _, _, +dm, +mention}: ev_flag.dm(dm, mention)

def ev_flag.dm(+dm: Bool, +mention: Bool) -> String:
  match dm:
    case True{}: "D"
    case False{}: ev_flag.men(mention)

def ev_flag.men(+mention: Bool) -> String:
  match mention:
    case True{}: "M"
    case False{}: "o"

def ev_flags(+evs: List<&2, N.NotifyEvent>) -> String:
  match evs:
    case Nil{}: ""
    case Con{+h, +t}: ev_flag(h) ++ ev_flags(t)

def obs_nnot(pair: WsNet.WsNotify & List<&2, N.Req>) -> WsNet.WsNotify:
  match pair:
    case (+nnot, _): nnot

def obs_jobs(pair: WsNet.WsNotify & List<&2, N.Req>) -> Nat:
  match pair:
    case (_, +jobs): List.length(&2, N.Req, jobs)

def obs_titles(pair: WsNet.WsNotify & List<&2, N.Req>) -> String:
  match pair:
    case (_, +jobs): req_titles(jobs)

def comp_nnot(t: WsNet.WsNotify & List<&2, N.Req> & Bool) -> WsNet.WsNotify:
  match t:
    case (+nnot, _, _): nnot

def comp_jobs(t: WsNet.WsNotify & List<&2, N.Req> & Bool) -> Nat:
  match t:
    case (_, +jobs, _): List.length(&2, N.Req, jobs)

def comp_titles(t: WsNet.WsNotify & List<&2, N.Req> & Bool) -> String:
  match t:
    case (_, +jobs, _): req_titles(jobs)

def comp_rel(t: WsNet.WsNotify & List<&2, N.Req> & Bool) -> Bool:
  match t:
    case (_, _, +released): released

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

def nat_ids(+xs: List<&2, Nat>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, +t}: Nat.show(h) ++ "," ++ nat_ids(t)

def entry_claims(+nnot: WsNet.WsNotify, +id: Key.ServerId) -> String:
  nat_ids(Sess.notify_live_claimed(entry_nl(nnot, id)))

def entry_endpoint(+nnot: WsNet.WsNotify, +id: Key.ServerId) -> String:
  Sess.notify_live_endpoint(entry_nl(nnot, id))

def part_seq(+ws: W.Workspace, +id: Key.ServerId) -> Nat:
  Cl.log_seq_of(Sess.session_cl(WsNet.ws_part.st(ws, id)))

# Premise inspectors distinguish a missing part from an unjoined channel.
def b_room.named(+got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "absent"
    case Some{_}: "present"

def b_room(+got: Maybe<&2, W.Part>) -> String:
  match got:
    case None{}: "missing-part"
    case Some{W.Part{_, _, _, +st}}: b_room.named(Cl.buf_find(Sess.session_cl(st), "#b"))

def b_events(+got: Maybe<&2, W.Part>, +scope: String, +floor: Nat) -> String:
  match got:
    case None{}: "missing-part"
    case Some{W.Part{_, _, _, +st}}: ev_ids(Sess.notify_collect(Sess.session_cl(st), scope, floor))

# ---- gate 1: same-endpoint siblings keep disjoint floors --------------------
def g1_unjoined() -> W.Workspace:
  W.do_add(W.single_client("h.example", 6697, False{}, Feed.feed(Cl.init("me", "h.example"), ":me!u@h JOIN #a"), "#a"), "h.example", 6697, False{}, "me", "#b")

def g1_ws() -> W.Workspace:
  W.do_add(W.single_client("h.example", 6697, False{}, Feed.feed(Cl.init("me", "h.example"), ":me!u@h JOIN #a"), "#a"), "h.example", 6697, False{}, "me", "#b")

def g1_nnot0() -> WsNet.WsNotify:
  WsNet.ws_notify.seed_all(g1_ws())

def g1_wsf() -> W.Workspace:
  +w1 = framed(g1_ws(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")
  framed(w1, s1(), ":carol!u@h PRIVMSG #b :yo me\r\n")

def g1_st0f() -> Sess.Session:
  WsNet.ws_part.st(g1_wsf(), s0())

def g1_st1f() -> Sess.Session:
  WsNet.ws_part.st(g1_wsf(), s1())

def g1_o0() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(g1_nnot0(), s0(), 0, g1_st0f(), True{})

def g1_o1() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(obs_nnot(g1_o0()), s1(), 0, g1_st1f(), True{})

def g1_c1() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(obs_nnot(g1_o1()), g1_wsf(), s0(), 1n, ep_h(), True{})

def g1_c2() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(g1_c1()), g1_wsf(), s1(), 2n, ep_h(), True{})

def g1_r0() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(comp_nnot(g1_c2()), s0(), 0, g1_st0f(), True{})

def g1_r1() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(obs_nnot(g1_r0()), s1(), 0, g1_st1f(), True{})

def g1_ids0() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(g1_st0f()), ep_h(), entry_floor(g1_nnot0(), s0())))

def g1_ids1() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(g1_st1f()), ep_h(), entry_floor(g1_nnot0(), s1())))

# Fresh failure-leg burst: a later #b mention for a new queued request once
# the received done2 completion has freed the lease (fresh owner ticket).
def g1_wsfd() -> W.Workspace:
  framed(g1_wsf(), s1(), ":dave!u@h PRIVMSG #b :ping me\r\n")

def g1_st1fd() -> Sess.Session:
  WsNet.ws_part.st(g1_wsfd(), s1())

# ---- gate 2: overflowed ninth drains on completion, no new chunk ------------
def g2_ws() -> W.Workspace:
  W.single_client("h.example", 6697, False{}, Feed.feed(Cl.init("me", "h.example"), ":me!u@h JOIN #a"), "#a")

def g2_burst() -> String:
  ":a1!u@h PRIVMSG #a :hi me\r\n:a2!u@h PRIVMSG #a :hi me\r\n:a3!u@h PRIVMSG #a :hi me\r\n:a4!u@h PRIVMSG #a :hi me\r\n:a5!u@h PRIVMSG #a :hi me\r\n:a6!u@h PRIVMSG #a :hi me\r\n:a7!u@h PRIVMSG #a :hi me\r\n:a8!u@h PRIVMSG #a :hi me\r\n:a9!u@h PRIVMSG #a :hi me\r\n"

def g2_wsf() -> W.Workspace:
  framed(g2_ws(), s0(), g2_burst())

def g2_st9() -> Sess.Session:
  WsNet.ws_part.st(g2_wsf(), s0())

def g2_nnot0() -> WsNet.WsNotify:
  WsNet.ws_notify.seed_all(g2_ws())

def g2_o() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(g2_nnot0(), s0(), 0, g2_st9(), True{})

def g2_c() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(obs_nnot(g2_o()), g2_wsf(), s0(), 1n, ep_h(), True{})

def g2_c2() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(g2_c()), g2_wsf(), s0(), 2n, ep_h(), True{})

def g2_r() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(comp_nnot(g2_c2()), s0(), 0, g2_st9(), True{})

# ---- gate 3: accepted installs claim per-ID; stale/refused are no-ops ------
def g3_ws() -> W.Workspace:
  W.single_client("h.example", 6697, False{}, Feed.feed(Cl.init("me", "h.example"), ":me!u@h JOIN #a"), "#a")

def g3_nnot0() -> WsNet.WsNotify:
  WsNet.ws_notify.seed_all(g3_ws())

def g3_wslive() -> W.Workspace:
  framed(g3_ws(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")

def g3_stlive() -> Sess.Session:
  WsNet.ws_part.st(g3_wslive(), s0())

def g3_oq() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(g3_nnot0(), s0(), 0, g3_stlive(), False{})

def g3_wsafter() -> W.Workspace:
  framed(g3_wslive(), s0(), ":dave!u@h PRIVMSG me :cached one\r\n:mallory!u@h PRIVMSG me :cached two\r\n")

def g3_stafter() -> Sess.Session:
  WsNet.ws_part.st(g3_wsafter(), s0())

def g3_before() -> Nat:
  Cl.log_seq_of(Sess.session_cl(g3_stlive()))

def g3_installed() -> List<&2, Nat>:
  Sess.notify_claims_installed(g3_before(), Sess.session_cl(g3_stafter()))

def g3_acc() -> WsNet.WsNotify:
  WsNet.ws_notify.seeded(obs_nnot(g3_oq()), g3_wsafter(), s0(), True{}, g3_installed())

def g3_ref() -> WsNet.WsNotify:
  WsNet.ws_notify.seeded(obs_nnot(g3_oq()), g3_wsafter(), s0(), False{}, g3_installed())

def g3_o() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(g3_acc(), s0(), 0, g3_stafter(), True{})

def g3_wserin() -> W.Workspace:
  framed(g3_wsafter(), s0(), ":erin!u@h PRIVMSG #a :yo me\r\n")

def g3_sterin() -> Sess.Session:
  WsNet.ws_part.st(g3_wserin(), s0())

def g3_c() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(obs_nnot(g3_o()), g3_wserin(), s0(), 1n, ep_h(), True{})

def g3_c2() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(g3_c()), g3_wserin(), s0(), 2n, ep_h(), True{})

def g3_r() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(comp_nnot(g3_c2()), s0(), 0, g3_sterin(), True{})

# ---- gate 4: replacement drops stale queued work, keeps unrelated -----------
def g4_unjoined() -> W.Workspace:
  W.do_add(W.single_client("h.example", 6697, False{}, Feed.feed(Cl.init("me", "h.example"), ":me!u@h JOIN #a"), "#a"), "i.example", 6697, False{}, "me", "#b")

def g4_ws() -> W.Workspace:
  W.do_add(W.single_client("h.example", 6697, False{}, Feed.feed(Cl.init("me", "h.example"), ":me!u@h JOIN #a"), "#a"), "i.example", 6697, False{}, "me", "#b")

def g4_nnot0() -> WsNet.WsNotify:
  WsNet.ws_notify.seed_all(g4_ws())

def g4_wsf() -> W.Workspace:
  +w1 = framed(g4_ws(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")
  framed(w1, s1(), ":carol!u@h PRIVMSG #b :yo me\r\n")

def g4_st0f() -> Sess.Session:
  WsNet.ws_part.st(g4_wsf(), s0())

def g4_st1f() -> Sess.Session:
  WsNet.ws_part.st(g4_wsf(), s1())

def g4_o1() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(g4_nnot0(), s1(), 0, g4_st1f(), True{})

def g4_o0() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(obs_nnot(g4_o1()), s0(), 0, g4_st0f(), True{})

def g4_wsfrank() -> W.Workspace:
  framed(g4_wsf(), s1(), ":frank!u@h PRIVMSG #b :ping me\r\n")

def g4_st1frank() -> Sess.Session:
  WsNet.ws_part.st(g4_wsfrank(), s1())

def g4_o1b() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(obs_nnot(g4_o0()), s1(), 0, g4_st1frank(), True{})

def g4_wsr() -> W.Workspace:
  bumped(g4_wsfrank(), s0())

def g4_c() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(obs_nnot(g4_o1b()), g4_wsr(), s1(), 1n, ep_i(), True{})

def g4_dup() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(g4_c()), g4_wsr(), s1(), 1n, ep_i(), True{})

def g4_c2() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(g4_c()), g4_wsr(), s1(), 2n, ep_i(), True{})

def g4_o0r() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(comp_nnot(g4_c2()), s0(), 1, g4_st0f(), True{})

# Owner-replaced variant: the blocked worker still releases exactly once.
# The sibling part stays row-free so the post-release steal round is empty.
def g4b_wsf() -> W.Workspace:
  framed(g4_ws(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")

def g4b_st0f() -> Sess.Session:
  WsNet.ws_part.st(g4b_wsf(), s0())

def g4b_o0() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(g4_nnot0(), s0(), 0, g4b_st0f(), True{})

def g4b_wsr() -> W.Workspace:
  bumped(g4b_wsf(), s0())

def g4b_c() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(obs_nnot(g4b_o0()), g4b_wsr(), s0(), 1n, ep_h(), True{})

def g4b_dup() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(g4b_c()), g4b_wsr(), s0(), 1n, ep_h(), True{})

# Endpoint move resets logical state through the accepted owner.
def g4m_oq() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(g4_nnot0(), s0(), 0, g4_st0f(), False{})

def g4m_moved() -> Sess.Session:
  Sess.session_with_client_at(Sess.session_cl(g4_st0f()), "#a", 6667)

def g4m_o() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(obs_nnot(g4m_oq()), s0(), 0, g4m_moved(), True{})

# ---- physical barrier: owner channels, spawn counts, diagnostics ------------
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

def chan_pick(s0hit: Bool, +e0: Chan(Sess.UiMsg), +e1: Chan(Sess.UiMsg)) -> Chan(Sess.UiMsg):
  match s0hit:
    case True{}: e0
    case False{}: e1

def evt_owned(+held: WsNet.WsNotifyLease, +e0: Chan(Sess.UiMsg), +e1: Chan(Sess.UiMsg)) -> Chan(Sess.UiMsg):
  match held:
    case WsNet.WsNotifyLease{+owner, _, _, _}: chan_pick(Key.eq(owner, s0()), e0, e1)

def evt_for(+lease: Maybe<&2, WsNet.WsNotifyLease>, +e0: Chan(Sess.UiMsg), +e1: Chan(Sess.UiMsg)) -> Chan(Sess.UiMsg):
  match lease:
    case None{}: e0
    case Some{+held}: evt_owned(held, e0, e1)

def argv_joined(+args: List<&1, String>) -> String:
  match args:
    case Nil{}: ""
    case Con{+h, +t}: h ++ "|" ++ argv_joined(t)

def bad_helper() -> String:
  "/nonexistent-birc-dir/notify-send"

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("premise g1 unjoined b absent", b_room(W.find_part(g1_unjoined(), s1())), "absent")
    Unit <- E.must_eq("premise g1 unjoined b mention dropped", b_events(W.find_part(framed(g1_unjoined(), s1(), ":carol!u@h PRIVMSG #b :yo me\r\n"), s1()), ep_h(), part_seq(g1_unjoined(), s1())), "")
    Unit <- E.must_eq("premise g1 joined b present", b_room(W.find_part(g1_ws(), s1())), "present")
    Unit <- E.must_eq("premise g1 joined b mention fresh", b_events(W.find_part(g1_wsf(), s1()), ep_h(), part_seq(g1_ws(), s1())), Nat.show(Nat.add(part_seq(g1_ws(), s1()), 1n)) ++ ",")
    Unit <- E.must_eq("premise g4 unjoined b absent", b_room(W.find_part(g4_unjoined(), s1())), "absent")
    Unit <- E.must_eq("premise g4 unjoined b mention dropped", b_events(W.find_part(framed(g4_unjoined(), s1(), ":carol!u@h PRIVMSG #b :yo me\r\n"), s1()), ep_i(), part_seq(g4_unjoined(), s1())), "")
    Unit <- E.must_eq("premise g4 joined b present", b_room(W.find_part(g4_ws(), s1())), "present")
    Unit <- E.must_eq("premise g4 joined b mention fresh", b_events(W.find_part(g4_wsf(), s1()), ep_i(), part_seq(g4_ws(), s1())), Nat.show(Nat.add(part_seq(g4_ws(), s1()), 1n)) ++ ",")
    # Per-event classification over actual framed rows (never final-id-only).
    Unit <- E.must_eq("g1 s0 collects one", Nat.show(List.length(&2, N.NotifyEvent, Sess.notify_collect(Sess.session_cl(g1_st0f()), ep_h(), entry_floor(g1_nnot0(), s0())))), "1")
    Unit <- E.must_eq("g1 s0 mention flag", ev_flags(Sess.notify_collect(Sess.session_cl(g1_st0f()), ep_h(), entry_floor(g1_nnot0(), s0()))), "M")
    Unit <- E.must_eq("g1 s1 collects one", Nat.show(List.length(&2, N.NotifyEvent, Sess.notify_collect(Sess.session_cl(g1_st1f()), ep_h(), entry_floor(g1_nnot0(), s1())))), "1")
    Unit <- E.must_eq("g1 s1 mention flag", ev_flags(Sess.notify_collect(Sess.session_cl(g1_st1f()), ep_h(), entry_floor(g1_nnot0(), s1()))), "M")
    # Gate 1: disjoint floors; Sid1 lives at/above 2^44.
    Unit <- E.must("g1 s1 floor in sid1 range", Nat.is_lt(W.id_range(), entry_floor(g1_nnot0(), s1())))
    Unit <- E.must("g1 s0 floor below range", Nat.is_lt(entry_floor(g1_nnot0(), s0()), W.id_range()))
    Unit <- E.must("g1 s1 floor tracks actual seq", Nat.is_eq(entry_floor(g1_nnot0(), s1()), part_seq(g1_ws(), s1())))
    Unit <- E.must_eq("g1 s0 selected id", g1_ids0(), Nat.show(part_seq(g1_wsf(), s0())) ++ ",")
    Unit <- E.must_eq("g1 s1 selected id", g1_ids1(), Nat.show(part_seq(g1_wsf(), s1())) ++ ",")
    Unit <- E.must_eq("g1 s0 hands bob", obs_titles(g1_o0()), "bob in #a;")
    Unit <- E.must_eq("g1 lease owner s0", lease_of(obs_nnot(g1_o0())), "0:1:" ++ ep_h())
    Unit <- E.must_eq("g1 s1 quiets while busy", Nat.show(obs_jobs(g1_o1())), "0")
    Unit <- E.must_eq("g1 s1 retains carol", Nat.show(entry_qlen(obs_nnot(g1_o1()), s1())), "1")
    Unit <- E.must_eq("g1 busy keeps lease", lease_of(obs_nnot(g1_o1())), "0:1:" ++ ep_h())
    Unit <- E.must_eq("g1 next monotone", Nat.show(WsNet.ws_notify.next(obs_nnot(g1_o0()))) ++ "," ++ Nat.show(WsNet.ws_notify.next(comp_nnot(g1_c1()))), "2,3")
    Unit <- E.must("g1 c1 releases", comp_rel(g1_c1()))
    Unit <- E.must_eq("g1 steal hands carol", comp_titles(g1_c1()), "carol in #b;")
    Unit <- E.must_eq("g1 lease moves to s1", lease_of(comp_nnot(g1_c1())), "1:2:" ++ ep_h())
    Unit <- E.must("g1 c2 releases", comp_rel(g1_c2()))
    Unit <- E.must_eq("g1 c2 drains nothing", Nat.show(comp_jobs(g1_c2())), "0")
    Unit <- E.must_eq("g1 lease cleared", lease_of(comp_nnot(g1_c2())), "none")
    Unit <- E.must_eq("g1 replay s0 quiet", Nat.show(obs_jobs(g1_r0())), "0")
    Unit <- E.must_eq("g1 replay s1 quiet", Nat.show(obs_jobs(g1_r1())), "0")
    # Hardening drops (never releases, never a double worker).
    Unit <- E.must("g1 wrong sid drops", Bool.not(comp_rel(WsNet.ws_notify.completed(obs_nnot(g1_o0()), g1_wsf(), s1(), 1n, ep_h(), True{}))))
    Unit <- E.must_eq("g1 wrong sid keeps lease", lease_of(comp_nnot(WsNet.ws_notify.completed(obs_nnot(g1_o0()), g1_wsf(), s1(), 1n, ep_h(), True{}))), "0:1:" ++ ep_h())
    Unit <- E.must("g1 wrong ticket drops", Bool.not(comp_rel(WsNet.ws_notify.completed(obs_nnot(g1_o0()), g1_wsf(), s0(), 9n, ep_h(), True{}))))
    Unit <- E.must("g1 wrong endpoint drops", Bool.not(comp_rel(WsNet.ws_notify.completed(obs_nnot(g1_o0()), g1_wsf(), s0(), 1n, "x.test:1", True{}))))
    # Gate 2: eight hands, ninth unadmitted, completion rescans without input.
    Unit <- E.must_eq("g2 queue cap eight", Nat.show(N.QUEUE_CAP()), "8")
    Unit <- E.must_eq("g2 hands eight", Nat.show(obs_jobs(g2_o())), "8")
    Unit <- E.must_eq("g2 hands in order", obs_titles(g2_o()), "a1 in #a;a2 in #a;a3 in #a;a4 in #a;a5 in #a;a6 in #a;a7 in #a;a8 in #a;")
    Unit <- E.must("g2 floor below final", Nat.is_lt(entry_floor(obs_nnot(g2_o()), s0()), part_seq(g2_wsf(), s0())))
    Unit <- E.must("g2 completion releases", comp_rel(g2_c()))
    Unit <- E.must_eq("g2 rescan hands ninth", comp_titles(g2_c()), "a9 in #a;")
    Unit <- E.must("g2 floor reaches final", Nat.is_eq(entry_floor(comp_nnot(g2_c()), s0()), part_seq(g2_wsf(), s0())))
    Unit <- E.must_eq("g2 nine total", Nat.show(Nat.add(obs_jobs(g2_o()), comp_jobs(g2_c()))), "9")
    Unit <- E.must("g2 second releases", comp_rel(g2_c2()))
    Unit <- E.must_eq("g2 second drains nothing", Nat.show(comp_jobs(g2_c2())), "0")
    Unit <- E.must_eq("g2 replay quiet", Nat.show(obs_jobs(g2_r())), "0")
    # Gate 3: per-ID archive claims; refused installs are no-ops.
    Unit <- E.must_eq("g3 installed ids", nat_ids(g3_installed()), Nat.show(Nat.add(g3_before(), 1n)) ++ "," ++ Nat.show(Nat.add(g3_before(), 2n)) ++ ",")
    Unit <- E.must_eq("g3 refused keeps queue", Nat.show(entry_qlen(g3_ref(), s0())), "1")
    Unit <- E.must_eq("g3 refused keeps claims empty", entry_claims(g3_ref(), s0()), "")
    Unit <- E.must("g3 refused keeps floor", Nat.is_eq(entry_floor(g3_ref(), s0()), entry_floor(obs_nnot(g3_oq()), s0())))
    Unit <- E.must_eq("g3 accepted merges claims", entry_claims(g3_acc(), s0()), nat_ids(g3_installed()))
    Unit <- E.must_eq("g3 accepted keeps pending", Nat.show(entry_qlen(g3_acc(), s0())), "1")
    Unit <- E.must("g3 accepted keeps floor", Nat.is_eq(entry_floor(g3_acc(), s0()), entry_floor(obs_nnot(g3_oq()), s0())))
    Unit <- E.must_eq("g3 hands pending only", obs_titles(g3_o()), "bob in #a;")
    Unit <- E.must_eq("g3 later live delivers", comp_titles(g3_c()), "erin in #a;")
    Unit <- E.must_eq("g3 archive never private", obs_titles(g3_o()) ++ comp_titles(g3_c()) ++ comp_titles(g3_c2()) ++ obs_titles(g3_r()), "bob in #a;erin in #a;")
    Unit <- E.must_eq("g3 replay quiet", Nat.show(obs_jobs(g3_r())), "0")
    # Gate 4: replacement drops stale queued work, keeps unrelated work.
    Unit <- E.must_eq("g4 s1 hands carol", obs_titles(g4_o1()), "carol in #b;")
    Unit <- E.must_eq("g4 s0 quiets bob", Nat.show(obs_jobs(g4_o0())), "0")
    Unit <- E.must_eq("g4 s0 retains bob", Nat.show(entry_qlen(obs_nnot(g4_o0()), s0())), "1")
    Unit <- E.must_eq("g4 s1 quiets frank", Nat.show(obs_jobs(g4_o1b())), "0")
    Unit <- E.must("g4 completion releases", comp_rel(g4_c()))
    Unit <- E.must_eq("g4 unrelated frank kept", comp_titles(g4_c()), "frank in #b;")
    Unit <- E.must("g4 duplicate drops", Bool.not(comp_rel(g4_dup())))
    Unit <- E.must_eq("g4 duplicate keeps lease", lease_of(comp_nnot(g4_dup())), "1:2:" ++ ep_i())
    Unit <- E.must("g4 second releases", comp_rel(g4_c2()))
    Unit <- E.must_eq("g4 second drains nothing", Nat.show(comp_jobs(g4_c2())), "0")
    Unit <- E.must_eq("g4 replaced fires nothing", Nat.show(obs_jobs(g4_o0r())), "0")
    Unit <- E.must_eq("g4 replaced queue dropped", Nat.show(entry_qlen(obs_nnot(g4_o0r()), s0())), "0")
    Unit <- E.must("g4 replaced floor reset", Nat.is_eq(entry_floor(obs_nnot(g4_o0r()), s0()), part_seq(g4_wsf(), s0())))
    Unit <- E.must_eq("g4 owner hands bob", obs_titles(g4b_o0()), "bob in #a;")
    Unit <- E.must("g4b owner release once", comp_rel(g4b_c()))
    Unit <- E.must_eq("g4b owner drains nothing", Nat.show(comp_jobs(g4b_c())), "0")
    Unit <- E.must_eq("g4b lease cleared", lease_of(comp_nnot(g4b_c())), "none")
    Unit <- E.must("g4b duplicate drops", Bool.not(comp_rel(g4b_dup())))
    Unit <- E.must_eq("g4m quiet retains", Nat.show(entry_qlen(obs_nnot(g4m_oq()), s0())), "1")
    Unit <- E.must_eq("g4m move fires nothing", Nat.show(obs_jobs(g4m_o())), "0")
    Unit <- E.must_eq("g4m move clears queue", Nat.show(entry_qlen(obs_nnot(g4m_o()), s0())), "0")
    Unit <- E.must_eq("g4m move endpoint", entry_endpoint(obs_nnot(g4m_o()), s0()), "h.example:6667")
    # R4 argv: birc-notify admitted with notify-send shape; impostors rejected.
    Unit <- E.must("known birc-notify", NIO.known_helper("/nix/store/x/bin/birc-notify"))
    Unit <- E.must("known notify-send", NIO.known_helper("notify-send"))
    Unit <- E.must("known rejects impostor", Bool.not(NIO.known_helper("x-notify-send")))
    Unit <- E.must_eq("argv birc-notify shape", argv_joined(NIO.args_for("birc-notify", N.Req{"T", "B"})), "--|T|B|")
    Unit <- E.must_eq("argv unknown empty", argv_joined(NIO.args_for("x-notify-send", N.Req{"T", "B"})), "")
    run_physical()

def pair_jobs(pair: WsNet.WsNotify & List<&2, N.Req>) -> List<&2, N.Req>:
  match pair:
    case (_, +jobs): jobs

def trip_jobs(t: WsNet.WsNotify & List<&2, N.Req> & Bool) -> List<&2, N.Req>:
  match t:
    case (_, +jobs, _): jobs

# Physical barrier through the actual production path: spawns go through
# ws_notify.spawn_ticket (captured owner channel, ticket, endpoint), and
# each received completion threads its own ticket/endpoint through
# ws_notify.completed (never a precomputed completion state).
def run_owned(+h: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("helper admitted", NIO.known_helper(h))
    +evt0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +evt1 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +evt2 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +evt3 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +evts : WsNet.WsEvts <- IO.pure(WsNet.WsEvts, WsNet.WsEvts{evt0, evt1, evt2, evt3})
    +jobs0 = pair_jobs(g1_o0())
    +nn0 = obs_nnot(g1_o0())
    _ : WsNet.WsNotify & W.Workspace <- WsNet.ws_notify.spawn_ticket(WsNet.ws_notify.lease(nn0), h, jobs0, evts, nn0, g1_wsf())
    Unit <- IO.sleep(100)
    +log1 : String <- read_log(h)
    Unit <- E.must_eq("worker1 ran once", log1, "start -- bob in #a <bob> hi me\ndone -- bob in #a <bob> hi me\n")
    +d0 : Sess.UiMsg <- recv_one(evt0)
    Unit <- E.must_eq("done1 on owner channel", done_shown(d0), "1:" ++ ep_h())
    +t1 : Nat <- IO.pure(Nat, recv_ticket(d0))
    +e1 : String <- IO.pure(String, recv_endpoint(d0))
    +c1 : WsNet.WsNotify & List<&2, N.Req> & Bool <- IO.pure(WsNet.WsNotify & List<&2, N.Req> & Bool, WsNet.ws_notify.completed(nn0, g1_wsf(), s0(), t1, e1, True{}))
    +jobs1 : List<&2, N.Req> <- IO.pure(List<&2, N.Req>, trip_jobs(c1))
    +nn1 : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(c1))
    _ : WsNet.WsNotify & W.Workspace <- WsNet.ws_notify.spawn_ticket(WsNet.ws_notify.lease(nn1), h, jobs1, evts, nn1, g1_wsf())
    Unit <- IO.sleep(100)
    +log2 : String <- read_log(h)
    Unit <- E.must_eq("two sequential workers", log2, "start -- bob in #a <bob> hi me\ndone -- bob in #a <bob> hi me\nstart -- carol in #b <carol> yo me\ndone -- carol in #b <carol> yo me\n")
    +d1 : Sess.UiMsg <- recv_one(evt1)
    Unit <- E.must_eq("done2 on stolen channel", done_shown(d1), "2:" ++ ep_h())
    +t2 : Nat <- IO.pure(Nat, recv_ticket(d1))
    +e2 : String <- IO.pure(String, recv_endpoint(d1))
    # The received completion threads through production completed (never a
    # precomputed state); the freed lease takes a fresh queued request.
    +c2 : WsNet.WsNotify & List<&2, N.Req> & Bool <- IO.pure(WsNet.WsNotify & List<&2, N.Req> & Bool, WsNet.ws_notify.completed(nn1, g1_wsf(), s1(), t2, e2, True{}))
    +nn2 : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(c2))
    Unit <- E.must("c2 releases", comp_rel(c2))
    Unit <- E.must_eq("c2 drains nothing", Nat.show(comp_jobs(c2)), "0")
    Unit <- E.must_eq("lease cleared", lease_of(nn2), "none")
    +oD : WsNet.WsNotify & List<&2, N.Req> <- IO.pure(WsNet.WsNotify & List<&2, N.Req>, WsNet.ws_notify.observed(nn2, s1(), 0, g1_st1fd(), True{}))
    +nnD : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, obs_nnot(oD))
    +jobsD : List<&2, N.Req> <- IO.pure(List<&2, N.Req>, pair_jobs(oD))
    Unit <- E.must_eq("fresh request hands dave", req_titles(jobsD), "dave in #b;")
    Unit <- E.must_eq("fresh lease takes ticket 3", lease_of(nnD), "1:3:" ++ ep_h())
    _ : WsNet.WsNotify & W.Workspace <- WsNet.ws_notify.spawn_ticket(WsNet.ws_notify.lease(nnD), bad_helper(), jobsD, evts, nnD, g1_wsfd())
    Unit <- IO.sleep(100)
    +f0 : Sess.UiMsg <- recv_one(evt1)
    Unit <- E.must_eq("failed helper logs error", msg_kind(f0), "error")
    +f1 : Sess.UiMsg <- recv_one(evt1)
    Unit <- E.must_eq("failed worker still completes", done_shown(f1), "3:" ++ ep_h())
    +t3 : Nat <- IO.pure(Nat, recv_ticket(f1))
    +e3 : String <- IO.pure(String, recv_endpoint(f1))
    +c3 : WsNet.WsNotify & List<&2, N.Req> & Bool <- IO.pure(WsNet.WsNotify & List<&2, N.Req> & Bool, WsNet.ws_notify.completed(nnD, g1_wsfd(), s1(), t3, e3, True{}))
    +nn3 : WsNet.WsNotify <- IO.pure(WsNet.WsNotify, comp_nnot(c3))
    Unit <- E.must("c3 releases", comp_rel(c3))
    Unit <- E.must_eq("c3 drains nothing", Nat.show(comp_jobs(c3)), "0")
    Unit <- E.must_eq("lease cleared after failure", lease_of(nn3), "none")
    +log3 : String <- read_log(h)
    Unit <- E.must_eq("failed spawn adds no run", log3, log2)
    IO.print("notify_binding_gates=ok")

def deliver_phys(helper: Maybe<&2, String>) -> IO(Unit):
  match helper:
    case None{}: IO.die(Unit, 1, "no helper resolved")
    case Some{+h}: run_owned(h)

def run_physical() -> IO(Unit):
  do IO<Unit>:
    helper : Maybe<&2, String> <- NIO.program_or_default("fallback-default")
    deliver_phys(helper)
