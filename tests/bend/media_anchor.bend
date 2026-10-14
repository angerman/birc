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
    case Cl.Client{_, _, bufs, active, _, _, _, _}: V.active_buf.on(Cl.nth_buf(bufs, active))

def active_media() -> M.State:
  M.State{False{}, 1n, 2n, Some{M.Request{M.Manual{}, url(), 1n, 1n}}, Nil{}, Nil{}, M.Supported{}}

def ready_inline() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, url(), 9}], M.Supported{}}

def manual_session() -> Sess.Session:
  Sess.session_set_media(Sess.session_demo(client(Sub.submit(Cl.init("me", "s"), "/preview " ++ url())), ""), active_media())

def paused_session() -> Sess.Session:
  +st = manual_session()
  +cl = Sess.session_cl(st)
  Sess.session_set_client(st, Cl.buf_modify_client(cl, Cl.active_of(cl), b => V.scroll_buf_media(b, 2n, 20, False{}, Nil{}, True{}, True{}, "s", 2n, 0n, active_media())))

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
    case Cl.Buffer{_, _, _, _, _, Cl.ScrollAt{after, tail}}: Nat.show(after) ++ ":" ++ Nat.show(tail)

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
    case Cl.Buffer{_, _, _, lines, _, _}: lines

def raw_text(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, _, text, _, _}, tail}: text ++ raw_text(tail)

def topic(b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, topic, _, _, _}: topic

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
  V.scroll_buf_media(Cl.Buffer{"server", False{}, "", [Cl.Line{Cl.Msg{}, "", inline_text(), "alice", 1n}], Nil{}, Cl.ScrollAt{0n, 0n}}, 2n, 20, False{}, Nil{}, True{}, True{}, "s", 2n, 0n, ready_inline())

def first_line(lines: List<&2, Cl.Line>) -> Cl.Line:
  match lines:
    case Nil{}: Cl.Line{Cl.Error{}, "", "missing", "", 0n}
    case Con{h, _}: h

def split_media() -> M.State:
  M.State{True{}, 1n, 3n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, url(), 11}, M.MediaReady{M.Inline{2n}, "https://x/b.gif", 22}], M.Supported{}}

def split_client.of(cl: Cl.Client) -> Cl.Client:
  match cl:
    case Cl.Client{nick, server, _, _, now, stg, auth, _}:
      Cl.Client{nick, server,
        [Cl.Buffer{"server", False{}, "", [Cl.Line{Cl.Msg{}, "", url(), "alice", 1n}], Nil{}, Cl.ScrollAt{0n, 0n}},
         Cl.Buffer{"#b", True{}, "", [Cl.Line{Cl.Msg{}, "", "https://x/b.gif", "bob", 2n}], Nil{}, Cl.ScrollAt{0n, 0n}}],
        0n, now, Cl.set_ts(stg, False{}), auth, 2n}

def split_client() -> Cl.Client:
  split_client.of(Cl.init("me", "s"))

def split_state(axis: Sp.Axis, focus: U32) -> Sp.State:
  Sp.On{axis, "*server*", "#b", focus}

def split_paused(+axis: Sp.Axis, +rows: U32) -> Cl.Client:
  +first = V.scroll_active_media(split_client(), rows, 80, split_state(axis, 0), 1n, 0n, split_media())
  V.scroll_active_media(Cl.set_active(first, 1n), rows, 80, split_state(axis, 1), 2n, 0n, split_media())

def vm_shape(vm: V.ViewModel) -> String:
  match vm:
    case V.ViewModel{ops, _}: shape(ops)

def split_paint(cl: Cl.Client, axis: Sp.Axis, rows: U32, cols: U32) -> String:
  vm_shape(V.view_draft.state_typing_media(cl, rows, cols, "", "online", Nil{}, split_state(axis, 1), split_media()))

def manual_controls() -> IO(Unit):
  +pending = paused_session()
  +failed = failed_session(pending)
  +retry = retry_session(failed)
  +ready = ready_session(retry)
  do IO<Unit>:
    Unit <- E.must_eq("pending manual clip", session_paint(pending, 20), "1,1,20,6,2,2,0;")
    Unit <- E.must_eq("pending manual anchor", anchor(active_buf(Sess.session_cl(pending))), "0:2")
    Unit <- E.must_eq("failed append counts newer diagnostic", anchor(active_buf(Sess.session_cl(failed))), "1:2")
    Unit <- E.must_eq("failed completion keeps paused image", session_paint(failed, 20), "1,1,20,6,2,2,0;")
    Unit <- E.must_eq("identical retry keeps paused image", session_paint(retry, 20), "1,1,20,6,2,2,0;")
    Unit <- E.must_eq("successful retry keeps paused image", session_paint(ready, 20), "1,1,20,6,2,2,9;")
    Unit <- E.must_eq("failed resize keeps virtual clip", session_paint(failed, 40), "1,1,40,6,2,2,0;")
    Unit <- E.must_eq("ready resize keeps virtual clip", session_paint(ready, 40), "1,1,40,6,2,2,9;")
    Unit <- E.must_eq("one-cell pane remains bounded", session_paint(ready, 1), "1,1,1,6,2,2,9;")
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
  +pending = paused_session()
  +ready = ready_session(retry_session(failed_session(pending)))
  +live_error = failed_session(manual_session())
  do IO<Unit>:
    Unit <- E.must_eq("manual image never enters raw rows", Nat.show(List.length(&2, Cl.Line, raw_lines(active_buf(Sess.session_cl(pending))))), "0")
    Unit <- E.must_eq("raw failure contains only actual error", raw_text(raw_lines(active_buf(Sess.session_cl(ready)))), "image preview unavailable")
    Unit <- E.must_eq("exact manual source stays topic", topic(active_buf(Sess.session_cl(ready))), url())
    Unit <- E.must_eq("manual diagnostics are not history", H.extract_new_history(Sess.session_cl(pending), Sess.session_cl(ready)), "")
    Unit <- E.must_eq("live tail shows newest diagnostic", rows_text(V.body_of.buf_media(active_buf(Sess.session_cl(live_error)), 2n, 20, False{}, Nil{}, True{}, True{}, "s", Sess.session_media(live_error))), "image preview unavailable")
    IO.pure(Unit, Unit{})

def split_controls() -> IO(Unit):
  +side = split_paused(Sp.SideBySide{}, 9)
  +stacked = split_paused(Sp.Stacked{}, 13)
  do IO<Unit>:
    Unit <- E.must_eq("side-by-side distinct clips", split_paint(side, Sp.SideBySide{}, 9, 80), "1,2,29,6,1,4,11;32,2,29,6,0,4,22;")
    Unit <- E.must_eq("side-by-side resized clips", split_paint(side, Sp.SideBySide{}, 9, 56), "1,2,17,6,1,4,11;20,2,17,6,0,4,22;")
    Unit <- E.must_eq("stacked distinct clips", split_paint(stacked, Sp.Stacked{}, 13, 80), "1,2,40,6,2,3,11;1,7,40,6,1,3,22;")
    Unit <- E.must_eq("first pane source preserved", raw_text(raw_lines(V.active_buf.on(Cl.nth_buf(Cl.client_bufs(side), 0n)))), url())
    Unit <- E.must_eq("second pane source preserved", raw_text(raw_lines(active_buf(side))), "https://x/b.gif")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- projection_controls()
    Unit <- manual_controls()
    Unit <- inline_controls()
    Unit <- source_controls()
    Unit <- split_controls()
    IO.print("media_anchor=ok\n")
