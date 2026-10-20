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

def cluster_spans.nil(done: Bool, rev: List<&2, SpanOp>) -> List<&2, SpanOp>:
  match done:
    case True{}: cluster_finish(List.reverse(&2, SpanOp, rev))
    case False{}: cluster_finish(List.reverse(&2, SpanOp, rev))

# `bound` is the copyable cluster-walk limit. `p` only decreases this loop.
def cluster_spans.go(fuel: Nat, +text: String, xs: List<&2, SpanOp>, rev: List<&2, SpanOp>, +bound: Nat) -> List<&2, SpanOp>:
  match fuel:
    case 0n: cluster_finish(List.reverse(&2, SpanOp, rev))
    case 1n+p:
      match text:
        case SNil{}: cluster_spans.nil(Nat.is_eq(p, 0n), rev)
        case SCon{_, _}: cluster_spans.piece(Cols.cluster_bounded(text, bound), xs, rev, remaining => rest => acc => cluster_spans.go(p, remaining, rest, acc, bound))

def cluster_spans(+xs: List<&2, SpanOp>) -> List<&2, SpanOp>:
  +text = spans_text(xs)
  +n = String.length(text)
  +fuel = Nat.add(2n, Nat.add(n, n))
  cluster_spans.go(fuel, text, spans_drop(xs, 0n), Nil{}, fuel)

type Rect is Data:
  Rect{x: U32, y: U32, w: U32, h: U32}

# Pane roles on OpBox/OpSplit (U32 for the TimUI FFI). Unknown (0) is the
# backward-compatible default for hand-built ops in tests; production paint
# tags Body / Nicks / Composer so C does not infer from x==0 or geometry.
def PANE_UNKNOWN() -> U32:
  0

def PANE_BODY() -> U32:
  1

def PANE_NICKS() -> U32:
  2

def PANE_COMPOSER() -> U32:
  3

type DrawOp is Data:
  OpBox{x: U32, y: U32, w: U32, h: U32, role: U32}
  OpSplit{x: U32, y: U32, w: U32, h: U32, axis: U32, role: U32}
  OpText{x: U32, y: U32, w: U32, fg: U32, attrs: U32, text: String}
  OpTabs{x: U32, y: U32, w: U32, sel: U32, names: List<&2, String>, alerts: List<&2, U32>, bell: U32, bell_seq: U32}
  OpLine{x: U32, y: U32, w: U32, fg: U32, spans: List<&2, SpanOp>}
  OpImage{x: U32, y: U32, w: U32, h: U32, path: String}
  OpMedia{x: U32, y: U32, w: U32, h: U32, clip_y: U32, clip_h: U32, token: U32}
  # Deferred after the composer widget; never shares OpText attrs space.
  OpGhost{x: U32, y: U32, w: U32, fg: U32, text: String}

# Test / exhaustiveness helper: role defaults to Unknown.
def op_box(+x: U32, +y: U32, +w: U32, +h: U32) -> DrawOp:
  OpBox{x, y, w, h, PANE_UNKNOWN()}

def op_box_role(+x: U32, +y: U32, +w: U32, +h: U32, +role: U32) -> DrawOp:
  OpBox{x, y, w, h, role}

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

# Pending rows keep inner-kind parsing; explicit colors dim while plain
# spans inherit the dimmed row fg. Links stay bright (still clickable).
def span_dim(+sp: SpanOp) -> SpanOp:
  match sp:
    case Spn{+attrs, +text}: Spn{attrs, text}
    case Lnk{+url, +text}: Lnk{url, text}
    case Col{+attrs, +fg, +text}: Col{attrs, Theme.dim_fg(fg), text}

def spans_dim(+xs: List<&2, SpanOp>) -> List<&2, SpanOp>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}: span_dim(h) <> spans_dim(t)

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
    case Cl.Pending{+inner}:
      spans_dim(line_spans_raw(inner, text))
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

def recon_label.marked(marked: Bool, +text: String) -> String:
  match marked:
    case True{}: " " ++ String.drop(text, 1n) ++ " "
    case False{}: recon_label.ts(String.is_empty(text), text)

def recon_label(+text: String) -> String:
  recon_label.marked(String.starts_with(text, "@"), text)

def bar_text(day: Bool, +text: String) -> String:
  match day:
    case True{}: "@" ++ text
    case False{}: text

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
      line_ops_at_ts.chk(Cl.is_reconnect(k) || Cl.is_day(k), x, y, w, k, Cl.now_hms(ts), bar_text(Cl.is_day(k), text), show_ts)

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

def word_break.keep(keep: Bool, last: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match keep:
    case True{}: last
    case False{}: last

def word_break.go(fuel: Nat, +s: String, pos: Nat, last: Maybe<&2, Nat>, in_space: Bool, +bound: Nat) -> Maybe<&2, Nat>:
  match fuel:
    case 0n: last
    case 1n+p:
      match s:
        case SNil{}: word_break.keep(Nat.is_eq(p, 0n), last)
        case SCon{_, _}: word_break.piece(Cols.cluster_bounded(s, bound), pos, last, in_space, rest => n => boundary => space => word_break.go(p, rest, n, boundary, space, bound))

def spans_drop_spaces.piece(space: Bool, +sp: SpanOp, +rest: List<&2, SpanOp>, +tail: String, k: List<&2, SpanOp> -> List<&2, SpanOp>) -> List<&2, SpanOp>:
  match space:
    case False{}: sp <> rest
    case True{}: k(Bool.pick(List<&2, SpanOp>, String.is_empty(tail), rest, span_text_as(sp, tail) <> rest))

def spans_drop_spaces.cut(piece: Cols.Cut, +sp: SpanOp, rest: List<&2, SpanOp>, k: List<&2, SpanOp> -> List<&2, SpanOp>) -> List<&2, SpanOp>:
  match piece:
    case Cols.Cut{head, tail, _}: spans_drop_spaces.piece(String.eq(head, " "), sp, rest, tail, k)

def spans_drop_spaces.keep(keep: Bool, xs: List<&2, SpanOp>) -> List<&2, SpanOp>:
  match keep:
    case True{}: xs
    case False{}: xs

def spans_drop_spaces.go(fuel: Nat, xs: List<&2, SpanOp>, +bound: Nat) -> List<&2, SpanOp>:
  match fuel:
    case 0n: xs
    case 1n+p:
      match xs:
        case Nil{}: spans_drop_spaces.keep(Nat.is_eq(p, 0n), Nil{})
        case Con{+sp, rest}: spans_drop_spaces.cut(Cols.cluster_bounded(span_text(sp), bound), sp, rest, tail => spans_drop_spaces.go(p, tail, bound))

def spans_drop_spaces(+xs: List<&2, SpanOp>) -> List<&2, SpanOp>:
  +n = spans_chars(xs)
  +fuel = Nat.add(2n, Nat.add(n, n))
  spans_drop_spaces.go(fuel, xs, fuel)

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
  +n = String.length(shown)
  +fuel = Nat.add(2n, Nat.add(n, n))
  word_cut.boundary(word_break.go(fuel, shown, 0n, None{}, False{}, fuel), SpanCut{head, tail}, xs, shown, protected)

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
      +piece = span_text(sp)
      word_cut.first(Cols.cluster_bounded(piece, Nat.add(1n, String.length(piece))), head, sp <> rest, xs, protected)

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
    case Con{+sp, rest}:
      +piece = span_text(sp)
      force_span_piece(Cols.cluster_bounded(piece, Nat.add(1n, String.length(piece))), sp, rest)

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

def msg_prefix_w.width(ok: Bool, +nick: String) -> U32:
  match ok:
    case True{}: Cols.text_width("<" ++ nick ++ "> ")
    case False{}: 0

def msg_prefix_w.parsed(pair: String & String) -> U32:
  match pair:
    case (+nick, +rest):
      msg_prefix_w.width(String.starts_with(rest, " ") && Bool.not(String.is_empty(nick)), nick)

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
    case Cl.Pending{+inner}: line_prefix_w(inner, text)
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

def FG_DIM_themed(+th: Theme.Id) -> U32:
  Theme.status_dim(th)

def FG_TEXT_themed(+th: Theme.Id) -> U32:
  Theme.kind_fg(th, Cl.Msg{})


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
    case Cl.Pending{+inner}:
      spans_dim(line_spans_raw_themed(inner, text, th))
    case _:
      render_spans(text)

def line_spans_for_themed(k: Cl.LineKind, text: String, +th: Theme.Id) -> List<&2, SpanOp>:
  cluster_spans(line_spans_raw_themed(k, text, th))


# One paint configuration for the media × cards × casemapping × theme × legacy
# axes. The record is always carried in a one-element list so a continuation
# captures one word. `inline` selects the media row expander; plain `wrap_line`
# keeps reconnect-inside-Pending as a divider, while every buffer painter uses
# the inline expander (empty media adds no image rows). `pends` is empty on
# every path that does not overlay optimistic sends, and the empty check in
# `pending_display_lines` returns history unchanged.
type PaintOpts is Data:
  PaintOpts{
    theme: Maybe<&2, Theme.Id>,
    iso: Maybe<&2, Cl.Iso>,
    media: M.State,
    cards: Maybe<&2, List<&2, CardEntry>>,
    legacy: Bool,
    pends: List<&2, Cl.PendSend>,
    inline: Bool
  }

def paint_box(theme: Maybe<&2, Theme.Id>, iso: Maybe<&2, Cl.Iso>, +media: M.State, cards: Maybe<&2, List<&2, CardEntry>>, legacy: Bool, +pends: List<&2, Cl.PendSend>, inline: Bool) -> List<&2, PaintOpts>:
  PaintOpts{theme, iso, media, cards, legacy, pends, inline} <> Nil{}

def paint_iso_cm(+cm: String) -> Cl.Iso:
  Cl.Iso{cm, Cl.dflt_types(), Cl.dflt_status(), Cl.dflt_sigils(), Cl.dflt_strip()}

def paint_text() -> List<&2, PaintOpts>:
  paint_box(None{}, None{}, M.empty(), None{}, False{}, Nil{}, False{})

def paint_media_only(+media: M.State) -> List<&2, PaintOpts>:
  paint_box(None{}, None{}, media, None{}, False{}, Nil{}, True{})

def paint_media_cards(+media: M.State, +cards: List<&2, CardEntry>) -> List<&2, PaintOpts>:
  paint_box(None{}, None{}, media, Some{cards}, False{}, Nil{}, True{})

def paint_media_cards_cm(+cm: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, PaintOpts>:
  paint_box(None{}, Some{paint_iso_cm(cm)}, media, Some{cards}, False{}, Nil{}, True{})

def paint_media_cards_iso(+isc: Cl.Iso, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, PaintOpts>:
  paint_box(None{}, Some{isc}, media, Some{cards}, False{}, Nil{}, True{})

def paint_media_theme(+media: M.State, +th: Theme.Id, +pends: List<&2, Cl.PendSend>) -> List<&2, PaintOpts>:
  paint_box(Some{th}, None{}, media, None{}, False{}, pends, True{})

def paint_media_cards_cm_theme(+cm: String, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id, +pends: List<&2, Cl.PendSend>) -> List<&2, PaintOpts>:
  paint_box(Some{th}, Some{paint_iso_cm(cm)}, media, Some{cards}, False{}, pends, True{})

def paint_media_iso_theme(+isc: Cl.Iso, +media: M.State, +th: Theme.Id, +pends: List<&2, Cl.PendSend>) -> List<&2, PaintOpts>:
  paint_box(Some{th}, Some{isc}, media, None{}, False{}, pends, True{})

def paint_media_cards_iso_theme(+isc: Cl.Iso, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id, +pends: List<&2, Cl.PendSend>) -> List<&2, PaintOpts>:
  paint_box(Some{th}, Some{isc}, media, Some{cards}, False{}, pends, True{})

def paint_legacy_empty() -> List<&2, PaintOpts>:
  paint_box(None{}, None{}, M.empty(), None{}, True{}, Nil{}, True{})

def opt_theme(boxed: List<&2, PaintOpts>) -> Maybe<&2, Theme.Id>:
  match boxed:
    case Nil{}: None{}
    case Con{PaintOpts{theme, _, _, _, _, _, _}, _}: theme

def opt_iso(boxed: List<&2, PaintOpts>) -> Maybe<&2, Cl.Iso>:
  match boxed:
    case Nil{}: None{}
    case Con{PaintOpts{_, iso, _, _, _, _, _}, _}: iso

def opt_cm.got(iso: Maybe<&2, Cl.Iso>) -> Maybe<&2, String>:
  match iso:
    case None{}: None{}
    case Some{+isc}: Some{Cl.iso_cm(isc)}

def opt_cm(boxed: List<&2, PaintOpts>) -> Maybe<&2, String>:
  opt_cm.got(opt_iso(boxed))

def opt_media(boxed: List<&2, PaintOpts>) -> M.State:
  match boxed:
    case Nil{}: M.empty()
    case Con{PaintOpts{_, _, media, _, _, _, _}, _}: media

def opt_cards(boxed: List<&2, PaintOpts>) -> Maybe<&2, List<&2, CardEntry>>:
  match boxed:
    case Nil{}: None{}
    case Con{PaintOpts{_, _, _, cards, _, _, _}, _}: cards

def opt_legacy(boxed: List<&2, PaintOpts>) -> Bool:
  match boxed:
    case Nil{}: False{}
    case Con{PaintOpts{_, _, _, _, legacy, _, _}, _}: legacy

def opt_pends(boxed: List<&2, PaintOpts>) -> List<&2, Cl.PendSend>:
  match boxed:
    case Nil{}: Nil{}
    case Con{PaintOpts{_, _, _, _, _, pends, _}, _}: pends

def opt_inline(boxed: List<&2, PaintOpts>) -> Bool:
  match boxed:
    case Nil{}: False{}
    case Con{PaintOpts{_, _, _, _, _, _, inline}, _}: inline

def paint_style_theme(theme: Maybe<&2, Theme.Id>, k: Cl.LineKind) -> U32:
  match theme:
    case None{}: style_of(k)
    case Some{id}: style_of_themed(id, k)

def paint_style(+boxed: List<&2, PaintOpts>, k: Cl.LineKind) -> U32:
  paint_style_theme(opt_theme(boxed), k)

def paint_dim_theme(theme: Maybe<&2, Theme.Id>) -> U32:
  match theme:
    case None{}: FG_DIM()
    case Some{id}: FG_DIM_themed(id)

def paint_dim(+boxed: List<&2, PaintOpts>) -> U32:
  paint_dim_theme(opt_theme(boxed))

def paint_fg_theme(theme: Maybe<&2, Theme.Id>) -> U32:
  match theme:
    case None{}: FG_TEXT()
    case Some{id}: FG_TEXT_themed(id)

def paint_fg(+boxed: List<&2, PaintOpts>) -> U32:
  paint_fg_theme(opt_theme(boxed))

def paint_nick_theme(theme: Maybe<&2, Theme.Id>, +nick: String) -> U32:
  match theme:
    case None{}: nick_color(nick)
    case Some{id}: nick_color_themed(id, nick)

def paint_nick(+boxed: List<&2, PaintOpts>, +nick: String) -> U32:
  paint_nick_theme(opt_theme(boxed), nick)

def paint_status_theme(theme: Maybe<&2, Theme.Id>, +net: String) -> U32:
  match theme:
    case None{}: status_color(net)
    case Some{id}: status_color_themed(id, net)

def paint_status(+boxed: List<&2, PaintOpts>, +net: String) -> U32:
  paint_status_theme(opt_theme(boxed), net)

def paint_spans_theme(theme: Maybe<&2, Theme.Id>, k: Cl.LineKind, text: String) -> List<&2, SpanOp>:
  match theme:
    case None{}: line_spans_for(k, text)
    case Some{id}: line_spans_for_themed(k, text, id)

def paint_spans(+boxed: List<&2, PaintOpts>, k: Cl.LineKind, text: String) -> List<&2, SpanOp>:
  paint_spans_theme(opt_theme(boxed), k, text)

def paint_shown(show_ts: Bool, +ts: String) -> String:
  match show_ts:
    case True{}: ts
    case False{}: ""

def paint_off.on(empty: Bool, +w: U32) -> U32:
  match empty:
    case True{}: 0
    case False{}: line_shift(w)

def paint_off(+shown: String, +w: U32) -> U32:
  paint_off.on(String.is_empty(shown), w)

def paint_wrapped_metrics(metrics: WrapMetrics, +k: Cl.LineKind, text: String, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match metrics:
    case WrapMetrics{shown, stamp_w, first_off, +first_w, cont_off, +cont_w}:
      wrapped_rows.chunks(wrap_spans(paint_spans(boxed, k, text), first_w, cont_w), shown, stamp_w, first_off, first_w, cont_off, cont_w, paint_style(boxed, k))

def paint_wrapped(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  paint_wrapped_metrics(wrap_metrics(k, ts, text, w, show_ts), k, text, boxed)

def paint_wrapped_media_metrics(metrics: WrapMetrics, urls: List<&2, String>, +k: Cl.LineKind, text: String, +w: U32, id: Nat, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match metrics:
    case WrapMetrics{shown, stamp_w, first_off, first_w, cont_off, cont_w}:
      wrapped_media.parts(media_parts(paint_spans(boxed, k, text), Nil{}, urls), opt_media(boxed), M.Inline{id}, shown, stamp_w, first_off, first_w, cont_off, cont_w, paint_style(boxed, k), w)

def paint_wrapped_media_known(urls: List<&2, String>, +k: Cl.LineKind, +ts: String, +text: String, +w: U32, +show_ts: Bool, +id: Nat, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match urls:
    case Nil{}: paint_wrapped(k, ts, text, w, show_ts, boxed)
    case Con{+h, +tail}:
      paint_wrapped_media_metrics(wrap_metrics(k, ts, text, w, show_ts), h <> tail, k, text, w, id, boxed)

def paint_wrapped_media(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, +show_ts: Bool, +id: Nat, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  paint_wrapped_media_known(M.known_urls(opt_media(boxed), M.Inline{id}), k, ts, text, w, show_ts, id, boxed)

def paint_card_texts(xs: List<&2, String>, +w: U32, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}: List.append(&2, BodyRow, paint_wrapped(Cl.System{}, "", h, w, False{}, boxed), paint_card_texts(t, w, boxed))

def paint_card_entry(+texts: List<&2, String>, +w: U32, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  List.take(&2, BodyRow, paint_card_texts(texts, w, boxed), card_rows_cap())

def paint_card_hit(hit: Bool, +texts: List<&2, String>, +w: U32, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match hit:
    case True{}: paint_card_entry(texts, w, boxed)
    case False{}: Nil{}

def paint_card_go(xs: List<&2, CardEntry>, +id: Nat, +w: U32, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{CardEntry{other, +texts}, t}:
      List.append(&2, BodyRow, paint_card_hit(Nat.is_eq(other, id), texts, w, boxed), paint_card_go(t, id, w, boxed))

def paint_cards_for.on(zero: Bool, +xs: List<&2, CardEntry>, +id: Nat, +w: U32, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match zero:
    case True{}: Nil{}
    case False{}: paint_card_go(xs, id, w, boxed)

# Id 0 never owns inline cards (admission and live kinds require id > 0);
# skip the ready-card scan on synthetic/pending rows.
def paint_cards_for(+xs: List<&2, CardEntry>, +id: Nat, +w: U32, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  paint_cards_for.on(Nat.is_eq(id, 0n), xs, id, w, boxed)

def paint_with_cards(cards: Maybe<&2, List<&2, CardEntry>>, rows: List<&2, BodyRow>, +id: Nat, +w: U32, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match cards:
    case None{}: rows
    case Some{xs}: List.append(&2, BodyRow, rows, paint_cards_for(xs, id, w, boxed))

def paint_append_cards(+boxed: List<&2, PaintOpts>, rows: List<&2, BodyRow>, +id: Nat, +w: U32) -> List<&2, BodyRow>:
  paint_with_cards(opt_cards(boxed), rows, id, w, boxed)

def paint_manual(manual: Bool, +ts: String, +text: String, +w: U32, show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match manual:
    case True{}: media_rows(M.token(opt_media(boxed), M.Manual{}, text), w)
    case False{}: paint_wrapped_media(Cl.System{}, ts, text, w, show_ts, 0n, boxed)

def paint_wrap_plain_on(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool, recon: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match recon:
    case True{}: BodyRecon{text, w} <> Nil{}
    case False{}: paint_wrapped(k, ts, text, w, show_ts, boxed)

def paint_wrap_plain(+ln: Cl.Line, +w: U32, show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match ln:
    case Cl.Line{+k, +ts, +text, _, _}:
      paint_wrap_plain_on(k, Cl.now_hms(ts), bar_text(Cl.is_day(k), text), w, show_ts, Cl.is_reconnect(k) || Cl.is_day(k), boxed)

def paint_wrap_inline(+ln: Cl.Line, +w: U32, show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match ln:
    case Cl.Line{Cl.Reconnect{}, _, text, _, _}: [BodyRecon{text, w}]
    case Cl.Line{Cl.Day{}, _, +text, _, _}: [BodyRecon{bar_text(True{}, text), w}]
    case Cl.Line{Cl.System{}, +ts, +text, _, 0n}:
      paint_manual(contains_url(M.known_urls(opt_media(boxed), M.Manual{}), text), Cl.now_hms(ts), text, w, show_ts, boxed)
    case Cl.Line{+k, +ts, +text, _, +id}:
      paint_append_cards(boxed, paint_wrapped_media(k, Cl.now_hms(ts), text, w, show_ts, id, boxed), id, w)

def paint_wrap_pick(inline: Bool, +ln: Cl.Line, +w: U32, show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match inline:
    case False{}: paint_wrap_plain(ln, w, show_ts, boxed)
    case True{}: paint_wrap_inline(ln, w, show_ts, boxed)

def paint_wrap_line(+ln: Cl.Line, +w: U32, show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  paint_wrap_pick(opt_inline(boxed), ln, w, show_ts, boxed)

def paint_wrap_lines(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{h, tail}: List.append(&2, BodyRow, paint_wrap_line(h, w, show_ts, boxed), paint_wrap_lines(tail, w, show_ts, boxed))

def paint_unwrapped_on(+k: Cl.LineKind, +ts: String, +text: String, +w: U32, show_ts: Bool, recon: Bool, +boxed: List<&2, PaintOpts>) -> BodyRow:
  match recon:
    case True{}: BodyRecon{text, w}
    case False{}:
      +shown = paint_shown(show_ts, ts)
      +off = paint_off(shown, w)
      +spans = paint_spans(boxed, k, text)
      BodyRow{shown, ts_w(w), off, U32.sub(w, off), paint_style(boxed, k), spans, spans_chars(spans)}

def paint_unwrapped_line(+ln: Cl.Line, +w: U32, show_ts: Bool, +boxed: List<&2, PaintOpts>) -> BodyRow:
  match ln:
    case Cl.Line{+k, +ts, +text, _, _}:
      paint_unwrapped_on(k, Cl.now_hms(ts), bar_text(Cl.is_day(k), text), w, show_ts, Cl.is_reconnect(k) || Cl.is_day(k), boxed)

def paint_unwrapped_lines(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}: paint_unwrapped_line(h, w, show_ts, boxed) <> paint_unwrapped_lines(t, w, show_ts, boxed)

def paint_body_rows_on(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +boxed: List<&2, PaintOpts>, synthetic: Bool) -> List<&2, BodyRow>:
  match synthetic:
    case True{}: paint_unwrapped_lines(lines, w, show_ts, boxed)
    case False{}: paint_wrap_lines(lines, w, show_ts, boxed)

def paint_body_rows(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  paint_body_rows_on(lines, w, show_ts, boxed, String.eq(name, "*settings*"))


def wrap_line_media(+ln: Cl.Line, +w: U32, show_ts: Bool, +media: M.State) -> List<&2, BodyRow>:
  paint_wrap_line(ln, w, show_ts, paint_media_only(media))

def wrap_lines_media(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool, +media: M.State) -> List<&2, BodyRow>:
  paint_wrap_lines(lines, w, show_ts, paint_media_only(media))

# Card rows splice under the anchor chat line with the same wrap mechanics as
# Cards.rows_for (System styling, no timestamp, per-card row cap). Client and
# history stay raw; only paint, navigation bounds, and visible scheduling read
# these synthetic rows, all through this one cascade.
def card_rows_for(+xs: List<&2, CardEntry>, +id: Nat, +w: U32) -> List<&2, BodyRow>:
  paint_cards_for(xs, id, w, paint_text())

def wrap_line_media_cards(+ln: Cl.Line, +w: U32, show_ts: Bool, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, BodyRow>:
  paint_wrap_line(ln, w, show_ts, paint_media_cards(media, cards))

def wrap_line(+ln: Cl.Line, +w: U32, show_ts: Bool) -> List<&2, BodyRow>:
  paint_wrap_line(ln, w, show_ts, paint_text())

def wrap_lines(lines: List<&2, Cl.Line>, +w: U32, +show_ts: Bool) -> List<&2, BodyRow>:
  paint_wrap_lines(lines, w, show_ts, paint_text())

def body_rows(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool) -> List<&2, BodyRow>:
  paint_body_rows(lines, name, w, show_ts, paint_text())

def body_rows_media(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, media: M.State) -> List<&2, BodyRow>:
  paint_body_rows(lines, name, w, show_ts, paint_media_only(media))

def media_display_lines(+name: String, +topic: String, +lines: List<&2, Cl.Line>, media: M.State) -> List<&2, Cl.Line>:
  Bool.pick(List<&2, Cl.Line>, String.eq(name, "*preview*") && contains_url(M.known_urls(media, M.Manual{}), topic),
    Cl.Line{Cl.System{}, "", topic, "", 0n} <> lines, lines)

# Optimistic-send overlay (same view-only idiom): unconfirmed echo-message
# sends render as dimmed Pending rows at the tail. Id 0 keeps them out of
# media/cards admission; the buffer name routes split panes.
def pend_buf_of(+p: Cl.PendSend) -> String:
  match p:
    case Cl.PendSend{+buf, _, _, _, _, _, _, _, _}: buf

def pend_line(+p: Cl.PendSend) -> Cl.Line:
  match p:
    case Cl.PendSend{_, _, _, _, _, +disp, +ts, +kind, _}: Cl.Line{Cl.Pending{kind}, ts, disp, "", 0n}

def pending_for_buf.rest(hit: Bool, +h: Cl.PendSend, +rec: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match hit:
    case True{}: pend_line(h) <> rec
    case False{}: rec

def pending_for_buf.go(fuel: Nat, pends: List<&2, Cl.PendSend>, +name: String) -> List<&2, Cl.Line>:
  match fuel:
    case 0n: Nil{}
    case 1n+f:
      match pends:
        case Nil{}: Nil{}
        case Con{+h, t}: pending_for_buf.rest(String.eq(pend_buf_of(h), name), h, pending_for_buf.go(f, t, name))

def pending_for_buf(+pends: List<&2, Cl.PendSend>, +name: String) -> List<&2, Cl.Line>:
  pending_for_buf.go(List.length(&2, Cl.PendSend, pends), pends, name)

def pending_display_lines.on(empty: Bool, +name: String, +pends: List<&2, Cl.PendSend>, +lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match empty:
    case True{}: lines
    case False{}: List.append(&2, Cl.Line, lines, pending_for_buf(pends, name))

def pending_display_lines(+name: String, +pends: List<&2, Cl.PendSend>, +lines: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  pending_display_lines.on(List.is_empty(&2, Cl.PendSend, pends), name, pends, lines)

# Render filtering: mutes first, then the retroactive joins/nicks kind
# filter. Paint, scroll, navigation, and card/media admission all read
# through here, so hidden rows vanish everywhere at once.
def body_of.lines(lines: List<&2, Cl.Line>, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +chan: String, +server: String) -> List<&2, Cl.Line>:
  match mutes:
    case Nil{}: Cl.filter_kinds(lines, joins, nicks)
    case Con{_, _}: Cl.filter_kinds(Cl.filter_muted_lines(lines, mutes, chan, server), joins, nicks)

# Negotiated render filtering (I2-dynamic2 F4): mute checks fold under the
# Session CASEMAPPING supplied by the painter (Net/Session hold the iso).
def body_of.lines_iso(+isc: Cl.Iso, lines: List<&2, Cl.Line>, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +chan: String, +server: String) -> List<&2, Cl.Line>:
  match mutes:
    case Nil{}: Cl.filter_kinds(lines, joins, nicks)
    case Con{_, _}: Cl.filter_kinds(Cl.filter_muted_lines_iso(isc, lines, mutes, chan, server), joins, nicks)

def body_of.lines_cm(+cm: String, lines: List<&2, Cl.Line>, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +chan: String, +server: String) -> List<&2, Cl.Line>:
  body_of.lines_iso(paint_iso_cm(cm), lines, mutes, joins, nicks, chan, server)

type AnchoredRow is Data:
  AnchoredRow{body: BodyRow, anchor: Cl.Scroll, line: Cl.Line}

def row_chars(row: BodyRow) -> Nat:
  match row:
    case BodyRow{_, _, _, _, _, _, source_chars}: source_chars
    case BodyRecon{_, _}: 0n
    case BodyMedia{_, _, _, _}: 1n

def day_bar_row(row: BodyRow) -> Bool:
  match row:
    case BodyRecon{+text, _}: String.starts_with(text, "@")
    case _: False{}

# Day bars and reconnect dividers are BodyRecon with zero source characters.
def recon_row(row: BodyRow) -> Bool:
  match row:
    case BodyRecon{_, _}: True{}
    case _: False{}

def rows_chars(rows: List<&2, BodyRow>) -> Nat:
  match rows:
    case Nil{}: 0n
    case Con{h, t}: Nat.add(row_chars(h), rows_chars(t))

# Text/source characters only — BodyMedia rows are virtual and must not inflate
# BodyRecon ScrollAt.tail (day bars / reconnect stay at text_chars+1).
def row_text_chars(row: BodyRow) -> Nat:
  match row:
    case BodyRow{_, _, _, _, _, _, source_chars}: source_chars
    case _: 0n

def rows_text_chars(rows: List<&2, BodyRow>) -> Nat:
  match rows:
    case Nil{}: 0n
    case Con{h, t}: Nat.add(row_text_chars(h), rows_text_chars(t))

# ScrollAt.tail is text/source only. BodyMedia is virtual (0 text chars) so it
# neither consumes the budget nor collides with BodyRecon's text_chars+1, and a
# PageUp anchor taken without media still matches the same text row after
# placeholders expand. BodyRecon keeps text_chars+1 without consuming.
def anchored_rows.step(is_recon: Bool, +h: BodyRow, +after: Nat, +text_chars: Nat, +line: Cl.Line, k: Nat -> List<&2, AnchoredRow>) -> List<&2, AnchoredRow>:
  match is_recon:
    case True{}: AnchoredRow{h, Cl.ScrollAt{after, Nat.add(text_chars, 1n)}, line} <> k(text_chars)
    case False{}:
      +tail = Nat.sub(text_chars, row_text_chars(h))
      AnchoredRow{h, Cl.ScrollAt{after, tail}, line} <> k(tail)

def anchored_rows(rows: List<&2, BodyRow>, +after: Nat, +text_chars: Nat, +line: Cl.Line) -> List<&2, AnchoredRow>:
  match rows:
    case Nil{}: Nil{}
    case Con{+h, t}:
      anchored_rows.step(recon_row(h), h, after, text_chars, line, next => anchored_rows(t, after, next, line))

def anchored_line(+rows: List<&2, BodyRow>, +after: Nat, +line: Cl.Line) -> List<&2, AnchoredRow>:
  anchored_rows(rows, after, rows_text_chars(rows), line)

def paint_filter_iso(iso: Maybe<&2, Cl.Iso>, lines: List<&2, Cl.Line>, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +chan: String, +server: String) -> List<&2, Cl.Line>:
  match iso:
    case None{}: body_of.lines(lines, mutes, joins, nicks, chan, server)
    case Some{+isc}: body_of.lines_iso(isc, lines, mutes, joins, nicks, chan, server)

def paint_filter(+boxed: List<&2, PaintOpts>, lines: List<&2, Cl.Line>, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +chan: String, +server: String) -> List<&2, Cl.Line>:
  paint_filter_iso(opt_iso(boxed), lines, mutes, joins, nicks, chan, server)

def paint_display_lines(+name: String, +topic: String, +lines: List<&2, Cl.Line>, +boxed: List<&2, PaintOpts>) -> List<&2, Cl.Line>:
  pending_display_lines(name, opt_pends(boxed), media_display_lines(name, topic, lines, opt_media(boxed)))

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
    case Con{AnchoredRow{_, anchor, _}, t}:
      anchor_end.on(anchor_reached(anchor, want), 1n+i, n => anchor_end(t, want, n))

# BodyMedia is virtual: top-pin must count source rows (text/day/reconnect) so
# image expansion pushes older content up instead of drifting the bottom source.
def anchored_source(row: AnchoredRow) -> Bool:
  match row:
    case AnchoredRow{BodyMedia{_, _, _, _}, _, _}: False{}
    case _: True{}

def media_run_end.keep(source: Bool, +t: List<&2, AnchoredRow>, +i: Nat, k: Unit -> Nat) -> Nat:
  match source:
    case True{}: i
    case False{}: k(Unit{})

def media_run_end(rows: List<&2, AnchoredRow>, +i: Nat) -> Nat:
  match rows:
    case Nil{}: i
    case Con{+h, +t}:
      media_run_end.keep(anchored_source(h), t, i, done => media_run_end(t, 1n+i))

# +t is copyable so step may pass it and the continue lambda may capture it.
def nth_source_end.hit(at_n: Bool, +t: List<&2, AnchoredRow>, +i: Nat, k: Unit -> Nat) -> Nat:
  match at_n:
    case True{}: media_run_end(t, i)
    case False{}: k(Unit{})

def nth_source_end.step(is_src: Bool, +t: List<&2, AnchoredRow>, +n: Nat, +i: Nat, +seen: Nat, k: Nat -> Nat) -> Nat:
  match is_src:
    case False{}: k(seen)
    case True{}: nth_source_end.hit(Nat.is_eq(1n+seen, n), t, i, done => k(1n+seen))

def nth_source_end(fuel: Nat, rows: List<&2, AnchoredRow>, +n: Nat, +i: Nat, +seen: Nat) -> Nat:
  match fuel:
    case 0n: i
    case 1n+p:
      match rows:
        case Nil{}: i
        case Con{+h, +t}:
          nth_source_end.step(anchored_source(h), t, n, 1n+i, seen,
            ns => nth_source_end(p, t, n, 1n+i, ns))

# Top-pin (anchor within the first `height` rows) would otherwise take a fixed
# row budget from the oldest edge; BodyMedia then steals slots and the bottom
# source line drifts. Keep the height-th source line as the bottom instead.
# Mid-history top-pin (older rows above ScrollAt): keep the height-th source
# as the bottom so BodyMedia pushes content up. At-oldest top-pin: fill from
# the top with a row budget so the oldest source (and its URL) stays visible.
def head_after(rows: List<&2, AnchoredRow>) -> Nat:
  match rows:
    case Nil{}: 0n
    case Con{AnchoredRow{_, Cl.ScrollAt{+after, _}, _}, _}: after

def viewport_end.top.on(above: Bool, +rows: List<&2, AnchoredRow>, +height: Nat, +count: Nat) -> Nat:
  match above:
    case True{}: nth_source_end(count, rows, height, 0n, 0n)
    case False{}: height

def viewport_end.top(top: Bool, +rows: List<&2, AnchoredRow>, +height: Nat, +count: Nat, +clamped: Nat, +after: Nat) -> Nat:
  match top:
    case False{}: clamped
    case True{}: viewport_end.top.on(Nat.is_gt(head_after(rows), after), rows, height, count)

def viewport_end(+rows: List<&2, AnchoredRow>, +height: Nat, want: Cl.Scroll) -> Nat:
  match want:
    case Cl.ScrollAt{+after, +tail}:
      +count = List.length(&2, AnchoredRow, rows)
      +raw = Bool.pick(Nat, Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), count, anchor_end(rows, Cl.ScrollAt{after, tail}, 0n))
      +clamped = Nat.sub(count, clamp_scroll(Nat.sub(count, raw), count, height))
      viewport_end.top(Nat.is_le(raw, height) && Nat.is_ge(count, height), rows, height, count, clamped, after)

def anchored_bodies(rows: List<&2, AnchoredRow>) -> List<&2, BodyRow>:
  match rows:
    case Nil{}: Nil{}
    case Con{AnchoredRow{body, _, _}, t}: body <> anchored_bodies(t)

def visible_anchored(+rows: List<&2, AnchoredRow>, +height: Nat, want: Cl.Scroll) -> List<&2, BodyRow>:
  +end = viewport_end(rows, height, want)
  +start = Nat.sub(end, Nat.min(end, height))
  anchored_bodies(List.take(&2, AnchoredRow, List.drop(&2, AnchoredRow, rows, start), Nat.sub(end, start)))

# Newest-first suffix for the live bottom. raw_lines stays oldest-first.
# SCROLL_CAP + one synthetic preview row + PEND_MAX fits under this fuel;
# a longer list falls back to a full reverse rather than showing the wrong tail.
def rev_tail_fuel() -> Nat:
  2048n

type RevBuild is Data:
  RevOk{rev: List<&2, Cl.Line>, n: Nat}
  RevOver{}

type Newest is Data:
  Newest{lines: List<&2, Cl.Line>, truncated: Bool}

def rev_tail.exhausted(lines: List<&2, Cl.Line>) -> RevBuild:
  match lines:
    case Nil{}: RevOk{Nil{}, 0n}
    case Con{_, _}: RevOver{}

def rev_tail.cons(full: Bool, +rev: List<&2, Cl.Line>, +n: Nat, +h: Cl.Line) -> RevBuild:
  match full:
    case True{}: RevOk{rev, n}
    case False{}: RevOk{List.append(&2, Cl.Line, rev, h <> Nil{}), Nat.add(n, 1n)}

def rev_tail.got(built: RevBuild, +h: Cl.Line, +keep: Nat) -> RevBuild:
  match built:
    case RevOver{}: RevOver{}
    case RevOk{+rev, +n}: rev_tail.cons(Nat.is_ge(n, keep), rev, n, h)

def rev_tail.go(fuel: Nat, lines: List<&2, Cl.Line>, +keep: Nat) -> RevBuild:
  match fuel:
    case 0n: rev_tail.exhausted(lines)
    case 1n+p:
      match lines:
        case Nil{}: RevOk{Nil{}, 0n}
        case Con{+h, t}: rev_tail.got(rev_tail.go(p, t, keep), h, keep)

def newest_of(built: RevBuild, +keep: Nat, +lines: List<&2, Cl.Line>) -> Newest:
  match built:
    case RevOver{}: Newest{List.reverse(&2, Cl.Line, lines), False{}}
    case RevOk{+rev, +n}: Newest{rev, Nat.is_eq(n, keep)}

def newest_lines(+lines: List<&2, Cl.Line>, +keep: Nat) -> Newest:
  newest_of(rev_tail.go(rev_tail_fuel(), lines, keep), keep, lines)

# truncated means the suffix stopped at `keep` and older lines may exist.
# A short row list then has to walk the real history. Exactly `keep` lines
# in the whole buffer also looks truncated; the retry repeats the same rows.
def bottom_short(truncated: Bool, +rows: List<&2, BodyRow>, +height: Nat) -> Bool:
  match truncated:
    case False{}: False{}
    case True{}: Nat.is_lt(List.length(&2, BodyRow, rows), height)

# Day dividers are view-only: history keeps dated Line stamps, paint inserts
# a reconnect-style bar when the local calendar day changes.
def line_ts(+ln: Cl.Line) -> String:
  match ln:
    case Cl.Line{_, +ts, _, _, _}: ts

def line_day(+ln: Cl.Line) -> String:
  Cl.now_day(line_ts(ln))

def day_or_prev(empty: Bool, +day: String, +prev: String) -> String:
  match empty:
    case True{}: prev
    case False{}: day

def visible_day_step(hidden: Bool, +day: String, +prev_day: String) -> String:
  match hidden:
    case True{}: prev_day
    case False{}: day_or_prev(String.is_empty(day), day, prev_day)

# One oldest-first pass tags each line with its previous visible calendar day
# and cached paint filter so newest-first paint does not rescan the suffix.
type DayTag is Data:
  DayTag{line: Cl.Line, prev_day: String, filtered: List<&2, Cl.Line>}

# At least one visible line so an up=0 / empty budget still tags the anchor.
def day_tag_need(+need: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(need, 0n), 1n, need)

# Nearest visible dated day scanning newest-first (older neighbors of a line).
def older_day.dated(empty: Bool, +day: String, k: Unit -> String) -> String:
  match empty:
    case True{}: k(Unit{})
    case False{}: day

def older_day.pick(hidden: Bool, +day: String, k: Unit -> String) -> String:
  match hidden:
    case True{}: k(Unit{})
    case False{}: older_day.dated(String.is_empty(day), day, k)

def older_day.tags(tags: List<&2, DayTag>) -> String:
  match tags:
    case Nil{}: ""
    case Con{DayTag{+line, _, +filtered}, +t}:
      older_day.pick(List.is_empty(&2, Cl.Line, filtered), line_day(line), done => older_day.tags(t))

def older_day.scan.go(
  fuel: Nat,
  lines: List<&2, Cl.Line>,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +name: String,
  +server: String,
  +boxed: List<&2, PaintOpts>
) -> String:
  match fuel:
    case 0n: ""
    case 1n+p:
      match lines:
        case Nil{}: ""
        case Con{+h, +t}:
          +filtered = paint_filter(boxed, h <> Nil{}, mutes, joins, nicks, name, server)
          older_day.pick(List.is_empty(&2, Cl.Line, filtered), line_day(h),
            done => older_day.scan.go(p, t, mutes, joins, nicks, name, server, boxed))

def older_day.scan(
  lines: List<&2, Cl.Line>,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +name: String,
  +server: String,
  +boxed: List<&2, PaintOpts>
) -> String:
  older_day.scan.go(rev_tail_fuel(), lines, mutes, joins, nicks, name, server, boxed)

# Hidden lines do not consume `left`; stop once `left` visible lines are taken.
def day_tag.left(hidden: Bool, +left: Nat) -> Nat:
  match hidden:
    case True{}: left
    case False{}: Nat.sub(left, Nat.min(left, 1n))

def day_tag.cover.stop(done: Bool, +h: Cl.Line, +acc: List<&2, Cl.Line>, k: Unit -> List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match done:
    case True{}: h <> acc
    case False{}: k(Unit{})

# Newest-first walk; cons yields oldest-first among taken (reverse before tag).
def day_tag.cover.go(
  fuel: Nat,
  lines: List<&2, Cl.Line>,
  +left: Nat,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +name: String,
  +server: String,
  +boxed: List<&2, PaintOpts>,
  +acc: List<&2, Cl.Line>
) -> List<&2, Cl.Line>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match lines:
        case Nil{}: acc
        case Con{+h, +t}:
          +filtered = paint_filter(boxed, h <> Nil{}, mutes, joins, nicks, name, server)
          +hidden = List.is_empty(&2, Cl.Line, filtered)
          +next = day_tag.left(hidden, left)
          day_tag.cover.stop(Bool.and(Bool.not(hidden), Nat.is_eq(next, 0n)), h, acc,
            done => day_tag.cover.go(p, t, next, mutes, joins, nicks, name, server, boxed, h <> acc))

def day_tag.cover(
  +lines_newest: List<&2, Cl.Line>,
  +need: Nat,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +name: String,
  +server: String,
  +boxed: List<&2, PaintOpts>
) -> List<&2, Cl.Line>:
  List.reverse(&2, Cl.Line, day_tag.cover.go(rev_tail_fuel(), lines_newest, day_tag_need(need), mutes, joins, nicks, name, server, boxed, Nil{}))

def day_tag.go(
  fuel: Nat,
  lines: List<&2, Cl.Line>,
  +prev_day: String,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +name: String,
  +server: String,
  +boxed: List<&2, PaintOpts>,
  +acc: List<&2, DayTag>
) -> List<&2, DayTag>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match lines:
        case Nil{}: acc
        case Con{+h, +t}:
          +filtered = paint_filter(boxed, h <> Nil{}, mutes, joins, nicks, name, server)
          +hidden = List.is_empty(&2, Cl.Line, filtered)
          # Cons while walking oldest-first yields newest-first without a second reverse.
          day_tag.go(p, t, visible_day_step(hidden, line_day(h), prev_day), mutes, joins, nicks, name, server, boxed,
            DayTag{h, prev_day, filtered} <> acc)

# Cover `need` visible newest-first lines (hidden runs free); seed from older rest.
def day_tag(
  +lines_newest: List<&2, Cl.Line>,
  +need: Nat,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +name: String,
  +server: String,
  +boxed: List<&2, PaintOpts>
) -> List<&2, DayTag>:
  +slice = day_tag.cover(lines_newest, need, mutes, joins, nicks, name, server, boxed)
  +seed = older_day.scan(List.drop(&2, Cl.Line, lines_newest, List.length(&2, Cl.Line, slice)), mutes, joins, nicks, name, server, boxed)
  day_tag.go(rev_tail_fuel(), List.reverse(&2, Cl.Line, slice), seed, mutes, joins, nicks, name, server, boxed, Nil{})

def day_rows.on(skip: Bool, +day: String, +w: U32) -> List<&2, BodyRow>:
  match skip:
    case True{}: Nil{}
    case False{}: BodyRecon{bar_text(True{}, day), w} <> Nil{}

def day_rows(+prev: String, +ts: String, +w: U32) -> List<&2, BodyRow>:
  +day = Cl.now_day(ts)
  day_rows.on(String.is_empty(day) || String.eq(day, prev), day, w)

def day_rows_visible(hidden: Bool, +prev: String, +ts: String, +w: U32) -> List<&2, BodyRow>:
  match hidden:
    case True{}: Nil{}
    case False{}: day_rows(prev, ts, w)

def paint_anchored.next_prev(hidden: Bool, +day: String, +prev_day: String) -> String:
  visible_day_step(hidden, day, prev_day)

# Oldest-first anchored paint threads the previous visible calendar day so
# scrolled windows get the same day bars as the live bottom.
def paint_anchored.go(
  lines: List<&2, Cl.Line>,
  +prev_day: String,
  +name: String,
  +w: U32,
  +show_ts: Bool,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +server: String,
  +left: Nat,
  +boxed: List<&2, PaintOpts>
) -> List<&2, AnchoredRow>:
  match lines:
    case Nil{}: Nil{}
    case Con{+h, t}:
      +after = Nat.sub(left, 1n)
      +filtered = paint_filter(boxed, h <> Nil{}, mutes, joins, nicks, name, server)
      +hidden = List.is_empty(&2, Cl.Line, filtered)
      +chat = paint_body_rows(filtered, name, w, show_ts, boxed)
      +body = List.append(&2, BodyRow, day_rows_visible(hidden, prev_day, line_ts(h), w), chat)
      List.append(&2, AnchoredRow, anchored_line(body, after, h),
        paint_anchored.go(t, paint_anchored.next_prev(hidden, line_day(h), prev_day), name, w, show_ts, mutes, joins, nicks, server, after, boxed))

def paint_anchored(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +boxed: List<&2, PaintOpts>) -> List<&2, AnchoredRow>:
  paint_anchored.go(lines, "", name, w, show_ts, mutes, joins, nicks, server, left, boxed)

def anchored_lines_media(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State) -> List<&2, AnchoredRow>:
  paint_anchored(lines, name, w, show_ts, mutes, joins, nicks, server, left, paint_media_only(media))

def anchored_lines_media_cards(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  paint_anchored(lines, name, w, show_ts, mutes, joins, nicks, server, left, paint_media_cards(media, cards))

def anchored_lines_media_cards_cm(+cm: String, lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +left: Nat, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  paint_anchored(lines, name, w, show_ts, mutes, joins, nicks, server, left, paint_media_cards_cm(cm, media, cards))

# At the live bottom, stop after enough expanded rows, not logical messages:
# muted/empty media lines can add no rows, while wrapped lines and images add many.
def paint_recent_more(state: Nat & List<&2, BodyRow>, +line: Cl.Line, +prev_day: String, +filtered: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +boxed: List<&2, PaintOpts>, k: (Nat & List<&2, BodyRow>) -> List<&2, BodyRow>) -> List<&2, BodyRow>:
  match state:
    case (0n, acc): acc
    case (1n+p, +acc):
      +left : Nat = 1n+p
      +hidden = List.is_empty(&2, Cl.Line, filtered)
      +chat = paint_body_rows(filtered, name, w, show_ts, boxed)
      +rows = List.append(&2, BodyRow, day_rows_visible(hidden, prev_day, line_ts(line), w), chat)
      +count = List.length(&2, BodyRow, rows)
      +keep = Nat.min(left, count)
      k((Nat.sub(left, keep), List.append(&2, BodyRow, List.drop(&2, BodyRow, rows, Nat.sub(count, keep)), acc)))

def paint_recent_tagged(
  tags: List<&2, DayTag>,
  +name: String,
  +w: U32,
  +show_ts: Bool,
  +boxed: List<&2, PaintOpts>,
  state: Nat & List<&2, BodyRow>
) -> List<&2, BodyRow>:
  match tags:
    case Nil{}: Pair.snd(Nat, List<&2, BodyRow>, state)
    case Con{DayTag{+h, +prev, +filtered}, +t}:
      paint_recent_more(state, h, prev, filtered, name, w, show_ts, boxed,
        next => paint_recent_tagged(t, name, w, show_ts, boxed, next))

def paint_recent_go(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>, +height: Nat, +acc: List<&2, BodyRow>) -> List<&2, BodyRow>:
  paint_recent_tagged(day_tag(lines, height, mutes, joins, nicks, name, server, boxed), name, w, show_ts, boxed, (height, acc))

def paint_bottom_rest(need: Bool, +rows: List<&2, BodyRow>, +lines: List<&2, Cl.Line>, +name: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match need:
    case False{}: rows
    case True{}: paint_recent_go(List.reverse(&2, Cl.Line, lines), name, w, show_ts, mutes, joins, nicks, server, boxed, height, Nil{})

def paint_bottom_use(got: Newest, +lines: List<&2, Cl.Line>, +name: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match got:
    case Newest{+rev, +truncated}:
      +rows = paint_recent_go(rev, name, w, show_ts, mutes, joins, nicks, server, boxed, height, Nil{})
      paint_bottom_rest(bottom_short(truncated, rows, height), rows, lines, name, height, w, show_ts, mutes, joins, nicks, server, boxed)

# Only *preview* leaves the live scroll spine. Local pending sends stay on
# the history newest walk and overlay at the live bottom via paint_bottom.edge.
def spine_live(+name: String, +boxed: List<&2, PaintOpts>) -> Bool:
  Bool.not(String.eq(name, "*preview*"))

def spine_live_pends(+name: String, +pends: List<&2, Cl.PendSend>) -> Bool:
  Bool.not(String.eq(name, "*preview*"))

def paint_source(live: Bool, +name: String, +topic: String, +raw: List<&2, Cl.Line>, +boxed: List<&2, PaintOpts>) -> List<&2, Cl.Line>:
  match live:
    case True{}: raw
    case False{}: paint_display_lines(name, topic, raw, boxed)

type Step is Data:
  Step{after: Nat, budget: Nat, on_anchor: Bool}

def window_stop(on_anchor: Bool, +budget: Nat) -> Bool:
  match on_anchor:
    case True{}: False{}
    case False{}: Nat.is_eq(budget, 0n)

def window_next_budget(on_anchor: Bool, +budget: Nat, +n: Nat, +height: Nat) -> Nat:
  match on_anchor:
    case True{}: height
    case False{}: Nat.sub(budget, Nat.min(budget, n))

# Newest-first tagged lines, oldest-first anchored rows. The anchor line is
# always wrapped. Older lines stop once `height` extra rows exist.
def window_body(
  stop: Bool,
  +h: Cl.Line,
  +prev_day: String,
  +filtered: List<&2, Cl.Line>,
  +after: Nat,
  +budget: Nat,
  +on_anchor: Bool,
  +height: Nat,
  +name: String,
  +w: U32,
  +show_ts: Bool,
  +boxed: List<&2, PaintOpts>,
  k: Step -> List<&2, AnchoredRow>
) -> List<&2, AnchoredRow>:
  match stop:
    case True{}: Nil{}
    case False{}:
      +hidden = List.is_empty(&2, Cl.Line, filtered)
      +chat = paint_body_rows(filtered, name, w, show_ts, boxed)
      +body = List.append(&2, BodyRow, day_rows_visible(hidden, prev_day, line_ts(h), w), chat)
      +older = k(Step{Nat.add(after, 1n), window_next_budget(on_anchor, budget, List.length(&2, BodyRow, body), height), False{}})
      List.append(&2, AnchoredRow, older, anchored_line(body, after, h))

def window_with(
  step: Step,
  +h: Cl.Line,
  +prev_day: String,
  +filtered: List<&2, Cl.Line>,
  +height: Nat,
  +name: String,
  +w: U32,
  +show_ts: Bool,
  +boxed: List<&2, PaintOpts>,
  k: Step -> List<&2, AnchoredRow>
) -> List<&2, AnchoredRow>:
  match step:
    case Step{+after, +budget, +on_anchor}:
      window_body(window_stop(on_anchor, budget), h, prev_day, filtered, after, budget, on_anchor, height, name, w, show_ts, boxed, k)

def window_tagged(
  fuel: Nat,
  tags: List<&2, DayTag>,
  step: Step,
  +height: Nat,
  +name: String,
  +w: U32,
  +show_ts: Bool,
  +boxed: List<&2, PaintOpts>
) -> List<&2, AnchoredRow>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match tags:
        case Nil{}: Nil{}
        case Con{DayTag{+h, +prev, +filtered}, +t}:
          window_with(step, h, prev, filtered, height, name, w, show_ts, boxed,
            next => window_tagged(p, t, next, height, name, w, show_ts, boxed))

def take_emit(zero: Bool, +h: Cl.Line, k: Unit -> List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match zero:
    case True{}: Nil{}
    case False{}: h <> k(Unit{})

def take_new(fuel: Nat, lines: List<&2, Cl.Line>, +n: Nat) -> List<&2, Cl.Line>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match lines:
        case Nil{}: Nil{}
        case Con{+h, t}:
          take_emit(Nat.is_eq(n, 0n), h, done => take_new(p, t, Nat.sub(n, 1n)))

def rev_new(lines: List<&2, Cl.Line>, +acc: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match lines:
    case Nil{}: acc
    case Con{+h, t}: rev_new(t, h <> acc)

type Next is Data:
  Next{after: Nat, budget: Nat, prev_day: String}

# Newer walk result: painted rows, whether the walk reached logical after=0
# (even when that newest line emitted no rows), and how many newer lines were
# visited. `visited` lets PageDown advance past a filtered run longer than the
# copy cap when no visible row moved the anchor.
type NewerWalk is Data:
  NewerWalk{rows: List<&2, AnchoredRow>, reached_newest: Bool, visited: Nat}

def newer_rows(walk: NewerWalk) -> List<&2, AnchoredRow>:
  match walk:
    case NewerWalk{+rows, _, _}: rows

def newer_from.join(walk: NewerWalk, +head: List<&2, AnchoredRow>, +n: Nat) -> NewerWalk:
  match walk:
    case NewerWalk{+more, +reached, +v}:
      NewerWalk{List.append(&2, AnchoredRow, head, more), reached, Nat.add(n, v)}

# Stop at the newest logical line once visited; otherwise continue for more rows.
def newer_from.rest(at_newest: Bool, +head: List<&2, AnchoredRow>, +next: Next, k: Next -> NewerWalk) -> NewerWalk:
  match at_newest:
    case True{}: NewerWalk{head, True{}, 1n}
    case False{}: newer_from.join(k(next), head, 1n)

# `lines` is oldest-first, starting at the line just newer than the anchor.
# Stop after `height` rows or once the newest logical line is visited.
def newer_from(
  stop: Bool,
  +h: Cl.Line,
  +prev_day: String,
  +after: Nat,
  +budget: Nat,
  +name: String,
  +w: U32,
  +show_ts: Bool,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +server: String,
  +boxed: List<&2, PaintOpts>,
  k: Next -> NewerWalk
) -> NewerWalk:
  match stop:
    case True{}: NewerWalk{Nil{}, False{}, 0n}
    case False{}:
      +filtered = paint_filter(boxed, h <> Nil{}, mutes, joins, nicks, name, server)
      +hidden = List.is_empty(&2, Cl.Line, filtered)
      +chat = paint_body_rows(filtered, name, w, show_ts, boxed)
      +body = List.append(&2, BodyRow, day_rows_visible(hidden, prev_day, line_ts(h), w), chat)
      +n = List.length(&2, BodyRow, body)
      newer_from.rest(Nat.is_eq(after, 0n), anchored_line(body, after, h),
        Next{Nat.sub(after, 1n), Nat.sub(budget, Nat.min(budget, n)), paint_anchored.next_prev(hidden, line_day(h), prev_day)}, k)

def newer_open(
  step: Next,
  +h: Cl.Line,
  +name: String,
  +w: U32,
  +show_ts: Bool,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +server: String,
  +boxed: List<&2, PaintOpts>,
  k: Next -> NewerWalk
) -> NewerWalk:
  match step:
    case Next{+after, +budget, +prev_day}:
      newer_from(Nat.is_eq(budget, 0n), h, prev_day, after, budget, name, w, show_ts, mutes, joins, nicks, server, boxed, k)

def newer_go(
  fuel: Nat,
  lines: List<&2, Cl.Line>,
  step: Next,
  +name: String,
  +w: U32,
  +show_ts: Bool,
  +mutes: List<&2, String>,
  +joins: Bool,
  +nicks: Bool,
  +server: String,
  +boxed: List<&2, PaintOpts>,
  tail: Bool
) -> NewerWalk:
  match fuel:
    case 0n: NewerWalk{Nil{}, False{}, 0n}
    case 1n+p:
      match lines:
        case Nil{}: NewerWalk{Nil{}, tail, 0n}
        case Con{+h, t}:
          newer_open(step, h, name, w, show_ts, mutes, joins, nicks, server, boxed,
            next => newer_go(p, t, next, name, w, show_ts, mutes, joins, nicks, server, boxed, tail))

# Drop the newer prefix in place, then reverse the span the walk may visit.
# Callers pass a line budget for paint windows; scroll passes `after` so the
# walk can skip long hidden runs until `dn` rows or the newest line.
def newer_start(wide: Bool, +after: Nat, +take: Nat) -> Nat:
  match wide:
    case True{}: Nat.sub(after, take)
    case False{}: 0n

def newer_lines(+newest: List<&2, Cl.Line>, +after: Nat, +budget: Nat) -> List<&2, Cl.Line>:
  +take = Nat.min(after, budget)
  +start = newer_start(Nat.is_gt(after, take), after, take)
  rev_new(take_new(rev_tail_fuel(), List.drop(&2, Cl.Line, newest, start), Nat.sub(after, start)), Nil{})

def newer_after(zero: Bool, +after: Nat) -> Nat:
  match zero:
    case True{}: 0n
    case False{}: Nat.sub(after, 1n)

def window_join(has_newer: Bool, +older: List<&2, AnchoredRow>, +newest: List<&2, Cl.Line>, +after: Nat, +height: Nat, +prev_day: String, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, AnchoredRow>:
  match has_newer:
    case False{}: older
    case True{}:
      List.append(&2, AnchoredRow, older,
        newer_rows(newer_go(rev_tail_fuel(), newer_lines(newest, after, height), Next{newer_after(Nat.is_eq(after, 0n), after), height, prev_day}, name, w, show_ts, mutes, joins, nicks, server, boxed, Nat.is_ge(height, after))))

def window_after(past: Bool, +after: Nat, +count: Nat) -> Nat:
  match past:
    case True{}: Nat.sub(count, 1n)
    case False{}: after

# One bounded day_tag pass serves both the older window and the newer-walk day seed.
def window_anchored(+newest: List<&2, Cl.Line>, +after: Nat, +count: Nat, +height: Nat, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, AnchoredRow>:
  +at = window_after(Bool.and(Nat.is_gt(count, 0n), Nat.is_ge(after, count)), after, count)
  +tags = day_tag(List.drop(&2, Cl.Line, newest, at), height, mutes, joins, nicks, name, server, boxed)
  window_join(Nat.is_gt(at, 0n),
    window_tagged(rev_tail_fuel(), tags, Step{at, height, True{}}, height, name, w, show_ts, boxed),
    newest, at, height, older_day.tags(tags), name, w, show_ts, mutes, joins, nicks, server, boxed)

# One ScrollAt window under media+cards paint. Admission and nav consumers
# share this instead of each re-entering window_anchored.
def window_media_cards_cm(+cm: String, +newest: List<&2, Cl.Line>, +after: Nat, +count: Nat, +height: Nat, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  window_anchored(newest, after, count, height, name, w, show_ts, mutes, joins, nicks, server, paint_media_cards_cm(cm, media, cards))

def window_media_cards_iso(+isc: Cl.Iso, +newest: List<&2, Cl.Line>, +after: Nat, +count: Nat, +height: Nat, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  window_anchored(newest, after, count, height, name, w, show_ts, mutes, joins, nicks, server, paint_media_cards_iso(isc, media, cards))

def window_buf_media_cards_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match b:
    case Cl.Buffer{+name, _, _, _, _, Cl.ScrollAt{+after, _}, +newest, +count}:
      window_media_cards_cm(cm, newest, after, count, height, name, w, show_ts, mutes, joins, nicks, server, media, cards)

def window_buf_media_cards_iso(+isc: Cl.Iso, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match b:
    case Cl.Buffer{+name, _, _, _, _, Cl.ScrollAt{+after, _}, +newest, +count}:
      window_media_cards_iso(isc, newest, after, count, height, name, w, show_ts, mutes, joins, nicks, server, media, cards)

# Viewport slice of an anchored window (AnchoredRow units; preserves ScrollAt).
def visible_anchored_crop(+rows: List<&2, AnchoredRow>, +height: Nat, scroll: Cl.Scroll) -> List<&2, AnchoredRow>:
  +end = viewport_end(rows, height, scroll)
  +start = Nat.sub(end, Nat.min(end, height))
  List.take(&2, AnchoredRow, List.drop(&2, AnchoredRow, rows, start), Nat.sub(end, start))

def visible_anchored_buf_media_cards_cm.allowed(+cm: String, allowed: Bool, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match allowed:
    case False{}: Nil{}
    case True{}:
      match b:
        case Cl.Buffer{_, _, _, _, _, +scroll, _, _}:
          visible_anchored_crop(window_buf_media_cards_cm(cm, b, height, w, show_ts, mutes, joins, nicks, server, media, cards), height, scroll)

def visible_anchored_buf_media_cards_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match b:
    case Cl.Buffer{name, _, _, _, _, _, _, _}:
      visible_anchored_buf_media_cards_cm.allowed(cm, Bool.not(Cl.target_is_synthetic(name)) && Nat.is_gt(height, 0n) && Bool.not(U32.is_zero(w)),
        b, height, w, show_ts, mutes, joins, nicks, server, media, cards)

def visible_anchored_buf_media_cards_iso.allowed(+isc: Cl.Iso, allowed: Bool, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match allowed:
    case False{}: Nil{}
    case True{}:
      match b:
        case Cl.Buffer{_, _, _, _, _, +scroll, _, _}:
          visible_anchored_crop(window_buf_media_cards_iso(isc, b, height, w, show_ts, mutes, joins, nicks, server, media, cards), height, scroll)

def visible_anchored_buf_media_cards_iso(+isc: Cl.Iso, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match b:
    case Cl.Buffer{name, _, _, _, _, _, _, _}:
      visible_anchored_buf_media_cards_iso.allowed(isc, Bool.not(Cl.target_is_synthetic(name)) && Nat.is_gt(height, 0n) && Bool.not(U32.is_zero(w)),
        b, height, w, show_ts, mutes, joins, nicks, server, media, cards)

def paint_preview_row(show: Bool, +rows: List<&2, BodyRow>, +topic: String, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match show:
    case False{}: rows
    case True{}:
      +extra = paint_body_rows(paint_filter(boxed, Cl.Line{Cl.System{}, "", topic, "", 0n} <> Nil{}, mutes, joins, nicks, name, server), name, w, show_ts, boxed)
      List.append(&2, BodyRow, extra, rows)

def paint_bottom.edge(+newest: List<&2, Cl.Line>, +name: String, +topic: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  +rows = paint_recent_go(List.append(&2, Cl.Line, rev_new(pending_for_buf(opt_pends(boxed), name), Nil{}), newest), name, w, show_ts, mutes, joins, nicks, server, boxed, height, Nil{})
  paint_preview_row(Bool.and(Nat.is_lt(List.length(&2, BodyRow, rows), height), String.eq(name, "*preview*")), rows, topic, name, w, show_ts, mutes, joins, nicks, server, boxed)

# Live and non-live bottoms both overlay local pends via edge; spine_live
# already keeps history ScrollAt off the pending list.
def paint_bottom.live(+newest: List<&2, Cl.Line>, +name: String, +topic: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  paint_bottom.edge(newest, name, topic, height, w, show_ts, mutes, joins, nicks, server, boxed)

def paint_bottom.away(live: Bool, +newest: List<&2, Cl.Line>, +lines: List<&2, Cl.Line>, +name: String, +count: Nat, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>, scroll: Cl.Scroll) -> List<&2, BodyRow>:
  match live:
    case False{}: visible_anchored(paint_anchored(lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), boxed), height, scroll)
    case True{}:
      match scroll:
        case Cl.ScrollAt{+after, _}:
          visible_anchored(window_anchored(newest, after, count, height, name, w, show_ts, mutes, joins, nicks, server, boxed), height, scroll)

def paint_bottom(bottom: Bool, live: Bool, +newest: List<&2, Cl.Line>, +lines: List<&2, Cl.Line>, +name: String, +topic: String, +count: Nat, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>, scroll: Cl.Scroll) -> List<&2, BodyRow>:
  match bottom:
    case True{}: paint_bottom.live(newest, name, topic, height, w, show_ts, mutes, joins, nicks, server, boxed)
    case False{}: paint_bottom.away(live, newest, lines, name, count, height, w, show_ts, mutes, joins, nicks, server, boxed, scroll)

def paint_body_of.scrolled(live: Bool, +newest: List<&2, Cl.Line>, +raw: List<&2, Cl.Line>, +name: String, +topic: String, +count: Nat, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>, scroll: Cl.Scroll) -> List<&2, BodyRow>:
  match live:
    case True{}: paint_bottom.away(True{}, newest, raw, name, count, height, w, show_ts, mutes, joins, nicks, server, boxed, scroll)
    case False{}: paint_bottom.away(False{}, newest, paint_display_lines(name, topic, raw, boxed), name, count, height, w, show_ts, mutes, joins, nicks, server, boxed, scroll)

def paint_body_of.bottom(preview: Bool, +live: Bool, +newest: List<&2, Cl.Line>, +raw: List<&2, Cl.Line>, +name: String, +topic: String, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match preview:
    case True{}:
      +shown = paint_display_lines(name, topic, raw, boxed)
      paint_bottom_use(newest_lines(shown, height), shown, name, height, w, show_ts, mutes, joins, nicks, server, boxed)
    case False{}: paint_bottom.live(newest, name, topic, height, w, show_ts, mutes, joins, nicks, server, boxed)

def paint_body_of.at(bottom: Bool, +live: Bool, +newest: List<&2, Cl.Line>, +raw: List<&2, Cl.Line>, +name: String, +topic: String, +count: Nat, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>, scroll: Cl.Scroll) -> List<&2, BodyRow>:
  match bottom:
    case True{}: paint_body_of.bottom(String.eq(name, "*preview*"), live, newest, raw, name, topic, height, w, show_ts, mutes, joins, nicks, server, boxed)
    case False{}: paint_body_of.scrolled(live, newest, raw, name, topic, count, height, w, show_ts, mutes, joins, nicks, server, boxed, scroll)

def paint_body_of(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> List<&2, BodyRow>:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw_lines, _, Cl.ScrollAt{+after, +tail}, +newest, +count}:
      paint_body_of.at(Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n), spine_live(name, boxed), newest, raw_lines, name, topic, count, height, w, show_ts, mutes, joins, nicks, server, boxed, Cl.ScrollAt{after, tail})

def body_of.buf_media(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State) -> List<&2, BodyRow>:
  paint_body_of(b, height, w, show_ts, mutes, joins, nicks, server, paint_media_only(media))

def body_of.buf(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String) -> List<&2, BodyRow>:
  body_of.buf_media(b, height, w, show_ts, mutes, joins, nicks, server, M.empty())

def row_anchor_at(rows: List<&2, AnchoredRow>, i: Nat) -> Cl.Scroll:
  match rows:
    case Nil{}: Cl.ScrollAt{0n, 0n}
    case Con{AnchoredRow{_, +anchor, _}, t}:
      match i:
        case 0n: anchor
        case 1n+p: row_anchor_at(t, p)

def moved_anchor(+rows: List<&2, AnchoredRow>, +height: Nat, +want: Cl.Scroll, +up: Nat, +dn: Nat) -> Cl.Scroll:
  +count = List.length(&2, AnchoredRow, rows)
  +current = viewport_end(rows, height, want)
  +target = Cl.clamp_nat(Nat.sub(Nat.add(current, dn), up), count)
  +end = Nat.sub(count, clamp_scroll(Nat.sub(count, target), count, height))
  Bool.pick(Cl.Scroll, Nat.is_eq(end, count), Cl.ScrollAt{0n, 0n}, row_anchor_at(rows, Nat.sub(end, 1n)))

def shift_len(bottom: Bool, +count: Nat, +end: Nat) -> Nat:
  match bottom:
    case True{}: count
    case False{}: end

def shift_len_of(+rows: List<&2, AnchoredRow>, want: Cl.Scroll) -> Nat:
  match want:
    case Cl.ScrollAt{+after, +tail}:
      shift_len(Bool.and(Nat.is_eq(after, 0n), Nat.is_eq(tail, 0n)), List.length(&2, AnchoredRow, rows), anchor_end(rows, want, 0n))

def row_after(row: AnchoredRow) -> Nat:
  match row:
    case AnchoredRow{_, Cl.ScrollAt{+after, _}, _}: after

def first_after(rows: List<&2, AnchoredRow>) -> Nat:
  match rows:
    case Nil{}: 0n
    case Con{+h, _}: row_after(h)

def last_after(rows: List<&2, AnchoredRow>) -> Nat:
  match rows:
    case Nil{}: 1n
    case Con{+h, Nil{}}: row_after(h)
    case Con{_, +t}: last_after(t)

def shift_at_top.go(empty: Bool, +rows: List<&2, AnchoredRow>, +count: Nat) -> Bool:
  match empty:
    case True{}: True{}
    case False{}: Nat.is_eq(first_after(rows), Nat.sub(count, 1n))

def shift_at_top(+rows: List<&2, AnchoredRow>, +count: Nat) -> Bool:
  shift_at_top.go(Bool.or(List.is_empty(&2, AnchoredRow, rows), Nat.is_eq(count, 0n)), rows, count)

def shift_at_bottom(+rows: List<&2, AnchoredRow>) -> Bool:
  match rows:
    case Nil{}: True{}
    case Con{_, _}: Nat.is_eq(last_after(rows), 0n)

# Upward move with target==0 (including shift_at_top): stay on the oldest
# painted row. Never snap to live {0,0} or height-1 away from oldest.
def shift_pick.page(+rows: List<&2, AnchoredRow>) -> Cl.Scroll:
  row_anchor_at(rows, 0n)

def shift_pick.zero(zero: Bool, +rows: List<&2, AnchoredRow>, +target: Nat) -> Cl.Scroll:
  match zero:
    case True{}: shift_pick.page(rows)
    case False{}: row_anchor_at(rows, Nat.sub(target, 1n))

def shift_pick(snap: Bool, +rows: List<&2, AnchoredRow>, +target: Nat) -> Cl.Scroll:
  match snap:
    case True{}: Cl.ScrollAt{0n, 0n}
    case False{}: shift_pick.zero(Nat.is_eq(target, 0n), rows, target)

# Move by whole rows inside a window that contains the anchor line, `up`
# older rows, and `dn` newer rows. Snap to the live tail when the newer walk
# reached logical after=0, even if that line painted no rows.
# `height` and `lines_n` remain for call-site shape; top-snap no longer
# branches on short windows or shift_at_top.
def shift_anchor(+rows: List<&2, AnchoredRow>, +height: Nat, want: Cl.Scroll, +up: Nat, +dn: Nat, +lines_n: Nat, +reached_newest: Bool) -> Cl.Scroll:
  +count = List.length(&2, AnchoredRow, rows)
  +index = shift_len_of(rows, want)
  +target = Cl.clamp_nat(Nat.sub(Nat.add(index, dn), up), count)
  shift_pick(Bool.and(reached_newest, Nat.is_eq(target, count)), rows, target)

def shift_anchor_stuck(stuck: Bool, +after: Nat, +visited: Nat, moved: Cl.Scroll) -> Cl.Scroll:
  match stuck:
    case False{}: moved
    case True{}: Cl.ScrollAt{Nat.sub(after, Nat.min(after, visited)), 0n}

def shift_anchor_of.after(+after: Nat, +tail: Nat, +rows: List<&2, AnchoredRow>, +height: Nat, +up: Nat, +dn: Nat, +lines_n: Nat, +reached: Bool, +visited: Nat) -> Cl.Scroll:
  +want: Cl.Scroll = Cl.ScrollAt{after, tail}
  +moved = shift_anchor(rows, height, want, up, dn, lines_n, reached)
  shift_anchor_stuck(
    Nat.is_gt(dn, 0n) && Bool.not(reached) && Nat.is_gt(visited, 0n) && Cl.scroll_eq(moved, want),
    after, visited, moved)

def shift_anchor_of(walk: NewerWalk, +height: Nat, want: Cl.Scroll, +up: Nat, +dn: Nat, +lines_n: Nat) -> Cl.Scroll:
  match walk:
    case NewerWalk{+rows, +reached, +visited}:
      match want:
        case Cl.ScrollAt{+after, +tail}:
          shift_anchor_of.after(after, tail, rows, height, up, dn, lines_n, reached, visited)

def scroll_rows.join(walk: NewerWalk, +older: List<&2, AnchoredRow>) -> NewerWalk:
  match walk:
    case NewerWalk{+newer, +reached, +visited}:
      NewerWalk{List.append(&2, AnchoredRow, older, newer), reached, visited}

# Older `up` rows from the anchor, then newer rows until `dn` visible rows or
# the newest logical line — fuel-bounded, not a hard dn+32 line cap.
# Copy only a page of newer lines, plus a short run of hidden rows. When that
# whole slice paints nothing, shift_anchor_of advances `after` by `visited`.
def scroll_rows(+newest: List<&2, Cl.Line>, +after: Nat, +up: Nat, +dn: Nat, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>) -> NewerWalk:
  +cap = Nat.add(Nat.add(up, dn), 64n)
  # Cover is the anchor line plus `up` older lines (up=0 still tags one line).
  +tags = day_tag(List.drop(&2, Cl.Line, newest, after), Nat.add(up, 1n), mutes, joins, nicks, name, server, boxed)
  scroll_rows.join(
    newer_go(rev_tail_fuel(), newer_lines(newest, after, cap), Next{newer_after(Nat.is_eq(after, 0n), after), dn, older_day.tags(tags)}, name, w, show_ts, mutes, joins, nicks, server, boxed, Nat.is_ge(cap, after)),
    window_tagged(rev_tail_fuel(), tags, Step{after, up, True{}}, up, name, w, show_ts, boxed))

def scroll_shift(+b: Cl.Buffer, +name: String, +newest: List<&2, Cl.Line>, +after: Nat, +count: Nat, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +boxed: List<&2, PaintOpts>, scroll: Cl.Scroll) -> Cl.Buffer:
  Cl.set_buf_anchor(b, shift_anchor_of(scroll_rows(newest, after, up, dn, name, w, show_ts, mutes, joins, nicks, server, boxed), height, scroll, up, dn, count))

def scroll_buf_media.full(+b: Cl.Buffer, +name: String, +topic: String, +raw: List<&2, Cl.Line>, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State, scroll: Cl.Scroll) -> Cl.Buffer:
  +lines = media_display_lines(name, topic, raw, media)
  +rows = anchored_lines_media(lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), media)
  Cl.set_buf_anchor(b, moved_anchor(rows, height, scroll, up, dn))

def scroll_buf_media.go(live: Bool, +b: Cl.Buffer, +name: String, +topic: String, +raw: List<&2, Cl.Line>, +newest: List<&2, Cl.Line>, +count: Nat, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State, scroll: Cl.Scroll) -> Cl.Buffer:
  match live:
    case False{}: scroll_buf_media.full(b, name, topic, raw, height, w, show_ts, mutes, joins, nicks, server, up, dn, media, scroll)
    case True{}:
      match scroll:
        case Cl.ScrollAt{+after, _}:
          scroll_shift(b, name, newest, after, count, height, w, show_ts, mutes, joins, nicks, server, up, dn, paint_media_only(media), scroll)

def scroll_buf_media(+b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Buffer:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw, _, +scroll, +newest, +count}:
      scroll_buf_media.go(spine_live(name, paint_media_only(media)), b, name, topic, raw, newest, count, height, w, show_ts, mutes, joins, nicks, server, up, dn, media, scroll)

def scroll_buf(+b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat) -> Cl.Buffer:
  scroll_buf_media(b, height, w, show_ts, mutes, joins, nicks, server, up, dn, M.empty())

def scroll_buf_media_cards_iso.full(+isc: Cl.Iso, +b: Cl.Buffer, +name: String, +topic: String, +raw: List<&2, Cl.Line>, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>, +pends: List<&2, Cl.PendSend>, scroll: Cl.Scroll) -> Cl.Buffer:
  +lines = pending_display_lines(name, pends, media_display_lines(name, topic, raw, media))
  +rows = paint_anchored(lines, name, w, show_ts, mutes, joins, nicks, server, List.length(&2, Cl.Line, lines), paint_media_cards_iso(isc, media, cards))
  Cl.set_buf_anchor(b, moved_anchor(rows, height, scroll, up, dn))

def scroll_buf_media_cards_iso.go(+isc: Cl.Iso, live: Bool, +b: Cl.Buffer, +name: String, +topic: String, +raw: List<&2, Cl.Line>, +newest: List<&2, Cl.Line>, +count: Nat, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>, +pends: List<&2, Cl.PendSend>, scroll: Cl.Scroll) -> Cl.Buffer:
  match live:
    case False{}: scroll_buf_media_cards_iso.full(isc, b, name, topic, raw, height, w, show_ts, mutes, joins, nicks, server, up, dn, media, cards, pends, scroll)
    case True{}:
      match scroll:
        case Cl.ScrollAt{+after, _}:
          scroll_shift(b, name, newest, after, count, height, w, show_ts, mutes, joins, nicks, server, up, dn, paint_media_cards_iso(isc, media, cards), scroll)

def scroll_buf_media_cards_iso(+isc: Cl.Iso, +b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>, +pends: List<&2, Cl.PendSend>) -> Cl.Buffer:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw, _, +scroll, +newest, +count}:
      +boxed = paint_media_cards_iso(isc, media, cards)
      scroll_buf_media_cards_iso.go(isc, spine_live_pends(name, pends), b, name, topic, raw, newest, count, height, w, show_ts, mutes, joins, nicks, server, up, dn, media, cards, pends, scroll)

def scroll_buf_media_cards_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>, +pends: List<&2, Cl.PendSend>) -> Cl.Buffer:
  scroll_buf_media_cards_iso(paint_iso_cm(cm), b, height, w, show_ts, mutes, joins, nicks, server, up, dn, media, cards, pends)

def body_title_of(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, +topic, _, _, _, _, _}:
      topic

def nicks_title_of(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, _, _, _, _, _, _}:
      name

def nicks_list_of(+b: Cl.Buffer) -> List<&2, String>:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _, _, _}:
      nicks

def status_of.buf(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{_, _, _, _, +nicks, _, _, _}:
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
    case Con{Cl.Buffer{+name, _, _, _, _, _, _, _}, t}:
      tab_lab(name, first, Cl.buf_unread_status(unreads, name)) <> tab_names.go(t, unreads, False{})

# Server buffer keeps the name "server" internally; the tab strip uses
# *server* so a nick or channel named server cannot collide.
def tab_names(bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, String>:
  tab_names.go(bufs, unreads, True{})

def tab_alerts.go(bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>, first: Bool) -> List<&2, U32>:
  match bufs:
    case Nil{}:
      Nil{}
    case Con{Cl.Buffer{+name, _, _, _, _, _, _, _}, t}:
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
    case Con{Cl.Buffer{+name, _, _, _, _, _, _, _}, t}:
      tab_lab(name, first, Cl.buf_unread_status_cm(cm, unreads, name)) <> tab_names.go_cm(cm, t, unreads, False{})

def tab_names_cm(+cm: String, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, String>:
  tab_names.go_cm(cm, bufs, unreads, True{})

def tab_alerts.go_cm(+cm: String, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>, first: Bool) -> List<&2, U32>:
  match bufs:
    case Nil{}:
      Nil{}
    case Con{Cl.Buffer{+name, _, _, _, _, _, _, _}, t}:
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

# Off-screen. The cheat-sheet row is gone; the body box ends on the last
# screen row and the composer is its last inner line.
def status_y(+rows: U32) -> U32:
  rows

# Body last occupied row is y+h-1. The box runs through the last screen row.
# The composer lives on the last inner body row.
# Prefer y=1 (row 0 is tabs bar).
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
  +top = body_top(rows)
  +bh = body_box_h(rows, top)
  Lay{
    Rect{0, 0, tabs_w(cols, uw), 1},
    user_rect(cols, uw),
    Rect{0, top, mid, bh},
    Rect{mid, top, nick_w(cols, mid), bh},
    Rect{0, status_y(rows), cols, 0}
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

# Composer/widget agreement (ONE rule): C always seats exactly one text
# widget (src/ffi/timui_ffi.c chooser: bottom-most, left-most over ALL
# panes, even zero-inner), and Bend always paints the <nick> prefix in
# that same pane, clipped to C's inner geometry (possibly zero bytes).
# Typing stays live at every size; a zero-inner pane shows no prefix
# with the widget at its inner origin. The helpers below mirror the C
# formulas exactly: C inner is (x+1, y+1, w>2 ? w-2 : 0, h>2 ? h-2 : 0),
# the widget row is in.y+in.h-1, and the widget x is in.x+min(cx, in.w).
# (Global inner_w/inner_last keep history layout; only the composer
# mirrors the widget seat. Defined here: last_body_row.box below and
# the oracle use composer_row, and Bend rejects forward references.)
def composer_inner_w.on(+w: U32, gt: Bool) -> U32:
  match gt:
    case True{}:
      U32.sub(w, 2)
    case False{}:
      0

def composer_inner_w(+w: U32) -> U32:
  composer_inner_w.on(w, U32.is_gt(w, 2))

def composer_row.on(+y: U32, +h: U32, gt: Bool) -> U32:
  match gt:
    case True{}:
      U32.sub(U32.add(y, h), 2)
    case False{}:
      y

def composer_row(+y: U32, +h: U32) -> U32:
  composer_row.on(y, h, U32.is_gt(h, 2))

def box_max_y(+y: U32, +h: U32) -> U32:
  U32.sub(U32.add(y, h), 1)

def body_y0.pick(+cand: U32, +min_y: U32, ge: Bool) -> U32:
  match ge:
    case True{}:
      cand
    case False{}:
      min_y

# w4-feed-body-ys: an empty hist rect (1-row body box) leaves inner_last
# underflowing, so cand wraps to U32::MAX and passes the ge clamp. Start
# at the top row instead; history shares the composer row on 1-row terms.
def body_y0.zero(+min_y: U32, +cand: U32, zero: Bool) -> U32:
  match zero:
    case True{}:
      min_y
    case False{}:
      body_y0.pick(cand, min_y, U32.is_ge(cand, min_y))

def body_y0(+y: U32, +h: U32, +n: U32) -> U32:
  +last = inner_last(y, h)
  +min_y = inner_min(y, h)
  +cand = U32.sub(U32.add(last, 1), n)
  body_y0.zero(min_y, cand, U32.is_zero(h))

# Oracle helper (body_ys_case): the row composer_ops paints, i.e. the
# unified C seat. composer_row == inner_last for h >= 3; 2-high boxes
# seat at the box top (empty inner), where history shares the row.
def last_body_row.box(r: Rect) -> U32:
  match r:
    case Rect{_, y, _, h}:
      composer_row(y, h)

def last_body_row.of(lay0: Lay) -> U32:
  match lay0:
    case Lay{_, _, br, _, _}:
      last_body_row.box(br)

def last_body_row(+rows: U32) -> U32:
  last_body_row.of(lay(rows, 80, 0))

# Inline composer: the last inner body row is always reserved, even for an
# empty draft, so history layout never jumps. History paints in the box
# above that row; the <nick> prefix paints at the row with normal nick
# styling, and C draws the text_area widget after it at body_x+compose_x.
def body_hist_h(+h: U32) -> U32:
  Sp.hist_h(h)

def body_hist_rect(r: Rect) -> Rect:
  match r:
    case Rect{+x, +y, +w, +h}:
      Rect{x, y, w, body_hist_h(h)}

def composer_nick(+nick: String) -> String:
  Bool.pick(String, String.is_empty(nick), "*", nick)

def composer_prefix(+nick: String) -> String:
  "<" ++ composer_nick(nick) ++ "> "

# The composer prompt indents by the timestamp column (ts_w + one space)
# so <nick> aligns with message text. Spaces, not a live clock: the clock
# applies at log IO, not every paint. A future timestamp-side switch
# (off/RHS) keys off this same flag.
def composer_shift(show_ts: Bool) -> U32:
  match show_ts:
    case True{}: 9
    case False{}: 0

def composer_indent(show_ts: Bool) -> List<&2, SpanOp>:
  match show_ts:
    case True{}: Spn{0, "         "} <> Nil{}
    case False{}: Nil{}

def composer_x(+nick: String, show_ts: Bool) -> U32:
  U32.add(Cols.text_width(composer_prefix(nick)), composer_shift(show_ts))

def composer_spans(+nick: String, show_ts: Bool) -> List<&2, SpanOp>:
  +shown = composer_nick(nick)
  List.append(&2, SpanOp, composer_indent(show_ts), Spn{0, "<"} <> (Col{1, nick_color(shown), shown} <> (Spn{0, "> "} <> Nil{})))

def composer_ops(r: Rect, +nick: String, show_ts: Bool) -> List<&2, DrawOp>:
  match r:
    case Rect{+x, +y, +w, +h}:
      OpLine{inner_x(x), composer_row(y, h), composer_inner_w(w), FG_TEXT(), composer_spans(nick, show_ts)} <> Nil{}

# Split mode: Bend picks the composer host (bottom-most, then left-most)
# and tags that OpBox PANE_COMPOSER so C seats the widget without a
# geometry chooser. Side-by-side panes share a bottom edge and the left
# pane wins; stacked panes share a left edge and the bottom pane wins.
# composer_row is C's widget row (one above the inner bottom), so the
# pick agrees for zero-inner panes, including 1-high stacked panes where
# outer bottoms tie but inner bottoms do not.
def split_second_wins(+b1: U32, +x1: U32, +b2: U32, +x2: U32) -> Bool:
  U32.is_gt(b2, b1) || (U32.is_eq(b2, b1) && U32.is_lt(x2, x1))

def split_widget_is_r1(r1: Rect, r2: Rect) -> Bool:
  match r1 r2:
    case Rect{+x1, +y1, _, +h1} Rect{+x2, +y2, _, +h2}:
      Bool.not(split_second_wins(composer_row(y1, h1), x1, composer_row(y2, h2), x2))

def split_composer_rect(+r1: Rect, +r2: Rect) -> Rect:
  Bool.pick(Rect, split_widget_is_r1(r1, r2), r1, r2)

def split_pane_role(is_composer: Bool) -> U32:
  match is_composer:
    case True{}: PANE_COMPOSER()
    case False{}: PANE_BODY()

def split_body_role(+r1: Rect, +r2: Rect, first: Bool) -> U32:
  match first:
    case True{}: split_pane_role(split_widget_is_r1(r1, r2))
    case False{}: split_pane_role(Bool.not(split_widget_is_r1(r1, r2)))

def vis_n.on(+have: Nat, +cap: Nat, ge: Bool) -> Nat:
  match ge:
    case True{}:
      cap
    case False{}:
      have

def vis_n(+have: Nat, +cap: Nat) -> Nat:
  vis_n.on(have, cap, Nat.is_ge(have, cap))

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

def paint_tab_names_cm(cm: Maybe<&2, String>, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, String>:
  match cm:
    case None{}: tab_names(bufs, unreads)
    case Some{name}: tab_names_cm(name, bufs, unreads)

def paint_tab_names(+boxed: List<&2, PaintOpts>, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, String>:
  paint_tab_names_cm(opt_cm(boxed), bufs, unreads)

def paint_tab_alerts_cm(cm: Maybe<&2, String>, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, U32>:
  match cm:
    case None{}: tab_alerts(bufs, unreads)
    case Some{name}: tab_alerts_cm(name, bufs, unreads)

def paint_tab_alerts(+boxed: List<&2, PaintOpts>, bufs: List<&2, Cl.Buffer>, +unreads: List<&2, Cl.Alert>) -> List<&2, U32>:
  paint_tab_alerts_cm(opt_cm(boxed), bufs, unreads)

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
      OpBox{x, y, w, h, PANE_NICKS()}
        <> OpText{ix, y, iw, fg, 0, title}
        <> nick_ops.go(names, U32.is_lt(y1, max_y), ix, y1, iw, fg, max_y)

def nick_ops(r: Rect, +title: String, +names: List<&2, String>) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, +w, h}:
      nick_ops.wide(x, y, w, h, title, names, U32.is_gt(w, 2))

def preview_path_of.on(+topic: String, preview: Bool) -> String:
  match preview:
    case True{}: topic
    case False{}: ""

def preview_path_of(+b: Cl.Buffer) -> String:
  match b:
    case Cl.Buffer{+name, _, +topic, _, _, _, _, _}:
      preview_path_of.on(topic, String.eq(name, "*preview*") && Bool.not(Links.is_url_prefix(topic)))

# `Bool.pick` would run preview_path_of on every frame. Production passes
# False, so match and skip the scan unless a legacy adapter asked for it.
def preview_path_legacy(legacy: Bool, +b: Cl.Buffer) -> String:
  match legacy:
    case True{}: preview_path_of(b)
    case False{}: ""

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

def rect_vis_h(r: Rect) -> Nat:
  match r:
    case Rect{_, _, _, +h}: Sp.inner_extent(body_hist_h(h))

def rect_vis_w(r: Rect) -> U32:
  match r:
    case Rect{_, _, +w, _}: inner_w(w)

def visible_anchored_split_media_cards_cm(+cm: String, pair: Rect & Rect, +cl: Cl.Client, +first: String, +second: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match pair:
    case (+r1, +r2):
      match cl:
        case Cl.Client{_, +server, +bufs, +active, _, +stg, _, _, _}:
          List.append(&2, AnchoredRow,
            visible_anchored_buf_media_cards_cm(cm, active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))),
              rect_vis_h(r1), rect_vis_w(r1), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards),
            visible_anchored_buf_media_cards_cm(cm, active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active))),
              rect_vis_h(r2), rect_vis_w(r2), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards))

def visible_anchored_single_media_cards_cm(+cm: String, cl: Cl.Client, +rows: U32, +cols: U32, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match cl:
    case Cl.Client{_, server, bufs, active, _, +stg, _, _, _}:
      visible_anchored_buf_media_cards_cm(cm, active_buf.on(Cl.nth_buf(bufs, active)), vis_h(rows),
        rect_vis_w(lay_body_rect(lay(rows, cols, 0))), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards)

# Cropped visible AnchoredRows for every painted pane under media+cards+cm.
# Media and cards admission both consume this list via *.rows / visible_rows.
def visible_anchored_panes_media_cards_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match split:
    case Sp.Off{}: visible_anchored_single_media_cards_cm(cm, cl, rows, cols, media, cards)
    case Sp.On{axis, first, second, _}:
      visible_anchored_split_media_cards_cm(cm, split_rects(axis, lay_body_rect(lay(rows, cols, 0))), cl, first, second, media, cards)

def visible_anchored_split_media_cards_iso(+isc: Cl.Iso, pair: Rect & Rect, +cl: Cl.Client, +first: String, +second: String, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match pair:
    case (+r1, +r2):
      match cl:
        case Cl.Client{_, +server, +bufs, +active, _, +stg, _, _, _}:
          List.append(&2, AnchoredRow,
            visible_anchored_buf_media_cards_iso(isc, active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))),
              rect_vis_h(r1), rect_vis_w(r1), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards),
            visible_anchored_buf_media_cards_iso(isc, active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active))),
              rect_vis_h(r2), rect_vis_w(r2), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards))

def visible_anchored_single_media_cards_iso(+isc: Cl.Iso, cl: Cl.Client, +rows: U32, +cols: U32, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match cl:
    case Cl.Client{_, server, bufs, active, _, +stg, _, _, _}:
      visible_anchored_buf_media_cards_iso(isc, active_buf.on(Cl.nth_buf(bufs, active)), vis_h(rows),
        rect_vis_w(lay_body_rect(lay(rows, cols, 0))), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media, cards)

def visible_anchored_panes_media_cards_iso(+isc: Cl.Iso, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, AnchoredRow>:
  match split:
    case Sp.Off{}: visible_anchored_single_media_cards_iso(isc, cl, rows, cols, media, cards)
    case Sp.On{axis, first, second, _}:
      visible_anchored_split_media_cards_iso(isc, split_rects(axis, lay_body_rect(lay(rows, cols, 0))), cl, first, second, media, cards)

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

def visible_media.rows(rows: List<&2, AnchoredRow>) -> List<&2, M.Candidate>:
  match rows:
    case Nil{}: Nil{}
    case Con{AnchoredRow{_, _, +line}, tail}:
      List.append(&2, M.Candidate, visible_media.line(Some{line}), visible_media.rows(tail))

def visible_media.crop(+rows: List<&2, AnchoredRow>, +height: Nat, scroll: Cl.Scroll) -> List<&2, M.Candidate>:
  visible_media.rows(visible_anchored_crop(rows, height, scroll))

def at_bottom(scroll: Cl.Scroll) -> Bool:
  match scroll:
    case Cl.ScrollAt{+after, +tail}:
      Bool.and(Nat.is_eq(after, 0n), Nat.is_eq(tail, 0n))

# A filtered line paints nothing, so it is not a visible candidate.
def visible_bottom.keep(empty: Bool, +line: Cl.Line) -> List<&2, M.Candidate>:
  match empty:
    case True{}: Nil{}
    case False{}: visible_media.line(Some{line})

def visible_bottom.after(got: Nat & List<&2, M.Candidate>, +mine: List<&2, M.Candidate>) -> Nat & List<&2, M.Candidate>:
  match got:
    case (left, +tail): (left, List.append(&2, M.Candidate, tail, mine))

# Newest-first. Stop once the viewport rows are filled, matching paint_recent.
def visible_bottom.more(done: Bool, +left: Nat, +h: Cl.Line, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>, k: Nat -> (Nat & List<&2, M.Candidate>)) -> Nat & List<&2, M.Candidate>:
  match done:
    case True{}: (0n, Nil{})
    case False{}:
      +rows = paint_body_rows(paint_filter(boxed, h <> Nil{}, mutes, joins, nicks, name, server), name, w, show_ts, boxed)
      +keep = Nat.min(left, List.length(&2, BodyRow, rows))
      visible_bottom.after(k(Nat.sub(left, keep)), visible_bottom.keep(Nat.is_eq(keep, 0n), h))

def visible_bottom.go(lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +boxed: List<&2, PaintOpts>, +left: Nat) -> Nat & List<&2, M.Candidate>:
  match lines:
    case Nil{}: (left, Nil{})
    case Con{+h, t}:
      visible_bottom.more(Nat.is_eq(left, 0n), left, h, name, w, show_ts, mutes, joins, nicks, server, boxed,
        next => visible_bottom.go(t, name, w, show_ts, mutes, joins, nicks, server, boxed, next))

# `short` is the rare muted suffix that did not fill the pane. Only then
# is the full-history candidate list built.
def visible_bottom.pair(got: Nat & List<&2, M.Candidate>, +truncated: Bool) -> Bool & List<&2, M.Candidate>:
  match got:
    case (left, +cands): (Bool.and(truncated, Nat.is_gt(left, 0n)), cands)

def visible_bottom.scan(got: Newest, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +height: Nat, +boxed: List<&2, PaintOpts>) -> Bool & List<&2, M.Candidate>:
  match got:
    case Newest{+rev, +truncated}:
      visible_bottom.pair(visible_bottom.go(rev, name, w, show_ts, mutes, joins, nicks, server, boxed, height), truncated)

def visible_media.full(+newest: List<&2, Cl.Line>, +count: Nat, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +height: Nat, scroll: Cl.Scroll, +media: M.State) -> List<&2, M.Candidate>:
  match scroll:
    case Cl.ScrollAt{+after, _}:
      visible_media.crop(window_anchored(newest, after, count, height, name, w, show_ts, mutes, joins, nicks, server, paint_media_only(media)), height, scroll)

def visible_media.buffer.tail.use(short: Bool, +cands: List<&2, M.Candidate>, +lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +height: Nat, scroll: Cl.Scroll, +media: M.State) -> List<&2, M.Candidate>:
  match short:
    case False{}: cands
    case True{}: visible_media.full(lines, 0n, name, w, show_ts, mutes, joins, nicks, server, height, scroll, media)

def visible_media.buffer.tail.scanned(scanned: Bool & List<&2, M.Candidate>, +lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +height: Nat, scroll: Cl.Scroll, +media: M.State) -> List<&2, M.Candidate>:
  match scanned:
    case (short, +cands):
      visible_media.buffer.tail.use(short, cands, lines, name, w, show_ts, mutes, joins, nicks, server, height, scroll, media)

def visible_media.buffer.tail(+lines: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +height: Nat, scroll: Cl.Scroll, +media: M.State) -> List<&2, M.Candidate>:
  visible_media.buffer.tail.scanned(
    visible_bottom.scan(newest_lines(lines, height), name, w, show_ts, mutes, joins, nicks, server, height, paint_media_only(media)),
    lines, name, w, show_ts, mutes, joins, nicks, server, height, scroll, media)

def visible_media.spine.got(got: Nat & List<&2, M.Candidate>) -> List<&2, M.Candidate>:
  match got:
    case (_, +cands): cands

# The stored spine is the whole buffer, newest-first, so a short row list
# means the pane really is short. No second walk.
def visible_media.spine(+newest: List<&2, Cl.Line>, +name: String, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +height: Nat, +media: M.State) -> List<&2, M.Candidate>:
  visible_media.spine.got(visible_bottom.go(newest, name, w, show_ts, mutes, joins, nicks, server, paint_media_only(media), height))

def visible_media.buffer.where(bottom: Bool, +name: String, +lines: List<&2, Cl.Line>, +newest: List<&2, Cl.Line>, +count: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +height: Nat, scroll: Cl.Scroll, +media: M.State) -> List<&2, M.Candidate>:
  match bottom:
    case False{}: visible_media.full(newest, count, name, w, show_ts, mutes, joins, nicks, server, height, scroll, media)
    case True{}: visible_media.spine(newest, name, w, show_ts, mutes, joins, nicks, server, height, media)

def visible_media.buffer.allowed(allowed: Bool, b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +joins: Bool, +nicks: Bool, +server: String, +media: M.State) -> List<&2, M.Candidate>:
  match allowed:
    case False{}: Nil{}
    case True{}:
      match b:
        case Cl.Buffer{+name, _, _, +lines, _, +scroll, +newest, +count}:
          visible_media.buffer.where(at_bottom(scroll), name, lines, newest, count, w, show_ts, mutes, joins, nicks, server, height, scroll, media)

def visible_media.buffer(+b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State) -> List<&2, M.Candidate>:
  match b:
    case Cl.Buffer{name, _, _, _, _, _, _, _}:
      visible_media.buffer.allowed(Bool.not(Cl.target_is_synthetic(name)) && Nat.is_gt(height, 0n) && Bool.not(U32.is_zero(w)),
        b, height, w, show_ts, mutes, joins, nicks, server, media)

def visible_media.split(pair: Rect & Rect, +cl: Cl.Client, +first: String, +second: String, +media: M.State) -> List<&2, M.Candidate>:
  match pair:
    case (+r1, +r2):
      match cl:
        case Cl.Client{_, +server, +bufs, +active, _, +stg, _, _, _}:
          List.append(&2, M.Candidate,
            visible_media.buffer(active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))),
              rect_vis_h(r1), rect_vis_w(r1), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media),
            visible_media.buffer(active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active))),
              rect_vis_h(r2), rect_vis_w(r2), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media))

def visible_media.single(cl: Cl.Client, +rows: U32, +cols: U32, media: M.State) -> List<&2, M.Candidate>:
  match cl:
    case Cl.Client{_, server, bufs, active, _, +stg, _, _, _}:
      visible_media.buffer(active_buf.on(Cl.nth_buf(bufs, active)), vis_h(rows),
        rect_vis_w(lay_body_rect(lay(rows, cols, 0))), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, media)

def visible_media.panes(+cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State) -> List<&2, M.Candidate>:
  match split:
    case Sp.Off{}: visible_media.single(cl, rows, cols, media)
    case Sp.On{axis, first, second, _}:
      visible_media.split(split_rects(axis, lay_body_rect(lay(rows, cols, 0))), cl, first, second, media)

def visible_media_candidates(+cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State) -> List<&2, M.Candidate>:
  M.newest_candidates(visible_media.panes(cl, rows, cols, split, media), media)

# Cards-aware admission: consume the shared cropped anchored window so card
# rows that push a chat line out of the viewport also keep it unscheduled.
# Bottom and scrolled paths share window_media_cards_cm (same crop as cards).
def visible_media_cards.from_rows(+rows: List<&2, AnchoredRow>) -> List<&2, M.Candidate>:
  visible_media.rows(rows)

def visible_media_cards.buffer_cm(+cm: String, +b: Cl.Buffer, +height: Nat, +w: U32, show_ts: Bool, mutes: List<&2, String>, +joins: Bool, +nicks: Bool, server: String, media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  visible_media_cards.from_rows(visible_anchored_buf_media_cards_cm(cm, b, height, w, show_ts, mutes, joins, nicks, server, media, cards))

def visible_media_cards.panes_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  visible_media_cards.from_rows(visible_anchored_panes_media_cards_cm(cm, cl, rows, cols, split, media, cards))

def visible_media_candidates_cards_cm(+cm: String, +cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  M.newest_candidates(visible_media_cards.panes_cm(cm, cl, rows, cols, split, media, cards), media)

def visible_media_candidates_cards_iso(+isc: Cl.Iso, +cl: Cl.Client, rows: U32, cols: U32, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>) -> List<&2, M.Candidate>:
  M.newest_candidates(visible_media_cards.from_rows(visible_anchored_panes_media_cards_iso(isc, cl, rows, cols, split, media, cards)), media)

# Prefer when the caller already holds visible_anchored_panes_media_cards_cm.
def visible_media_candidates_from_rows(+rows: List<&2, AnchoredRow>, +media: M.State) -> List<&2, M.Candidate>:
  M.newest_candidates(visible_media_cards.from_rows(rows), media)
def scroll_active_media.on(move: Bool, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Client:
  match move:
    case False{}: cl
    case True{}:
      match cl:
        case Cl.Client{_, +server, _, +active, _, +stg, _, _, _}:
          +rect = focused_rect(rows, cols, split)
          Cl.buf_modify_client(cl, active, b => scroll_buf_media(b, rect_vis_h(rect), rect_vis_w(rect), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, up, dn, media))

def scroll_active_media(+cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State) -> Cl.Client:
  scroll_active_media.on(Nat.is_gt(up, 0n) || Nat.is_gt(dn, 0n), cl, rows, cols, split, up, dn, media)

def scroll_active_media_cards_cm.on(+cm: String, move: Bool, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>, +pends: List<&2, Cl.PendSend>) -> Cl.Client:
  match move:
    case False{}: cl
    case True{}:
      match cl:
        case Cl.Client{_, +server, _, +active, _, +stg, _, _, _}:
          +rect = focused_rect(rows, cols, split)
          Cl.buf_modify_client(cl, active, b => scroll_buf_media_cards_cm(cm, b, rect_vis_h(rect), rect_vis_w(rect), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, up, dn, media, cards, pends))

def scroll_active_media_cards_cm(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>, +pends: List<&2, Cl.PendSend>) -> Cl.Client:
  scroll_active_media_cards_cm.on(cm, Nat.is_gt(up, 0n) || Nat.is_gt(dn, 0n), cl, rows, cols, split, up, dn, media, cards, pends)

def scroll_active_media_cards_iso.on(+isc: Cl.Iso, move: Bool, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>, +pends: List<&2, Cl.PendSend>) -> Cl.Client:
  match move:
    case False{}: cl
    case True{}:
      match cl:
        case Cl.Client{_, +server, _, +active, _, +stg, _, _, _}:
          +rect = focused_rect(rows, cols, split)
          Cl.buf_modify_client(cl, active, b => scroll_buf_media_cards_iso(isc, b, rect_vis_h(rect), rect_vis_w(rect), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, up, dn, media, cards, pends))

def scroll_active_media_cards_iso(+isc: Cl.Iso, +cl: Cl.Client, +rows: U32, +cols: U32, +split: Sp.State, +up: Nat, +dn: Nat, +media: M.State, +cards: List<&2, CardEntry>, +pends: List<&2, Cl.PendSend>) -> Cl.Client:
  scroll_active_media_cards_iso.on(isc, Nat.is_gt(up, 0n) || Nat.is_gt(dn, 0n), cl, rows, cols, split, up, dn, media, cards, pends)

def split_axis_tag(axis: Sp.Axis) -> U32:
  match axis:
    case Sp.SideBySide{}: 0
    case Sp.Stacked{}: 1

def op_split(r: Rect, axis: Sp.Axis) -> DrawOp:
  match r:
    case Rect{x, y, w, h}: OpSplit{x, y, w, h, split_axis_tag(axis), PANE_BODY()}

def split_title.base(+name: String, +topic: String) -> String:
  match topic:
    case SNil{}: name
    case SCon{_, _}: name ++ " — " ++ topic

def split_title(+b: Cl.Buffer, +focused: U32, +pane: U32) -> String:
  match b:
    case Cl.Buffer{+name, _, +topic, _, _, _, _, _}:
      +base = split_title.base(name, topic)
      Bool.pick(String, U32.is_eq(focused, pane), base ++ " [active]", base)

def paint_header_split(r: Rect, +base: String, +net: String, empty: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match r:
    case Rect{+x, +y, +w, _}:
      match empty:
        case True{}:
          OpText{x, y, w, paint_dim(boxed), 0, base} <> Nil{}
        case False{}:
          +pfx = base ++ " · "
          +pw = bounded_width(Cols.text_width(pfx), w)
          +nw = bounded_width(Cols.text_width(net), U32.sub(w, pw))
          OpText{x, y, pw, paint_dim(boxed), 0, pfx}
            <> (OpText{U32.add(x, pw), y, nw, paint_status(boxed, net), 1, net} <> Nil{})

def paint_header_visible(hidden: Bool, r: Rect, +base: String, +net: String, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match hidden:
    case True{}: Nil{}
    case False{}: paint_header_split(r, base, net, String.is_empty(net), boxed)

def paint_header(r: Rect, +nick: String, +server: String, +net: String, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match r:
    case Rect{+x, +y, +w, +h}:
      paint_header_visible(U32.is_zero(w) || U32.is_zero(h), Rect{x, y, w, h}, nick ++ "@" ++ server, net, boxed)

def paint_composer_spans(+nick: String, +boxed: List<&2, PaintOpts>, show_ts: Bool) -> List<&2, SpanOp>:
  +shown = composer_nick(nick)
  List.append(&2, SpanOp, composer_indent(show_ts), Spn{0, "<"} <> (Col{1, paint_nick(boxed, shown), shown} <> (Spn{0, "> "} <> Nil{})))

def paint_composer(r: Rect, +nick: String, +boxed: List<&2, PaintOpts>, show_ts: Bool) -> List<&2, DrawOp>:
  match r:
    case Rect{+x, +y, +w, +h}:
      OpLine{inner_x(x), composer_row(y, h), composer_inner_w(w), paint_fg(boxed), paint_composer_spans(nick, boxed, show_ts)} <> Nil{}

def paint_split_composer(+r1: Rect, +r2: Rect, +nick: String, +boxed: List<&2, PaintOpts>, show_ts: Bool) -> List<&2, DrawOp>:
  paint_composer(split_composer_rect(r1, r2), nick, boxed, show_ts)

def paint_body_box_on(+x: U32, +y: U32, +w: U32, +h: U32, +title: String, empty: Bool, +boxed: List<&2, PaintOpts>, +role: U32) -> List<&2, DrawOp>:
  match empty:
    case True{}: OpBox{x, y, w, h, role} <> Nil{}
    case False{}: OpBox{x, y, w, h, role} <> OpText{inner_x(x), y, inner_w(w), paint_dim(boxed), 0, title} <> Nil{}

def paint_body_box_role(r: Rect, +title: String, +boxed: List<&2, PaintOpts>, +role: U32) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, w, h}: paint_body_box_on(x, y, w, h, title, String.is_empty(title), boxed, role)

# Single-pane body hosts the composer widget.
def paint_body_box(r: Rect, +title: String, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  paint_body_box_role(r, title, boxed, PANE_COMPOSER())

def paint_row_normal(+x: U32, +y: U32, +ts: String, +stamp_w: U32, +off: U32, +w: U32, +fg: U32, +spans: List<&2, SpanOp>, empty: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match empty:
    case True{}: OpLine{U32.add(x, off), y, w, fg, spans} <> Nil{}
    case False{}:
      OpText{x, y, stamp_w, paint_dim(boxed), 0, ts}
        <> (OpLine{U32.add(x, off), y, w, fg, spans} <> Nil{})

def paint_row_ops(+x: U32, +y: U32, row: BodyRow, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match row:
    case BodyRow{+ts, stamp_w, off, w, fg, +spans, _}:
      paint_row_normal(x, y, ts, stamp_w, off, w, fg, spans, String.is_empty(ts), boxed)
    case BodyRecon{+text, +w}:
      OpText{x, y, w, paint_dim(boxed), 0, recon_divider(text, w)} <> Nil{}
    case BodyMedia{_, _, _, _}: Nil{}

def paint_body_ops_go(fuel: Nat, xs: List<&2, BodyRow>, +x: U32, +y: U32, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{BodyMedia{token, w, +h, +row}, +tail}:
          +visible = U32.min(U32.sub(h, row), U32.from_nat(Nat.add(1n, List.length(&2, BodyRow, tail))))
          OpMedia{x, y, w, h, row, visible, token} <> paint_body_ops_go(p, List.drop(&2, BodyRow, tail, Nat.sub(U32.to_nat(visible), 1n)), x, U32.add(y, visible), boxed)
        case Con{head, tail}:
          List.append(&2, DrawOp, paint_row_ops(x, y, head, boxed), paint_body_ops_go(p, tail, x, U32.add(y, 1), boxed))

def paint_body_ops(r: Rect, +xs: List<&2, BodyRow>, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, w, h}:
      +n = U32.from_nat(List.length(&2, BodyRow, xs))
      paint_body_ops_go(List.length(&2, BodyRow, xs), xs, inner_x(x), body_y0(y, h, n), boxed)

def paint_nick_go(xs: List<&2, String>, ok: Bool, +x: U32, +y: U32, +w: U32, +fg: U32, +max_y: U32, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, t}:
      match ok:
        case False{}: Nil{}
        case True{}:
          OpText{x, y, w, paint_nick(boxed, Cl.nick_strip(h)), 0, h}
            <> paint_nick_go(t, U32.is_lt(U32.add(y, 1), max_y), x, U32.add(y, 1), w, fg, max_y, boxed)

def paint_nick_wide(+x: U32, +y: U32, +w: U32, +h: U32, +title: String, +names: List<&2, String>, wide: Bool, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match wide:
    case False{}: Nil{}
    case True{}:
      +ix = inner_x(x)
      +iw = inner_w(w)
      +fg = paint_dim(boxed)
      +y1 = U32.add(y, 1)
      +max_y = box_max_y(y, h)
      OpBox{x, y, w, h, PANE_NICKS()}
        <> OpText{ix, y, iw, fg, 0, title}
        <> paint_nick_go(names, U32.is_lt(y1, max_y), ix, y1, iw, fg, max_y, boxed)

def paint_nicks(r: Rect, +title: String, +names: List<&2, String>, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  match r:
    case Rect{x, y, +w, h}:
      paint_nick_wide(x, y, w, h, title, names, U32.is_gt(w, 2), boxed)

def paint_view_kept.go(empty: Bool, ops: List<&2, DrawOp>) -> List<&2, DrawOp>:
  match empty:
    case True{}: ops
    case False{}: ops

def paint_view_kept(ops: List<&2, DrawOp>, +sr: Rect, +st: String) -> List<&2, DrawOp>:
  match sr:
    case Rect{_, _, _, _}: paint_view_kept.go(String.is_empty(st), ops)

# The cheat sheet used to occupy a reserved row under the box. That row is the
# box border now, so nothing is painted there.
def paint_view_rest(+br: Rect, +bod: List<&2, BodyRow>, +preview: String, +nr: Rect, +title: String, +nicks: List<&2, String>, +sr: Rect, +st: String, +boxed: List<&2, PaintOpts>) -> List<&2, DrawOp>:
  paint_view_kept(
    List.append(&2, DrawOp, image_ops(br, preview),
      List.append(&2, DrawOp, paint_body_ops(body_hist_rect(br), bod, boxed),
        paint_nicks(nr, title, nicks, boxed))),
    sr, st)

def paint_view_ops(
  +boxed: List<&2, PaintOpts>,
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
  show_ts: Bool
) -> List<&2, DrawOp>:
  match lay0:
    case Lay{tr, ur, +br, nr, sr}:
      List.append(&2, DrawOp,
        op_tabs(tr, U32.from_nat(active), names, alerts, bell, bell_seq)
          <> List.append(&2, DrawOp, paint_header(ur, nick, server, net, boxed), paint_body_box(br, btitle, boxed)),
        List.append(&2, DrawOp, paint_view_rest(br, bod, preview, nr, ntitle, nicks, sr, st, boxed), paint_composer(br, nick, boxed, show_ts)))

def paint_view_ops_split(
  +boxed: List<&2, PaintOpts>,
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
  show_ts: Bool
) -> List<&2, DrawOp>:
  match lay0:
    case Lay{tabs, user, body, nicks_rect, status_rect}:
      List.append(&2, DrawOp,
        op_tabs(tabs, U32.from_nat(active), names, alerts, bell, bell_seq)
          <> List.append(&2, DrawOp, paint_header(user, nick, server, net, boxed),
               op_split(body, axis)
                 <> List.append(&2, DrawOp, paint_body_box_role(r1, title1, boxed, split_body_role(r1, r2, True{})),
                      List.append(&2, DrawOp, image_ops(r1, preview1),
                        List.append(&2, DrawOp, paint_body_ops(body_hist_rect(r1), body1, boxed),
                          List.append(&2, DrawOp, paint_body_box_role(r2, title2, boxed, split_body_role(r1, r2, False{})),
                            List.append(&2, DrawOp, image_ops(r2, preview2), paint_body_ops(body_hist_rect(r2), body2, boxed))))))),
        List.append(&2, DrawOp, paint_nicks(nicks_rect, ntitle, nicks, boxed),
          List.append(&2, DrawOp, op_text(status_rect, paint_dim(boxed), status) <> Nil{}, paint_split_composer(r1, r2, nick, boxed, show_ts))))

def paint_view_single(+boxed: List<&2, PaintOpts>, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>) -> ViewModel:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, _, _, _}:
      +b = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +br = lay_body_rect(lay0)
      +unreads = Cl.settings_unreads(stg)
      bod = paint_body_of(b, vis_h(rows), rect_vis_w(br), Cl.settings_ts(stg), Cl.settings_mutes(stg), Cl.settings_joins(stg), Cl.settings_nicks(stg), server, boxed)
      bt nt = body_title_of(b) nicks_title_of(b)
      +ns = nicks_list_of(b)
      ViewModel{paint_view_ops(boxed, lay0, nick, server, net, active, paint_tab_names(boxed, bufs, unreads), paint_tab_alerts(boxed, bufs, unreads), bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), bod, preview_path_legacy(opt_legacy(boxed), b), bt, nt, ns, status_or_typing(status_of.buf(b), typers), Cl.settings_ts(stg)), view_input(draft)}

def paint_view_split_rects(
  +boxed: List<&2, PaintOpts>,
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
  match pair:
    case (+r1, +r2):
      body1 body2 = paint_body_of(b1, rect_vis_h(r1), rect_vis_w(r1), show_ts, mutes, show_joins, show_nicks, server, boxed) paint_body_of(b2, rect_vis_h(r2), rect_vis_w(r2), show_ts, mutes, show_joins, show_nicks, server, boxed)
      paint_view_ops_split(boxed, lay0, axis, nick, server, net, active, tabs, alerts, bell, bell_seq, r1, split_title(b1, focused, 0), body1, preview_path_legacy(opt_legacy(boxed), b1), r2, split_title(b2, focused, 1), body2, preview_path_legacy(opt_legacy(boxed), b2), ntitle, nicks, status_or_typing(status, typers), show_ts)

def paint_view_split(
  +boxed: List<&2, PaintOpts>,
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
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, _, +stg, _, _, _}:
      b1 b2 = active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, first), active))) active_buf.on(Cl.nth_buf(bufs, Maybe.default(&2, Nat, Sp.named_idx(cl, second), active)))
      +focused_buf = active_buf.on(Cl.nth_buf(bufs, active))
      +uh = user_host_label(nick, server, net)
      +lay0 = lay(rows, cols, user_w(uh))
      +body_rect = lay_body_rect(lay0)
      +unreads = Cl.settings_unreads(stg)
      +mutes = Cl.settings_mutes(stg)
      +joins = Cl.settings_joins(stg)
      +nicks = Cl.settings_nicks(stg)
      nt status = nicks_title_of(focused_buf) status_of.buf(focused_buf)
      +ns = nicks_list_of(focused_buf)
      ViewModel{paint_view_split_rects(boxed, split_rects(axis, body_rect), lay0, axis, nick, server, net, active, paint_tab_names(boxed, bufs, unreads), paint_tab_alerts(boxed, bufs, unreads), bool_bit(Cl.settings_bell(stg)), Cl.settings_bell_seq(stg), b1, b2, focused, mutes, joins, nicks, nt, ns, status, typers, Cl.settings_ts(stg)), view_input(draft)}

def paint_view_state(+boxed: List<&2, PaintOpts>, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State) -> ViewModel:
  match split:
    case Sp.Off{}: paint_view_single(boxed, cl, rows, cols, draft, net, typers)
    case Sp.On{axis, +first, +second, focus}:
      paint_view_split(boxed, cl, rows, cols, draft, net, axis, first, second, focus, typers)
def view_draft.state_typing_media(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State) -> ViewModel:
  paint_view_state(paint_media_only(media), cl, rows, cols, draft, net, typers, split)

def view_draft.state_typing(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State) -> ViewModel:
  paint_view_state(paint_legacy_empty(), cl, rows, cols, draft, net, typers, split)

def view_draft_typing(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>) -> ViewModel:
  view_draft.state_typing(cl, rows, cols, draft, net, typers, Sp.Off{})

def view_draft(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String) -> ViewModel:
  view_draft_typing(cl, rows, cols, draft, net, Nil{})

def view_draft_split(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, split: Sp.State) -> ViewModel:
  view_draft.state_typing(cl, rows, cols, draft, net, Nil{}, split)

# Themed production painters. Session owns a Theme.Id and paints through
# these entries; the unthemed painters above keep the historic dark values.
def view_draft.state_typing_media_themed(+cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State, +th: Theme.Id, +pends: List<&2, Cl.PendSend>) -> ViewModel:
  paint_view_state(paint_media_theme(media, th, pends), cl, rows, cols, draft, net, typers, split)

def view_draft.state_typing_media_iso_themed(+isc: Cl.Iso, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State, +th: Theme.Id, +pends: List<&2, Cl.PendSend>) -> ViewModel:
  paint_view_state(paint_media_iso_theme(isc, media, th, pends), cl, rows, cols, draft, net, typers, split)

def view_draft.state_typing_media_cards_cm_themed(+cm: String, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id, +pends: List<&2, Cl.PendSend>) -> ViewModel:
  paint_view_state(paint_media_cards_cm_theme(cm, media, cards, th, pends), cl, rows, cols, draft, net, typers, split)

def view_draft.state_typing_media_cards_iso_themed(+isc: Cl.Iso, +cl: Cl.Client, +rows: U32, +cols: U32, +draft: String, +net: String, +typers: List<&2, String>, split: Sp.State, +media: M.State, +cards: List<&2, CardEntry>, +th: Theme.Id, +pends: List<&2, Cl.PendSend>) -> ViewModel:
  paint_view_state(paint_media_cards_iso_theme(isc, media, cards, th, pends), cl, rows, cols, draft, net, typers, split)

