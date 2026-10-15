# SPDX-License-Identifier: Apache-2.0
# Proof-facing View inspectors and concrete fixtures. No IO or runtime import.
import Base
import ./buffer.bend as Cl
import ./split.bend as Sp
import ./view.bend as V
import ./links.bend as Links
import ./wire_style.bend as Ws
import ./columns.bend as Cols

# Legacy tokenizer adapters preserve the original proof/test vocabulary.
# Production View paints shared Links.Run values without this intermediate type.
type TextSpan is Data:
  Plain{text: String}
  Bold{text: String}
  Italic{text: String}
  Code{text: String}
  Link{url: String, text: String}
  Styled{attrs: U32, text: String}
  WCol{fg: U32, attrs: U32, text: String}

def STAR() -> Char:
  Chr{42}

def USCORE() -> Char:
  Chr{95}

def TICK() -> Char:
  Chr{96}

type TokMode is Data:
  MdOut{}
  MdBold{}
  MdItalic{}
  MdCode{}

# Retain the public fallback seam used by the original tokenizer guards.
def tokenize.emit_plain(+acc: String, spans: List<&2, TextSpan>) -> List<&2, TextSpan>:
  match acc:
    case SNil{}: spans
    case SCon{_, _}: Plain{String.reverse(acc)} <> spans

def tokenize.force_mode(mode: TokMode, +acc: String, spans: List<&2, TextSpan>) -> List<&2, TextSpan>:
  match mode:
    case MdOut{}: List.reverse(&2, TextSpan, tokenize.emit_plain(acc, spans))
    case MdBold{}: List.reverse(&2, TextSpan, Plain{SCon{STAR(), String.reverse(acc)}} <> spans)
    case MdItalic{}: List.reverse(&2, TextSpan, Plain{SCon{USCORE(), String.reverse(acc)}} <> spans)
    case MdCode{}: List.reverse(&2, TextSpan, Plain{SCon{TICK(), String.reverse(acc)}} <> spans)

def tokenize.styled(attrs: U32, text: String) -> TextSpan:
  match attrs:
    case 0: Plain{text}
    case 1: Bold{text}
    case 2: Code{text}
    case 4: Italic{text}
    case _: Styled{attrs, text}

def tokenize.run(run: Links.Run) -> TextSpan:
  match run:
    case Links.Run{attrs, text, url}:
      match url:
        case None{}: tokenize.styled(attrs, text)
        case Some{link}: Link{link, text}

def tokenize.runs(runs: List<&2, Links.Run>) -> List<&2, TextSpan>:
  match runs:
    case Nil{}: Nil{}
    case Con{h, t}: tokenize.run(h) <> tokenize.runs(t)

def tokenize.paint(+attrs: U32, +fg: U32, +has_fg: Bool, +text: String) -> TextSpan:
  match has_fg:
    case True{}: WCol{fg, attrs, text}
    case False{}: tokenize.styled(attrs, text)

def tokenize.finished(+url: Maybe<&2, String>, +attrs: U32, +fg: U32, +has_fg: Bool, +text: String) -> TextSpan:
  match url:
    case None{}: tokenize.paint(attrs, fg, has_fg, text)
    case Some{+link}: Link{link, text}

def tokenize.styled_run(run: Ws.SRun) -> TextSpan:
  match run:
    case Ws.SRun{+attrs, +fg, +has_fg, +text, +url}: tokenize.finished(url, attrs, fg, has_fg, text)

def tokenize.styled_runs(+xs: List<&2, Ws.SRun>) -> List<&2, TextSpan>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: tokenize.styled_run(h) <> tokenize.styled_runs(t)

# Wire-aware: control-free input tokenizes exactly as before (one unstyled
# run), while wire codes become WCol/Styled spans instead of painted bytes.
def tokenize(+s: String) -> List<&2, TextSpan>:
  tokenize.styled_runs(Ws.render(s))

# Reconstruct the legacy single-style spelling for the tokenizer laws.
# Emoji and escaped source remain in Client; display spans are not source text.
def show_spans.styled(+attrs: U32, text: String) -> String:
  +bold = Bool.pick(String, U32.is_ne(U32.and(attrs, 1), 0), "*", "")
  +italic = Bool.pick(String, U32.is_ne(U32.and(attrs, 4), 0), "_", "")
  +code = Bool.pick(String, U32.is_ne(U32.and(attrs, 2), 0), "`", "")
  bold ++ italic ++ code ++ text ++ code ++ italic ++ bold

def show_spans.chunk(sp: TextSpan) -> String:
  match sp:
    case Plain{+tx}:
      tx
    case Bold{+tx}:
      "*" ++ tx ++ "*"
    case Italic{+tx}:
      "_" ++ tx ++ "_"
    case Code{+tx}:
      "`" ++ tx ++ "`"
    case Link{_, +text}:
      text
    case Styled{attrs, text}:
      show_spans.styled(attrs, text)
    case WCol{_, attrs, text}:
      show_spans.styled(attrs, text)

def show_spans.chunks(+xs: List<&2, TextSpan>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      show_spans.chunk(h) <> show_spans.chunks(t)

def show_spans(+xs: List<&2, TextSpan>) -> String:
  String.concat(show_spans.chunks(xs))

def tokenize_roundtrip(+s: String) -> Bool:
  String.eq(show_spans(tokenize(s)), s)

type SpanKind is Data:
  WantBold{}
  WantItalic{}
  WantCode{}
  WantLink{}

def span_hit(k: SpanKind, h: TextSpan) -> Bool:
  match k:
    case WantBold{}:
      match h:
        case Bold{_}:
          True{}
        case Styled{attrs, _}:
          U32.is_ne(U32.and(attrs, 1), 0)
        case WCol{_, attrs, _}:
          U32.is_ne(U32.and(attrs, 1), 0)
        case _:
          False{}
    case WantItalic{}:
      match h:
        case Italic{_}:
          True{}
        case Styled{attrs, _}:
          U32.is_ne(U32.and(attrs, 4), 0)
        case WCol{_, attrs, _}:
          U32.is_ne(U32.and(attrs, 4), 0)
        case _:
          False{}
    case WantCode{}:
      match h:
        case Code{_}:
          True{}
        case Styled{attrs, _}:
          U32.is_ne(U32.and(attrs, 2), 0)
        case WCol{_, attrs, _}:
          U32.is_ne(U32.and(attrs, 2), 0)
        case _:
          False{}
    case WantLink{}:
      match h:
        case Link{_, _}:
          True{}
        case _:
          False{}

def has_kind.go(+k: SpanKind, xs: List<&2, TextSpan>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      Bool.pick(Bool, span_hit(k, h), True{}, has_kind.go(k, t))

def has_kind(+k: SpanKind, +s: String) -> Bool:
  has_kind.go(k, tokenize(s))

def tokenize_has_bold(+s: String) -> Bool:
  has_kind(WantBold{}, s)

def tokenize_has_italic(+s: String) -> Bool:
  has_kind(WantItalic{}, s)

def tokenize_has_code(+s: String) -> Bool:
  has_kind(WantCode{}, s)

def tokenize_has_link(+s: String) -> Bool:
  has_kind(WantLink{}, s)

def first_link.go(+xs: List<&2, TextSpan>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      match h:
        case Link{+url, _}:
          url
        case _:
          first_link.go(t)

def tokenize_no_embed() -> Bool:
  Bool.not(tokenize_has_link("notahttp://x"))

def tokenize_trim_dot() -> Bool:
  String.eq(first_link.go(tokenize("see http://x.com.")), "http://x.com")

def tokenize_trim_semi() -> Bool:
  String.eq(first_link.go(tokenize("see http://x.com;")), "http://x.com")

def tokenize_trim_brack() -> Bool:
  String.eq(first_link.go(tokenize("see http://x.com]")), "http://x.com")

# − https://evil2.exampleclick]8;; was one link including the OSC-8 closer.
# Trailing ] and ; strip; a digit stops the trim, so ]8 remains.
def tokenize_trim_osc() -> Bool:
  String.eq(first_link.go(tokenize("see https://evil2.exampleclick];; x")), "https://evil2.exampleclick")
    && String.eq(first_link.go(tokenize("see https://evil2.exampleclick]8;; x")), "https://evil2.exampleclick]8")

def unclosed_star_plain() -> Bool:
  Bool.not(tokenize_has_bold("*foo"))

def span_op(sp: TextSpan) -> V.SpanOp:
  match sp:
    case Plain{+tx}:
      V.Spn{0, tx}
    case Bold{+tx}:
      V.Spn{1, tx}
    case Italic{+tx}:
      V.Spn{4, tx}
    case Code{+tx}:
      V.Spn{2, tx}
    case Link{+url, +text}:
      V.Lnk{url, text}
    case Styled{attrs, text}:
      V.Spn{attrs, text}
    case WCol{+fg, +attrs, +text}:
      V.Col{attrs, fg, text}

def span_ops(xs: List<&2, TextSpan>) -> List<&2, V.SpanOp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      span_op(h) <> span_ops(t)

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

def ys_sorted.go(xs: List<&2, U32>, +prev: U32) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{+y, t}:
      U32.is_le(prev, y) && ys_sorted.go(t, y)

def ys_sorted(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{y, t}:
      ys_sorted.go(t, y)

def ys_init(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      match t:
        case Nil{}:
          Nil{}
        case Con{_, _}:
          h <> ys_init(t)

def hist_sep.box(+y: U32, +h: U32) -> Bool:
  +hh = V.body_hist_h(h)
  U32.is_ge(hh, 1) && U32.is_lt(V.inner_last(y, hh), V.inner_last(y, h))

def hist_sep.lay(l: V.Lay) -> Bool:
  match l:
    case V.Lay{_, _, V.Rect{_, +y, _, +h}, _, _}:
      hist_sep.box(y, h)

def hist_sep(+rows: U32) -> Bool:
  hist_sep.lay(V.lay(rows, 80, 0))

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

# Body-line y values are history rows plus the inline-composer row
# (c19445d): the count is min(lines, V.vis_h)+1, rows are non-decreasing
# ending on the composer (last inner body row), history rows are mutually
# distinct, and the full list is strictly increasing whenever the box
# separates history from the composer (tiny boxes share the row).
def body_ys_case(+rows: U32, +nlines: Nat) -> Bool:
  +ys = body_ys(rows, nlines)
  Nat.is_eq(List.length(&2, U32, ys), Nat.add(V.vis_n(nlines, V.vis_h(rows)), 1n))
    && U32.is_eq(ys_last(ys), V.last_body_row(rows))
    && ys_sorted(ys)
    && ys_inc(ys_init(ys))
    && Bool.pick(Bool, hist_sep(rows), ys_inc(ys), True{})

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
    && lay_body_ok(V.lay(4, 80, 0), 1, 2, 3)
    && lay_body_ok(V.lay(24, 80, 0), 1, 22, 23)

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

def cluster_plain(xs: List<&2, V.SpanOp>, +want: String) -> Bool:
  match xs:
    case Con{V.Spn{attrs, text}, Nil{}}: U32.is_eq(attrs, 0) && String.eq(text, want)
    case _: False{}

def styled_cluster_ok() -> Bool:
  cluster_plain(V.line_spans_for(Cl.Msg{}, "e*́*X"), "éX")
    && cluster_plain(V.line_spans_for(Cl.Msg{}, "👩*‍💻*X"), "👩‍💻X")
    && cluster_plain(V.line_spans_for(Cl.Msg{}, "👩‍💻X"), "👩‍💻X")

def wrapped_text(rows: List<&2, V.BodyRow>) -> List<&2, String>:
  match rows:
    case Nil{}: Nil{}
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: V.spans_text(spans) <> wrapped_text(t)
    case Con{_, t}: wrapped_text(t)

def word_wrap_ok() -> Bool:
  +rows = V.wrap_line(Cl.Line{Cl.Msg{}, "", "hello   **world**", "", 0n}, 8, False{})
  String.eq(String.join(wrapped_text(rows), "|"), "hello|world")
    && Nat.is_eq(V.rows_chars(rows), 13n)
    && String.eq(String.join(wrapped_text(V.wrap_line(Cl.Line{Cl.Msg{}, "", "abcdefghijk", "", 0n}, 4, False{})), "|"), "abcd|efgh|ijk")

def hidden_header_ok() -> Bool:
  List.is_empty(&2, V.DrawOp, V.user_header_ops(V.Rect{0, 0, 0, 0}, "me", "irc", "online"))
    && List.is_empty(&2, V.DrawOp, V.user_header_ops(V.Rect{5, 2, 20, 0}, "me", "irc", "online"))

def header_columns_ok() -> Bool:
  U32.is_eq(V.user_w("漢@irc · online"), Cols.text_width("漢@irc · online"))
    && U32.is_eq(V.user_w("é@irc · online"), Cols.text_width("é@irc · online"))

def prefix_fallback_ok() -> Bool:
  String.eq(V.spans_text(V.line_spans_for(Cl.Msg{}, "<alice>oops")), "<alice>oops")
    && String.eq(V.spans_text(V.line_spans_for(Cl.Msg{}, "<alice")), "<alice")
    && String.eq(V.spans_text(V.line_spans_for(Cl.Msg{}, "<alice> hello")), "<alice> hello")
