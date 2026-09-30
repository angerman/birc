# Stable message identities must survive edits of a scrolled buffer.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/submit.bend as Sub

def id_at(lines: List<&2, Cl.Line>, index: Nat) -> Nat:
  match lines:
    case Nil{}: 0n
    case Con{Cl.Line{_, _, _, _, id}, t}:
      match index:
        case 0n: id
        case 1n+p: id_at(t, p)

def anchor_id(buffer: Cl.Buffer) -> Nat:
  match buffer:
    case Cl.Buffer{_, _, _, +lines, _, Cl.ScrollAt{after, _}}:
      id_at(lines, Nat.sub(List.length(&2, Cl.Line, lines), 1n+after))

def anchor_id.got(buffer: Maybe<&2, Cl.Buffer>) -> Nat:
  match buffer:
    case None{}: 0n
    case Some{b}: anchor_id(b)

def client_anchor(+cl: Cl.Client) -> Nat:
  anchor_id.got(Cl.nth_buf(Cl.client_bufs(cl), Cl.active_of(cl)))

def anchor_tail(buffer: Cl.Buffer) -> Nat:
  match buffer:
    case Cl.Buffer{_, _, _, _, _, Cl.ScrollAt{_, tail}}: tail

def client_tail.got(buffer: Maybe<&2, Cl.Buffer>) -> Nat:
  match buffer:
    case None{}: 0n
    case Some{b}: anchor_tail(b)

def client_tail(+cl: Cl.Client) -> Nat:
  client_tail.got(Cl.nth_buf(Cl.client_bufs(cl), Cl.active_of(cl)))

def three_lines() -> Cl.Buffer:
  Cl.Buffer{"#t", True{}, "",
    Cl.Line{Cl.Msg{}, "", "first", "a", 1n}
      <> Cl.Line{Cl.Msg{}, "", "second", "b", 2n}
      <> Cl.Line{Cl.Msg{}, "", "third", "c", 3n} <> Nil{},
    Nil{}, Cl.ScrollAt{1n, 2n}}

def purge_newer_ok() -> Bool:
  +b = Cl.purge_nick_buf(three_lines(), "c")
  Nat.is_eq(anchor_id(b), 2n) && Nat.is_eq(anchor_tail(b), 2n)

def purge_older_ok() -> Bool:
  Nat.is_eq(anchor_id(Cl.purge_nick_buf(three_lines(), "a")), 2n)

def purge_anchor_ok() -> Bool:
  +b = Cl.purge_nick_buf(three_lines(), "b")
  Nat.is_eq(anchor_id(b), 1n) && Nat.is_eq(anchor_tail(b), 0n)

def purge_all_ok() -> Bool:
  +b = Cl.purge_nick_buf(Cl.purge_nick_buf(Cl.purge_nick_buf(three_lines(), "a"), "b"), "c")
  Nat.is_eq(anchor_id(b), 0n) && Nat.is_eq(anchor_tail(b), 0n)

def purge_follow_ok() -> Bool:
  +b = Cl.purge_nick_buf(Cl.set_buf_anchor(three_lines(), Cl.ScrollAt{0n, 0n}), "c")
  Nat.is_eq(anchor_id(b), 2n) && Nat.is_eq(anchor_tail(b), 0n)

def query_source() -> Cl.Client:
  +a = Feed.feed(Cl.init("me", "s"), ":a!u@h PRIVMSG me :first")
  +b = Feed.feed(a, ":b!u@h PRIVMSG me :second")
  Feed.feed(b, ":a!u@h PRIVMSG me :third")

def merge_source_ok() -> Bool:
  +cl = Cl.set_active(Cl.buf_modify_client(query_source(), 1n, b => Cl.set_buf_anchor(b, Cl.ScrollAt{1n, 2n})), 1n)
  +merged = Feed.feed(cl, ":a!u@h NICK :b")
  Nat.is_eq(client_anchor(merged), 1n) && Nat.is_eq(client_tail(merged), 2n)

def merge_destination_ok() -> Bool:
  +cl = Cl.set_active(Cl.buf_modify_client(query_source(), 2n, b => Cl.set_buf_anchor(b, Cl.ScrollAt{0n, 2n})), 2n)
  +merged = Feed.feed(cl, ":a!u@h NICK :b")
  Nat.is_eq(client_anchor(merged), 2n) && Nat.is_eq(client_tail(merged), 2n)

def merge_follow_ok() -> Bool:
  +merged = Feed.feed(Cl.set_active(query_source(), 2n), ":a!u@h NICK :b")
  Nat.is_eq(client_anchor(merged), 4n) && Nat.is_eq(client_tail(merged), 0n)

def submit_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def repeat_links_ok() -> Bool:
  +old = Cl.client_log(Cl.init("me", "s"), 0n, Cl.Msg{}, "https://old.example")
  +source = Cl.client_log(old, 0n, Cl.Msg{}, "https://new.example")
  +listed = submit_client(Sub.submit(source, "/links"))
  +scrolled = Cl.buf_modify_client(listed, 0n, b => Cl.set_buf_anchor(b, Cl.ScrollAt{3n, 2n}))
  +repeated = submit_client(Sub.submit(scrolled, "/links"))
  Nat.is_eq(client_anchor(repeated), 2n) && Nat.is_eq(client_tail(repeated), 2n)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("purge_older", purge_older_ok())
    Unit <- E.must("purge_newer", purge_newer_ok())
    Unit <- E.must("purge_anchor", purge_anchor_ok())
    Unit <- E.must("purge_all", purge_all_ok())
    Unit <- E.must("purge_follow", purge_follow_ok())
    Unit <- E.must("merge_source", merge_source_ok())
    Unit <- E.must("merge_destination", merge_destination_ok())
    Unit <- E.must("merge_follow", merge_follow_ok())
    Unit <- E.must("repeat_links", repeat_links_ok())
    IO.print("scroll_edits_demo=ok")
