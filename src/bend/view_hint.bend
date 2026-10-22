# A transient panel over the bottom of the chat. It never replaces the draft
# and never enters history. OpGhost is drawn by C after the composer widget,
# so a one-line warning still shows on a terminal too small for a panel row.
import Base
import ./buffer.bend as Cl
import ./columns.bend as Cols
import ./theme.bend as Theme
import ./view.bend as V

def spaces(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: SCon{Chr{32}, spaces(p)}

def panel_end.on(above: Bool, +last: U32) -> U32:
  match above:
    case True{}: U32.sub(last, 1)
    case False{}: last

def panel_end(+rows: U32) -> U32:
  +last = V.last_body_row(rows)
  panel_end.on(U32.is_gt(last, 2), last)

def on_composer(+rows: U32) -> Bool:
  U32.is_eq(panel_end(rows), V.last_body_row(rows))

def inner_w.on(wide: Bool, +cols: U32) -> U32:
  match wide:
    case True{}: U32.sub(cols, 2)
    case False{}: cols

def inner_w(+cols: U32) -> U32:
  inner_w.on(U32.is_ge(cols, 2), cols)

def pad.on(fits: Bool, +s: String, +n: Nat) -> String:
  match fits:
    case True{}: s
    case False{}: s ++ spaces(Nat.sub(n, String.length(s)))

def pad(+s: String, +w: U32) -> String:
  +n = Cl.clamp_nat(U32.to_nat(w), 1024n)
  pad.on(Nat.is_ge(String.length(s), n), s, n)

def line_cap.room(room: Bool, +end: U32) -> Nat:
  match room:
    case True{}: U32.to_nat(U32.sub(end, 1))
    case False{}: 1n

def line_cap.on(composer: Bool, +end: U32) -> Nat:
  match composer:
    case True{}: 1n
    case False{}: line_cap.room(U32.is_gt(end, 1), end)

def line_cap(+rows: U32) -> Nat:
  line_cap.on(on_composer(rows), panel_end(rows))

def take_n(fuel: Nat, xs: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+h, t}: h <> take_n(p, t)

def count(xs: List<&2, String>) -> Nat:
  List.length(&2, String, xs)

def start_y.on(low: Bool, +raw: U32) -> U32:
  match low:
    case True{}: 2
    case False{}: raw

def start_y(+end: U32, +n: Nat) -> U32:
  +raw = U32.sub(U32.add(end, 1), U32.from_nat(n))
  start_y.on(U32.is_lt(raw, 2), raw)

def paint_hot(+s: String) -> Bool:
  String.starts_with(s, "→")

def paint_fg.hot(hot: Bool, +fg: U32, +th: Theme.Id) -> U32:
  match hot:
    case False{}: fg
    case True{}: V.FG_TEXT_themed(th)

def paint_fg(hot: Bool, warn: Bool, +fg: U32, +th: Theme.Id) -> U32:
  match warn:
    case True{}: fg
    case False{}: paint_fg.hot(hot, fg, th)

def paint_attr.hot(hot: Bool, +base: U32) -> U32:
  match hot:
    case False{}: base
    case True{}: 1

def paint_attr(hot: Bool, composer: Bool, +base: U32) -> U32:
  match composer:
    case True{}: base
    case False{}: paint_attr.hot(hot, base)

def paint_op(composer: Bool, +x: U32, +y: U32, +w: U32, +fg: U32, +attrs: U32, +text: String) -> V.DrawOp:
  match composer:
    case True{}: V.OpGhost{x, y, w, fg, text}
    case False{}: V.OpText{x, y, w, fg, attrs, text}

def paint_at(fuel: Nat, xs: List<&2, String>, +x: U32, +y: U32, +w: U32, +fg: U32, +attrs: U32, +warn: Bool, +composer: Bool, +th: Theme.Id) -> List<&2, V.DrawOp>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+h, t}:
          +hot = paint_hot(h)
          paint_op(composer, x, y, w, paint_fg(hot, warn, fg, th), paint_attr(hot, composer, attrs), pad(h, w)) <> paint_at(p, t, x, U32.add(y, 1), w, fg, attrs, warn, composer, th)

def line_attrs(composer: Bool, warn: Bool) -> U32:
  match composer:
    case True{}: 0
    case False{}:
      match warn:
        case True{}: 1
        case False{}: 0

def line_fg(warn: Bool, +th: Theme.Id) -> U32:
  match warn:
    case True{}: V.FG_TEXT_themed(th)
    case False{}: V.FG_DIM_themed(th)

def ghost_op(show: Bool, +ghost: String, +x: U32, +y: U32, +w: U32, +fg: U32) -> List<&2, V.DrawOp>:
  match show:
    case False{}: Nil{}
    case True{}: V.OpGhost{x, y, w, fg, ghost} <> Nil{}

# The native composer keeps one deferred slot. A panel line already on the
# composer row fills it; a second ghost suffix would replace that line.
def ghost_show.lines(has_lines: Bool, +ghost: String) -> Bool:
  match has_lines:
    case True{}: False{}
    case False{}: Bool.not(String.is_empty(ghost))

def ghost_show.open(composer: Bool, has_lines: Bool, +ghost: String) -> Bool:
  match composer:
    case False{}: Bool.not(String.is_empty(ghost))
    case True{}: ghost_show.lines(has_lines, ghost)

def ghost_show(warn: Bool, composer: Bool, has_lines: Bool, +ghost: String) -> Bool:
  match warn:
    case True{}: False{}
    case False{}: ghost_show.open(composer, has_lines, ghost)

def panel_ops(vm: V.ViewModel, +rows: U32, +cols: U32, lines: List<&2, String>, +ghost: String, +gx: U32, +th: Theme.Id, +warn: Bool) -> V.ViewModel:
  match vm:
    case V.ViewModel{ops, input}:
      +composer = on_composer(rows)
      +shown = take_n(line_cap(rows), lines)
      +n = count(shown)
      +w = inner_w(cols)
      +fg = line_fg(warn, th)
      +attrs = line_attrs(composer, warn)
      +text = paint_at(n, shown, 1, start_y(panel_end(rows), n), w, fg, attrs, warn, composer, th)
      +with_ghost = List.append(&2, V.DrawOp, text, ghost_op(ghost_show(warn, composer, Bool.not(Nat.is_eq(n, 0n)), ghost), ghost, gx, V.last_body_row(rows), w, V.FG_DIM_themed(th)))
      V.ViewModel{List.append(&2, V.DrawOp, ops, with_ghost), input}

def ghost_x(+compose_x: U32, +draft: String) -> U32:
  U32.add(compose_x, Cols.text_width(draft))

def status.on(empty: Bool, vm: V.ViewModel, rows: U32, cols: U32, +hint: String) -> V.ViewModel:
  match empty:
    case True{}: vm
    case False{}: panel_ops(vm, rows, cols, hint <> Nil{}, "", 0, Theme.default(), True{})

def status(vm: V.ViewModel, rows: U32, cols: U32, +hint: String) -> V.ViewModel:
  status.on(String.is_empty(hint), vm, rows, cols, hint)
