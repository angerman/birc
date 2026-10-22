# SPDX-License-Identifier: Apache-2.0
# Session <-> Cards/fullscreen runtime adapter (pure).
#
# ADAPTER BOUNDARY (branch c8/session-adapter, from parent HEAD 910f622):
# threads one bounded Cards queue plus one fullscreen overlay through
# Session dispatch. Parent owns merges; this file is new and disjoint by
# construction. Session is consumed, never modified: every
# Session effect below delegates to Sess.step_keys / Sess.step_enter /
# Sess.step_on_chunk_ms, so control/query/server scoping, reconnect
# dividers, global IDs, unread/alerts, scroll anchors, the 512-byte wire
# cap, and SEND_CAP batching all keep Session's exact semantics.
#
# Wiring contract (C8.5/C8.6):
# - Scheduling consumes bounded visible candidates only
#   (C.visible_candidates: exact panes, rows, mutes, anchors, eligibility,
#   media exclusion). There is no all-buffer scan; settle() after key and
#   chunk steps only closes dead state, never schedules.
# - Text cards need no terminal image protocol, so scheduling has no
#   display gate. Fullscreen reuses the one canonical Media path: only
#   accepted nonzero media tokens open, and every observe/complete/settle
#   plus every paint (see cards_view.bend) re-validates retention,
#   support, generation, and endpoint/source liveness before emitting.
# - The physical cards worker stays owned until its exact completion,
#   even after disable/reset (Cards.take_job / Cards.complete own that
#   policy; this adapter only threads it). Stale results release without
#   storing and never revive prior state.
# - Endpoint transitions call reset_endpoint alongside Session's own
#   media reset: the cards generation bumps (pending/ready drop) and the
#   overlay closes. Returning to an old endpoint never restores either.
# - This adapter never emits wire output, never touches Session media
#   state (so the one unsupported-terminal log line stays Session-owned),
#   and never normalizes URLs: exact chat text flows end to end.
#
# The fullscreen open/close key binding is not wired from the live key
# path (open_full and close_full). Native/PTY qualification stays out of
# scope.
#
# Layout is bottom-up: Bend forbids same-module forward references, so
# every helper precedes its callers and recursion recurs in the match arm.
import Base
import ./buffer.bend as Cl
import ./session.bend as Sess
import ./media.bend as M
import ./cards.bend as C

type AD is Data:
  AD{st: Sess.Session, cards: C.State, full: C.Fullscreen}

def wrap(+st: Sess.Session) -> AD:
  AD{st, C.initial(True{}), C.FullOff{}}

def with_cards(+st: Sess.Session, +cards: C.State, +full: C.Fullscreen) -> AD:
  AD{st, cards, full}

def ad_session(+ad: AD) -> Sess.Session:
  match ad:
    case AD{+st, _, _}: st

def ad_cards(+ad: AD) -> C.State:
  match ad:
    case AD{_, +cards, _}: cards

def ad_full(+ad: AD) -> C.Fullscreen:
  match ad:
    case AD{_, _, +full}: full

def ad_client(+ad: AD) -> Cl.Client:
  match ad:
    case AD{st, _, _}: Sess.session_cl(st)

def ad_pending(+ad: AD) -> Nat:
  match ad:
    case AD{_, cards, _}: C.pending_count(cards)

def ad_ready(+ad: AD) -> Nat:
  match ad:
    case AD{_, cards, _}: C.ready_count(cards)

def ad_open(+ad: AD) -> Bool:
  match ad:
    case AD{_, _, full}: C.is_open(full)

# ---- net gates (mirrors Session's visible-media and worker gates) ----

def schedule_net(net: Sess.NetState) -> Bool:
  match net:
    case Sess.Demo{}: False{}
    case Sess.Stopping{_}: False{}
    case _: True{}

def job_net(net: Sess.NetState) -> Bool:
  match net:
    case Sess.Stopping{_}: False{}
    case _: True{}

# ---- bounded visible scheduling ----

def observe_visible.media(+st: Sess.Session, +cards: C.State, +full: C.Fullscreen, +cl: Cl.Client, +rows: U32, +cols: U32, +media: M.State) -> AD:
  +kept = C.maintain(cards, cl)
  +cands = C.visible_candidates(cl, rows, cols, Sess.session_split(st), media)
  AD{st, C.enqueue_candidates(cands, kept), C.maintain_full(full, media, cl)}

def observe_visible.size(+st: Sess.Session, +cards: C.State, +full: C.Fullscreen, +cl: Cl.Client, size: Sess.Size) -> AD:
  match size:
    case Sess.Size{rows, cols}:
      observe_visible.media(st, cards, full, cl, rows, cols, Sess.session_media(st))

def observe_visible.on(allowed: Bool, +st: Sess.Session, +cards: C.State, +full: C.Fullscreen, +cl: Cl.Client, size: Sess.Size) -> AD:
  match allowed:
    case False{}: AD{st, cards, full}
    case True{}: observe_visible.size(st, cards, full, cl, size)

def observe_visible(+ad: AD) -> AD:
  match ad:
    case AD{+st, +cards, +full}:
      observe_visible.on(schedule_net(Sess.session_net(st)) && C.enabled(cards),
        st, cards, full, Sess.session_cl(st), Sess.session_size(st))

# ---- endpoint/source removal closure (no scheduling here) ----

def settle.go(+st: Sess.Session, +cards: C.State, +full: C.Fullscreen, +cl: Cl.Client, +media: M.State) -> AD:
  AD{st, C.maintain(cards, cl), C.maintain_full(full, media, cl)}

def settle(+ad: AD) -> AD:
  match ad:
    case AD{+st, +cards, +full}:
      settle.go(st, cards, full, Sess.session_cl(st), Sess.session_media(st))

def reset_endpoint(+ad: AD) -> AD:
  match ad:
    case AD{st, cards, full}: AD{st, C.reset(cards), C.close(full)}

def set_enabled.go(+st: Sess.Session, +cards: C.State, +full: C.Fullscreen, on: Bool, +cl: Cl.Client, +media: M.State) -> AD:
  AD{st, C.set_enabled(cards, on), C.maintain_full(full, media, cl)}

def set_enabled(+ad: AD, on: Bool) -> AD:
  match ad:
    case AD{+st, +cards, +full}:
      set_enabled.go(st, cards, full, on, Sess.session_cl(st), Sess.session_media(st))

# ---- worker ownership ----

def job_allowed(+ad: AD) -> Bool:
  match ad:
    case AD{st, _, _}: job_net(Sess.session_net(st))

def take_job.full(+st: Sess.Session, +next: C.State, +full: C.Fullscreen, +job: Maybe<&2, C.Request>, +cl: Cl.Client, +media: M.State) -> AD & Maybe<&2, C.Request>:
  (AD{st, next, C.maintain_full(full, media, cl)}, job)

def take_job.go(pair: C.State & Maybe<&2, C.Request>, +st: Sess.Session, +full: C.Fullscreen) -> AD & Maybe<&2, C.Request>:
  match pair:
    case (next, job): take_job.full(st, next, full, job, Sess.session_cl(st), Sess.session_media(st))

def take_job(+ad: AD) -> AD & Maybe<&2, C.Request>:
  match ad:
    case AD{+st, +cards, +full}:
      take_job.go(C.take_job_allowed(job_net(Sess.session_net(st)), C.maintain(cards, Sess.session_cl(st))), st, full)

# ---- completion admission (stale results release without storing) ----
# Text completions carry no native token, so admission is Cards.accept
# exactly (exact worker identity, enabled generation, live target), with
# no visible-partition gate: a hidden-but-live completion still lands in
# the bounded text cache, exactly like the first fetch.

def accept_result(+ad: AD, +gen: Nat, +ticket: Nat, +url: String) -> Bool:
  match ad:
    case AD{st, cards, _}: C.accept(cards, Sess.session_cl(st), gen, ticket, url)

def complete.go(+st: Sess.Session, +cards: C.State, +full: C.Fullscreen, +gen: Nat, +ticket: Nat, +url: String, +payload: String) -> AD:
  +cl = Sess.session_cl(st)
  +media = Sess.session_media(st)
  AD{st, C.complete(cards, cl, gen, ticket, url, payload), C.maintain_full(full, media, cl)}

def complete(+ad: AD, +gen: Nat, +ticket: Nat, +url: String, +payload: String) -> AD:
  match ad:
    case AD{st, cards, full}: complete.go(st, cards, full, gen, ticket, url, payload)

def reject.go(+st: Sess.Session, +cards: C.State, +full: C.Fullscreen, +gen: Nat, +ticket: Nat, +url: String) -> AD:
  +cl = Sess.session_cl(st)
  +media = Sess.session_media(st)
  AD{st, C.reject(cards, gen, ticket, url), C.maintain_full(full, media, cl)}

def reject(+ad: AD, +gen: Nat, +ticket: Nat, +url: String) -> AD:
  match ad:
    case AD{st, cards, full}: reject.go(st, cards, full, gen, ticket, url)

# ---- fullscreen open/close (explicit intent; parent binds the key) ----

def open_full.go(+st: Sess.Session, +cards: C.State, +media: M.State, +target: M.Target, +url: String) -> AD:
  AD{st, cards, C.open(media, target, url)}

def open_full(+ad: AD, +target: M.Target, +url: String) -> AD:
  match ad:
    case AD{+st, cards, _}: open_full.go(st, cards, Sess.session_media(st), target, url)

def close_full(+ad: AD) -> AD:
  match ad:
    case AD{st, cards, full}: AD{st, cards, C.close(full)}

# ---- Session dispatch wrappers (wire output passes through untouched) ----

def lift_closed(+st: Sess.Session, +cmd: Sess.NetCmd, +halt: Bool, +cards: C.State, +full: C.Fullscreen) -> AD & Sess.NetCmd & Bool:
  (settle(AD{st, cards, full}), cmd, halt)

def step_keys.go(trip: Sess.Session & Sess.NetCmd & Bool, +cards: C.State, +full: C.Fullscreen) -> AD & Sess.NetCmd & Bool:
  match trip:
    case (st, cmd, halt): lift_closed(st, cmd, halt, cards, full)

def step_keys(+ad: AD, +keys: Sess.Keys) -> AD & Sess.NetCmd & Bool:
  match ad:
    case AD{st, cards, full}: step_keys.go(Sess.step_keys(st, keys), cards, full)

def step_enter(+ad: AD, +line: String) -> AD & Sess.NetCmd & Bool:
  match ad:
    case AD{st, cards, full}: step_keys.go(Sess.step_enter(st, line), cards, full)

def step_chunk.go(pair: Sess.Session & List<&2, String>, +cards: C.State, +full: C.Fullscreen) -> AD & List<&2, String>:
  match pair:
    case (st, outs): (settle(AD{st, cards, full}), outs)

def step_chunk(+ad: AD, +chunk: List<&2, U32>, +now_ms: U32) -> AD & List<&2, String>:
  match ad:
    case AD{st, cards, full}: step_chunk.go(Sess.step_on_chunk_ms(st, chunk, now_ms), cards, full)

# ---- law-facing wire preservation checks ----

def wire_cmd_eq(+cmda: Sess.NetCmd, +halt_a: Bool, cmdb: Sess.NetCmd, +halt_b: Bool) -> Bool:
  String.eq(Sess.show_netcmd(cmda), Sess.show_netcmd(cmdb)) && Bool.pick(Bool, halt_a, halt_b, Bool.not(halt_b))

def wire_ok.ad(trip: AD & Sess.NetCmd & Bool, +cmdb: Sess.NetCmd, +haltb: Bool) -> Bool:
  match trip:
    case (_, cmda, halta): wire_cmd_eq(cmda, halta, cmdb, haltb)

def wire_ok.sess(trip: AD & Sess.NetCmd & Bool, plain: Sess.Session & Sess.NetCmd & Bool) -> Bool:
  match plain:
    case (_, cmdb, haltb): wire_ok.ad(trip, cmdb, haltb)

def wire_ok(+live: Sess.Session, +line: String) -> Bool:
  +keys = Sess.keys_of(line, True{}, 0, 0, 0, 0, 0, 0, 0)
  wire_ok.sess(step_keys(wrap(live), keys), Sess.step_keys(live, keys))

def chunk_ok.ad(pair: AD & List<&2, String>, +outsb: List<&2, String>) -> Bool:
  match pair:
    case (_, +outsa): String.eq(String.join(outsa, "|"), String.join(outsb, "|"))

def chunk_ok.outs(pair: AD & List<&2, String>, plain: Sess.Session & List<&2, String>) -> Bool:
  match plain:
    case (_, +outsb): chunk_ok.ad(pair, outsb)

def chunk_ok(+live: Sess.Session, +chunk: List<&2, U32>, +now_ms: U32) -> Bool:
  chunk_ok.outs(step_chunk(wrap(live), chunk, now_ms), Sess.step_on_chunk_ms(live, chunk, now_ms))
