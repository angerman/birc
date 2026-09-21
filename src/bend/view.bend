# View model from Client. Pure scroll math + DrawOp list for the paint FFI.
import Base
import ./buffer.bend as Cl
import ./session.bend as Sess

# Live paint ops. C walks the list inside one Timui.frame (no packed wire).
# Bend owns layout and assigns every line its y. Attr bits: bold=1, italic=4.
type SpanOp is Data:
  Spn{attrs: U32, text: String}
  Lnk{url: String, text: String}

type Rect is Data:
  Rect{x: U32, y: U32, w: U32, h: U32}

type DrawOp is Data:
  OpBox{x: U32, y: U32, w: U32, h: U32}
  OpText{x: U32, y: U32, w: U32, fg: U32, attrs: U32, text: String}
  OpTabs{x: U32, y: U32, w: U32, sel: U32, names: List<&2, String>}
  OpLine{x: U32, y: U32, w: U32, fg: U32, ts: String, spans: List<&2, SpanOp>}

type Lay is Data:
  Lay{header: Rect, tabs: Rect, body: Rect, nicks: Rect, status: Rect}

type ViewModel is Data:
  ViewModel{ops: List<&2, DrawOp>, input: String}

def scroll_max.on(+count: Nat, +height: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      Nat.sub(count, height)
    case False{}:
      0n

def scroll_max(+count: Nat, +height: Nat) -> Nat:
  scroll_max.on(count, height, Nat.is_ge(count, height))

def clamp_scroll.ge(+scroll: Nat, +maxs: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      maxs
    case False{}:
      scroll

def clamp_scroll.on(+scroll: Nat, +maxs: Nat) -> Nat:
  clamp_scroll.ge(scroll, maxs, Nat.is_ge(scroll, maxs))

def clamp_scroll(+scroll: Nat, +count: Nat, +height: Nat) -> Nat:
  clamp_scroll.on(scroll, scroll_max(count, height))

def visible_start.ge(+count: Nat, +height: Nat, +scroll: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      Nat.sub(Nat.sub(count, height), scroll)
    case False{}:
      0n

def visible_start.on(+count: Nat, +height: Nat, +scroll: Nat) -> Nat:
  visible_start.ge(count, height, scroll, Nat.is_ge(count, height))

def visible_start(+count: Nat, +height: Nat, +scroll: Nat) -> Nat:
  visible_start.on(count, height, clamp_scroll(scroll, count, height))

def visible_lines(+lines: List<&2, Cl.Line>, +height: Nat, +scroll: Nat) -> List<&2, Cl.Line>:
  List.take(
    &2, Cl.Line,
    List.drop(&2, Cl.Line, lines, visible_start(List.length(&2, Cl.Line, lines), height, scroll)),
    height
  )

# TextSpan is the tokenize law type. Live paint uses SpanOp / DrawOp.
type TextSpan is Data:
  Plain{text: String}
  Bold{text: String}
  Italic{text: String}
  Code{text: String}
  Link{url: String, text: String}

def TS_WIDTH() -> Nat:
  8n

def style_of(k: Cl.LineKind) -> U32:
  match k:
    case Cl.Msg{}:
      13158600
    case Cl.Self{}:
      5893695
    case Cl.System{}:
      10526880
    case Cl.Action{}:
      13079274
    case Cl.Notice{}:
      8563455
    case Cl.Error{}:
      16223340

def style_self_ne_msg() -> Bool:
  Bool.not(U32.is_eq(style_of(Cl.Self{}), style_of(Cl.Msg{})))

def ts_width_ok() -> Bool:
  Nat.is_eq(TS_WIDTH(), 8n)

def STAR() -> Char:
  Chr{42}

def USCORE() -> Char:
  Chr{95}

def TICK() -> Char:
  Chr{96}

def HTTP() -> String:
  "http://"

def HTTPS() -> String:
  "https://"

type TokMode is Data:
  MdOut{}
  MdBold{}
  MdItalic{}
  MdCode{}

type TokJump is Data:
  Jump{mode: TokMode, s: String, acc: String, spans: List<&2, TextSpan>}
  Done{spans: List<&2, TextSpan>}

def tokenize.emit_plain(+acc: String, spans: List<&2, TextSpan>) -> List<&2, TextSpan>:
  match acc:
    case SNil{}:
      spans
    case SCon{_, _}:
      Plain{String.reverse(acc)} <> spans

def url_stop.on(+c: U32) -> Bool:
  U32.is_eq(c, 32) || U32.is_eq(c, 9) || U32.is_lt(c, 32)

def url_stop(h: Char) -> Bool:
  match h:
    case Chr{c}:
      url_stop.on(c)

def take_url.cons(+h: Char, r: String & String) -> String & String:
  match r:
    case (tok, rest):
      (SCon{h, tok}, rest)

def take_url.fin(+h: Char, +t: String, r: String & String, stop: Bool) -> String & String:
  match stop:
    case True{}:
      ("", SCon{h, t})
    case False{}:
      take_url.cons(h, r)

def take_url.go(s: String) -> String & String:
  match s:
    case SNil{}:
      ("", "")
    case SCon{+h, +t}:
      take_url.fin(h, t, take_url.go(t), url_stop(h))

def url_trail(+c: U32) -> Bool:
  U32.is_eq(c, 41) || U32.is_eq(c, 46) || U32.is_eq(c, 44) || U32.is_eq(c, 34)
    || U32.is_eq(c, 93) || U32.is_eq(c, 59)

def trim_url.keep(+h: Char, t: String, rec: String, trail: Bool) -> String:
  match trail:
    case True{}:
      rec
    case False{}:
      String.reverse(SCon{h, t})

def trim_url.go(+rev: String) -> String:
  match rev:
    case SNil{}:
      SNil{}
    case SCon{+h, +t}:
      match h:
        case Chr{n}:
          trim_url.keep(h, t, trim_url.go(t), url_trail(n))

def trim_url(+url: String) -> String:
  trim_url.go(String.reverse(url))

def take_url.trim(pair: String & String) -> String & String:
  match pair:
    case (+url, rest):
      (trim_url(url), rest)

def take_url(+s: String) -> String & String:
  take_url.trim(take_url.go(s))

def tokenize.emit_url(+acc: String, spans: List<&2, TextSpan>, pair: String & String) -> TokJump:
  match pair:
    case (+url, rest):
      Jump{MdOut{}, rest, SNil{}, Link{url, url} <> tokenize.emit_plain(acc, spans)}

def tokenize.out_tick(+s: String, +t: String, +acc: String, +h: Char, spans: List<&2, TextSpan>, tick: Bool) -> TokJump:
  match tick:
    case True{}:
      Jump{MdCode{}, t, SNil{}, tokenize.emit_plain(acc, spans)}
    case False{}:
      Jump{MdOut{}, t, SCon{h, acc}, spans}

def tokenize.out_us(+s: String, +t: String, +acc: String, +h: Char, spans: List<&2, TextSpan>, us: Bool) -> TokJump:
  match us:
    case True{}:
      Jump{MdItalic{}, t, SNil{}, tokenize.emit_plain(acc, spans)}
    case False{}:
      tokenize.out_tick(s, t, acc, h, spans, Char.is_eq(h, TICK()))

def tokenize.out_star(+s: String, +t: String, +acc: String, +h: Char, spans: List<&2, TextSpan>, star: Bool) -> TokJump:
  match star:
    case True{}:
      Jump{MdBold{}, t, SNil{}, tokenize.emit_plain(acc, spans)}
    case False{}:
      tokenize.out_us(s, t, acc, h, spans, Char.is_eq(h, USCORE()))

def is_alnum(+c: Char) -> Bool:
  match c:
    case Chr{n}:
      (U32.is_ge(n, 48) && U32.is_le(n, 57))
        || (U32.is_ge(n, 65) && U32.is_le(n, 90))
        || (U32.is_ge(n, 97) && U32.is_le(n, 122))

def url_bound(+acc: String) -> Bool:
  match acc:
    case SNil{}:
      True{}
    case SCon{+h, _}:
      Bool.not(is_alnum(h))

def tokenize.url_if(
  ok: Bool,
  +s: String,
  +t: String,
  +acc: String,
  +h: Char,
  spans: List<&2, TextSpan>
) -> TokJump:
  match ok:
    case True{}:
      tokenize.emit_url(acc, spans, take_url(s))
    case False{}:
      tokenize.out_star(s, t, acc, h, spans, Char.is_eq(h, STAR()))

def tokenize.out_http(+s: String, +t: String, +acc: String, +h: Char, spans: List<&2, TextSpan>, http: Bool) -> TokJump:
  match http:
    case True{}:
      tokenize.url_if(url_bound(acc), s, t, acc, h, spans)
    case False{}:
      tokenize.out_star(s, t, acc, h, spans, Char.is_eq(h, STAR()))

def tokenize.out_https(+s: String, +t: String, +acc: String, +h: Char, spans: List<&2, TextSpan>, https: Bool) -> TokJump:
  match https:
    case True{}:
      tokenize.url_if(url_bound(acc), s, t, acc, h, spans)
    case False{}:
      tokenize.out_http(s, t, acc, h, spans, String.starts_with(s, HTTP()))

def tokenize.next_out(+s: String, +acc: String, spans: List<&2, TextSpan>) -> TokJump:
  match s:
    case SNil{}:
      Done{tokenize.emit_plain(acc, spans)}
    case SCon{+h, t}:
      tokenize.out_https(s, t, acc, h, spans, String.starts_with(s, HTTPS()))

def tokenize.close_bold(+t: String, +acc: String, +h: Char, spans: List<&2, TextSpan>, star: Bool) -> TokJump:
  match star:
    case True{}:
      Jump{MdOut{}, t, SNil{}, Bold{String.reverse(acc)} <> spans}
    case False{}:
      Jump{MdBold{}, t, SCon{h, acc}, spans}

def tokenize.next_bold(+s: String, +acc: String, spans: List<&2, TextSpan>) -> TokJump:
  match s:
    case SNil{}:
      Done{Plain{String.reverse(SCon{STAR(), acc})} <> spans}
    case SCon{+h, t}:
      tokenize.close_bold(t, acc, h, spans, Char.is_eq(h, STAR()))

def tokenize.close_italic(+t: String, +acc: String, +h: Char, spans: List<&2, TextSpan>, us: Bool) -> TokJump:
  match us:
    case True{}:
      Jump{MdOut{}, t, SNil{}, Italic{String.reverse(acc)} <> spans}
    case False{}:
      Jump{MdItalic{}, t, SCon{h, acc}, spans}

def tokenize.next_italic(+s: String, +acc: String, spans: List<&2, TextSpan>) -> TokJump:
  match s:
    case SNil{}:
      Done{Plain{String.reverse(SCon{USCORE(), acc})} <> spans}
    case SCon{+h, t}:
      tokenize.close_italic(t, acc, h, spans, Char.is_eq(h, USCORE()))

def tokenize.close_code(+t: String, +acc: String, +h: Char, spans: List<&2, TextSpan>, tick: Bool) -> TokJump:
  match tick:
    case True{}:
      Jump{MdOut{}, t, SNil{}, Code{String.reverse(acc)} <> spans}
    case False{}:
      Jump{MdCode{}, t, SCon{h, acc}, spans}

def tokenize.next_code(+s: String, +acc: String, spans: List<&2, TextSpan>) -> TokJump:
  match s:
    case SNil{}:
      Done{Plain{String.reverse(SCon{TICK(), acc})} <> spans}
    case SCon{+h, t}:
      tokenize.close_code(t, acc, h, spans, Char.is_eq(h, TICK()))

def tokenize.next(mode: TokMode, +s: String, +acc: String, spans: List<&2, TextSpan>) -> TokJump:
  match mode:
    case MdOut{}:
      tokenize.next_out(s, acc, spans)
    case MdBold{}:
      tokenize.next_bold(s, acc, spans)
    case MdItalic{}:
      tokenize.next_italic(s, acc, spans)
    case MdCode{}:
      tokenize.next_code(s, acc, spans)

def tokenize.force_mode(mode: TokMode, +acc: String, spans: List<&2, TextSpan>) -> List<&2, TextSpan>:
  match mode:
    case MdOut{}:
      List.reverse(&2, TextSpan, tokenize.emit_plain(acc, spans))
    case MdBold{}:
      List.reverse(&2, TextSpan, Plain{String.reverse(SCon{STAR(), acc})} <> spans)
    case MdItalic{}:
      List.reverse(&2, TextSpan, Plain{String.reverse(SCon{USCORE(), acc})} <> spans)
    case MdCode{}:
      List.reverse(&2, TextSpan, Plain{String.reverse(SCon{TICK(), acc})} <> spans)

def tokenize.force_done(j: TokJump) -> List<&2, TextSpan>:
  match j:
    case Done{spans}:
      List.reverse(&2, TextSpan, spans)
    case Jump{+mode, _, +acc, spans}:
      tokenize.force_mode(mode, acc, spans)

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed tokenize.go
def tokenize.go(fuel: Nat, j: TokJump) -> List<&2, TextSpan>:
  match fuel:
    case 0n:
      tokenize.force_done(j)
    case 1n+p:
      match j:
        case Done{spans}:
          List.reverse(&2, TextSpan, spans)
        case Jump{+mode, +s, +acc, spans}:
          tokenize.go(p, tokenize.next(mode, s, acc, spans))

def tokenize(+s: String) -> List<&2, TextSpan>:
  tokenize.go(Nat.add(1n, Nat.mul(4n, String.length(s))), Jump{MdOut{}, s, SNil{}, Nil{}})

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
        case _:
          False{}
    case WantItalic{}:
      match h:
        case Italic{_}:
          True{}
        case _:
          False{}
    case WantCode{}:
      match h:
        case Code{_}:
          True{}
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

# Test helper: visible window is chronological (oldest first).
def vis_chrono_ok.pair(+t0: String, rest: List<&2, Cl.Line>) -> Bool:
  match rest:
    case Nil{}:
      False{}
    case Con{Cl.Line{_, _, +t1}, _}:
      String.eq(t0, "one") && String.eq(t1, "two")

def vis_chrono_ok.vis(xs: List<&2, Cl.Line>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Cl.Line{_, _, +t0}, rest}:
      vis_chrono_ok.pair(t0, rest)

def vis_chrono_ok.buf(b: Cl.Buffer) -> Bool:
  match b:
    case Cl.Buffer{_, _, _, +lines, _, _}:
      vis_chrono_ok.vis(visible_lines(lines, 10n, 0n))

def vis_chrono_ok() -> Bool:
  vis_chrono_ok.buf(Cl.buf_log(Cl.buf_log(Cl.server_buf(), Cl.Msg{}, "one"), Cl.Msg{}, "two"))

def active_buf.on(+got: Maybe<&2, Cl.Buffer>) -> Cl.Buffer:
  match got:
    case Some{b}:
      b
    case None{}:
      Cl.server_buf()

def header_of.buf(+nick: String, +server: String, +b: Cl.Buffer, +net: String) -> String:
  match b:
    case Cl.Buffer{+name, _, +topic, _, _, _}:
      nick ++ "@" ++ server ++ " · " ++ name ++ " · " ++ net

def span_op(sp: TextSpan) -> SpanOp:
  match sp:
    case Plain{+tx}:
      Spn{0, tx}
    case Bold{+tx}:
      Spn{1, tx}
    case Italic{+tx}:
      Spn{4, tx}
    case Code{+tx}:
      Spn{0, tx}
    case Link{+url, +text}:
      Lnk{url, text}

def span_ops(xs: List<&2, TextSpan>) -> List<&2, SpanOp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      span_op(h) <> span_ops(t)

def FG_TEXT() -> U32:
  13158600

def FG_DIM() -> U32:
  10526880

def line_op.at(+x: U32, +y: U32, +w: U32, +ln: Cl.Line) -> DrawOp:
  match ln:
    case Cl.Line{+k, +ts, +text}:
      OpLine{x, y, w, style_of(k), ts, span_ops(tokenize(text))}

def line_op(+ln: Cl.Line) -> DrawOp:
  line_op.at(0, 0, 40, ln)

def body_of.buf(+b: Cl.Buffer, +height: Nat) -> List<&2, Cl.Line>:
  match b:
    case Cl.Buffer{_, _, _, +lines, _, +scroll}:
      visible_lines(lines, height, scroll)

def nicks_title.on(+name: String, +topic: String, empty: Bool) -> String:
  match empty:
    case True{}:
      name
    case False{}:
      name ++ " — " ++ topic

def nicks_title_of(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, +topic, _, _, _}:
      nicks_title.on(name, topic, String.is_empty(topic))

def nicks_list_of(+b: Cl.Buffer) -> List<&2, String>:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _}:
      nicks

def status_of.buf(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _}:
      "/connect /join /part /msg /nick /me /quit  ·  Up/Down hist  ·  Shift+Left/Right  ·  Esc  ·  "
        ++ Nat.show(List.length(&2, String, nicks))
        ++ " nicks"

def view_input(+draft: String) -> String:
  draft

def tab_names(bufs: List<&2, Cl.Buffer>) -> List<&2, String>:
  match bufs:
    case Nil{}:
      Nil{}
    case Con{Cl.Buffer{+name, _, _, _, _, _}, t}:
      name <> tab_names(t)

def vis_h(+rows: U32) -> Nat:
  Sess.body_h(rows)

def mid_w.on(+cols: U32, wide: Bool) -> U32:
  match wide:
    case True{}:
      U32.sub(cols, 18)
    case False{}:
      U32.div(cols, 2)

def mid_w(+cols: U32) -> U32:
  mid_w.on(cols, U32.is_gt(cols, 24))

def status_y.on(+rows: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      U32.sub(rows, 2)
    case False{}:
      0

def status_y(+rows: U32) -> U32:
  status_y.on(rows, U32.is_ge(rows, 2))

# Body last occupied row is y+h-1. Keep y+h <= status_y so the box never
# reaches the status (or composer) row. Prefer y=2 when there is room.
def body_top.small(+end: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      U32.sub(end, 1)
    case False{}:
      0

def body_top.on(+end: U32, room: Bool) -> U32:
  match room:
    case True{}:
      2
    case False{}:
      body_top.small(end, U32.is_ge(end, 1))

def body_top(+end: U32) -> U32:
  body_top.on(end, U32.is_gt(end, 2))

def body_box_h.on(+end: U32, +top: U32, gt: Bool) -> U32:
  match gt:
    case True{}:
      U32.sub(end, top)
    case False{}:
      1

def body_box_h(+end: U32, +top: U32) -> U32:
  body_box_h.on(end, top, U32.is_gt(end, top))

def nick_w.on(+cols: U32, +mid: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      U32.sub(cols, mid)
    case False{}:
      0

def nick_w(+cols: U32, +mid: U32) -> U32:
  nick_w.on(cols, mid, U32.is_ge(cols, mid))

def lay(+rows: U32, +cols: U32) -> Lay:
  +mid = mid_w(cols)
  +sy = status_y(rows)
  +top = body_top(sy)
  +bh = body_box_h(sy, top)
  Lay{
    Rect{0, 0, cols, 1},
    Rect{0, 1, cols, 1},
    Rect{0, top, mid, bh},
    Rect{mid, top, nick_w(cols, mid), bh},
    Rect{0, sy, cols, 1}
  }

def inner_x(+x: U32) -> U32:
  U32.add(x, 1)

def inner_w.on(+w: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      U32.sub(w, 2)
    case False{}:
      w

def inner_w(+w: U32) -> U32:
  inner_w.on(w, U32.is_ge(w, 2))

def inner_last.on(+y: U32, +h: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      U32.sub(U32.add(y, h), 2)
    case False{}:
      U32.sub(U32.add(y, h), 1)

def inner_last(+y: U32, +h: U32) -> U32:
  inner_last.on(y, h, U32.is_ge(h, 3))

def inner_min.on(+y: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      U32.add(y, 1)
    case False{}:
      y

def inner_min(+y: U32, +h: U32) -> U32:
  inner_min.on(y, U32.is_ge(h, 3))

def box_max_y(+y: U32, +h: U32) -> U32:
  U32.sub(U32.add(y, h), 1)

def body_y0.pick(+cand: U32, +min_y: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      cand
    case False{}:
      min_y

def body_y0(+y: U32, +h: U32, +n: U32) -> U32:
  +last = inner_last(y, h)
  +min_y = inner_min(y, h)
  +cand = U32.sub(U32.add(last, 1), n)
  body_y0.pick(cand, min_y, U32.is_ge(cand, min_y))

def last_body_row.box(r: Rect) -> U32:
  match r:
    case Rect{_, y, _, h}:
      inner_last(y, h)

def last_body_row.of(lay0: Lay) -> U32:
  match lay0:
    case Lay{_, _, br, _, _}:
      last_body_row.box(br)

def last_body_row(+rows: U32) -> U32:
  last_body_row.of(lay(rows, 80))

def vis_n.on(+have: Nat, +cap: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      cap
    case False{}:
      have

def vis_n(+have: Nat, +cap: Nat) -> Nat:
  vis_n.on(have, cap, Nat.is_ge(have, cap))

def op_box(r: Rect) -> DrawOp:
  match r:
    case Rect{x, y, w, h}:
      OpBox{x, y, w, h}

def op_text(r: Rect, +fg: U32, +text: String) -> DrawOp:
  match r:
    case Rect{x, y, w, _}:
      OpText{x, y, w, fg, 0, text}

def op_tabs(r: Rect, +sel: U32, +names: List<&2, String>) -> DrawOp:
  match r:
    case Rect{x, y, w, _}:
      OpTabs{x, y, w, sel, names}

def body_ops.go(xs: List<&2, Cl.Line>, +x: U32, +y: U32, +w: U32) -> List<&2, DrawOp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      line_op.at(x, y, w, h) <> body_ops.go(t, x, U32.add(y, 1), w)

def body_ops(r: Rect, +xs: List<&2, Cl.Line>) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, w, h}:
      +n = U32.from_nat(List.length(&2, Cl.Line, xs))
      body_ops.go(xs, inner_x(x), body_y0(y, h, n), inner_w(w))

def nick_ops.go(xs: List<&2, String>, ok: Bool, +x: U32, +y: U32, +w: U32, +fg: U32, +max_y: U32) -> List<&2, DrawOp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      match ok:
        case False{}:
          Nil{}
        case True{}:
          OpText{x, y, w, fg, 0, h}
            <> nick_ops.go(t, U32.is_lt(U32.add(y, 1), max_y), x, U32.add(y, 1), w, fg, max_y)

def nick_ops.wide(+x: U32, +y: U32, +w: U32, +h: U32, +title: String, +names: List<&2, String>, wide: Bool) -> List<&2, DrawOp>:
  match wide:
    case False{}:
      Nil{}
    case True{}:
      +ix = inner_x(x)
      +iw = inner_w(w)
      +fg = FG_DIM()
      +y1 = U32.add(y, 1)
      +max_y = box_max_y(y, h)
      OpBox{x, y, w, h}
        <> OpText{ix, y, iw, fg, 0, title}
        <> nick_ops.go(names, U32.is_lt(y1, max_y), ix, y1, iw, fg, max_y)

def nick_ops(r: Rect, +title: String, +names: List<&2, String>) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, +w, h}:
      nick_ops.wide(x, y, w, h, title, names, U32.is_gt(w, 2))

def view_ops.rest(+br: Rect, +bod: List<&2, Cl.Line>, +nr: Rect, +title: String, +nicks: List<&2, String>, +sr: Rect, +st: String) -> List<&2, DrawOp>:
  List.append(&2, DrawOp, body_ops(br, bod),
    List.append(&2, DrawOp, nick_ops(nr, title, nicks),
      op_text(sr, FG_DIM(), st) <> Nil{}))

def view_ops(
  lay0: Lay,
  +h: String,
  +active: Nat,
  +names: List<&2, String>,
  +bod: List<&2, Cl.Line>,
  +title: String,
  +nicks: List<&2, String>,
  +st: String
) -> List<&2, DrawOp>:
  match lay0:
    case Lay{hr, tr, +br, nr, sr}:
      op_text(hr, FG_TEXT(), h)
        <> op_tabs(tr, U32.from_nat(active), names)
        <> op_box(br)
        <> view_ops.rest(br, bod, nr, title, nicks, sr, st)

def view_draft(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      h bod = header_of.buf(nick, server, b, net) body_of.buf(b, vis_h(rows))
      title ns = nicks_title_of(b) nicks_list_of(b)
      ViewModel{view_ops(lay(rows, cols), h, active, tab_names(bufs), bod, title, ns, status_of.buf(b)), view_input(draft)}

def dummy_line(+i: Nat) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", "L" ++ Nat.show(i)}

def dummy_lines.go(n: Nat, +i: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      dummy_line(i) <> dummy_lines.go(p, 1n+i)

def dummy_cl(+n: Nat) -> Cl.Client:
  Cl.Client{"me", "s", Cl.Buffer{"server", False{}, "", dummy_lines.go(n, 0n), Nil{}, 0n} <> Nil{}, 0n, ""}

def body_line_ys.go(ops: List<&2, DrawOp>) -> List<&2, U32>:
  match ops:
    case Nil{}:
      Nil{}
    case Con{OpLine{_, y, _, _, _, _}, t}:
      y <> body_line_ys.go(t)
    case Con{_, t}:
      body_line_ys.go(t)

def body_ys.of(vm: ViewModel) -> List<&2, U32>:
  match vm:
    case ViewModel{ops, _}:
      body_line_ys.go(ops)

def body_ys(+rows: U32, +nlines: Nat) -> List<&2, U32>:
  body_ys.of(view_draft(dummy_cl(nlines), rows, 80, "", "demo"))

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
# row, and the count is min(lines, vis_h) = Sess.body_h(rows).
def body_ys_case(+rows: U32, +nlines: Nat) -> Bool:
  +ys = body_ys(rows, nlines)
  Nat.is_eq(List.length(&2, U32, ys), vis_n(nlines, vis_h(rows)))
    && U32.is_eq(ys_last(ys), last_body_row(rows))
    && ys_inc(ys)

def lay_body_ok(l: Lay, +want_y: U32, +want_h: U32, +want_sy: U32) -> Bool:
  match l:
    case Lay{_, _, Rect{_, +by, _, +bh}, _, Rect{_, +sy, _, _}}:
      U32.is_eq(by, want_y) && U32.is_eq(bh, want_h) && U32.is_eq(sy, want_sy) && U32.is_le(U32.add(by, bh), sy)

def ys_clear_chrome(+rows: U32) -> Bool:
  +last = ys_last(body_ys(rows, 8n))
  U32.is_lt(last, status_y(rows)) && U32.is_lt(last, U32.sub(rows, 1))

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
    && lay_body_ok(lay(4, 80), 1, 1, 2)
    && lay_body_ok(lay(24, 80), 2, 20, 22)
    && ys_clear_chrome(4)
    && ys_clear_chrome(5)
    && ys_clear_chrome(6)
    && ys_clear_chrome(7)
    && ys_clear_chrome(8)
    && Nat.is_eq(vis_h(24), Sess.body_h(24))
    && Nat.is_eq(vis_h(6), Sess.body_h(6))
    && Nat.is_eq(vis_h(7), Sess.body_h(7))

def scroll_bounds_ok.fin(+c: Nat, +m: Nat, +count: Nat, +height: Nat) -> Bool:
  Nat.is_eq(c, clamp_scroll(c, count, height)) && Nat.is_le(c, m)

def scroll_bounds_ok(+scroll: Nat, +count: Nat, +height: Nat) -> Bool:
  scroll_bounds_ok.fin(clamp_scroll(scroll, count, height), scroll_max(count, height), count, height)
