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
import ./irc_commands.bend as Commands
import ./submit.bend as Sub
import ./split.bend as Sp
import ./server_key.bend as Key

type Draft is Data:
  Draft{server: Key.ServerId, name: String, text: String}

# Canonical buffer identity. The control buffer is "*server*" exactly like
# Split.name_at(cl, 0n) (pinned by the control-key test); every other buffer
# keeps target_name. A peer query named "server" therefore never collides
# with the control draft. Callers pass Split.name_at(cl, i) for resolved
# buffers, or key_of for typed names with an explicit control flag.
def key_of(control: Bool, +raw: String) -> String:
  match control:
    case True{}: "*server*"
    case False{}: Cl.target_name(raw)

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
# Lookup folds names under a caller-supplied CASEMAPPING through the shared
# Cl.buf_eq_cm, so a draft follows the buffer it was typed in on every map:
# under ascii, #a[ and #a{ hold distinct drafts; under the default map they
# stay one entry like buf_find. Keys are canonical (key_of) and
# server-scoped: (server, "*server*") is the control draft, (server,
# "server") a peer query, and different servers never share entries. An
# empty text clears the entry instead of storing a blank draft. The plain
# entry points delegate with Cl.dflt_cm(); session paths call the _cm
# variants with Sess.session_cm. One store, one comparison core per op.

def find_entry.rest(cont: Maybe<&2, String>, +text: String, hit: Bool) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{text}
    case False{}:
      cont

def find_entry_cm.go(xs: List<&2, Draft>, +server: Key.ServerId, +key: String, +cm: String) -> Maybe<&2, String>:
  match xs:
    case Nil{}:
      None{}
    case Con{h, +t}:
      match h:
        case Draft{+srv, +stored, +text}:
          +cont = find_entry_cm.go(t, server, key, cm)
          find_entry.rest(cont, text, Key.eq(srv, server) && Cl.buf_eq_cm(cm, stored, key))

def find_entry_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +cm: String) -> Maybe<&2, String>:
  match ds:
    case Drafts{+entries}:
      find_entry_cm.go(entries, server, key, cm)

def find_entry(+ds: Drafts, +server: Key.ServerId, +key: String) -> Maybe<&2, String>:
  find_entry_cm(ds, server, key, Cl.dflt_cm())

def get.on(found: Maybe<&2, String>) -> String:
  match found:
    case None{}:
      ""
    case Some{+text}:
      text

def get_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +cm: String) -> String:
  get.on(find_entry_cm(ds, server, key, cm))

def get(+ds: Drafts, +server: Key.ServerId, +key: String) -> String:
  get_cm(ds, server, key, Cl.dflt_cm())

def has.on(found: Maybe<&2, String>) -> Bool:
  match found:
    case None{}:
      False{}
    case Some{_}:
      True{}

def has_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +cm: String) -> Bool:
  has.on(find_entry_cm(ds, server, key, cm))

def has(+ds: Drafts, +server: Key.ServerId, +key: String) -> Bool:
  has_cm(ds, server, key, Cl.dflt_cm())

def remove_entry.keep(+rest: List<&2, Draft>, +srv: Key.ServerId, +stored: String, +text: String, hit: Bool) -> List<&2, Draft>:
  match hit:
    case True{}:
      rest
    case False{}:
      Draft{srv, stored, text} <> rest

def remove_entry_cm.go(xs: List<&2, Draft>, +server: Key.ServerId, +key: String, +cm: String) -> List<&2, Draft>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, +t}:
      match h:
        case Draft{+srv, +stored, +text}:
          remove_entry.keep(remove_entry_cm.go(t, server, key, cm), srv, stored, text, Key.eq(srv, server) && Cl.buf_eq_cm(cm, stored, key))

def clear_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +cm: String) -> Drafts:
  match ds:
    case Drafts{+entries}:
      Drafts{remove_entry_cm.go(entries, server, key, cm)}

def clear(+ds: Drafts, +server: Key.ServerId, +key: String) -> Drafts:
  clear_cm(ds, server, key, Cl.dflt_cm())

def drop_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +cm: String) -> Drafts:
  clear_cm(ds, server, key, cm)

def drop(+ds: Drafts, +server: Key.ServerId, +key: String) -> Drafts:
  drop_cm(ds, server, key, Cl.dflt_cm())

def replace_entry.picked(+rest: List<&2, Draft>, replaced: Bool, +srv: Key.ServerId, +stored: String, +old: String, +server: Key.ServerId, +key: String, +text: String, hit: Bool) -> List<&2, Draft> & Bool:
  match hit:
    case True{}:
      (Draft{server, key, text} <> rest, True{})
    case False{}:
      (Draft{srv, stored, old} <> rest, replaced)

def replace_entry.keep(pair: List<&2, Draft> & Bool, +srv: Key.ServerId, +stored: String, +old: String, +server: Key.ServerId, +key: String, +text: String, hit: Bool) -> List<&2, Draft> & Bool:
  match pair:
    case (+rest, +replaced):
      replace_entry.picked(rest, replaced, srv, stored, old, server, key, text, hit)

def replace_entry_cm.go(+xs: List<&2, Draft>, +server: Key.ServerId, +key: String, +text: String, +cm: String) -> List<&2, Draft> & Bool:
  match xs:
    case Nil{}:
      (Nil{}, False{})
    case Con{h, +t}:
      match h:
        case Draft{+srv, +stored, +old}:
          replace_entry.keep(replace_entry_cm.go(t, server, key, text, cm), srv, stored, old, server, key, text, Key.eq(srv, server) && Cl.buf_eq_cm(cm, stored, key))

def set.grow(+rest: List<&2, Draft>, +server: Key.ServerId, +key: String, +text: String, replaced: Bool) -> List<&2, Draft>:
  match replaced:
    case True{}:
      rest
    case False{}:
      Draft{server, key, text} <> rest

def set_cm.append(pair: List<&2, Draft> & Bool, +server: Key.ServerId, +key: String, +text: String) -> List<&2, Draft>:
  match pair:
    case (+rest, +replaced):
      set.grow(rest, server, key, text, replaced)

def set_cm.stored(+entries: List<&2, Draft>, +server: Key.ServerId, +key: String, +text: String, +cm: String) -> List<&2, Draft>:
  set_cm.append(replace_entry_cm.go(entries, server, key, text, cm), server, key, text)

def count_server.hit(+tail: Nat, hit: Bool) -> Nat:
  match hit:
    case True{}:
      Nat.add(tail, 1n)
    case False{}:
      tail

def count_server.go(xs: List<&2, Draft>, +server: Key.ServerId, +n: Nat) -> Nat:
  match xs:
    case Nil{}:
      n
    case Con{h, +t}:
      match h:
        case Draft{+srv, _, _}:
          count_server.hit(count_server.go(t, server, n), Key.eq(srv, server))

def count_server(+ds: Drafts, +server: Key.ServerId) -> Nat:
  match ds:
    case Drafts{+entries}:
      count_server.go(entries, server, 0n)

def set_cm.admit(fits_text: Bool, +ds: Drafts, +server: Key.ServerId, +key: String, +cm: String) -> Bool:
  match fits_text:
    case False{}:
      False{}
    case True{}:
      has_cm(ds, server, key, cm) || Nat.is_lt(count_server(ds, server), ENTRY_CAP())

def set_cm.replace.stored(+entries: List<&2, Draft>, +server: Key.ServerId, +key: String, +text: String, +cm: String, admitted: Bool) -> Drafts:
  match admitted:
    case False{}:
      Drafts{entries}
    case True{}:
      Drafts{set_cm.stored(entries, server, key, text, cm)}

def set_cm.replace(+ds: Drafts, +server: Key.ServerId, +key: String, +text: String, +cm: String, admitted: Bool) -> Drafts:
  match ds:
    case Drafts{+entries}:
      set_cm.replace.stored(entries, server, key, text, cm, admitted)

def set_cm.named(+ds: Drafts, +server: Key.ServerId, +key: String, +text: String, +cm: String, empty: Bool) -> Drafts:
  match empty:
    case True{}:
      clear_cm(ds, server, key, cm)
    case False{}:
      set_cm.replace(ds, server, key, text, cm, set_cm.admit(fits(text), ds, server, key, cm))

# Public admission validates the server first: an invalid id admits nothing
# and changes nothing, so invalid/huge ids cannot each smuggle in a full
# store beside the four valid servers.
def set_cm.valid(+ds: Drafts, +server: Key.ServerId, +key: String, +text: String, +cm: String, ok: Bool) -> Drafts:
  match ok:
    case True{}:
      set_cm.named(ds, server, key, text, cm, String.is_empty(key) || String.is_empty(text))
    case False{}:
      ds

def set_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +text: String, +cm: String) -> Drafts:
  set_cm.valid(ds, server, key, text, cm, Key.valid(server))

def set(+ds: Drafts, +server: Key.ServerId, +key: String, +text: String) -> Drafts:
  set_cm(ds, server, key, text, Cl.dflt_cm())

def set_ok_cm.named(+ds: Drafts, +server: Key.ServerId, +key: String, +text: String, +cm: String, empty: Bool) -> Bool:
  match empty:
    case True{}:
      True{}
    case False{}:
      set_cm.admit(fits(text), ds, server, key, cm)

def set_ok_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +text: String, +cm: String) -> Bool:
  Key.valid(server) && set_ok_cm.named(ds, server, key, text, cm, String.is_empty(key) || String.is_empty(text))

def set_ok(+ds: Drafts, +server: Key.ServerId, +key: String, +text: String) -> Bool:
  set_ok_cm(ds, server, key, text, Cl.dflt_cm())

# ---- rename / close / prune -------------------------------------------
# Rename mirrors feed_nick_with.query: the draft follows an accepted *query*
# rename only. Both ends must satisfy the shared query-source predicate,
# so channel drafts never move and the control draft ("*server*") is never
# a rename party. An existing draft under the new name wins over the moved
# one, like the coalesced buffer keeps its surviving head. Close drops the
# entry. `retain` prunes same-server drafts for buffers that no longer
# exist; residency uses Split.name_at, so index 0 resolves to "*server*".

# Negotiated NICK-to-draft rename: rename_cm below is the parameterized
# owner; every lookup, clear, and store folds under the caller-supplied
# CASEMAPPING through the shared _cm store core (Cl.buf_eq_cm), so
# ascii-distinct drafts never merge. The fixed rename chain delegates with
# Cl.dflt_cm(). rename_nick.line_cm is the per-line NICK owner mirroring
# Split.rename_query.line_cm: Irc parse, NICK command check, the shared
# nick_rename_allowed gate, and target_name ends.
def rename_cm.occupied(+ds: Drafts, +server: Key.ServerId, +to: String, +text: String, occupied: Bool, +cm: String) -> Drafts:
  match occupied:
    case True{}:
      ds
    case False{}:
      set_cm(ds, server, to, text, cm)

def rename_cm.place(+ds: Drafts, +server: Key.ServerId, +to: String, +text: String, +cm: String) -> Drafts:
  rename_cm.occupied(ds, server, to, text, has_cm(ds, server, to, cm), cm)

def rename_cm.carry(+ds: Drafts, +server: Key.ServerId, +from: String, +to: String, carried: Maybe<&2, String>, +cm: String) -> Drafts:
  match carried:
    case None{}:
      ds
    case Some{+text}:
      rename_cm.place(clear_cm(ds, server, from, cm), server, to, text, cm)

def rename_cm.move(+ds: Drafts, +server: Key.ServerId, +from: String, +to: String, allowed: Bool, +cm: String) -> Drafts:
  match allowed:
    case False{}:
      ds
    case True{}:
      rename_cm.carry(ds, server, from, to, find_entry_cm(ds, server, from, cm), cm)

def rename_cm(+ds: Drafts, +server: Key.ServerId, +from_key: String, +to_key: String, +cm: String) -> Drafts:

  rename_cm.move(ds, server, from_key, to_key,
    Cl.is_query_name(from_key) && Cl.is_query_name(to_key) && Cl.nick_rename_allowed(from_key, to_key), cm)

# Per-line NICK rename effect carried from the live fold: the fold emits
# (from, to) under the per-line CM for each accepted live NICK (claimed,
# unregistered, consumed, and ceiling-reverted lines emit nothing).
# apply_renames folds rename_cm in arrival order; missing keys no-op.
type NickRename is Data:
  NickRename{from: String, to: String, cm: String}

def apply_renames.go(+xs: List<&2, NickRename>, +ds: Drafts, +server: Key.ServerId) -> Drafts:
  match xs:
    case Nil{}: ds
    case Con{+e, +t}:
      match e:
        case NickRename{+from, +to, +cm}: apply_renames.go(t, rename_cm(ds, server, from, to, cm), server)

def apply_renames(+ds: Drafts, +server: Key.ServerId, +xs: List<&2, NickRename>) -> Drafts:
  apply_renames.go(xs, ds, server)

def rename.occupied(+ds: Drafts, +server: Key.ServerId, +to: String, +text: String, occupied: Bool) -> Drafts:
  rename_cm.occupied(ds, server, to, text, occupied, Cl.dflt_cm())

def rename.place(+ds: Drafts, +server: Key.ServerId, +to: String, +text: String) -> Drafts:
  rename_cm.place(ds, server, to, text, Cl.dflt_cm())

def rename.carry(+ds: Drafts, +server: Key.ServerId, +from: String, +to: String, carried: Maybe<&2, String>) -> Drafts:
  rename_cm.carry(ds, server, from, to, carried, Cl.dflt_cm())

def rename.move(+ds: Drafts, +server: Key.ServerId, +from: String, +to: String, allowed: Bool) -> Drafts:
  rename_cm.move(ds, server, from, to, allowed, Cl.dflt_cm())

def rename(+ds: Drafts, +server: Key.ServerId, +from_key: String, +to_key: String) -> Drafts:
  rename_cm(ds, server, from_key, to_key, Cl.dflt_cm())

def rename_nick.accepted_cm(+ds: Drafts, +server: Key.ServerId, +from: String, +to: String, allowed: Bool, +cm: String) -> Drafts:
  match allowed:
    case False{}:
      ds
    case True{}:
      rename_cm(ds, server, from, to, cm)

def rename_nick.nick_cm(+ds: Drafts, +server: Key.ServerId, nick: Bool, +m: Irc.Message, +cm: String) -> Drafts:
  match nick:
    case False{}:
      ds
    case True{}:
      rename_nick.accepted_cm(ds, server, Cl.target_name(Irc.msg_nick(m)), Cl.target_name(Irc.msg_param(m, 0n)), Cl.nick_rename_allowed(Irc.msg_nick(m), Irc.msg_param(m, 0n)), cm)

def rename_nick.parsed_cm(+ds: Drafts, +server: Key.ServerId, m: Maybe<&2, Irc.Message>, +cm: String) -> Drafts:
  match m:
    case None{}:
      ds
    case Some{+msg}:
      rename_nick.nick_cm(ds, server, Irc.ieq(Irc.msg_command(msg), "NICK"), msg, cm)

def rename_nick.line_cm(+ds: Drafts, +server: Key.ServerId, +line: String, +cm: String) -> Drafts:
  rename_nick.parsed_cm(ds, server, Irc.parse(line), cm)

def rename_nick.line(+ds: Drafts, +server: Key.ServerId, +line: String) -> Drafts:
  rename_nick.line_cm(ds, server, line, Cl.dflt_cm())

def rename_nicks_cm.go(lines: List<&2, String>, +ds: Drafts, +server: Key.ServerId, +cm: String) -> Drafts:
  match lines:
    case Nil{}:
      ds
    case Con{+h, +t}:
      rename_nicks_cm.go(t, rename_nick.line_cm(ds, server, h, cm), server, cm)

def rename_nicks_cm(+ds: Drafts, +server: Key.ServerId, +lines: List<&2, String>, +cm: String) -> Drafts:
  rename_nicks_cm.go(lines, ds, server, cm)

def rename_nicks(+ds: Drafts, +server: Key.ServerId, +lines: List<&2, String>) -> Drafts:
  rename_nicks_cm(ds, server, lines, Cl.dflt_cm())

def resident.go(+cl: Cl.Client, bufs: List<&2, Cl.Buffer>, +i: Nat, +key: String) -> Bool:
  match bufs:
    case Nil{}:
      False{}
    case Con{_, +t}:
      Irc.ieq(Sp.name_at(cl, i), key) || resident.go(cl, t, Nat.add(i, 1n), key)

def resident(+cl: Cl.Client, +key: String) -> Bool:
  resident.go(cl, Cl.client_bufs(cl), 0n, key)

def retain_entry.keep(+rest: List<&2, Draft>, +srv: Key.ServerId, +name: String, +text: String, keep: Bool) -> List<&2, Draft>:
  match keep:
    case True{}:
      Draft{srv, name, text} <> rest
    case False{}:
      rest

def retain_entry.go(xs: List<&2, Draft>, +server: Key.ServerId, +cl: Cl.Client) -> List<&2, Draft>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, +t}:
      match h:
        case Draft{+srv, +name, +text}:
          retain_entry.keep(retain_entry.go(t, server, cl), srv, name, text,
            Bool.not(Key.eq(srv, server)) || resident(cl, name))

def retain(+ds: Drafts, +server: Key.ServerId, +cl: Cl.Client) -> Drafts:
  match ds:
    case Drafts{+entries}:
      Drafts{retain_entry.go(entries, server, cl)}

# Endpoint/slot replacement drops that server's drafts: a ServerId alone is
# not an endpoint identity, so a replaced slot must not inherit the old
# room's composers. Same-endpoint reconnects retain drafts. Other servers'
# entries are never touched.
def replace_endpoint.keep(+rest: List<&2, Draft>, +srv: Key.ServerId, +name: String, +text: String, drop: Bool) -> List<&2, Draft>:
  match drop:
    case True{}:
      rest
    case False{}:
      Draft{srv, name, text} <> rest

def replace_endpoint.go(xs: List<&2, Draft>, +server: Key.ServerId, +same: Bool) -> List<&2, Draft>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, +t}:
      match h:
        case Draft{+srv, +name, +text}:
          replace_endpoint.keep(replace_endpoint.go(t, server, same), srv, name, text,
            Key.eq(srv, server) && Bool.not(same))

def replace_endpoint(+ds: Drafts, +server: Key.ServerId, same_endpoint: Bool) -> Drafts:
  match ds:
    case Drafts{+entries}:
      Drafts{replace_endpoint.go(entries, server, same_endpoint)}

# ---- focus ------------------------------------------------------------
# Stash the outgoing buffer text, then load the incoming buffer text.
# The integrator calls this before tab, click, and split-focus moves.
# A stash the store rejects (over-byte, over-line, full) is preserved:
# the store stays unchanged and the composer keeps the typed text
# instead of loading the next draft.

# Shared admission check for focus moves: Session changes the active buffer
# only when this admits. A rejected save keeps the old active buffer while
# the composer keeps the typed text, so the old composer can never be sent
# in the new room.
def focus_admits_cm(+ds: Drafts, +server: Key.ServerId, +cur: String, +cur_text: String, +cm: String) -> Bool:
  Key.valid(server) && (String.is_empty(cur_text) || set_ok_cm(ds, server, cur, cur_text, cm))

def focus_admits(+ds: Drafts, +server: Key.ServerId, +cur: String, +cur_text: String) -> Bool:
  focus_admits_cm(ds, server, cur, cur_text, Cl.dflt_cm())

def focus_cm.kept(+ds: Drafts, +server: Key.ServerId, +cur: String, +cur_text: String, +next: String, +cm: String, keep: Bool) -> Drafts & String:
  match keep:
    case True{}:
      (ds, cur_text)
    case False{}:
      +stashed = set_cm(ds, server, cur, cur_text, cm)
      (stashed, get_cm(stashed, server, next, cm))

def focus_cm(+ds: Drafts, +server: Key.ServerId, +cur: String, +cur_text: String, +next: String, +cm: String) -> Drafts & String:
  focus_cm.kept(ds, server, cur, cur_text, next, cm, Bool.not(focus_admits_cm(ds, server, cur, cur_text, cm)))

def focus(+ds: Drafts, +server: Key.ServerId, +cur: String, +cur_text: String, +next: String) -> Drafts & String:
  focus_cm(ds, server, cur, cur_text, next, Cl.dflt_cm())

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

# Planning uses the one shared Sub.text_valid with the raw line, so a NUL
# anywhere rejects the whole send instead of silently shipping a stripped
# line while send_text would report a different cause.
def plan_line(+cl: Cl.Client, +target: String, +body: String, +notice: Bool) -> Maybe<&2, List<&2, String>>:
  +clean = Irc.strip_ctl(body)
  +name = Cl.target_name(target)
  +overhead = Irc.utf8_len(Sub.message_wire(name, "", notice))
  plan_line.valid(Sub.text_valid(target, body, notice), cl, name, clean, notice, overhead)

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

def reject_reason.cause(caused: Bool, +target: String, +line: String, +cl: Cl.Client, +name: String, +clean: String, +notice: Bool) -> String:
  match caused:
    case False{}:
      Sub.text_reason(target, line, notice)
    case True{}:
      reject_reason.sensitive(Sub.message_sensitive(cl, name, clean, notice))

def reject_reason.bad(bad: Maybe<&2, String>, +cl: Cl.Client, +target: String, +notice: Bool) -> String:
  match bad:
    case None{}:
      "message cluster exceeds IRC line limit"
    case Some{+line}:
      +clean = Irc.strip_ctl(line)
      reject_reason.cause(Sub.text_valid(target, line, notice), target, line, cl, Cl.target_name(target), clean, notice)

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

# Synthetic targets (control, log) are read-only like submit_plain: the send
# is rejected with no wire output and the caller's draft stays untouched
# (after_submit runs only on accepted sends).
def submit_lines.synthetic(synth: Bool, +cl: Cl.Client, +bi: Nat, +target: String, +lines: List<&2, String>, +notice: Bool) -> Cl.Client & List<&2, String>:
  match synth:
    case True{}:
      (Sub.echo_err(cl, "read-only buffer"), Nil{})
    case False{}:
      submit_lines.empty(cl, bi, target, lines, notice, List.is_empty(&2, String, lines))

# The resolved pane gates like the target spelling: buffer 0 and
# read-only synthetic panes reject, mirroring submit_plain on the active
# buffer. A real nonzero pane keeps a peer query named "server" sendable.
def submit_lines.resolved(+cl: Cl.Client, +bi: Nat, +target: String, +lines: List<&2, String>, +notice: Bool, pane_ok: Bool) -> Cl.Client & List<&2, String>:
  match pane_ok:
    case True{}:
      submit_lines.synthetic(Cl.target_is_synthetic(Cl.target_name(target)), cl, bi, target, lines, notice)
    case False{}:
      (Sub.echo_err(cl, "read-only buffer"), Nil{})

def submit_lines(+cl: Cl.Client, +bi: Nat, +target: String, +text: String, +notice: Bool) -> Cl.Client & List<&2, String>:
  +lines = nonempty(split_lines(text))
  submit_lines.resolved(cl, bi, target, lines, notice,
    Bool.not(Nat.is_eq(bi, 0n)) && Bool.not(Cl.target_is_synthetic(Sp.name_at(cl, bi))))

# ---- modal ------------------------------------------------------------
# A pending modal (upload consent) blocks Enter in session; the typed text
# is still stashed per buffer so focus moves cannot lose it. The warning
# itself never replaces a draft.

def stash_modal_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +typed: String, +cm: String) -> Drafts:
  set_cm(ds, server, key, typed, cm)

def stash_modal(+ds: Drafts, +server: Key.ServerId, +key: String, +typed: String) -> Drafts:
  stash_modal_cm(ds, server, key, typed, Cl.dflt_cm())

def after_submit_cm(+ds: Drafts, +server: Key.ServerId, +key: String, +cm: String) -> Drafts:
  clear_cm(ds, server, key, cm)

def after_submit(+ds: Drafts, +server: Key.ServerId, +key: String) -> Drafts:
  after_submit_cm(ds, server, key, Cl.dflt_cm())

# ---- proof-facing predicates ------------------------------------------

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def roundtrip_ok() -> Bool:
  String.eq(get(set(empty(), s0(), "#room", "hi"), s0(), "#room"), "hi")

def missing_ok() -> Bool:
  String.eq(get(empty(), s0(), "#room"), "")

def rename_ok() -> Bool:
  +moved = rename(set(empty(), s0(), "alice", "hi"), s0(), "alice", "bob")
  +chan = rename(set(empty(), s0(), "#a", "x"), s0(), "#a", "#b")
  +ctl = rename(set(empty(), s0(), key_of(True{}, "server"), "c"), s0(), key_of(True{}, "server"), "bob")
  String.eq(get(moved, s0(), "bob"), "hi") && Bool.not(has(moved, s0(), "alice"))
    && String.eq(get(chan, s0(), "#a"), "x") && Bool.not(has(chan, s0(), "#b"))
    && String.eq(get(ctl, s0(), key_of(True{}, "server")), "c") && Bool.not(has(ctl, s0(), "bob"))

def rename_cm_ok() -> Bool:
  +ascii_ds = set_cm(set_cm(empty(), s0(), "a[b", "X", "ascii"), s0(), "a{b", "Y", "ascii")
  +ascii_moved = rename_cm(ascii_ds, s0(), "a[b", "c", "ascii")
  +rfc_moved = rename_cm(set(set(empty(), s0(), "a[b", "X"), s0(), "a{b", "Y"), s0(), "a[b", "c", "rfc1459")
  String.eq(get_cm(ascii_moved, s0(), "c", "ascii"), "X")
    && String.eq(get_cm(ascii_moved, s0(), "a{b", "ascii"), "Y")
    && Nat.is_eq(count(ascii_moved), 2n)
    && String.eq(get_cm(rfc_moved, s0(), "c", "rfc1459"), "Y")
    && Nat.is_eq(count(rfc_moved), 1n)
    && Bool.not(has_cm(rfc_moved, s0(), "a[b", "rfc1459"))

def coexist_ok() -> Bool:
  +ds = set(set(empty(), s0(), key_of(True{}, "server"), "C"), s0(), key_of(False{}, "server"), "Q")
  +moved = rename(ds, s0(), key_of(False{}, "server"), "bob")
  String.eq(get(ds, s0(), key_of(True{}, "server")), "C") && String.eq(get(ds, s0(), key_of(False{}, "server")), "Q")
    && String.eq(get(moved, s0(), "bob"), "Q") && String.eq(get(moved, s0(), key_of(True{}, "server")), "C")

def overcap_ok() -> Bool:
  String.eq(get(set(empty(), s0(), "#room", Irc.stars.go(4097n)), s0(), "#room"), "")

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

def focus.get(pair: Drafts & String, +key: String, +want: String) -> Bool:
  match pair:
    case (+ds, +loaded):
      String.eq(get(ds, s0(), key), want) && String.eq(loaded, "")

def focus.kept_ok(pair: Drafts & String, +key: String, +want: String, +typed: String) -> Bool:
  match pair:
    case (+ds, +loaded):
      String.eq(get(ds, s0(), key), want) && String.eq(loaded, typed)

def focus_ok() -> Bool:
  +big = Irc.stars.go(4097n)
  focus.get(focus(set(empty(), s0(), "#a", "aa"), s0(), "#a", "aa2", "#b"), "#a", "aa2")
    && focus.kept_ok(focus(set(empty(), s0(), "#a", "aa"), s0(), "#a", big, "#b"), "#a", "aa", big)
    && focus_admits(set(empty(), s0(), "#a", "aa"), s0(), "#a", "aa2")
    && Bool.not(focus_admits(set(empty(), s0(), "#a", "aa"), s0(), "#a", big))

def entry_cap_ok() -> Bool:
  Nat.is_eq(ENTRY_CAP(), Cl.MAX_BUFFERS())
