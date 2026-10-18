# SPDX-License-Identifier: Apache-2.0
# Dual-spine Buffer invariant: newest == reverse(lines) and count matches.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed

def line(+text: String, +id: Nat) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", text, "a", id}

def mismatched() -> Cl.Buffer:
  Cl.Buffer{"#t", True{}, "topic", line("a", 1n) <> line("b", 2n) <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}, line("a", 1n) <> Nil{}, 2n}

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
    Unit <- view_structure()
    IO.print("buffer_spines=ok")
