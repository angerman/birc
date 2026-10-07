# Notify follow-up guards: reconnect floor/lease + chained completion threading.
# R1: an actual Dial-gen reconnect seeds its fresh entry at the PRE-accept
# floor, so the first framed post-reconnect mention stages instead of being
# lost pre-scanned. R2: the old physical lease stays until the exact done,
# and the staged mention then delivers exactly once. R3: same-gen delivery
# is unchanged (positive control). R4: a changed-endpoint reconnect stays
# quiet at the exact post floor (scope gate, no stale pre floor). T: chained
# wrong-ticket then wrong-origin completions thread forward on returned
# state and latch nothing; the exact completion then runs the FIFO once.
# Actual framed bursts through the real workspace dispatch; selected event
# IDs pin the bursts (never synthetic counts). JS backend, pure (no helper).
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/frame.bend as Fr
import ../../src/bend/notify.bend as N
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/wsnet.bend as WsNet

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def ep_h() -> String:
  "h.example:6697"

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

def obs_nnot(pair: WsNet.WsNotify & List<&2, N.Req>) -> WsNet.WsNotify:
  match pair:
    case (+nnot, _): nnot

def obs_jobs(pair: WsNet.WsNotify & List<&2, N.Req>) -> Nat:
  match pair:
    case (_, +jobs): List.length(&2, N.Req, jobs)

def obs_titles(pair: WsNet.WsNotify & List<&2, N.Req>) -> String:
  match pair:
    case (_, +jobs): req_titles(jobs)

def comp_nnot(t: WsNet.WsNotify & (List<&2, N.Req> & Bool)) -> WsNet.WsNotify:
  match t:
    case (+nnot, _): nnot

def comp_jobs.r1(rest: List<&2, N.Req> & Bool) -> Nat:
  match rest:
    case (+jobs, _): List.length(&2, N.Req, jobs)

def comp_jobs(t: WsNet.WsNotify & (List<&2, N.Req> & Bool)) -> Nat:
  match t:
    case (_, rest): comp_jobs.r1(rest)

def comp_titles.r1(rest: List<&2, N.Req> & Bool) -> String:
  match rest:
    case (+jobs, _): req_titles(jobs)

def comp_titles(t: WsNet.WsNotify & (List<&2, N.Req> & Bool)) -> String:
  match t:
    case (_, rest): comp_titles.r1(rest)

def comp_rel.r1(rest: List<&2, N.Req> & Bool) -> Bool:
  match rest:
    case (_, +released): released

def comp_rel(t: WsNet.WsNotify & (List<&2, N.Req> & Bool)) -> Bool:
  match t:
    case (_, rest): comp_rel.r1(rest)

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

def entry_endpoint(+nnot: WsNet.WsNotify, +id: Key.ServerId) -> String:
  Sess.notify_live_endpoint(entry_nl(nnot, id))

def part_seq(+ws: W.Workspace, +id: Key.ServerId) -> Nat:
  Cl.log_seq_of(Sess.session_cl(WsNet.ws_part.st(ws, id)))

def solo_ws() -> W.Workspace:
  W.single_client("h.example", 6697, False{}, Feed.feed(Cl.init("me", "h.example"), ":me!u@h JOIN #a"), "#a")

# ---- R1: reconnect-fresh entry stages the first framed mention ------------
def r1_wsd() -> W.Workspace:
  bumped(solo_ws(), s0())

def r1_wsf() -> W.Workspace:
  framed(r1_wsd(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")

def r1_pre() -> Sess.Session:
  WsNet.ws_part.st(r1_wsd(), s0())

def r1_post() -> Sess.Session:
  WsNet.ws_part.st(r1_wsf(), s0())

def r1_o() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed_pre(WsNet.ws_notify.seed_all(solo_ws()), s0(), 1, r1_pre(), r1_post(), True{})

def r1_ids() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(r1_post()), ep_h(), part_seq(r1_wsd(), s0())))

def r1_r() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed_pre(obs_nnot(r1_o()), s0(), 1, r1_post(), r1_post(), True{})

# ---- R2: old lease stays until exact done, then staged mention fires once --
def r2_wsa() -> W.Workspace:
  framed(solo_ws(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")

def r2_oA() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed_pre(WsNet.ws_notify.seed_all(solo_ws()), s0(), 0, WsNet.ws_part.st(solo_ws(), s0()), WsNet.ws_part.st(r2_wsa(), s0()), True{})

def r2_wsd() -> W.Workspace:
  bumped(r2_wsa(), s0())

def r2_wsf() -> W.Workspace:
  framed(r2_wsd(), s0(), ":erin!u@h PRIVMSG #a :yo me\r\n")

def r2_preB() -> Sess.Session:
  WsNet.ws_part.st(r2_wsd(), s0())

def r2_postB() -> Sess.Session:
  WsNet.ws_part.st(r2_wsf(), s0())

def r2_oB() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed_pre(obs_nnot(r2_oA()), s0(), 1, r2_preB(), r2_postB(), True{})

def r2_idsB() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(r2_postB()), ep_h(), part_seq(r2_wsd(), s0())))

def r2_c() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(obs_nnot(r2_oB()), r2_wsf(), s0(), 1n, ep_h(), True{})

def r2_c2() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(r2_c()), r2_wsf(), s0(), 2n, ep_h(), True{})

# ---- R3: same-gen delivery unchanged (positive control) --------------------
def r3_wsf() -> W.Workspace:
  framed(solo_ws(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")

def r3_o() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed_pre(WsNet.ws_notify.seed_all(solo_ws()), s0(), 0, WsNet.ws_part.st(solo_ws(), s0()), WsNet.ws_part.st(r3_wsf(), s0()), True{})

def r3_c() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(obs_nnot(r3_o()), r3_wsf(), s0(), 1n, ep_h(), True{})

def r3_r() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed_pre(comp_nnot(r3_c()), s0(), 0, WsNet.ws_part.st(r3_wsf(), s0()), WsNet.ws_part.st(r3_wsf(), s0()), True{})

# ---- R4: changed-endpoint reconnect stays quiet at the exact post floor ----
def r4_wsd() -> W.Workspace:
  bumped(solo_ws(), s0())

def r4_wsf() -> W.Workspace:
  framed(r4_wsd(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")

def r4_moved() -> Sess.Session:
  Sess.session_with_client_at(Sess.session_cl(WsNet.ws_part.st(r4_wsf(), s0())), "#a", 6667)

def r4_o() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed_pre(WsNet.ws_notify.seed_all(solo_ws()), s0(), 1, WsNet.ws_part.st(r4_wsd(), s0()), r4_moved(), True{})

def r4_seq() -> Nat:
  Cl.log_seq_of(Sess.session_cl(r4_moved()))

# ---- T: chained wrong completions thread forward, then exact runs once -----
def t_wsa() -> W.Workspace:
  framed(solo_ws(), s0(), ":bob!u@h PRIVMSG #a :hi me\r\n")

def t_oA() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(WsNet.ws_notify.seed_all(solo_ws()), s0(), 0, WsNet.ws_part.st(t_wsa(), s0()), True{})

def t_wsb() -> W.Workspace:
  framed(t_wsa(), s0(), ":frank!u@h PRIVMSG #a :ping me\r\n")

def t_oB() -> WsNet.WsNotify & List<&2, N.Req>:
  WsNet.ws_notify.observed(obs_nnot(t_oA()), s0(), 0, WsNet.ws_part.st(t_wsb(), s0()), True{})

def t_idsB() -> String:
  ev_ids(Sess.notify_collect(Sess.session_cl(WsNet.ws_part.st(t_wsb(), s0())), ep_h(), part_seq(t_wsa(), s0())))

def t_wrong_ticket() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(obs_nnot(t_oB()), t_wsb(), s0(), 99n, ep_h(), True{})

def t_wrong_origin() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(t_wrong_ticket()), t_wsb(), s0(), 1n, "x.test:1", True{})

def t_exact() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(t_wrong_origin()), t_wsb(), s0(), 1n, ep_h(), True{})

def t_dup() -> WsNet.WsNotify & List<&2, N.Req> & Bool:
  WsNet.ws_notify.completed(comp_nnot(t_exact()), t_wsb(), s0(), 1n, ep_h(), True{})

def main() -> IO(Unit):
  do IO<Unit>:
    # R1: first framed mention after reconnect stages (never pre-scanned).
    Unit <- E.must_eq("r1 selected id", r1_ids(), Nat.show(part_seq(r1_wsf(), s0())) ++ ",")
    Unit <- E.must_eq("r1 hands bob once", obs_titles(r1_o()), "bob in #a;")
    Unit <- E.must_eq("r1 hands one job", Nat.show(obs_jobs(r1_o())), "1")
    Unit <- E.must_eq("r1 lease taken", lease_of(obs_nnot(r1_o())), "0:1:" ++ ep_h())
    Unit <- E.must("r1 floor reaches final", Nat.is_eq(entry_floor(obs_nnot(r1_o()), s0()), part_seq(r1_wsf(), s0())))
    Unit <- E.must_eq("r1 replay quiet", Nat.show(obs_jobs(r1_r())), "0")
    # R2: old lease stays until the exact done; staged mention fires once.
    Unit <- E.must_eq("r2 idsB selected", r2_idsB(), Nat.show(part_seq(r2_wsf(), s0())) ++ ",")
    Unit <- E.must_eq("r2 first hands bob", obs_titles(r2_oA()), "bob in #a;")
    Unit <- E.must_eq("r2 reconnect quiets", Nat.show(obs_jobs(r2_oB())), "0")
    Unit <- E.must_eq("r2 reconnect retains one", Nat.show(entry_qlen(obs_nnot(r2_oB()), s0())), "1")
    Unit <- E.must_eq("r2 old lease stays", lease_of(obs_nnot(r2_oB())), "0:1:" ++ ep_h())
    Unit <- E.must("r2 staged floor reaches final", Nat.is_eq(entry_floor(obs_nnot(r2_oB()), s0()), part_seq(r2_wsf(), s0())))
    Unit <- E.must("r2 exact releases", comp_rel(r2_c()))
    Unit <- E.must_eq("r2 staged fires once", comp_titles(r2_c()), "erin in #a;")
    Unit <- E.must_eq("r2 fires one job", Nat.show(comp_jobs(r2_c())), "1")
    Unit <- E.must_eq("r2 lease moves", lease_of(comp_nnot(r2_c())), "0:2:" ++ ep_h())
    Unit <- E.must("r2 second releases", comp_rel(r2_c2()))
    Unit <- E.must_eq("r2 second drains nothing", Nat.show(comp_jobs(r2_c2())), "0")
    Unit <- E.must_eq("r2 lease cleared", lease_of(comp_nnot(r2_c2())), "none")
    # R3: same-gen delivery unchanged.
    Unit <- E.must_eq("r3 hands bob once", obs_titles(r3_o()), "bob in #a;")
    Unit <- E.must_eq("r3 lease taken", lease_of(obs_nnot(r3_o())), "0:1:" ++ ep_h())
    Unit <- E.must("r3 exact releases", comp_rel(r3_c()))
    Unit <- E.must_eq("r3 drains nothing retained", Nat.show(comp_jobs(r3_c())), "0")
    Unit <- E.must_eq("r3 lease cleared", lease_of(comp_nnot(r3_c())), "none")
    Unit <- E.must_eq("r3 replay quiet", Nat.show(obs_jobs(r3_r())), "0")
    # R4: changed-endpoint reconnect stays quiet at the exact post floor.
    Unit <- E.must_eq("r4 fires nothing", Nat.show(obs_jobs(r4_o())), "0")
    Unit <- E.must_eq("r4 queue empty", Nat.show(entry_qlen(obs_nnot(r4_o()), s0())), "0")
    Unit <- E.must_eq("r4 endpoint moved", entry_endpoint(obs_nnot(r4_o()), s0()), "h.example:6667")
    Unit <- E.must("r4 floor exact post", Nat.is_eq(entry_floor(obs_nnot(r4_o()), s0()), r4_seq()))
    Unit <- E.must_eq("r4 lease free", lease_of(obs_nnot(r4_o())), "none")
    # T: wrong completions thread forward and latch nothing; exact runs once.
    Unit <- E.must_eq("t idsB selected", t_idsB(), Nat.show(part_seq(t_wsb(), s0())) ++ ",")
    Unit <- E.must_eq("t first hands bob", obs_titles(t_oA()), "bob in #a;")
    Unit <- E.must_eq("t busy retains frank", Nat.show(entry_qlen(obs_nnot(t_oB()), s0())), "1")
    Unit <- E.must("t wrong ticket drops", Bool.not(comp_rel(t_wrong_ticket())))
    Unit <- E.must_eq("t wrong ticket keeps lease", lease_of(comp_nnot(t_wrong_ticket())), "0:1:" ++ ep_h())
    Unit <- E.must_eq("t wrong ticket keeps queue", Nat.show(entry_qlen(comp_nnot(t_wrong_ticket()), s0())), "1")
    Unit <- E.must("t wrong origin drops", Bool.not(comp_rel(t_wrong_origin())))
    Unit <- E.must_eq("t wrong origin keeps lease", lease_of(comp_nnot(t_wrong_origin())), "0:1:" ++ ep_h())
    Unit <- E.must_eq("t wrong origin keeps queue", Nat.show(entry_qlen(comp_nnot(t_wrong_origin()), s0())), "1")
    Unit <- E.must("t exact releases", comp_rel(t_exact()))
    Unit <- E.must_eq("t exact runs fifo once", comp_titles(t_exact()), "frank in #a;")
    Unit <- E.must_eq("t exact one job", Nat.show(comp_jobs(t_exact())), "1")
    Unit <- E.must_eq("t lease moves", lease_of(comp_nnot(t_exact())), "0:2:" ++ ep_h())
    Unit <- E.must("t consumed replay drops", Bool.not(comp_rel(t_dup())))
    Unit <- E.must_eq("t replay keeps lease", lease_of(comp_nnot(t_dup())), "0:2:" ++ ep_h())
    IO.print("notify_followup_guards=ok")
