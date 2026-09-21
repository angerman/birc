# View model from Client. Pure scroll math + DrawOp list for the paint FFI.
import Base
import ./client.bend as Cl

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

# Spec / C table: Msg=0xC8C8C8 Self=0x59EE3F System=0xA0A0A0
# Action=0xC792EA Notice=0x82AAFF Error=0xF78C6C
def style_spec_ok() -> Bool:
  U32.is_eq(style_of(Cl.Msg{}), 13158600)
    && U32.is_eq(style_of(Cl.Self{}), 5893695)
    && U32.is_eq(style_of(Cl.System{}), 10526880)
    && U32.is_eq(style_of(Cl.Action{}), 13079274)
    && U32.is_eq(style_of(Cl.Notice{}), 8563455)
    && U32.is_eq(style_of(Cl.Error{}), 16223340)

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

type UrlPh is Data:
  UrlRead{}
  UrlStop{}

def take_url.go(fuel: Nat, phase: UrlPh, +s: String, +acc: String, +h: Char, stop: Bool) -> String & String:
  match fuel:
    case 0n:
      (String.reverse(acc), s)
    case 1n+p:
      match phase:
        case UrlRead{}:
          match s:
            case SNil{}:
              (String.reverse(acc), SNil{})
            case SCon{+hd, t}:
              take_url.go(p, UrlStop{}, t, acc, hd, url_stop(hd))
        case UrlStop{}:
          match stop:
            case True{}:
              (String.reverse(acc), SCon{h, s})
            case False{}:
              take_url.go(p, UrlRead{}, s, SCon{h, acc}, h, False{})

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
  take_url.trim(
    take_url.go(Nat.add(2n, Nat.mul(2n, String.length(s))), UrlRead{}, s, "", Chr{0}, False{})
  )

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

def show_spans.one(sp: TextSpan, +acc: String) -> String:
  match sp:
    case Plain{+tx}:
      acc ++ tx
    case Bold{+tx}:
      acc ++ "*" ++ tx ++ "*"
    case Italic{+tx}:
      acc ++ "_" ++ tx ++ "_"
    case Code{+tx}:
      acc ++ "`" ++ tx ++ "`"
    case Link{_, +text}:
      acc ++ text

def show_spans.go(fuel: Nat, +xs: List<&2, TextSpan>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_spans.go(p, t, show_spans.one(h, acc))

def show_spans(+xs: List<&2, TextSpan>) -> String:
  show_spans.go(Nat.add(1n, List.length(&2, TextSpan, xs)), xs, "")

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

type HKPh is Data:
  HKList{}
  HKHit{hit: Bool, rest: List<&2, TextSpan>}

def has_kind.go(fuel: Nat, ph: HKPh, +k: SpanKind, xs: List<&2, TextSpan>) -> Bool:
  match fuel:
    case 0n:
      False{}
    case 1n+p:
      match ph:
        case HKList{}:
          match xs:
            case Nil{}:
              False{}
            case Con{h, t}:
              has_kind.go(p, HKHit{span_hit(k, h), t}, k, Nil{})
        case HKHit{hit, rest}:
          match hit:
            case True{}:
              True{}
            case False{}:
              has_kind.go(p, HKList{}, k, rest)

def has_kind(k: SpanKind, +s: String) -> Bool:
  +xs = tokenize(s)
  has_kind.go(Nat.add(1n, Nat.mul(2n, List.length(&2, TextSpan, xs))), HKList{}, k, xs)

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

def vis_h.on(+rows: U32, ge: Bool) -> Nat:
  match ge:
    case True{}:
      U32.to_nat(U32.sub(rows, 6))
    case False{}:
      1n

def vis_h(+rows: U32) -> Nat:
  vis_h.on(rows, U32.is_ge(rows, 7))

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

def body_box_h.on(+sy: U32, gt: Bool) -> U32:
  match gt:
    case True{}:
      U32.sub(sy, 2)
    case False{}:
      1

def body_box_h(+sy: U32) -> U32:
  body_box_h.on(sy, U32.is_gt(sy, 2))

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
  +bh = body_box_h(sy)
  Lay{
    Rect{0, 0, cols, 1},
    Rect{0, 1, cols, 1},
    Rect{0, 2, mid, bh},
    Rect{mid, 2, nick_w(cols, mid), bh},
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

def inner_last(+y: U32, +h: U32) -> U32:
  U32.sub(U32.add(y, h), 2)

def inner_min(+y: U32) -> U32:
  U32.add(y, 1)

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
  +min_y = inner_min(y)
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

def show_spanop.ital(+tx: String, ital: Bool) -> String:
  match ital:
    case True{}:
      "_" ++ tx ++ "_"
    case False{}:
      tx

def show_spanop.bold(+tx: String, bold: Bool, ital: Bool) -> String:
  match bold:
    case True{}:
      "*" ++ tx ++ "*"
    case False{}:
      show_spanop.ital(tx, ital)

def show_spanop.spn(+attrs: U32, +tx: String) -> String:
  show_spanop.bold(tx, U32.is_eq(attrs, 1), U32.is_eq(attrs, 4))

def show_spanop(sp: SpanOp) -> String:
  match sp:
    case Spn{attrs, +tx}:
      show_spanop.spn(attrs, tx)
    case Lnk{+url, +text}:
      "[" ++ url ++ "]" ++ text

def show_spanops.go(+xs: List<&2, SpanOp>, +acc: String) -> String:
  match xs:
    case Nil{}:
      acc
    case Con{+h, t}:
      show_spanops.go(t, acc ++ show_spanop(h))

def show_spanops(+xs: List<&2, SpanOp>) -> String:
  show_spanops.go(xs, "")

def show_names.cons(+acc: String, +h: String, empty: Bool) -> String:
  match empty:
    case True{}:
      h
    case False{}:
      acc ++ "," ++ h

def show_names.go(+xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}:
      acc
    case Con{+h, t}:
      show_names.go(t, show_names.cons(acc, h, String.is_empty(acc)))

def show_names(+xs: List<&2, String>) -> String:
  show_names.go(xs, "")

def show_op(op: DrawOp) -> String:
  match op:
    case OpBox{x, y, w, h}:
      "X:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h)
    case OpText{_, y, _, _, _, +text}:
      "t:" ++ U32.show(y) ++ "|" ++ text
    case OpTabs{_, _, _, sel, names}:
      "T:" ++ U32.show(sel) ++ "|" ++ show_names(names)
    case OpLine{_, y, _, fg, +ts, spans}:
      "L:" ++ U32.show(y) ++ "|" ++ U32.show(fg) ++ "|" ++ ts ++ "|" ++ show_spanops(spans)

def show_ops.cons(+acc: String, +chunk: String, empty: Bool) -> String:
  match empty:
    case True{}:
      chunk
    case False{}:
      acc ++ ";" ++ chunk

def show_ops.step(acc: String, op: DrawOp) -> String:
  +a = acc
  show_ops.cons(a, show_op(op), String.is_empty(a))

def show_ops(+xs: List<&2, DrawOp>) -> String:
  List.foldl(~&2, ~DrawOp, ~String, ~show_ops.step, xs, "")

def show_vm_ops(+vm: ViewModel) -> String:
  match vm:
    case ViewModel{+ops, _}:
      show_ops(ops)

def draw_line_ok() -> Bool:
  String.eq(
    show_op(line_op(Cl.Line{Cl.Msg{}, "12:00:00", "hello"})),
    "L:0|13158600|12:00:00|hello"
  )

def draw_link_ok() -> Bool:
  String.eq(
    show_op(line_op(Cl.Line{Cl.Msg{}, "", "see https://timui.dev x"})),
    "L:0|13158600||see [https://timui.dev]https://timui.dev x"
  )

def hostile_body() -> String:
  "look "
    ++ SCon{Chr{31}, "Lhttps://evil.example"}
    ++ SCon{Chr{29}, "https://github.com/zw3rk/birc"}
    ++ SCon{Chr{27}, "x"}

def draw_hostile_ok() -> Bool:
  String.eq(
    show_op(line_op(Cl.Line{Cl.Msg{}, "", hostile_body()})),
    "L:0|13158600||look "
      ++ SCon{Chr{31}, "Lhttps://evil.example"}
      ++ SCon{Chr{29}, "[https://github.com/zw3rk/birc]https://github.com/zw3rk/birc"}
      ++ SCon{Chr{27}, "x"}
  )

def draw_tabs_ok() -> Bool:
  String.eq(
    show_op(OpTabs{0, 1, 10, 1, "server" <> "#birc" <> Nil{}}),
    "T:1|server,#birc"
  )

def draw_nicks_ok() -> Bool:
  String.eq(
    show_ops(nick_ops(Rect{0, 2, 8, 10}, "#birc", "me" <> "alice" <> Nil{})),
    "X:0,2,8,10;t:2|#birc;t:3|me;t:4|alice"
  )

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

def body_ys_ok() -> Bool:
  body_ys_case(24, 200n)
    && body_ys_case(90, 200n)
    && body_ys_case(200, 200n)
    && body_ys_case(24, 5n)

def scroll_bounds_ok.fin(+c: Nat, +m: Nat, +count: Nat, +height: Nat) -> Bool:
  Nat.is_eq(c, clamp_scroll(c, count, height)) && Nat.is_le(c, m)

def scroll_bounds_ok(+scroll: Nat, +count: Nat, +height: Nat) -> Bool:
  scroll_bounds_ok.fin(clamp_scroll(scroll, count, height), scroll_max(count, height), count, height)
