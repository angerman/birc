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
  Cl.Buffer{name, True{}, "", rows, Nil{}, Cl.ScrollAt{0n, 0n}}

def client() -> Cl.Client:
  Cl.Client{"me", "s", Cl.server_buf() <> buffer("#left", lines(10n, 1n))
    <> buffer("#right", lines(10n, 11n)) <> buffer("#hidden", lines(10n, 100n)) <> Nil{},
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 109n}

def with_split(st: S.Session, split: Sp.State) -> S.Session:
  match st:
    case S.Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, _, typing, port, media, plan, edits, +iso, +hl, +cf, +regbox, +theme}:
      S.Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits, iso, hl, cf, regbox, theme}

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

def finish(accepted: Bool, +st: S.Session, +gen: Nat, +ticket: Nat, +url: String) -> S.Session:
  match accepted:
    case True{}: S.session_set_media(st, M.complete(S.session_media(st), S.session_cl(st), gen, ticket, url, U32.from_nat(ticket)))
    case False{}: S.session_set_media(st, M.reject(S.session_media(st), gen, ticket, url))

def drain.step(pair: M.State & Maybe<&2, M.Request>, +st: S.Session, k: S.Session -> Drain) -> Drain:
  match pair:
    case (media, None{}): Drain{S.session_set_media(st, media), 0n}
    case (media, Some{M.Request{_, +url, +gen, +ticket}}):
      +active : S.Session = S.session_set_media(st, media)
      drain.count(k(finish(S.session_accept_media_result(active, gen, ticket, url), active, gen, ticket, url)))

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

def fill(n: Nat, +id: Nat, state: M.State) -> M.State:
  match n:
    case 0n: state
    case 1n+p: fill(p, 1n+id, M.enqueue(state, M.Inline{id}, url(id)))

def restored() -> Cl.Client:
  +current : Cl.Client = Cl.Client{"me", "s", [Cl.server_buf(), buffer("#history", Nil{})],
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 50n}
  +snapshot : Cl.Client = Cl.Client{"old", "s", [Cl.server_buf(), buffer("#history", [line(1n)])],
    0n, "", Cl.settings0(), Cl.AuthIdle{}, 1n}
  Startup.install(current, snapshot)

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
    [Cl.Buffer{"*preview*", False{}, "/tmp/synthetic.png", Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}}]),
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 109n}

def prospective(pair: M.State & Maybe<&2, M.Request>, client: Cl.Client) -> M.State:
  match pair:
    case (state, None{}): state
    case (state, Some{M.Request{_, url, gen, ticket}}): M.complete(state, client, gen, ticket, url, 0)

def token_has(xs: List<&2, U32>, +token: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, tail}: U32.is_eq(h, token) || token_has(tail, token)

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
    1n, "", Cl.settings0(), Cl.AuthIdle{}, 33n}, S.Online{}, True{}), 30, 160)

def admission.page_up(st: S.Session) -> S.Session:
  Terminal.entered(S.step_keys(st, S.Keys{"", False{}, Cl.TabStay{}, None{}, 25n, 0n, S.HistStay{}, False{}, 0}))

def admission.rows(+st: S.Session, cols: U32) -> List<&2, V.BodyRow>:
  V.body_of.buf_media(Anchor.active_buf(S.session_cl(st)), 25n, V.rect_vis_w(V.lay_body_rect(V.lay(30, cols, 0))),
    True{}, Nil{}, "s", S.session_media(st))

def admission.bottom(rows: List<&2, V.BodyRow>, previous: String) -> String:
  match rows:
    case Nil{}: previous
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, tail}: admission.bottom(tail, V.spans_text(spans))
    case Con{_, tail}: admission.bottom(tail, previous)

def admission.controls() -> IO(Unit):
  +before : S.Session = admission.page_up(admission.session())
  +pending : S.Session = S.session_observe_visible_media(before)
  +resized : S.Session = S.session_set_size(pending, 30, 180)
  +revealed : S.Session = admission.page_up(pending)
  +revealed_wide : S.Session = S.session_set_size(revealed, 30, 180)
  do IO<Unit>:
    Unit <- E.must("first PageUp exposes archive URL before admission", String.contains(Anchor.rows_text(admission.rows(before, 160)), admission.url()))
    Unit <- E.must_eq("pending admission keeps bottom source anchor", Anchor.anchor(Anchor.active_buf(S.session_cl(pending))), Anchor.anchor(Anchor.active_buf(S.session_cl(before))))
    Unit <- E.must_eq("first PageUp bottom is archive source row25", admission.bottom(admission.rows(before, 160), ""), "ARCHIVE-25")
    Unit <- E.must_eq("six pending rows retain the same bottom source", admission.bottom(admission.rows(pending, 160), ""), "ARCHIVE-25")
    Unit <- E.must("pending row expansion moves URL above viewport, before resize", Bool.not(String.contains(Anchor.rows_text(admission.rows(pending, 160)), admission.url())))
    Unit <- E.must_eq("resize still retains exact bottom source", admission.bottom(admission.rows(resized, 180), ""), "ARCHIVE-25")
    Unit <- E.must("second PageUp establishes URL-visible resize precondition", String.contains(Anchor.rows_text(admission.rows(revealed, 160)), admission.url()))
    Unit <- E.must("resize preserves URL with image rows already present", String.contains(Anchor.rows_text(admission.rows(revealed_wide, 180)), admission.url()))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    +single : S.Session = session(client(), S.Online{}, True{})
    Unit <- E.must_eq("only current pane admits newest eight", selected_ids(candidates(single)), "10|9|8|7|6|5|4|3|")
    +split : S.Session = with_split(single, Sp.On{Sp.SideBySide{}, "#left", "#right", 0})
    Unit <- E.must_eq("split bounds both panes together", selected_ids(candidates(split)), "20|19|18|17|16|15|14|13|")
    Unit <- E.must("muted rows never become candidates", List.is_empty(&2, M.Candidate,
      V.visible_media_candidates(Cl.set_settings(client(), Cl.set_mutes(Cl.get_settings(client()), ["alice"])), 35, 200, Sp.Off{}, M.initial(True{}))))
    Unit <- E.must("synthetic tabs never become candidates", List.is_empty(&2, M.Candidate,
      V.visible_media.buffer(buffer("*log*", [line(1n)]), 10n, 100, False{}, Nil{}, "s", M.initial(True{}))))
    Unit <- E.must("zero-ID rows never become candidates", List.is_empty(&2, M.Candidate,
      V.visible_media.buffer(buffer("#room", [line(0n)]), 10n, 100, False{}, Nil{}, "s", M.initial(True{}))))
    Unit <- E.must("empty-height viewport never fetches", List.is_empty(&2, M.Candidate,
      V.visible_media.buffer(buffer("#room", [line(1n)]), 0n, 100, False{}, Nil{}, "s", M.initial(True{}))))
    Unit <- E.must("empty-width viewport never fetches", List.is_empty(&2, M.Candidate,
      V.visible_media.buffer(buffer("#room", [line(1n)]), 10n, 0, False{}, Nil{}, "s", M.initial(True{}))))
    Unit <- E.must_eq("fitting tiny viewport admits exact visible row", selected_ids(V.visible_media_candidates(
      Cl.Client{"me", "s", [Cl.server_buf(), buffer("#room", [line(1n)])], 1n, "", Cl.settings0(), Cl.AuthIdle{}, 1n},
      6, 80, Sp.Off{}, M.initial(True{}))), "1|")
    Unit <- E.must_eq("paused anchor uses exact painted rows", selected_ids(M.newest_candidates(V.visible_media.buffer(
      Cl.set_buf_anchor(buffer("#room", lines(10n, 1n)), Cl.ScrollAt{5n, 0n}), 2n, 100, False{}, Nil{}, "s", M.initial(True{})), M.initial(True{}))), "5|4|")
    Unit <- E.must_eq("media-only visible rows keep source identity", selected_ids(M.newest_candidates(V.visible_media.buffer(
      buffer("#room", [line(1n)]), 3n, 100, False{}, Nil{}, "s", M.enqueue(M.initial(True{}), M.Inline{1n}, url(1n))), M.initial(True{}))), "1|")
    +imported : S.Session = session(restored(), S.Connecting{}, True{})
    Unit <- E.must_eq("archive row receives fresh identity", selected_ids(candidates(imported)), "51|")
    Unit <- E.must_eq("live fresh-ID cutoff does not refetch archive", Nat.show(M.pending_count(S.session_media(S.session_observe_media(S.session_online(imported), 51n)))), "0")
    Unit <- E.must_eq("visible startup archive queues while Connecting", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(imported)))), "1")
    Unit <- E.must_eq("visible archive queues while Offline", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_net(imported, S.Offline{}))))), "1")
    Unit <- E.must_eq("visible archive queues while Reconnecting", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_net(imported, S.Reconnecting{}))))), "1")
    Unit <- E.must_eq("Demo never automatically fetches archive", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_net(imported, S.Demo{}))))), "0")
    Unit <- E.must_eq("Stopping never starts archive work", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_net(imported, S.Stopping{False{}}))))), "0")
    Unit <- E.must_eq("saved images off suppresses archive work", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(S.session_set_media(imported, M.initial(False{})))))), "0")
    +unsupported : S.Session = S.session_observe_visible_media(S.session_set_media(imported, M.set_supported(M.initial(True{}), False{})))
    Unit <- E.must("unsupported visible archive stays quiet", Terminal.quiet(S.session_media(unsupported)))
    Unit <- E.must_eq("unsupported visible archive explains once", Nat.show(Terminal.notice_count(S.session_observe_visible_media(unsupported))), "1")
    +observed : S.Session = S.session_observe_visible_media(imported)
    Unit <- E.must_eq("admission does not steal focus", Cl.active_buf_name(S.session_cl(observed)), "#history")
    Unit <- E.must_eq("admission preserves sequence", Nat.show(Cl.log_seq_of(S.session_cl(observed))), "51")
    Unit <- E.must_eq("admission creates no history append", H.extract_new_history(S.session_cl(imported), S.session_cl(observed)), "")
    +single_done : Drain = drain(64n, single)
    Unit <- E.must("single pane settles after eight jobs", Nat.is_eq(count(single_done), 8n) && stable(result(single_done)))
    +split_done : Drain = drain(64n, split)
    Unit <- E.must("mixed split settles without eviction/refetch loop", Nat.is_lt(count(split_done), 32n) && stable(result(split_done)))
    +stacked : S.Session = with_split(S.session_set_size(single, 65, 200), Sp.On{Sp.Stacked{}, "#left", "#right", 1})
    +stacked_done : Drain = drain(64n, stacked)
    Unit <- E.must("stacked split also settles without repeated work", Nat.is_lt(count(stacked_done), 32n) && stable(result(stacked_done)))
    +saturated : S.Session = S.session_set_media(single, fill(8n, 100n, M.initial(True{})))
    +refilled : Drain = drain(64n, saturated)
    Unit <- E.must("full old live queue drains and refills visible archive", Nat.is_gt(count(refilled), 8n) && Nat.is_lt(count(refilled), 32n) && stable(result(refilled)))
    +again : S.Session = S.session_observe_visible_media(Terminal.entered(S.step_enter(result(single_done), "/reconnect")))
    Unit <- E.must("reconnect generation admits visible stored rows again", Nat.is_gt(M.pending_count(S.session_media(again)), 0n) && Nat.is_eq(M.ready_count(S.session_media(again)), 0n))
    +cache : M.State = M.State{True{}, 1n, 9n, None{}, Nil{}, ready(8n, 1n), M.Supported{}}
    +wanted : List<&2, M.Candidate> = List.append(&2, M.Candidate, selected(7n, 2n), [M.Candidate{M.Inline{9n}, url(9n)}])
    +protected : M.State = prospective(M.take_job(M.enqueue_candidates(wanted, cache)), client())
    +legacy : M.State = prospective(M.take_job(M.enqueue_candidates.go(wanted, cache)), client())
    Unit <- E.must("prospective native set retains selected visible token", token_has(M.retained_tokens(protected), 8) && Bool.not(token_has(M.retained_tokens(protected), 1)))
    Unit <- E.must("control shows unchanged completion FIFO would evict visible token", token_has(M.retained_tokens(legacy), 1) && Bool.not(token_has(M.retained_tokens(legacy), 8)))
    +duplicate : Cl.Client = Cl.Client{"me", "s", [Cl.server_buf(), buffer("#room", [line(1n), Cl.Line{Cl.Msg{}, "", url(1n), "alice", 2n}])], 1n, "", Cl.settings0(), Cl.AuthIdle{}, 2n}
    Unit <- E.must_eq("same URL on distinct events retains per-target identity", Nat.show(M.pending_count(S.session_media(S.session_observe_visible_media(session(duplicate, S.Online{}, True{}))))), "2")
    +hidden : M.State = M.State{True{}, 1n, 101n, Some{M.Request{M.Inline{100n}, url(100n), 1n, 100n}}, Nil{}, ready(8n, 1n), M.Supported{}}
    +full : S.Session = S.session_set_size(S.session_set_media(single, hidden), 200, 200)
    Unit <- E.must("legacy admission would accept unrelated hidden completion", M.accept(hidden, client(), 1n, 100n, url(100n)))
    Unit <- E.must("full visible cache rejects unrelated hidden completion", Bool.not(S.session_accept_media_result(full, 1n, 100n, url(100n))))
    +declined : M.State = M.reject(hidden, 1n, 100n, url(100n))
    Unit <- E.must("declined completion releases only its worker and retains visible cache", Bool.not(Terminal.has_active(declined)) && Nat.is_eq(M.ready_count(declined), 8n)
      && token_has(M.retained_tokens(declined), 8) && List.is_empty(&2, String, M.known_urls(declined, M.Inline{100n})))
    Unit <- E.must("wrong completion cannot release owned worker", Terminal.has_active(M.reject(hidden, 1n, 99n, url(100n)))
      && Terminal.has_active(M.reject(hidden, 2n, 100n, url(100n))) && Terminal.has_active(M.reject(hidden, 1n, 100n, url(101n))))
    +room : M.State = M.State{True{}, 1n, 10n, Some{M.Request{M.Inline{9n}, url(9n), 1n, 9n}}, Nil{}, ready(8n, 1n), M.Supported{}}
    Unit <- E.must("selected completion can replace nonvisible cache tail", M.visible_result_allowed(room, wanted))
    +manual_state : M.State = M.State{True{}, 1n, 10n, Some{M.Request{M.Manual{}, "/tmp/synthetic.png", 1n, 9n}}, Nil{}, ready(8n, 1n), M.Supported{}}
    Unit <- E.must("explicit manual completion may replace full visible cache", M.visible_result_allowed(manual_state, selected(8n, 1n))
      && S.session_accept_media_result(S.session_set_size(S.session_set_media(session(manual_client(), S.Online{}, True{}), manual_state), 200, 200), 1n, 9n, "/tmp/synthetic.png"))
    +failures : M.State = M.State{True{}, 1n, 101n, Some{M.Request{M.Inline{100n}, url(100n), 1n, 100n}}, Nil{}, failed(8n, 1n), M.Supported{}}
    Unit <- E.must("failed visible identities also suppress eviction/refetch loops", Bool.not(S.session_accept_media_result(S.session_set_size(S.session_set_media(single, failures), 200, 200), 1n, 100n, url(100n))))
    +queued : S.Session = S.session_set_media(single, M.enqueue(M.initial(True{}), M.Inline{100n}, url(100n)))
    +stopping : S.Session = S.session_set_net(queued, S.Stopping{True{}})
    Unit <- E.must("Stopping does not start queued next helper", Bool.not(Terminal.has_job(M.take_job_allowed(S.session_media_job_allowed(stopping), S.session_media(stopping))))
      && Nat.is_eq(M.pending_count(Terminal.state_of(M.take_job_allowed(S.session_media_job_allowed(stopping), S.session_media(stopping)))), 1n))
    Unit <- E.must("normal state starts the same queued helper", Terminal.has_job(M.take_job_allowed(S.session_media_job_allowed(queued), S.session_media(queued))))
    Unit <- admission.controls()
    IO.print("media_history=ok")
