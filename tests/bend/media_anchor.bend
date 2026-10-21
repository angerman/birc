# SPDX-License-Identifier: Apache-2.0
# Manual synthetic rows and ordinary inline rows share append-safe anchors.
import Base
import ./expect.bend as E
import ./ascii_row_projection.bend as P
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V
import ../../src/bend/session.bend as Sess
import ../../src/bend/submit.bend as Sub
import ../../src/bend/split.bend as Sp
import ../../src/bend/history.bend as H

def url() -> String:
  "https://x/a.png"

def inline_text() -> String:
  "alice: **bold** :eyes: " ++ url()

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def active_buf(cl: Cl.Client) -> Cl.Buffer:
  match cl:
    case Cl.Client{_, _, bufs, active, _, _, _, _, _}: V.active_buf.on(Cl.nth_buf(bufs, active))

def active_media() -> M.State:
  M.State{False{}, 1n, 2n, Some{M.Request{M.Manual{}, url(), 1n, 1n}}, Nil{}, Nil{}, M.Supported{}}

def ready_inline() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, url(), 9}], M.Supported{}}

def manual_session() -> Sess.Session:
  Sess.session_set_media(Sess.session_demo(client(Sub.submit(Cl.init("me", "s"), "/preview " ++ url())), ""), active_media())

type SBox is Data:
  SBox{cell: List<&2, Sess.Session>}

# Singleton-list box: a live Session flattens to dozens of words, so the
# four Sessions held across manual_controls breach the 247-word native
# continuation limit ("an arity over 247"). Boxing keeps bind captures
# narrow (session_drafts_demo idiom); use sites unbox transiently. The
# Nil arm is unreachable by construction.
def sbox(+st: Sess.Session) -> SBox:
  SBox{st <> Nil{}}

def sunbox.cell(+cell: List<&2, Sess.Session>) -> Sess.Session:
  match cell:
    case Con{+st, _}: st
    case Nil{}: Sess.session_fail(manual_session(), "unreachable")

def sunbox(+b: SBox) -> Sess.Session:
  match b:
    case SBox{+cell}: sunbox.cell(cell)

type CBox is Data:
  CBox{cell: List<&2, Cl.Client>}

# A split Client embeds both panes. Two live Clients across split_controls
# sit in the same continuation class as the Session overflow above.
def cbox(+cl: Cl.Client) -> CBox:
  CBox{cl <> Nil{}}

def cunbox.cell(+cell: List<&2, Cl.Client>) -> Cl.Client:
  match cell:
    case Con{+cl, _}: cl
    case Nil{}: Cl.init("me", "s")

def cunbox(+b: CBox) -> Cl.Client:
  match b:
    case CBox{+cell}: cunbox.cell(cell)

def paused_session() -> Sess.Session:
  +st = sbox(manual_session())
  +cl = Sess.session_cl(sunbox(st))
  Sess.session_set_client(sunbox(st), Cl.buf_modify_client(cl, Cl.active_of(cl), b => V.hold_buf(V.scroll_buf_media(b, 2n, 20, False{}, Nil{}, True{}, True{}, "s", 2n, 0n, active_media()))))

def failed_session(+st: Sess.Session) -> Sess.Session:
  Sess.session_error(Sess.session_set_media(st, M.complete(Sess.session_media(st), Sess.session_cl(st), 1n, 1n, url(), 0)), "image preview unavailable")

def state_of(pair: M.State & Maybe<&2, M.Request>) -> M.State:
  match pair:
    case (state, _): state

def retry_session(+st: Sess.Session) -> Sess.Session:
  Sess.session_set_media(st, state_of(M.take_job(M.enqueue(Sess.session_media(st), M.Manual{}, url()))))

def ready_session(+st: Sess.Session) -> Sess.Session:
  Sess.session_set_media(st, M.complete(Sess.session_media(st), Sess.session_cl(st), 1n, 2n, url(), 9))

def anchor(b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, _, _, _, Cl.ScrollAt{after, tail}, _, _}: Nat.show(after) ++ ":" ++ Nat.show(tail)

def shape(xs: List<&2, V.DrawOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.OpMedia{x, y, w, h, clip_y, clip_h, token}, tail}:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(clip_y) ++ "," ++ U32.show(clip_h) ++ "," ++ U32.show(token) ++ ";" ++ shape(tail)
    case Con{_, tail}: shape(tail)

def paint(+b: Cl.Buffer, +media: M.State, +width: U32) -> String:
  shape(V.body_ops(V.Rect{0, 0, U32.add(width, 2), 4}, V.body_of.buf_media(b, 2n, width, False{}, Nil{}, True{}, True{}, "s", media)))

def session_paint(+st: Sess.Session, width: U32) -> String:
  paint(active_buf(Sess.session_cl(st)), Sess.session_media(st), width)

def raw_lines(b: Cl.Buffer) -> List<&2, Cl.Line>:
  match b:
    case Cl.Buffer{_, _, _, lines, _, _, _, _}: lines

def raw_text(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, _, text, _, _}, tail}: text ++ raw_text(tail)

def topic(b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, topic, _, _, _, _, _}: topic

def rows_text(xs: List<&2, V.BodyRow>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.BodyRow{_, _, _, _, _, spans, chars}, tail}: P.show(spans, chars) ++ rows_text(tail)
    case Con{_, tail}: rows_text(tail)

def projection_controls() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("ASCII projection restores hidden word boundary", rows_text(V.wrapped_rows(Cl.System{}, "", "hello   world", 8, False{})), "hello   world")
    Unit <- E.must_eq("ASCII hard-wrap projection does not invent spaces", rows_text(V.wrapped_rows(Cl.System{}, "", "abcdefghijk", 4, False{})), "abcdefghijk")
    Unit <- E.must("ASCII projection rejects non-ASCII clusters", Maybe.is_none(&2, String, P.text([V.Spn{0, "é"}], 2n)))
    Unit <- E.must("ASCII projection rejects non-ASCII replacements", Maybe.is_none(&2, String, P.text([V.Spn{0, "�"}], 3n)))
    Unit <- E.must("ASCII projection rejects invalid source counts", Maybe.is_none(&2, String, P.text([V.Spn{0, "abc"}], 2n)))
    IO.pure(Unit, Unit{})

def inline_paused() -> Cl.Buffer:
  V.hold_buf(V.scroll_buf_media(Cl.buf_indexed("server", False{}, "", [Cl.Line{Cl.Msg{}, "", inline_text(), "alice", 1n}], Nil{}, Cl.ScrollAt{0n, 0n}), 2n, 20, False{}, Nil{}, True{}, True{}, "s", 2n, 0n, ready_inline()))

def first_line(lines: List<&2, Cl.Line>) -> Cl.Line:
  match lines:
    case Nil{}: Cl.Line{Cl.Error{}, "", "missing", "", 0n}
    case Con{h, _}: h

def split_media() -> M.State:
  M.State{True{}, 1n, 3n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, url(), 11}, M.MediaReady{M.Inline{2n}, "https://x/b.gif", 22}], M.Supported{}}

def split_client.of(cl: Cl.Client) -> Cl.Client:
  match cl:
    case Cl.Client{nick, server, _, _, now, stg, auth, _, welcomed}:
      Cl.Client{nick, server,
        [Cl.buf_indexed("server", False{}, "", [Cl.Line{Cl.Msg{}, "", url(), "alice", 1n}], Nil{}, Cl.ScrollAt{0n, 0n}),
         Cl.buf_indexed("#b", True{}, "", [Cl.Line{Cl.Msg{}, "", "https://x/b.gif", "bob", 2n}], Nil{}, Cl.ScrollAt{0n, 0n})],
        0n, now, Cl.set_ts(stg, False{}), auth, 2n, welcomed}

def split_client() -> Cl.Client:
  split_client.of(Cl.init("me", "s"))

def split_state(axis: Sp.Axis, focus: U32) -> Sp.State:
  Sp.On{axis, "*server*", "#b", focus}

def split_paused(+axis: Sp.Axis, +rows: U32) -> Cl.Client:
  +first = cbox(V.scroll_active_media(split_client(), rows, 80, split_state(axis, 0), 1n, 0n, split_media()))
  V.scroll_active_media(Cl.set_active(cunbox(first), 1n), rows, 80, split_state(axis, 1), 2n, 0n, split_media())

def vm_shape(vm: V.ViewModel) -> String:
  match vm:
    case V.ViewModel{ops, _}: shape(ops)

def split_vm(cl: Cl.Client, axis: Sp.Axis, rows: U32, cols: U32) -> V.ViewModel:
  V.view_draft.state_typing_media(cl, rows, cols, "", "online", Nil{}, split_state(axis, 1), split_media())

def split_paint(cl: Cl.Client, axis: Sp.Axis, rows: U32, cols: U32) -> String:
  vm_shape(split_vm(cl, axis, rows, cols))

def vm_ops(vm: V.ViewModel) -> List<&2, V.DrawOp>:
  match vm:
    case V.ViewModel{ops, _}: ops

def medias_of(xs: List<&2, V.DrawOp>) -> List<&2, V.DrawOp>:
  match xs:
    case Nil{}: Nil{}
    case Con{V.OpMedia{x, y, w, h, clip_y, clip_h, token}, t}:
      V.OpMedia{x, y, w, h, clip_y, clip_h, token} <> medias_of(t)
    case Con{_, t}: medias_of(t)

# Painted pixels are the clip, not the full virtual image height.
def clip_inside(op: V.DrawOp) -> Bool:
  match op:
    case V.OpMedia{_, _, _, +h, +clip_y, +clip_h, _}:
      U32.is_gt(clip_h, 0) && U32.is_le(U32.add(clip_y, clip_h), h)
    case _: False{}

def painted_overlap(a: V.DrawOp, b: V.DrawOp) -> Bool:
  match a b:
    case V.OpMedia{+ax, +ay, +aw, _, _, +ah, _} V.OpMedia{+bx, +by, +bw, _, _, +bh, _}:
      U32.is_lt(ax, U32.add(bx, bw)) && U32.is_lt(bx, U32.add(ax, aw)) && U32.is_lt(ay, U32.add(by, bh)) && U32.is_lt(by, U32.add(ay, ah))
    case _ _: True{}

def y_in_inner(op: V.DrawOp, r: V.Rect) -> Bool:
  match op r:
    case V.OpMedia{_, +y, _, _, _, +clip_h, _} V.Rect{_, +ry, _, +rh}:
      U32.is_ge(y, V.inner_min(ry, rh)) && U32.is_le(U32.add(y, clip_h), U32.add(V.inner_last(ry, rh), 1))
    case _ _: False{}

def distinct_pair(xs: List<&2, V.DrawOp>) -> Bool:
  match xs:
    case Con{+a, Con{+b, Nil{}}}: clip_inside(a) && clip_inside(b) && Bool.not(painted_overlap(a, b))
    case _: False{}

def split_panes.or(first: Bool, +a: V.DrawOp, +b: V.DrawOp, +r1: V.Rect, +r2: V.Rect) -> Bool:
  match first:
    case True{}: True{}
    case False{}: y_in_inner(a, r2) && y_in_inner(b, r1)

def split_panes(+a: V.DrawOp, +b: V.DrawOp, +r1: V.Rect, +r2: V.Rect) -> Bool:
  split_panes.or(y_in_inner(a, r1) && y_in_inner(b, r2), a, b, r1, r2)

def panes_of(xs: List<&2, V.DrawOp>, r1: V.Rect, r2: V.Rect) -> Bool:
  match xs:
    case Con{a, Con{b, Nil{}}}: split_panes(a, b, r1, r2)
    case _: False{}

def hist_pair.go(pair: V.Rect & V.Rect) -> V.Rect & V.Rect:
  match pair:
    case (+r1, +r2): (V.body_hist_rect(r1), V.body_hist_rect(r2))

def hist_pair(axis: Sp.Axis, +rows: U32, +cols: U32) -> V.Rect & V.Rect:
  hist_pair.go(V.split_rects(axis, V.lay_body_rect(V.lay(rows, cols, 0))))

def clip_ok.on(ok: Bool, +why: String) -> String:
  match ok:
    case True{}: ""
    case False{}: why

def clip_report.on(pair: V.Rect & V.Rect, +ops: List<&2, V.DrawOp>) -> String:
  match pair:
    case (+r1, +r2):
      clip_ok.on(distinct_pair(ops) && panes_of(ops, r1, r2), "clip")

def clip_report(+cl: Cl.Client, +axis: Sp.Axis, +rows: U32, +cols: U32) -> String:
  clip_report.on(hist_pair(axis, rows, cols), medias_of(vm_ops(split_vm(cl, axis, rows, cols))))

def focus_vis.on(pair: V.Rect & V.Rect, +focus: U32) -> Nat:
  match pair:
    case (+r1, +r2):
      match focus:
        case 0: V.rect_vis_h(r1)
        case _: V.rect_vis_h(r2)

def focus_vis(+rows: U32, +focus: U32, axis: Sp.Axis) -> Nat:
  focus_vis.on(V.split_rects(axis, V.lay_body_rect(V.lay(rows, 80, 0))), focus)

def page_vs_paint(+rows: U32, +axis: Sp.Axis, +focus: U32) -> Bool:
  Nat.is_eq(Sp.page_height(rows, Sp.On{axis, "a", "b", focus}), focus_vis(rows, focus, axis))

def off_vs_paint(+rows: U32) -> Bool:
  Nat.is_eq(Sp.page_height(rows, Sp.Off{}), V.rect_vis_h(V.lay_body_rect(V.lay(rows, 80, 0))))

def first_bad(+a: String, +b: String) -> String:
  match a:
    case SNil{}: b
    case SCon{_, _}: a

def page_bad.on(ok: Bool, +msg: String) -> String:
  match ok:
    case True{}: ""
    case False{}: msg

def page_bad(+rows: U32) -> String:
  first_bad(page_bad.on(page_vs_paint(rows, Sp.Stacked{}, 0), U32.show(rows) ++ ":stack0"),
    first_bad(page_bad.on(page_vs_paint(rows, Sp.Stacked{}, 1), U32.show(rows) ++ ":stack1"),
      first_bad(page_bad.on(page_vs_paint(rows, Sp.SideBySide{}, 0), U32.show(rows) ++ ":side0"),
        first_bad(page_bad.on(page_vs_paint(rows, Sp.SideBySide{}, 1), U32.show(rows) ++ ":side1"),
          page_bad.on(off_vs_paint(rows), U32.show(rows) ++ ":off")))))

def page_sweep.msg(fuel: Nat, +rows: U32) -> String:
  match fuel:
    case 0n: ""
    case 1n+p: first_bad(page_bad(rows), page_sweep.msg(p, U32.add(rows, 1)))

def manual_controls() -> IO(Unit):
  +pending = sbox(paused_session())
  +failed = sbox(failed_session(sunbox(pending)))
  +retry = sbox(retry_session(sunbox(failed)))
  +ready = sbox(ready_session(sunbox(retry)))
  do IO<Unit>:
    Unit <- E.must_eq("pending manual clip", session_paint(sunbox(pending), 20), "1,1,20,6,2,2,0;")
    Unit <- E.must_eq("pending manual anchor", anchor(active_buf(Sess.session_cl(sunbox(pending)))), "0:2")
    Unit <- E.must_eq("failed append counts newer diagnostic", anchor(active_buf(Sess.session_cl(sunbox(failed)))), "1:2")
    Unit <- E.must_eq("failed completion keeps paused image", session_paint(sunbox(failed), 20), "1,1,20,6,2,2,0;")
    Unit <- E.must_eq("identical retry keeps paused image", session_paint(sunbox(retry), 20), "1,1,20,6,2,2,0;")
    Unit <- E.must_eq("successful retry keeps paused image", session_paint(sunbox(ready), 20), "1,1,20,6,2,2,9;")
    Unit <- E.must_eq("failed resize keeps virtual clip", session_paint(sunbox(failed), 40), "1,1,40,6,2,2,0;")
    Unit <- E.must_eq("ready resize keeps virtual clip", session_paint(sunbox(ready), 40), "1,1,40,6,2,2,9;")
    Unit <- E.must_eq("one-cell pane remains bounded", session_paint(sunbox(ready), 1), "1,1,1,6,2,2,9;")
    IO.pure(Unit, Unit{})

def inline_controls() -> IO(Unit):
  +inline = inline_paused()
  +logged = Cl.buf_log(inline, Cl.Error{}, "image preview unavailable")
  do IO<Unit>:
    Unit <- E.must_eq("ordinary inline before", paint(inline, ready_inline(), 20), "1,1,20,6,2,2,9;")
    Unit <- E.must_eq("ordinary inline append still correct", paint(logged, ready_inline(), 20), "1,1,20,6,2,2,9;")
    Unit <- E.must_eq("ordinary inline newer-log anchor", anchor(logged), "1:2")
    Unit <- E.must_eq("inline source stays raw", H.serialize_line("server", first_line(raw_lines(logged))), "server\tMSG\t\t" ++ inline_text() ++ "\n")
    IO.pure(Unit, Unit{})

def source_controls() -> IO(Unit):
  +pending = sbox(paused_session())
  +ready = sbox(ready_session(retry_session(failed_session(sunbox(pending)))))
  +live_error = sbox(failed_session(manual_session()))
  do IO<Unit>:
    Unit <- E.must_eq("manual image never enters raw rows", Nat.show(List.length(&2, Cl.Line, raw_lines(active_buf(Sess.session_cl(sunbox(pending)))))), "0")
    Unit <- E.must_eq("raw failure contains only actual error", raw_text(raw_lines(active_buf(Sess.session_cl(sunbox(ready))))), "image preview unavailable")
    Unit <- E.must_eq("exact manual source stays topic", topic(active_buf(Sess.session_cl(sunbox(ready)))), url())
    Unit <- E.must_eq("manual diagnostics are not history", H.extract_new_history(Sess.session_cl(sunbox(pending)), Sess.session_cl(sunbox(ready))), "")
    Unit <- E.must_eq("live tail shows newest diagnostic", rows_text(V.body_of.buf_media(active_buf(Sess.session_cl(sunbox(live_error))), 2n, 20, False{}, Nil{}, True{}, True{}, "s", Sess.session_media(sunbox(live_error)))), "image preview unavailable")
    IO.pure(Unit, Unit{})

def split_controls() -> IO(Unit):
  +side = cbox(split_paused(Sp.SideBySide{}, 9))
  +stacked = cbox(split_paused(Sp.Stacked{}, 13))
  do IO<Unit>:
    Unit <- E.must_eq("side-by-side distinct clips", split_paint(cunbox(side), Sp.SideBySide{}, 9, 80), "1,2,29,6,0,5,11;32,3,29,6,0,4,22;")
    Unit <- E.must_eq("side-by-side resized clips", split_paint(cunbox(side), Sp.SideBySide{}, 9, 56), "1,2,17,6,0,5,11;20,3,17,6,0,4,22;")
    Unit <- E.must_eq("stacked distinct clips", split_paint(cunbox(stacked), Sp.Stacked{}, 13, 80), "1,2,40,6,2,3,11;1,8,40,6,1,3,22;")
    Unit <- E.must_eq("side clips sit inside history", clip_report(cunbox(side), Sp.SideBySide{}, 9, 80), "")
    Unit <- E.must_eq("stacked clips sit inside history", clip_report(cunbox(stacked), Sp.Stacked{}, 13, 80), "")
    Unit <- E.must_eq("page height matches paint", page_sweep.msg(40n, 1), "")
    Unit <- E.must_eq("first pane source preserved", raw_text(raw_lines(V.active_buf.on(Cl.nth_buf(Cl.client_bufs(cunbox(side)), 0n)))), url())
    Unit <- E.must_eq("second pane source preserved", raw_text(raw_lines(active_buf(cunbox(side)))), "https://x/b.gif")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- projection_controls()
    Unit <- manual_controls()
    Unit <- inline_controls()
    Unit <- source_controls()
    Unit <- split_controls()
    IO.print("media_anchor=ok\n")
