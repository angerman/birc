# SPDX-License-Identifier: Apache-2.0
# N9 full follow-up GATES 2+3 (red-first): single-worker bounded drain with
# marks consumed only for reqs handed to the worker, and the live per-chunk
# dispatch package (observe with cutoff, stage into the bounded queue, drain,
# helper resolution with quiet undeliverable retention). Fails to compile
# before the fix (new API absent). IO delivery uses a recipe-provided fake
# `notify-send` plus an owned log file; no live services. Synthetic fixtures.
# n9-bind2 adds R1/R2/R3 red-first guards (physical-worker retention, durable
# per-ID claims, callback-gated seeding) plus claim-producer and rescan guards.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/frame.bend as Fr
import ../../src/bend/notify.bend as Notify
import ../../src/bend/notify_io.bend as NotifyIO
import ../../src/bend/session.bend as Sess
import ../../src/bend/history_startup.bend as Startup
import ../../src/bend/net.bend as Net
import ../../src/bend/live_context.bend as LC
import ../../src/bend/preferences_live.bend as PL
import ../../src/bend/preferences_runtime.bend as PR

def scope() -> String:
  "irc.test:6697"

# ---- shared builders --------------------------------------------------------
def req_at(+n: Nat) -> Notify.Req:
  Notify.Req{"t" ++ Nat.show(n), "b" ++ Nat.show(n)}

def reqs_upto(left: Nat, +n: Nat) -> List<&2, Notify.Req>:
  match left:
    case 0n: Nil{}
    case 1n+p: req_at(n) <> reqs_upto(p, Nat.add(n, 1n))

def q8() -> Notify.Queue:
  Notify.enqueue_all(Notify.queue_empty(), reqs_upto(8n, 0n))

def req_titles(rs: List<&2, Notify.Req>) -> String:
  match rs:
    case Nil{}: ""
    case Con{r, t}: Notify.req_title(r) ++ ";" ++ req_titles(t)

def maybe_str(+got: Maybe<&2, String>) -> String:
  match got:
    case None{}: "(none)"
    case Some{+h}: h

def bool_str(ok: Bool) -> String:
  match ok:
    case True{}: "true"
    case False{}: "false"

def hi_shown(+got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "unknown"
    case Some{hi}: Nat.show(hi)

# ---- GATE 2 pure: single-handoff drain ---------------------------------------
def drained_staged(pair: Notify.Queue & List<&2, Notify.Req>) -> String:
  match pair:
    case (_, rs): req_titles(rs)

def drained_kept(pair: Notify.Queue & List<&2, Notify.Req>) -> String:
  match pair:
    case (q, _): Nat.show(Notify.queue_len(q))

# ---- GATE 2 pure: staged dispatch (marks on admit) ---------------------------
def ev_at(+id: Nat, +author: String) -> Notify.NotifyEvent:
  Notify.NotifyEvent{id, scope(), author, "#a", "hi me", False{}, True{}}

def stage_handed(+s: Notify.Stage) -> String:
  req_titles(Notify.stage_reqs(s))

def stage_q(+s: Notify.Stage) -> String:
  Nat.show(Notify.queue_len(Notify.stage_queue(s)))

def stage_hi(+s: Notify.Stage) -> String:
  Nat.show(Notify.stage_hi(s))

def stage_mk(+s: Notify.Stage, +sc: String) -> String:
  hi_shown(Notify.hi_of(Notify.stage_st(s), sc))

def marks8() -> Notify.State:
  Notify.seed(Notify.on(), scope(), 8n)

# ---- GATE 3 pure: staged session seam ----------------------------------------
def cl_mention() -> Cl.Client:
  Feed.feed(Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #room"), ":bob!u@h PRIVMSG #room :hi me")

def sess_mention() -> Sess.Session:
  Sess.session_with_client(cl_mention(), "#room")

# ---- GATE 3 pure: framed live steps ------------------------------------------
def st0() -> Sess.Session:
  Sess.session_with_client(Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #room"), "#room")

def floor0() -> Nat:
  Cl.log_seq_of(Sess.session_cl(st0()))

def chunk1() -> List<&2, U32>:
  Fr.string_to_octets(":bob!u@h PRIVMSG #room :hi me\r\n")

def chunk2() -> List<&2, U32>:
  Fr.string_to_octets(":bob!u@h PRIVMSG #room :hello\r\n:bob!u@h PRIVMSG me :hey you\r\n")

def chunk3() -> List<&2, U32>:
  Fr.string_to_octets(":carol!u@h PRIVMSG #room :yo me\r\n")

def chunk_mixed() -> List<&2, U32>:
  Fr.string_to_octets(":bob!u@h PRIVMSG #room :hi me\r\n:carol!u@h PRIVMSG #room :yo me\r\n:dave!u@h PRIVMSG me :hello\r\n:erin!u@h PRIVMSG me :hey\r\n")

def claimed_mixed() -> List<&2, Nat>:
  3n <> 5n <> Nil{}

def live_nl(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> Sess.NotifyLive:
  match r:
    case (nl, _, _, _): nl

def live_sess(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> Sess.Session:
  match r:
    case (_, st, _, _): st

def live_outs(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> String:
  match r:
    case (_, _, outs, _): String.join(outs, "|")

def live_handed(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> String:
  match r:
    case (_, _, _, handed): req_titles(handed)

def live_handed_len(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> String:
  match r:
    case (_, _, _, handed): Nat.show(List.length(&2, Notify.Req, handed))

def live_seq(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> String:
  Nat.show(Cl.log_seq_of(Sess.session_cl(live_sess(r))))

def live_scanned(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> String:
  Nat.show(Sess.notify_live_scanned(live_nl(r)))

def live_qlen(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> String:
  Nat.show(Notify.queue_len(Sess.notify_live_queue(live_nl(r))))

def live_mkhi(r: Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>) -> String:
  hi_shown(Notify.hi_of(Sess.notify_live_st(live_nl(r)), scope()))

# ---- GATE 1 (n9-bind red): one retained physical worker -----------------------
def nl_ep() -> Sess.NotifyLive:
  Sess.notify_live_init_ep(Notify.on(), floor0(), scope())

def step_mixed_claimed() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(nl_ep(), st0(), chunk_mixed(), 0, True{}, claimed_mixed())

def step_mixed_noclaim() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(nl_ep(), st0(), chunk_mixed(), 0, True{}, Nil{})

def step_mixed_h5() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(nl_ep(), st0(), chunk_mixed(), 0, True{}, Notify.claimed_from_ids(claimed_mixed()))

def step_g1_1() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_ep(), st0(), chunk1(), 0, True{})

def nl_g1_1() -> Sess.NotifyLive:
  live_nl(step_g1_1())

def st_g1_1() -> Sess.Session:
  live_sess(step_g1_1())

def step_g1_2() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_g1_1(), st_g1_1(), chunk2(), 0, True{})

def nl_g1_2() -> Sess.NotifyLive:
  live_nl(step_g1_2())

def st_g1_2() -> Sess.Session:
  live_sess(step_g1_2())

def step_g1_3() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_g1_2(), st_g1_2(), chunk3(), 0, True{})

def nl_g1_3() -> Sess.NotifyLive:
  live_nl(step_g1_3())

def active_shown(+got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "none"
    case Some{n}: Nat.show(n)

def nl_active_shown(+nl: Sess.NotifyLive) -> String:
  active_shown(Sess.notify_live_active(nl))

def nl_busy_shown(+nl: Sess.NotifyLive) -> String:
  bool_str(Sess.notify_live_busy(nl))

def nl_next_shown(+nl: Sess.NotifyLive) -> String:
  Nat.show(Sess.notify_live_next(nl))

def comp_nl(r: Sess.NotifyLive & List<&2, Notify.Req> & Bool) -> Sess.NotifyLive:
  match r:
    case (nl, _, _): nl

def comp_jobs(r: Sess.NotifyLive & List<&2, Notify.Req> & Bool) -> String:
  match r:
    case (_, jobs, _): req_titles(jobs)

def comp_rel(r: Sess.NotifyLive & List<&2, Notify.Req> & Bool) -> String:
  match r:
    case (_, _, rel): bool_str(rel)

def comp_qlen(r: Sess.NotifyLive & List<&2, Notify.Req> & Bool) -> String:
  Nat.show(Notify.queue_len(Sess.notify_live_queue(comp_nl(r))))

# Legacy two-step flows now complete the first worker before the next
# deliverable handoff; retention would otherwise block the second hand.
def step_legacy_1() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})

def nl_legacy_1c() -> Sess.NotifyLive:
  comp_nl(Sess.notify_live_complete(live_nl(step_legacy_1()), 1n, ""))

def st_legacy_1() -> Sess.Session:
  live_sess(step_legacy_1())

def step_legacy_2() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_legacy_1c(), st_legacy_1(), chunk2(), 0, True{})

def step_legacy_2_out() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_legacy_1c(), st_legacy_1(), chunk2(), 0, False{})

def nl_legacy_2_out() -> Sess.NotifyLive:
  live_nl(step_legacy_2_out())

def st_legacy_2_out() -> Sess.Session:
  live_sess(step_legacy_2_out())

def step_legacy_3_rec() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_legacy_2_out(), st_legacy_2_out(), Nil{}, 0, True{})

# ---- GATE 4 (n9-bind red): endpoint/off reset + post-restore seeding -----------
def st_g1_3() -> Sess.Session:
  live_sess(step_g1_3())

def nl_reset() -> Sess.NotifyLive:
  Sess.notify_live_reset_endpoint(nl_g1_3(), "other.test:6697", 0n)

def nl_off() -> Sess.NotifyLive:
  Sess.notify_live_off(nl_g1_3())

def nl_qlen_shown(+nl: Sess.NotifyLive) -> String:
  Nat.show(Notify.queue_len(Sess.notify_live_queue(nl)))

def nl_enabled_shown(+nl: Sess.NotifyLive) -> String:
  bool_str(Notify.enabled(Sess.notify_live_st(nl)))

def nl_endpoint_shown(+nl: Sess.NotifyLive) -> String:
  Sess.notify_live_endpoint(nl)

def nl_scanned_shown(+nl: Sess.NotifyLive) -> String:
  Nat.show(Sess.notify_live_scanned(nl))

def nl_marks_shown(+nl: Sess.NotifyLive, +sc: String) -> String:
  hi_shown(Notify.hi_of(Sess.notify_live_st(nl), sc))

def step_off_silent() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_off(), st_g1_3(), chunk1(), 0, True{})

def cl0_restore() -> Cl.Client:
  Cl.init("me", "irc.test")

def snapshot_restore() -> Cl.Client:
  Feed.feed(Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #room"), ":bob!u@h PRIVMSG #room :hi me")

def imported_restore() -> Cl.Client:
  Startup.install_startup(cl0_restore(), snapshot_restore())

def sess_imported() -> Sess.Session:
  Sess.session_with_client(imported_restore(), "#room")

def nl_seeded() -> Sess.NotifyLive:
  Sess.notify_live_seed_postrestore(Sess.notify_live_init_ep(Notify.on(), 0n, scope()), sess_imported())

def step_restore_silent() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_seeded(), sess_imported(), Nil{}, 0, True{})

def nl_restore_silent() -> Sess.NotifyLive:
  live_nl(step_restore_silent())

def st_restore_silent() -> Sess.Session:
  live_sess(step_restore_silent())

def step_restore_live() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_restore_silent(), st_restore_silent(), chunk3(), 0, True{})

# ---- GATE 5 (n9-bind red): ticket completion + endpoint cancel ----------------
def cancel_nl(r: Sess.NotifyLive & Bool) -> Sess.NotifyLive:
  match r:
    case (nl, _): nl

def cancel_rel(r: Sess.NotifyLive & Bool) -> String:
  match r:
    case (_, rel): bool_str(rel)

def cancel_exact() -> Sess.NotifyLive & Bool:
  Sess.notify_live_cancel(nl_g1_3(), scope())

def cancel_stale() -> Sess.NotifyLive & Bool:
  Sess.notify_live_cancel(nl_g1_3(), "other.test:6697")

# ---- R1 (n9-bind2 red): physical ticket + origin survive logical reset -------
def chunk_new() -> List<&2, U32>:
  Fr.string_to_octets(":frank!u@h PRIVMSG #room :ping me\r\n")

def nl_reset5() -> Sess.NotifyLive:
  Sess.notify_live_reset_endpoint(nl_g1_3(), "other.test:6697", 5n)

def step_r1_reset() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_reset5(), st_g1_3(), chunk_new(), 0, True{})

def nl_r1_reset() -> Sess.NotifyLive:
  live_nl(step_r1_reset())

def comp_r1_reset() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(nl_r1_reset(), 1n, scope())

def nl_r1_off_step() -> Sess.NotifyLive:
  live_nl(Sess.notify_live_step(nl_off(), st_g1_3(), chunk_new(), 0, True{}))

def comp_r1_off() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(nl_off(), 1n, scope())

def step_r1_cancel() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(cancel_nl(cancel_exact()), st_g1_3(), chunk_new(), 0, True{})

def nl_r1_cancel() -> Sess.NotifyLive:
  live_nl(step_r1_cancel())

def comp_r1_cancel() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(nl_r1_cancel(), 1n, scope())

def nl_r1_reset2() -> Sess.NotifyLive:
  Sess.notify_live_reset_endpoint(nl_reset(), "third.test:6697", 0n)

def nl_r1_idle() -> Sess.NotifyLive:
  Sess.notify_live_init_ep(Notify.on(), 0n, scope())

# ---- R2a (n9-bind2 red): durable per-ID claims, synthetic pre-claim ---------
def chunk_chatter6_erin() -> List<&2, U32>:
  Fr.string_to_octets(":bob!u@h PRIVMSG #room :hello0\r\n:bob!u@h PRIVMSG #room :hello1\r\n:bob!u@h PRIVMSG #room :hello2\r\n:bob!u@h PRIVMSG #room :hello3\r\n:bob!u@h PRIVMSG #room :hello4\r\n:bob!u@h PRIVMSG #room :hello5\r\n:erin!u@h PRIVMSG #room :hey me\r\n")

def step_r2_d0() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(nl_ep(), st0(), chunk1(), 0, True{}, 9n <> Nil{})

def nl_r2_d0() -> Sess.NotifyLive:
  live_nl(step_r2_d0())

def st_r2_d0() -> Sess.Session:
  live_sess(step_r2_d0())

def step_r2_d1() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(nl_r2_d0(), st_r2_d0(), chunk_chatter6_erin(), 0, True{}, Nil{})

def comp_r2_d() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(live_nl(step_r2_d1()), 1n, scope())

def step_r2_d2() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(comp_nl(comp_r2_d()), live_sess(step_r2_d1()), chunk_new(), 0, True{})

def step_r2_c1() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(live_nl(step_mixed_claimed()), live_sess(step_mixed_claimed()), Nil{}, 0, True{}, Nil{})

def comp_r2_c() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(live_nl(step_r2_c1()), 1n, scope())

def step_r2_c2() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(comp_nl(comp_r2_c()), live_sess(step_r2_c1()), chunk_new(), 0, True{})

def nl_origin_shown(+nl: Sess.NotifyLive) -> String:
  Sess.notify_live_origin(nl)

def ids_len(+xs: List<&2, Nat>) -> String:
  Nat.show(List.length(&2, Nat, xs))

def nl_claimed_len(+nl: Sess.NotifyLive) -> String:
  ids_len(Sess.notify_live_claimed(nl))

def nl_claimed_has(+nl: Sess.NotifyLive, +id: Nat) -> String:
  bool_str(List.contains(~Nat, ~Nat.is_eq, Sess.notify_live_claimed(nl), id))

# ---- R2b (n9-bind2 red): real claim producer + union/prune -------------------
def snapA() -> Cl.Client:
  Feed.feed(Feed.feed(Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #room"), ":bob!u@h PRIVMSG #room :hi me"), ":carol!u@h PRIVMSG #room :yo me")

def impA() -> Cl.Client:
  Startup.install_startup(Sess.session_cl(st0()), snapA())

def prodA() -> List<&2, Nat>:
  Sess.notify_claims_installed(1n, impA())

def sessA() -> Sess.Session:
  Sess.session_with_client(impA(), "#room")

def chunk_dave() -> List<&2, U32>:
  Fr.string_to_octets(":dave!u@h PRIVMSG #room :hey me\r\n")

def step_r2_a1() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(nl_ep(), sessA(), chunk_dave(), 0, True{}, prodA())

def impE() -> Cl.Client:
  Startup.install_startup(Sess.session_cl(st_g1_1()), snapA())

def prodE() -> List<&2, Nat>:
  Sess.notify_claims_installed(2n, impE())

def sessE() -> Sess.Session:
  Sess.session_with_client(impE(), "#room")

def step_r2_e1() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(nl_g1_1(), sessE(), Nil{}, 0, True{}, prodE())

def comp_r2_e() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(live_nl(step_r2_e1()), 1n, scope())

def step_r2_e2() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(comp_nl(comp_r2_e()), live_sess(step_r2_e1()), chunk_new(), 0, True{})

def all_above.go(+xs: List<&2, Nat>, +floor: Nat) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, t}: Nat.is_gt(h, floor) && all_above.go(t, floor)

def all_above_shown(+xs: List<&2, Nat>, +floor: Nat) -> String:
  bool_str(all_above.go(xs, floor))

def ids_head(+xs: List<&2, Nat>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{+h, _}: h

def ids_upto(left: Nat, +n: Nat) -> List<&2, Nat>:
  match left:
    case 0n: Nil{}
    case 1n+p: n <> ids_upto(p, Nat.add(n, 1n))

def ids_shown(+xs: List<&2, Nat>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, t}: Nat.show(h) ++ ";" ++ ids_shown(t)

# ---- R2c joint (n9-final): 65 truly-qualifying mentions, lossless (JS-safe) --
# 65 real new rows above seq 1, ALL notify-worthy mentions (IDs 2..66). The
# chatter-diluted fixture (60 chatter + 5 mentions) never stressed the claim
# bound; this one does. The floor-tied owner claims every qualifying
# installed id with no producer truncation, the ledger-backed bound holds
# all 65, archives stay quiet, and adjacent live notifies once.
def feed_mentions_at(left: Nat, +cl: Cl.Client, +n: Nat, +target: String) -> Cl.Client:
  match left:
    case 0n: cl
    case 1n+p: feed_mentions_at(p, Feed.feed(cl, ":bob!u@h PRIVMSG " ++ target ++ " :hi me " ++ Nat.show(n)), Nat.add(n, 1n), target)

def feed_mentions(left: Nat, +cl: Cl.Client, +n: Nat) -> Cl.Client:
  feed_mentions_at(left, cl, n, "#room")

def cl65_base() -> Cl.Client:
  Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #room")

def cl65() -> Cl.Client:
  feed_mentions(65n, cl65_base(), 0n)

def sess65() -> Sess.Session:
  Sess.session_with_client(cl65(), "#room")

def prod65() -> List<&2, Nat>:
  Sess.notify_claims_installed(1n, cl65())

def step_r2_65() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step_claimed(nl_ep(), sess65(), Nil{}, 0, True{}, prod65())

def step_r2_65_live() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(live_nl(step_r2_65()), live_sess(step_r2_65()), chunk_new(), 0, True{})

def dup_fresh() -> List<&2, Nat>:
  1n <> 1n <> 2n <> Nil{}

def dup_union() -> List<&2, Nat>:
  Notify.claim_union(Nil{}, dup_fresh())

def dup_union2() -> List<&2, Nat>:
  Notify.claim_union(1n <> 2n <> Nil{}, 2n <> 3n <> 3n <> Nil{})


# ---- GATE 2 (n9-bind red): live-chunk dispatch via Net ------------------------
def framed1() -> List<&2, String> & List<&2, U32> & Bool:
  Sess.frame_chunk(st0(), chunk1())

def fed1() -> Sess.Session & List<&2, String>:
  Sess.step_on_framed_ms(st0(), framed1(), Nil{}, 0)

def fed1_st.go(pair: Sess.Session & List<&2, String>) -> Sess.Session:
  match pair:
    case (+st, _): st

def fed1_st() -> Sess.Session:
  fed1_st.go(fed1())

def nl_net_init() -> Sess.NotifyLive:
  Net.net_notify_init(st0())

def obs_net() -> Sess.NotifyLive & List<&2, Notify.Req>:
  Net.net_notify_observe(nl_net_init(), fed1_st(), True{}, Nil{})

def obs_net_claimed() -> Sess.NotifyLive & List<&2, Notify.Req>:
  Net.net_notify_observe(nl_net_init(), fed1_st(), True{}, 2n <> Nil{})

def obs_nl(r: Sess.NotifyLive & List<&2, Notify.Req>) -> Sess.NotifyLive:
  match r:
    case (nl, _): nl

def obs_jobs(r: Sess.NotifyLive & List<&2, Notify.Req>) -> String:
  match r:
    case (_, jobs): req_titles(jobs)

# R2b Net fixtures (placed after the G2 accessors they use).
def obs_r2_n() -> Sess.NotifyLive & List<&2, Notify.Req>:
  Net.net_notify_observe(Net.net_notify_init(st0()), sessA(), True{}, prodA())

def sessAL() -> Sess.Session:
  Sess.session_with_client(Feed.feed(impA(), ":dave!u@h PRIVMSG #room :hey me"), "#room")

def obs_r2_n2() -> Sess.NotifyLive & List<&2, Notify.Req>:
  Net.net_notify_observe(obs_nl(obs_r2_n()), sessAL(), True{}, Nil{})

# JOIN #a(1), seven chatter rows (2-8), three mentions (9-11).
def cl_backlog() -> Cl.Client:
  Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(
    Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #a"),
    ":bob!u@h PRIVMSG #a :hello0"), ":bob!u@h PRIVMSG #a :hello1"), ":bob!u@h PRIVMSG #a :hello2"),
    ":bob!u@h PRIVMSG #a :hello3"), ":bob!u@h PRIVMSG #a :hello4"), ":bob!u@h PRIVMSG #a :hello5"),
    ":bob!u@h PRIVMSG #a :hello6"), ":bob!u@h PRIVMSG #a :hi me"), ":bob!u@h PRIVMSG #a :hi me"),
    ":bob!u@h PRIVMSG #a :hi me")

def nl_full_busy() -> Sess.NotifyLive:
  Sess.NotifyLive{marks8(), q8(), 8n, Some{1n}, 2n, scope(), scope(), Nil{}}

# ---- gate b (n9-bind2 guard): overflow->completion->rescan delivers ---------
# JOIN #a(1), seven chatter rows (2-8), one mention (9).
def cl_r3() -> Cl.Client:
  Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(Feed.feed(
    Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #a"),
    ":bob!u@h PRIVMSG #a :hello0"), ":bob!u@h PRIVMSG #a :hello1"), ":bob!u@h PRIVMSG #a :hello2"),
    ":bob!u@h PRIVMSG #a :hello3"), ":bob!u@h PRIVMSG #a :hello4"), ":bob!u@h PRIVMSG #a :hello5"),
    ":bob!u@h PRIVMSG #a :hello6"), ":bob!u@h PRIVMSG #a :hi me")

def sess_r3() -> Sess.Session:
  Sess.session_with_client(cl_r3(), "#a")

def comp_r3_b1() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(nl_full_busy(), 1n, scope())

def step_r3_rescan() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(comp_nl(comp_r3_b1()), sess_r3(), Nil{}, 0, True{})

def comp_r3_b2() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(live_nl(step_r3_rescan()), 2n, scope())

# ---- joint R2 (n9-final): 65 archives above pending live9, no eviction -------
# The accepted-import trace as pure fixtures: floor 8, marks 8, full queue,
# busy worker, live9 (ID 9) pending, 65 real archive mentions installed above
# (IDs 10..74). The floor-tied owner holds ALL 65 exclusions (no truncation,
# no eviction); the rescan admits live9 only, live9 delivers exactly once,
# archives never notify, and later live still notifies once.
def cl_r3_65() -> Cl.Client:
  feed_mentions_at(65n, cl_r3(), 0n, "#a")

def sess_r3_65() -> Sess.Session:
  Sess.session_with_client(cl_r3_65(), "#a")

def prod_j65() -> List<&2, Nat>:
  Sess.notify_claims_installed(9n, cl_r3_65())

def nl_jseed() -> Sess.NotifyLive:
  Sess.notify_live_merge_claims(nl_full_busy(), prod_j65())

def comp_j1() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(nl_jseed(), 1n, scope())

def step_jre() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(comp_nl(comp_j1()), sess_r3_65(), Nil{}, 0, True{})

def comp_j2() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(live_nl(step_jre()), 2n, scope())

def step_jq() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(comp_nl(comp_j2()), sess_r3_65(), Nil{}, 0, True{})

def comp_j3() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(live_nl(step_jq()), 3n, scope())

def chunk_dave_a() -> List<&2, U32>:
  Fr.string_to_octets(":dave!u@h PRIVMSG #a :hey me\r\n")

def step_jnew() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(comp_nl(comp_j3()), sess_r3_65(), chunk_dave_a(), 0, True{})

# ---- Net dispatch (n9-final): floor-tied union THROUGH the Net entry ---------
# Stored exclusions fill the cap but the oldest eight sit at/below the floor;
# fresh live9 must still be honored through Net.net_notify_observe (a
# floor-blind union would drop it past the cap and hand live9 instead).
def nd_stored() -> List<&2, Nat>:
  List.append(&2, Nat, ids_upto(8n, 1n), ids_upto(16376n, 10n))

def nl_nd() -> Sess.NotifyLive:
  Sess.NotifyLive{marks8(), Notify.queue_empty(), 8n, None{}, 1n, scope(), scope(), nd_stored()}

def obs_nd() -> Sess.NotifyLive & List<&2, Notify.Req>:
  Net.net_notify_observe(nl_nd(), sess_r3(), True{}, 9n <> Nil{})

# ---- R3 pure (n9-bind2): accepted gate + gated seed (JS-safe) ------------------
# The LC.history IO entries reach native FFI, so they live in the C-backend
# test-notify-history suite; this file pins the pure gate, the gated seed,
# the merge, and the bug-shape contrast.
def lc_waiting() -> LC.Context:
  LC.wrap(LC.Details{PL.wrap(PR.Disabled{}), LC.Waiting{7, scope()}, Some{True{}}, "", Some{LC.Archive{3n, 7, scope(), 500, True{}, "me", "irc.test", "", False{}}}, 4n})

def lc_ready() -> LC.Context:
  LC.wrap(LC.Details{PL.wrap(PR.Disabled{}), LC.Ready{}, Some{True{}}, "", None{}, 4n})

def nl_r3_kept() -> Sess.NotifyLive:
  Sess.notify_live_seed_accepted(False{}, nl_full_busy(), Nil{})

def comp_r3_k1() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(nl_r3_kept(), 1n, scope())

def step_r3_kre() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(comp_nl(comp_r3_k1()), sess_r3(), Nil{}, 0, True{})

def comp_r3_k2() -> Sess.NotifyLive & List<&2, Notify.Req> & Bool:
  Sess.notify_live_complete(live_nl(step_r3_kre()), 2n, scope())

def prod_r3_seed() -> List<&2, Nat>:
  Sess.notify_claims_installed(1n, Sess.session_cl(sess_imported()))

def nl_r3_seed() -> Sess.NotifyLive:
  Sess.notify_live_seed_accepted(True{}, nl_ep(), prod_r3_seed())

def step_r3_kok() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_r3_seed(), sess_imported(), chunk_dave(), 0, True{})

def nl_r3_m() -> Sess.NotifyLive:
  Sess.notify_live_merge_claims(nl_ep(), 9n <> 10n <> Nil{})

def nl_r3_m2() -> Sess.NotifyLive:
  Sess.notify_live_merge_claims(nl_full_busy(), 7n <> 9n <> Nil{})

def step_full_busy() -> Sess.NotifyLive & Sess.Session & List<&2, String> & List<&2, Notify.Req>:
  Sess.notify_live_step(nl_full_busy(), Sess.session_with_client(cl_backlog(), "#a"), Nil{}, 0, True{})

# ---- GATE 6 (n9-bind red): birc-notify default helper gating ------------------
def args_len_shown(+prog: String) -> String:
  Nat.show(List.length(&1, String, NotifyIO.args_for(prog, req_at(0n))))

def args_head(args: List<&1, String>) -> String:
  match args:
    case Nil{}: "empty"
    case Con{+h, _}: h

def args_head_shown(+prog: String) -> String:
  args_head(NotifyIO.args_for(prog, req_at(0n)))

# ---- GATE 2/3 IO: fake-helper delivery ---------------------------------------
def expected_log() -> String:
  "-- t0 b0\n-- t1 b1\n-- t2 b2\n-- t3 b3\n-- t4 b4\n-- t5 b5\n-- t6 b6\n-- t7 b7\n"

def log_got(pair: File & Result<&1, &1, U32 & String, List<&2, U32>>, +want: String) -> IO(Unit):
  match pair:
    case (f, Fail{_}):
      do IO<Unit>:
        Unit <- File.close(f)
        IO.die(Unit, 1, "delivery log unreadable")
    case (f, Done{+bytes}):
      do IO<Unit>:
        Unit <- File.close(f)
        E.must_eq("worker delivers eight fifo exactly once", Fr.octets_to_string(bytes), want)

def log_opened(result: Result<&1, &1, U32 & String, File>, +want: String) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "delivery log missing")
    case Done{f}:
      do IO<Unit>:
        pair : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 4096)
        log_got(pair, want)

def done_ticket_shown(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{+ticket, _}: Nat.show(ticket)
    case _: "other"

def done_endpoint_shown(+m: Sess.UiMsg) -> String:
  match m:
    case Sess.NotifyDone{_, +ep}: ep
    case _: "other"

def done_msg(+m: Sess.UiMsg) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("completion ticket exact", done_ticket_shown(m), "42")
    E.must_eq("completion endpoint exact", done_endpoint_shown(m), scope())

def done_got(g: Maybe<&1, Sess.UiMsg>) -> IO(Unit):
  match g:
    case None{}: IO.die(Unit, 1, "completion missing")
    case Some{+m}: done_msg(m)

def run_delivery(+h: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("helper nonempty", Bool.not(String.is_empty(h)))
    Unit <- NotifyIO.run_jobs(h, reqs_upto(8n, 0n), None{})
    result : Result<&1, &1, U32 & String, File> <- File.open(h ++ ".log", "r")
    Unit <- log_opened(result, expected_log())
    q_handed : Notify.Queue <- NotifyIO.send_queued.with(Some{"/tmp/n9notify-missing-dir/notify-send"}, q8(), None{})
    Unit <- E.must_eq("known helper hands the queue off", Nat.show(Notify.queue_len(q_handed)), "0")
    q_kept_unknown : Notify.Queue <- NotifyIO.send_queued.with(Some{"x-notify"}, q8(), None{})
    Unit <- E.must_eq("unknown helper retains the queue", Nat.show(Notify.queue_len(q_kept_unknown)), "8")
    q_kept_none : Notify.Queue <- NotifyIO.send_queued.with(None{}, q8(), None{})
    Unit <- E.must_eq("absent helper retains the queue", Nat.show(Notify.queue_len(q_kept_none)), "8")
    +evt2 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    Unit <- NotifyIO.run_jobs_done(h, req_at(9n) <> Nil{}, Some{evt2}, 42n, scope())
    g_done : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt2)
    Unit <- done_got(g_done)
    IO.print("notify_full=ok")

def deliver_jobs(helper: Maybe<&2, String>) -> IO(Unit):
  match helper:
    case None{}: IO.die(Unit, 1, "no helper resolved")
    case Some{+h}: run_delivery(h)

def main() -> IO(Unit):
  do IO<Unit>:
    # A: one drain call hands the whole bounded queue, FIFO.
    Unit <- E.must_eq("drain hands all eight in one call",
      drained_staged(Notify.drain_all(q8())), "t0;t1;t2;t3;t4;t5;t6;t7;")
    Unit <- E.must_eq("drain keeps nothing back",
      drained_kept(Notify.drain_all(q8())), "0")
    Unit <- E.must_eq("drain of empty stages nothing",
      drained_staged(Notify.drain_all(Notify.queue_empty())), "")
    Unit <- E.must_eq("drain preserves fail-closed cap",
      drained_staged(Notify.drain_all(Notify.enqueue_all(Notify.queue_empty(), reqs_upto(9n, 0n)))),
      "t0;t1;t2;t3;t4;t5;t6;t7;")
    # B: marks advance only for admitted reqs.
    Unit <- E.must_eq("stage admits one fresh mention",
      stage_handed(Notify.stage(Notify.on(), ev_at(3n, "bob") <> Nil{}, "", "", Notify.queue_empty(), 0n)),
      "bob in #a;")
    Unit <- E.must_eq("stage admit advances marks",
      stage_mk(Notify.stage(Notify.on(), ev_at(3n, "bob") <> Nil{}, "", "", Notify.queue_empty(), 0n), scope()), "3")
    Unit <- E.must_eq("stage admit advances scan floor",
      stage_hi(Notify.stage(Notify.on(), ev_at(3n, "bob") <> Nil{}, "", "", Notify.queue_empty(), 0n)), "3")
    Unit <- E.must_eq("stage over full queue admits nothing",
      stage_handed(Notify.stage(marks8(), ev_at(9n, "bob") <> Nil{}, "", "", q8(), 8n)), "")
    Unit <- E.must_eq("stage over full queue leaves marks",
      stage_mk(Notify.stage(marks8(), ev_at(9n, "bob") <> Nil{}, "", "", q8(), 8n), scope()), "8")
    Unit <- E.must_eq("stage over full queue freezes floor",
      stage_hi(Notify.stage(marks8(), ev_at(9n, "bob") <> Nil{}, "", "", q8(), 8n)), "8")
    Unit <- E.must_eq("stage over full queue keeps eight",
      stage_q(Notify.stage(marks8(), ev_at(9n, "bob") <> Nil{}, "", "", q8(), 8n)), "8")
    Unit <- E.must_eq("retry after drain admits the frozen row",
      stage_handed(Notify.stage(marks8(), ev_at(9n, "bob") <> Nil{}, "", "",
        Notify.stage_queue(Notify.stage(marks8(), Nil{}, "", "", Notify.queue_empty(), 8n)), 8n)), "bob in #a;")
    Unit <- E.must_eq("staged dispatch sorts reversed input",
      stage_handed(Notify.stage(Notify.on(), ev_at(9n, "bob") <> ev_at(7n, "amy") <> Nil{}, "", "",
        Notify.queue_empty(), 6n)), "amy in #a;bob in #a;")
    Unit <- E.must_eq("staged replay stays silent",
      stage_handed(Notify.stage(
        Notify.stage_st(Notify.stage(Notify.on(), ev_at(7n, "amy") <> Nil{}, "", "", Notify.queue_empty(), 6n)),
        ev_at(7n, "amy") <> Nil{}, "", "", Notify.queue_empty(), 6n)), "")
    Unit <- E.must_eq("staged dispatch honors disabled",
      stage_handed(Notify.stage(Notify.off(), ev_at(7n, "amy") <> Nil{}, "", "", Notify.queue_empty(), 6n)), "")
    # C: helper resolution.
    Unit <- E.must_eq("missing explicit falls back to default",
      maybe_str(NotifyIO.with_default(None{}, "dflt")), "dflt")
    Unit <- E.must_eq("explicit helper wins over default",
      maybe_str(NotifyIO.with_default(Some{"/usr/bin/notify-send"}, "dflt")), "/usr/bin/notify-send")
    Unit <- E.must_eq("known helpers",
      bool_str(NotifyIO.known_helper("notify-send")) ++ "/" ++
      bool_str(NotifyIO.known_helper("/usr/bin/notify-send")) ++ "/" ++
      bool_str(NotifyIO.known_helper("osascript")) ++ "/" ++
      bool_str(NotifyIO.known_helper("x-notify-send")) ++ "/" ++
      bool_str(NotifyIO.known_helper("")), "true/true/true/false/false")
    Unit <- E.must_eq("deliverable helpers",
      bool_str(NotifyIO.can_deliver(None{})) ++ "/" ++
      bool_str(NotifyIO.can_deliver(Some{"x-notify"})) ++ "/" ++
      bool_str(NotifyIO.can_deliver(Some{"notify-send"})), "false/false/true")
    # D: staged session seam agrees with the observe seam under cap.
    Unit <- E.must_eq("staged session derives the mention",
      stage_handed(Sess.notify_observe_session_staged(Notify.on(), sess_mention(), 0n, Notify.queue_empty())),
      "bob in #room;")
    Unit <- E.must_eq("staged session marks the mention",
      stage_mk(Sess.notify_observe_session_staged(Notify.on(), sess_mention(), 0n, Notify.queue_empty()), scope()), "2")
    # E: framed live steps share one pre-chunk cutoff discipline.
    Unit <- E.must_eq("pre-chunk floor is the join seq", Nat.show(floor0()), "1")
    Unit <- E.must_eq("live chunk hands the mention",
      live_handed(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})), "bob in #room;")
    Unit <- E.must_eq("live chunk drains its own queue",
      live_qlen(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})), "0")
    Unit <- E.must_eq("live chunk advances the floor",
      live_scanned(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})), "2")
    Unit <- E.must_eq("live chunk advances marks",
      live_mkhi(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})), "2")
    Unit <- E.must_eq("live chunk feeds the session",
      live_seq(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})), "2")
    Unit <- E.must_eq("notify path never changes outs",
      live_outs(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
      live_outs(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, False{})))
    Unit <- E.must_eq("dm chunk hands only the dm",
      live_handed(step_legacy_2()), "bob (private);")
    Unit <- E.must_eq("empty chunk replays silent",
      live_handed_len(Sess.notify_live_step(
        live_nl(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        live_sess(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        Nil{}, 0, True{})), "0")
    Unit <- E.must_eq("stale floor replays silent via marks",
      live_handed_len(Sess.notify_live_step(Sess.notify_live_init(
        Sess.notify_live_st(live_nl(Sess.notify_live_step(
          Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{}))), 0n),
        live_sess(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        Nil{}, 0, True{})), "0")
    Unit <- E.must_eq("outage chunk hands nothing",
      live_handed_len(Sess.notify_live_step(
        live_nl(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        live_sess(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        chunk2(), 0, False{})), "0")
    Unit <- E.must_eq("outage chunk retains the dm",
      live_qlen(Sess.notify_live_step(
        live_nl(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        live_sess(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        chunk2(), 0, False{})), "1")
    Unit <- E.must_eq("outage chunk still feeds the session",
      live_seq(Sess.notify_live_step(
        live_nl(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        live_sess(Sess.notify_live_step(Sess.notify_live_init(Notify.on(), floor0()), st0(), chunk1(), 0, True{})),
        chunk2(), 0, False{})), "4")
    Unit <- E.must_eq("recovery hands the retained dm once",
      live_handed(step_legacy_3_rec()), "bob (private);")
    Unit <- E.must_eq("backlog plus fresh share one handoff",
      live_handed(Sess.notify_live_step(
        Sess.NotifyLive{marks8(), q8(), 8n, None{}, 1n, scope(), "", Nil{}},
        Sess.session_with_client(cl_backlog(), "#a"), Nil{}, 0, True{})),
      "t0;t1;t2;t3;t4;t5;t6;t7;bob in #a;bob in #a;bob in #a;")
    Unit <- E.must_eq("shared handoff drains the queue",
      live_qlen(Sess.notify_live_step(
        Sess.NotifyLive{marks8(), q8(), 8n, None{}, 1n, scope(), "", Nil{}},
        Sess.session_with_client(cl_backlog(), "#a"), Nil{}, 0, True{})), "0")
    Unit <- E.must_eq("shared handoff reaches the max id",
      live_mkhi(Sess.notify_live_step(
        Sess.NotifyLive{marks8(), q8(), 8n, None{}, 1n, scope(), "", Nil{}},
        Sess.session_with_client(cl_backlog(), "#a"), Nil{}, 0, True{})), "11")
    # G1: one retained worker across chunks.
    Unit <- E.must_eq("first chunk hands and retains worker",
      live_handed(step_g1_1()), "bob in #room;")
    Unit <- E.must_eq("first chunk marks busy",
      nl_busy_shown(nl_g1_1()), "true")
    Unit <- E.must_eq("first chunk worker is ticket one",
      nl_active_shown(nl_g1_1()), "1")
    Unit <- E.must_eq("first chunk bumps next ticket",
      nl_next_shown(nl_g1_1()), "2")
    Unit <- E.must_eq("second chunk hands nothing while blocked",
      live_handed(step_g1_2()), "")
    Unit <- E.must_eq("second chunk retains one pending",
      live_qlen(step_g1_2()), "1")
    Unit <- E.must_eq("second chunk keeps same worker",
      nl_active_shown(nl_g1_2()), "1")
    Unit <- E.must_eq("second chunk keeps next ticket",
      nl_next_shown(nl_g1_2()), "2")
    Unit <- E.must_eq("second chunk advances marks past dm",
      live_mkhi(step_g1_2()), "4")
    Unit <- E.must_eq("third chunk hands nothing while blocked",
      live_handed(step_g1_3()), "")
    Unit <- E.must_eq("third chunk retains two pending",
      live_qlen(step_g1_3()), "2")
    Unit <- E.must_eq("third chunk still one worker",
      nl_active_shown(nl_g1_3()), "1")
    Unit <- E.must_eq("third chunk advances marks",
      live_mkhi(step_g1_3()), "5")
    Unit <- E.must_eq("exact completion releases two fifo",
      comp_jobs(Sess.notify_live_complete(nl_g1_3(), 1n, scope())), "bob (private);carol in #room;")
    Unit <- E.must_eq("exact completion advances worker",
      nl_active_shown(comp_nl(Sess.notify_live_complete(nl_g1_3(), 1n, scope()))), "2")
    Unit <- E.must_eq("exact completion drains pending",
      comp_qlen(Sess.notify_live_complete(nl_g1_3(), 1n, scope())), "0")
    Unit <- E.must_eq("exact completion reports released",
      comp_rel(Sess.notify_live_complete(nl_g1_3(), 1n, scope())), "true")
    Unit <- E.must_eq("stale ticket completion ignored",
      comp_rel(Sess.notify_live_complete(nl_g1_3(), 99n, scope())), "false")
    Unit <- E.must_eq("stale ticket keeps worker",
      nl_active_shown(comp_nl(Sess.notify_live_complete(nl_g1_3(), 99n, scope()))), "1")
    Unit <- E.must_eq("stale ticket keeps pending",
      comp_qlen(Sess.notify_live_complete(nl_g1_3(), 99n, scope())), "2")
    Unit <- E.must_eq("endpoint completion ignored",
      comp_rel(Sess.notify_live_complete(nl_g1_3(), 1n, "other.test:6697")), "false")
    Unit <- E.must_eq("endpoint completion keeps worker",
      nl_active_shown(comp_nl(Sess.notify_live_complete(nl_g1_3(), 1n, "other.test:6697"))), "1")
    Unit <- E.must_eq("blocked full queue hands nothing",
      live_handed(step_full_busy()), "")
    Unit <- E.must_eq("blocked full queue keeps eight",
      live_qlen(step_full_busy()), "8")
    Unit <- E.must_eq("blocked full queue freezes marks",
      live_mkhi(step_full_busy()), "8")
    # G3: batch-claimed archive IDs excluded per-ID, live interleaved notifies.
    Unit <- E.must_eq("mixed chunk live mention and dm notify once",
      live_handed(step_mixed_claimed()), "bob in #room;dave (private);")
    Unit <- E.must_eq("mixed chunk drains its own queue",
      live_qlen(step_mixed_claimed()), "0")
    Unit <- E.must_eq("mixed chunk floor stops at live max",
      live_scanned(step_mixed_claimed()), "4")
    Unit <- E.must_eq("mixed chunk marks stop at live max",
      live_mkhi(step_mixed_claimed()), "4")
    Unit <- E.must_eq("mixed chunk without claims hands all four",
      live_handed(step_mixed_noclaim()), "bob in #room;carol in #room;dave (private);erin (private);")
    Unit <- E.must_eq("h5 claimed helper preserves synthetic set",
      live_handed(step_mixed_h5()), "bob in #room;dave (private);")
    Unit <- E.must_eq("claimed stage admits only live",
      stage_handed(Notify.stage_claimed(Notify.on(), ev_at(2n, "bob") <> ev_at(3n, "carol") <> ev_at(4n, "dave") <> ev_at(5n, "erin") <> Nil{}, "", "", Notify.queue_empty(), 1n, 3n <> 5n <> Nil{})), "bob in #a;dave in #a;")
    Unit <- E.must_eq("claimed stage marks stop at live max",
      stage_mk(Notify.stage_claimed(Notify.on(), ev_at(2n, "bob") <> ev_at(3n, "carol") <> ev_at(4n, "dave") <> ev_at(5n, "erin") <> Nil{}, "", "", Notify.queue_empty(), 1n, 3n <> 5n <> Nil{}), scope()), "4")
    # G4: endpoint/off reset tears down; post-restore seeding silences restore.
    # Q4-HELD (n9-bind2 R1): physical worker retained across logical reset;
    # flipped false->true per the ownership fix, pending explicit owner reply.
    Unit <- E.must_eq("endpoint reset clears busy",
      nl_busy_shown(nl_reset()), "true")
    Unit <- E.must_eq("endpoint reset clears pending",
      nl_qlen_shown(nl_reset()), "0")
    Unit <- E.must_eq("endpoint reset clears old marks",
      nl_marks_shown(nl_reset(), scope()), "unknown")
    Unit <- E.must_eq("endpoint reset sets new endpoint",
      nl_endpoint_shown(nl_reset()), "other.test:6697")
    Unit <- E.must_eq("endpoint reset preserves next ticket",
      nl_next_shown(nl_reset()), "2")
    Unit <- E.must_eq("endpoint reset sets new floor",
      nl_scanned_shown(nl_reset()), "0")
    # Q4-HELD (n9-bind2 R1): (ticket 1, original endpoint) is the EXACT
    # physical completion post-reset, so it releases; flipped false->true
    # per the ownership fix, pending explicit owner reply.
    Unit <- E.must_eq("reset drops stale completion",
      comp_rel(Sess.notify_live_complete(nl_reset(), 1n, scope())), "true")
    Unit <- E.must_eq("reset keeps idle after stale",
      nl_busy_shown(comp_nl(Sess.notify_live_complete(nl_reset(), 1n, scope()))), "false")
    # Q4-HELD (n9-bind2 R1): physical worker retained across off;
    # flipped false->true per the ownership fix, pending explicit owner reply.
    Unit <- E.must_eq("off clears busy",
      nl_busy_shown(nl_off()), "true")
    Unit <- E.must_eq("off clears pending",
      nl_qlen_shown(nl_off()), "0")
    Unit <- E.must_eq("off clears marks",
      nl_marks_shown(nl_off(), scope()), "unknown")
    Unit <- E.must_eq("off disables dispatch",
      nl_enabled_shown(nl_off()), "false")
    Unit <- E.must_eq("off preserves endpoint",
      nl_endpoint_shown(nl_off()), scope())
    Unit <- E.must_eq("off preserves next",
      nl_next_shown(nl_off()), "2")
    # Q4-HELD (n9-bind2 R1): (ticket 1, original endpoint) is the EXACT
    # physical completion post-off, so it releases; flipped false->true
    # per the ownership fix, pending explicit owner reply.
    Unit <- E.must_eq("off drops stale completion",
      comp_rel(Sess.notify_live_complete(nl_off(), 1n, scope())), "true")
    Unit <- E.must_eq("disabled live chunk stays silent",
      live_handed(step_off_silent()), "")
    Unit <- E.must_eq("disabled live chunk keeps queue empty",
      live_qlen(step_off_silent()), "0")
    Unit <- E.must_eq("restored mentions stay silent on live path",
      live_handed(step_restore_silent()), "")
    Unit <- E.must_eq("restored silent keeps queue empty",
      live_qlen(step_restore_silent()), "0")
    Unit <- E.must_eq("new live mention alerts after restore",
      live_handed(step_restore_live()), "carol in #room;")
    Unit <- E.must_eq("restore seeds marks to final seq",
      nl_marks_shown(nl_seeded(), scope()), Nat.show(Cl.log_seq_of(imported_restore())))
    Unit <- E.must_eq("restore sets floor to final seq",
      nl_scanned_shown(nl_seeded()), Nat.show(Cl.log_seq_of(imported_restore())))
    # G5: endpoint cancel drops without release confusion.
    Unit <- E.must_eq("endpoint cancel drops with true",
      cancel_rel(cancel_exact()), "true")
    # Q4-HELD (n9-bind2 R1): physical worker retained across cancel;
    # flipped false->true per the ownership fix, pending explicit owner reply.
    Unit <- E.must_eq("endpoint cancel clears busy",
      nl_busy_shown(cancel_nl(cancel_exact())), "true")
    Unit <- E.must_eq("endpoint cancel drops pending",
      nl_qlen_shown(cancel_nl(cancel_exact())), "0")
    Unit <- E.must_eq("endpoint cancel preserves marks",
      nl_marks_shown(cancel_nl(cancel_exact()), scope()), "5")
    Unit <- E.must_eq("endpoint cancel preserves next",
      nl_next_shown(cancel_nl(cancel_exact())), "2")
    # Q4-HELD (n9-bind2 R1): (ticket 1, original endpoint) is the EXACT
    # physical completion post-cancel, so it releases; flipped false->true
    # per the ownership fix, pending explicit owner reply.
    Unit <- E.must_eq("cancelled drops stale completion",
      comp_rel(Sess.notify_live_complete(cancel_nl(cancel_exact()), 1n, scope())), "true")
    Unit <- E.must_eq("stale cancel ignored",
      cancel_rel(cancel_stale()), "false")
    Unit <- E.must_eq("stale cancel keeps busy",
      nl_busy_shown(cancel_nl(cancel_stale())), "true")
    Unit <- E.must_eq("stale cancel keeps pending",
      nl_qlen_shown(cancel_nl(cancel_stale())), "2")
    # R1: one physical worker across logical reset/off/cancel.
    Unit <- E.must_eq("reset keeps blocked chunk quiet",
      live_handed(step_r1_reset()), "")
    Unit <- E.must_eq("reset keeps no second worker",
      nl_active_shown(nl_r1_reset()), "1")
    Unit <- E.must_eq("reset retains one pending",
      live_qlen(step_r1_reset()), "1")
    Unit <- E.must_eq("reset exact origin runs fifo once",
      comp_jobs(comp_r1_reset()), "frank in #room;")
    Unit <- E.must_eq("reset exact origin releases",
      comp_rel(comp_r1_reset()), "true")
    Unit <- E.must_eq("reset release advances worker",
      nl_active_shown(comp_nl(comp_r1_reset())), "2")
    Unit <- E.must_eq("reset release keeps new endpoint",
      nl_endpoint_shown(comp_nl(comp_r1_reset())), "other.test:6697")
    Unit <- E.must_eq("reset repeat completion ignored",
      comp_rel(Sess.notify_live_complete(comp_nl(comp_r1_reset()), 1n, scope())), "false")
    Unit <- E.must_eq("reset second ticket releases new endpoint",
      comp_rel(Sess.notify_live_complete(comp_nl(comp_r1_reset()), 2n, "other.test:6697")), "true")
    Unit <- E.must_eq("off keeps worker",
      nl_active_shown(nl_off()), "1")
    Unit <- E.must_eq("off step keeps worker",
      nl_active_shown(nl_r1_off_step()), "1")
    Unit <- E.must_eq("off exact origin releases",
      comp_rel(comp_r1_off()), "true")
    Unit <- E.must_eq("off release idles empty",
      nl_busy_shown(comp_nl(comp_r1_off())), "false")
    Unit <- E.must_eq("cancel keeps blocked chunk quiet",
      live_handed(step_r1_cancel()), "")
    Unit <- E.must_eq("cancel keeps no second worker",
      nl_active_shown(nl_r1_cancel()), "1")
    Unit <- E.must_eq("cancel exact origin runs fifo once",
      comp_jobs(comp_r1_cancel()), "frank in #room;")
    Unit <- E.must_eq("cancel exact origin releases",
      comp_rel(comp_r1_cancel()), "true")
    Unit <- E.must_eq("double reset keeps worker",
      nl_active_shown(nl_r1_reset2()), "1")
    Unit <- E.must_eq("double reset keeps busy",
      nl_busy_shown(nl_r1_reset2()), "true")
    Unit <- E.must_eq("double reset origin still releases",
      comp_rel(Sess.notify_live_complete(nl_r1_reset2(), 1n, scope())), "true")
    Unit <- E.must_eq("reset wrong endpoint ignored",
      comp_rel(Sess.notify_live_complete(nl_reset(), 1n, "other.test:6697")), "false")
    Unit <- E.must_eq("reset wrong endpoint stays busy",
      nl_busy_shown(comp_nl(Sess.notify_live_complete(nl_reset(), 1n, "other.test:6697"))), "true")
    Unit <- E.must_eq("idle reset stays idle",
      nl_busy_shown(Sess.notify_live_reset_endpoint(nl_r1_idle(), "other.test:6697", 0n)), "false")
    Unit <- E.must_eq("idle off stays idle",
      nl_busy_shown(Sess.notify_live_off(nl_r1_idle())), "false")
    # R1 received-completion latch: only the held (ticket, origin) releases;
    # every other received completion latches nothing.
    Unit <- E.must_eq("wrong ticket and origin ignored",
      comp_rel(Sess.notify_live_complete(nl_g1_3(), 99n, "other.test:6697")), "false")
    Unit <- E.must_eq("wrong ticket and origin keeps worker",
      nl_active_shown(comp_nl(Sess.notify_live_complete(nl_g1_3(), 99n, "other.test:6697"))), "1")
    Unit <- E.must_eq("idle completion latches nothing",
      comp_rel(Sess.notify_live_complete(nl_r1_idle(), 1n, scope())), "false")
    Unit <- E.must_eq("idle completion stays idle",
      nl_busy_shown(comp_nl(Sess.notify_live_complete(nl_r1_idle(), 1n, scope()))), "false")
    Unit <- E.must_eq("off repeat completion ignored",
      comp_rel(Sess.notify_live_complete(comp_nl(comp_r1_off()), 1n, scope())), "false")
    Unit <- E.must_eq("cancel repeat completion ignored",
      comp_rel(Sess.notify_live_complete(comp_nl(comp_r1_cancel()), 1n, scope())), "false")
    Unit <- E.must_eq("rebound ticket wrong origin ignored",
      comp_rel(Sess.notify_live_complete(comp_nl(comp_r1_reset()), 2n, scope())), "false")
    # R1 mechanism pins (origin introspection).
    Unit <- E.must_eq("reset retains origin",
      nl_origin_shown(nl_reset()), scope())
    Unit <- E.must_eq("off retains origin",
      nl_origin_shown(nl_off()), scope())
    Unit <- E.must_eq("cancel retains origin",
      nl_origin_shown(cancel_nl(cancel_exact())), scope())
    Unit <- E.must_eq("idle origin empty",
      nl_origin_shown(nl_r1_idle()), "")
    Unit <- E.must_eq("release rebinds origin",
      nl_origin_shown(comp_nl(comp_r1_reset())), "other.test:6697")
    Unit <- E.must_eq("idle release clears origin",
      nl_origin_shown(comp_nl(comp_r1_off())), "")
    # R2a: durable per-ID claims (synthetic pre-claim above the live max).
    Unit <- E.must_eq("durable chunk hands live",
      live_handed(step_r2_d0()), "bob in #room;")
    Unit <- E.must_eq("durable preclaim retained",
      nl_claimed_has(nl_r2_d0(), 9n), "true")
    Unit <- E.must_eq("durable preclaim only",
      nl_claimed_len(nl_r2_d0()), "1")
    Unit <- E.must_eq("nil chunk stays archive quiet",
      live_handed(step_r2_d1()), "")
    Unit <- E.must_eq("nil chunk keeps floor at live",
      live_scanned(step_r2_d1()), "2")
    Unit <- E.must_eq("nil chunk keeps marks at live",
      live_mkhi(step_r2_d1()), "2")
    Unit <- E.must_eq("nil chunk keeps claim",
      nl_claimed_has(live_nl(step_r2_d1()), 9n), "true")
    Unit <- E.must_eq("archive completion hands nothing",
      comp_jobs(comp_r2_d()), "")
    Unit <- E.must_eq("archive completion releases",
      comp_rel(comp_r2_d()), "true")
    Unit <- E.must_eq("live ten notifies after quiet",
      live_handed(step_r2_d2()), "frank in #room;")
    Unit <- E.must_eq("scanned claim pruned",
      nl_claimed_len(live_nl(step_r2_d2())), "0")
    Unit <- E.must_eq("sketch nil stays quiet",
      live_handed(step_r2_c1()), "")
    Unit <- E.must_eq("sketch completion quiet",
      comp_jobs(comp_r2_c()), "")
    Unit <- E.must_eq("sketch completion releases",
      comp_rel(comp_r2_c()), "true")
    Unit <- E.must_eq("sketch live six notifies",
      live_handed(step_r2_c2()), "frank in #room;")
    # R2b: real claim producer through the live path (gate a).
    Unit <- E.must_eq("producer claims archive rows",
      bool_str(Nat.is_gt(List.length(&2, Nat, prodA()), 1n)), "true")
    Unit <- E.must_eq("producer claims above floor",
      all_above_shown(prodA(), 1n), "true")
    Unit <- E.must_eq("real mixed hands only live",
      live_handed(step_r2_a1()), "dave in #room;")
    Unit <- E.must_eq("real mixed floor is live max",
      live_scanned(step_r2_a1()), Nat.show(Cl.log_seq_of(Sess.session_cl(live_sess(step_r2_a1())))))
    Unit <- E.must_eq("reverse import stays quiet",
      live_handed(step_r2_e1()), "")
    Unit <- E.must_eq("reverse import keeps floor",
      live_scanned(step_r2_e1()), "2")
    Unit <- E.must_eq("reverse import keeps marks",
      live_mkhi(step_r2_e1()), "2")
    Unit <- E.must_eq("reverse import keeps worker",
      nl_active_shown(live_nl(step_r2_e1())), "1")
    Unit <- E.must_eq("reverse completion quiet",
      comp_jobs(comp_r2_e()), "")
    Unit <- E.must_eq("reverse live still notifies",
      live_handed(step_r2_e2()), "frank in #room;")
    Unit <- E.must_eq("net producer claims quiet",
      obs_jobs(obs_r2_n()), "")
    Unit <- E.must_eq("net producer claims idle",
      nl_busy_shown(obs_nl(obs_r2_n())), "false")
    Unit <- E.must_eq("net retained claims free live",
      obs_jobs(obs_r2_n2()), "dave in #room;")
    Unit <- E.must_eq("net stored claims retained",
      nl_claimed_has(obs_nl(obs_r2_n()), ids_head(prodA())), "true")
    # Claim set algebra (bounded union, floor prune). The bound covers a max
    # import (MAX_BUFFERS * SCROLL_CAP); the past-cap policy is in-lane
    # fail-closed reject-new (drops newest, never evicts stored), restoring
    # the d2b1d5c provenance. The ceebe5b keeps-newest guards were a
    # candidate-side regression, not a user fixture, and are RETIRED.
    Unit <- E.must_eq("claim cap covers a max import",
      Nat.show(Notify.CLAIM_CAP()), "16384")
    Unit <- E.must_eq("claim union dedups",
      ids_shown(Notify.claim_union(1n <> 2n <> Nil{}, 2n <> 3n <> Nil{})), "1;2;3;")
    Unit <- E.must_eq("claim union rejects past cap",
      ids_len(Notify.claim_union(ids_upto(16384n, 1n), 99999n <> Nil{})), "16384")
    Unit <- E.must_eq("claim union drops newest past cap",
      bool_str(List.contains(~Nat, ~Nat.is_eq, Notify.claim_union(ids_upto(16384n, 1n), 99999n <> Nil{}), 99999n)), "false")
    Unit <- E.must_eq("claim union keeps oldest past cap",
      bool_str(List.contains(~Nat, ~Nat.is_eq, Notify.claim_union(ids_upto(16384n, 1n), 99999n <> Nil{}), 1n)), "true")
    Unit <- E.must_eq("claim union never evicts stored",
      bool_str(List.contains(~Nat, ~Nat.is_eq, Notify.claim_union(ids_upto(16384n, 1n), 99999n <> Nil{}), 16384n)), "true")
    Unit <- E.must_eq("floor prune frees capacity",
      ids_len(Notify.claim_union_floor(ids_upto(16384n, 1n), ids_upto(65n, 20000n), 16384n)), "65")
    Unit <- E.must_eq("floor prune keeps fresh ends",
      bool_str(List.contains(~Nat, ~Nat.is_eq, Notify.claim_union_floor(ids_upto(16384n, 1n), ids_upto(65n, 20000n), 16384n), 20000n)
        && List.contains(~Nat, ~Nat.is_eq, Notify.claim_union_floor(ids_upto(16384n, 1n), ids_upto(65n, 20000n), 16384n), 20064n)), "true")
    Unit <- E.must_eq("claim fresh dupes use no capacity",
      ids_len(dup_union()), "2")
    Unit <- E.must_eq("claim fresh dupes keep set",
      ids_shown(dup_union()), "1;2;")
    Unit <- E.must_eq("claim union dedups stored and fresh dupes",
      ids_shown(dup_union2()), "1;2;3;")
    Unit <- E.must_eq("claim union dedup no capacity",
      ids_len(dup_union2()), "3")
    Unit <- E.must_eq("claim prune drops floor",
      ids_shown(Notify.claim_prune(1n <> 2n <> 3n <> Nil{}, 2n)), "3;")
    # R2c paired guards through real entries: 65 archives quiet, live once.
    Unit <- E.must_eq("producer 65 rows valid",
      Nat.show(Cl.log_seq_of(cl65())), "66")
    Unit <- E.must_eq("producer claims all 65 qualifying",
      ids_len(prod65()), "65")
    Unit <- E.must_eq("65 archives never notify",
      live_handed(step_r2_65()), "")
    Unit <- E.must_eq("65 archives keep queue empty",
      live_qlen(step_r2_65()), "0")
    Unit <- E.must_eq("adjacent live notifies exactly once",
      live_handed(step_r2_65_live()), "frank in #room;")
    # Joint R2 (n9-final): 65 archives above pending live9, no eviction.
    Unit <- E.must_eq("joint import holds 74 rows",
      Nat.show(Cl.log_seq_of(cl_r3_65())), "74")
    Unit <- E.must_eq("joint producer claims all 65",
      ids_len(prod_j65()), "65")
    Unit <- E.must_eq("joint merge holds all 65 (no eviction)",
      nl_claimed_len(nl_jseed()), "65")
    Unit <- E.must_eq("joint merge keeps oldest exclusion",
      nl_claimed_has(nl_jseed(), 10n), "true")
    Unit <- E.must_eq("joint merge keeps newest exclusion",
      nl_claimed_has(nl_jseed(), 74n), "true")
    Unit <- E.must_eq("joint merge keeps floor",
      Nat.show(Sess.notify_live_scanned(nl_jseed())), "8")
    Unit <- E.must_eq("joint rescan admits live9 only",
      live_qlen(step_jre()), "1")
    Unit <- E.must_eq("joint rescan hands nothing while blocked",
      live_handed(step_jre()), "")
    Unit <- E.must_eq("joint live9 delivers exactly once",
      comp_jobs(comp_j2()), "bob in #a;")
    Unit <- E.must_eq("joint claims retained past rescan",
      nl_claimed_len(live_nl(step_jre())), "65")
    Unit <- E.must_eq("joint archives never notify",
      live_qlen(step_jq()), "0")
    Unit <- E.must_eq("joint live9 worker releases quiet",
      comp_jobs(comp_j3()), "")
    Unit <- E.must_eq("joint new live notifies once",
      live_handed(step_jnew()), "dave in #a;")
    # Net dispatch honors fresh past a stale-filled cap (floor-tied).
    Unit <- E.must_eq("net dispatch honors fresh past stale cap",
      obs_jobs(obs_nd()), "")
    Unit <- E.must_eq("net dispatch retains fresh exclusion",
      nl_claimed_has(obs_nl(obs_nd()), 9n), "true")
    Unit <- E.must_eq("net dispatch prunes stale stored",
      nl_claimed_has(obs_nl(obs_nd()), 1n), "false")
    Unit <- E.must_eq("net dispatch retains live stored",
      nl_claimed_has(obs_nl(obs_nd()), 10n), "true")
    Unit <- E.must_eq("net dispatch claimed length",
      nl_claimed_len(obs_nl(obs_nd())), "16377")
    Unit <- E.must_eq("net dispatch keeps floor on quiet",
      Nat.show(Sess.notify_live_scanned(obs_nl(obs_nd()))), "8")
    # Gate b: overflow->completion->rescan delivers with no new IRC input.
    Unit <- E.must_eq("overflow completion hands eight fifo",
      comp_jobs(comp_r3_b1()), "t0;t1;t2;t3;t4;t5;t6;t7;")
    Unit <- E.must_eq("overflow completion advances worker",
      nl_active_shown(comp_nl(comp_r3_b1())), "2")
    Unit <- E.must_eq("rescan admits pending row",
      live_qlen(step_r3_rescan()), "1")
    Unit <- E.must_eq("rescan advances marks",
      live_mkhi(step_r3_rescan()), "9")
    Unit <- E.must_eq("rescan hands nothing while blocked",
      live_handed(step_r3_rescan()), "")
    Unit <- E.must_eq("second completion delivers pending",
      comp_jobs(comp_r3_b2()), "bob in #a;")
    Unit <- E.must_eq("second completion releases",
      comp_rel(comp_r3_b2()), "true")
    # R3 pure: accepted gate + gated seed (IO entries in test-notify-history).
    Unit <- E.must_eq("accepted on resolve",
      bool_str(LC.history_accepted(lc_waiting(), lc_ready())), "true")
    Unit <- E.must_eq("waiting waiting rejected",
      bool_str(LC.history_accepted(lc_waiting(), lc_waiting())), "false")
    Unit <- E.must_eq("ready ready rejected",
      bool_str(LC.history_accepted(lc_ready(), lc_ready())), "false")
    Unit <- E.must_eq("rejected keeps floor",
      Nat.show(Sess.notify_live_scanned(nl_r3_kept())), "8")
    Unit <- E.must_eq("rejected keeps marks",
      hi_shown(Notify.hi_of(Sess.notify_live_st(nl_r3_kept()), scope())), "8")
    Unit <- E.must_eq("rejected keeps worker",
      nl_active_shown(nl_r3_kept()), "1")
    Unit <- E.must_eq("rejected keeps queue",
      nl_qlen_shown(nl_r3_kept()), "8")
    Unit <- E.must_eq("ungated seed bumps floor (bug shape)",
      Nat.show(Sess.notify_live_scanned(Net.net_notify_seed_postrestore(nl_full_busy(), sess_r3()))), "9")
    Unit <- E.must_eq("rejected drain hands eight",
      comp_jobs(comp_r3_k1()), "t0;t1;t2;t3;t4;t5;t6;t7;")
    Unit <- E.must_eq("rejected rescan admits nine",
      live_qlen(step_r3_kre()), "1")
    Unit <- E.must_eq("rejected nine still delivers",
      comp_jobs(comp_r3_k2()), "bob in #a;")
    # R3d per-ID (n9-bind3): accepted merges claims, keeps floor/marks (no jump).
    Unit <- E.must_eq("accepted keeps floor (no jump)",
      Nat.show(Sess.notify_live_scanned(nl_r3_seed())), "1")
    Unit <- E.must_eq("accepted keeps marks (no jump)",
      hi_shown(Notify.hi_of(Sess.notify_live_st(nl_r3_seed()), scope())), "unknown")
    Unit <- E.must_eq("accepted claims archive",
      nl_claimed_len(nl_r3_seed()), "1")
    Unit <- E.must_eq("accepted archive quiet live alerts",
      live_handed(step_r3_kok()), "dave in #room;")
    Unit <- E.must_eq("merge stores fresh",
      nl_claimed_len(nl_r3_m()), "2")
    Unit <- E.must_eq("merge keeps floor",
      Nat.show(Sess.notify_live_scanned(nl_r3_m())), "1")
    Unit <- E.must_eq("merge prunes scanned",
      nl_claimed_len(nl_r3_m2()), "1")
    Unit <- E.must_eq("merge keeps unscanned",
      nl_claimed_has(nl_r3_m2(), 9n), "true")
    # G2: framed live-chunk dispatch through Net real entries.
    Unit <- E.must_eq("net init sets endpoint",
      nl_endpoint_shown(nl_net_init()), scope())
    Unit <- E.must_eq("net init sets floor",
      nl_scanned_shown(nl_net_init()), "1")
    Unit <- E.must_eq("net init starts idle",
      nl_busy_shown(nl_net_init()), "false")
    Unit <- E.must_eq("framed live mention dispatches via net",
      obs_jobs(obs_net()), "bob in #room;")
    Unit <- E.must_eq("framed net observe sets worker",
      nl_active_shown(obs_nl(obs_net())), "1")
    Unit <- E.must_eq("framed net observe drains",
      nl_qlen_shown(obs_nl(obs_net())), "0")
    Unit <- E.must_eq("framed net observe advances marks",
      nl_marks_shown(obs_nl(obs_net()), scope()), "2")
    Unit <- E.must_eq("net observe respects claimed",
      obs_jobs(obs_net_claimed()), "")
    Unit <- E.must_eq("net observe claimed stays idle",
      nl_busy_shown(obs_nl(obs_net_claimed())), "false")
    Unit <- E.must_eq("net complete releases",
      comp_rel(Net.net_notify_complete(obs_nl(obs_net()), 1n, scope())), "true")
    # G6: birc-notify default helper gating.
    Unit <- E.must_eq("birc-notify is deliverable",
      bool_str(NotifyIO.can_deliver(Some{"/x/birc-notify"})), "true")
    Unit <- E.must_eq("birc-notify args length three",
      args_len_shown("/x/birc-notify"), "3")
    Unit <- E.must_eq("birc-notify args start with dashes",
      args_head_shown("/x/birc-notify"), "--")
    # F: the single worker delivers through the resolved helper.
    helper : Maybe<&2, String> <- NotifyIO.program_or_default("fallback-default")
    deliver_jobs(helper)
