# Pure split-view state. IRC client data stays independent of UI tiling.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl

type Axis is Data:
  SideBySide{}
  Stacked{}

type State is Data:
  Off{}
  # Pane keys use *server* for index zero and actual names for other buffers.
  On{axis: Axis, first: String, second: String, focus: U32}

type Command is Data:
  NotSplit{}
  BadSplit{}
  SplitOpen{axis: Axis, target: String}
  SplitClose{}
  SplitFocus{}

def state0() -> State:
  Off{}

def show_axis(axis: Axis) -> String:
  match axis:
    case SideBySide{}: "side-by-side"
    case Stacked{}: "stacked"

def show_name(+name: String) -> String:
  Bool.pick(String, String.eq(name, "*server*"), "server", name)

def show_state(st: State) -> String:
  match st:
    case Off{}: "off"
    case On{axis, +first, +second, focus}:
      show_axis(axis) ++ ":" ++ show_name(first) ++ ":" ++ show_name(second) ++ ":" ++ U32.show(focus)

def is_on(st: State) -> Bool:
  match st:
    case Off{}: False{}
    case On{_, _, _, _}: True{}

def axis_of(st: State) -> Axis:
  match st:
    case Off{}: Stacked{}
    case On{axis, _, _, _}: axis

def focus_of(st: State) -> U32:
  match st:
    case Off{}: 0
    case On{_, _, _, focus}: focus

def first_extent(+n: U32) -> U32:
  U32.add(U32.div(n, 2), U32.mod(n, 2))

def second_extent(+n: U32) -> U32:
  U32.sub(n, first_extent(n))

def inner_extent.on(+n: U32, large: Bool) -> Nat:
  match large:
    case True{}: U32.to_nat(U32.sub(n, 2))
    case False{}: 1n

def inner_extent(+n: U32) -> Nat:
  inner_extent.on(n, U32.is_ge(n, 3))

# The full body box is rows-3 on normal terminals. TimUI FLEX(1),FLEX(1)
# gives the rounding remainder to the second constraint after rounding the first.
def body_box_h.on(+rows: U32, normal: Bool) -> U32:
  match normal:
    case True{}: U32.sub(rows, 3)
    case False{}: 1

def body_box_h(+rows: U32) -> U32:
  body_box_h.on(rows, U32.is_ge(rows, 4))

def page_height.stacked(+focus: U32, +h: U32) -> Nat:
  match focus:
    case 0: inner_extent(first_extent(h))
    case _: inner_extent(second_extent(h))

def page_height.on(axis: Axis, +focus: U32, +rows: U32) -> Nat:
  match axis:
    case SideBySide{}:
      inner_extent(body_box_h(rows))
    case Stacked{}:
      page_height.stacked(focus, body_box_h(rows))

def page_height(+rows: U32, st: State) -> Nat:
  match st:
    case Off{}:
      inner_extent(body_box_h(rows))
    case On{axis, _, _, focus}:
      page_height.on(axis, focus, rows)

def page_height_ok() -> Bool:
  Nat.is_eq(page_height(24, On{Stacked{}, "a", "b", 0}), 9n)
    && Nat.is_eq(page_height(24, On{Stacked{}, "a", "b", 1}), 8n)
    && Nat.is_eq(page_height(24, On{SideBySide{}, "a", "b", 0}), 19n)
    && Nat.is_eq(page_height(2, On{Stacked{}, "a", "b", 1}), 1n)

def extents_fit(+n: U32) -> Bool:
  U32.is_eq(U32.add(first_extent(n), second_extent(n)), n)

def bounds_ok() -> Bool:
  extents_fit(0) && extents_fit(1) && extents_fit(20) && extents_fit(21) && extents_fit(200)

def toggle_focus(+focus: U32) -> U32:
  match focus:
    case 0: 1
    case _: 0

def focus_bit(b: Bool) -> U32:
  match b:
    case False{}: 0
    case True{}: 1

def focus_twice_ok(b: Bool) -> Bool:
  +f = focus_bit(b)
  U32.is_eq(toggle_focus(toggle_focus(f)), f)

def name_at.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{b}:
      match b:
        case Cl.Buffer{+name, _, _, _, _, _}: name

def name_at(+cl: Cl.Client, +i: Nat) -> String:
  Bool.pick(String, Nat.is_eq(i, 0n), "*server*", name_at.got(Cl.nth_buf(Cl.client_bufs(cl), i)))

def default_target.active(+active: Nat) -> Maybe<&2, Nat>:
  match active:
    case 0n: Some{1n}
    case 1n+_: Some{0n}

def default_target.on(+active: Nat, +count: Nat, enough: Bool) -> Maybe<&2, Nat>:
  match enough:
    case False{}: None{}
    case True{}: default_target.active(active)

def default_target(+cl: Cl.Client) -> Maybe<&2, Nat>:
  +count = Cl.buf_count(Cl.client_bufs(cl))
  default_target.on(Cl.active_of(cl), count, Nat.is_gt(count, 1n))

def named_idx.server(is_server: Bool, +cl: Cl.Client, +target: String) -> Maybe<&2, Nat>:
  match is_server:
    case True{}: Some{0n}
    case False{}: Cl.buf_find(cl, target)

def named_idx(+cl: Cl.Client, +target: String) -> Maybe<&2, Nat>:
  named_idx.server(String.eq(target, "*server*"), cl, target)

# Internal pane keys never guess a role from the display name. Only command
# input accepts the old "server" alias, and only while that query is absent.
def command_idx.got(got: Maybe<&2, Nat>, +target: String) -> Maybe<&2, Nat>:
  match got:
    case Some{i}: Some{i}
    case None{}: Bool.pick(Maybe<&2, Nat>, Irc.ieq(target, "server"), Some{0n}, None{})

def command_idx(+cl: Cl.Client, +target: String) -> Maybe<&2, Nat>:
  command_idx.got(named_idx(cl, target), target)

def target_idx(+cl: Cl.Client, +target: String) -> Maybe<&2, Nat>:
  match target:
    case SNil{}: default_target(cl)
    case SCon{_, _}: command_idx(cl, target)

def activate.idx(same: Bool, +cl: Cl.Client, axis: Axis, +i: Nat) -> Cl.Client & State & Bool:
  match same:
    case True{}: (cl, Off{}, False{})
    case False{}:
      +first = name_at(cl, Cl.active_of(cl))
      +second = name_at(cl, i)
      (cl, On{axis, first, second, 0}, True{})

def activate.got(+cl: Cl.Client, axis: Axis, got: Maybe<&2, Nat>) -> Cl.Client & State & Bool:
  match got:
    case None{}: (cl, Off{}, False{})
    case Some{+i}: activate.idx(Nat.is_eq(i, Cl.active_of(cl)), cl, axis, i)

def activate(+cl: Cl.Client, axis: Axis, +target: String) -> Cl.Client & State & Bool:
  activate.got(cl, axis, target_idx(cl, Irc.drop_spaces(target)))

def found.got(got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def found(+cl: Cl.Client, +name: String) -> Bool:
  found.got(named_idx(cl, name))

# A query keeps its pane and focus when NICK changes its name. The internal
# control key is not a query. Apply accepted renames in arrival order before
# normalizing against the final client (which may have coalesced two queries).
def rename_query.key(+key: String, +from: String, +to: String) -> String:
  Bool.pick(String, Cl.is_query_name(key) && Irc.ieq(key, from), to, key)

def rename_query.names(st: State, +from: String, +to: String) -> State:
  match st:
    case Off{}: Off{}
    case On{axis, +first, +second, focus}:
      On{axis, rename_query.key(first, from, to), rename_query.key(second, from, to), focus}

def rename_query.accepted(allowed: Bool, st: State, from: String, to: String) -> State:
  match allowed:
    case False{}: st
    case True{}: rename_query.names(st, from, to)

def rename_query.nick(nick: Bool, st: State, +m: Irc.Message) -> State:
  match nick:
    case False{}: st
    case True{}: rename_query.accepted(Cl.nick_rename_allowed(Irc.msg_nick(m), Irc.msg_param(m, 0n)), st, Cl.target_name(Irc.msg_nick(m)), Cl.target_name(Irc.msg_param(m, 0n)))

def rename_query.parsed(st: State, m: Maybe<&2, Irc.Message>) -> State:
  match m:
    case None{}: st
    case Some{+msg}: rename_query.nick(Irc.ieq(Irc.msg_command(msg), "NICK"), st, msg)

def rename_query.line(st: State, line: String) -> State:
  rename_query.parsed(st, Irc.parse(line))

def rename_queries(st: State, lines: List<&2, String>) -> State:
  List.foldl(~&2, ~String, ~State, ~rename_query.line, lines, st)

def normalize.on(ok: Bool, st: State) -> State:
  match ok:
    case True{}: st
    case False{}: Off{}

def normalize(+cl: Cl.Client, st: State) -> State:
  match st:
    case Off{}: Off{}
    case On{axis, +first, +second, focus}:
      normalize.on(found(cl, first) && found(cl, second) && Bool.not(Irc.ieq(first, second)), On{axis, first, second, focus})

def follow_active.on(+cl: Cl.Client, axis: Axis, +first: String, +second: String, +focus: U32, +active: String) -> State:
  match focus:
    case 0: normalize(cl, On{axis, active, second, 0})
    case _: normalize(cl, On{axis, first, active, 1})

def follow_active(+cl: Cl.Client, st: State) -> State:
  match st:
    case Off{}: Off{}
    case On{axis, +first, +second, focus}:
      follow_active.on(cl, axis, first, second, focus, name_at(cl, Cl.active_of(cl)))

def focus_name(+first: String, +second: String, +focus: U32) -> String:
  match focus:
    case 0: first
    case _: second

def set_active_named.got(+cl: Cl.Client, got: Maybe<&2, Nat>) -> Cl.Client:
  match got:
    case None{}: cl
    case Some{+i}: Cl.set_active(cl, i)

def set_active_named(+cl: Cl.Client, +name: String) -> Cl.Client:
  set_active_named.got(cl, named_idx(cl, name))

def toggle(+cl: Cl.Client, st: State) -> Cl.Client & State:
  match st:
    case Off{}: (cl, Off{})
    case On{axis, +first, +second, focus}:
      +next = toggle_focus(focus)
      (set_active_named(cl, focus_name(first, second, next)), On{axis, first, second, next})

def parse_split_arg.vertical(vertical: Bool, +word: String, +rest: String) -> Command:
  match vertical:
    case True{}: SplitOpen{Stacked{}, Irc.drop_spaces(rest)}
    case False{}: SplitOpen{Stacked{}, word}

def parse_split_arg.horizontal(horizontal: Bool, +word: String, +rest: String) -> Command:
  match horizontal:
    case True{}: SplitOpen{SideBySide{}, Irc.drop_spaces(rest)}
    case False{}: parse_split_arg.vertical(Irc.ieq(word, "vertical") || Irc.ieq(word, "stacked"), word, rest)

def parse_split_arg.word(+word: String, +rest: String) -> Command:
  match word:
    case SNil{}: SplitOpen{Stacked{}, ""}
    case SCon{_, _}:
      parse_split_arg.horizontal(Irc.ieq(word, "horizontal") || Irc.ieq(word, "side"), word, rest)

def parse_split_arg(pair: String & String) -> Command:
  match pair:
    case (+word, +rest): parse_split_arg.word(word, rest)

def parse_verb.focus(focus: Bool) -> Command:
  match focus:
    case True{}: SplitFocus{}
    case False{}: NotSplit{}

def parse_verb.close(close: Bool, +verb: String) -> Command:
  match close:
    case True{}: SplitClose{}
    case False{}: parse_verb.focus(Irc.ieq(verb, "focus"))

def parse_verb.vsplit(vsplit: Bool, +verb: String, +rest: String) -> Command:
  match vsplit:
    case True{}: SplitOpen{SideBySide{}, Irc.drop_spaces(rest)}
    case False{}: parse_verb.close(Irc.ieq(verb, "split-off") || Irc.ieq(verb, "unsplit"), verb)

def parse_verb.split(split: Bool, +verb: String, +rest: String) -> Command:
  match split:
    case True{}: parse_split_arg(Irc.take_until_space(Irc.drop_spaces(rest)))
    case False{}: parse_verb.vsplit(Irc.ieq(verb, "vsplit"), verb, rest)

def parse_verb(+verb: String, +rest: String) -> Command:
  parse_verb.split(Irc.ieq(verb, "split"), verb, rest)

def parse_words(pair: String & String) -> Command:
  match pair:
    case (+verb, +rest): parse_verb(verb, rest)

def parse(+input: String) -> Command:
  match input:
    case SCon{'/', +rest}: parse_words(Irc.take_until_space(rest))
    case _: NotSplit{}

def show_command(cmd: Command) -> String:
  match cmd:
    case NotSplit{}: "none"
    case BadSplit{}: "bad"
    case SplitOpen{axis, +target}: "open:" ++ show_axis(axis) ++ ":" ++ target
    case SplitClose{}: "close"
    case SplitFocus{}: "focus"

def parse_ok() -> Bool:
  String.eq(show_command(parse("/split #birc")), "open:stacked:#birc")
    && String.eq(show_command(parse("/split horizontal server")), "open:side-by-side:server")
    && String.eq(show_command(parse("/vsplit #two")), "open:side-by-side:#two")
    && String.eq(show_command(parse("/split-off")), "close")
    && String.eq(show_command(parse("/unsplit")), "close")
    && String.eq(show_command(parse("/focus")), "focus")
    && String.eq(show_command(parse("hello")), "none")
