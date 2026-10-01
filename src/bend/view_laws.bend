# SPDX-License-Identifier: Apache-2.0
# Proof-facing View inspectors and concrete fixtures. No IO or runtime import.
import Base
import ./buffer.bend as Cl
import ./split.bend as Sp
import ./view.bend as V

def style_self_ne_msg() -> Bool:
  Bool.not(U32.is_eq(V.style_of(Cl.Self{}), V.style_of(Cl.Msg{})))

def ts_width_ok() -> Bool:
  Nat.is_eq(V.TS_WIDTH(), 8n)

# Test helper: visible window is chronological (oldest first).
def vis_chrono_ok.pair(+t0: String, rest: List<&2, Cl.Line>) -> Bool:
  match rest:
    case Nil{}:
      False{}
    case Con{Cl.Line{_, _, +t1, +author, +id}, _}:
      String.eq(t0, "one") && String.eq(t1, "two")

def vis_chrono_ok.vis(xs: List<&2, Cl.Line>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Cl.Line{_, _, +t0, +author, +id}, rest}:
      vis_chrono_ok.pair(t0, rest)

def vis_chrono_ok.buf(b: Cl.Buffer) -> Bool:
  match b:
    case Cl.Buffer{_, _, _, +lines, _, _}:
      vis_chrono_ok.vis(V.visible_lines(lines, 10n, 0n))

def vis_chrono_ok() -> Bool:
  vis_chrono_ok.buf(Cl.buf_log(Cl.buf_log(Cl.server_buf(), Cl.Msg{}, "one"), Cl.Msg{}, "two"))

def span_hello(spans: List<&2, V.SpanOp>) -> Bool:
  match spans:
    case Con{V.Spn{a, +text}, Nil{}}:
      U32.is_eq(a, 0) && String.eq(text, "hello")
    case _:
      False{}

def line_ts_wide.line(ok: Bool, rest: List<&2, V.DrawOp>) -> Bool:
  match rest:
    case Con{V.OpLine{x, y, w, fg, spans}, Nil{}}:
      ok && U32.is_eq(x, 9) && U32.is_eq(y, 0) && U32.is_eq(w, 31) && U32.is_eq(fg, V.FG_TEXT()) && span_hello(spans)
    case _:
      False{}

def line_ts_wide.ops(ops: List<&2, V.DrawOp>) -> Bool:
  match ops:
    case Con{V.OpText{x, y, w, fg, attrs, +text}, rest}:
      line_ts_wide.line(U32.is_eq(x, 0) && U32.is_eq(y, 0) && U32.is_eq(w, 8) && U32.is_eq(fg, V.FG_DIM()) && U32.is_eq(attrs, 0) && String.eq(text, "12:00:00"), rest)
    case _:
      False{}

def line_ts_narrow.line(ok: Bool, rest: List<&2, V.DrawOp>) -> Bool:
  match rest:
    case Con{V.OpLine{x, _, w, _, _}, Nil{}}:
      ok && U32.is_eq(x, 4) && U32.is_eq(w, 0)
    case _:
      False{}

def line_ts_narrow.ops(ops: List<&2, V.DrawOp>) -> Bool:
  match ops:
    case Con{V.OpText{_, _, w, _, _, _}, rest}:
      line_ts_narrow.line(U32.is_eq(w, 4), rest)
    case _:
      False{}

def line_ts_empty.ops(ops: List<&2, V.DrawOp>) -> Bool:
  match ops:
    case Con{V.OpLine{x, _, w, _, spans}, Nil{}}:
      U32.is_eq(x, 0) && U32.is_eq(w, 40) && span_hello(spans)
    case _:
      False{}

def line_ts_long.line(ok: Bool, rest: List<&2, V.DrawOp>) -> Bool:
  match rest:
    case Con{V.OpLine{x, _, _, _, _}, Nil{}}:
      ok && U32.is_eq(x, 9)
    case _:
      False{}

def line_ts_long.ops(ops: List<&2, V.DrawOp>) -> Bool:
  match ops:
    case Con{V.OpText{_, _, w, _, _, +text}, rest}:
      line_ts_long.line(U32.is_eq(w, 8) && String.eq(text, "12:00:00.extra"), rest)
    case _:
      False{}

def line_ts_ok() -> Bool:
  line_ts_wide.ops(V.line_ops_at(0, 0, 40, Cl.Line{Cl.Msg{}, "12:00:00", "hello", "", 0n}))
    && line_ts_narrow.ops(V.line_ops_at(0, 0, 4, Cl.Line{Cl.Msg{}, "12:00:00", "hello", "", 0n}))
    && line_ts_empty.ops(V.line_ops_at(0, 0, 40, Cl.Line{Cl.Msg{}, "", "hello", "", 0n}))
    && line_ts_long.ops(V.line_ops_at(0, 0, 40, Cl.Line{Cl.Msg{}, "12:00:00.extra", "hello", "", 0n}))

def tab_names_ok.rest(t: List<&2, String>) -> Bool:
  match t:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def tab_names_ok.head(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+h, t}:
      String.eq(h, "*server*") && tab_names_ok.rest(t)
    case Nil{}:
      False{}

def tab_names_ok.on(cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, +stg, +auth, +log_seq}:
      tab_names_ok.head(V.tab_names(bufs, Cl.settings_unreads(stg)))

def tab_names_ok() -> Bool:
  tab_names_ok.on(Cl.init("me", "s"))

def split_test_cl.got(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (cl, Some{+i}): Cl.set_active(cl, i)
    case (cl, None{}): cl

def split_test_cl() -> Cl.Client:
  split_test_cl.got(Cl.buf_get(Cl.init("me", "s"), "#one", True{}, True{}))

def split_ops_check.go(xs: List<&2, V.DrawOp>, split: Bool, first: Bool, second: Bool) -> Bool:
  match xs:
    case Nil{}: split && first && second
    case Con{V.OpSplit{x, y, w, h, axis}, t}:
      split_ops_check.go(t, U32.is_eq(x, 0) && U32.is_eq(y, 1) && U32.is_eq(w, 62) && U32.is_eq(h, 21) && U32.is_eq(axis, 1), first, second)
    case Con{V.OpText{_, _, _, _, _, +text}, t}:
      split_ops_check.go(t, split, first || String.eq(text, "#one [active]"), second || String.eq(text, "server"))
    case Con{_, t}: split_ops_check.go(t, split, first, second)

def split_ops_check(vm: V.ViewModel) -> Bool:
  match vm:
    case V.ViewModel{ops, _}: split_ops_check.go(ops, False{}, False{}, False{})

def split_draw_ok() -> Bool:
  +cl = split_test_cl()
  split_ops_check(V.view_draft_split(cl, 24, 80, "", "demo", Sp.On{Sp.Stacked{}, "#one", "*server*", 0}))


def dummy_line(+i: Nat) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", "L" ++ Nat.show(i), "", 0n}

def dummy_lines.go(n: Nat, +i: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      dummy_line(i) <> dummy_lines.go(p, 1n+i)

def dummy_cl(+n: Nat) -> Cl.Client:
  Cl.Client{"me", "s", Cl.Buffer{"server", False{}, "", dummy_lines.go(n, 0n), Nil{}, Cl.ScrollAt{0n, 0n}} <> Nil{}, 0n, "", Cl.settings0(), Cl.AuthIdle{}, 0n}

def body_line_ys.go(ops: List<&2, V.DrawOp>) -> List<&2, U32>:
  match ops:
    case Nil{}:
      Nil{}
    case Con{V.OpLine{_, y, _, _, _}, t}:
      y <> body_line_ys.go(t)
    case Con{_, t}:
      body_line_ys.go(t)

def body_ys.of(vm: V.ViewModel) -> List<&2, U32>:
  match vm:
    case V.ViewModel{ops, _}:
      body_line_ys.go(ops)

def body_ys(+rows: U32, +nlines: Nat) -> List<&2, U32>:
  body_ys.of(V.view_draft(dummy_cl(nlines), rows, 80, "", "demo"))

def ys_inc.go(xs: List<&2, U32>, +prev: U32) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+y, t}:
      U32.is_lt(prev, y) && ys_inc.go(t, y)

def ys_inc(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{y, t}:
      ys_inc.go(t, y)

def ys_last.go(xs: List<&2, U32>, +y: U32) -> U32:
  match xs:
    case Nil{}:
      y
    case Con{h, t}:
      ys_last.go(t, h)

def ys_last(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{h, t}:
      ys_last.go(t, h)

# Body-line y values are strictly increasing, end on the last inner body
# row, and the count is min(lines, V.vis_h).
def body_ys_case(+rows: U32, +nlines: Nat) -> Bool:
  +ys = body_ys(rows, nlines)
  Nat.is_eq(List.length(&2, U32, ys), V.vis_n(nlines, V.vis_h(rows)))
    && U32.is_eq(ys_last(ys), V.last_body_row(rows))
    && ys_inc(ys)

def lay_body_ok(l: V.Lay, +want_y: U32, +want_h: U32, +want_sy: U32) -> Bool:
  match l:
    case V.Lay{_, _, V.Rect{_, +by, _, +bh}, _, V.Rect{_, +sy, _, _}}:
      U32.is_eq(by, want_y) && U32.is_eq(bh, want_h) && U32.is_eq(sy, want_sy) && U32.is_le(U32.add(by, bh), sy)

def ys_clear_chrome(+rows: U32) -> Bool:
  +last = ys_last(body_ys(rows, 8n))
  U32.is_lt(last, V.status_y(rows)) && U32.is_lt(last, U32.sub(rows, 1))

def body_ys_ok() -> Bool:
  body_ys_case(24, 200n)
    && body_ys_case(90, 200n)
    && body_ys_case(200, 200n)
    && body_ys_case(24, 5n)
    && body_ys_case(1, 8n)
    && body_ys_case(2, 8n)
    && body_ys_case(3, 8n)
    && body_ys_case(4, 8n)
    && body_ys_case(5, 8n)
    && body_ys_case(6, 8n)
    && body_ys_case(7, 8n)
    && body_ys_case(8, 8n)
    && lay_body_ok(V.lay(4, 80, 0), 1, 1, 2)
    && lay_body_ok(V.lay(24, 80, 0), 1, 21, 22)

    && ys_clear_chrome(4)
    && ys_clear_chrome(5)
    && ys_clear_chrome(6)
    && ys_clear_chrome(7)
    && ys_clear_chrome(8)
    && Nat.is_eq(V.vis_h(24), Sp.page_height(24, Sp.Off{}))
    && Nat.is_eq(V.vis_h(6), Sp.page_height(6, Sp.Off{}))
    && Nat.is_eq(V.vis_h(7), Sp.page_height(7, Sp.Off{}))

def scroll_bounds_ok.fin(+c: Nat, +m: Nat, +count: Nat, +height: Nat) -> Bool:
  Nat.is_eq(c, V.clamp_scroll(c, count, height)) && Nat.is_le(c, m)

def scroll_bounds_ok(+scroll: Nat, +count: Nat, +height: Nat) -> Bool:
  scroll_bounds_ok.fin(V.clamp_scroll(scroll, count, height), V.scroll_max(count, height), count, height)
