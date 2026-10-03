# SPDX-License-Identifier: Apache-2.0
# Per-buffer drafts and multiline composition (pure).
#
# One composer draft per buffer, keyed by normalized buffer name, plus a
# multiline send policy for pasted or typed text. Session keeps focus,
# modals, and history; this module owns the store and the wire plan so the
# integrator can call it without changing shared Client/Buffer types.
#
# Bounds: at most ENTRY_CAP entries (one per buffer slot), TEXT_BYTES UTF-8
# bytes per draft, LINE_CAP composition lines per draft. `set` rejects
# over-bound text and keeps the previous draft; it never truncates.
# Separators are ASCII CR, CRLF, and LF, which cannot occur inside a UTF-8
# multibyte sequence, so splitting never breaks a cluster. Wire chunks reuse
# message_chunks.split at TimUI common-cluster boundaries, and credential
# checks reuse submit.message_sensitive per line. Multiline sends are
# chat-only: any slash-led line rejects the whole send atomically, so a
# paste can never smuggle a command onto the wire.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./message_chunks.bend as Chunks
import ./irc_commands.bend as Commands
import ./submit.bend as Sub

type Draft is Data:
  Draft{name: String, text: String}

type Drafts is Data:
  Drafts{entries: List<&2, Draft>}

type Route is Data:
  RouteEmpty{}
  RouteSingle{line: String}
  RouteMulti{lines: List<&2, String>}

def ENTRY_CAP() -> Nat:
  16n

def TEXT_BYTES() -> Nat:
  4096n

def LINE_CAP() -> Nat:
  32n

def empty() -> Drafts:
  Drafts{Nil{}}

def count(+ds: Drafts) -> Nat:
  match ds:
    case Drafts{+entries}:
      List.length(&2, Draft, entries)

# ---- line splitting ---------------------------------------------------
# CR, CRLF, and LF separate lines. Every other character, including TAB,
# SOH, DEL, and multibyte clusters, stays in its line untouched.

def split_lines.end.tail(empty: Bool, +line: String, +lines: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      List.reverse(&2, String, lines)
    case False{}:
      List.reverse(&2, String, String.reverse(line) <> lines)

def split_lines.end(+line: String, +lines: List<&2, String>) -> List<&2, String>:
  match lines:
    case Nil{}:
      String.reverse(line) <> Nil{}
    case Con{_, _}:
      split_lines.end.tail(String.is_empty(line), line, lines)

# One recursive def per loop: the step helpers take a continuation and
# never name split_lines.go. Fuel is length+1; every step consumes a char.

def split_lines.step.after_cr(skip: Bool, +n: Char, +rest: String, +line: String, +lines: List<&2, String>, k: String -> String -> List<&2, String> -> List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}:
      k(rest, "", String.reverse(line) <> lines)
    case False{}:
      k(SCon{n, rest}, "", String.reverse(line) <> lines)

def split_lines.step.cr(+t: String, +line: String, +lines: List<&2, String>, k: String -> String -> List<&2, String> -> List<&2, String>) -> List<&2, String>:
  match t:
    case SNil{}:
      k("", "", String.reverse(line) <> lines)
    case SCon{+n, +rest}:
      split_lines.step.after_cr(Irc.code_is(n, 10), n, rest, line, lines, k)

def split_lines.step.plain(lf: Bool, +h: Char, +t: String, +line: String, +lines: List<&2, String>, k: String -> String -> List<&2, String> -> List<&2, String>) -> List<&2, String>:
  match lf:
    case True{}:
      k(t, "", String.reverse(line) <> lines)
    case False{}:
      k(t, SCon{h, line}, lines)

def split_lines.step(cr: Bool, lf: Bool, +h: Char, +t: String, +line: String, +lines: List<&2, String>, k: String -> String -> List<&2, String> -> List<&2, String>) -> List<&2, String>:
  match cr:
    case True{}:
      split_lines.step.cr(t, line, lines, k)
    case False{}:
      split_lines.step.plain(lf, h, t, line, lines, k)

def split_lines.go(fuel: Nat, s: String, +line: String, +lines: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      split_lines.end(line, lines)
    case 1n+p:
      match s:
        case SNil{}:
          split_lines.end(line, lines)
        case SCon{+h, +t}:
          split_lines.step(Irc.code_is(h, 13), Irc.code_is(h, 10), h, t, line, lines, rest => acc => done => split_lines.go(p, rest, acc, done))

def split_lines(+s: String) -> List<&2, String>:
  split_lines.go(Nat.add(1n, String.length(s)), s, "", Nil{})

def nonempty.keep(+rest: List<&2, String>, +h: String, drop: Bool) -> List<&2, String>:
  match drop:
    case True{}:
      rest
    case False{}:
      h <> rest

def nonempty(+xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, +t}:
      nonempty.keep(nonempty(t), h, String.is_empty(h))

def fits_bytes(+text: String) -> Bool:
  Nat.is_le(Irc.utf8_len(text), TEXT_BYTES())

def fits_lines(+text: String) -> Bool:
  Nat.is_le(List.length(&2, String, split_lines(text)), LINE_CAP())

def fits(+text: String) -> Bool:
  fits_bytes(text) && fits_lines(text)

# ---- store ------------------------------------------------------------
# Lookup uses RFC 1459 casemapping like buf_find, so a draft follows the
# buffer it was typed in. An empty text clears the entry instead of
# storing a blank draft.

def find_entry.rest(cont: Maybe<&2, String>, +text: String, hit: Bool) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{text}
    case False{}:
      cont

def find_entry.go(xs: List<&2, Draft>, +name: String) -> Maybe<&2, String>:
  match xs:
    case Nil{}:
      None{}
    case Con{h, +t}:
      match h:
        case Draft{+stored, +text}:
          +cont = find_entry.go(t, name)
          find_entry.rest(cont, text, Irc.ieq(stored, name))

def find_entry(+ds: Drafts, +name: String) -> Maybe<&2, String>:
  match ds:
    case Drafts{+entries}:
      find_entry.go(entries, Cl.target_name(name))

def get.on(found: Maybe<&2, String>) -> String:
  match found:
    case None{}:
      ""
    case Some{+text}:
      text

def get(+ds: Drafts, +name: String) -> String:
  get.on(find_entry(ds, name))

def has.on(found: Maybe<&2, String>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{_}:
      True{}

def has(+ds: Drafts, +name: String) -> Bool:
  has.on(find_entry(ds, name))

def remove_entry.keep(+rest: List<&2, Draft>, +stored: String, +text: String, hit: Bool) -> List<&2, Draft>:
  match hit:
    case True{}:
      rest
    case False{}:
      Draft{stored, text} <> rest

def remove_entry.go(xs: List<&2, Draft>, +name: String) -> List<&2, Draft>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, +t}:
      match h:
        case Draft{+stored, +text}:
          remove_entry.keep(remove_entry.go(t, name), stored, text, Irc.ieq(stored, name))

def clear(+ds: Drafts, +raw: String) -> Drafts:
  match ds:
    case Drafts{+entries}:
      Drafts{remove_entry.go(entries, Cl.target_name(raw))}

def drop(+ds: Drafts, +name: String) -> Drafts:
  clear(ds, name)

def replace_entry.picked(+rest: List<&2, Draft>, replaced: Bool, +stored: String, +old: String, +name: String, +text: String, hit: Bool) -> List<&2, Draft> & Bool:
  match hit:
    case True{}:
      (Draft{name, text} <> rest, True{})
    case False{}:
      (Draft{stored, old} <> rest, replaced)

def replace_entry.keep(pair: List<&2, Draft> & Bool, +stored: String, +old: String, +name: String, +text: String, hit: Bool) -> List<&2, Draft> & Bool:
  match pair:
    case (+rest, +replaced):
      replace_entry.picked(rest, replaced, stored, old, name, text, hit)

def replace_entry.go(+xs: List<&2, Draft>, +name: String, +text: String) -> List<&2, Draft> & Bool:
  match xs:
    case Nil{}:
      (Nil{}, False{})
    case Con{h, +t}:
      match h:
        case Draft{+stored, +old}:
          replace_entry.keep(replace_entry.go(t, name, text), stored, old, name, text, Irc.ieq(stored, name))

def set.grow(+rest: List<&2, Draft>, +name: String, +text: String, replaced: Bool) -> List<&2, Draft>:
  match replaced:
    case True{}:
      rest
    case False{}:
      Draft{name, text} <> rest

def set.append(pair: List<&2, Draft> & Bool, +name: String, +text: String) -> List<&2, Draft>:
  match pair:
    case (+rest, +replaced):
      set.grow(rest, name, text, replaced)

def set.stored(+entries: List<&2, Draft>, +name: String, +text: String) -> List<&2, Draft>:
  set.append(replace_entry.go(entries, name, text), name, text)

def set.admit(fits_text: Bool, +ds: Drafts, +name: String) -> Bool:
  match fits_text:
    case False{}:
      False{}
    case True{}:
      has(ds, name) || Nat.is_lt(count(ds), ENTRY_CAP())

def set.replace.stored(+entries: List<&2, Draft>, +name: String, +text: String, admitted: Bool) -> Drafts:
  match admitted:
    case False{}:
      Drafts{entries}
    case True{}:
      Drafts{set.stored(entries, name, text)}

def set.replace(+ds: Drafts, +name: String, +text: String, admitted: Bool) -> Drafts:
  match ds:
    case Drafts{+entries}:
      set.replace.stored(entries, name, text, admitted)

def set.named(+ds: Drafts, +name: String, +text: String, empty: Bool) -> Drafts:
  match empty:
    case True{}:
      clear(ds, name)
    case False{}:
      set.replace(ds, name, text, set.admit(fits(text), ds, name))

def set(+ds: Drafts, +raw: String, +text: String) -> Drafts:
  +name = Cl.target_name(raw)
  set.named(ds, name, text, String.is_empty(name) || String.is_empty(text))

def set_ok.named(+ds: Drafts, +name: String, +text: String, empty: Bool) -> Bool:
  match empty:
    case True{}:
      True{}
    case False{}:
      set.admit(fits(text), ds, name)

def set_ok(+ds: Drafts, +raw: String, +text: String) -> Bool:
  +name = Cl.target_name(raw)
  set_ok.named(ds, name, text, String.is_empty(name) || String.is_empty(text))

# ---- rename / close / prune -------------------------------------------
# Rename mirrors feed_nick: the draft follows an accepted query rename, and
# an existing draft under the new name wins over the moved one, like the
# coalesced buffer keeps its surviving head. Close drops the entry.
# `retain` prunes drafts for buffers that no longer exist, including the
# server buffer at index 0 which buf_find skips.

def rename.occupied(+ds: Drafts, +to: String, +text: String, occupied: Bool) -> Drafts:
  match occupied:
    case True{}:
      ds
    case False{}:
      set(ds, to, text)

def rename.place(+ds: Drafts, +to: String, +text: String) -> Drafts:
  rename.occupied(ds, to, text, has(ds, to))

def rename.carry(+ds: Drafts, +from: String, +to: String, carried: Maybe<&2, String>) -> Drafts:
  match carried:
    case None{}:
      ds
    case Some{+text}:
      rename.place(clear(ds, from), to, text)

def rename.move(+ds: Drafts, +from: String, +to: String, allowed: Bool) -> Drafts:
  match allowed:
    case False{}:
      ds
    case True{}:
      rename.carry(ds, from, to, find_entry(ds, from))

def rename(+ds: Drafts, +from_raw: String, +to_raw: String) -> Drafts:
  rename.move(ds, Cl.target_name(from_raw), Cl.target_name(to_raw), Cl.nick_rename_allowed(from_raw, to_raw))

def resident.or(+tail: Bool, hit: Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      tail

def resident(+bufs: List<&2, Cl.Buffer>, +name: String) -> Bool:
  match bufs:
    case Nil{}:
      False{}
    case Con{h, +t}:
      match h:
        case Cl.Buffer{+n, _, _, _, _, _}:
          resident.or(resident(t, name), Irc.ieq(n, name))

def retain_entry.keep(+rest: List<&2, Draft>, +name: String, +text: String, keep: Bool) -> List<&2, Draft>:
  match keep:
    case True{}:
      Draft{name, text} <> rest
    case False{}:
      rest

def retain_entry.go(xs: List<&2, Draft>, +cl: Cl.Client) -> List<&2, Draft>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, +t}:
      match h:
        case Draft{+name, +text}:
          retain_entry.keep(retain_entry.go(t, cl), name, text, resident(Cl.client_bufs(cl), name))

def retain(+ds: Drafts, +cl: Cl.Client) -> Drafts:
  match ds:
    case Drafts{+entries}:
      Drafts{retain_entry.go(entries, cl)}

# ---- focus ------------------------------------------------------------
# Stash the outgoing buffer text, then load the incoming buffer text.
# The integrator calls this before tab, click, and split-focus moves.

def focus(+ds: Drafts, +cur: String, +cur_text: String, +next: String) -> Drafts & String:
  +stashed = set(ds, cur, cur_text)
  (stashed, get(stashed, next))

# ---- routing ----------------------------------------------------------

def route.tail(+one: String, +rest: List<&2, String>) -> Route:
  match rest:
    case Nil{}:
      RouteSingle{one}
    case Con{+h, +t}:
      RouteMulti{one <> h <> t}

def route.multi(+lines: List<&2, String>) -> Route:
  match lines:
    case Nil{}:
      RouteEmpty{}
    case Con{+one, +rest}:
      route.tail(one, rest)

def route(+text: String) -> Route:
  route.multi(nonempty(split_lines(text)))

# ---- multiline wire plan ----------------------------------------------
# One wire chunk list per composition line, in order. Any command-looking,
# unframable, or unchunkable line rejects the whole plan, as does an empty
# composition. Credential lines reuse the single-message rule: they must
# fit one chunk and are never split.

def command_line(+line: String) -> Bool:
  String.starts_with(Irc.drop_spaces(Irc.strip_ctl(line)), "/")

def any_command.or(+tail: Bool, hit: Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      tail

def any_command(+xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+h, +t}:
      any_command.or(any_command(t), command_line(h))

def wire_each(+xs: List<&2, String>, +target: String, +notice: Bool) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+body, +t}:
      Sub.message_wire(target, body, notice) <> wire_each(t, target, notice)

def plan_line.wires(chunks: Maybe<&2, List<&2, String>>, +target: String, +notice: Bool) -> Maybe<&2, List<&2, String>>:
  match chunks:
    case None{}:
      None{}
    case Some{+xs}:
      Some{wire_each(xs, target, notice)}

def plan_line.valid(valid: Bool, +cl: Cl.Client, +name: String, +clean: String, +notice: Bool, +overhead: Nat) -> Maybe<&2, List<&2, String>>:
  match valid:
    case False{}:
      None{}
    case True{}:
      plan_line.wires(Sub.message_parts(Sub.message_sensitive(cl, name, clean, notice), clean, Nat.sub(Irc.LINE_MAX(), overhead)), name, notice)

def plan_line(+cl: Cl.Client, +target: String, +body: String, +notice: Bool) -> Maybe<&2, List<&2, String>>:
  +clean = Irc.strip_ctl(body)
  +name = Cl.target_name(target)
  +overhead = Irc.utf8_len(Sub.message_wire(name, "", notice))
  plan_line.valid(Commands.word(name) && Commands.framing(clean) && Nat.is_lt(overhead, Irc.LINE_MAX()), cl, name, clean, notice, overhead)

def plan_each.ok(+tail: Maybe<&2, List<&2, String>>, +head: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match tail:
    case None{}:
      None{}
    case Some{+rest}:
      Some{List.append(&2, String, head, rest)}

def plan_each.head(+tail: Maybe<&2, List<&2, String>>, +head: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match head:
    case None{}:
      None{}
    case Some{+wires}:
      plan_each.ok(tail, wires)

def plan_each.combine(+tail: Maybe<&2, List<&2, String>>, +cl: Cl.Client, +line: String, +target: String, +notice: Bool) -> Maybe<&2, List<&2, String>>:
  plan_each.head(tail, plan_line(cl, target, line, notice))

def plan_each.go(fuel: Nat, +cl: Cl.Client, xs: List<&2, String>, +target: String, +notice: Bool) -> Maybe<&2, List<&2, String>>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match xs:
        case Nil{}:
          Some{Nil{}}
        case Con{+line, +t}:
          plan_each.combine(plan_each.go(p, cl, t, target, notice), cl, line, target, notice)

def plan_each(+cl: Cl.Client, +xs: List<&2, String>, +target: String, +notice: Bool) -> Maybe<&2, List<&2, String>>:
  plan_each.go(Nat.add(1n, List.length(&2, String, xs)), cl, xs, target, notice)

def plan.gated(+cl: Cl.Client, +target: String, +lines: List<&2, String>, +notice: Bool, none: Bool) -> Maybe<&2, List<&2, String>>:
  match none:
    case True{}:
      None{}
    case False{}:
      plan_each(cl, lines, target, notice)

def plan.lines(+cl: Cl.Client, +target: String, +lines: List<&2, String>, +notice: Bool, blocked: Bool) -> Maybe<&2, List<&2, String>>:
  match blocked:
    case True{}:
      None{}
    case False{}:
      plan.gated(cl, target, lines, notice, List.is_empty(&2, String, lines))

def plan(+cl: Cl.Client, +target: String, +text: String, +notice: Bool) -> Maybe<&2, List<&2, String>>:
  +lines = nonempty(split_lines(text))
  plan.lines(cl, target, lines, notice, any_command(lines))

# ---- multiline submit -------------------------------------------------
# Pre-validated by the same plan, so every line sends; a rejected plan
# echoes one reason instead of a partial send. Empty input stays a no-op
# like EmptyInput.

def submit_each.step(pair: Cl.Client & List<&2, String>, k: Cl.Client -> List<&2, String> -> Cl.Client & List<&2, String>) -> Cl.Client & List<&2, String>:
  match pair:
    case (+cl2, +outs):
      k(cl2, outs)

def submit_each.join(pair: Cl.Client & List<&2, String>, +outs: List<&2, String>) -> Cl.Client & List<&2, String>:
  match pair:
    case (+cl3, +rest):
      (cl3, List.append(&2, String, outs, rest))

def submit_each.go(fuel: Nat, +cl: Cl.Client, +bi: Nat, xs: List<&2, String>, +target: String, +notice: Bool) -> Cl.Client & List<&2, String>:
  match fuel:
    case 0n:
      (cl, Nil{})
    case 1n+p:
      match xs:
        case Nil{}:
          (cl, Nil{})
        case Con{+line, +t}:
          submit_each.step(Sub.send_text(cl, bi, target, line, notice),
            cl2 => outs => submit_each.join(submit_each.go(p, cl2, bi, t, target, notice), outs))

def submit_each(+cl: Cl.Client, +bi: Nat, +xs: List<&2, String>, +target: String, +notice: Bool) -> Cl.Client & List<&2, String>:
  submit_each.go(Nat.add(1n, List.length(&2, String, xs)), cl, bi, xs, target, notice)

def wires_ready(+wires: Maybe<&2, List<&2, String>>) -> Bool:
  match wires:
    case None{}:
      False{}
    case Some{_}:
      True{}

def submit_ready(+cl: Cl.Client, +target: String, +lines: List<&2, String>, +notice: Bool) -> Bool:
  Bool.not(any_command(lines)) && wires_ready(plan_each(cl, lines, target, notice))

def first_bad.line(+line: String, +tail: Maybe<&2, String>, head_ok: Bool) -> Maybe<&2, String>:
  match head_ok:
    case True{}:
      tail
    case False{}:
      Some{line}

def first_bad.go(fuel: Nat, +cl: Cl.Client, xs: List<&2, String>, +target: String, +notice: Bool) -> Maybe<&2, String>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match xs:
        case Nil{}:
          None{}
        case Con{+line, +t}:
          first_bad.line(line, first_bad.go(p, cl, t, target, notice), wires_ready(plan_line(cl, target, line, notice)))

def first_bad(+cl: Cl.Client, +xs: List<&2, String>, +target: String, +notice: Bool) -> Maybe<&2, String>:
  first_bad.go(Nat.add(1n, List.length(&2, String, xs)), cl, xs, target, notice)

def reject_reason.sensitive(sensitive: Bool) -> String:
  match sensitive:
    case True{}:
      "credential command exceeds IRC line limit"
    case False{}:
      "message cluster exceeds IRC line limit"

def reject_reason.bad(bad: Maybe<&2, String>, +cl: Cl.Client, +target: String, +notice: Bool) -> String:
  match bad:
    case None{}:
      "message cluster exceeds IRC line limit"
    case Some{+line}:
      reject_reason.sensitive(Sub.message_sensitive(cl, Cl.target_name(target), Irc.strip_ctl(line), notice))

def reject_reason.command(command: Bool, +cl: Cl.Client, +target: String, +lines: List<&2, String>, +notice: Bool) -> String:
  match command:
    case True{}:
      "multiline commands are not sent"
    case False{}:
      reject_reason.bad(first_bad(cl, lines, target, notice), cl, target, notice)

def reject_reason_lines(+cl: Cl.Client, +target: String, +lines: List<&2, String>, +notice: Bool) -> String:
  reject_reason.command(any_command(lines), cl, target, lines, notice)

def submit_lines.gated(+cl: Cl.Client, +bi: Nat, +target: String, +lines: List<&2, String>, +notice: Bool, ready: Bool) -> Cl.Client & List<&2, String>:
  match ready:
    case True{}:
      submit_each(cl, bi, lines, target, notice)
    case False{}:
      (Sub.echo_err(cl, reject_reason_lines(cl, target, lines, notice)), Nil{})

def submit_lines.empty(+cl: Cl.Client, +bi: Nat, +target: String, +lines: List<&2, String>, +notice: Bool, none: Bool) -> Cl.Client & List<&2, String>:
  match none:
    case True{}:
      (cl, Nil{})
    case False{}:
      submit_lines.gated(cl, bi, target, lines, notice, submit_ready(cl, target, lines, notice))

def submit_lines(+cl: Cl.Client, +bi: Nat, +target: String, +text: String, +notice: Bool) -> Cl.Client & List<&2, String>:
  +lines = nonempty(split_lines(text))
  submit_lines.empty(cl, bi, target, lines, notice, List.is_empty(&2, String, lines))

# ---- modal ------------------------------------------------------------
# A pending modal (upload consent) blocks Enter in session; the typed text
# is still stashed per buffer so focus moves cannot lose it. The warning
# itself never replaces a draft.

def stash_modal(+ds: Drafts, +name: String, +typed: String) -> Drafts:
  set(ds, name, typed)

def after_submit(+ds: Drafts, +name: String) -> Drafts:
  clear(ds, name)

# ---- proof-facing predicates ------------------------------------------

def roundtrip_ok() -> Bool:
  String.eq(get(set(empty(), "#room", "hi"), "#room"), "hi")

def missing_ok() -> Bool:
  String.eq(get(empty(), "#room"), "")

def rename_ok() -> Bool:
  +moved = rename(set(empty(), "alice", "hi"), "alice", "bob")
  String.eq(get(moved, "bob"), "hi") && Bool.not(has(moved, "alice"))

def overcap_ok() -> Bool:
  String.eq(get(set(empty(), "#room", Irc.stars.go(4097n)), "#room"), "")

def split_ok() -> Bool:
  String.eq(String.join(split_lines("a\r\nb\rc\nd"), "|"), "a|b|c|d")

def route_single_ok(+r: Route) -> Bool:
  match r:
    case RouteEmpty{}:
      False{}
    case RouteSingle{+line}:
      String.eq(line, "hi")
    case RouteMulti{_}:
      False{}

def route_ok() -> Bool:
  route_single_ok(route("hi"))

def plan_bounded.got(+wires: Maybe<&2, List<&2, String>>) -> Bool:
  match wires:
    case None{}:
      False{}
    case Some{+xs}:
      Sub.out_all_ok(xs) && Nat.is_eq(List.length(&2, String, xs), 2n)

def plan_ok() -> Bool:
  plan_bounded.got(plan(Cl.init("me", "s"), "#room", "hi\nyo", False{}))

def plan_none.got(+wires: Maybe<&2, List<&2, String>>) -> Bool:
  match wires:
    case None{}:
      True{}
    case Some{_}:
      False{}

def command_rejected_ok() -> Bool:
  plan_none.got(plan(Cl.init("me", "s"), "#room", "/join #x\nhi", False{}))

def focus.get(pair: Drafts & String, +name: String, +want: String) -> Bool:
  match pair:
    case (+ds, +loaded):
      String.eq(get(ds, name), want) && String.eq(loaded, "")

def focus_ok() -> Bool:
  focus.get(focus(set(empty(), "#a", "aa"), "#a", "aa2", "#b"), "#a", "aa2")

def entry_cap_ok() -> Bool:
  Nat.is_eq(ENTRY_CAP(), Cl.MAX_BUFFERS())
