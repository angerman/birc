# SPDX-License-Identifier: Apache-2.0
# Dual-spine Buffer invariant: newest == reverse(lines) and count matches.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL

def line(+text: String, +id: Nat) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", text, "a", id}

def mismatched() -> Cl.Buffer:
  Cl.Buffer{"#t", True{}, "topic", line("a", 1n) <> line("b", 2n) <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}, line("a", 1n) <> Nil{}, 2n}

# Same ids and length as a valid reverse spine, but newest text differs.
def same_ids_diff_text() -> Cl.Buffer:
  Cl.Buffer{"#t", True{}, "topic", line("a", 1n) <> line("b", 2n) <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}, line("B", 2n) <> line("a", 1n) <> Nil{}, 2n}

def spines_controls() -> IO(Unit):
  +empty = Cl.empty_buf("#t", True{})
  +pushed = Cl.buf_push(empty, line("one", 1n), 100n)
  +pushed2 = Cl.buf_push(pushed, line("two", 2n), 100n)
  +topic = Cl.set_topic(pushed2, "hello")
  +nicked = Cl.nick_add(topic, "alice")
  do IO<Unit>:
    Unit <- E.must("empty spines ok", Cl.buf_spines_ok(empty))
    Unit <- E.must("append keeps spines", Cl.buf_spines_ok(pushed2))
    Unit <- E.must("topic meta keeps spines", Cl.buf_spines_ok(topic))
    Unit <- E.must("nick meta keeps spines", Cl.buf_spines_ok(nicked))
    Unit <- E.must("hand-built mismatch rejected", Bool.not(Cl.buf_spines_ok(mismatched())))
    Unit <- E.must("same ids different text rejected", Bool.not(Cl.buf_spines_ok(same_ids_diff_text())))
    IO.pure(Unit, Unit{})

def nick_roster() -> IO(Unit):
  +base = Cl.nick_add(Cl.nick_add(Cl.nick_add(Cl.empty_buf("#t", True{}), "@alice"), "+bob"), "carol")
  +stripped = Cl.nick_del(Cl.nick_del(base, "bob"), "@ALICE")
  +renamed = Cl.nick_rename(stripped, "carol", "@Dave")
  do IO<Unit>:
    Unit <- E.must_eq("nick strip sigils", Cl.nick_strip("@ops"), "ops")
    Unit <- E.must_eq("nick del keeps others", CL.buf_nicks.text(stripped), "carol ")
    Unit <- E.must_eq("nick rename swaps one", CL.buf_nicks.text(renamed), "Dave ")
    IO.pure(Unit, Unit{})

def channel_bit(b: Cl.Buffer) -> Bool:
  match b:
    case Cl.Buffer{_, ch, _, _, _, _, _, _}: ch

def caller_channel_bit() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("empty_buf ampersand local keeps a false channel bit", Bool.not(channel_bit(Cl.empty_buf("&local", False{}))))
    IO.pure(Unit, Unit{})

def unread_names(xs: List<&2, Cl.Alert>) -> String:
  match xs:
    case Nil{}: ""
    case Con{Cl.Alert{+name, _}, +t}:
      name ++ "|" ++ unread_names(t)

def ascii_focus.step(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (+cl, _): cl

def ascii_focus.base() -> Cl.Client:
  ascii_focus.step(Cl.buf_get(ascii_focus.step(Cl.buf_get(Cl.init("me", "s"), "#a[", True{}, True{})), "#a{", True{}, True{}))

def ascii_focus.armed() -> Cl.Client:
  +cl = ascii_focus.base()
  Cl.set_settings(cl, Cl.set_unreads(Cl.get_settings(cl), Cl.Alert{"#a[", Cl.Activity{}} <> Cl.Alert{"#a{", Cl.Activity{}} <> Nil{}))

def ascii_focus.idx(got: Maybe<&2, Nat>) -> Nat:
  match got:
    case None{}: 0n
    case Some{+i}: i

def ascii_focus.done() -> Cl.Client:
  +cl = ascii_focus.armed()
  Cl.set_active_cm("ascii", cl, ascii_focus.idx(Cl.buf_find_cm(cl, "ascii", "#a[")))

def ascii_focus() -> IO(Unit):
  +names = unread_names(Cl.settings_unreads(Cl.get_settings(ascii_focus.done())))
  do IO<Unit>:
    Unit <- E.must_eq("ascii focus drops only the bracket unread", names, "#a{|")
    IO.pure(Unit, Unit{})

# Ascii focus and self-PART must not clear a fold-sibling unread.
def ascii_isc() -> Cl.Iso:
  Cl.Iso{"ascii", Cl.dflt_types(), Cl.dflt_status(), Cl.dflt_sigils(), Cl.dflt_strip()}

def pair_cl(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (+cl, _): cl

def open_ascii(+cl: Cl.Client, +name: String) -> Cl.Client:
  pair_cl(Cl.buf_get_with(cl, ascii_isc(), name, True{}, True{}))

def twin_channels() -> Cl.Client:
  open_ascii(open_ascii(Cl.init("me", "s"), "#x["), "#x{")

def idx_of(got: Maybe<&2, Nat>) -> Nat:
  match got:
    case None{}: 0n
    case Some{+i}: i

def focus_name(+cl: Cl.Client, +name: String) -> Cl.Client:
  Cl.set_active(cl, idx_of(Cl.buf_find_cm(cl, "ascii", name)))

def with_unread(+cl: Cl.Client, +name: String) -> Cl.Client:
  Cl.set_settings(cl, Cl.set_unreads(Cl.get_settings(cl), Cl.Alert{name, Cl.Activity{}} <> Nil{}))

def unread_ascii(+cl: Cl.Client, +name: String) -> U32:
  Cl.buf_unread_status_cm("ascii", Cl.settings_unreads(Cl.get_settings(cl)), name)

def has_buf(got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def nick_focus_after() -> Cl.Client:
  Feed.feed_with(with_unread(focus_name(twin_channels(), "#x["), "#x{"), ascii_isc(), ":bob!u@h NICK carol")

def ascii_nick_focus() -> IO(Unit):
  +after = nick_focus_after()
  do IO<Unit>:
    Unit <- E.must_eq("ascii nick focus stays on bracket", Cl.active_buf_name(after), "#x[")
    Unit <- E.must("ascii nick focus keeps brace unread", U32.is_eq(unread_ascii(after, "#x{"), 1))
    IO.pure(Unit, Unit{})

def part_feed_after() -> Cl.Client:
  Feed.feed_with(with_unread(twin_channels(), "#x{"), ascii_isc(), ":me!u@h PART #x[")

def ascii_part_feed() -> IO(Unit):
  +after = part_feed_after()
  do IO<Unit>:
    Unit <- E.must("ascii self-part drops bracket", Bool.not(has_buf(Cl.buf_find_cm(after, "ascii", "#x["))))
    Unit <- E.must("ascii self-part keeps brace", has_buf(Cl.buf_find_cm(after, "ascii", "#x{")))
    Unit <- E.must("ascii self-part keeps brace unread", U32.is_eq(unread_ascii(after, "#x{"), 1))
    IO.pure(Unit, Unit{})

def view_structure() -> IO(Unit):
  +base = Feed.feed(Feed.feed(Cl.init("me", "s"), ":a!u@h PRIVMSG me :hi"), ":b!u@h PRIVMSG me :hi")
  +closed = Cl.drop_buf(base, 2n)
  do IO<Unit>:
    Unit <- E.must("identical clients stay quiet", Cl.view_same(base, base))
    Unit <- E.must("closing right query invalidates quiet", Bool.not(Cl.view_same(base, closed)))
    Unit <- E.must("active name still server", String.eq(Cl.active_buf_name(closed), "server"))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- spines_controls()
    Unit <- nick_roster()
    Unit <- caller_channel_bit()
    Unit <- ascii_focus()
    Unit <- ascii_nick_focus()
    Unit <- ascii_part_feed()
    Unit <- view_structure()
    IO.print("buffer_spines=ok")
