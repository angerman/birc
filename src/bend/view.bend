# View model from Client. Pure scroll math + DrawOp list for the paint FFI.
import Base
import ./client.bend as Cl

# Live paint ops. C walks the list inside one Timui.frame (no packed wire).
# Attr bits match timui.h: bold=1, italic=4.
type SpanOp is Data:
  Spn{attrs: U32, text: String}
  Lnk{url: String, text: String}

type BodyLn is Data:
  BodyLn{fg: U32, ts: String, spans: List<&2, SpanOp>}

type DrawOp is Data:
  OpHeader{text: String}
  OpTabs{sel: U32, names: List<&2, String>}
  OpBody{lines: List<&2, BodyLn>}
  OpNicks{title: String, names: List<&2, String>}
  OpStatus{text: String}

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

# Packed paint wire is the live API (C interprets k|ts|spans). TextSpan is
# the tokenize law type.
type TextSpan is Data:
  Plain{text: String}
  Bold{text: String}
  Italic{text: String}
  Code{text: String}
  Link{url: String, text: String}

def TS_WIDTH() -> Nat:
  8n

def kind_code(k: Cl.LineKind) -> U32:
  match k:
    case Cl.Msg{}:
      0
    case Cl.Self{}:
      1
    case Cl.System{}:
      2
    case Cl.Action{}:
      3
    case Cl.Notice{}:
      4
    case Cl.Error{}:
      5

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

def UNIT() -> Char:
  Chr{31}

def GS() -> Char:
  Chr{29}

def kind_digit(k: Cl.LineKind) -> String:
  match k:
    case Cl.Msg{}:
      "0"
    case Cl.Self{}:
      "1"
    case Cl.System{}:
      "2"
    case Cl.Action{}:
      "3"
    case Cl.Notice{}:
      "4"
    case Cl.Error{}:
      "5"

def kind_code_ok() -> Bool:
  String.eq(kind_digit(Cl.Msg{}), "0")
    && String.eq(kind_digit(Cl.Self{}), "1")
    && String.eq(kind_digit(Cl.System{}), "2")
    && String.eq(kind_digit(Cl.Action{}), "3")
    && String.eq(kind_digit(Cl.Notice{}), "4")
    && String.eq(kind_digit(Cl.Error{}), "5")

def pack_span(sp: TextSpan) -> String:
  match sp:
    case Plain{+tx}:
      SCon{Chr{80}, tx}
    case Bold{+tx}:
      SCon{Chr{66}, tx}
    case Italic{+tx}:
      SCon{Chr{73}, tx}
    case Code{+tx}:
      SCon{Chr{67}, tx}
    case Link{+url, +text}:
      SCon{Chr{76}, url ++ SCon{GS(), text}}

def pack_spans.cons(+acc: String, +chunk: String, empty: Bool) -> String:
  match empty:
    case True{}:
      chunk
    case False{}:
      acc ++ SCon{UNIT(), chunk}

def pack_spans.step(acc: String, sp: TextSpan) -> String:
  +a = acc
  pack_spans.cons(a, pack_span(sp), String.is_empty(a))

def pack_spans(+xs: List<&2, TextSpan>) -> String:
  List.foldl(~&2, ~TextSpan, ~String, ~pack_spans.step, xs, "")

def pack_line(+ln: Cl.Line) -> String:
  match ln:
    case Cl.Line{+k, +ts, +text}:
      U32.show(style_of(k)) ++ "|" ++ ts ++ "|" ++ pack_spans(tokenize(text)) ++ "\n"

def pack_fg_ok() -> Bool:
  String.starts_with(pack_line(Cl.Line{Cl.Msg{}, "", "hi"}), "13158600|")
    && String.starts_with(pack_line(Cl.Line{Cl.Action{}, "", "x"}), "13079274|")

def pack_body.step(acc: String, ln: Cl.Line) -> String:
  acc ++ pack_line(ln)

def pack_body(+xs: List<&2, Cl.Line>) -> String:
  List.foldl(~&2, ~Cl.Line, ~String, ~pack_body.step, xs, "")

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

def line_op(+ln: Cl.Line) -> BodyLn:
  match ln:
    case Cl.Line{+k, +ts, +text}:
      BodyLn{style_of(k), ts, span_ops(tokenize(text))}

def body_lines.go(xs: List<&2, Cl.Line>) -> List<&2, BodyLn>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      line_op(h) <> body_lines.go(t)

def body_of.buf(+b: Cl.Buffer, +height: Nat) -> List<&2, BodyLn>:
  match b:
    case Cl.Buffer{_, _, _, +lines, _, +scroll}:
      body_lines.go(visible_lines(lines, height, scroll))

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

def view_ops(
  +h: String,
  +active: Nat,
  +names: List<&2, String>,
  +bod: List<&2, BodyLn>,
  +title: String,
  +nicks: List<&2, String>,
  +st: String
) -> List<&2, DrawOp>:
  OpHeader{h}
    <> OpTabs{U32.from_nat(active), names}
    <> OpBody{bod}
    <> OpNicks{title, nicks}
    <> OpStatus{st}
    <> Nil{}

def view_draft(+cl: Cl.Client, +height: Nat, +draft: String, +net: String) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      h bod = header_of.buf(nick, server, b, net) body_of.buf(b, height)
      title ns = nicks_title_of(b) nicks_list_of(b)
      ViewModel{view_ops(h, active, tab_names(bufs), bod, title, ns, status_of.buf(b)), view_input(draft)}

def scroll_bounds_ok.fin(+c: Nat, +m: Nat, +count: Nat, +height: Nat) -> Bool:
  Nat.is_eq(c, clamp_scroll(c, count, height)) && Nat.is_le(c, m)

def scroll_bounds_ok(+scroll: Nat, +count: Nat, +height: Nat) -> Bool:
  scroll_bounds_ok.fin(clamp_scroll(scroll, count, height), scroll_max(count, height), count, height)
