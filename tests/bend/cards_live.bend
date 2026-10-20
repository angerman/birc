# SPDX-License-Identifier: Apache-2.0
# C8 live integration: boundary-aware scheduling, Session-retained cards and
# fullscreen, worker ownership across endpoint transitions, completion
# admission, fullscreen key binding, overlay paint, and card-row paint/nav
# agreement. Pure Session/View/Net seams (JS backend); the IO spawn and the
# native frame stay with the heavy lane.
import Base
import ./expect.bend as E
import ../../src/bend/links.bend as Links
import ../../src/bend/wire_style.bend as Ws
import ../../src/bend/view_laws.bend as VL
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/frame.bend as Fr
import ../../src/bend/isupport.bend as Is
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V
import ../../src/bend/cards.bend as C
import ../../src/bend/cards_view.bend as CV
import ../../src/bend/cards_net.bend as CN

def page() -> String:
  "https://x.test/read"

def image() -> String:
  "https://x.test/a.png"

def doc() -> String:
  "https://x.test/doc"

def soh() -> String:
  SCon{Chr{1}, ""}

def stx() -> String:
  SCon{Chr{2}, ""}

def esc() -> String:
  SCon{Chr{27}, ""}

def styled_infix() -> String:
  "https://x.test/re" ++ stx() ++ "ad"

def soh_prefixed() -> String:
  "x" ++ soh() ++ page()

def gate3_query() -> String:
  "https://example.test/no-image?name=photo.png"

def link_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see " ++ page(), "alice", 1n}])

def online() -> Sess.Session:
  Sess.session_online(Sess.session_with_client(link_client(), "#t"))

def demo() -> Sess.Session:
  Sess.session_demo(link_client(), "#t")

def stopping() -> Sess.Session:
  Sess.session_set_net(Sess.session_with_client(link_client(), "#t"), Sess.Stopping{False{}})

def cards_pending(+st: Sess.Session) -> Nat:
  C.pending_count(Sess.session_cards(st))

def cards_ready(+st: Sess.Session) -> Nat:
  C.ready_count(Sess.session_cards(st))

def cards_gen(+st: Sess.Session) -> Nat:
  C.generation(Sess.session_cards(st))

def full_open(+st: Sess.Session) -> Bool:
  C.is_open(Sess.session_full(st))

def observed() -> Sess.Session:
  Sess.session_observe_visible_cards(online())

def job_shape(job: Maybe<&2, C.Request>) -> String:
  match job:
    case None{}: "none"
    case Some{C.Request{_, url, generation, ticket}}: Nat.show(generation) ++ ":" ++ Nat.show(ticket) ++ ":" ++ url

def took_job(pair: C.State & Maybe<&2, C.Request>) -> Maybe<&2, C.Request>:
  match pair:
    case (_, job): job

def take_shape(+st: Sess.Session) -> String:
  job_shape(took_job(C.take_job_allowed(Sess.session_cards_job_allowed(st),
    C.maintain(Sess.session_cards(st), Sess.session_cl(st)))))

def took_state(pair: C.State & Maybe<&2, C.Request>) -> C.State:
  match pair:
    case (state, _): state

def took() -> Sess.Session:
  Sess.session_set_cards(observed(), took_state(C.take_job_allowed(Sess.session_cards_job_allowed(observed()),
    C.maintain(Sess.session_cards(observed()), Sess.session_cl(observed())))))

def done() -> Sess.Session:
  Sess.session_set_cards(took(), C.complete(Sess.session_cards(took()),
    Sess.session_cl(took()), 1n, 1n, page(), "Hello\nA description\n"))

def on_card_st(pair: Sess.Session & Bool) -> Sess.Session:
  match pair:
    case (st, _): st

def on_card_repaint(pair: Sess.Session & Bool) -> String:
  match pair:
    case (_, repaint): Bool.pick(String, repaint, "repaint", "quiet")

def stepped_st(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match trip:
    case (st, _, _): st

def trip_wire(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (_, cmd, halt):
      match cmd:
        case Sess.Cont{+outs}: String.join(outs, "|") ++ ";" ++ Bool.pick(String, halt, "halt", "go")
        case _: Sess.show_netcmd(cmd) ++ ";" ++ Bool.pick(String, halt, "halt", "go")

def link_count(xs: List<&2, V.SpanOp>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{V.Lnk{_, _}, t}: Nat.add(1n, link_count(t))
    case Con{_, t}: link_count(t)

def link_urls(xs: List<&2, V.SpanOp>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{V.Lnk{+url, _}, t}: url <> link_urls(t)
    case Con{_, t}: link_urls(t)

def ops_shape(xs: List<&2, V.DrawOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.OpBox{x, y, w, h, _}, tail}:
      "box:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ ";" ++ ops_shape(tail)
    case Con{V.OpMedia{x, y, w, h, clip_y, clip_h, token}, tail}:
      "media:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(clip_y) ++ "," ++ U32.show(clip_h) ++ "," ++ U32.show(token) ++ ";" ++ ops_shape(tail)
    case Con{_, tail}: ops_shape(tail)

def overlay_of(+st: Sess.Session, +rows: U32, +cols: U32) -> String:
  ops_shape(CV.overlay_ops(Sess.session_full(st), Sess.session_media(st), Sess.session_cl(st), rows, cols))

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text(t)

def row_text(row: V.BodyRow) -> String:
  match row:
    case V.BodyRow{_, _, _, _, _, spans, _}: spans_text(spans)
    case _: "#"

def rows_text(xs: List<&2, V.BodyRow>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, Nil{}}: row_text(h)
    case Con{h, t}: row_text(h) ++ "|" ++ rows_text(t)

def ready_media() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, image(), 7}], M.Supported{}}

def img_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see " ++ image(), "alice", 1n}])

def media_online() -> Sess.Session:
  Sess.session_set_media(Sess.session_online(Sess.session_with_client(img_client(), "#t")), ready_media())

def cards_with_ready() -> C.State:
  C.State{True{}, 1n, 2n, None{}, Nil{}, [C.CardReady{C.CardInline{1n}, page(), "Hello", "A description", ""}]}

def pick_ready(m: Maybe<&2, M.MediaReady>) -> String:
  match m:
    case None{}: "none"
    case Some{M.MediaReady{M.Inline{id}, +url, _}}: Nat.show(id) ++ ":" ++ url
    case Some{M.MediaReady{M.Manual{}, +url, _}}: "manual:" ++ url

def pick_shape(m: Maybe<&2, M.MediaReady>) -> String:
  pick_ready(m)

def fs_handled(pair: Sess.Session & Bool) -> String:
  match pair:
    case (_, handled): Bool.pick(String, handled, "handled", "ignored")

def fs_open(pair: Sess.Session & Bool) -> Bool:
  match pair:
    case (st, _): full_open(st)

def fs_st(pair: Sess.Session & Bool) -> Sess.Session:
  match pair:
    case (st, _): st

def chunk_outs(pair: Sess.Session & List<&2, String>) -> String:
  match pair:
    case (_, +outs): String.join(outs, "|")

def lines2_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n,
    [Cl.Line{Cl.Msg{}, "", "see https://x.test/p1", "alice", 1n},
     Cl.Line{Cl.Msg{}, "", "see https://x.test/p2", "alice", 2n}])

def cards_ready_id2() -> C.State:
  C.State{True{}, 1n, 2n, None{}, Nil{}, [C.CardReady{C.CardInline{2n}, "https://x.test/p2", "Hello", "A description", ""}]}

def cand_ids(xs: List<&2, C.Candidate>) -> String:
  match xs:
    case Nil{}: ""
    case Con{C.Candidate{C.CardInline{id}, _}, Nil{}}: Nat.show(id)
    case Con{C.Candidate{C.CardInline{id}, _}, t}: Nat.show(id) ++ "|" ++ cand_ids(t)
    case Con{_, t}: cand_ids(t)

def paint_empty() -> List<&2, V.CardEntry>:
  Nil{}

def paint_ready() -> List<&2, V.CardEntry>:
  C.paint_entries(cards_with_ready())

def paint_id2() -> List<&2, V.CardEntry>:
  C.paint_entries(cards_ready_id2())

# Union cm repro: CASEMAPPING=ascii with muted a{b. The newest one-row a[b
# message stays painted (ascii keeps { and [ distinct); the older bob URL is
# a separate author. Narrow (rows=5, one painted history row) hides the older URL;
# wide (rows=24) paints both.
def cm_ascii_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n,
    [Cl.Line{Cl.Msg{}, "", "see " ++ page(), "bob", 1n},
     Cl.Line{Cl.Msg{}, "", "hello", "a[b", 2n}])

def cm_muted_client() -> Cl.Client:
  Cl.set_settings(cm_ascii_client(), Cl.set_mutes(Cl.get_settings(cm_ascii_client()), ["a{b"]))

def cm_iso_ascii() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CASEMAPPING=ascii :are supported")

def cm_narrow() -> Sess.Session:
  Sess.session_set_size(Sess.session_set_iso(Sess.session_online(Sess.session_with_client(cm_muted_client(), "#t")), cm_iso_ascii()), 5, 80)

def cm_wide() -> Sess.Session:
  Sess.session_set_size(Sess.session_set_iso(Sess.session_online(Sess.session_with_client(cm_muted_client(), "#t")), cm_iso_ascii()), 24, 80)

def media_pending(+st: Sess.Session) -> Nat:
  M.pending_count(Sess.session_media(st))

def gate1_media_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n,
    [Cl.Line{Cl.Msg{}, "", "see " ++ image(), "alice", 1n},
     Cl.Line{Cl.Msg{}, "", "see https://x.test/b.png", "alice", 2n}])

def gate1_media_ready() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, image(), 7}], M.Supported{}}

def gate1_media_online() -> Sess.Session:
  Sess.session_set_media(Sess.session_online(Sess.session_with_client(gate1_media_client(), "#t")), gate1_media_ready())

def gate1_media_fs() -> Sess.Session:
  fs_st(Sess.session_fullscreen_key(gate1_media_online(), Sess.KEY_F9(), 0))

def gate1_cards_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n,
    [Cl.Line{Cl.Msg{}, "", "see " ++ page(), "alice", 1n},
     Cl.Line{Cl.Msg{}, "", "see " ++ image(), "alice", 2n}])

def gate1_cards_media() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{2n}, image(), 7}], M.Supported{}}

def gate1_cards_online() -> Sess.Session:
  Sess.session_set_media(Sess.session_online(Sess.session_with_client(gate1_cards_client(), "#t")), gate1_cards_media())

def gate1_cards_fs() -> Sess.Session:
  fs_st(Sess.session_fullscreen_key(gate1_cards_online(), Sess.KEY_F9(), 0))

def gate1_stale_media() -> Sess.Session:
  Sess.session_set_media(gate1_media_fs(), M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, image(), 9}], M.Supported{}})

def gate1_stale_cards() -> Sess.Session:
  Sess.session_set_media(gate1_cards_fs(), M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{2n}, image(), 9}], M.Supported{}})

def gate1_media_closed() -> Sess.Session:
  fs_st(Sess.session_fullscreen_key(gate1_media_fs(), Sess.KEY_ESCAPE(), 0))

def gate1_media_closed_f9() -> Sess.Session:
  fs_st(Sess.session_fullscreen_key(gate1_media_fs(), Sess.KEY_F9(), 0))

def gate1_cards_closed() -> Sess.Session:
  fs_st(Sess.session_fullscreen_key(gate1_cards_fs(), Sess.KEY_ESCAPE(), 0))

def gate1_cards_closed_f9() -> Sess.Session:
  fs_st(Sess.session_fullscreen_key(gate1_cards_fs(), Sess.KEY_F9(), 0))

def gate1_media_admitted() -> Sess.Session:
  Sess.session_observe_visible_media(gate1_media_closed())

def gate1_cards_admitted() -> Sess.Session:
  Sess.session_observe_visible_cards(gate1_cards_closed())

def gate1_media_muted_client() -> Cl.Client:
  Cl.set_settings(gate1_media_client(), Cl.set_mutes(Cl.get_settings(gate1_media_client()), ["alice"]))

def gate1_media_muted_online() -> Sess.Session:
  Sess.session_set_media(Sess.session_online(Sess.session_with_client(gate1_media_muted_client(), "#t")), gate1_media_ready())

def gate1_media_muted_fs() -> Sess.Session:
  fs_st(Sess.session_fullscreen_key(gate1_media_muted_online(), Sess.KEY_F9(), 0))

def gate1_media_muted_admitted() -> Sess.Session:
  Sess.session_observe_visible_media(fs_st(Sess.session_fullscreen_key(gate1_media_muted_fs(), Sess.KEY_ESCAPE(), 0)))

def gate1_cards_muted_client() -> Cl.Client:
  Cl.set_settings(gate1_cards_client(), Cl.set_mutes(Cl.get_settings(gate1_cards_client()), ["alice"]))

def gate1_cards_muted_online() -> Sess.Session:
  Sess.session_set_media(Sess.session_online(Sess.session_with_client(gate1_cards_muted_client(), "#t")), gate1_cards_media())

def gate1_cards_muted_fs() -> Sess.Session:
  fs_st(Sess.session_fullscreen_key(gate1_cards_muted_online(), Sess.KEY_F9(), 0))

def gate1_cards_muted_admitted() -> Sess.Session:
  Sess.session_observe_visible_cards(fs_st(Sess.session_fullscreen_key(gate1_cards_muted_fs(), Sess.KEY_ESCAPE(), 0)))

def media_job_shape.fields(got: Maybe<&2, M.Work>) -> String:
  match got:
    case None{}: "none"
    case Some{M.Work{_, url, generation, ticket}}: Nat.show(generation) ++ ":" ++ Nat.show(ticket) ++ ":" ++ url

def media_job_shape(job: Maybe<&2, M.Request>) -> String:
  match job:
    case None{}: "none"
    case Some{req}: media_job_shape.fields(M.work_fields(req))

def media_took_job(pair: M.State & Maybe<&2, M.Request>) -> Maybe<&2, M.Request>:
  match pair:
    case (_, job): job

def media_took_state(pair: M.State & Maybe<&2, M.Request>) -> M.State:
  match pair:
    case (state, _): state

def media_take_shape(+st: Sess.Session) -> String:
  media_job_shape(media_took_job(M.take_job_allowed(Sess.session_media_job_allowed(st),
    M.maintain(Sess.session_media(st), Sess.session_cl(st)))))

def media_taken(+st: Sess.Session) -> Sess.Session:
  Sess.session_set_media(st, media_took_state(M.take_job_allowed(Sess.session_media_job_allowed(st),
    M.maintain(Sess.session_media(st), Sess.session_cl(st)))))

def gate5_state_of(pair: C.State & Maybe<&2, C.Request>) -> C.State:
  match pair:
    case (state, _): state

def gate5_job_of(pair: C.State & Maybe<&2, C.Request>) -> String:
  match pair:
    case (_, None{}): "none"
    case (_, Some{C.Request{_, url, generation, ticket}}): Nat.show(generation) ++ ":" ++ Nat.show(ticket) ++ ":" ++ url

def gate5_queued() -> C.State:
  C.enqueue(C.initial(True{}), C.CardInline{1n}, page())

def gate5_active() -> C.State:
  gate5_state_of(C.take_job(gate5_queued()))

def gate5_reset_queued() -> C.State:
  C.maintain(C.enqueue(C.reset(gate5_active()), C.CardInline{1n}, page()), link_client())

def gate5_taken(+st: Sess.Session) -> Sess.Session:
  Sess.session_set_cards(st, took_state(C.take_job_allowed(Sess.session_cards_job_allowed(st),
    C.maintain(Sess.session_cards(st), Sess.session_cl(st)))))

def gate5_reset_session() -> Sess.Session:
  Sess.session_set_cards(took(), C.reset(Sess.session_cards(took())))

def gate5_queued_session() -> Sess.Session:
  Sess.session_observe_visible_cards(gate5_reset_session())

def gate5_pure_wrong(+gen: Nat, +ticket: Nat, +url: String) -> C.State:
  C.complete(gate5_reset_queued(), link_client(), gen, ticket, url, "T\nD\n")

def gate5_pure_iso_old(+w: C.State) -> C.State:
  C.complete(w, link_client(), 1n, 1n, page(), "T\nD\n")

def gate5_pure_iso_taken(+w: C.State) -> C.State:
  gate5_state_of(C.take_job(gate5_pure_iso_old(w)))

def gate5_pure_iso_new_ready(+w: C.State) -> Nat:
  C.ready_count(C.complete(gate5_pure_iso_taken(w), link_client(), 2n, 2n, page(), "T\nD\n"))

def gate5_sess_wrong(+st: Sess.Session, +gen: Nat, +ticket: Nat, +url: String) -> Sess.Session:
  on_card_st(CN.on_card_session(Sess.session_accept_card_result(st, gen, ticket, url), st, gen, ticket, url, "T\nD\n"))

def gate5_sess_wrong_repaint(+st: Sess.Session, +gen: Nat, +ticket: Nat, +url: String) -> String:
  on_card_repaint(CN.on_card_session(Sess.session_accept_card_result(st, gen, ticket, url), st, gen, ticket, url, "T\nD\n"))

def gate5_sess_iso_old(+st: Sess.Session, +gen: Nat, +ticket: Nat, +url: String) -> Sess.Session:
  +w = gate5_sess_wrong(st, gen, ticket, url)
  gate5_sess_wrong(w, 1n, 1n, page())

def gate5_sess_iso_taken(+st: Sess.Session, +gen: Nat, +ticket: Nat, +url: String) -> Sess.Session:
  gate5_taken(gate5_sess_iso_old(st, gen, ticket, url))

def gate5_sess_iso_new_ready(+st: Sess.Session, +gen: Nat, +ticket: Nat, +url: String) -> Nat:
  +taken = gate5_sess_iso_taken(st, gen, ticket, url)
  cards_ready(on_card_st(CN.on_card_session(Sess.session_accept_card_result(taken, 2n, 2n, page()), taken, 2n, 2n, page(), "T\nD\n")))

def main() -> IO(Unit):
  do IO<Unit>:
    # ---- shared boundary seam: View, /open, Media, Cards read one run set ----
    Unit <- E.must_eq("styled infix fetches nothing", String.join(C.targets(styled_infix()), ","), "")
    Unit <- E.must_eq("SOH-prefixed autofetch refused", String.join(C.targets(soh_prefixed()), ","), "")
    Unit <- E.must_eq("ordinary exact URL positive", String.join(C.targets("see " ++ page()), ","), page())
    Unit <- E.must_eq("media SOH-prefixed refused", String.join(M.targets("x" ++ soh() ++ image()), ","), "")
    Unit <- E.must_eq("media styled infix never glues", String.join(M.targets("https://x.test/a." ++ stx() ++ "png"), ","), "")
    Unit <- E.must_eq("media ordinary positive", String.join(M.targets("see " ++ image()), ","), image())
    Unit <- E.must_eq("view paints no styled link", Nat.show(link_count(V.render_spans(styled_infix()))), "0")
    Unit <- E.must_eq("view paints no SOH link", Nat.show(link_count(V.render_spans(soh_prefixed()))), "0")
    Unit <- E.must_eq("view paints exact ordinary link", String.join(link_urls(V.render_spans("see " ++ page())), ","), page())
    Unit <- E.must_eq("open collects no styled link", String.join(Sub.extract_urls(styled_infix()), ","), "")
    Unit <- E.must_eq("open collects no SOH link", String.join(Sub.extract_urls(soh_prefixed()), ","), "")
    Unit <- E.must_eq("open collects exact ordinary link", String.join(Sub.extract_urls("see " ++ page()), ","), page())
    Unit <- E.must_eq("leading style still fetches", String.join(C.targets(stx() ++ page()), ","), page())
    Unit <- E.must_eq("bare duplicate kept past image intent", String.join(C.targets("![a](" ++ doc() ++ ") or " ++ doc()), ","), doc())
    Unit <- E.must_eq("extract shares url_runs negatives", String.join(Ws.extract(styled_infix()), ",") ++ "|" ++ String.join(Ws.extract(soh_prefixed()), ","), "|")
    Unit <- E.must("image-intent run is media", M.media_run_hit("![a](", doc(), [Ws.SRun{0, 0, False{}, ")", None{}}]))
    Unit <- E.must("bare run is not media", Bool.not(M.media_run_hit(" or ", doc(), [Ws.SRun{0, 0, False{}, "", None{}}])))
    # ---- live Session scheduling ----
    Unit <- E.must_eq("online schedules visible page", Nat.show(cards_pending(observed())), "1")
    Unit <- E.must_eq("demo schedules nothing", Nat.show(cards_pending(Sess.session_observe_visible_cards(demo()))), "0")
    Unit <- E.must_eq("stopping schedules nothing", Nat.show(cards_pending(Sess.session_observe_visible_cards(stopping()))), "0")
    Unit <- E.must_eq("env-off mapping", Bool.pick(String, CN.cards_enabled.got(Done{"off"}), "on", "off"), "off")
    Unit <- E.must_eq("env unset stays on", Bool.pick(String, CN.cards_enabled.got(Fail{(2, "no")}), "on", "off"), "on")
    +off : Sess.Session = Sess.session_set_cards(online(), C.set_enabled(Sess.session_cards(online()), False{}))
    Unit <- E.must_eq("disabled schedules nothing", Nat.show(cards_pending(Sess.session_observe_visible_cards(off))), "0")
    Unit <- E.must_eq("disabled starts zero helpers", take_shape(off), "none")
    Unit <- E.must_eq("enabled starts exact one", take_shape(observed()), "1:1:" ++ page())
    Unit <- E.must_eq("worker starts exact job", take_shape(observed()), "1:1:" ++ page())
    Unit <- E.must_eq("one worker only", take_shape(took()), "none")
    Unit <- E.must_eq("idle takes nothing", take_shape(online()), "none")
    Unit <- E.must("stopping forbids jobs", Bool.not(Sess.session_cards_job_allowed(stopping())))
    Unit <- E.must("online allows jobs", Sess.session_cards_job_allowed(online()))
    # ---- completion admission at completion time ----
    Unit <- E.must("exact completion accepted", Sess.session_accept_card_result(took(), 1n, 1n, page()))
    Unit <- E.must("wrong ticket rejected", Bool.not(Sess.session_accept_card_result(took(), 1n, 2n, page())))
    Unit <- E.must("wrong generation rejected", Bool.not(Sess.session_accept_card_result(took(), 2n, 1n, page())))
    Unit <- E.must("wrong URL rejected", Bool.not(Sess.session_accept_card_result(took(), 1n, 1n, doc())))
    Unit <- E.must_eq("accepted completion repaints", on_card_repaint(CN.on_card_session(True{}, took(), 1n, 1n, page(), "T\nD\n")), "repaint")
    Unit <- E.must_eq("accepted stores", Nat.show(cards_ready(on_card_st(CN.on_card_session(True{}, took(), 1n, 1n, page(), "T\nD\n")))), "1")
    Unit <- E.must_eq("stale completion stays quiet", on_card_repaint(CN.on_card_session(False{}, took(), 1n, 1n, page(), "T\nD\n")), "quiet")
    Unit <- E.must_eq("stale stores nothing", Nat.show(cards_ready(on_card_st(CN.on_card_session(False{}, took(), 1n, 1n, page(), "T\nD\n")))), "0")
    Unit <- E.must_eq("stale keeps worker until exact release", take_shape(on_card_st(CN.on_card_session(False{}, took(), 1n, 1n, page(), "T\nD\n"))), "none")
    +gone : Sess.Session = Sess.session_set_client(took(), Cl.init("me", "s"))
    Unit <- E.must("removed source rejected at completion", Bool.not(Sess.session_accept_card_result(gone, 1n, 1n, page())))
    Unit <- E.must_eq("removed source stores nothing", Nat.show(cards_ready(on_card_st(CN.on_card_session(Sess.session_accept_card_result(gone, 1n, 1n, page()), gone, 1n, 1n, page(), "T\nD\n")))), "0")
    Unit <- E.must_eq("settle never schedules", Nat.show(cards_pending(Sess.session_observe_cards(online()))), "0")
    # ---- endpoint transitions: exact host+port reset, same-endpoint retain ----
    +moved : Sess.Session = stepped_st(Sess.step_enter(Sess.session_online(Sess.session_with_client_at(link_client(), "#t", 6697)), "/connect other.example"))
    Unit <- E.must_eq("different host drops pending", Nat.show(cards_pending(moved)), "0")
    +moved_ready : Sess.Session = stepped_st(Sess.step_enter(Sess.session_set_cards(Sess.session_online(Sess.session_with_client_at(link_client(), "#t", 6697)), cards_with_ready()), "/connect other.example"))
    Unit <- E.must_eq("different host drops ready", Nat.show(cards_ready(moved_ready)), "0")
    Unit <- E.must("different host bumps generation", Nat.is_gt(cards_gen(moved_ready), 1n))
    Unit <- E.must("different host closes overlay", Bool.not(full_open(moved_ready)))
    +report : Sess.Session = stepped_st(Sess.step_enter(Sess.session_online(Sess.session_with_client_at(Cl.init("me", "old.example"), "#t", 7000)), "/connect old.example:7001"))
    Unit <- E.must("different port resets", Nat.is_gt(cards_gen(report), 1n))
    +same : Sess.Session = stepped_st(Sess.step_enter(Sess.session_online(Sess.session_with_client_at(Cl.init("me", "old.example"), "#t", 7000)), "/reconnect"))
    Unit <- E.must_eq("same reconnect keeps generation", Nat.show(cards_gen(same)), "1")
    +same_ready : Sess.Session = stepped_st(Sess.step_enter(Sess.session_set_cards(Sess.session_online(Sess.session_with_client_at(Cl.buf_set_lines_at(Cl.init("me", "old.example"), 0n, [Cl.Line{Cl.Msg{}, "", "see " ++ page(), "alice", 1n}]), "#t", 7000)), cards_with_ready()), "/reconnect"))
    Unit <- E.must_eq("same reconnect retains text cards", Nat.show(cards_ready(same_ready)), "1")
    Unit <- E.must_eq("same reconnect resets media", Nat.show(Nat.add(M.pending_count(Sess.session_media(same_ready)), M.ready_count(Sess.session_media(same_ready)))), "0")
    Unit <- E.must("same reconnect bumps media generation", Nat.is_gt(M.generation(Sess.session_media(same_ready)), 1n))
    # In-flight worker across transitions: retained until its exact completion.
    +moved_busy : Sess.Session = stepped_st(Sess.step_enter(Sess.session_set_cards(Sess.session_online(Sess.session_with_client_at(link_client(), "#t", 6697)), Sess.session_cards(took())), "/connect other.example"))
    Unit <- E.must_eq("reset starts no second worker", take_shape(moved_busy), "none")
    Unit <- E.must_eq("endpoint late completion stays quiet", on_card_repaint(CN.on_card_session(Sess.session_accept_card_result(moved_busy, 1n, 1n, page()), moved_busy, 1n, 1n, page(), "T\nD\n")), "quiet")
    Unit <- E.must_eq("endpoint late completion stores nothing", Nat.show(cards_ready(on_card_st(CN.on_card_session(Sess.session_accept_card_result(moved_busy, 1n, 1n, page()), moved_busy, 1n, 1n, page(), "T\nD\n")))), "0")
    +same_busy : Sess.Session = stepped_st(Sess.step_enter(Sess.session_set_cards(Sess.session_online(Sess.session_with_client_at(Cl.buf_set_lines_at(Cl.init("me", "old.example"), 0n, [Cl.Line{Cl.Msg{}, "", "see " ++ page(), "alice", 1n}]), "#t", 7000)), Sess.session_cards(took())), "/reconnect"))
    Unit <- E.must("same reconnect keeps worker identity", Sess.session_accept_card_result(same_busy, 1n, 1n, page()))
    Unit <- E.must_eq("same reconnect completion repaints", on_card_repaint(CN.on_card_session(Sess.session_accept_card_result(same_busy, 1n, 1n, page()), same_busy, 1n, 1n, page(), "T\nD\n")), "repaint")
    Unit <- E.must_eq("disabled keeps worker until release", take_shape(Sess.session_set_cards(took(), C.set_enabled(Sess.session_cards(took()), False{}))), "none")
    Unit <- E.must_eq("disabled completion stays quiet", on_card_repaint(CN.on_card_session(Sess.session_accept_card_result(Sess.session_set_cards(took(), C.set_enabled(Sess.session_cards(took()), False{})), 1n, 1n, page()), Sess.session_set_cards(took(), C.set_enabled(Sess.session_cards(took()), False{})), 1n, 1n, page(), "T\nD\n")), "quiet")
    # ---- fullscreen binding and paint revalidation ----
    Unit <- E.must_eq("F9 without token stays closed", fs_handled(Sess.session_fullscreen_key(online(), Sess.KEY_F9(), 0)), "handled")
    Unit <- E.must("F9 without token opens nothing", Bool.not(fs_open(Sess.session_fullscreen_key(online(), Sess.KEY_F9(), 0))))
    Unit <- E.must("accepted token opens on F9", fs_open(Sess.session_fullscreen_key(media_online(), Sess.KEY_F9(), 0)))
    +fs_opened : Sess.Session = fs_st(Sess.session_fullscreen_key(media_online(), Sess.KEY_F9(), 0))
    Unit <- E.must_eq("overlay covers body", overlay_of(fs_opened, 24, 80), "box:0,1,62,23;media:1,2,60,21,0,21,7;")
    Unit <- E.must("F9 toggles closed", Bool.not(fs_open(Sess.session_fullscreen_key(fs_opened, Sess.KEY_F9(), 0))))
    Unit <- E.must_eq("Escape closes overlay", fs_handled(Sess.session_fullscreen_key(fs_opened, Sess.KEY_ESCAPE(), 0)), "handled")
    Unit <- E.must("Escape leaves no overlay", Bool.not(fs_open(Sess.session_fullscreen_key(fs_opened, Sess.KEY_ESCAPE(), 0))))
    Unit <- E.must_eq("Escape without overlay falls through", fs_handled(Sess.session_fullscreen_key(online(), Sess.KEY_ESCAPE(), 0)), "ignored")
    Unit <- E.must_eq("F9 with mods ignored", fs_handled(Sess.session_fullscreen_key(media_online(), Sess.KEY_F9(), 1)), "ignored")
    Unit <- E.must_eq("fullscreen pick is newest alive", pick_shape(M.fullscreen_pick(ready_media(), img_client())), "1:" ++ image())
    Unit <- E.must_eq("fullscreen pick skips dead", pick_shape(M.fullscreen_pick(ready_media(), Cl.init("me", "s"))), "none")
    +retokened : Sess.Session = Sess.session_set_media(fs_opened, M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, image(), 9}], M.Supported{}})
    Unit <- E.must_eq("stale token paints nothing", overlay_of(retokened, 24, 80), "")
    +unsupported : Sess.Session = Sess.session_set_media(fs_opened, M.set_supported(ready_media(), False{}))
    Unit <- E.must_eq("unsupported paints nothing", overlay_of(unsupported, 24, 80), "")
    Unit <- E.must("F9 without support opens nothing", Bool.not(fs_open(Sess.session_fullscreen_key(unsupported, Sess.KEY_F9(), 0))))
    +unlinked : Sess.Session = Sess.session_set_client(fs_opened, Cl.init("me", "s"))
    Unit <- E.must_eq("removed source paints nothing", overlay_of(unlinked, 24, 80), "")
    # ---- card rows: paint and navigation share one wrapped row set ----
    +line1 : Cl.Line = Cl.Line{Cl.Msg{}, "", "see " ++ page(), "alice", 1n}
    Unit <- E.must_eq("unknown target paints nothing", Nat.show(List.length(&2, V.BodyRow, V.wrap_line_media_cards(line1, 80, False{}, M.empty(), paint_empty()))), Nat.show(List.length(&2, V.BodyRow, V.wrap_line_media(line1, 80, False{}, M.empty()))))
    Unit <- E.must("ready card paints rows", Nat.is_gt(List.length(&2, V.BodyRow, V.wrap_line_media_cards(line1, 80, False{}, M.empty(), paint_ready())), List.length(&2, V.BodyRow, V.wrap_line_media(line1, 80, False{}, M.empty()))))
    Unit <- E.must("ready card paints title", String.contains(rows_text(V.wrap_line_media_cards(line1, 80, False{}, M.empty(), paint_ready())), "Hello"))
    +anchored_plain : List<&2, V.BodyRow> = V.anchored_bodies(V.anchored_lines_media_cards([line1], "#t", 80, False{}, Nil{}, True{}, True{}, "s", 1n, M.empty(), paint_empty()))
    +anchored_cards : List<&2, V.BodyRow> = V.anchored_bodies(V.anchored_lines_media_cards([line1], "#t", 80, False{}, Nil{}, True{}, True{}, "s", 1n, M.empty(), paint_ready()))
    Unit <- E.must("anchors include card rows", Nat.is_gt(List.length(&2, V.BodyRow, anchored_cards), List.length(&2, V.BodyRow, anchored_plain)))
    # Two chat rows plus two card rows under id2; rows=7 gives a 3-row
    # viewport, so id1 stays visible only when card rows are absent. The
    # candidate layer still lists the ready id2 (enqueue skips known URLs).
    Unit <- E.must_eq("painted rows push edge line out", cand_ids(C.visible_candidates_cards_cm(Cl.dflt_cm(), lines2_client(), 7, 80, Sp.Off{}, M.empty(), paint_id2())), "2")
    Unit <- E.must_eq("bare rows keep edge line", cand_ids(C.visible_candidates_cards_cm(Cl.dflt_cm(), lines2_client(), 7, 80, Sp.Off{}, M.empty(), paint_empty())), "2|1")
    Unit <- E.must_eq("painted rows schedule nothing new", Nat.show(C.pending_count(C.enqueue_candidates(C.visible_candidates_cards_cm(Cl.dflt_cm(), lines2_client(), 7, 80, Sp.Off{}, M.empty(), paint_id2()), cards_ready_id2()))), "0")
    Unit <- E.must_eq("bare rows schedule edge line", Nat.show(C.pending_count(C.enqueue_candidates(C.visible_candidates_cards_cm(Cl.dflt_cm(), lines2_client(), 7, 80, Sp.Off{}, M.empty(), paint_empty()), cards_ready_id2()))), "1")
    # ---- union cm: cards schedule the negotiated paint rows, not default RFC ----
    # Narrow: paint retains newest a[b, hiding the older bob URL, so nothing
    # enqueues. Default RFC mutes the newest and leaks the offscreen URL.
    Unit <- E.must_eq("cm narrow paints newest only", cand_ids(C.visible_candidates_cards_cm("ascii", cm_muted_client(), 5, 80, Sp.Off{}, M.empty(), paint_empty())), "")
    Unit <- E.must_eq("default-RFC narrow leaks offscreen url", cand_ids(C.visible_candidates_cards_cm(Cl.dflt_cm(), cm_muted_client(), 5, 80, Sp.Off{}, M.empty(), paint_empty())), "1")
    Unit <- E.must_eq("cm narrow schedules nothing", Nat.show(cards_pending(Sess.session_observe_visible_cards(cm_narrow()))), "0")
    # Wide: both rows painted, so the older URL enqueues exactly.
    Unit <- E.must_eq("cm wide admits painted url", cand_ids(C.visible_candidates_cards_cm("ascii", cm_muted_client(), 24, 80, Sp.Off{}, M.empty(), paint_empty())), "1")
    Unit <- E.must_eq("cm wide schedules painted url", Nat.show(cards_pending(Sess.session_observe_visible_cards(cm_wide()))), "1")
    Unit <- E.must_eq("cm wide takes exact url", take_shape(Sess.session_observe_visible_cards(cm_wide())), "1:1:" ++ page())
    # ---- wire preservation across the Session-field merge ----
    +room : Cl.Client = Cl.init("me", "irc.example")
    +live : Sess.Session = Sess.session_online(Sess.session_with_client(room, "#t"))
    +live_cards : Sess.Session = Sess.session_set_cards(Sess.session_set_full(live, C.FullOff{}), cards_with_ready())
    Unit <- E.must_eq("key-step outs ignore cards", trip_wire(Sess.step_keys(live_cards, Sess.keys_enter("hello"))), trip_wire(Sess.step_keys(live, Sess.keys_enter("hello"))))
    Unit <- E.must_eq("chunk outs ignore cards", chunk_outs(Sess.step_on_chunk_ms(live_cards, Fr.string_to_octets("PING :abc\r\n"), 0)), chunk_outs(Sess.step_on_chunk_ms(live, Fr.string_to_octets("PING :abc\r\n"), 0)))
    # ---- GATE1 overlay scheduling: maintain_full first, schedule only when closed ----
    Unit <- E.must("gate1 media fs opens", full_open(gate1_media_fs()))
    Unit <- E.must("gate1 cards fs opens", full_open(gate1_cards_fs()))
    Unit <- E.must_eq("gate1 media open schedules nothing new", Nat.show(media_pending(Sess.session_observe_visible_media(gate1_media_fs()))), "0")
    Unit <- E.must_eq("gate1 cards open schedules nothing new", Nat.show(cards_pending(Sess.session_observe_visible_cards(gate1_cards_fs()))), "0")
    Unit <- E.must("gate1 media open forbids jobs", Bool.not(Sess.session_media_job_allowed(gate1_media_fs())))
    Unit <- E.must("gate1 cards open forbids jobs", Bool.not(Sess.session_cards_job_allowed(gate1_cards_fs())))
    Unit <- E.must("gate1 stale media overlay closes before admission", Bool.not(full_open(Sess.session_observe_visible_media(gate1_stale_media()))))
    Unit <- E.must_eq("gate1 stale media admits after close", Nat.show(media_pending(Sess.session_observe_visible_media(gate1_stale_media()))), "1")
    Unit <- E.must("gate1 stale cards overlay closes before admission", Bool.not(full_open(Sess.session_observe_visible_cards(gate1_stale_cards()))))
    Unit <- E.must_eq("gate1 stale cards admits after close", Nat.show(cards_pending(Sess.session_observe_visible_cards(gate1_stale_cards()))), "1")
    # ---- GATE1 Session key close (pure session_fullscreen_key only; native key qualification stays PTY): Esc/F9 close re-admits visible unmuted once ----
    Unit <- E.must_eq("gate1 media esc close handled", fs_handled(Sess.session_fullscreen_key(gate1_media_fs(), Sess.KEY_ESCAPE(), 0)), "handled")
    Unit <- E.must("gate1 media esc closes overlay", Bool.not(full_open(gate1_media_closed())))
    Unit <- E.must("gate1 media f9 closes overlay", Bool.not(full_open(gate1_media_closed_f9())))
    Unit <- E.must_eq("gate1 cards esc close handled", fs_handled(Sess.session_fullscreen_key(gate1_cards_fs(), Sess.KEY_ESCAPE(), 0)), "handled")
    Unit <- E.must("gate1 cards esc closes overlay", Bool.not(full_open(gate1_cards_closed())))
    Unit <- E.must("gate1 cards f9 closes overlay", Bool.not(full_open(gate1_cards_closed_f9())))
    Unit <- E.must_eq("gate1 media close admits visible once", Nat.show(media_pending(gate1_media_admitted())), "1")
    Unit <- E.must("gate1 media close allows jobs", Sess.session_media_job_allowed(gate1_media_admitted()))
    Unit <- E.must_eq("gate1 media close takes exact job", media_take_shape(gate1_media_admitted()), "1:2:https://x.test/b.png")
    Unit <- E.must_eq("gate1 media close second take none", media_take_shape(media_taken(gate1_media_admitted())), "none")
    Unit <- E.must_eq("gate1 media close re-observe still once", Nat.show(media_pending(Sess.session_observe_visible_media(gate1_media_admitted()))), "1")
    Unit <- E.must_eq("gate1 media f9 close admits visible once", Nat.show(media_pending(Sess.session_observe_visible_media(gate1_media_closed_f9()))), "1")
    Unit <- E.must_eq("gate1 cards close admits visible once", Nat.show(cards_pending(gate1_cards_admitted())), "1")
    Unit <- E.must("gate1 cards close allows jobs", Sess.session_cards_job_allowed(gate1_cards_admitted()))
    Unit <- E.must_eq("gate1 cards close takes exact job", take_shape(gate1_cards_admitted()), "1:1:" ++ page())
    Unit <- E.must_eq("gate1 cards close second take none", take_shape(gate5_taken(gate1_cards_admitted())), "none")
    Unit <- E.must_eq("gate1 cards close re-observe still once", Nat.show(cards_pending(Sess.session_observe_visible_cards(gate1_cards_admitted()))), "1")
    Unit <- E.must_eq("gate1 cards f9 close admits visible once", Nat.show(cards_pending(Sess.session_observe_visible_cards(gate1_cards_closed_f9()))), "1")
    Unit <- E.must("gate1 media muted fs opens", full_open(gate1_media_muted_fs()))
    Unit <- E.must_eq("gate1 media muted close admits nothing", Nat.show(media_pending(gate1_media_muted_admitted())), "0")
    Unit <- E.must("gate1 cards muted fs opens", full_open(gate1_cards_muted_fs()))
    Unit <- E.must_eq("gate1 cards muted close admits nothing", Nat.show(cards_pending(gate1_cards_muted_admitted())), "0")
    # ---- GATE3 parser: one Ws boundary owner ----
    Unit <- E.must_eq("gate3 full styled page exact", String.join(C.targets(stx() ++ page() ++ stx()), ","), page())
    Unit <- E.must_eq("gate3 full styled image exact", String.join(M.targets(stx() ++ image() ++ stx()), ","), image())
    Unit <- E.must_eq("gate3 query exact", String.join(C.targets("see " ++ gate3_query()), ","), gate3_query())
    Unit <- E.must_eq("gate3 completed boundary space eligible", String.join(C.targets(page() ++ stx() ++ " end"), ","), page())
    Unit <- E.must_eq("gate3 glued x stx refused", String.join(C.targets("x" ++ stx() ++ page()), ","), "")
    Unit <- E.must_eq("gate3 png stx query refused", String.join(M.targets(image() ++ stx() ++ "?token=1"), ","), "")
    Unit <- E.must_eq("gate3 soh infix refused", String.join(C.targets("https://x.test/re" ++ soh() ++ "ad"), ","), "")
    Unit <- E.must_eq("gate3 esc infix refused", String.join(C.targets("https://x.test/re" ++ esc() ++ "ad"), ","), "")
    Unit <- E.must_eq("gate3 slash continuation refused", String.join(C.targets("https://x.test/re" ++ stx() ++ "/ad"), ","), "")
    Unit <- E.must("gate3 proof shares Ws boundary", Bool.not(VL.tokenize_has_link("x" ++ stx() ++ page())))
    # ---- GATE5 lease pair: reset retains worker, exact-old releases, exact-new stores ----
    Unit <- E.must_eq("gate5 pure wrong gen keeps pending", Nat.show(C.pending_count(C.complete(gate5_reset_queued(), link_client(), 3n, 2n, page(), "T\nD\n"))), "1")
    Unit <- E.must_eq("gate5 pure wrong ticket keeps pending", Nat.show(C.pending_count(C.complete(gate5_reset_queued(), link_client(), 2n, 9n, page(), "T\nD\n"))), "1")
    Unit <- E.must_eq("gate5 pure wrong url keeps pending", Nat.show(C.pending_count(C.complete(gate5_reset_queued(), link_client(), 2n, 2n, doc(), "T\nD\n"))), "1")
    Unit <- E.must_eq("gate5 pure wrong keeps worker", gate5_job_of(C.take_job(C.complete(gate5_reset_queued(), link_client(), 3n, 2n, page(), "T\nD\n"))), "none")
    Unit <- E.must_eq("gate5 pure exact-old keeps pending", Nat.show(C.pending_count(C.complete(gate5_reset_queued(), link_client(), 1n, 1n, page(), "T\nD\n"))), "1")
    Unit <- E.must_eq("gate5 pure exact-old stores nothing", Nat.show(C.ready_count(C.complete(gate5_reset_queued(), link_client(), 1n, 1n, page(), "T\nD\n"))), "0")
    Unit <- E.must_eq("gate5 pure take g2 once", gate5_job_of(C.take_job(C.complete(gate5_reset_queued(), link_client(), 1n, 1n, page(), "T\nD\n"))), "2:2:" ++ page())
    Unit <- E.must_eq("gate5 pure second take none", gate5_job_of(C.take_job(gate5_state_of(C.take_job(C.complete(gate5_reset_queued(), link_client(), 1n, 1n, page(), "T\nD\n"))))), "none")
    Unit <- E.must_eq("gate5 pure exact-new stores", Nat.show(C.ready_count(C.complete(gate5_state_of(C.take_job(C.complete(gate5_reset_queued(), link_client(), 1n, 1n, page(), "T\nD\n"))), link_client(), 2n, 2n, page(), "T\nD\n"))), "1")
    +g5sess : Sess.Session = gate5_queued_session()
    Unit <- E.must_eq("gate5 sess wrong gen retains", Nat.show(cards_pending(on_card_st(CN.on_card_session(Sess.session_accept_card_result(g5sess, 3n, 2n, page()), g5sess, 3n, 2n, page(), "T\nD\n")))), "1")
    Unit <- E.must_eq("gate5 sess wrong ticket retains", Nat.show(cards_pending(on_card_st(CN.on_card_session(Sess.session_accept_card_result(g5sess, 2n, 9n, page()), g5sess, 2n, 9n, page(), "T\nD\n")))), "1")
    Unit <- E.must_eq("gate5 sess wrong url retains", Nat.show(cards_pending(on_card_st(CN.on_card_session(Sess.session_accept_card_result(g5sess, 2n, 2n, doc()), g5sess, 2n, 2n, doc(), "T\nD\n")))), "1")
    Unit <- E.must_eq("gate5 sess wrong stays quiet", on_card_repaint(CN.on_card_session(Sess.session_accept_card_result(g5sess, 3n, 2n, page()), g5sess, 3n, 2n, page(), "T\nD\n")), "quiet")
    +g5old : Sess.Session = on_card_st(CN.on_card_session(Sess.session_accept_card_result(g5sess, 1n, 1n, page()), g5sess, 1n, 1n, page(), "T\nD\n"))
    Unit <- E.must_eq("gate5 sess exact stale keeps pending", Nat.show(cards_pending(g5old)), "1")
    Unit <- E.must_eq("gate5 sess exact stale stores nothing", Nat.show(cards_ready(g5old)), "0")
    Unit <- E.must_eq("gate5 sess exact stale stays quiet", on_card_repaint(CN.on_card_session(Sess.session_accept_card_result(g5sess, 1n, 1n, page()), g5sess, 1n, 1n, page(), "T\nD\n")), "quiet")
    Unit <- E.must_eq("gate5 sess take current once", take_shape(g5old), "2:2:" ++ page())
    Unit <- E.must_eq("gate5 sess next none", take_shape(gate5_taken(g5old)), "none")
    Unit <- E.must_eq("gate5 sess new exact stores", Nat.show(cards_ready(on_card_st(CN.on_card_session(Sess.session_accept_card_result(gate5_taken(g5old), 2n, 2n, page()), gate5_taken(g5old), 2n, 2n, page(), "T\nD\n")))), "1")
    # ---- GATE5 isolation: near-miss wrongs thread through exact-old ----
    Unit <- E.must_eq("gate5 pure iso gen keeps pending", Nat.show(C.pending_count(gate5_pure_wrong(2n, 1n, page()))), "1")
    Unit <- E.must_eq("gate5 pure iso ticket keeps pending", Nat.show(C.pending_count(gate5_pure_wrong(1n, 2n, page()))), "1")
    Unit <- E.must_eq("gate5 pure iso url keeps pending", Nat.show(C.pending_count(gate5_pure_wrong(1n, 1n, doc()))), "1")
    Unit <- E.must_eq("gate5 pure iso gen stores nothing", Nat.show(C.ready_count(gate5_pure_wrong(2n, 1n, page()))), "0")
    Unit <- E.must_eq("gate5 pure iso ticket stores nothing", Nat.show(C.ready_count(gate5_pure_wrong(1n, 2n, page()))), "0")
    Unit <- E.must_eq("gate5 pure iso url stores nothing", Nat.show(C.ready_count(gate5_pure_wrong(1n, 1n, doc()))), "0")
    Unit <- E.must_eq("gate5 pure iso gen keeps worker", gate5_job_of(C.take_job(gate5_pure_wrong(2n, 1n, page()))), "none")
    Unit <- E.must_eq("gate5 pure iso ticket keeps worker", gate5_job_of(C.take_job(gate5_pure_wrong(1n, 2n, page()))), "none")
    Unit <- E.must_eq("gate5 pure iso url keeps worker", gate5_job_of(C.take_job(gate5_pure_wrong(1n, 1n, doc()))), "none")
    Unit <- E.must_eq("gate5 pure iso gen old keeps pending", Nat.show(C.pending_count(gate5_pure_iso_old(gate5_pure_wrong(2n, 1n, page())))), "1")
    Unit <- E.must_eq("gate5 pure iso ticket old keeps pending", Nat.show(C.pending_count(gate5_pure_iso_old(gate5_pure_wrong(1n, 2n, page())))), "1")
    Unit <- E.must_eq("gate5 pure iso url old keeps pending", Nat.show(C.pending_count(gate5_pure_iso_old(gate5_pure_wrong(1n, 1n, doc())))), "1")
    Unit <- E.must_eq("gate5 pure iso gen old stores nothing", Nat.show(C.ready_count(gate5_pure_iso_old(gate5_pure_wrong(2n, 1n, page())))), "0")
    Unit <- E.must_eq("gate5 pure iso ticket old stores nothing", Nat.show(C.ready_count(gate5_pure_iso_old(gate5_pure_wrong(1n, 2n, page())))), "0")
    Unit <- E.must_eq("gate5 pure iso url old stores nothing", Nat.show(C.ready_count(gate5_pure_iso_old(gate5_pure_wrong(1n, 1n, doc())))), "0")
    Unit <- E.must_eq("gate5 pure iso gen take once", gate5_job_of(C.take_job(gate5_pure_iso_old(gate5_pure_wrong(2n, 1n, page())))), "2:2:" ++ page())
    Unit <- E.must_eq("gate5 pure iso ticket take once", gate5_job_of(C.take_job(gate5_pure_iso_old(gate5_pure_wrong(1n, 2n, page())))), "2:2:" ++ page())
    Unit <- E.must_eq("gate5 pure iso url take once", gate5_job_of(C.take_job(gate5_pure_iso_old(gate5_pure_wrong(1n, 1n, doc())))), "2:2:" ++ page())
    Unit <- E.must_eq("gate5 pure iso gen second none", gate5_job_of(C.take_job(gate5_pure_iso_taken(gate5_pure_wrong(2n, 1n, page())))), "none")
    Unit <- E.must_eq("gate5 pure iso ticket second none", gate5_job_of(C.take_job(gate5_pure_iso_taken(gate5_pure_wrong(1n, 2n, page())))), "none")
    Unit <- E.must_eq("gate5 pure iso url second none", gate5_job_of(C.take_job(gate5_pure_iso_taken(gate5_pure_wrong(1n, 1n, doc())))), "none")
    Unit <- E.must_eq("gate5 pure iso gen new stores", Nat.show(gate5_pure_iso_new_ready(gate5_pure_wrong(2n, 1n, page()))), "1")
    Unit <- E.must_eq("gate5 pure iso ticket new stores", Nat.show(gate5_pure_iso_new_ready(gate5_pure_wrong(1n, 2n, page()))), "1")
    Unit <- E.must_eq("gate5 pure iso url new stores", Nat.show(gate5_pure_iso_new_ready(gate5_pure_wrong(1n, 1n, doc()))), "1")
    Unit <- E.must_eq("gate5 sess iso gen retains", Nat.show(cards_pending(gate5_sess_wrong(g5sess, 2n, 1n, page()))), "1")
    Unit <- E.must_eq("gate5 sess iso ticket retains", Nat.show(cards_pending(gate5_sess_wrong(g5sess, 1n, 2n, page()))), "1")
    Unit <- E.must_eq("gate5 sess iso url retains", Nat.show(cards_pending(gate5_sess_wrong(g5sess, 1n, 1n, doc()))), "1")
    Unit <- E.must_eq("gate5 sess iso gen stores nothing", Nat.show(cards_ready(gate5_sess_wrong(g5sess, 2n, 1n, page()))), "0")
    Unit <- E.must_eq("gate5 sess iso ticket stores nothing", Nat.show(cards_ready(gate5_sess_wrong(g5sess, 1n, 2n, page()))), "0")
    Unit <- E.must_eq("gate5 sess iso url stores nothing", Nat.show(cards_ready(gate5_sess_wrong(g5sess, 1n, 1n, doc()))), "0")
    Unit <- E.must_eq("gate5 sess iso gen stays quiet", gate5_sess_wrong_repaint(g5sess, 2n, 1n, page()), "quiet")
    Unit <- E.must_eq("gate5 sess iso ticket stays quiet", gate5_sess_wrong_repaint(g5sess, 1n, 2n, page()), "quiet")
    Unit <- E.must_eq("gate5 sess iso url stays quiet", gate5_sess_wrong_repaint(g5sess, 1n, 1n, doc()), "quiet")
    Unit <- E.must_eq("gate5 sess iso gen worker kept", take_shape(gate5_sess_wrong(g5sess, 2n, 1n, page())), "none")
    Unit <- E.must_eq("gate5 sess iso ticket worker kept", take_shape(gate5_sess_wrong(g5sess, 1n, 2n, page())), "none")
    Unit <- E.must_eq("gate5 sess iso url worker kept", take_shape(gate5_sess_wrong(g5sess, 1n, 1n, doc())), "none")
    Unit <- E.must_eq("gate5 sess iso gen old keeps pending", Nat.show(cards_pending(gate5_sess_iso_old(g5sess, 2n, 1n, page()))), "1")
    Unit <- E.must_eq("gate5 sess iso ticket old keeps pending", Nat.show(cards_pending(gate5_sess_iso_old(g5sess, 1n, 2n, page()))), "1")
    Unit <- E.must_eq("gate5 sess iso url old keeps pending", Nat.show(cards_pending(gate5_sess_iso_old(g5sess, 1n, 1n, doc()))), "1")
    Unit <- E.must_eq("gate5 sess iso gen old stores nothing", Nat.show(cards_ready(gate5_sess_iso_old(g5sess, 2n, 1n, page()))), "0")
    Unit <- E.must_eq("gate5 sess iso ticket old stores nothing", Nat.show(cards_ready(gate5_sess_iso_old(g5sess, 1n, 2n, page()))), "0")
    Unit <- E.must_eq("gate5 sess iso url old stores nothing", Nat.show(cards_ready(gate5_sess_iso_old(g5sess, 1n, 1n, doc()))), "0")
    Unit <- E.must_eq("gate5 sess iso gen take once", take_shape(gate5_sess_iso_old(g5sess, 2n, 1n, page())), "2:2:" ++ page())
    Unit <- E.must_eq("gate5 sess iso ticket take once", take_shape(gate5_sess_iso_old(g5sess, 1n, 2n, page())), "2:2:" ++ page())
    Unit <- E.must_eq("gate5 sess iso url take once", take_shape(gate5_sess_iso_old(g5sess, 1n, 1n, doc())), "2:2:" ++ page())
    Unit <- E.must_eq("gate5 sess iso gen next none", take_shape(gate5_sess_iso_taken(g5sess, 2n, 1n, page())), "none")
    Unit <- E.must_eq("gate5 sess iso ticket next none", take_shape(gate5_sess_iso_taken(g5sess, 1n, 2n, page())), "none")
    Unit <- E.must_eq("gate5 sess iso url next none", take_shape(gate5_sess_iso_taken(g5sess, 1n, 1n, doc())), "none")
    Unit <- E.must_eq("gate5 sess iso gen new stores", Nat.show(gate5_sess_iso_new_ready(g5sess, 2n, 1n, page())), "1")
    Unit <- E.must_eq("gate5 sess iso ticket new stores", Nat.show(gate5_sess_iso_new_ready(g5sess, 1n, 2n, page())), "1")
    Unit <- E.must_eq("gate5 sess iso url new stores", Nat.show(gate5_sess_iso_new_ready(g5sess, 1n, 1n, doc())), "1")
    IO.print("cards_live=ok")
