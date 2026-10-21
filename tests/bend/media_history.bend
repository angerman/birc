# SPDX-License-Identifier: Apache-2.0
# Restored/visible chat shares the bounded live media worker, never history IO.
import Base
import ./expect.bend as E
import ./media_terminal.bend as Terminal
import ./media_anchor.bend as Anchor
import ../../src/bend/media.bend as M
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as S
import ../../src/bend/view.bend as V
import ../../src/bend/split.bend as Sp
import ../../src/bend/history.bend as H
import ../../src/bend/history_startup.bend as Startup

def url(id: Nat) -> String:
  "https://offline.invalid/" ++ Nat.show(id) ++ ".png"

def line(+id: Nat) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", url(id), "alice", id}

def lines(n: Nat, +id: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p: line(id) <> lines(p, 1n+id)

def buffer(name: String, rows: List<&2, Cl.Line>) -> Cl.Buffer:
  Cl.buf_indexed(name, True{}, "", rows, Nil{}, Cl.ScrollAt{0n, 0n})

def client() -> Cl.Client:
  Cl.Client{"me", "s", Cl.server_buf() <> buffer("#left", lines(10n, 1n))
    <> buffer("#right", lines(10n, 11n)) <> buffer("#hidden", lines(10n, 100n)) <> Nil{},
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 109n, False{}}

def with_split(st: S.Session, split: Sp.State) -> S.Session:
  match st:
    case S.Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, _, typing, port, media, plan, edits, +iso, +hlbox, +cf, +regbox, +theme, _, +pends}:
      S.Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hlbox, cf, regbox, theme, S.labels0(), pends}

def session(cl: Cl.Client, net: S.NetState, on: Bool) -> S.Session:
  S.session_set_media(S.session_set_size(S.session_set_net(S.session_set_client(S.session0("me", "s", ""), cl), net), 35, 200), M.initial(on))

def selected_ids(xs: List<&2, M.Candidate>) -> String:
  match xs:
    case Nil{}: ""
    case Con{M.Candidate{M.Inline{id}, _}, tail}: Nat.show(id) ++ "|" ++ selected_ids(tail)
    case Con{_, tail}: selected_ids(tail)

def candidates(+st: S.Session) -> List<&2, M.Candidate>:
  V.visible_media_candidates(S.session_cl(st), 35, 200, S.session_split(st), S.session_media(st))

type Drain is Data:
  Drain{st: S.Session, count: Nat}

def drain.count(pair: Drain) -> Drain:
  match pair:
    case Drain{st, count}: Drain{st, 1n+count}

# Mirrors net/wsnet accept=false: plain reject clears the worker and soft-
# defers relaunch. Sticky reject_full is native CAP overflow only
# (ph_cache_admit + below).
def finish(accepted: Bool, +st: S.Session, +gen: Nat, +ticket: Nat, +url: String) -> S.Session:
  match accepted:
    case True{}: S.session_set_media(st, M.complete(S.session_media(st), S.session_cl(st), gen, ticket, url, U32.from_nat(ticket)))
    case False{}: S.session_set_media(st, M.reject(S.session_media(st), gen, ticket, url))

def drain.step.work(+media: M.State, +st: S.Session, k: S.Session -> Drain, got: Maybe<&2, M.Work>) -> Drain:
  match got:
    # SoftFence / StickyFence are never take_job work.
    case None{}: Drain{S.session_set_media(st, media), 0n}
    case Some{M.Work{_, +url, +gen, +ticket}}:
      +active : S.Session = S.session_set_media(st, media)
      drain.count(k(finish(S.session_accept_media_result(active, gen, ticket, url), active, gen, ticket, url)))

def drain.step(pair: M.State & Maybe<&2, M.Request>, +st: S.Session, k: S.Session -> Drain) -> Drain:
  match pair:
    case (media, None{}): Drain{S.session_set_media(st, media), 0n}
    case (media, Some{req}): drain.step.work(media, st, k, M.work_fields(req))

# Real observe/take_job/complete transitions. Fuel catches eviction/refetch loops.
def drain(fuel: Nat, +st: S.Session) -> Drain:
  match fuel:
    case 0n: Drain{st, 0n}
    case 1n+p:
      +next = S.session_observe_visible_media(st)
      drain.step(M.take_job_allowed(S.session_media_job_allowed(next), S.session_media(next)), next, after => drain(p, after))

def count(pair: Drain) -> Nat:
  match pair:
    case Drain{_, n}: n

def result(pair: Drain) -> S.Session:
  match pair:
    case Drain{st, _}: st

def stable(+st: S.Session) -> Bool:
  +next = S.session_observe_visible_media(st)
  Nat.is_eq(M.pending_count(S.session_media(next)), 0n)
    && Bool.not(Terminal.has_job(M.take_job(S.session_media(next))))
    && M.bounded(S.session_media(next))

type SBox is Data:
  SBox{cell: List<&2, S.Session>}

# Singleton-list box: a live Session flattens to dozens of words, so one
# main holding ~10 of them breaches the 247-word native continuation
# limit ("an arity over 247"). Boxing keeps bind captures narrow
# (session_drafts_demo idiom); use sites unbox transiently. The Nil arm
# is unreachable by construction.
def sbox(+st: S.Session) -> SBox:
  SBox{st <> Nil{}}

def sunbox.cell(+cell: List<&2, S.Session>) -> S.Session:
  match cell:
    case Con{+st, _}: st
    case Nil{}: session(client(), S.Online{}, True{})

def sunbox(+b: SBox) -> S.Session:
  match b:
    case SBox{+cell}: sunbox.cell(cell)

def fill(n: Nat, +id: Nat, state: M.State) -> M.State:
  match n:
    case 0n: state
    case 1n+p: fill(p, 1n+id, M.enqueue(state, M.Inline{id}, url(id)))

def restored() -> Cl.Client:
  +current : Cl.Client = Cl.Client{"me", "s", [Cl.server_buf(), buffer("#history", Nil{})],
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 50n, False{}}
  +snapshot : Cl.Client = Cl.Client{"old", "s", [Cl.server_buf(), buffer("#history", [line(1n)])],
    0n, "", Cl.settings0(), Cl.AuthIdle{}, 1n, False{}}
  Startup.install(current, snapshot, "s:6697", "s:6697")

def ready(n: Nat, +id: Nat) -> List<&2, M.MediaReady>:
  match n:
    case 0n: Nil{}
    case 1n+p: M.MediaReady{M.Inline{id}, url(id), U32.from_nat(id)} <> ready(p, 1n+id)

def selected(n: Nat, +id: Nat) -> List<&2, M.Candidate>:
  match n:
    case 0n: Nil{}
    case 1n+p: M.Candidate{M.Inline{id}, url(id)} <> selected(p, 1n+id)

def failed(n: Nat, +id: Nat) -> List<&2, M.MediaReady>:
  match n:
    case 0n: Nil{}
    case 1n+p: M.MediaReady{M.Inline{id}, url(id), 0} <> failed(p, 1n+id)

def manual_client() -> Cl.Client:
  Cl.Client{"me", "s", List.append(&2, Cl.Buffer, Cl.client_bufs(client()),
    [Cl.buf_indexed("*preview*", False{}, "/tmp/synthetic.png", Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})]),
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 109n, False{}}

def prospective.work(+state: M.State, +client: Cl.Client, got: Maybe<&2, M.Work>) -> M.State:
  match got:
    case None{}: state
    case Some{M.Work{_, url, gen, ticket}}: M.complete(state, client, gen, ticket, url, 0)

def prospective(pair: M.State & Maybe<&2, M.Request>, client: Cl.Client) -> M.State:
  match pair:
    case (state, None{}): state
    case (state, Some{req}): prospective.work(state, client, M.work_fields(req))

def token_has(xs: List<&2, U32>, +token: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, tail}: U32.is_eq(h, token) || token_has(tail, token)

# Same-target gen bump that keeps pending (set_supported-enable shape).
def bump_gen_maintain(state: M.State, +cl: Cl.Client) -> M.State:
  match state:
    case M.State{on, gen, ticket, active, pending, ready, display}:
      M.maintain(M.State{on, (1n + gen : Nat), ticket, active, pending, ready, display}, cl)

# Unbounded SoftFence list (old hazard): work count stays 0 while tags grow.
def soft_tags(+n: Nat) -> List<&2, M.Request>:
  match n:
    case 0n: Nil{}
    case 1n+p: M.SoftFence{M.Inline{n}, url(n), n} <> soft_tags(p)

# Many soft declines via reject: each cycle enqueues, takes, SoftFence-defers.
# Helpers take a continuation so soft_flood can recurse without a forward ref.
def soft_flood.work(+state: M.State, got: Maybe<&2, M.Work>, k: M.State -> M.State) -> M.State:
  match got:
    case None{}: state
    case Some{M.Work{_, u, g, t}}: k(M.reject(state, g, t, u))

def soft_flood.job(+state: M.State, got: Maybe<&2, M.Request>, k: M.State -> M.State) -> M.State:
  match got:
    case None{}: state
    case Some{req}: soft_flood.work(state, M.work_fields(req), k)

def soft_flood.taken(pair: M.State & Maybe<&2, M.Request>, k: M.State -> M.State) -> M.State:
  match pair:
    case (st, job): soft_flood.job(st, job, k)

def soft_flood(+n: Nat, state: M.State) -> M.State:
  match n:
    case 0n: state
    case 1n+p: soft_flood.taken(M.take_job(M.enqueue(state, M.Inline{n}, url(n))), next => soft_flood(p, next))

# StickyFence flood via reject_full into CAP-nonzero ready (no ready slot).
def sticky_flood.work(+state: M.State, +cl: Cl.Client, got: Maybe<&2, M.Work>, k: M.State -> M.State) -> M.State:
  match got:
    case None{}: state
    case Some{M.Work{_, u, g, t}}: k(M.reject_full(state, cl, g, t, u))

def sticky_flood.job(+state: M.State, +cl: Cl.Client, got: Maybe<&2, M.Request>, k: M.State -> M.State) -> M.State:
  match got:
    case None{}: state
    case Some{req}: sticky_flood.work(state, cl, M.work_fields(req), k)

def sticky_flood.taken(+cl: Cl.Client, pair: M.State & Maybe<&2, M.Request>, k: M.State -> M.State) -> M.State:
  match pair:
    case (st, job): sticky_flood.job(st, cl, job, k)

def sticky_flood(+n: Nat, state: M.State, +cl: Cl.Client) -> M.State:
  match n:
    case 0n: state
    case 1n+p: sticky_flood.taken(cl, M.take_job(M.enqueue(state, M.Inline{n}, url(n))), next => sticky_flood(p, next, cl))

def admission.url() -> String:
  "https://history-image.test/archived%20a%E2%80%AF.png"

def admission.line(+id: Nat) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "12:00:00", Bool.pick(String, Nat.is_eq(id, 1n),
    "ARCHIVE-IMAGE " ++ admission.url(), "ARCHIVE-" ++ Nat.show(id)), "alice", id}

def admission.lines(n: Nat, +id: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: [Cl.Line{Cl.Reconnect{}, "", "IRC connection established", "", 33n}]
    case 1n+p: admission.line(id) <> admission.lines(p, 1n+id)

def admission.session() -> S.Session:
  S.session_set_size(session(Cl.Client{"me", "s", [Cl.server_buf(), buffer("#archive", admission.lines(32n, 1n))],
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 33n, False{}}, S.Online{}, True{}), 30, 160)

def admission.page_up(st: S.Session) -> S.Session:
  Terminal.entered(S.step_keys(st, S.Keys{"", False{}, Cl.TabStay{}, None{}, 25n, 0n, S.HistStay{}, 0, 0}))

def admission.rows(+st: S.Session, cols: U32) -> List<&2, V.BodyRow>:
  V.body_of.buf_media(Anchor.active_buf(S.session_cl(st)), 25n, V.rect_vis_w(V.lay_body_rect(V.lay(30, cols, 0))),
    True{}, Nil{}, True{}, True{}, "s", S.session_media(st))

def admission.bottom(rows: List<&2, V.BodyRow>, previous: String) -> String:
  match rows:
    case Nil{}: previous
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, tail}: admission.bottom(tail, V.spans_text(spans))
    case Con{_, tail}: admission.bottom(tail, previous)

def admission.controls() -> IO(Unit):
  +before = sbox(admission.page_up(admission.session()))
  +pending = sbox(S.session_observe_visible_media(sunbox(before)))
  +resized = sbox(S.session_set_size(sunbox(pending), 30, 180))
  +revealed = sbox(admission.page_up(sunbox(pending)))
  +revealed_wide = sbox(S.session_set_size(sunbox(revealed), 30, 180))
  do IO<Unit>:
    Unit <- E.must("first PageUp exposes archive URL before admission", String.contains(Anchor.rows_text(admission.rows(sunbox(before), 160)), admission.url()))
    Unit <- E.must_eq("pending admission keeps bottom source anchor", Anchor.anchor(Anchor.active_buf(S.session_cl(sunbox(pending)))), Anchor.anchor(Anchor.active_buf(S.session_cl(sunbox(before)))))
    Unit <- E.must_eq("first PageUp bottom is archive source row25", admission.bottom(admission.rows(sunbox(before), 160), ""), "ARCHIVE-25")
    Unit <- E.must_eq("six pending rows retain the same bottom source", admission.bottom(admission.rows(sunbox(pending), 160), ""), "ARCHIVE-25")
    Unit <- E.must("pending row expansion moves URL above viewport, before resize", Bool.not(String.contains(Anchor.rows_text(admission.rows(sunbox(pending), 160)), admission.url())))
    Unit <- E.must_eq("resize still retains exact bottom source", admission.bottom(admission.rows(sunbox(resized), 180), ""), "ARCHIVE-25")
    Unit <- E.must("second PageUp establishes URL-visible resize precondition", String.contains(Anchor.rows_text(admission.rows(sunbox(revealed), 160)), admission.url()))
    Unit <- E.must("resize preserves URL with image rows already present", String.contains(Anchor.rows_text(admission.rows(sunbox(revealed_wide), 180)), admission.url()))
    IO.pure(Unit, Unit{})

# Absolute oldest edge + BodyMedia: top-pin must keep ARCHIVE-1 (URL row) in
# the first painted source rows. Mid-history ARCHIVE-25 control stays above.
def admission.oldest_buf() -> Cl.Buffer:
  Cl.buf_indexed("#archive", True{}, "", admission.lines(32n, 1n), Nil{}, Cl.ScrollAt{32n, 0n})

def admission.oldest_session() -> S.Session:
  S.session_set_size(session(Cl.Client{"me", "s", [Cl.server_buf(), admission.oldest_buf()],
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 33n, False{}}, S.Online{}, True{}), 30, 160)

def admission.oldest_top(rows: List<&2, V.BodyRow>) -> String:
  match rows:
    case Nil{}: ""
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, _}: V.spans_text(spans)
    case Con{_, tail}: admission.oldest_top(tail)

# − mid-history (admission.controls): BodyMedia expansion pushes the URL
# above the viewport while ARCHIVE-25 bottom-pin holds. + at-oldest: fill
# from the top so ARCHIVE-1 text/URL stay painted; PageUp does not move.
def admission.oldest_controls() -> IO(Unit):
  +at = sbox(admission.oldest_session())
  +pending = sbox(S.session_observe_visible_media(sunbox(at)))
  +again = sbox(admission.page_up(sunbox(pending)))
  do IO<Unit>:
    Unit <- E.must_eq("at-oldest ScrollAt before media", Anchor.anchor(Anchor.active_buf(S.session_cl(sunbox(at)))), "32:0")
    Unit <- E.must("at-oldest exposes ARCHIVE-1 URL before admission", String.contains(Anchor.rows_text(admission.rows(sunbox(at), 160)), admission.url()))
    Unit <- E.must_eq("at-oldest top source is ARCHIVE-1", admission.oldest_top(admission.rows(sunbox(at), 160)), "ARCHIVE-IMAGE " ++ admission.url())
    Unit <- E.must_eq("BodyMedia pending keeps at-oldest anchor", Anchor.anchor(Anchor.active_buf(S.session_cl(sunbox(pending)))), "32:0")
    Unit <- E.must_eq("+ BodyMedia pending keeps ARCHIVE-1 as top source", admission.oldest_top(admission.rows(sunbox(pending), 160)), "ARCHIVE-IMAGE " ++ admission.url())
    Unit <- E.must("+ BodyMedia pending keeps oldest URL in viewport", String.contains(Anchor.rows_text(admission.rows(sunbox(pending), 160)), admission.url()))
    Unit <- E.must_eq("+ PageUp at oldest stays", Anchor.anchor(Anchor.active_buf(S.session_cl(sunbox(again)))), "32:0")
    IO.pure(Unit, Unit{})

# The pinned native backend permits at most 247 flattened capture words
# per continuation. One 66-statement main holding ~10 live Sessions
# breaches it ("an arity over 247"); each phase below holds only boxed
# Sessions plus small M.State/Nat values, and main only sequences
# phases. Assertions are unchanged, in the same order
# (session_drafts_demo precedent).
def ph_panes() -> IO(Unit):
  +single = sbox(session(client(), S.Online{}, True{}))
  +split = sbox(with_split(sunbox(single), Sp.On{Sp.SideBySide{}, "#left", "#right", 0}))
  do IO<Unit>:
    Unit <- E.must_eq("only current pane admits newest eight", selected_ids(candidates(sunbox(single))), "10|9|8|7|6|5|4|3|")
    Unit <- E.must_eq("split bounds both panes together", selected_ids(candidates(sunbox(split))), "20|19|18|17|16|15|14|13|")
    Unit <- E.must("muted rows never become candidates", List.is_empty(&2, M.Candidate,
      V.visible_media_candidates(Cl.set_settings(client(), Cl.set_mutes(Cl.get_settings(client()), ["alice"])), 35, 200, Sp.Off{}, M.initial(True{}))))
    Unit <- E.must("synthetic tabs never become candidates", List.is_empty(&2, M.Candidate,
      V.visible_media.buffer(buffer("*log*", [line(1n)]), 10n, 100, False{}, Nil{}, True{}, True{}, "s", M.initial(True{}))))
    Unit <- E.must("zero-ID rows never become candidates", List.is_empty(&2, M.Candidate,
      V.visible_media.buffer(buffer("#room", [line(0n)]), 10n, 100, False{}, Nil{}, True{}, True{}, "s", M.initial(True{}))))
    Unit <- E.must("empty-height viewport never fetches", List.is_empty(&2, M.Candidate,
      V.visible_media.buffer(buffer("#room", [line(1n)]), 0n, 100, False{}, Nil{}, True{}, True{}, "s", M.initial(True{}))))
    Unit <- E.must("empty-width viewport never fetches", List.is_empty(&2, M.Candidate,
      V.visible_media.buffer(buffer("#room", [line(1n)]), 10n, 0, False{}, Nil{}, True{}, True{}, "s", M.initial(True{}))))
    Unit <- E.must_eq("fitting tiny viewport admits exact visible row", selected_ids(V.visible_media_candidates(
      Cl.Client{"me", "s", [Cl.server_buf(), buffer("#room", [line(1n)])], 1n, "", Cl.settings0(), Cl.AuthIdle{}, 1n, False{}},
      6, 80, Sp.Off{}, M.initial(True{}))), "1|")
    Unit <- E.must_eq("paused anchor uses exact painted rows", selected_ids(M.newest_candidates(V.visible_media.buffer(
      Cl.set_buf_anchor(buffer("#room", lines(10n, 1n)), Cl.ScrollAt{5n, 0n}), 2n, 100, False{}, Nil{}, True{}, True{}, "s", M.initial(True{})), M.initial(True{}))), "5|4|")
    Unit <- E.must_eq("media-only visible rows keep source identity", selected_ids(M.newest_candidates(V.visible_media.buffer(
      buffer("#room", [line(1n)]), 3n, 100, False{}, Nil{}, True{}, True{}, "s", M.enqueue(M.initial(True{}), M.Inline{1n}, url(1n))), M.initial(True{}))), "1|")
    return Unit{}

def ph_archive() -> IO(Unit):
  +imported = sbox(session(restored(), S.Connecting{}, True{}))
  +unsupported = sbox(S.session_observe_visible_media(S.session_set_media(sunbox(imported), M.set_supported(M.initial(True{}), False{}))))
  +observed = sbox(S.session_observe_visible_media(sunbox(imported)))
  do IO<Unit>:
    Unit <- E.must_eq("archive row receives fresh identity", selected_ids(candidates(sunbox(imported))), "51|")
    Unit <- E.must_eq("live fresh-ID cutoff does not refetch archive", Nat.show(M.pending_count(S.session_media(S.session_observe_media(S.session_online(sunbox(imported)), 51n)))), "0")
    Unit <- E.must_eq("visible startup archive queues while Connecting", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(sunbox(imported))))), "1")
    Unit <- E.must_eq("visible archive queues while Offline", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_net(sunbox(imported), S.Offline{}))))), "1")
    Unit <- E.must_eq("visible archive queues while Reconnecting", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_net(sunbox(imported), S.Reconnecting{}))))), "1")
    Unit <- E.must_eq("Demo never automatically fetches archive", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_net(sunbox(imported), S.Demo{}))))), "0")
    Unit <- E.must_eq("Stopping never starts archive work", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_net(sunbox(imported), S.Stopping{False{}}))))), "0")
    Unit <- E.must_eq("saved images off suppresses archive work", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_media(sunbox(imported), M.initial(False{})))))), "0")
    Unit <- E.must("unsupported visible archive stays quiet", Terminal.quiet(S.session_media(sunbox(unsupported))))
    Unit <- E.must_eq("unsupported visible archive explains once", Nat.show(Terminal.notice_count(S.session_observe_visible_media(sunbox(unsupported)))), "1")
    Unit <- E.must_eq("admission does not steal focus", Cl.active_buf_name(S.session_cl(sunbox(observed))), "#history")
    Unit <- E.must_eq("admission preserves sequence", Nat.show(Cl.log_seq_of(S.session_cl(sunbox(observed)))), "51")
    Unit <- E.must_eq("admission creates no history append", H.extract_new_history(S.session_cl(sunbox(imported)), S.session_cl(sunbox(observed))), "")
    return Unit{}

def ph_drain() -> IO(Unit):
  +single = sbox(session(client(), S.Online{}, True{}))
  +dd1 : Drain = drain(64n, sunbox(single))
  +single_n : Nat = count(dd1)
  +single_st = sbox(result(dd1))
  +split = sbox(with_split(sunbox(single), Sp.On{Sp.SideBySide{}, "#left", "#right", 0}))
  +dd2 : Drain = drain(64n, sunbox(split))
  +split_n : Nat = count(dd2)
  +split_st = sbox(result(dd2))
  +stacked = sbox(with_split(S.session_set_size(sunbox(single), 65, 200), Sp.On{Sp.Stacked{}, "#left", "#right", 1}))
  +dd3 : Drain = drain(64n, sunbox(stacked))
  +stacked_n : Nat = count(dd3)
  +stacked_st = sbox(result(dd3))
  +saturated = sbox(S.session_set_media(sunbox(single), fill(8n, 100n, M.initial(True{}))))
  +dd4 : Drain = drain(64n, sunbox(saturated))
  +refilled_n : Nat = count(dd4)
  +refilled_st = sbox(result(dd4))
  +again = sbox(S.session_observe_visible_media(Terminal.entered(S.step_enter(sunbox(single_st), "/reconnect"))))
  do IO<Unit>:
    Unit <- E.must("single pane settles after eight jobs", Nat.is_eq(single_n, 8n) && stable(sunbox(single_st)))
    Unit <- E.must("mixed split settles without eviction/refetch loop", Nat.is_lt(split_n, 32n) && stable(sunbox(split_st)))
    Unit <- E.must("stacked split also settles without repeated work", Nat.is_lt(stacked_n, 32n) && stable(sunbox(stacked_st)))
    Unit <- E.must("full old live queue drains and refills visible archive", Nat.is_gt(refilled_n, 8n) && Nat.is_lt(refilled_n, 32n) && stable(sunbox(refilled_st)))
    Unit <- E.must("reconnect generation admits visible stored rows again", Nat.is_gt(M.pending_count(S.session_media(sunbox(again))), 0n) && Nat.is_eq(M.ready_count(S.session_media(sunbox(again))), 0n))
    return Unit{}

def ph_cache_admit() -> IO(Unit):
  +single = sbox(session(client(), S.Online{}, True{}))
  +cache : M.State = M.State{True{}, 1n, 9n, None{}, Nil{}, ready(8n, 1n), M.Supported{}}
  +wanted : List<&2, M.Candidate> = List.append(&2, M.Candidate, selected(7n, 2n), [M.Candidate{M.Inline{9n}, url(9n)}])
  +protected : M.State = prospective(M.take_job(M.enqueue_candidates(wanted, cache)), client())
  +legacy : M.State = prospective(M.take_job(M.enqueue_candidates.go(wanted, cache)), client())
  +duplicate : Cl.Client = Cl.Client{"me", "s", [Cl.server_buf(), buffer("#room", [line(1n), Cl.Line{Cl.Msg{}, "", url(1n), "alice", 2n}])], 1n, "", Cl.settings0(), Cl.AuthIdle{}, 2n, False{}}
  +hidden : M.State = M.State{True{}, 1n, 101n, Some{M.Request{M.Inline{100n}, url(100n), 1n, 100n}}, Nil{}, ready(8n, 1n), M.Supported{}}
  +room : M.State = M.State{True{}, 1n, 101n, Some{M.Request{M.Inline{100n}, url(100n), 1n, 100n}}, Nil{}, ready(7n, 1n), M.Supported{}}
  +full = sbox(S.session_set_size(S.session_set_media(sunbox(single), hidden), 200, 200))
  # − plain reject / visible decline: clears exact worker, soft-defers relaunch.
  +declined : M.State = M.reject(hidden, 1n, 100n, url(100n))
  # Soft defer lifts when the same candidate is selected again.
  +soft_cleared : M.State = M.enqueue_candidates([M.Candidate{M.Inline{100n}, url(100n)}], declined)
  # SoftFence keeps across a same-target gen bump (not gen=0 encoding).
  +soft_bumped : M.State = bump_gen_maintain(declined, client())
  # − reject_full into CAP nonzero ready: must not drop a live retained token.
  +declined_full_cap : M.State = M.reject_full(hidden, client(), 1n, 100n, url(100n))
  # StickyFence keeps across a same-target gen bump; reset clears it.
  +sticky_bumped : M.State = bump_gen_maintain(declined_full_cap, client())
  +sticky_reset : M.State = M.reset(declined_full_cap)
  # − SoftFence tags ignored by pending_work_count: total can exceed PENDING_CAP.
  +soft_hazard : M.State = M.State{True{}, 1n, 1n, None{}, soft_tags(24n), Nil{}, M.Supported{}}
  # + reject SoftFence flood: drop oldest fence tags; work count stays 0.
  +soft_flooded : M.State = soft_flood(24n, M.initial(True{}))
  # + StickyFence flood into CAP ready (ids 100..): same total bound; work 0.
  +sticky_base : M.State = M.State{True{}, 1n, 1n, None{}, Nil{}, ready(8n, 100n), M.Supported{}}
  +sticky_flooded : M.State = sticky_flood(20n, sticky_base, client())
  # + reject_full with room: failed identity → ready_has blocks relaunch.
  +declined_full : M.State = M.reject_full(room, client(), 1n, 100n, url(100n))
  # − speculative complete(..., 0) at CAP FIFO-drops a live owner Bend still has.
  +speculative : M.State = M.complete(hidden, client(), 1n, 100n, url(100n), 0)
  # −/+ complete into CAP ready that mixes 7nz+1z: blind List.take dropped a
  # nonzero; zero-prefer keeps all 7nz + the new token.
  +mixed_z : List<&2, M.MediaReady> = M.MediaReady{M.Inline{0n}, url(0n), 0} <> ready(7n, 1n)
  +mixed : M.State = M.State{True{}, 1n, 101n, Some{M.Request{M.Inline{100n}, url(100n), 1n, 100n}}, Nil{}, mixed_z, M.Supported{}}
  +blind_mixed : M.State = M.State{True{}, 1n, 101n, None{}, Nil{},
    List.take(&2, M.MediaReady, M.MediaReady{M.Inline{100n}, url(100n), 100} <> mixed_z, M.CAP()), M.Supported{}}
  +mixed_done : M.State = M.complete(mixed, client(), 1n, 100n, url(100n), 100)
  # Same hazard when media_add returns 0 into a ready that still has zeros.
  +mixed_zero_done : M.State = M.complete(mixed, client(), 1n, 100n, url(100n), 0)
  do IO<Unit>:
    Unit <- E.must("prospective native set retains selected visible token", token_has(M.retained_tokens(protected), 8) && Bool.not(token_has(M.retained_tokens(protected), 1)))
    Unit <- E.must("control shows unchanged completion FIFO would evict visible token", token_has(M.retained_tokens(legacy), 1) && Bool.not(token_has(M.retained_tokens(legacy), 8)))
    Unit <- E.must_eq("same URL on distinct events retains per-target identity", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(session(duplicate, S.Online{}, True{}))))), "2")
    Unit <- E.must("legacy admission would accept unrelated hidden completion", M.accept(hidden, client(), 1n, 100n, url(100n)))
    Unit <- E.must("full visible cache rejects unrelated hidden completion", Bool.not(S.session_accept_media_result(sunbox(full), 1n, 100n, url(100n))))
    Unit <- E.must("- reject clears active", Bool.not(Terminal.has_active(declined)))
    Unit <- E.must("- reject keeps ready CAP", Nat.is_eq(M.ready_count(declined), 8n) && token_has(M.retained_tokens(declined), 8))
    Unit <- E.must("- reject leaves known_urls empty", List.is_empty(&2, String, M.known_urls(declined, M.Inline{100n})))
    Unit <- E.must("- reject soft-blocks bare enqueue", Nat.is_eq(M.pending_count(M.enqueue(declined, M.Inline{100n}, url(100n))), 0n))
    Unit <- E.must("- reject soft-blocks take_job", Bool.not(Terminal.has_job(M.take_job(declined))))
    Unit <- E.must("- reject soft survives maintain as non-work", Nat.is_eq(M.pending_count(M.maintain(declined, client())), 0n))
    Unit <- E.must("- SoftFence survives same-target gen bump", Nat.is_eq(M.pending_count(M.enqueue(soft_bumped, M.Inline{100n}, url(100n))), 0n)
      && Bool.not(Terminal.has_job(M.take_job(soft_bumped))))
    Unit <- E.must("+ selected enqueue_candidates lifts soft defer", Nat.is_gt(M.pending_count(soft_cleared), 0n)
      && Terminal.has_job(M.take_job(soft_cleared))
      && List.is_empty(&2, String, M.known_urls(declined, M.Inline{100n})))
    Unit <- E.must("- speculative complete at CAP drops a live retained token", Nat.is_eq(List.length(&2, U32, M.retained_tokens(speculative)), 7n)
      && Bool.not(token_has(M.retained_tokens(speculative), 8)))
    Unit <- E.must("- blind take at CAP 7nz+1z drops a nonzero", Nat.is_eq(List.length(&2, U32, M.retained_tokens(blind_mixed)), 7n)
      && Bool.not(token_has(M.retained_tokens(blind_mixed), 7))
      && token_has(M.retained_tokens(blind_mixed), 100)
      && Nat.is_eq(M.ready_count(blind_mixed), 8n))
    Unit <- E.must("+ complete at CAP 7nz+1z keeps nonzero and new token", Nat.is_eq(List.length(&2, U32, M.retained_tokens(mixed_done)), 8n)
      && token_has(M.retained_tokens(mixed_done), 1) && token_has(M.retained_tokens(mixed_done), 7)
      && token_has(M.retained_tokens(mixed_done), 100)
      && Bool.not(token_has(M.retained_tokens(mixed_done), 0)))
    Unit <- E.must("+ complete(..., 0) at CAP 7nz+1z drops the zero not a nonzero", Nat.is_eq(List.length(&2, U32, M.retained_tokens(mixed_zero_done)), 7n)
      && token_has(M.retained_tokens(mixed_zero_done), 1) && token_has(M.retained_tokens(mixed_zero_done), 7)
      && Nat.is_eq(M.ready_count(mixed_zero_done), 8n))
    Unit <- E.must("+ admit_retained keeps every current owner at CAP", Nat.is_eq(List.length(&2, U32, M.admit_retained(hidden)), 8n)
      && token_has(M.admit_retained(hidden), 8) && Bool.not(M.admit_room(hidden)))
    # Headless Net.on_media gate (mirror wsnet): never speculative retain;
    # admit_room false → reject_full; policy decline stays plain reject.
    Unit <- E.must("- net admit_room false at CAP nonzero", Bool.not(M.admit_room(hidden)))
    Unit <- E.must("+ net admit_room true below CAP", M.admit_room(room))
    Unit <- E.must("+ net retain list is admit_retained not speculative", Nat.is_eq(List.length(&2, U32, M.admit_retained(hidden)), 8n)
      && token_has(M.admit_retained(hidden), 8)
      && Bool.not(Nat.is_eq(List.length(&2, U32, M.admit_retained(hidden)), List.length(&2, U32, M.retained_tokens(speculative)))))
    Unit <- E.must("- reject_full at CAP nonzero keeps all retained tokens", Bool.not(Terminal.has_active(declined_full_cap))
      && Nat.is_eq(List.length(&2, U32, M.retained_tokens(declined_full_cap)), 8n)
      && token_has(M.retained_tokens(declined_full_cap), 8))
    Unit <- E.must("+ reject_full at CAP nonzero sticky-blocks relaunch", Bool.not(List.is_empty(&2, String, M.known_urls(declined_full_cap, M.Inline{100n})))
      && Nat.is_eq(M.pending_count(M.enqueue(declined_full_cap, M.Inline{100n}, url(100n))), 0n)
      && Bool.not(Terminal.has_job(M.take_job(declined_full_cap))))
    # StickyFence blocks relaunch across gen bumps (same oracle as SoftFence).
    Unit <- E.must("+ StickyFence survives same-target gen bump", Nat.is_eq(M.pending_count(M.enqueue(sticky_bumped, M.Inline{100n}, url(100n))), 0n)
      && Bool.not(Terminal.has_job(M.take_job(sticky_bumped)))
      && Bool.not(List.is_empty(&2, String, M.known_urls(sticky_bumped, M.Inline{100n}))))
    Unit <- E.must("+ reset clears StickyFence", List.is_empty(&2, String, M.known_urls(sticky_reset, M.Inline{100n}))
      && Nat.is_eq(M.pending_count(sticky_reset), 0n))
    # R9/R10 view M4: SoftFence/StickyFence ignored by pending_work_count.
    Unit <- E.must("- SoftFence flood exceeds PENDING_CAP while work count is 0",
      Nat.is_gt(M.pending_total(soft_hazard), M.PENDING_CAP())
      && Nat.is_eq(M.pending_count(soft_hazard), 0n)
      && Bool.not(M.bounded(soft_hazard)))
    Unit <- E.must("+ SoftFence reject flood stays within PENDING_CAP",
      Nat.is_le(M.pending_total(soft_flooded), M.PENDING_CAP())
      && Nat.is_eq(M.pending_count(soft_flooded), 0n)
      && M.bounded(soft_flooded)
      && Nat.is_eq(M.pending_count(M.enqueue(soft_flooded, M.Inline{1n}, url(1n))), 0n)
      && Bool.not(Terminal.has_job(M.take_job(soft_flooded))))
    Unit <- E.must("+ StickyFence reject_full flood stays within PENDING_CAP",
      Nat.is_le(M.pending_total(sticky_flooded), M.PENDING_CAP())
      && Nat.is_eq(M.pending_count(sticky_flooded), 0n)
      && M.bounded(sticky_flooded)
      && Nat.is_eq(List.length(&2, U32, M.retained_tokens(sticky_flooded)), 8n)
      && Nat.is_eq(M.pending_count(M.enqueue(sticky_flooded, M.Inline{1n}, url(1n))), 0n)
      && Bool.not(Terminal.has_job(M.take_job(sticky_flooded))))
    Unit <- E.must("+ reject_full records token-zero and blocks relaunch", Bool.not(Terminal.has_active(declined_full))
      && Bool.not(List.is_empty(&2, String, M.known_urls(declined_full, M.Inline{100n})))
      && Nat.is_eq(List.length(&2, U32, M.retained_tokens(declined_full)), 7n)
      && token_has(M.retained_tokens(declined_full), 7)
      && Nat.is_eq(M.pending_count(M.enqueue(declined_full, M.Inline{100n}, url(100n))), 0n))
    Unit <- E.must("+ net policy decline stays soft reject not reject_full", Bool.not(Terminal.has_active(declined))
      && List.is_empty(&2, String, M.known_urls(declined, M.Inline{100n}))
      && Nat.is_eq(List.length(&2, U32, M.retained_tokens(declined)), 8n))
    Unit <- E.must("wrong completion cannot release owned worker", Terminal.has_active(M.reject(hidden, 1n, 99n, url(100n)))
      && Terminal.has_active(M.reject(hidden, 2n, 100n, url(100n))) && Terminal.has_active(M.reject(hidden, 1n, 100n, url(101n))))
    return Unit{}

def ph_cache_replace() -> IO(Unit):
  +single = sbox(session(client(), S.Online{}, True{}))
  +wanted : List<&2, M.Candidate> = List.append(&2, M.Candidate, selected(7n, 2n), [M.Candidate{M.Inline{9n}, url(9n)}])
  +room : M.State = M.State{True{}, 1n, 10n, Some{M.Request{M.Inline{9n}, url(9n), 1n, 9n}}, Nil{}, ready(8n, 1n), M.Supported{}}
  +manual_state : M.State = M.State{True{}, 1n, 10n, Some{M.Request{M.Manual{}, "/tmp/synthetic.png", 1n, 9n}}, Nil{}, ready(8n, 1n), M.Supported{}}
  +manual_full = sbox(S.session_set_size(S.session_set_media(session(manual_client(), S.Online{}, True{}), manual_state), 200, 200))
  +failures : M.State = M.State{True{}, 1n, 101n, Some{M.Request{M.Inline{100n}, url(100n), 1n, 100n}}, Nil{}, failed(8n, 1n), M.Supported{}}
  +failures_full = sbox(S.session_set_size(S.session_set_media(sunbox(single), failures), 200, 200))
  do IO<Unit>:
    Unit <- E.must("selected completion can replace nonvisible cache tail", M.visible_result_allowed(room, wanted))
    Unit <- E.must("explicit manual completion may replace full visible cache", M.visible_result_allowed(manual_state, selected(8n, 1n))
      && S.session_accept_media_result(sunbox(manual_full), 1n, 9n, "/tmp/synthetic.png"))
    Unit <- E.must("failed visible identities also suppress eviction/refetch loops", Bool.not(S.session_accept_media_result(sunbox(failures_full), 1n, 100n, url(100n))))
    return Unit{}

def ph_stopping() -> IO(Unit):
  +single = sbox(session(client(), S.Online{}, True{}))
  +queued = sbox(S.session_set_media(sunbox(single), M.enqueue(M.initial(True{}), M.Inline{100n}, url(100n))))
  +stopping = sbox(S.session_set_net(sunbox(queued), S.Stopping{True{}}))
  do IO<Unit>:
    Unit <- E.must("Stopping does not start queued next helper", Bool.not(Terminal.has_job(M.take_job_allowed(S.session_media_job_allowed(sunbox(stopping)), S.session_media(sunbox(stopping)))))
      && Nat.is_eq(M.pending_count(Terminal.state_of(M.take_job_allowed(S.session_media_job_allowed(sunbox(stopping)), S.session_media(sunbox(stopping))))), 1n))
    Unit <- E.must("normal state starts the same queued helper", Terminal.has_job(M.take_job_allowed(S.session_media_job_allowed(sunbox(queued)), S.session_media(sunbox(queued)))))
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- ph_panes()
    Unit <- ph_archive()
    Unit <- ph_drain()
    Unit <- ph_cache_admit()
    Unit <- ph_cache_replace()
    Unit <- ph_stopping()
    Unit <- admission.controls()
    Unit <- admission.oldest_controls()
    IO.print("media_history=ok")
