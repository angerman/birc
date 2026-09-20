# View model from Client (M5). Pure scroll math + string packing for draw FFI.
import Base
import ./client.bend as Cl

type ViewModel is Data:
  ViewModel{
    header: String,
    tabs: String,
    body: String,
    nicks: String,
    status: String,
    input: String
  }

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

# M5.3 — minimal rich-text: Plain / Bold split on *…*
type TextSpan is Data:
  Plain{text: String}
  Bold{text: String}

def STAR() -> Char:
  Chr{42}

type TokJump is Data:
  Jump{bold: Bool, s: String, acc: String, spans: List<&2, TextSpan>}
  Done{spans: List<&2, TextSpan>}

def tokenize.emit_plain(+acc: String, spans: List<&2, TextSpan>) -> List<&2, TextSpan>:
  match acc:
    case SNil{}:
      spans
    case SCon{_, _}:
      Plain{String.reverse(acc)} <> spans

def tokenize.jump_out(+s: String, +acc: String, +ch: Char, spans: List<&2, TextSpan>, star: Bool) -> TokJump:
  match star:
    case True{}:
      Jump{True{}, s, SNil{}, tokenize.emit_plain(acc, spans)}
    case False{}:
      Jump{False{}, s, SCon{ch, acc}, spans}

def tokenize.jump_in(+s: String, +acc: String, +ch: Char, spans: List<&2, TextSpan>, star: Bool) -> TokJump:
  match star:
    case True{}:
      Jump{False{}, s, SNil{}, Bold{String.reverse(acc)} <> spans}
    case False{}:
      Jump{True{}, s, SCon{ch, acc}, spans}

def tokenize.next_out(+s: String, +acc: String, spans: List<&2, TextSpan>) -> TokJump:
  match s:
    case SNil{}:
      Done{tokenize.emit_plain(acc, spans)}
    case SCon{+h, t}:
      tokenize.jump_out(t, acc, h, spans, Char.is_eq(h, STAR()))

def tokenize.next_in(+s: String, +acc: String, spans: List<&2, TextSpan>) -> TokJump:
  match s:
    case SNil{}:
      Done{Plain{String.reverse(SCon{STAR(), acc})} <> spans}
    case SCon{+h, t}:
      tokenize.jump_in(t, acc, h, spans, Char.is_eq(h, STAR()))

def tokenize.next(bold: Bool, +s: String, +acc: String, spans: List<&2, TextSpan>) -> TokJump:
  match bold:
    case False{}:
      tokenize.next_out(s, acc, spans)
    case True{}:
      tokenize.next_in(s, acc, spans)

def tokenize.force_done_bold(bold: Bool, +acc: String, spans: List<&2, TextSpan>) -> List<&2, TextSpan>:
  match bold:
    case False{}:
      List.reverse(&2, TextSpan, tokenize.emit_plain(acc, spans))
    case True{}:
      List.reverse(&2, TextSpan, Plain{String.reverse(SCon{STAR(), acc})} <> spans)

def tokenize.force_done(j: TokJump) -> List<&2, TextSpan>:
  match j:
    case Done{spans}:
      List.reverse(&2, TextSpan, spans)
    case Jump{+bold, +s, +acc, spans}:
      tokenize.force_done_bold(bold, acc, spans)

def tokenize.go(fuel: Nat, j: TokJump) -> List<&2, TextSpan>:
  match fuel:
    case 0n:
      tokenize.force_done(j)
    case 1n+p:
      match j:
        case Done{spans}:
          List.reverse(&2, TextSpan, spans)
        case Jump{+bold, +s, +acc, spans}:
          tokenize.go(p, tokenize.next(bold, s, acc, spans))

def tokenize(+s: String) -> List<&2, TextSpan>:
  tokenize.go(Nat.add(1n, Nat.mul(2n, String.length(s))), Jump{False{}, s, SNil{}, Nil{}})

def show_spans.one(sp: TextSpan, +acc: String) -> String:
  match sp:
    case Plain{+tx}:
      acc ++ tx
    case Bold{+tx}:
      acc ++ "*" ++ tx ++ "*"

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

def tokenize_has_bold.go(+xs: List<&2, TextSpan>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      match h:
        case Bold{_}:
          True{}
        case Plain{_}:
          tokenize_has_bold.go(t)

def tokenize_has_bold(+s: String) -> Bool:
  tokenize_has_bold.go(tokenize(s))

def show_vis.go(+xs: List<&2, Cl.Line>, +acc: String) -> String:
  match xs:
    case Nil{}:
      acc
    case Con{Cl.Line{_, +text}, t}:
      show_vis.go(t, acc ++ show_spans(tokenize(text)) ++ "\n")

def show_vis(+xs: List<&2, Cl.Line>) -> String:
  show_vis.go(xs, "")

def show_tabs.mark(+name: String, eq: Bool) -> String:
  match eq:
    case True{}:
      "[" ++ name ++ "]"
    case False{}:
      name

def show_tabs.go(+bufs: List<&2, Cl.Buffer>, +active: Nat, +i: Nat, +acc: String) -> String:
  match bufs:
    case Nil{}:
      acc
    case Con{Cl.Buffer{+name, _, _, _, _, _}, t}:
      show_tabs.go(t, active, 1n+i, acc ++ show_tabs.mark(name, Nat.is_eq(i, active)) ++ " ")

def show_tabs(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, +active}:
      show_tabs.go(bufs, active, 0n, "")

def show_nicks_col.go(fuel: Nat, +ns: List<&2, String>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match ns:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_nicks_col.go(p, t, acc ++ h ++ "\n")

def show_nicks_col(+ns: List<&2, String>) -> String:
  show_nicks_col.go(Nat.add(1n, List.length(&2, String, ns)), ns, "")

def active_buf.on(+got: Maybe<&2, Cl.Buffer>) -> Cl.Buffer:
  match got:
    case Some{b}:
      b
    case None{}:
      Cl.server_buf()

def active_buf(+cl: Cl.Client) -> Cl.Buffer:
  match cl:
    case Cl.Client{_, _, +bufs, +active}:
      active_buf.on(Cl.nth_buf(bufs, active))

def header_of.buf(+nick: String, +server: String, +b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, +topic, _, _, _}:
      nick ++ "@" ++ server ++ " " ++ name ++ " — " ++ topic

def header_of(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{+nick, +server, _, _}:
      header_of.buf(nick, server, active_buf(cl))

def pad_top(n: Nat, +s: String) -> String:
  match n:
    case 0n:
      s
    case 1n+p:
      pad_top(p, SCon{Chr{10}, s})

def pad_n.on(ge: Bool, +height: Nat, +k: Nat) -> Nat:
  match ge:
    case True{}:
      Nat.sub(height, k)
    case False{}:
      0n

def pad_n(+height: Nat, +k: Nat) -> Nat:
  pad_n.on(Nat.is_ge(height, k), height, k)

def body_of.buf(+b: Cl.Buffer, +height: Nat) -> String:
  match b:
    case Cl.Buffer{_, _, _, +lines, _, +scroll}:
      +vis = visible_lines(lines, height, scroll)
      pad_top(pad_n(height, List.length(&2, Cl.Line, vis)), show_vis(vis))

def body_of(+cl: Cl.Client, +height: Nat) -> String:
  body_of.buf(active_buf(cl), height)

def nicks_of.buf(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _}:
      show_nicks_col(nicks)

def nicks_of(+cl: Cl.Client) -> String:
  nicks_of.buf(active_buf(cl))

def status_of.buf(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _}:
      "/join /part /msg /nick /me  ·  Shift+Left/Right  ·  Esc  ·  "
        ++ Nat.show(List.length(&2, String, nicks))
        ++ " nicks"

def status_of(+cl: Cl.Client) -> String:
  status_of.buf(active_buf(cl))

def view_input(+draft: String) -> String:
  "> " ++ draft

def view_draft(+cl: Cl.Client, +height: Nat, +draft: String) -> ViewModel:
  # M1.8: bind the active buffer once, then three independent parallel packs.
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      h t = header_of.buf(nick, server, b) show_tabs(cl)
      bod ns = body_of.buf(b, height) nicks_of.buf(b)
      st inp = status_of.buf(b) view_input(draft)
      ViewModel{h, t, bod, ns, st, inp}

def view(+cl: Cl.Client, +height: Nat) -> ViewModel:
  view_draft(cl, height, "")

def show_vm(+vm: ViewModel) -> String:
  match vm:
    case ViewModel{+h, +t, +b, +n, +s, +inp}:
      "H:" ++ h ++ "|T:" ++ t ++ "|B:" ++ b ++ "|N:" ++ n ++ "|S:" ++ s ++ "|I:" ++ inp

def scroll_bounds_ok.fin(+c: Nat, +m: Nat, +count: Nat, +height: Nat) -> Bool:
  Nat.is_eq(c, clamp_scroll(c, count, height)) && Nat.is_le(c, m)

def scroll_bounds_ok(+scroll: Nat, +count: Nat, +height: Nat) -> Bool:
  scroll_bounds_ok.fin(clamp_scroll(scroll, count, height), scroll_max(count, height), count, height)
