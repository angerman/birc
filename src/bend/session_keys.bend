# Pure composer key, panel, and input-recall decisions.
# Hist/Comp/Keys constructors stay in session.bend. Session applies KeyPlan.
import Base
import ./composer_ui.bend as Cu
import ./submit.bend as Sub
import ./view.bend as View

type CView is Data:
  CNone{}
  CActive{}
  CUpload{}
  CHelp{topic: String}
  CHidden{}
  CPick{idx: Nat}

type HistStep is Data:
  StepStay{}
  StepPrev{}
  StepNext{}

type KeyPlan is Data:
  KeyApply{halt: Bool, seed: U32, view: CView, pos: Nat, draft: String}
  KeyCycle{}

def line_at(+xs: List<&2, String>, +i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, i), "")

def hist_prev.on(+lines: List<&2, String>, +pos: Nat, z: Bool) -> Nat & String:
  match z:
    case True{}:
      (pos, line_at(lines, pos))
    case False{}:
      +p = Nat.sub(pos, 1n)
      (p, line_at(lines, p))

def hist_prev(+lines: List<&2, String>, +pos: Nat) -> Nat & String:
  hist_prev.on(lines, pos, Nat.is_eq(pos, 0n))

def hist_next.at(+lines: List<&2, String>, +p: Nat, +n: Nat, last: Bool) -> Nat & String:
  match last:
    case True{}:
      (n, "")
    case False{}:
      (p, line_at(lines, p))

def hist_next.on(+lines: List<&2, String>, +pos: Nat, +n: Nat, last: Bool) -> Nat & String:
  match last:
    case True{}:
      (n, "")
    case False{}:
      +p = Nat.add(pos, 1n)
      hist_next.at(lines, p, n, Nat.is_eq(p, n))

def hist_next(+lines: List<&2, String>, +pos: Nat) -> Nat & String:
  +n = List.length(&2, String, lines)
  hist_next.on(lines, pos, n, Nat.is_ge(pos, n))

def hist_move(+lines: List<&2, String>, +pos: Nat, +draft: String, dir: HistStep) -> Nat & String:
  match dir:
    case StepStay{}:
      (pos, draft)
    case StepPrev{}:
      hist_prev(lines, pos)
    case StepNext{}:
      hist_next(lines, pos)

def panel_open(view: CView, +draft: String) -> Bool:
  match view:
    case CHelp{_}: True{}
    case CHidden{}: False{}
    case CUpload{}: False{}
    case _: Bool.or(Cu.is_help(draft), Bool.not(List.is_empty(&2, String, Cu.menu_lines(draft))))

def panel_keep.same(same: Bool, view: CView) -> CView:
  match same:
    case False{}: CNone{}
    case True{}:
      match view:
        case CHelp{topic}: CHelp{topic}
        case CHidden{}: CHidden{}
        case CPick{idx}: CPick{idx}
        case _: CNone{}

def panel_keep(view: CView, +typed: String, +draft: String) -> CView:
  panel_keep.same(String.eq(typed, draft), view)

def panel_dismiss(view: CView) -> CView:
  match view:
    case CHelp{_}: CNone{}
    case _: CHidden{}

def pick_idx(view: CView) -> Nat:
  match view:
    case CPick{idx}: idx
    case _: 0n

def menu_movable(view: CView, +draft: String) -> Bool:
  match view:
    case CHelp{_}: False{}
    case CHidden{}: False{}
    case CUpload{}: False{}
    case _: Bool.or(Nat.is_gt(Cu.menu_len(draft), 1n), Nat.is_gt(Cu.emoji_len(draft), 0n))

def dir_down(dir: HistStep) -> Bool:
  match dir:
    case StepNext{}: True{}
    case _: False{}

def pick_len.on(slash: Bool, +draft: String) -> Nat:
  match slash:
    case True{}: Cu.menu_len(draft)
    case False{}: Cu.emoji_len(draft)

def pick_len(+draft: String) -> Nat:
  pick_len.on(Nat.is_gt(Cu.menu_len(draft), 1n), draft)

def seed_of(dir: HistStep) -> U32:
  match dir:
    case StepStay{}: 0
    case _: 1

def halt_of(enter: Bool, +line: String) -> Bool:
  match enter:
    case True{}: Sub.submit_is_quit(line)
    case False{}: False{}

def ghost_seed.on(empty: Bool) -> U32:
  match empty:
    case True{}: 0
    case False{}: 1

def ghost_seed(+typed: String) -> U32:
  ghost_seed.on(String.is_empty(Cu.ghost_suffix(typed)))

def tab_cycle(view: CView) -> Bool:
  match view:
    case CActive{}: True{}
    case CUpload{}: True{}
    case _: False{}

def typing_line.on(empty: Bool, +notice: String) -> List<&2, String>:
  match empty:
    case True{}: Nil{}
    case False{}: notice <> Nil{}

def typing_line(typers: List<&2, String>) -> List<&2, String>:
  +notice = View.typing_notice(typers)
  typing_line.on(String.is_empty(notice), notice)

def panel_menu(xs: List<&2, String>, typers: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: typing_line(typers)
    case _: xs

def panel_lines.rest(is_help: Bool, +draft: String, typers: List<&2, String>, +idx: Nat) -> List<&2, String>:
  match is_help:
    case True{}: Cu.help_lines(Cu.help_arg(draft), 24n)
    case False{}: panel_menu(Cu.emoji_or(draft, idx), typers)

def panel_lines.help(view: CView, +draft: String, typers: List<&2, String>) -> List<&2, String>:
  match view:
    case CHidden{}: typing_line(typers)
    case CUpload{}: typing_line(typers)
    case CHelp{+topic}: Cu.help_lines(topic, 24n)
    case CPick{+idx}: panel_lines.rest(Cu.is_help(draft), draft, typers, idx)
    case _: panel_lines.rest(Cu.is_help(draft), draft, typers, 0n)

def panel_lines.on(empty: Bool, view: CView, +draft: String, +hint: String, typers: List<&2, String>) -> List<&2, String>:
  match empty:
    case False{}: hint <> Nil{}
    case True{}: panel_lines.help(view, draft, typers)

def panel_lines(view: CView, +draft: String, +hint: String, typers: List<&2, String>) -> List<&2, String>:
  panel_lines.on(String.is_empty(hint), view, draft, hint, typers)

# Help and a hidden menu survive a frame that does not change the composer.
# `prev` is the draft before this frame; `shown` is the draft after it.
def finish_keys.shown(+pos: Nat, +shown: String, halt: Bool, +seed: U32, view: CView, +prev: String) -> KeyPlan:
  KeyApply{halt, seed, panel_keep(view, shown, prev), pos, shown}

def finish_keys.plain.at(pair: Nat & String, view: CView, +typed: String, +prev: String, dir: HistStep, enter: Bool) -> KeyPlan:
  match pair:
    case (+npos, +shown):
      finish_keys.shown(npos, shown, halt_of(enter, typed), seed_of(dir), view, prev)

def finish_keys.plain(+lines: List<&2, String>, +pos: Nat, view: CView, +typed: String, +draft: String, +prev: String, +dir: HistStep, enter: Bool) -> KeyPlan:
  finish_keys.plain.at(hist_move(lines, pos, draft, dir), view, typed, prev, dir, enter)

def finish_keys.pick(down: Bool, +pos: Nat, view: CView, +draft: String, +prev: String) -> KeyPlan:
  +n = pick_len(draft)
  +idx = Cu.pick_move(down, Cu.pick_clamp(pick_idx(view), n), n)
  KeyApply{False{}, 1, panel_keep(CPick{idx}, draft, prev), pos, draft}

def finish_keys.navmenu(open: Bool, dir: HistStep, +lines: List<&2, String>, +pos: Nat, view: CView, +typed: String, +draft: String, +prev: String, enter: Bool) -> KeyPlan:
  match open:
    case True{}: finish_keys.pick(dir_down(dir), pos, view, draft, prev)
    case False{}: finish_keys.plain(lines, pos, view, typed, draft, prev, dir, enter)

def finish_keys.dir(dir: HistStep, +lines: List<&2, String>, +pos: Nat, +view: CView, +typed: String, +draft: String, +prev: String, enter: Bool) -> KeyPlan:
  match dir:
    case StepStay{}: finish_keys.plain(lines, pos, view, typed, draft, prev, dir, enter)
    case _: finish_keys.navmenu(menu_movable(view, draft), dir, lines, pos, view, typed, draft, prev, enter)

def finish_keys.accept(+pos: Nat, +view: CView, +typed: String, +prev: String) -> KeyPlan:
  +next = Cu.compose_accept(typed, pick_idx(view))
  KeyApply{False{}, ghost_seed(typed), panel_keep(view, next, prev), pos, next}

def finish_keys.dismiss.at(pair: Nat & String, +seed: U32, view: CView) -> KeyPlan:
  match pair:
    case (+npos, +shown):
      KeyApply{False{}, seed, panel_dismiss(view), npos, shown}

def finish_keys.dismiss(+lines: List<&2, String>, +pos: Nat, view: CView, +draft: String, +dir: HistStep) -> KeyPlan:
  finish_keys.dismiss.at(hist_move(lines, pos, draft, dir), seed_of(dir), view)

def finish_keys.tab(accept: Bool, +pos: Nat, view: CView, +typed: String, +prev: String) -> KeyPlan:
  match accept:
    case True{}: finish_keys.accept(pos, view, typed, prev)
    case False{}: KeyCycle{}

def finish_keys.comp(+code: U32, +lines: List<&2, String>, +pos: Nat, +view: CView, +typed: String, +draft: String, +prev: String, dir: HistStep, enter: Bool) -> KeyPlan:
  match code:
    case 1:
      finish_keys.tab(
        Bool.and(Bool.not(tab_cycle(view)), Cu.tab_accept_ok(typed, pick_idx(view))),
        pos, view, typed, prev)
    case 2:
      finish_keys.accept(pos, view, typed, prev)
    case 3:
      finish_keys.dismiss(lines, pos, view, draft, dir)
    case _:
      finish_keys.dir(dir, lines, pos, view, typed, draft, prev, enter)
