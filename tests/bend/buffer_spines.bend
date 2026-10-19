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
    Unit <- view_structure()
    IO.print("buffer_spines=ok")
