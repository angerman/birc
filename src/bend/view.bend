# View model from Client. Pure scroll math + DrawOp list for the paint FFI.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./split.bend as Sp
import ./links.bend as Links
import ./wire_style.bend as Ws
import ./columns.bend as Cols
import ./media.bend as M
import ./theme.bend as Theme

# Live paint ops. C walks the list inside one Timui.frame (no packed wire).
# Bend owns layout and assigns every line its y. Attr bits: bold=1, italic=4.
type SpanOp is Data:
  Spn{attrs: U32, text: String}
  Lnk{url: String, text: String}
  Col{attrs: U32, fg: U32, text: String}

def span_text(sp: SpanOp) -> String:
  match sp:
    case Spn{_, text}: text
    case Lnk{_, text}: text
    case Col{_, _, text}: text

def span_text_as(sp: SpanOp, text: String) -> SpanOp:
  match sp:
    case Spn{attrs, _}: Spn{attrs, text}
    case Lnk{url, _}: Lnk{url, text}
    case Col{attrs, fg, _}: Col{attrs, fg, text}

def spans_chars(xs: List<&2, SpanOp>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{sp, t}: Nat.add(String.length(span_text(sp)), spans_chars(t))

def spans_text(xs: List<&2, SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{sp, t}: span_text(sp) ++ spans_text(t)

def span_style_eq(a: SpanOp, b: SpanOp) -> Bool:
  match a b:
    case Spn{attrs, _} Spn{other, _}: U32.is_eq(attrs, other)
    case Col{attrs, fg, _} Col{other, color, _}: U32.is_eq(attrs, other) && U32.is_eq(fg, color)
    case Lnk{url, _} Lnk{other, _}: String.eq(url, other)
    case _ _: False{}

def spans_drop.on(whole: Bool, +sp: SpanOp, rest: List<&2, SpanOp>, +n: Nat, len: Nat, k: Nat -> List<&2, SpanOp>) -> List<&2, SpanOp>:
  match whole:
    case True{}: k(Nat.sub(n, len))
    case False{}: span_text_as(sp, String.drop(span_text(sp), n)) <> rest

def spans_drop(xs: List<&2, SpanOp>, +n: Nat) -> List<&2, SpanOp>:
  match xs:
    case Nil{}: Nil{}
    case Con{+sp, +rest}:
      +len = String.length(span_text(sp))
      spans_drop.on(Nat.is_ge(n, len), sp, rest, n, len, remaining => spans_drop(rest, remaining))

# The accumulator stores reversed text and runs. A cluster has the style of
# its leading scalar, even when source formatting changes inside that cluster.
def cluster_push.same(same: Bool, +sp: SpanOp, text: String, +prev: SpanOp, rest: List<&2, SpanOp>) -> List<&2, SpanOp>:
  match same:
    case True{}: span_text_as(prev, text ++ span_text(prev)) <> rest
    case False{}: span_text_as(sp, text) <> (prev <> rest)

def cluster_push(+sp: SpanOp, text: String, rev: List<&2, SpanOp>) -> List<&2, SpanOp>:
  match rev:
    case Nil{}: span_text_as(sp, text) <> Nil{}
    case Con{+prev, rest}: cluster_push.same(span_style_eq(sp, prev), sp, text, prev, rest)

def cluster_finish(xs: List<&2, SpanOp>) -> List<&2, SpanOp>:
  match xs:
    case Nil{}: Nil{}
    case Con{+sp, t}: span_text_as(sp, String.reverse(span_text(sp))) <> cluster_finish(t)

def cluster_spans.piece(piece: Cols.Cut, xs: List<&2, SpanOp>, rev: List<&2, SpanOp>, k: String -> List<&2, SpanOp> -> List<&2, SpanOp> -> List<&2, SpanOp>) -> List<&2, SpanOp>:
  match piece xs:
    case Cols.Cut{+head, tail, _} Con{+sp, +rest}:
      k(tail, spans_drop(sp <> rest, String.length(head)), cluster_push(sp, String.reverse(head), rev))
    case _ _: cluster_finish(List.reverse(&2, SpanOp, rev))

def cluster_spans.go(fuel: Nat, +text: String, xs: List<&2, SpanOp>, rev: List<&2, SpanOp>) -> List<&2, SpanOp>:
  match fuel:
    case 0n: cluster_finish(List.reverse(&2, SpanOp, rev))
    case 1n+p:
      match text:
        case SNil{}: cluster_finish(List.reverse(&2, SpanOp, rev))
        case SCon{_, _}: cluster_spans.piece(Cols.cluster(text), xs, rev, remaining => rest => acc => cluster_spans.go(p, remaining, rest, acc))

def cluster_spans(+xs: List<&2, SpanOp>) -> List<&2, SpanOp>:
  +text = spans_text(xs)
  cluster_spans.go(Nat.add(1n, String.length(text)), text, spans_drop(xs, 0n), Nil{})

type Rect is Data:
  Rect{x: U32, y: U32, w: U32, h: U32}

type DrawOp is Data:
  OpBox{x: U32, y: U32, w: U32, h: U32}
  OpSplit{x: U32, y: U32, w: U32, h: U32, axis: U32}
  OpText{x: U32, y: U32, w: U32, fg: U32, attrs: U32, text: String}
  OpTabs{x: U32, y: U32, w: U32, sel: U32, names: List<&2, String>, alerts: List<&2, U32>, bell: U32, bell_seq: U32}
  OpLine{x: U32, y: U32, w: U32, fg: U32, spans: List<&2, SpanOp>}
  OpImage{x: U32, y: U32, w: U32, h: U32, path: String}
  OpMedia{x: U32, y: U32, w: U32, h: U32, clip_y: U32, clip_h: U32, token: U32}

type Lay is Data:
  Lay{tabs: Rect, user: Rect, body: Rect, nicks: Rect, status: Rect}


type ViewModel is Data:
  ViewModel{ops: List<&2, DrawOp>, input: String}

type BodyRow is Data:
  BodyRow{ts: String, ts_w: U32, off: U32, w: U32, fg: U32, spans: List<&2, SpanOp>, source_chars: Nat}
  BodyRecon{text: String, w: U32}
  BodyMedia{token: U32, w: U32, h: U32, row: U32}

# Width-independent card paint data (C8 live). Cards.bend formats ready-card
# texts (title-or-URL, description, thumbnail reference); this module only
# wraps them at pane width under the anchor line. CardEntry keeps View free of
# a cards.bend import (cards.bend already imports this module for BodyRow).
type CardEntry is Data:
  CardEntry{id: Nat, texts: List<&2, String>}

# One ready card paints at most this many text rows. Pinned equal to
# Cards.ROWS_MAX by law (cards_rows_cap_matches); the cap lives here so the
# wrap cascade needs no cards import.
def card_rows_cap() -> Nat:
  4n

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

def TS_WIDTH() -> Nat:
  8n

def style_of(k: Cl.LineKind) -> U32:
  Theme.kind_fg(Theme.default(), k)

def active_buf.on(+got: Maybe<&2, Cl.Buffer>) -> Cl.Buffer:
  match got:
    case Some{b}:
      b
    case None{}:
      Cl.server_buf()

def user_host_label.empty(+base: String, +net: String, empty: Bool) -> String:
  match empty:
    case True{}:
      base
    case False{}:
      base ++ " · " ++ net

def user_host_label(+nick: String, +server: String, +net: String) -> String:
  +base = nick ++ "@" ++ server
  user_host_label.empty(base, net, String.is_empty(net))

def status_color(+net: String) -> U32:
  Theme.status_of(Theme.default(), net)


# Live rendering maps wire-styled lexical runs directly. There is ONE accepted
# render path: every production paint entry (live, unthemed, and themed)
# routes through render_spans (Ws.render); only the palette varies. Wire
# codes are opaque
# boundaries for markdown: each style run lexes separately, and a URL keeps
# its link only when it would linkify in the glued visible text. The
# proof-only tokenizer adapter lives in view_laws.bend, not in this path.
def render_run.styled(+has_fg: Bool, +attrs: U32, +fg: U32, +text: String) -> SpanOp:
  match has_fg:
    case True{}: Col{attrs, fg, text}
    case False{}: Spn{attrs, text}

def render_run.url(+url: Maybe<&2, String>, +attrs: U32, +fg: U32, +has_fg: Bool, +text: String) -> SpanOp:
  match url:
    case None{}: render_run.styled(has_fg, attrs, fg, text)
    case Some{+link}: Lnk{link, text}

def render_run(run: Ws.SRun) -> SpanOp:
  match run:
    case Ws.SRun{+attrs, +fg, +has_fg, +text, +url}: render_run.url(url, attrs, fg, has_fg, text)

def render_runs(runs: List<&2, Ws.SRun>) -> List<&2, SpanOp>:
  match runs:
    case Nil{}: Nil{}
    case Con{h, t}: render_run(h) <> render_runs(t)

def render_spans(text: String) -> List<&2, SpanOp>:
  render_runs(Ws.render(text))

def FG_TEXT() -> U32:
  13158600

def FG_DIM() -> U32:
  10526880

def bounded_width(+w: U32, +cap: U32) -> U32:
  Bool.pick(U32, U32.is_le(w, cap), w, cap)

def user_header_ops.split(r: Rect, +base: String, +net: String, empty: Bool) -> List<&2, DrawOp>:
  match r:
    case Rect{+x, +y, +w, _}:
      match empty:
        case True{}:
          OpText{x, y, w, FG_DIM(), 0, base} <> Nil{}
        case False{}:
          +pfx = base ++ " · "
          +pw = bounded_width(Cols.text_width(pfx), w)
          +nw = bounded_width(Cols.text_width(net), U32.sub(w, pw))
          OpText{x, y, pw, FG_DIM(), 0, pfx}
            <> (OpText{U32.add(x, pw), y, nw, status_color(net), 1, net} <> Nil{})

def user_header_ops.visible(hidden: Bool, r: Rect, +base: String, +net: String) -> List<&2, DrawOp>:
  match hidden:
    case True{}: Nil{}
    case False{}: user_header_ops.split(r, base, net, String.is_empty(net))

def user_header_ops(r: Rect, +nick: String, +server: String, +net: String) -> List<&2, DrawOp>:
  match r:
    case Rect{+x, +y, +w, +h}:
      user_header_ops.visible(U32.is_zero(w) || U32.is_zero(h), Rect{x, y, w, h}, nick ++ "@" ++ server, net)

# Timestamp is an OpText of at most 8 columns, then one space, then the
# line. A narrow body clips the stamp to w so it cannot spill past the line.
def ts_w.on(+w: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      8
    case False{}:
      w

def ts_w(+w: U32) -> U32:
  ts_w.on(w, U32.is_ge(w, 8))

def line_shift.on(+w: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      9
    case False{}:
      w

def line_shift(+w: U32) -> U32:
  line_shift.on(w, U32.is_ge(w, 9))

def line_rest(+w: U32) -> U32:
  U32.sub(w, line_shift(w))

def nick_hash.char(+c: Char, +h: U32) -> U32:
  U32.add(U32.mul(h, 33), Irc.code_of(c))

def nick_hash.go(s: String, +h: U32) -> U32:
  match s:
    case SNil{}:
      h
    case SCon{c, t}:
      nick_hash.go(t, nick_hash.char(c, h))

def nick_hash(+s: String) -> U32:
  nick_hash.go(s, 5381)

# Canonical nick palette lives in theme.bend; the default theme keeps these values.
def nick_color_idx(+idx: U32) -> U32:
  Theme.nick_row(Theme.default(), idx)

def nick_color(+nick: String) -> U32:
  nick_color_idx(U32.and(nick_hash(nick), 15))

# Fixed adapters use Theme.default(); themed adapters use their supplied Id.
def style_of_themed(+id: Theme.Id, k: Cl.LineKind) -> U32:
  Theme.kind_fg(id, k)

def nick_color_themed(+id: Theme.Id, +nick: String) -> U32:
  Theme.nick_row(id, U32.and(nick_hash(nick), 15))

def status_color_themed(+id: Theme.Id, +net: String) -> U32:
  Theme.status_of(id, net)

def take_until_gt.cons(+h: Char, r: String & String) -> String & String:
  match r:
    case (tok, rest):
      (SCon{h, tok}, rest)

def take_until_gt.fin(+h: Char, +t: String, r: String & String, hit: Bool) -> String & String:
  match hit:
    case True{}:
      ("", t)
    case False{}:
      take_until_gt.cons(h, r)

def take_until_gt(s: String) -> String & String:
  match s:
    case SNil{}:
      ("", "")
    case SCon{+h, +t}:
      take_until_gt.fin(h, t, take_until_gt(t), Char.is_eq(h, '>'))

def parse_nick_msg.body(+rest: String, +nick: String) -> List<&2, SpanOp>:
  match rest:
    case SNil{}:
      render_spans("<" ++ nick ++ ">")
    case SCon{_, body}:
      Spn{0, "<"}
        <> (Col{1, nick_color(nick), nick}
        <> (Spn{0, "> "}
        <> render_spans(body)))

def parse_nick_msg.ok(ok: Bool, +rest: String, +nick: String, original: String) -> List<&2, SpanOp>:
  match ok:
    case True{}:
      parse_nick_msg.body(rest, nick)
    case False{}:
      render_spans(original)

def parse_nick_msg.parsed(pair: String & String, original: String) -> List<&2, SpanOp>:
  match pair:
    case (+nick, +rest):
      parse_nick_msg.ok(String.starts_with(rest, " ") && Bool.not(String.is_empty(nick)), rest, nick, original)

def parse_nick_msg.head(is_lt: Bool, +t: String, +s: String) -> List<&2, SpanOp>:
  match is_lt:
    case True{}:
      parse_nick_msg.parsed(take_until_gt(t), s)
    case False{}:
      render_spans(s)

def parse_nick_msg.con(+c: Char, +t: String, +s: String) -> List<&2, SpanOp>:
  parse_nick_msg.head(Char.is_eq(c, '<'), t, s)

def parse_nick_msg(s: String) -> List<&2, SpanOp>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{+c, +t}:
      parse_nick_msg.con(c, t, s)

def parse_nick_act.body(+rest: String, +nick: String) -> List<&2, SpanOp>:
  match rest:
    case SNil{}:
      render_spans("* " ++ nick)
    case SCon{_, body}:
      Spn{0, "* "}
        <> (Col{1, nick_color(nick), nick}
        <> (Spn{0, " "}
        <> render_spans(body)))

def parse_nick_act.ok(ok: Bool, +rest: String, +nick: String) -> List<&2, SpanOp>:
  match ok:
    case True{}:
      parse_nick_act.body(rest, nick)
    case False{}:
      render_spans("* " ++ nick ++ rest)

def parse_nick_act.parsed(pair: String & String) -> List<&2, SpanOp>:
  match pair:
    case (+nick, +rest):
      parse_nick_act.ok(String.starts_with(rest, " ") && Bool.not(String.is_empty(nick)), rest, nick)

def parse_nick_act.rest(+t2: String) -> List<&2, SpanOp>:
  parse_nick_act.parsed(Irc.take_until_space(t2))

def parse_nick_act.sp(is_sp: Bool, +t2: String, +s: String) -> List<&2, SpanOp>:
  match is_sp:
    case True{}:
      parse_nick_act.rest(t2)
    case False{}:
      render_spans(s)

def parse_nick_act.t1(+t1: String, +s: String) -> List<&2, SpanOp>:
  match t1:
    case SNil{}:
      render_spans(s)
    case SCon{+c2, +t2}:
      parse_nick_act.sp(Char.is_eq(c2, ' '), t2, s)

def parse_nick_act.star(is_star: Bool, +t1: String, +s: String) -> List<&2, SpanOp>:
  match is_star:
    case True{}:
      parse_nick_act.t1(t1, s)
    case False{}:
      render_spans(s)

def parse_nick_act(s: String) -> List<&2, SpanOp>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{+c1, +t1}:
      parse_nick_act.star(Char.is_eq(c1, '*'), t1, s)

def line_spans_raw(k: Cl.LineKind, +text: String) -> List<&2, SpanOp>:
  match k:
    case Cl.Msg{}:
      parse_nick_msg(text)
    case Cl.Self{}:
      parse_nick_msg(text)
    case Cl.Highlight{}:
      parse_nick_msg(text)
    case Cl.Action{}:
      parse_nick_act(text)
    case _:
      render_spans(text)

def line_spans_for(k: Cl.LineKind, text: String) -> List<&2, SpanOp>:
  cluster_spans(line_spans_raw(k, text))

def line_ops_go(
  +x: U32,
  +y: U32,
  +w: U32,
  +fg: U32,
  +ts: String,
  +spans: List<&2, SpanOp>,
  empty: Bool
) -> List<&2, DrawOp>:
  match empty:
    case True{}:
      OpLine{x, y, w, fg, spans} <> Nil{}
    case False{}:
      OpText{x, y, ts_w(w), FG_DIM(), 0, ts}
        <> (OpLine{U32.add(x, line_shift(w)), y, line_rest(w), fg, spans} <> Nil{})

def repeat_dash.go(fuel: Nat, acc: String) -> String:
  match fuel:
    case 0n: acc
    case 1n+p: repeat_dash.go(p, "─" ++ acc)

def repeat_dash(n: Nat) -> String:
  repeat_dash.go(n, "")

def recon_label.ts(empty: Bool, +ts: String) -> String:
  match empty:
    case True{}: " Reconnected "
    case False{}: " Reconnected: " ++ ts ++ " "

def recon_label(+text: String) -> String:
  recon_label.ts(String.is_empty(text), text)

def recon_divider.gt(gt: Bool, +lbl: String, +lbl_w: U32, +w: U32) -> String:
  match gt:
    case False{}:
      lbl
    case True{}:
      +rem = U32.sub(w, lbl_w)
      +half = U32.to_nat(U32.div(rem, 2))
      +rest = U32.to_nat(U32.sub(rem, U32.div(rem, 2)))
      repeat_dash(half) ++ lbl ++ repeat_dash(rest)

def recon_divider(+text: String, +w: U32) -> String:
  +lbl = recon_label(text)
  +lbl_w = U32.from_nat(String.length(lbl))
  recon_divider.gt(U32.is_gt(w, lbl_w), lbl, lbl_w, w)

def line_ops_at_ts.recon(+x: U32, +y: U32, +w: U32, +text: String) -> List<&2, DrawOp>:
  OpText{x, y, w, FG_DIM(), 0, recon_divider(text, w)} <> Nil{}

def line_ops_at_ts.chk(is_rec: Bool, +x: U32, +y: U32, +w: U32, +k: Cl.LineKind, +ts: String, +text: String, show_ts: Bool) -> List<&2, DrawOp>:
  match is_rec:
    case True{}:
      line_ops_at_ts.recon(x, y, w, text)
    case False{}:
      line_ops_go(x, y, w, style_of(k), ts, line_spans_for(k, text), Bool.not(show_ts) || String.is_empty(ts))

def line_ops_at_ts(+x: U32, +y: U32, +w: U32, +ln: Cl.Line, show_ts: Bool) -> List<&2, DrawOp>:
  match ln:
    case Cl.Line{+k, +ts, +text, +author, +id}:
      line_ops_at_ts.chk(Cl.is_reconnect(k), x, y, w, k, ts, text, show_ts)

def line_ops_at(+x: U32, +y: U32, +w: U32, +ln: Cl.Line) -> List<&2, DrawOp>:
  line_ops_at_ts(x, y, w, ln, True{})

def line_ops(+ln: Cl.Line) -> List<&2, DrawOp>:
  line_ops_at(0, 0, 40, ln)

def wrap_cap(+w: U32) -> U32:
  Bool.pick(U32, U32.is_zero(w), 1, w)

type SpanCut is Data:
  SpanCut{head: List<&2, SpanOp>, tail: List<&2, SpanOp>}

# A narrow pane may replace one whole cluster with a single glyph. Keep the
# number of consumed source characters separate from the painted text so
# resize-safe anchors still refer to the same source position.
type WrapChunk is Data:
  WrapChunk{shown: List<&2, SpanOp>, source_chars: Nat}

def span_cut_prepend(sp: SpanOp, cut: SpanCut) -> SpanCut:
  match cut:
    case SpanCut{head, tail}: SpanCut{sp <> head, tail}

def span_cut_partial(empty: Bool, +sp: SpanOp, head: String, tail: String, rest: List<&2, SpanOp>) -> SpanCut:
  match empty:
    case True{}: SpanCut{Nil{}, span_text_as(sp, tail) <> rest}
    case False{}: SpanCut{span_text_as(sp, head) <> Nil{}, span_text_as(sp, tail) <> rest}

def span_cut_text(complete: Bool, +sp: SpanOp, +head: String, tail: String, +width: U32, +cap: U32, rest: List<&2, SpanOp>, k: U32 -> SpanCut) -> SpanCut:
  match complete:
    case True{}: span_cut_prepend(span_text_as(sp, head), k(U32.sub(cap, width)))
    case False{}: span_cut_partial(String.is_empty(head), sp, head, tail, rest)

def span_cut_taken(cut: Cols.Cut, +sp: SpanOp, +cap: U32, rest: List<&2, SpanOp>, k: U32 -> SpanCut) -> SpanCut:
  match cut:
    case Cols.Cut{+head, +tail, +width}:
      span_cut_text(String.is_empty(tail), sp, head, tail, width, cap, rest, k)

def take_spans(xs: List<&2, SpanOp>, +cap: U32) -> SpanCut:
  match xs:
    case Nil{}: SpanCut{Nil{}, Nil{}}
    case Con{+sp, +rest}:
      span_cut_taken(Cols.take(span_text(sp), cap), sp, cap, rest, w => take_spans(rest, w))

def spans_split.on(whole: Bool, +sp: SpanOp, +rest: List<&2, SpanOp>, +n: Nat, len: Nat, k: Nat -> SpanCut) -> SpanCut:
  match whole:
    case True{}: span_cut_prepend(sp, k(Nat.sub(n, len)))
    case False{}: span_cut_partial(Nat.is_eq(n, 0n), sp, String.take(span_text(sp), n), String.drop(span_text(sp), n), rest)

def spans_split(xs: List<&2, SpanOp>, +n: Nat) -> SpanCut:
  match xs:
    case Nil{}: SpanCut{Nil{}, Nil{}}
    case Con{+sp, +rest}:
      +len = String.length(span_text(sp))
      spans_split.on(Nat.is_ge(n, len), sp, rest, n, len, remaining => spans_split(rest, remaining))

# Break only at complete IRC spaces, not a space with attached combining marks.
# Keep the start of the last space run, so all its boundary padding is hidden.
def word_break.piece(piece: Cols.Cut, +pos: Nat, last: Maybe<&2, Nat>, +in_space: Bool, k: String -> Nat -> Maybe<&2, Nat> -> Bool -> Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match piece:
    case Cols.Cut{+head, tail, _}:
      +space = String.eq(head, " ")
      k(tail, Nat.add(pos, String.length(head)), Bool.pick(Maybe<&2, Nat>, space && Bool.not(in_space), Some{pos}, last), space)

def word_break.go(fuel: Nat, +s: String, pos: Nat, last: Maybe<&2, Nat>, in_space: Bool) -> Maybe<&2, Nat>:
  match fuel:
    case 0n: last
    case 1n+p:
      match s:
        case SNil{}: last
        case SCon{_, _}: word_break.piece(Cols.cluster(s), pos, last, in_space, rest => n => boundary => space => word_break.go(p, rest, n, boundary, space))

def spans_drop_spaces.piece(space: Bool, +sp: SpanOp, +rest: List<&2, SpanOp>, +tail: String, k: List<&2, SpanOp> -> List<&2, SpanOp>) -> List<&2, SpanOp>:
  match space:
    case False{}: sp <> rest
    case True{}: k(Bool.pick(List<&2, SpanOp>, String.is_empty(tail), rest, span_text_as(sp, tail) <> rest))

def spans_drop_spaces.cut(piece: Cols.Cut, +sp: SpanOp, rest: List<&2, SpanOp>, k: List<&2, SpanOp> -> List<&2, SpanOp>) -> List<&2, SpanOp>:
  match piece:
    case Cols.Cut{head, tail, _}: spans_drop_spaces.piece(String.eq(head, " "), sp, rest, tail, k)

def spans_drop_spaces.go(fuel: Nat, xs: List<&2, SpanOp>) -> List<&2, SpanOp>:
  match fuel:
    case 0n: xs
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+sp, rest}: spans_drop_spaces.cut(Cols.cluster(span_text(sp)), sp, rest, tail => spans_drop_spaces.go(p, tail))

def spans_drop_spaces(+xs: List<&2, SpanOp>) -> List<&2, SpanOp>:
  spans_drop_spaces.go(Nat.add(1n, spans_chars(xs)), xs)

def word_cut.split(cut: SpanCut) -> SpanCut:
  match cut:
    case SpanCut{head, tail}: SpanCut{head, spans_drop_spaces(tail)}

def word_cut.allowed(ok: Bool, original: SpanCut, xs: List<&2, SpanOp>, n: Nat) -> SpanCut:
  match ok:
    case False{}: original
    case True{}: word_cut.split(spans_split(xs, n))

def word_cut.boundary(boundary: Maybe<&2, Nat>, original: SpanCut, xs: List<&2, SpanOp>, +shown: String, protected: U32) -> SpanCut:
  match boundary:
    case None{}: original
    case Some{+n}: word_cut.allowed(U32.is_gt(Cols.text_width(String.take(shown, n)), protected), original, xs, n)

def word_cut.scan(+head: List<&2, SpanOp>, tail: List<&2, SpanOp>, xs: List<&2, SpanOp>, protected: U32) -> SpanCut:
  +shown = spans_text(head)
  word_cut.boundary(word_break.go(Nat.add(1n, String.length(shown)), shown, 0n, None{}, False{}), SpanCut{head, tail}, xs, shown, protected)

def word_cut.exact(exact: Bool, head: List<&2, SpanOp>, tail: List<&2, SpanOp>, xs: List<&2, SpanOp>, protected: U32) -> SpanCut:
  match exact:
    case True{}: SpanCut{head, spans_drop_spaces(tail)}
    case False{}: word_cut.scan(head, tail, xs, protected)

def word_cut.tail_space(space: Bool, +head: List<&2, SpanOp>, tail: List<&2, SpanOp>, xs: List<&2, SpanOp>, protected: U32) -> SpanCut:
  word_cut.exact(space && Bool.not(String.ends_with(spans_text(head), " ")), head, tail, xs, protected)

def word_cut.first(piece: Cols.Cut, head: List<&2, SpanOp>, tail: List<&2, SpanOp>, xs: List<&2, SpanOp>, protected: U32) -> SpanCut:
  match piece:
    case Cols.Cut{text, _, _}: word_cut.tail_space(String.eq(text, " "), head, tail, xs, protected)

def word_cut(cut: SpanCut, +xs: List<&2, SpanOp>, protected: U32) -> SpanCut:
  match cut:
    case SpanCut{head, Nil{}}: SpanCut{head, Nil{}}
    case SpanCut{head, Con{+sp, +rest}}:
      word_cut.first(Cols.cluster(span_text(sp)), head, sp <> rest, xs, protected)

def spans_length(xs: List<&2, SpanOp>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{sp, t}: Nat.add(Nat.add(1n, String.length(span_text(sp))), spans_length(t))

# A one-column pane cannot paint a double-width glyph. Show a replacement
# rather than discard it or leave an empty, non-progressing wrapping loop.
def force_span_piece(piece: Cols.Cut, +sp: SpanOp, +rest: List<&2, SpanOp>) -> SpanCut:
  match piece:
    case Cols.Cut{_, +t, _}:
      SpanCut{span_text_as(sp, "�") <> Nil{}, Bool.pick(List<&2, SpanOp>, String.is_empty(t), rest, span_text_as(sp, t) <> rest)}

def force_span(xs: List<&2, SpanOp>) -> SpanCut:
  match xs:
    case Nil{}: SpanCut{Nil{}, Nil{}}
    case Con{+sp, rest}: force_span_piece(Cols.cluster(span_text(sp)), sp, rest)

def wrap_chunks_tail(tail: List<&2, SpanOp>, head: List<&2, SpanOp>, consumed: Nat, k: List<&2, SpanOp> -> List<&2, WrapChunk>) -> List<&2, WrapChunk>:
  match tail:
    case Nil{}: WrapChunk{head, consumed} <> Nil{}
    case Con{sp, rest}: WrapChunk{head, consumed} <> k(sp <> rest)

def wrap_spans_more(cut: SpanCut, +before: Nat, k: List<&2, SpanOp> -> List<&2, WrapChunk>) -> List<&2, WrapChunk>:
  match cut:
    case SpanCut{head, +tail}: wrap_chunks_tail(tail, head, Nat.sub(before, spans_chars(tail)), k)

def wrap_spans_cut(cut: SpanCut, +before: Nat, k: List<&2, SpanOp> -> List<&2, WrapChunk>) -> List<&2, WrapChunk>:
  match cut:
    case SpanCut{head, +tail}:
      match head:
        case Nil{}: wrap_spans_more(force_span(tail), before, k)
        case Con{sp, rest}: wrap_spans_more(SpanCut{sp <> rest, tail}, before, k)

def wrap_spans_go(fuel: Nat, +xs: List<&2, SpanOp>, +cap: U32, +cont_cap: U32) -> List<&2, WrapChunk>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      wrap_spans_cut(word_cut(take_spans(xs, cap), xs, U32.sub(cap, bounded_width(cont_cap, cap))), spans_chars(xs), rest => wrap_spans_go(p, rest, cont_cap, cont_cap))

def wrap_spans(+xs: List<&2, SpanOp>, +first_cap: U32, +cont_cap: U32) -> List<&2, WrapChunk>:
  wrap_spans_go(Nat.add(1n, spans_length(xs)), xs, wrap_cap(first_cap), wrap_cap(cont_cap))

def msg_prefix_w.parsed(pair: String & String) -> U32:
  match pair:
    case (+nick, +rest):
      Bool.pick(U32,
        String.starts_with(rest, " ") && Bool.not(String.is_empty(nick)),
        Cols.text_width("<" ++ nick ++ "> "),
        0)

def msg_prefix_w.lt(+t: String, lt: Bool) -> U32:
  match lt:
    case True{}: msg_prefix_w.parsed(take_until_gt(t))
    case False{}: 0

def msg_prefix_w(+s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{+h, +t}: msg_prefix_w.lt(t, Char.is_eq(h, '<'))

def line_prefix_w(k: Cl.LineKind, +text: String) -> U32:
  match k:
    case Cl.Msg{}: msg_prefix_w(text)
    case Cl.Self{}: msg_prefix_w(text)
    case Cl.Highlight{}: msg_prefix_w(text)
    case _: 0

def wrap_indent.max(+content: U32) -> U32:
  Bool.pick(U32, U32.is_zero(content), 0, U32.sub(content, 1))

def wrap_indent(+indent: U32, +content: U32) -> U32:
  +mx = wrap_indent.max(content)
  Bool.pick(U32, U32.is_gt(indent, mx), mx, indent)

def continuation_rows(chunks: List<&2, WrapChunk>, +off: U32, +w: U32, +fg: U32) -> List<&2, BodyRow>:
  match chunks:
    case Nil{}:
      Nil{}
    case Con{WrapChunk{h, source_chars}, t}:
      BodyRow{"", 0, off, w, fg, h, source_chars}
        <> continuation_rows(t, off, w, fg)

def wrapped_rows.chunks(
  chunks: List<&2, WrapChunk>,
  +ts: String,
  +stamp_w: U32,
  +first_off: U32,
  +first_w: U32,
  +cont_off: U32,
  +cont_w: U32,
  +fg: U32
) -> List<&2, BodyRow>:
  match chunks:
    case Nil{}:
      Nil{}
    case Con{WrapChunk{h, source_chars}, t}:
      BodyRow{ts, stamp_w, first_off, first_w, fg, h, source_chars}
        <> continuation_rows(t, cont_off, cont_w, fg)

type WrapMetrics is Data:
  WrapMetrics{shown: String, stamp_w: U32, first_off: U32, first_w: U32, cont_off: U32, cont_w: U32}

def wrap_metrics(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool) -> WrapMetrics:
  +shown = Bool.pick(String, show_ts, ts, "")
  +first_off = Bool.pick(U32, String.is_empty(shown), 0, line_shift(w))
  +first_w = U32.sub(w, first_off)
  +indent = wrap_indent(line_prefix_w(k, text), first_w)
  +cont_off = U32.add(first_off, indent)
  +cont_w = U32.sub(first_w, indent)
  WrapMetrics{shown, ts_w(w), first_off, first_w, cont_off, cont_w}

def wrapped_rows.metrics(metrics: WrapMetrics, +k: Cl.LineKind, text: String) -> List<&2, BodyRow>:
  match metrics:
    case WrapMetrics{shown, stamp_w, first_off, +first_w, cont_off, +cont_w}:
      wrapped_rows.chunks(wrap_spans(line_spans_for(k, text), first_w, cont_w), shown, stamp_w, first_off, first_w, cont_off, cont_w, style_of(k))

def wrapped_rows(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool) -> List<&2, BodyRow>:
  wrapped_rows.metrics(wrap_metrics(k, ts, text, w, show_ts), k, text)

type MediaPart is Data:
  MediaPart{spans: List<&2, SpanOp>, url: Maybe<&2, String>}

def contains_url(xs: List<&2, String>, +url: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, tail}: String.eq(h, url) || contains_url(tail, url)

def media_parts.link(+h: SpanOp, rev: List<&2, SpanOp>, +url: String, known: Bool, k: List<&2, SpanOp> -> List<&2, MediaPart>) -> List<&2, MediaPart>:
  match known:
    case True{}:
      MediaPart{List.reverse(&2, SpanOp, h <> rev), Some{url}} <> k(Nil{})
    case False{}:
      k(h <> rev)

def media_parts(xs: List<&2, SpanOp>, +rev: List<&2, SpanOp>, +urls: List<&2, String>) -> List<&2, MediaPart>:
  match xs:
    case Nil{}:
      match rev:
        case Nil{}: Nil{}
        case Con{+h, +tail}: [MediaPart{List.reverse(&2, SpanOp, h <> tail), None{}}]
    case Con{+h, +tail}:
      match h:
        case Lnk{+url, _}:
          media_parts.link(h, rev, url, contains_url(urls, url), next => media_parts(tail, next, urls))
        case _: media_parts(tail, h <> rev, urls)

# Image rows occupy six virtual rendered characters, independent of pane width.
# The exact same expanded rows are used for anchors, navigation and painting.
def media_rows.go(n: Nat, +token: U32, +w: U32, +row: U32) -> List<&2, BodyRow>:
  match n:
    case 0n: Nil{}
    case 1n+p: BodyMedia{token, U32.min(w, 40), 6, row} <> media_rows.go(p, token, w, U32.add(row, 1))

def media_rows(token: U32, w: U32) -> List<&2, BodyRow>:
  media_rows.go(6n, token, w, 0)

def media_part_image(url: Maybe<&2, String>, +media: M.State, +target: M.Target, +w: U32) -> List<&2, BodyRow>:
  match url:
    case None{}: Nil{}
    case Some{exact}: media_rows(M.token(media, target, exact), w)

def wrapped_media.parts(parts: List<&2, MediaPart>, +media: M.State, +target: M.Target, +ts: String, +stamp_w: U32, +first_off: U32, +first_w: U32, +cont_off: U32, +cont_w: U32, +fg: U32, +w: U32) -> List<&2, BodyRow>:
  match parts:
    case Nil{}: Nil{}
    case Con{MediaPart{spans, url}, tail}:
      List.append(&2, BodyRow, wrapped_rows.chunks(wrap_spans(spans, first_w, cont_w), ts, stamp_w, first_off, first_w, cont_off, cont_w, fg),
        List.append(&2, BodyRow, media_part_image(url, media, target, w),
          wrapped_media.parts(tail, media, target, "", 0, cont_off, cont_w, cont_off, cont_w, fg, w)))

def wrapped_media.metrics(metrics: WrapMetrics, urls: List<&2, String>, +k: Cl.LineKind, text: String, +w: U32, id: Nat, +media: M.State) -> List<&2, BodyRow>:
  match metrics:
    case WrapMetrics{shown, stamp_w, first_off, first_w, cont_off, cont_w}:
      wrapped_media.parts(media_parts(line_spans_for(k, text), Nil{}, urls), media, M.Inline{id}, shown, stamp_w, first_off, first_w, cont_off, cont_w, style_of(k), w)

def wrapped_media.known(urls: List<&2, String>, +k: Cl.LineKind, +ts: String, +text: String, +w: U32, +show_ts: Bool, +id: Nat, +media: M.State) -> List<&2, BodyRow>:
  match urls:
    case Nil{}: wrapped_rows(k, ts, text, w, show_ts)
    case Con{+h, +tail}:
      wrapped_media.metrics(wrap_metrics(k, ts, text, w, show_ts), h <> tail, k, text, w, id, media)

def wrapped_media(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, +show_ts: Bool, +id: Nat, +media: M.State) -> List<&2, BodyRow>:
  wrapped_media.known(M.known_urls(media, M.Inline{id}), k, ts, text, w, show_ts, id, media)

def wrap_line_media(+ln: Cl.Line, +w: U32, show_ts: Bool, +media: M.State) -> List<&2, BodyRow>:
  match ln:
    case Cl.Line{Cl.Reconnect{}, _, text, _, _}: [BodyRecon{text, w}]
    case Cl.Line{Cl.System{}, +ts, +text, _, 0n}:
      Bool.pick(List<&2, BodyRow>, contains_url(M.known_urls(media, M.Manual{}), text),
        media_rows(M.token(media, M.Manual{}, text), w), wrapped_media(Cl.System{}, ts, text, w, show_ts, 0n, media))
    case Cl.Line{+k, +ts, +text, _, +id}: wrapped_media(k, ts, text, w, show_ts, id, media)

def wrap_lines_media(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +media: M.State) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{h, tail}: List.append(&2, BodyRow, wrap_line_media(h, w, show_ts, media), wrap_lines_media(tail, w, show_ts, media))

# Card rows splice under the anchor chat line with the same wrap mechanics as
# Cards.rows_for (System styling, no timestamp, per-card row cap). Client and
# history stay raw; only paint, navigation bounds, and visible scheduling read
# these synthetic rows, all through this one cascade.
def card_rows_for_texts(xs: List<&2, String>, +w: U32) -> List<&2, BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}: List.append(&2, BodyRow, wrapped_rows(Cl.System{}, "", h, w, False{}), card_rows_for_texts(t, w))

def card_rows_for_entry(+texts: List<&2, String>, +w: U32) -> List<&2, BodyRow>:
  List.take(&2, BodyRow, card_rows_for_texts(texts, w), card_rows_cap())

def card_rows_for_hit(hit: Bool, +texts: List<&2, String>, +w: U32) -> List<&2, BodyRow>:
  match hit:
    case True{}: card_rows_for_entry(texts, w)
    case False{}: Nil{}

def card_rows_for.go(xs: List<&2, CardEntry>, +id: Nat, +w: U32) -> List<&2, BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{CardEntry{other, +texts}, t}:
      List.append(&2, BodyRow, card_rows_for_hit(Nat.is_eq(other, id), texts, w), card_rows_for.go(t, id, w))

def card_rows_for(+xs: List<&2, CardEntry>, +id: Nat, +w: U32) -> List<&2, BodyRow>:
  card_rows_for.go(xs, id, w)

def wrap_line_media_cards(+ln: Cl.Line, +w: U32, show_ts: Bool, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, BodyRow>:
  match ln:
    case Cl.Line{Cl.Reconnect{}, _, text, _, _}: [BodyRecon{text, w}]
    case Cl.Line{Cl.System{}, +ts, +text, _, 0n}:
      Bool.pick(List<&2, BodyRow>, contains_url(M.known_urls(media, M.Manual{}), text),
        media_rows(M.token(media, M.Manual{}, text), w), wrapped_media(Cl.System{}, ts, text, w, show_ts, 0n, media))
    case Cl.Line{+k, +ts, +text, _, +id}:
      List.append(&2, BodyRow, wrapped_media(k, ts, text, w, show_ts, id, media), card_rows_for(cards, id, w))

def wrap_lines_media_cards(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{h, tail}: List.append(&2, BodyRow, wrap_line_media_cards(h, w, show_ts, media, cards), wrap_lines_media_cards(tail, w, show_ts, media, cards))

def wrap_line.on(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool, recon: Bool) -> List<&2, BodyRow>:
  match recon:
    case True{}:
      BodyRecon{text, w} <> Nil{}
    case False{}:
      wrapped_rows(k, ts, text, w, show_ts)

def wrap_line(+ln: Cl.Line, +w: U32, show_ts: Bool) -> List<&2, BodyRow>:
  match ln:
    case Cl.Line{+k, +ts, +text, +author, +id}:
      wrap_line.on(k, ts, text, w, show_ts, Cl.is_reconnect(k))

def wrap_lines(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool) -> List<&2, BodyRow>:
  match lines:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      List.append(&2, BodyRow, wrap_line(h, w, show_ts), wrap_lines(t, w, show_ts))

def unwrapped_line.on(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool, recon: Bool) -> BodyRow:
  match recon:
    case True{}:
      BodyRecon{text, w}
    case False{}:
      +shown = Bool.pick(String, show_ts, ts, "")
      +off = Bool.pick(U32, String.is_empty(shown), 0, line_shift(w))
      +spans = line_spans_for(k, text)
      BodyRow{shown, ts_w(w), off, U32.sub(w, off), style_of(k), spans, spans_chars(spans)}

def unwrapped_line(+ln: Cl.Line, +w: U32, show_ts: Bool) -> BodyRow:
  match ln:
    case Cl.Line{+k, +ts, +text, +author, +id}:
      unwrapped_line.on(k, ts, text, w, show_ts, Cl.is_reconnect(k))

def unwrapped_lines(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool) -> List<&2, BodyRow>:
  match lines:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      unwrapped_line(h, w, show_ts) <> unwrapped_lines(t, w, show_ts)

def body_rows.on(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, synthetic: Bool) -> List<&2, BodyRow>:
  match synthetic:
    case True{}: unwrapped_lines(lines, w, show_ts)
    case False{}: wrap_lines(lines, w, show_ts)

def body_rows(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool) -> List<&2, BodyRow>:
  body_rows.on(lines, w, show_ts, String.eq(name, "*settings*"))

def body_rows_media.on(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, media: M.State, synthetic: Bool) -> List<&2, BodyRow>:
  match synthetic:
    case True{}: unwrapped_lines(lines, w, show_ts)
    case False{}: wrap_lines_media(lines, w, show_ts, media)

def body_rows_media(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, media: M.State) -> List<&2, BodyRow>:
  body_rows_media.on(lines, w, show_ts, media, String.eq(name, "*settings*"))

def body_rows_media_cards.on(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, media: M.State, +cards: List<&2, CardEntry>, synthetic: Bool) -> List<&2, BodyRow>:
  match synthetic:
    case True{}: unwrapped_lines(lines, w, show_ts)
    case False{}: wrap_lines_media_cards(lines, w, show_ts, media, cards)

def body_rows_media_cards(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, BodyRow>:
  body_rows_media_cards.on(lines, w, show_ts, media, cards, String.eq(name, "*settings*"))

# This synthetic row exists only in the view; raw Client/history lines stay intact.
# Manual diagnostics append after it, matching the ordinary paused-anchor rule.
def media_display_lines(+name: String, +topic: String, +lines: List<&2, Cl.Line>, media: M.State) -> List<&2, Cl.Line>:
  Bool.pick(List<&2, Cl.Line>, String.eq(name, "*preview*") && contains_url(M.known_urls(media, M.Manual{}), topic),
    Cl.Line{Cl.System{}, "", topic, "", 0n} <> lines, lines)

# Render filtering: mutes first, then the retroactive joins/nicks kind
# filter. Paint, scroll, navigation, and card/media admission all read
# through here, so hidden rows vanish everywhere at once.
def body_of.lines(lines: List<&2, Cl.Line>, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +chan: String, +server: String) -> List<&2, Cl.Line>:
  match mutes:
    case Nil{}: Cl.filter_kinds(lines, joins, nicks)
    case Con{_, _}: Cl.filter_kinds(Cl.filter_muted_lines(lines, mutes, chan, server), joins, nicks)

# Negotiated render filtering (I2-dynamic2 F4): mute checks fold under the
# Session CASEMAPPING supplied by the painter (Net/Session hold the iso).
def body_of.lines_cm(+cm: String, lines: List<&2, Cl.Line>, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +chan: String, +server: String) -> List<&2, Cl.Line>:
  match mutes:
    case Nil{}: Cl.filter_kinds(lines, joins, nicks)
    case Con{_, _}: Cl.filter_kinds(Cl.filter_muted_lines_cm(cm, lines, mutes, chan, server), joins, nicks)

def visible_body_rows(+rows: List<&2, BodyRow>, +height: Nat, +scroll: Nat) -> List<&2, BodyRow>:
  +start = visible_start(List.length(&2, BodyRow, rows), height, scroll)
  List.take(&2, BodyRow, List.drop(&2, BodyRow, rows, start), height)

# The same wrapped rows drive navigation and painting. An anchor stores a
# character position, not the current width-dependent row offset.
type AnchoredRow is Data:
  AnchoredRow{body: BodyRow, anchor: Cl.Scroll}

def row_chars(row: BodyRow) -> Nat:
  match row:
    case BodyRow{_, _, _, _, _, _, source_chars}: source_chars
    case BodyRecon{_, _}: 0n
    case BodyMedia{_, _, _, _}: 1n

def rows_chars(rows: List<&2, BodyRow>) -> Nat:
  match rows:
    case Nil{}: 0n
    case Con{h, t}: Nat.add(row_chars(h), rows_chars(t))

def anchored_rows(rows: List<&2, BodyRow>, +after: Nat, +chars: Nat) -> List<&2, AnchoredRow>:
  match rows:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +tail = Nat.sub(chars, row_chars(h))
      AnchoredRow{h, Cl.ScrollAt{after, tail}} <> anchored_rows(t, after, tail)

def anchored_line(+rows: List<&2, BodyRow>, +after: Nat) -> List<&2, AnchoredRow>:
  anchored_rows(rows, after, rows_chars(rows))

def anchored_lines_media(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State) -> List<&2, AnchoredRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +after = Nat.sub(left, 1n)
      +head = body_rows_media(body_of.lines(h <> Nil{}, mutes, joins, nicks, name, server), name, w, show_ts, media)
      List.append(&2, AnchoredRow, anchored_line(head, after), anchored_lines_media(t, name, w, show_ts, mutes, joins, nicks, server, after, media))

def anchored_lines_media_cm(+cm: String, lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State) -> List<&2, AnchoredRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +after = Nat.sub(left, 1n)
      +head = body_rows_media(body_of.lines_cm(cm, h <> Nil{}, mutes, joins, nicks, name, server), name, w, show_ts, media)
      List.append(&2, AnchoredRow, anchored_line(head, after), anchored_lines_media_cm(cm, t, name, w, show_ts, mutes, joins, nicks, server, after, media))

def anchored_lines(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat) -> List<&2, AnchoredRow>:
  anchored_lines_media(lines, name, w, show_ts, mutes, joins, nicks, server, left, M.empty())

def anchored_lines_media_cards(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +after = Nat.sub(left, 1n)
      +head = body_rows_media_cards(body_of.lines(h <> Nil{}, mutes, joins, nicks, name, server), name, w, show_ts, media, cards)
      List.append(&2, AnchoredRow, anchored_line(head, after), anchored_lines_media_cards(t, name, w, show_ts, mutes, joins, nicks, server, after, media, cards))

def anchored_lines_media_cards_cm(+cm: String, lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +after = Nat.sub(left, 1n)
      +head = body_rows_media_cards(body_of.lines_cm(cm, h <> Nil{}, mutes, joins, nicks, name, server), name, w, show_ts, media, cards)
      List.append(&2, AnchoredRow, anchored_line(head, after), anchored_lines_media_cards_cm(cm, t, name, w, show_ts, mutes, joins, nicks, server, after, media, cards))

def anchor_reached(row: Cl.Scroll, want: Cl.Scroll) -> Bool:
  match row:
    case Cl.ScrollAt{+ra, +rt}:
      match want:
        case Cl.ScrollAt{+wa, +wt}:
          Nat.is_lt(ra, wa) || (Nat.is_eq(ra, wa) && Nat.is_le(rt, wt))

def anchor_end.on(found: Bool, +i: Nat, k: Nat -> Nat) -> Nat:
  match found:
    case True{}: i
    case False{}: k(i)

def anchor_end(rows: List<&2, AnchoredRow>, +want: Cl.Scroll, +i: Nat) -> Nat:
  match rows:
    case Nil{}: i
    case Con{AnchoredRow{_, anchor}, t}:
      anchor_end.on(anchor_reached(anchor, want), 1n+i, n => anchor_end(t, want, n))

def viewport_end(+rows: List<&2, AnchoredRow>, +height: Nat, want: Cl.Scroll) -> Nat:
  match want:
    case Cl.ScrollAt{+after, +tail}:
      +count = List.length(&2, AnchoredRow, rows)
      +end = Bool.pick(Nat, Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), count, anchor_end(rows, Cl.ScrollAt{after, tail}, 0n))
      Nat.sub(count, clamp_scroll(Nat.sub(count, end), count, height))

def anchored_bodies(rows: List<&2, AnchoredRow>) -> List<&2, BodyRow>:
  match rows:
    case Nil{}: Nil{}
    case Con{AnchoredRow{body, _}, t}: body <> anchored_bodies(t)

def visible_anchored(+rows: List<&2, AnchoredRow>, +height: Nat, want: Cl.Scroll) -> List<&2, BodyRow>:
  +end = viewport_end(rows, height, want)
  anchored_bodies(List.take(&2, AnchoredRow, List.drop(&2, AnchoredRow, rows, Nat.sub(end, height)), height))

# At the live bottom, stop after enough expanded rows, not logical messages:
# muted/empty media lines can add no rows, while wrapped lines and images add many.
def recent_lines.more(state: Nat & List<&2, BodyRow>, +line: Cl.Line, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, k: (Nat & List<&2, BodyRow>) -> List<&2, BodyRow>) -> List<&2, BodyRow>:
  match state:
    case (0n, acc): acc
    case (1n+p, +acc):
      +left : Nat = 1n+p
      +rows = body_rows_media(body_of.lines([line], mutes, joins, nicks, name, server), name, w, show_ts, media)
      +count = List.length(&2, BodyRow, rows)
      +keep = Nat.min(left, count)
      k((Nat.sub(left, keep), List.append(&2, BodyRow, List.drop(&2, BodyRow, rows, Nat.sub(count, keep)), acc)))

def recent_lines.more_cm(+cm: String, state: Nat & List<&2, BodyRow>, +line: Cl.Line, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, k: (Nat & List<&2, BodyRow>) -> List<&2, BodyRow>) -> List<&2, BodyRow>:
  match state:
    case (0n, acc): acc
    case (1n+p, +acc):
      +left : Nat = 1n+p
      +rows = body_rows_media(body_of.lines_cm(cm, [line], mutes, joins, nicks, name, server), name, w, show_ts, media)
      +count = List.length(&2, BodyRow, rows)
      +keep = Nat.min(left, count)
      k((Nat.sub(left, keep), List.append(&2, BodyRow, List.drop(&2, BodyRow, rows, Nat.sub(count, keep)), acc)))

def recent_lines.go(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, state: Nat & List<&2, BodyRow>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Pair.snd(Nat, List<&2, BodyRow>, state)
    case Con{+h, t}:
      recent_lines.more(state, h, name, w, show_ts, mutes, joins, nicks, server, media,
        next => recent_lines.go(t, name, w, show_ts, mutes, joins, nicks, server, media, next))

def recent_lines.go_cm(+cm: String, lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, state: Nat & List<&2, BodyRow>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Pair.snd(Nat, List<&2, BodyRow>, state)
    case Con{+h, t}:
      recent_lines.more_cm(cm, state, h, name, w, show_ts, mutes, joins, nicks, server, media,
        next => recent_lines.go_cm(cm, t, name, w, show_ts, mutes, joins, nicks, server, media, next))

def body_of.buf_media.bottom(bottom: Bool, +lines: List<&2, Cl.Line>, +name: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, scroll: Cl.Scroll) -> List<&2, BodyRow>:
  match bottom:
    case True{}: recent_lines.go(List.reverse(&2, Cl.Line, lines), name, w, show_ts, mutes, joins, nicks, server, media, (height, Nil{}))
    case False{}: visible_anchored(anchored_lines_media(lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media), height, scroll)

def body_of.buf_media.bottom_cm(+cm: String, bottom: Bool, +lines: List<&2, Cl.Line>, +name: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, scroll: Cl.Scroll) -> List<&2, BodyRow>:
  match bottom:
    case True{}: recent_lines.go_cm(cm, List.reverse(&2, Cl.Line, lines), name, w, show_ts, mutes, joins, nicks, server, media, (height, Nil{}))
    case False{}: visible_anchored(anchored_lines_media_cm(cm, lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media), height, scroll)

def body_of.buf_media(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State) -> List<&2, BodyRow>:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, Cl.ScrollAt{+after, +tail}}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      body_of.buf_media.bottom(Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), lines, name, height, w, show_ts, mutes, joins, nicks, server, media, Cl.ScrollAt{after, tail})

def body_of.buf_media_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State) -> List<&2, BodyRow>:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, Cl.ScrollAt{+after, +tail}}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      body_of.buf_media.bottom_cm(cm, Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), lines, name, height, w, show_ts, mutes, joins, nicks, server, media, Cl.ScrollAt{after, tail})

def body_of.buf(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String) -> List<&2, BodyRow>:
  body_of.buf_media(b, height, w, show_ts, mutes, joins, nicks, server, M.empty())

def recent_lines_cards.more(state: Nat & List<&2, BodyRow>, +line: Cl.Line, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, k: (Nat & List<&2, BodyRow>) -> List<&2, BodyRow>) -> List<&2, BodyRow>:
  match state:
    case (0n, acc): acc
    case (1n+p, +acc):
      +left : Nat = 1n+p
      +rows = body_rows_media_cards(body_of.lines([line], mutes, joins, nicks, name, server), name, w, show_ts, media, cards)
      +count = List.length(&2, BodyRow, rows)
      +keep = Nat.min(left, count)
      k((Nat.sub(left, keep), List.append(&2, BodyRow, List.drop(&2, BodyRow, rows, Nat.sub(count, keep)), acc)))

def recent_lines_cards.go(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, state: Nat & List<&2, BodyRow>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Pair.snd(Nat, List<&2, BodyRow>, state)
    case Con{+h, t}:
      recent_lines_cards.more(state, h, name, w, show_ts, mutes, joins, nicks, server, media, cards,
        next => recent_lines_cards.go(t, name, w, show_ts, mutes, joins, nicks, server, media, cards, next))

def recent_lines_cards.more_cm(+cm: String, state: Nat & List<&2, BodyRow>, +line: Cl.Line, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, k: (Nat & List<&2, BodyRow>) -> List<&2, BodyRow>) -> List<&2, BodyRow>:
  match state:
    case (0n, acc): acc
    case (1n+p, +acc):
      +left : Nat = 1n+p
      +rows = body_rows_media_cards(body_of.lines_cm(cm, [line], mutes, joins, nicks, name, server), name, w, show_ts, media, cards)
      +count = List.length(&2, BodyRow, rows)
      +keep = Nat.min(left, count)
      k((Nat.sub(left, keep), List.append(&2, BodyRow, List.drop(&2, BodyRow, rows, Nat.sub(count, keep)), acc)))

def recent_lines_cards.go_cm(+cm: String, lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, state: Nat & List<&2, BodyRow>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Pair.snd(Nat, List<&2, BodyRow>, state)
    case Con{+h, t}:
      recent_lines_cards.more_cm(cm, state, h, name, w, show_ts, mutes, joins, nicks, server, media, cards,
        next => recent_lines_cards.go_cm(cm, t, name, w, show_ts, mutes, joins, nicks, server, media, cards, next))

def body_of.buf_media_cards.bottom(bottom: Bool, +lines: List<&2, Cl.Line>, +name: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, scroll: Cl.Scroll) -> List<&2, BodyRow>:
  match bottom:
    case True{}: recent_lines_cards.go(List.reverse(&2, Cl.Line, lines), name, w, show_ts, mutes, joins, nicks, server, media, cards, (height, Nil{}))
    case False{}: visible_anchored(anchored_lines_media_cards(lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media, cards), height, scroll)

def body_of.buf_media_cards(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, BodyRow>:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, Cl.ScrollAt{+after, +tail}}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      body_of.buf_media_cards.bottom(Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), lines, name, height, w, show_ts, mutes, joins, nicks, server, media, cards, Cl.ScrollAt{after, tail})

def body_of.buf_media_cards.bottom_cm(+cm: String, bottom: Bool, +lines: List<&2, Cl.Line>, +name: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, scroll: Cl.Scroll) -> List<&2, BodyRow>:
  match bottom:
    case True{}: recent_lines_cards.go_cm(cm, List.reverse(&2, Cl.Line, lines), name, w, show_ts, mutes, joins, nicks, server, media, cards, (height, Nil{}))
    case False{}: visible_anchored(anchored_lines_media_cards_cm(cm, lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media, cards), height, scroll)

def body_of.buf_media_cards_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, BodyRow>:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, Cl.ScrollAt{+after, +tail}}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      body_of.buf_media_cards.bottom_cm(cm, Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), lines, name, height, w, show_ts, mutes, joins, nicks, server, media, cards, Cl.ScrollAt{after, tail})

def row_anchor_at(rows: List<&2, AnchoredRow>, i: Nat) -> Cl.Scroll:
  match rows:
    case Nil{}: Cl.ScrollAt{0n, 0n}
    case Con{AnchoredRow{_, +anchor}, t}:
      match i:
        case 0n: anchor
        case 1n+p: row_anchor_at(t, p)

def moved_anchor(+rows: List<&2, AnchoredRow>, +height: Nat, +want: Cl.Scroll, +up: Nat, +dn: Nat) -> Cl.Scroll:
  +count = List.length(&2, AnchoredRow, rows)
  +current = viewport_end(rows, height, want)
  +target = Cl.clamp_nat(Nat.sub(Nat.add(current, dn), up), count)
  +end = Nat.sub(count, clamp_scroll(Nat.sub(count, target), count, height))
  Bool.pick(Cl.Scroll, Nat.is_eq(end, count), Cl.ScrollAt{0n, 0n}, row_anchor_at(rows, Nat.sub(end, 1n)))

def scroll_buf_media(+b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Buffer:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, +scroll}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      +rows = anchored_lines_media(lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media)
      Cl.set_buf_anchor(b, moved_anchor(rows, height, scroll, up, dn))

def scroll_buf_media_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Buffer:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, +scroll}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      +rows = anchored_lines_media_cm(cm, lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media)
      Cl.set_buf_anchor(b, moved_anchor(rows, height, scroll, up, dn))

def scroll_buf(+b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat) -> Cl.Buffer:
  scroll_buf_media(b, height, w, show_ts, mutes, joins, nicks, server, up, dn, M.empty())

def scroll_buf_media_cards(+b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> Cl.Buffer:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, +scroll}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      +rows = anchored_lines_media_cards(lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media, cards)
      Cl.set_buf_anchor(b, moved_anchor(rows, height, scroll, up, dn))

def scroll_buf_media_cards_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> Cl.Buffer:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, +scroll}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      +rows = anchored_lines_media_cards_cm(cm, lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media, cards)
      Cl.set_buf_anchor(b, moved_anchor(rows, height, scroll, up, dn))

def body_title_of(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, +topic, _, _, _}:
      topic

def nicks_title_of(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, _, _, _, _}:
      name

def nicks_list_of(+b: Cl.Buffer) -> List<&2, String>:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _}:
      nicks

def status_of.buf(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _}:
      "/connect /join /part /close /msg /nick /me /preview /quit  ·  Up/Down hist  ·  Shift+Left/Right  ·  Esc  ·  "
        ++ Nat.show(List.length(&2, String, nicks))
        ++ " nicks"

def typing_names(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+h, t}:
      match t:
        case Nil{}:
          h
        case Con{+h2, t2}:
          h ++ ", " ++ typing_names(h2 <> t2)

def typing_notice(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+h, t}:
      match t:
        case Nil{}:
          h ++ " is typing..."
        case Con{+h2, t2}:
          h ++ ", " ++ typing_names(h2 <> t2) ++ " are typing..."

def status_or_typing(+status: String, typers: List<&2, String>) -> String:
  match typers:
    case Nil{}:
      status
    case Con{+h, t}:
      typing_notice(h <> t)

def view_input(+draft: String) -> String:
  draft

def tab_lab(+name: String, first: Bool, unread: U32) -> String:
  match first:
    case True{}:
      "*" ++ name ++ "*"
    case False{}:
      match unread:
        case 2: name ++ "!"
        case 1: name ++ "*"
        case _: name

def tab_names.go(bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>, first: Bool) -> List<&2, String>:
  match bufs:
    case Nil{}:
      Nil{}
    case Con{Cl.Buffer{+name, _, _, _, _, _}, t}:
      tab_lab(name, first, Cl.buf_unread_status(unreads, name)) <> tab_names.go(t, unreads, False{})

# Server buffer keeps the name "server" internally; the tab strip uses
# *server* so a nick or channel named server cannot collide.
def tab_names(bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, String>:
  tab_names.go(bufs, unreads, True{})

def tab_alerts.go(bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>, first: Bool) -> List<&2, U32>:
  match bufs:
    case Nil{}:
      Nil{}
    case Con{Cl.Buffer{+name, _, _, _, _, _}, t}:
      match first:
        case True{}: 0 <> tab_alerts.go(t, unreads, False{})
        case False{}: Cl.buf_unread_status(unreads, name) <> tab_alerts.go(t, unreads, False{})

def tab_alerts(bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, U32>:
  tab_alerts.go(bufs, unreads, True{})

# Negotiated tab lookup (I2-dynamic3 R4): labels and alerts resolve unreads
# under the Session CASEMAPPING through the shared buf_unread_status_cm
# owner, so a marked buffer never lights its fold-sibling tab. Fixed
# tab_names/tab_alerts keep law behavior; cm paint entries call these.
def tab_names.go_cm(+cm: String, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>, first: Bool) -> List<&2, String>:
  match bufs:
    case Nil{}:
      Nil{}
    case Con{Cl.Buffer{+name, _, _, _, _, _}, t}:
      tab_lab(name, first, Cl.buf_unread_status_cm(cm, unreads, name)) <> tab_names.go_cm(cm, t, unreads, False{})

def tab_names_cm(+cm: String, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, String>:
  tab_names.go_cm(cm, bufs, unreads, True{})

def tab_alerts.go_cm(+cm: String, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>, first: Bool) -> List<&2, U32>:
  match bufs:
    case Nil{}:
      Nil{}
    case Con{Cl.Buffer{+name, _, _, _, _, _}, t}:
      match first:
        case True{}: 0 <> tab_alerts.go_cm(cm, t, unreads, False{})
        case False{}: Cl.buf_unread_status_cm(cm, unreads, name) <> tab_alerts.go_cm(cm, t, unreads, False{})

def tab_alerts_cm(+cm: String, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, U32>:
  tab_alerts.go_cm(cm, bufs, unreads, True{})

def bool_bit(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

def vis_h(+rows: U32) -> Nat:
  Sp.page_height(rows, Sp.Off{})

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
# reaches the status (or composer) row. Prefer y=1 (row 0 is tabs bar).
def body_top.small(+end: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      1
    case False{}:
      0

def body_top.on(+end: U32, room: Bool) -> U32:
  match room:
    case True{}:
      1
    case False{}:
      body_top.small(end, U32.is_ge(end, 1))

def body_top(+end: U32) -> U32:
  body_top.on(end, U32.is_gt(end, 1))

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

def user_w(+s: String) -> U32:
  Cols.text_width(s)

def tabs_w.on(+cols: U32, +uw: U32, room: Bool) -> U32:
  match room:
    case True{}:
      U32.sub(cols, U32.add(uw, 2))
    case False{}:
      cols

def tabs_w(+cols: U32, +uw: U32) -> U32:
  tabs_w.on(cols, uw, U32.is_ge(cols, U32.add(uw, 12)))

def user_rect.on(+cols: U32, +uw: U32, room: Bool) -> Rect:
  match room:
    case True{}:
      Rect{U32.sub(U32.sub(cols, uw), 1), 0, uw, 1}
    case False{}:
      Rect{0, 0, 0, 0}

def user_rect(+cols: U32, +uw: U32) -> Rect:
  user_rect.on(cols, uw, U32.is_ge(cols, U32.add(uw, 12)))

def lay(+rows: U32, +cols: U32, +uw: U32) -> Lay:
  +mid = mid_w(cols)
  +sy = status_y(rows)
  +top = body_top(sy)
  +bh = body_box_h(sy, top)
  Lay{
    Rect{0, 0, tabs_w(cols, uw), 1},
    user_rect(cols, uw),
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
  last_body_row.of(lay(rows, 80, 0))


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

def body_box.on(+x: U32, +y: U32, +w: U32, +h: U32, +title: String, empty: Bool) -> List<&2, DrawOp>:
  match empty:
    case True{}:
      OpBox{x, y, w, h} <> Nil{}
    case False{}:
      OpBox{x, y, w, h} <> OpText{inner_x(x), y, inner_w(w), FG_DIM(), 0, title} <> Nil{}

def body_box(r: Rect, +title: String) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, w, h}:
      body_box.on(x, y, w, h, title, String.is_empty(title))

def op_text(r: Rect, +fg: U32, +text: String) -> DrawOp:
  match r:
    case Rect{x, y, w, _}:
      OpText{x, y, w, fg, 0, text}

def op_tabs(r: Rect, +sel: U32, +names: List<&2, String>, +alerts: List<&2, U32>, +bell: U32, +bell_seq: U32) -> DrawOp:
  match r:
    case Rect{x, y, w, _}:
      OpTabs{x, y, w, sel, names, alerts, bell, bell_seq}

def body_row_ops.normal(+x: U32, +y: U32, +ts: String, +stamp_w: U32, +off: U32, +w: U32, +fg: U32, +spans: List<&2, SpanOp>, empty: Bool) -> List<&2, DrawOp>:
  match empty:
    case True{}:
      OpLine{U32.add(x, off), y, w, fg, spans} <> Nil{}
    case False{}:
      OpText{x, y, stamp_w, FG_DIM(), 0, ts}
        <> (OpLine{U32.add(x, off), y, w, fg, spans} <> Nil{})

def body_row_ops(+x: U32, +y: U32, row: BodyRow) -> List<&2, DrawOp>:
  match row:
    case BodyRow{+ts, stamp_w, off, w, fg, +spans, _}:
      body_row_ops.normal(x, y, ts, stamp_w, off, w, fg, spans, String.is_empty(ts))
    case BodyRecon{+text, +w}:
      OpText{x, y, w, FG_DIM(), 0, recon_divider(text, w)} <> Nil{}
    case BodyMedia{_, _, _, _}: Nil{}

def body_ops.go(fuel: Nat, xs: List<&2, BodyRow>, +x: U32, +y: U32) -> List<&2, DrawOp>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{BodyMedia{token, w, +h, +row}, +tail}:
          +visible = U32.min(U32.sub(h, row), U32.from_nat(Nat.add(1n, List.length(&2, BodyRow, tail))))
          OpMedia{x, y, w, h, row, visible, token} <> body_ops.go(p, List.drop(&2, BodyRow, tail, Nat.sub(U32.to_nat(visible), 1n)), x, U32.add(y, visible))
        case Con{head, tail}:
          List.append(&2, DrawOp, body_row_ops(x, y, head), body_ops.go(p, tail, x, U32.add(y, 1)))

def body_ops(r: Rect, +xs: List<&2, BodyRow>) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, w, h}:
      +n = U32.from_nat(List.length(&2, BodyRow, xs))
      body_ops.go(List.length(&2, BodyRow, xs), xs, inner_x(x), body_y0(y, h, n))

def image_ops.on(+x: U32, +y: U32, +w: U32, +h: U32, +path: String, empty: Bool) -> List<&2, DrawOp>:
  match empty:
    case True{}: Nil{}
    case False{}: OpImage{inner_x(x), U32.add(y, 1), inner_w(w), inner_w(h), path} <> Nil{}

def image_ops(r: Rect, +path: String) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, w, h}: image_ops.on(x, y, w, h, path, String.is_empty(path))

def nick_ops.go(xs: List<&2, String>, ok: Bool, +x: U32, +y: U32, +w: U32, +fg: U32, +max_y: U32) -> List<&2, DrawOp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      match ok:
        case False{}:
          Nil{}
        case True{}:
          OpText{x, y, w, nick_color(Cl.nick_strip(h)), 0, h}
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

def view_ops.rest(+br: Rect, +bod: List<&2, BodyRow>, +preview: String, +nr: Rect, +title: String, +nicks: List<&2, String>, +sr: Rect, +st: String) -> List<&2, DrawOp>:
  List.append(&2, DrawOp, image_ops(br, preview),
    List.append(&2, DrawOp, body_ops(br, bod),
    List.append(&2, DrawOp, nick_ops(nr, title, nicks),
      op_text(sr, FG_DIM(), st) <> Nil{})))

def view_ops(
  lay0: Lay,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +names: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +bod: List<&2, BodyRow>,
  +preview: String,
  +btitle: String,
  +ntitle: String,
  +nicks: List<&2, String>,
  +st: String
) -> List<&2, DrawOp>:
  match lay0:
    case Lay{tr, ur, +br, nr, sr}:
      List.append(&2, DrawOp,
        op_tabs(tr, U32.from_nat(active), names, alerts, bell, bell_seq)
          <> List.append(&2, DrawOp, user_header_ops(ur, nick, server, net), body_box(br, btitle)),
        view_ops.rest(br, bod, preview, nr, ntitle, nicks, sr, st))

def preview_path_of.on(+topic: String, preview: Bool) -> String:
  match preview:
    case True{}: topic
    case False{}: ""

def preview_path_of(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, +topic, _, _, _}:
      preview_path_of.on(topic, String.eq(name, "*preview*") && Bool.not(Links.is_url_prefix(topic)))

def rect_vis_h(r: Rect) -> Nat:
  match r:
    case Rect{_, _, _, +h}: Sp.inner_extent(h)

def rect_vis_w(r: Rect) -> U32:
  match r:
    case Rect{_, _, +w, _}: inner_w(w)

def split_rects.side(r: Rect) -> Rect & Rect:
  match r:
    case Rect{+x, +y, +w, +h}:
      +w1 = Sp.first_extent(w)
      (Rect{x, y, w1, h}, Rect{U32.add(x, w1), y, Sp.second_extent(w), h})

def split_rects.stack(r: Rect) -> Rect & Rect:
  match r:
    case Rect{+x, +y, +w, +h}:
      +h1 = Sp.first_extent(h)
      (Rect{x, y, w, h1}, Rect{x, U32.add(y, h1), w, Sp.second_extent(h)})

def split_rects(axis: Sp.Axis, r: Rect) -> Rect & Rect:
  match axis:
    case Sp.SideBySide{}: split_rects.side(r)
    case Sp.Stacked{}: split_rects.stack(r)

def lay_body_rect(l: Lay) -> Rect:
  match l:
    case Lay{_, _, +body, _, _}: body

def focused_rect.pair(pair: Rect & Rect, focus: U32) -> Rect:
  match pair:
    case (+first, +second): Bool.pick(Rect, U32.is_zero(focus), first, second)

def focused_rect.on(+body: Rect, split: Sp.State) -> Rect:
  match split:
    case Sp.Off{}: body
    case Sp.On{axis, _, _, focus}: focused_rect.pair(split_rects(axis, body), focus)

def focused_rect(+rows: U32, +cols: U32, split: Sp.State) -> Rect:
  focused_rect.on(lay_body_rect(lay(rows, cols, 0)), split)

def visible_media.urls(urls: List<&2, String>, +id: Nat) -> List<&2, M.Candidate>:
  match urls:
    case Nil{}: Nil{}
    case Con{url, tail}: M.Candidate{M.Inline{id}, url} <> visible_media.urls(tail, id)

def visible_media.line.allowed(allowed: Bool, id: Nat, text: String) -> List<&2, M.Candidate>:
  match allowed:
    case False{}: Nil{}
    case True{}: visible_media.urls(M.targets(text), id)

def visible_media.line(line: Maybe<&2, Cl.Line>) -> List<&2, M.Candidate>:
  match line:
    case None{}: Nil{}
    case Some{Cl.Line{kind, _, text, _, +id}}:
      visible_media.line.allowed(M.live_kind(kind) && Nat.is_gt(id, 0n), id, text)

def visible_media.line_at(lines: List<&2, Cl.Line>, index: Nat) -> Maybe<&2, Cl.Line>:
  match lines:
    case Nil{}: None{}
    case Con{line, tail}:
      match index:
        case 0n: Some{line}
        case 1n+p: visible_media.line_at(tail, p)

def visible_media.rows(rows: List<&2, AnchoredRow>, +lines: List<&2, Cl.Line>, +count: Nat) -> List<&2, M.Candidate>:
  match rows:
    case Nil{}: Nil{}
    case Con{AnchoredRow{_, Cl.ScrollAt{after, _}}, tail}:
      List.append(&2, M.Candidate,
        visible_media.line(visible_media.line_at(lines, Nat.sub(Nat.sub(count, after), 1n))),
        visible_media.rows(tail, lines, count))

def visible_media.crop(+rows: List<&2, AnchoredRow>, +lines: List<&2, Cl.Line>, +height: Nat, scroll: Cl.Scroll) -> List<&2, M.Candidate>:
  +end = viewport_end(rows, height, scroll)
  visible_media.rows(List.take(&2, AnchoredRow, List.drop(&2, AnchoredRow, rows, Nat.sub(end, height)), height),
    lines, List.length(&2, Cl.Line, lines))

def visible_media.buffer.allowed(allowed: Bool, b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State) -> List<&2, M.Candidate>:
  match allowed:
    case False{}: Nil{}
    case True{}:
      match b:
        case Cl.Buffer{+name, _, _, +lines, _, scroll}:
          visible_media.crop(anchored_lines_media(lines, name, w, show_ts, mutes, joins, nicks, server,
            List.length(&2, Cl.Line, lines), media), lines, height, scroll)

def visible_media.buffer.allowed_cm(+cm: String, allowed: Bool, b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State) -> List<&2, M.Candidate>:
  match allowed:
    case False{}: Nil{}
    case True{}:
      match b:
        case Cl.Buffer{+name, _, _, +lines, _, scroll}:
          visible_media.crop(anchored_lines_media_cm(cm, lines, name, w, show_ts, mutes, joins, nicks, server,
            List.length(&2, Cl.Line, lines), media), lines, height, scroll)

def visible_media.buffer(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State) -> List<&2, M.Candidate>:
  match b:
    case Cl.Buffer{name, _, _, _, _, _}:
      visible_media.buffer.allowed(Bool.not(Cl.target_is_synthetic(name)) && Nat.is_gt(height, 0n) && Bool.not(U32.is_zero(w)),
        b, height, w, show_ts, mutes, joins, nicks, server, media)

def visible_media.buffer_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State) -> List<&2, M.Candidate>:
  match b:
    case Cl.Buffer{name, _, _, _, _, _}:
      visible_media.buffer.allowed_cm(cm, Bool.not(Cl.target_is_synthetic(name)) && Nat.is_gt(height, 0n) && Bool.not(U32.is_zero(w)),
        b, height, w, show_ts, mutes, joins, nicks, server, media)

def visible_media.split(pair: Rect & Rect, +cl: Cl.Client, +first: String, +second: String, +media: M.State) -> List<&2, M.Candidate>:
  match pair:
    case (+r1, +r2):
      match cl:
        case Cl.Client{_, +server, +bufs, +active, _, +stg, _, _}:
          List.append(&2, M.Candidate,
            visible_media.buffer(active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))),
              rect_vis_h(r1), rect_vis_w(r1), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media),
            visible_media.buffer(active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active))),
              rect_vis_h(r2), rect_vis_w(r2), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media))

def visible_media.split_cm(+cm: String, pair: Rect & Rect, +cl: Cl.Client, +first: String, +second: String, +media: M.State) -> List<&2, M.Candidate>:
  match pair:
    case (+r1, +r2):
      match cl:
        case Cl.Client{_, +server, +bufs, +active, _, +stg, _, _}:
          List.append(&2, M.Candidate,
            visible_media.buffer_cm(cm, active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))),
              rect_vis_h(r1), rect_vis_w(r1), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media),
            visible_media.buffer_cm(cm, active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active))),
              rect_vis_h(r2), rect_vis_w(r2), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media))

def visible_media.single(cl: Cl.Client, +rows: U32, +cols: U32, media: M.State) -> List<&2, M.Candidate>:
  match cl:
    case Cl.Client{_, server, bufs, active, _, +stg, _, _}:
      visible_media.buffer(active_buf.on(Cl.nth_buf(bufs, active)), vis_h(rows),
        rect_vis_w(lay_body_rect(lay(rows, cols, 0))), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media)

def visible_media.single_cm(+cm: String, cl: Cl.Client, +rows: U32, +cols: U32, media: M.State) -> List<&2, M.Candidate>:
  match cl:
    case Cl.Client{_, server, bufs, active, _, +stg, _, _}:
      visible_media.buffer_cm(cm, active_buf.on(Cl.nth_buf(bufs, active)), vis_h(rows),
        rect_vis_w(lay_body_rect(lay(rows, cols, 0))), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media)

def visible_media.panes(+cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State) -> List<&2, M.Candidate>:
  match split:
    case Sp.Off{}: visible_media.single(cl, rows, cols, media)
    case Sp.On{axis, first, second, _}:
      visible_media.split(split_rects(axis, lay_body_rect(lay(rows, cols, 0))), cl, first, second, media)

def visible_media.panes_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State) -> List<&2, M.Candidate>:
  match split:
    case Sp.Off{}: visible_media.single_cm(cm, cl, rows, cols, media)
    case Sp.On{axis, first, second, _}:
      visible_media.split_cm(cm, split_rects(axis, lay_body_rect(lay(rows, cols, 0))), cl, first, second, media)

# Admission shares the painted panes, wrapped rows, mute filters and anchors.
# A partly visible image row retains its source event even if its URL is above
# the viewport. Stable nonzero IDs also admit rows imported from history.
def visible_media_candidates(+cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State) -> List<&2, M.Candidate>:
  M.newest_candidates(visible_media.panes(cl, rows, cols, split, media), media)

# Cards-aware admission: the same panes, rows, mutes, and anchors the cards
# paint path shows, so card rows that push a chat line out of the viewport
# also keep it out of the scheduled set.
def visible_media_cards.buffer.allowed(allowed: Bool, b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match allowed:
    case False{}: Nil{}
    case True{}:
      match b:
        case Cl.Buffer{+name, _, _, +lines, _, scroll}:
          visible_media.crop(anchored_lines_media_cards(lines, name, w, show_ts, mutes, joins, nicks, server,
            List.length(&2, Cl.Line, lines), media, cards), lines, height, scroll)

def visible_media_cards.buffer(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match b:
    case Cl.Buffer{name, _, _, _, _, _}:
      visible_media_cards.buffer.allowed(Bool.not(Cl.target_is_synthetic(name)) && Nat.is_gt(height, 0n) && Bool.not(U32.is_zero(w)),
        b, height, w, show_ts, mutes, joins, nicks, server, media, cards)

def visible_media_cards.split(pair: Rect & Rect, +cl: Cl.Client, +first: String, +second: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match pair:
    case (+r1, +r2):
      match cl:
        case Cl.Client{_, +server, +bufs, +active, _, +stg, _, _}:
          List.append(&2, M.Candidate,
            visible_media_cards.buffer(active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))),
              rect_vis_h(r1), rect_vis_w(r1), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards),
            visible_media_cards.buffer(active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active))),
              rect_vis_h(r2), rect_vis_w(r2), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards))

def visible_media_cards.single(cl: Cl.Client, +rows: U32, +cols: U32, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match cl:
    case Cl.Client{_, server, bufs, active, _, +stg, _, _}:
      visible_media_cards.buffer(active_buf.on(Cl.nth_buf(bufs, active)), vis_h(rows),
        rect_vis_w(lay_body_rect(lay(rows, cols, 0))), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards)

def visible_media_cards.panes(+cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match split:
    case Sp.Off{}: visible_media_cards.single(cl, rows, cols, media, cards)
    case Sp.On{axis, first, second, _}:
      visible_media_cards.split(split_rects(axis, lay_body_rect(lay(rows, cols, 0))), cl, first, second, media, cards)

def visible_media_candidates_cards(+cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  M.newest_candidates(visible_media_cards.panes(cl, rows, cols, split, media, cards), media)

def visible_media_cards.buffer.allowed_cm(+cm: String, allowed: Bool, b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match allowed:
    case False{}: Nil{}
    case True{}:
      match b:
        case Cl.Buffer{+name, _, _, +lines, _, scroll}:
          visible_media.crop(anchored_lines_media_cards_cm(cm, lines, name, w, show_ts, mutes, joins, nicks, server,
            List.length(&2, Cl.Line, lines), media, cards), lines, height, scroll)

def visible_media_cards.buffer_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match b:
    case Cl.Buffer{name, _, _, _, _, _}:
      visible_media_cards.buffer.allowed_cm(cm, Bool.not(Cl.target_is_synthetic(name)) && Nat.is_gt(height, 0n) && Bool.not(U32.is_zero(w)),
        b, height, w, show_ts, mutes, joins, nicks, server, media, cards)

def visible_media_cards.split_cm(+cm: String, pair: Rect & Rect, +cl: Cl.Client, +first: String, +second: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match pair:
    case (+r1, +r2):
      match cl:
        case Cl.Client{_, +server, +bufs, +active, _, +stg, _, _}:
          List.append(&2, M.Candidate,
            visible_media_cards.buffer_cm(cm, active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))),
              rect_vis_h(r1), rect_vis_w(r1), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards),
            visible_media_cards.buffer_cm(cm, active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active))),
              rect_vis_h(r2), rect_vis_w(r2), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards))

def visible_media_cards.single_cm(+cm: String, cl: Cl.Client, +rows: U32, +cols: U32, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match cl:
    case Cl.Client{_, server, bufs, active, _, +stg, _, _}:
      visible_media_cards.buffer_cm(cm, active_buf.on(Cl.nth_buf(bufs, active)), vis_h(rows),
        rect_vis_w(lay_body_rect(lay(rows, cols, 0))), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards)

def visible_media_cards.panes_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  match split:
    case Sp.Off{}: visible_media_cards.single_cm(cm, cl, rows, cols, media, cards)
    case Sp.On{axis, first, second, _}:
      visible_media_cards.split_cm(cm, split_rects(axis, lay_body_rect(lay(rows, cols, 0))), cl, first, second, media, cards)

def visible_media_candidates_cards_cm(+cm: String, +cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  M.newest_candidates(visible_media_cards.panes_cm(cm, cl, rows, cols, split, media, cards), media)
def visible_media_candidates_cm(+cm: String, +cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State) -> List<&2, M.Candidate>:
  M.newest_candidates(visible_media.panes_cm(cm, cl, rows, cols, split, media), media)

def scroll_active_media.on(move: Bool, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Client:
  match move:
    case False{}: cl
    case True{}:
      match cl:
        case Cl.Client{_, +server, _, +active, _, +stg, _, _}:
          +rect = focused_rect(rows, cols, split)
          Cl.buf_modify_client(cl, active, b => scroll_buf_media(b, rect_vis_h(rect), rect_vis_w(rect), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, up, dn, media))

def scroll_active_media_cm.on(+cm: String, move: Bool, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Client:
  match move:
    case False{}: cl
    case True{}:
      match cl:
        case Cl.Client{_, +server, _, +active, _, +stg, _, _}:
          +rect = focused_rect(rows, cols, split)
          Cl.buf_modify_client(cl, active, b => scroll_buf_media_cm(cm, b, rect_vis_h(rect), rect_vis_w(rect), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, up, dn, media))

def scroll_active.on(move: Bool, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat) -> Cl.Client:
  scroll_active_media.on(move, cl, rows, cols, split, up, dn, M.empty())

def scroll_active_media(+cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Client:
  scroll_active_media.on(Nat.is_gt(up, 0n) || Nat.is_gt(dn, 0n), cl, rows, cols, split, up, dn, media)

def scroll_active_media_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Client:
  scroll_active_media_cm.on(cm, Nat.is_gt(up, 0n) || Nat.is_gt(dn, 0n), cl, rows, cols, split, up, dn, media)

def scroll_active(+cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat) -> Cl.Client:
  scroll_active_media(cl, rows, cols, split, up, dn, M.empty())

def scroll_active_media_cards.on(move: Bool, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> Cl.Client:
  match move:
    case False{}: cl
    case True{}:
      match cl:
        case Cl.Client{_, +server, _, +active, _, +stg, _, _}:
          +rect = focused_rect(rows, cols, split)
          Cl.buf_modify_client(cl, active, b => scroll_buf_media_cards(b, rect_vis_h(rect), rect_vis_w(rect), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, up, dn, media, cards))

def scroll_active_media_cards(+cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> Cl.Client:
  scroll_active_media_cards.on(Nat.is_gt(up, 0n) || Nat.is_gt(dn, 0n), cl, rows, cols, split, up, dn, media, cards)

def scroll_active_media_cards_cm.on(+cm: String, move: Bool, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> Cl.Client:
  match move:
    case False{}: cl
    case True{}:
      match cl:
        case Cl.Client{_, +server, _, +active, _, +stg, _, _}:
          +rect = focused_rect(rows, cols, split)
          Cl.buf_modify_client(cl, active, b => scroll_buf_media_cards_cm(cm, b, rect_vis_h(rect), rect_vis_w(rect), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, up, dn, media, cards))

def scroll_active_media_cards_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> Cl.Client:
  scroll_active_media_cards_cm.on(cm, Nat.is_gt(up, 0n) || Nat.is_gt(dn, 0n), cl, rows, cols, split, up, dn, media, cards)

def split_axis_tag(axis: Sp.Axis) -> U32:
  match axis:
    case Sp.SideBySide{}: 0
    case Sp.Stacked{}: 1

def op_split(r: Rect, axis: Sp.Axis) -> DrawOp:
  match r:
    case Rect{x, y, w, h}: OpSplit{x, y, w, h, split_axis_tag(axis)}

def split_title.base(+name: String, +topic: String) -> String:
  match topic:
    case SNil{}: name
    case SCon{_, _}: name ++ " — " ++ topic

def split_title(+b: Cl.Buffer, +focused: U32, +pane: U32) -> String:
  match b:
    case Cl.Buffer{+name, _, +topic, _, _, _}:
      +base = split_title.base(name, topic)
      Bool.pick(String, U32.is_eq(focused, pane), base ++ " [active]", base)

def view_ops_split(
  lay0: Lay,
  +axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +names: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +r1: Rect,
  +title1: String,
  +body1: List<&2, BodyRow>,
  +preview1: String,
  +r2: Rect,
  +title2: String,
  +body2: List<&2, BodyRow>,
  +preview2: String,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String
) -> List<&2, DrawOp>:
  match lay0:
    case Lay{tabs, user, body, nicks_rect, status_rect}:
      List.append(&2, DrawOp,
        op_tabs(tabs, U32.from_nat(active), names, alerts, bell, bell_seq)
          <> List.append(&2, DrawOp, user_header_ops(user, nick, server, net),
               op_split(body, axis)
                 <> List.append(&2, DrawOp, body_box(r1, title1),
                      List.append(&2, DrawOp, image_ops(r1, preview1),
                        List.append(&2, DrawOp, body_ops(r1, body1),
                          List.append(&2, DrawOp, body_box(r2, title2),
                            List.append(&2, DrawOp, image_ops(r2, preview2), body_ops(r2, body2))))))),
        List.append(&2, DrawOp, nick_ops(nicks_rect, ntitle, nicks),
          op_text(status_rect, FG_DIM(), status) <> Nil{}))

def view_split_source.rects(
  pair: Rect & Rect,
  lay0: Lay,
  axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +tabs: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +b1: Cl.Buffer,
  +b2: Cl.Buffer,
  +focused: U32,
  +mutes: List<&2, String>,
  +show_joins: Bool,
  +show_nicks: Bool,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String,
  +typers: List<&2, String>,
  +show_ts: Bool,
  +media: M.State,
  +legacy: Bool
) -> List<&2, DrawOp>:
  match pair:
    case (+r1, +r2):
      body1 body2 = body_of.buf_media(b1, rect_vis_h(r1), rect_vis_w(r1), show_ts, mutes, show_joins, show_nicks, server, media) body_of.buf_media(b2, rect_vis_h(r2), rect_vis_w(r2), show_ts, mutes, show_joins, show_nicks, server, media)
      view_ops_split(lay0, axis, nick, server, net, active, tabs, alerts, bell, bell_seq, r1, split_title(b1, focused, 0), body1, Bool.pick(String, legacy, preview_path_of(b1), ""), r2, split_title(b2, focused, 1), body2, Bool.pick(String, legacy, preview_path_of(b2), ""), ntitle, nicks, status_or_typing(status, typers))

def view_split_source.rects_cm(
  +cm: String,
  pair: Rect & Rect,
  lay0: Lay,
  axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +tabs: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +b1: Cl.Buffer,
  +b2: Cl.Buffer,
  +focused: U32,
  +mutes: List<&2, String>,
  +show_joins: Bool,
  +show_nicks: Bool,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String,
  +typers: List<&2, String>,
  +show_ts: Bool,
  +media: M.State,
  +legacy: Bool
) -> List<&2, DrawOp>:
  match pair:
    case (+r1, +r2):
      body1 body2 = body_of.buf_media_cm(cm, b1, rect_vis_h(r1), rect_vis_w(r1), show_ts, mutes, show_joins, show_nicks, server, media) body_of.buf_media_cm(cm, b2, rect_vis_h(r2), rect_vis_w(r2), show_ts, mutes, show_joins, show_nicks, server, media)
      view_ops_split(lay0, axis, nick, server, net, active, tabs, alerts, bell, bell_seq, r1, split_title(b1, focused, 0), body1, Bool.pick(String, legacy, preview_path_of(b1), ""), r2, split_title(b2, focused, 1), body2, Bool.pick(String, legacy, preview_path_of(b2), ""), ntitle, nicks, status_or_typing(status, typers))

def view_split.rects(
  pair: Rect & Rect,
  lay0: Lay,
  axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +tabs: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +b1: Cl.Buffer,
  +b2: Cl.Buffer,
  +focused: U32,
  +mutes: List<&2, String>,
  +show_joins: Bool,
  +show_nicks: Bool,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String,
  +typers: List<&2, String>,
  +show_ts: Bool
) -> List<&2, DrawOp>:
  view_split_source.rects(pair, lay0, axis, nick, server, net, active, tabs, alerts, bell, bell_seq, b1, b2, focused, mutes, show_joins, show_nicks, ntitle, nicks, status, typers, show_ts, M.empty(), True{})

def view_split_source(
  +cl: Cl.Client,
  +rows: U32,
  +cols: U32,
  +draft: String,
  +net: String,
  +axis: Sp.Axis,
  +first: String,
  +second: String,
  +focused: U32,
  +typers: List<&2, String>,
  +media: M.State,
  +legacy: Bool
) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      b1 b2 = active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))) active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active)))
      +focused_buf = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +body_rect = lay_body_rect(lay0)
      +tabs = tab_names(bufs, Cl.settings_unreads(stg))
      +alerts = tab_alerts(bufs, Cl.settings_unreads(stg))
      +mutes = Cl.settings_mutes(stg)
      +joins = Cl.settings_joins(stg)
      +nicks = Cl.settings_nicks(stg)
      nt status = nicks_title_of(focused_buf) status_of.buf(focused_buf)
      +ns = nicks_list_of(focused_buf)
      ViewModel{view_split_source.rects(split_rects(axis, body_rect), lay0, axis, nick, server, net, active, tabs, alerts, bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), b1, b2, focused, mutes, joins, nicks, nt, ns, status, typers, Cl.settings_ts(stg), media, legacy), view_input(draft)}

# Production media-aware entry points never emit OpImage. Pending, failed and
# accepted local previews all use Media's worker/token path, like remote media.
def view_split_media(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +axis: Sp.Axis, +first: String, +second: String, +focused: U32, +typers: List<&2, String>, +media: M.State) -> ViewModel:
  view_split_source(cl, rows, cols, draft, net, axis, first, second, focused, typers, media, False{})

def view_split_source_cards.rects(
  pair: Rect & Rect,
  lay0: Lay,
  axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +tabs: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +b1: Cl.Buffer,
  +b2: Cl.Buffer,
  +focused: U32,
  +mutes: List<&2, String>,
  +show_joins: Bool,
  +show_nicks: Bool,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String,
  +typers: List<&2, String>,
  +show_ts: Bool,
  +media: M.State,
  +cards: List<&2, CardEntry>,
  +legacy: Bool
) -> List<&2, DrawOp>:
  match pair:
    case (+r1, +r2):
      body1 body2 = body_of.buf_media_cards(b1, rect_vis_h(r1), rect_vis_w(r1), show_ts, mutes, show_joins, show_nicks, server, media, cards) body_of.buf_media_cards(b2, rect_vis_h(r2), rect_vis_w(r2), show_ts, mutes, show_joins, show_nicks, server, media, cards)
      view_ops_split(lay0, axis, nick, server, net, active, tabs, alerts, bell, bell_seq, r1, split_title(b1, focused, 0), body1, Bool.pick(String, legacy, preview_path_of(b1), ""), r2, split_title(b2, focused, 1), body2, Bool.pick(String, legacy, preview_path_of(b2), ""), ntitle, nicks, status_or_typing(status, typers))

def view_split_source_cards(
  +cl: Cl.Client,
  +rows: U32,
  +cols: U32,
  +draft: String,
  +net: String,
  +axis: Sp.Axis,
  +first: String,
  +second: String,
  +focused: U32,
  +typers: List<&2, String>,
  +media: M.State,
  +cards: List<&2, CardEntry>,
  +legacy: Bool
) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      b1 b2 = active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))) active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active)))
      +focused_buf = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +body_rect = lay_body_rect(lay0)
      +tabs = tab_names(bufs, Cl.settings_unreads(stg))
      +alerts = tab_alerts(bufs, Cl.settings_unreads(stg))
      +mutes = Cl.settings_mutes(stg)
      +joins = Cl.settings_joins(stg)
      +nicks = Cl.settings_nicks(stg)
      nt status = nicks_title_of(focused_buf) status_of.buf(focused_buf)
      +ns = nicks_list_of(focused_buf)
      ViewModel{view_split_source_cards.rects(split_rects(axis, body_rect), lay0, axis, nick, server, net, active, tabs, alerts, bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), b1, b2, focused, mutes, joins, nicks, nt, ns, status, typers, Cl.settings_ts(stg), media, cards, legacy), view_input(draft)}

def view_split_media_cards(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +axis: Sp.Axis, +first: String, +second: String, +focused: U32, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>) -> ViewModel:
  view_split_source_cards(cl, rows, cols, draft, net, axis, first, second, focused, typers, media, cards, False{})

def view_split_source_cards_cm.rects(
  +cm: String,
  pair: Rect & Rect,
  lay0: Lay,
  axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +tabs: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +b1: Cl.Buffer,
  +b2: Cl.Buffer,
  +focused: U32,
  +mutes: List<&2, String>,
  +show_joins: Bool,
  +show_nicks: Bool,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String,
  +typers: List<&2, String>,
  +show_ts: Bool,
  +media: M.State,
  +cards: List<&2, CardEntry>,
  +legacy: Bool
) -> List<&2, DrawOp>:
  match pair:
    case (+r1, +r2):
      body1 body2 = body_of.buf_media_cards_cm(cm, b1, rect_vis_h(r1), rect_vis_w(r1), show_ts, mutes, show_joins, show_nicks, server, media, cards) body_of.buf_media_cards_cm(cm, b2, rect_vis_h(r2), rect_vis_w(r2), show_ts, mutes, show_joins, show_nicks, server, media, cards)
      view_ops_split(lay0, axis, nick, server, net, active, tabs, alerts, bell, bell_seq, r1, split_title(b1, focused, 0), body1, Bool.pick(String, legacy, preview_path_of(b1), ""), r2, split_title(b2, focused, 1), body2, Bool.pick(String, legacy, preview_path_of(b2), ""), ntitle, nicks, status_or_typing(status, typers))

def view_split_source_cards_cm(
  +cm: String,
  +cl: Cl.Client,
  +rows: U32,
  +cols: U32,
  +draft: String,
  +net: String,
  +axis: Sp.Axis,
  +first: String,
  +second: String,
  +focused: U32,
  +typers: List<&2, String>,
  +media: M.State,
  +cards: List<&2, CardEntry>,
  +legacy: Bool
) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      b1 b2 = active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))) active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active)))
      +focused_buf = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +body_rect = lay_body_rect(lay0)
      +tabs = tab_names_cm(cm, bufs, Cl.settings_unreads(stg))
      +alerts = tab_alerts_cm(cm, bufs, Cl.settings_unreads(stg))
      +mutes = Cl.settings_mutes(stg)
      +joins = Cl.settings_joins(stg)
      +nicks = Cl.settings_nicks(stg)
      nt status = nicks_title_of(focused_buf) status_of.buf(focused_buf)
      +ns = nicks_list_of(focused_buf)
      ViewModel{view_split_source_cards_cm.rects(cm, split_rects(axis, body_rect), lay0, axis, nick, server, net, active, tabs, alerts, bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), b1, b2, focused, mutes, joins, nicks, nt, ns, status, typers, Cl.settings_ts(stg), media, cards, legacy), view_input(draft)}

def view_split_media_cards_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +axis: Sp.Axis, +first: String, +second: String, +focused: U32, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>) -> ViewModel:
  view_split_source_cards_cm(cm, cl, rows, cols, draft, net, axis, first, second, focused, typers, media, cards, False{})

def view_split_source_cm(
  +cm: String,
  +cl: Cl.Client,
  +rows: U32,
  +cols: U32,
  +draft: String,
  +net: String,
  +axis: Sp.Axis,
  +first: String,
  +second: String,
  +focused: U32,
  +typers: List<&2, String>,
  +media: M.State,
  +legacy: Bool
) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      b1 b2 = active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))) active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active)))
      +focused_buf = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +body_rect = lay_body_rect(lay0)
      +tabs = tab_names_cm(cm, bufs, Cl.settings_unreads(stg))
      +alerts = tab_alerts_cm(cm, bufs, Cl.settings_unreads(stg))
      +mutes = Cl.settings_mutes(stg)
      +joins = Cl.settings_joins(stg)
      +nicks = Cl.settings_nicks(stg)
      nt status = nicks_title_of(focused_buf) status_of.buf(focused_buf)
      +ns = nicks_list_of(focused_buf)
      ViewModel{view_split_source.rects_cm(cm, split_rects(axis, body_rect), lay0, axis, nick, server, net, active, tabs, alerts, bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), b1, b2, focused, mutes, joins, nicks, nt, ns, status, typers, Cl.settings_ts(stg), media, legacy), view_input(draft)}

def view_split_media_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +axis: Sp.Axis, +first: String, +second: String, +focused: U32, +typers: List<&2, String>, +media: M.State) -> ViewModel:
  view_split_source_cm(cm, cl, rows, cols, draft, net, axis, first, second, focused, typers, media, False{})

def view_split(
  +cl: Cl.Client,
  +rows: U32,
  +cols: U32,
  +draft: String,
  +net: String,
  +axis: Sp.Axis,
  +first: String,
  +second: String,
  +focused: U32,
  +typers: List<&2, String>
) -> ViewModel:
  view_split_source(cl, rows, cols, draft, net, axis, first, second, focused, typers, M.empty(), True{})

def view_draft.single_source(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +legacy: Bool) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +br = lay_body_rect(lay0)
      bod = body_of.buf_media(b, vis_h(rows), rect_vis_w(br), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media)
      bt nt = body_title_of(b) nicks_title_of(b)
      +ns = nicks_list_of(b)
      ViewModel{view_ops(lay0, nick, server, net, active, tab_names(bufs, Cl.settings_unreads(stg)), tab_alerts(bufs, Cl.settings_unreads(stg)), bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), bod, Bool.pick(String, legacy, preview_path_of(b), ""), bt, nt, ns, status_or_typing(status_of.buf(b), typers)), view_input(draft)}

def view_draft.single_media(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State) -> ViewModel:
  view_draft.single_source(cl, rows, cols, draft, net, typers, media, False{})

def view_draft.single_source_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +legacy: Bool) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +br = lay_body_rect(lay0)
      bod = body_of.buf_media_cm(cm, b, vis_h(rows), rect_vis_w(br), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media)
      bt nt = body_title_of(b) nicks_title_of(b)
      +ns = nicks_list_of(b)
      ViewModel{view_ops(lay0, nick, server, net, active, tab_names_cm(cm, bufs, Cl.settings_unreads(stg)), tab_alerts_cm(cm, bufs, Cl.settings_unreads(stg)), bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), bod, Bool.pick(String, legacy, preview_path_of(b), ""), bt, nt, ns, status_or_typing(status_of.buf(b), typers)), view_input(draft)}

def view_draft.single_media_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State) -> ViewModel:
  view_draft.single_source_cm(cm, cl, rows, cols, draft, net, typers, media, False{})

# Legacy pure characterization/law adapters retain OpImage spelling. Live IO
# calls state_typing_media, never these empty-media compatibility wrappers.
def view_draft.single(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>) -> ViewModel:
  view_draft.single_source(cl, rows, cols, draft, net, typers, M.empty(), True{})

def view_draft.state_typing_media(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State) -> ViewModel:
  match split:
    case Sp.On{axis, +first, +second, focus}:
      view_split_media(cl, rows, cols, draft, net, axis, first, second, focus, typers, media)
    case Sp.Off{}:
      view_draft.single_media(cl, rows, cols, draft, net, typers, media)

# Live cards-aware paint: ready-card texts splice under their anchor chat
# line; navigation bounds and visible scheduling read the same wrapped rows.
def view_draft.single_source_cards(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>, +legacy: Bool) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +br = lay_body_rect(lay0)
      bod = body_of.buf_media_cards(b, vis_h(rows), rect_vis_w(br), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards)
      bt nt = body_title_of(b) nicks_title_of(b)
      +ns = nicks_list_of(b)
      ViewModel{view_ops(lay0, nick, server, net, active, tab_names(bufs, Cl.settings_unreads(stg)), tab_alerts(bufs, Cl.settings_unreads(stg)), bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), bod, Bool.pick(String, legacy, preview_path_of(b), ""), bt, nt, ns, status_or_typing(status_of.buf(b), typers)), view_input(draft)}

def view_draft.single_media_cards(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>) -> ViewModel:
  view_draft.single_source_cards(cl, rows, cols, draft, net, typers, media, cards, False{})

def view_draft.state_typing_media_cards(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> ViewModel:
  match split:
    case Sp.On{axis, +first, +second, focus}:
      view_split_media_cards(cl, rows, cols, draft, net, axis, first, second, focus, typers, media, cards)
    case Sp.Off{}:
      view_draft.single_media_cards(cl, rows, cols, draft, net, typers, media, cards)

def view_draft.single_source_cards_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>, +legacy: Bool) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +br = lay_body_rect(lay0)
      bod = body_of.buf_media_cards_cm(cm, b, vis_h(rows), rect_vis_w(br), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards)
      bt nt = body_title_of(b) nicks_title_of(b)
      +ns = nicks_list_of(b)
      ViewModel{view_ops(lay0, nick, server, net, active, tab_names_cm(cm, bufs, Cl.settings_unreads(stg)), tab_alerts_cm(cm, bufs, Cl.settings_unreads(stg)), bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), bod, Bool.pick(String, legacy, preview_path_of(b), ""), bt, nt, ns, status_or_typing(status_of.buf(b), typers)), view_input(draft)}

def view_draft.single_media_cards_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>) -> ViewModel:
  view_draft.single_source_cards_cm(cm, cl, rows, cols, draft, net, typers, media, cards, False{})

def view_draft.state_typing_media_cards_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> ViewModel:
  match split:
    case Sp.On{axis, +first, +second, focus}:
      view_split_media_cards_cm(cm, cl, rows, cols, draft, net, axis, first, second, focus, typers, media, cards)
    case Sp.Off{}:
      view_draft.single_media_cards_cm(cm, cl, rows, cols, draft, net, typers, media, cards)
def view_draft.state_typing_media_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State) -> ViewModel:
  match split:
    case Sp.On{axis, +first, +second, focus}:
      view_split_media_cm(cm, cl, rows, cols, draft, net, axis, first, second, focus, typers, media)
    case Sp.Off{}:
      view_draft.single_media_cm(cm, cl, rows, cols, draft, net, typers, media)

def view_draft.state_typing(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State) -> ViewModel:
  match split:
    case Sp.On{axis, +first, +second, focus}:
      view_split(cl, rows, cols, draft, net, axis, first, second, focus, typers)
    case Sp.Off{}:
      view_draft.single(cl, rows, cols, draft, net, typers)

def view_draft_typing(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>) -> ViewModel:
  view_draft.state_typing(cl, rows, cols, draft, net, typers, Sp.Off{})

def view_draft(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String) -> ViewModel:
  view_draft_typing(cl, rows, cols, draft, net, Nil{})

def view_draft_split(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, split: Sp.State) -> ViewModel:
  view_draft.state_typing(cl, rows, cols, draft, net, Nil{}, split)

# Themed production painters. Session owns a Theme.Id and paints through
# these entries; the unthemed painters above keep the historic dark values.
def FG_DIM_themed(+th: Theme.Id) -> U32:
  Theme.status_dim(th)

def FG_TEXT_themed(+th: Theme.Id) -> U32:
  Theme.kind_fg(th, Cl.Msg{})

def user_header_ops.split_themed(r: Rect, +base: String, +net: String, empty: Bool, +th: Theme.Id) -> List<&2, DrawOp>:
  match r:
    case Rect{+x, +y, +w, _}:
      match empty:
        case True{}:
          OpText{x, y, w, FG_DIM_themed(th), 0, base} <> Nil{}
        case False{}:
          +pfx = base ++ " · "
          +pw = bounded_width(Cols.text_width(pfx), w)
          +nw = bounded_width(Cols.text_width(net), U32.sub(w, pw))
          OpText{x, y, pw, FG_DIM_themed(th), 0, pfx}
            <> (OpText{U32.add(x, pw), y, nw, status_color_themed(th, net), 1, net} <> Nil{})

def user_header_ops.visible_themed(hidden: Bool, r: Rect, +base: String, +net: String, +th: Theme.Id) -> List<&2, DrawOp>:
  match hidden:
    case True{}: Nil{}
    case False{}: user_header_ops.split_themed(r, base, net, String.is_empty(net), th)

def user_header_ops_themed(r: Rect, +nick: String, +server: String, +net: String, +th: Theme.Id) -> List<&2, DrawOp>:
  match r:
    case Rect{+x, +y, +w, +h}:
      user_header_ops.visible_themed(U32.is_zero(w) || U32.is_zero(h), Rect{x, y, w, h}, nick ++ "@" ++ server, net, th)

def parse_nick_msg.body_themed(+rest: String, +nick: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match rest:
    case SNil{}:
      render_spans("<" ++ nick ++ ">")
    case SCon{_, body}:
      Spn{0, "<"}
        <> (Col{1, nick_color_themed(th, nick), nick}
        <> (Spn{0, "> "}
        <> render_spans(body)))

def parse_nick_msg.ok_themed(ok: Bool, +rest: String, +nick: String, original: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match ok:
    case True{}:
      parse_nick_msg.body_themed(rest, nick, th)
    case False{}:
      render_spans(original)

def parse_nick_msg.parsed_themed(pair: String & String, original: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match pair:
    case (+nick, +rest):
      parse_nick_msg.ok_themed(String.starts_with(rest, " ") && Bool.not(String.is_empty(nick)), rest, nick, original, th)

def parse_nick_msg.head_themed(is_lt: Bool, +t: String, +s: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match is_lt:
    case True{}:
      parse_nick_msg.parsed_themed(take_until_gt(t), s, th)
    case False{}:
      render_spans(s)

def parse_nick_msg.con_themed(+c: Char, +t: String, +s: String, +th: Theme.Id) -> List<&2, SpanOp>:
  parse_nick_msg.head_themed(Char.is_eq(c, '<'), t, s, th)

def parse_nick_msg_themed(s: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{+c, +t}:
      parse_nick_msg.con_themed(c, t, s, th)

def parse_nick_act.body_themed(+rest: String, +nick: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match rest:
    case SNil{}:
      render_spans("* " ++ nick)
    case SCon{_, body}:
      Spn{0, "* "}
        <> (Col{1, nick_color_themed(th, nick), nick}
        <> (Spn{0, " "}
        <> render_spans(body)))

def parse_nick_act.ok_themed(ok: Bool, +rest: String, +nick: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match ok:
    case True{}:
      parse_nick_act.body_themed(rest, nick, th)
    case False{}:
      render_spans("* " ++ nick ++ rest)

def parse_nick_act.parsed_themed(pair: String & String, +th: Theme.Id) -> List<&2, SpanOp>:
  match pair:
    case (+nick, +rest):
      parse_nick_act.ok_themed(String.starts_with(rest, " ") && Bool.not(String.is_empty(nick)), rest, nick, th)

def parse_nick_act.rest_themed(+t2: String, +th: Theme.Id) -> List<&2, SpanOp>:
  parse_nick_act.parsed_themed(Irc.take_until_space(t2), th)

def parse_nick_act.sp_themed(is_sp: Bool, +t2: String, +s: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match is_sp:
    case True{}:
      parse_nick_act.rest_themed(t2, th)
    case False{}:
      render_spans(s)

def parse_nick_act.t1_themed(+t1: String, +s: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match t1:
    case SNil{}:
      render_spans(s)
    case SCon{+c2, +t2}:
      parse_nick_act.sp_themed(Char.is_eq(c2, ' '), t2, s, th)

def parse_nick_act.star_themed(is_star: Bool, +t1: String, +s: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match is_star:
    case True{}:
      parse_nick_act.t1_themed(t1, s, th)
    case False{}:
      render_spans(s)

def parse_nick_act_themed(s: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{+c1, +t1}:
      parse_nick_act.star_themed(Char.is_eq(c1, '*'), t1, s, th)

def line_spans_raw_themed(k: Cl.LineKind, +text: String, +th: Theme.Id) -> List<&2, SpanOp>:
  match k:
    case Cl.Msg{}:
      parse_nick_msg_themed(text, th)
    case Cl.Self{}:
      parse_nick_msg_themed(text, th)
    case Cl.Highlight{}:
      parse_nick_msg_themed(text, th)
    case Cl.Action{}:
      parse_nick_act_themed(text, th)
    case _:
      render_spans(text)

def line_spans_for_themed(k: Cl.LineKind, text: String, +th: Theme.Id) -> List<&2, SpanOp>:
  cluster_spans(line_spans_raw_themed(k, text, th))

def line_ops_go_themed(
  +x: U32,
  +y: U32,
  +w: U32,
  +fg: U32,
  +ts: String,
  +spans: List<&2, SpanOp>,
  empty: Bool,
  +th: Theme.Id
) -> List<&2, DrawOp>:
  match empty:
    case True{}:
      OpLine{x, y, w, fg, spans} <> Nil{}
    case False{}:
      OpText{x, y, ts_w(w), FG_DIM_themed(th), 0, ts}
        <> (OpLine{U32.add(x, line_shift(w)), y, line_rest(w), fg, spans} <> Nil{})

def line_ops_at_ts.recon_themed(+x: U32, +y: U32, +w: U32, +text: String, +th: Theme.Id) -> List<&2, DrawOp>:
  OpText{x, y, w, FG_DIM_themed(th), 0, recon_divider(text, w)} <> Nil{}

def line_ops_at_ts.chk_themed(is_rec: Bool, +x: U32, +y: U32, +w: U32, +k: Cl.LineKind, +ts: String, +text: String, show_ts: Bool, +th: Theme.Id) -> List<&2, DrawOp>:
  match is_rec:
    case True{}:
      line_ops_at_ts.recon_themed(x, y, w, text, th)
    case False{}:
      line_ops_go_themed(x, y, w, style_of_themed(th, k), ts, line_spans_for_themed(k, text, th), Bool.not(show_ts) || String.is_empty(ts), th)

def line_ops_at_ts_themed(+x: U32, +y: U32, +w: U32, +ln: Cl.Line, show_ts: Bool, +th: Theme.Id) -> List<&2, DrawOp>:
  match ln:
    case Cl.Line{+k, +ts, +text, +author, +id}:
      line_ops_at_ts.chk_themed(Cl.is_reconnect(k), x, y, w, k, ts, text, show_ts, th)

def line_ops_at_themed(+x: U32, +y: U32, +w: U32, +ln: Cl.Line, +th: Theme.Id) -> List<&2, DrawOp>:
  line_ops_at_ts_themed(x, y, w, ln, True{}, th)

def line_ops_themed(+ln: Cl.Line, +th: Theme.Id) -> List<&2, DrawOp>:
  line_ops_at_themed(0, 0, 40, ln, th)

def wrapped_rows.metrics_themed(metrics: WrapMetrics, +k: Cl.LineKind, text: String, +th: Theme.Id) -> List<&2, BodyRow>:
  match metrics:
    case WrapMetrics{shown, stamp_w, first_off, +first_w, cont_off, +cont_w}:
      wrapped_rows.chunks(wrap_spans(line_spans_for_themed(k, text, th), first_w, cont_w), shown, stamp_w, first_off, first_w, cont_off, cont_w, style_of_themed(th, k))

def wrapped_rows_themed(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool, +th: Theme.Id) -> List<&2, BodyRow>:
  wrapped_rows.metrics_themed(wrap_metrics(k, ts, text, w, show_ts), k, text, th)

def wrapped_media.metrics_themed(metrics: WrapMetrics, urls: List<&2, String>, +k: Cl.LineKind, text: String, +w: U32, id: Nat, +media: M.State, +th: Theme.Id) -> List<&2, BodyRow>:
  match metrics:
    case WrapMetrics{shown, stamp_w, first_off, first_w, cont_off, cont_w}:
      wrapped_media.parts(media_parts(line_spans_for_themed(k, text, th), Nil{}, urls), media, M.Inline{id}, shown, stamp_w, first_off, first_w, cont_off, cont_w, style_of_themed(th, k), w)

def wrapped_media.known_themed(urls: List<&2, String>, +k: Cl.LineKind, +ts: String, +text: String, +w: U32, +show_ts: Bool, +id: Nat, +media: M.State, +th: Theme.Id) -> List<&2, BodyRow>:
  match urls:
    case Nil{}: wrapped_rows_themed(k, ts, text, w, show_ts, th)
    case Con{+h, +tail}:
      wrapped_media.metrics_themed(wrap_metrics(k, ts, text, w, show_ts), h <> tail, k, text, w, id, media, th)

def wrapped_media_themed(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, +show_ts: Bool, +id: Nat, +media: M.State, +th: Theme.Id) -> List<&2, BodyRow>:
  wrapped_media.known_themed(M.known_urls(media, M.Inline{id}), k, ts, text, w, show_ts, id, media, th)

def wrap_line_media_themed(+ln: Cl.Line, +w: U32, show_ts: Bool, +media: M.State, +th: Theme.Id) -> List<&2, BodyRow>:
  match ln:
    case Cl.Line{Cl.Reconnect{}, _, text, _, _}: [BodyRecon{text, w}]
    case Cl.Line{Cl.System{}, +ts, +text, _, 0n}:
      Bool.pick(List<&2, BodyRow>, contains_url(M.known_urls(media, M.Manual{}), text),
        media_rows(M.token(media, M.Manual{}, text), w), wrapped_media_themed(Cl.System{}, ts, text, w, show_ts, 0n, media, th))
    case Cl.Line{+k, +ts, +text, _, +id}: wrapped_media_themed(k, ts, text, w, show_ts, id, media, th)

def wrap_lines_media_themed(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +media: M.State, +th: Theme.Id) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{h, tail}: List.append(&2, BodyRow, wrap_line_media_themed(h, w, show_ts, media, th), wrap_lines_media_themed(tail, w, show_ts, media, th))

def unwrapped_line.on_themed(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool, recon: Bool, +th: Theme.Id) -> BodyRow:
  match recon:
    case True{}:
      BodyRecon{text, w}
    case False{}:
      +shown = Bool.pick(String, show_ts, ts, "")
      +off = Bool.pick(U32, String.is_empty(shown), 0, line_shift(w))
      +spans = line_spans_for_themed(k, text, th)
      BodyRow{shown, ts_w(w), off, U32.sub(w, off), style_of_themed(th, k), spans, spans_chars(spans)}

def unwrapped_line_themed(+ln: Cl.Line, +w: U32, show_ts: Bool, +th: Theme.Id) -> BodyRow:
  match ln:
    case Cl.Line{+k, +ts, +text, +author, +id}:
      unwrapped_line.on_themed(k, ts, text, w, show_ts, Cl.is_reconnect(k), th)

def unwrapped_lines_themed(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +th: Theme.Id) -> List<&2, BodyRow>:
  match lines:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      unwrapped_line_themed(h, w, show_ts, th) <> unwrapped_lines_themed(t, w, show_ts, th)

def body_rows_media.on_themed(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, media: M.State, synthetic: Bool, +th: Theme.Id) -> List<&2, BodyRow>:
  match synthetic:
    case True{}: unwrapped_lines_themed(lines, w, show_ts, th)
    case False{}: wrap_lines_media_themed(lines, w, show_ts, media, th)

def body_rows_media_themed(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, media: M.State, +th: Theme.Id) -> List<&2, BodyRow>:
  body_rows_media.on_themed(lines, w, show_ts, media, String.eq(name, "*settings*"), th)

def recent_lines.more_themed(state: Nat & List<&2, BodyRow>, +line: Cl.Line, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +th: Theme.Id, k: (Nat & List<&2, BodyRow>) -> List<&2, BodyRow>) -> List<&2, BodyRow>:
  match state:
    case (0n, acc): acc
    case (1n+p, +acc):
      +left : Nat = 1n+p
      +rows = body_rows_media_themed(body_of.lines([line], mutes, joins, nicks, name, server), name, w, show_ts, media, th)
      +count = List.length(&2, BodyRow, rows)
      +keep = Nat.min(left, count)
      k((Nat.sub(left, keep), List.append(&2, BodyRow, List.drop(&2, BodyRow, rows, Nat.sub(count, keep)), acc)))

def recent_lines.go_themed(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +th: Theme.Id, state: Nat & List<&2, BodyRow>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Pair.snd(Nat, List<&2, BodyRow>, state)
    case Con{+h, t}:
      recent_lines.more_themed(state, h, name, w, show_ts, mutes, joins, nicks, server, media, th,
        next => recent_lines.go_themed(t, name, w, show_ts, mutes, joins, nicks, server, media, th, next))

def anchored_lines_media_themed(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State, +th: Theme.Id) -> List<&2, AnchoredRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +after = Nat.sub(left, 1n)
      +head = body_rows_media_themed(body_of.lines(h <> Nil{}, mutes, joins, nicks, name, server), name, w, show_ts, media, th)
      List.append(&2, AnchoredRow, anchored_line(head, after), anchored_lines_media_themed(t, name, w, show_ts, mutes, joins, nicks, server, after, media, th))

def body_of.buf_media.bottom_themed(bottom: Bool, +lines: List<&2, Cl.Line>, +name: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, scroll: Cl.Scroll, +th: Theme.Id) -> List<&2, BodyRow>:
  match bottom:
    case True{}: recent_lines.go_themed(List.reverse(&2, Cl.Line, lines), name, w, show_ts, mutes, joins, nicks, server, media, th, (height, Nil{}))
    case False{}: visible_anchored(anchored_lines_media_themed(lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media, th), height, scroll)

def body_of.buf_media_themed(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +th: Theme.Id) -> List<&2, BodyRow>:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, Cl.ScrollAt{+after, +tail}}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      body_of.buf_media.bottom_themed(Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), lines, name, height, w, show_ts, mutes, joins, nicks, server, media, Cl.ScrollAt{after, tail}, th)

def body_box.on_themed(+x: U32, +y: U32, +w: U32, +h: U32, +title: String, empty: Bool, +th: Theme.Id) -> List<&2, DrawOp>:
  match empty:
    case True{}:
      OpBox{x, y, w, h} <> Nil{}
    case False{}:
      OpBox{x, y, w, h} <> OpText{inner_x(x), y, inner_w(w), FG_DIM_themed(th), 0, title} <> Nil{}

def body_box_themed(r: Rect, +title: String, +th: Theme.Id) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, w, h}:
      body_box.on_themed(x, y, w, h, title, String.is_empty(title), th)

def body_row_ops.normal_themed(+x: U32, +y: U32, +ts: String, +stamp_w: U32, +off: U32, +w: U32, +fg: U32, +spans: List<&2, SpanOp>, empty: Bool, +th: Theme.Id) -> List<&2, DrawOp>:
  match empty:
    case True{}:
      OpLine{U32.add(x, off), y, w, fg, spans} <> Nil{}
    case False{}:
      OpText{x, y, stamp_w, FG_DIM_themed(th), 0, ts}
        <> (OpLine{U32.add(x, off), y, w, fg, spans} <> Nil{})

def body_row_ops_themed(+x: U32, +y: U32, row: BodyRow, +th: Theme.Id) -> List<&2, DrawOp>:
  match row:
    case BodyRow{+ts, stamp_w, off, w, fg, +spans, _}:
      body_row_ops.normal_themed(x, y, ts, stamp_w, off, w, fg, spans, String.is_empty(ts), th)
    case BodyRecon{+text, +w}:
      OpText{x, y, w, FG_DIM_themed(th), 0, recon_divider(text, w)} <> Nil{}
    case BodyMedia{_, _, _, _}: Nil{}

def body_ops.go_themed(fuel: Nat, xs: List<&2, BodyRow>, +x: U32, +y: U32, +th: Theme.Id) -> List<&2, DrawOp>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{BodyMedia{token, w, +h, +row}, +tail}:
          +visible = U32.min(U32.sub(h, row), U32.from_nat(Nat.add(1n, List.length(&2, BodyRow, tail))))
          OpMedia{x, y, w, h, row, visible, token} <> body_ops.go_themed(p, List.drop(&2, BodyRow, tail, Nat.sub(U32.to_nat(visible), 1n)), x, U32.add(y, visible), th)
        case Con{head, tail}:
          List.append(&2, DrawOp, body_row_ops_themed(x, y, head, th), body_ops.go_themed(p, tail, x, U32.add(y, 1), th))

def body_ops_themed(r: Rect, +xs: List<&2, BodyRow>, +th: Theme.Id) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, w, h}:
      +n = U32.from_nat(List.length(&2, BodyRow, xs))
      body_ops.go_themed(List.length(&2, BodyRow, xs), xs, inner_x(x), body_y0(y, h, n), th)

def nick_ops.go_themed(xs: List<&2, String>, ok: Bool, +x: U32, +y: U32, +w: U32, +fg: U32, +max_y: U32, +th: Theme.Id) -> List<&2, DrawOp>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      match ok:
        case False{}:
          Nil{}
        case True{}:
          OpText{x, y, w, nick_color_themed(th, Cl.nick_strip(h)), 0, h}
            <> nick_ops.go_themed(t, U32.is_lt(U32.add(y, 1), max_y), x, U32.add(y, 1), w, fg, max_y, th)

def nick_ops.wide_themed(+x: U32, +y: U32, +w: U32, +h: U32, +title: String, +names: List<&2, String>, wide: Bool, +th: Theme.Id) -> List<&2, DrawOp>:
  match wide:
    case False{}:
      Nil{}
    case True{}:
      +ix = inner_x(x)
      +iw = inner_w(w)
      +fg = FG_DIM_themed(th)
      +y1 = U32.add(y, 1)
      +max_y = box_max_y(y, h)
      OpBox{x, y, w, h}
        <> OpText{ix, y, iw, fg, 0, title}
        <> nick_ops.go_themed(names, U32.is_lt(y1, max_y), ix, y1, iw, fg, max_y, th)

def nick_ops_themed(r: Rect, +title: String, +names: List<&2, String>, +th: Theme.Id) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, +w, h}:
      nick_ops.wide_themed(x, y, w, h, title, names, U32.is_gt(w, 2), th)

def view_ops.rest_themed(+br: Rect, +bod: List<&2, BodyRow>, +preview: String, +nr: Rect, +title: String, +nicks: List<&2, String>, +sr: Rect, +st: String, +th: Theme.Id) -> List<&2, DrawOp>:
  List.append(&2, DrawOp, image_ops(br, preview),
    List.append(&2, DrawOp, body_ops_themed(br, bod, th),
    List.append(&2, DrawOp, nick_ops_themed(nr, title, nicks, th),
      op_text(sr, FG_DIM_themed(th), st) <> Nil{})))

def view_ops_themed(
  lay0: Lay,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +names: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +bod: List<&2, BodyRow>,
  +preview: String,
  +btitle: String,
  +ntitle: String,
  +nicks: List<&2, String>,
  +st: String,
  +th: Theme.Id
) -> List<&2, DrawOp>:
  match lay0:
    case Lay{tr, ur, +br, nr, sr}:
      List.append(&2, DrawOp,
        op_tabs(tr, U32.from_nat(active), names, alerts, bell, bell_seq)
          <> List.append(&2, DrawOp, user_header_ops_themed(ur, nick, server, net, th), body_box_themed(br, btitle, th)),
        view_ops.rest_themed(br, bod, preview, nr, ntitle, nicks, sr, st, th))

def view_ops_split_themed(
  lay0: Lay,
  +axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +names: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +r1: Rect,
  +title1: String,
  +body1: List<&2, BodyRow>,
  +preview1: String,
  +r2: Rect,
  +title2: String,
  +body2: List<&2, BodyRow>,
  +preview2: String,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String,
  +th: Theme.Id
) -> List<&2, DrawOp>:
  match lay0:
    case Lay{tabs, user, body, nicks_rect, status_rect}:
      List.append(&2, DrawOp,
        op_tabs(tabs, U32.from_nat(active), names, alerts, bell, bell_seq)
          <> List.append(&2, DrawOp, user_header_ops_themed(user, nick, server, net, th),
               op_split(body, axis)
                 <> List.append(&2, DrawOp, body_box_themed(r1, title1, th),
                      List.append(&2, DrawOp, image_ops(r1, preview1),
                        List.append(&2, DrawOp, body_ops_themed(r1, body1, th),
                          List.append(&2, DrawOp, body_box_themed(r2, title2, th),
                            List.append(&2, DrawOp, image_ops(r2, preview2), body_ops_themed(r2, body2, th))))))),
        List.append(&2, DrawOp, nick_ops_themed(nicks_rect, ntitle, nicks, th),
          op_text(status_rect, FG_DIM_themed(th), status) <> Nil{}))

def view_split_source.rects_themed(
  pair: Rect & Rect,
  lay0: Lay,
  axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +tabs: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +b1: Cl.Buffer,
  +b2: Cl.Buffer,
  +focused: U32,
  +mutes: List<&2, String>,
  +show_joins: Bool,
  +show_nicks: Bool,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String,
  +typers: List<&2, String>,
  +show_ts: Bool,
  +media: M.State,
  +legacy: Bool,
  +th: Theme.Id
) -> List<&2, DrawOp>:
  match pair:
    case (+r1, +r2):
      body1 body2 = body_of.buf_media_themed(b1, rect_vis_h(r1), rect_vis_w(r1), show_ts, mutes, show_joins, show_nicks, server, media, th) body_of.buf_media_themed(b2, rect_vis_h(r2), rect_vis_w(r2), show_ts, mutes, show_joins, show_nicks, server, media, th)
      view_ops_split_themed(lay0, axis, nick, server, net, active, tabs, alerts, bell, bell_seq, r1, split_title(b1, focused, 0), body1, Bool.pick(String, legacy, preview_path_of(b1), ""), r2, split_title(b2, focused, 1), body2, Bool.pick(String, legacy, preview_path_of(b2), ""), ntitle, nicks, status_or_typing(status, typers), th)

def view_split_source_themed(
  +cl: Cl.Client,
  +rows: U32,
  +cols: U32,
  +draft: String,
  +net: String,
  +axis: Sp.Axis,
  +first: String,
  +second: String,
  +focused: U32,
  +typers: List<&2, String>,
  +media: M.State,
  +legacy: Bool,
  +th: Theme.Id
) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      b1 b2 = active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))) active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active)))
      +focused_buf = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +body_rect = lay_body_rect(lay0)
      +tabs = tab_names(bufs, Cl.settings_unreads(stg))
      +alerts = tab_alerts(bufs, Cl.settings_unreads(stg))
      +mutes = Cl.settings_mutes(stg)
      +joins = Cl.settings_joins(stg)
      +nicks = Cl.settings_nicks(stg)
      nt status = nicks_title_of(focused_buf) status_of.buf(focused_buf)
      +ns = nicks_list_of(focused_buf)
      ViewModel{view_split_source.rects_themed(split_rects(axis, body_rect), lay0, axis, nick, server, net, active, tabs, alerts, bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), b1, b2, focused, mutes, joins, nicks, nt, ns, status, typers, Cl.settings_ts(stg), media, legacy, th), view_input(draft)}

def view_split_media_themed(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +axis: Sp.Axis, +first: String, +second: String, +focused: U32, +typers: List<&2, String>, +media: M.State, +th: Theme.Id) -> ViewModel:
  view_split_source_themed(cl, rows, cols, draft, net, axis, first, second, focused, typers, media, False{}, th)

def view_draft.single_source_themed(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +legacy: Bool, +th: Theme.Id) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +br = lay_body_rect(lay0)
      bod = body_of.buf_media_themed(b, vis_h(rows), rect_vis_w(br), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, th)
      bt nt = body_title_of(b) nicks_title_of(b)
      +ns = nicks_list_of(b)
      ViewModel{view_ops_themed(lay0, nick, server, net, active, tab_names(bufs, Cl.settings_unreads(stg)), tab_alerts(bufs, Cl.settings_unreads(stg)), bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), bod, Bool.pick(String, legacy, preview_path_of(b), ""), bt, nt, ns, status_or_typing(status_of.buf(b), typers), th), view_input(draft)}

def view_draft.single_media_themed(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +th: Theme.Id) -> ViewModel:
  view_draft.single_source_themed(cl, rows, cols, draft, net, typers, media, False{}, th)

def view_draft.state_typing_media_themed(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State, +th: Theme.Id) -> ViewModel:
  match split:
    case Sp.On{axis, +first, +second, focus}:
      view_split_media_themed(cl, rows, cols, draft, net, axis, first, second, focus, typers, media, th)
    case Sp.Off{}:
      view_draft.single_media_themed(cl, rows, cols, draft, net, typers, media, th)

# Themed cards/casemapping live painters. Mirror the cards_cm chain above;
# card/mute/cm helpers stay shared, colors route through the themed leaves.
def card_rows_for_texts_themed(xs: List<&2, String>, +w: U32, +th: Theme.Id) -> List<&2, BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}: List.append(&2, BodyRow, wrapped_rows_themed(Cl.System{}, "", h, w, False{}, th), card_rows_for_texts_themed(t, w, th))

def card_rows_for_entry_themed(+texts: List<&2, String>, +w: U32, +th: Theme.Id) -> List<&2, BodyRow>:
  List.take(&2, BodyRow, card_rows_for_texts_themed(texts, w, th), card_rows_cap())

def card_rows_for_hit_themed(hit: Bool, +texts: List<&2, String>, +w: U32, +th: Theme.Id) -> List<&2, BodyRow>:
  match hit:
    case True{}: card_rows_for_entry_themed(texts, w, th)
    case False{}: Nil{}

def card_rows_for.go_themed(xs: List<&2, CardEntry>, +id: Nat, +w: U32, +th: Theme.Id) -> List<&2, BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{CardEntry{other, +texts}, t}:
      List.append(&2, BodyRow, card_rows_for_hit_themed(Nat.is_eq(other, id), texts, w, th), card_rows_for.go_themed(t, id, w, th))

def card_rows_for_themed(+xs: List<&2, CardEntry>, +id: Nat, +w: U32, +th: Theme.Id) -> List<&2, BodyRow>:
  card_rows_for.go_themed(xs, id, w, th)

def wrap_line_media_cards_themed(+ln: Cl.Line, +w: U32, show_ts: Bool, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id) -> List<&2, BodyRow>:
  match ln:
    case Cl.Line{Cl.Reconnect{}, _, text, _, _}: [BodyRecon{text, w}]
    case Cl.Line{Cl.System{}, +ts, +text, _, 0n}:
      Bool.pick(List<&2, BodyRow>, contains_url(M.known_urls(media, M.Manual{}), text),
        media_rows(M.token(media, M.Manual{}, text), w), wrapped_media_themed(Cl.System{}, ts, text, w, show_ts, 0n, media, th))
    case Cl.Line{+k, +ts, +text, _, +id}:
      List.append(&2, BodyRow, wrapped_media_themed(k, ts, text, w, show_ts, id, media, th), card_rows_for_themed(cards, id, w, th))

def wrap_lines_media_cards_themed(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{h, tail}: List.append(&2, BodyRow, wrap_line_media_cards_themed(h, w, show_ts, media, cards, th), wrap_lines_media_cards_themed(tail, w, show_ts, media, cards, th))

def body_rows_media_cards.on_themed(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, media: M.State, +cards: List<&2, CardEntry>, synthetic: Bool, +th: Theme.Id) -> List<&2, BodyRow>:
  match synthetic:
    case True{}: unwrapped_lines_themed(lines, w, show_ts, th)
    case False{}: wrap_lines_media_cards_themed(lines, w, show_ts, media, cards, th)

def body_rows_media_cards_themed(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id) -> List<&2, BodyRow>:
  body_rows_media_cards.on_themed(lines, w, show_ts, media, cards, String.eq(name, "*settings*"), th)

def recent_lines_cards.more_cm_themed(+cm: String, state: Nat & List<&2, BodyRow>, +line: Cl.Line, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id, k: (Nat & List<&2, BodyRow>) -> List<&2, BodyRow>) -> List<&2, BodyRow>:
  match state:
    case (0n, acc): acc
    case (1n+p, +acc):
      +left : Nat = 1n+p
      +rows = body_rows_media_cards_themed(body_of.lines_cm(cm, [line], mutes, joins, nicks, name, server), name, w, show_ts, media, cards, th)
      +count = List.length(&2, BodyRow, rows)
      +keep = Nat.min(left, count)
      k((Nat.sub(left, keep), List.append(&2, BodyRow, List.drop(&2, BodyRow, rows, Nat.sub(count, keep)), acc)))

def recent_lines_cards.go_cm_themed(+cm: String, lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id, state: Nat & List<&2, BodyRow>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Pair.snd(Nat, List<&2, BodyRow>, state)
    case Con{+h, t}:
      recent_lines_cards.more_cm_themed(cm, state, h, name, w, show_ts, mutes, joins, nicks, server, media, cards, th,
        next => recent_lines_cards.go_cm_themed(cm, t, name, w, show_ts, mutes, joins, nicks, server, media, cards, th, next))

def anchored_lines_media_cards_cm_themed(+cm: String, lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id) -> List<&2, AnchoredRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +after = Nat.sub(left, 1n)
      +head = body_rows_media_cards_themed(body_of.lines_cm(cm, h <> Nil{}, mutes, joins, nicks, name, server), name, w, show_ts, media, cards, th)
      List.append(&2, AnchoredRow, anchored_line(head, after), anchored_lines_media_cards_cm_themed(cm, t, name, w, show_ts, mutes, joins, nicks, server, after, media, cards, th))

def body_of.buf_media_cards.bottom_cm_themed(+cm: String, bottom: Bool, +lines: List<&2, Cl.Line>, +name: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, scroll: Cl.Scroll, +th: Theme.Id) -> List<&2, BodyRow>:
  match bottom:
    case True{}: recent_lines_cards.go_cm_themed(cm, List.reverse(&2, Cl.Line, lines), name, w, show_ts, mutes, joins, nicks, server, media, cards, th, (height, Nil{}))
    case False{}: visible_anchored(anchored_lines_media_cards_cm_themed(cm, lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media, cards, th), height, scroll)

def body_of.buf_media_cards_cm_themed(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id) -> List<&2, BodyRow>:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, Cl.ScrollAt{+after, +tail}}:
      +lines = media_display_lines(name, topic, raw_lines, media)
      body_of.buf_media_cards.bottom_cm_themed(cm, Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), lines, name, height, w, show_ts, mutes, joins, nicks, server, media, cards, Cl.ScrollAt{after, tail}, th)

def view_split_source_cards_cm.rects_themed(
  +cm: String,
  pair: Rect & Rect,
  lay0: Lay,
  axis: Sp.Axis,
  +nick: String,
  +server: String,
  +net: String,
  +active: Nat,
  +tabs: List<&2, String>,
  +alerts: List<&2, U32>,
  +bell: U32,
  +bell_seq: U32,
  +b1: Cl.Buffer,
  +b2: Cl.Buffer,
  +focused: U32,
  +mutes: List<&2, String>,
  +show_joins: Bool,
  +show_nicks: Bool,
  +ntitle: String,
  +nicks: List<&2, String>,
  +status: String,
  +typers: List<&2, String>,
  +show_ts: Bool,
  +media: M.State,
  +cards: List<&2, CardEntry>,
  +legacy: Bool,
  +th: Theme.Id
) -> List<&2, DrawOp>:
  match pair:
    case (+r1, +r2):
      body1 body2 = body_of.buf_media_cards_cm_themed(cm, b1, rect_vis_h(r1), rect_vis_w(r1), show_ts, mutes, show_joins, show_nicks, server, media, cards, th) body_of.buf_media_cards_cm_themed(cm, b2, rect_vis_h(r2), rect_vis_w(r2), show_ts, mutes, show_joins, show_nicks, server, media, cards, th)
      view_ops_split_themed(lay0, axis, nick, server, net, active, tabs, alerts, bell, bell_seq, r1, split_title(b1, focused, 0), body1, Bool.pick(String, legacy, preview_path_of(b1), ""), r2, split_title(b2, focused, 1), body2, Bool.pick(String, legacy, preview_path_of(b2), ""), ntitle, nicks, status_or_typing(status, typers), th)

def view_split_source_cards_cm_themed(
  +cm: String,
  +cl: Cl.Client,
  +rows: U32,
  +cols: U32,
  +draft: String,
  +net: String,
  +axis: Sp.Axis,
  +first: String,
  +second: String,
  +focused: U32,
  +typers: List<&2, String>,
  +media: M.State,
  +cards: List<&2, CardEntry>,
  +legacy: Bool,
  +th: Theme.Id
) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      b1 b2 = active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))) active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active)))
      +focused_buf = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +body_rect = lay_body_rect(lay0)
      +tabs = tab_names_cm(cm, bufs, Cl.settings_unreads(stg))
      +alerts = tab_alerts_cm(cm, bufs, Cl.settings_unreads(stg))
      +mutes = Cl.settings_mutes(stg)
      +joins = Cl.settings_joins(stg)
      +nicks = Cl.settings_nicks(stg)
      nt status = nicks_title_of(focused_buf) status_of.buf(focused_buf)
      +ns = nicks_list_of(focused_buf)
      ViewModel{view_split_source_cards_cm.rects_themed(cm, split_rects(axis, body_rect), lay0, axis, nick, server, net, active, tabs, alerts, bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), b1, b2, focused, mutes, joins, nicks, nt, ns, status, typers, Cl.settings_ts(stg), media, cards, legacy, th), view_input(draft)}

def view_split_media_cards_cm_themed(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +axis: Sp.Axis, +first: String, +second: String, +focused: U32, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id) -> ViewModel:
  view_split_source_cards_cm_themed(cm, cl, rows, cols, draft, net, axis, first, second, focused, typers, media, cards, False{}, th)

def view_draft.single_source_cards_cm_themed(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>, +legacy: Bool, +th: Theme.Id) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, +auth, +log_seq}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +br = lay_body_rect(lay0)
      bod = body_of.buf_media_cards_cm_themed(cm, b, vis_h(rows), rect_vis_w(br), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards, th)
      bt nt = body_title_of(b) nicks_title_of(b)
      +ns = nicks_list_of(b)
      ViewModel{view_ops_themed(lay0, nick, server, net, active, tab_names_cm(cm, bufs, Cl.settings_unreads(stg)), tab_alerts_cm(cm, bufs, Cl.settings_unreads(stg)), bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), bod, Bool.pick(String, legacy, preview_path_of(b), ""), bt, nt, ns, status_or_typing(status_of.buf(b), typers), th), view_input(draft)}

def view_draft.single_media_cards_cm_themed(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id) -> ViewModel:
  view_draft.single_source_cards_cm_themed(cm, cl, rows, cols, draft, net, typers, media, cards, False{}, th)

def view_draft.state_typing_media_cards_cm_themed(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id) -> ViewModel:
  match split:
    case Sp.On{axis, +first, +second, focus}:
      view_split_media_cards_cm_themed(cm, cl, rows, cols, draft, net, axis, first, second, focus, typers, media, cards, th)
    case Sp.Off{}:
      view_draft.single_media_cards_cm_themed(cm, cl, rows, cols, draft, net, typers, media, cards, th)
