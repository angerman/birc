# M16.3 scrollback search goldens.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub

def fixture() -> Cl.Client:
  Feed.feed_all(
    Cl.init("me", "irc.example"),
    ":me!u@h JOIN #birc"
      <> ":alice!u@h PRIVMSG #birc :Hello World"
      <> ":bob!u@h PRIVMSG me :hello private"
      <> Nil{}
  )

def take_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _):
      cl

def take_outs(pair: Cl.Client & List<&2, String>) -> List<&2, String>:
  match pair:
    case (_, outs):
      outs

def texts_at.got(+cl: Cl.Client, got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}:
      ""
    case Some{i}:
      CL.buf_texts(cl, i)

def texts_at(+cl: Cl.Client, +name: String) -> String:
  texts_at.got(cl, Cl.buf_find(cl, name))

def search_client() -> Cl.Client:
  take_client(Sub.submit(fixture(), "/search HELLO"))

def repeat_hit(n: Nat, +i: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Cl.Line{Cl.Msg{}, "", "hit " ++ Nat.show(i), "", 0n} <> repeat_hit(p, Nat.add(i, 1n))

def cap_fixture() -> Cl.Buffer:
  Cl.buf_indexed("#many", True{}, "", repeat_hit(Nat.add(Cl.SCROLL_CAP(), 1n), 0n), Nil{}, Cl.ScrollAt{0n, 0n})

def first_text(xs: List<&2, Cl.Line>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{Cl.Line{_, _, +text, +author, +id}, _}:
      text

def last_text.go(xs: List<&2, Cl.Line>, +last: String) -> String:
  match xs:
    case Nil{}:
      last
    case Con{Cl.Line{_, _, +text, +author, +id}, t}:
      last_text.go(t, text)

def last_text(xs: List<&2, Cl.Line>) -> String:
  last_text.go(xs, "")

def empty_query_active() -> String:
  Sub.active_name(take_client(Sub.submit(fixture(), "/search")))

def ctl(+n: U32, +s: String) -> String:
  SCon{Chr{n}, s}

def color_fixture() -> Cl.Client:
  Feed.feed_all(
    Cl.init("me", "irc.example"),
    ":me!u@h JOIN #birc"
      <> (":alice!u@h PRIVMSG #birc :" ++ ctl(3, "04hello"))
      <> ":bob!u@h PRIVMSG #birc :call 04 now"
      <> Nil{}
  )

def fill_buffers.go(n: Nat, +i: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n:
      cl
    case 1n+p:
      fill_buffers.go(
        p,
        Nat.add(i, 1n),
        Feed.feed(cl, ":me!u@h JOIN #full" ++ Nat.show(i))
      )

def full_client() -> Cl.Client:
  fill_buffers.go(15n, 0n, Cl.init("me", "irc.example"))

def full_search_client() -> Cl.Client:
  take_client(Sub.submit(full_client(), "/search hello"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("active", Sub.active_name(search_client()), "*search*")
    Unit <- E.must_eq("count", Nat.show(CL.nbuf(search_client())), "4")
    Unit <- E.must_eq(
      "matches",
      texts_at(search_client(), "*search*"),
      "[#birc] <alice> Hello World|[bob] <bob> hello private|"
    )
    Unit <- E.must(
      "no_outbound",
      List.is_empty(&2, String, take_outs(Sub.submit(fixture(), "/search hello")))
    )
    Unit <- E.must(
      "read_only",
      List.is_empty(&2, String, take_outs(Sub.submit(search_client(), "do not send")))
    )
    Unit <- E.must_eq(
      "repeat_replaces",
      texts_at(take_client(Sub.submit(search_client(), "/search private")), "*search*"),
      "[bob] <bob> hello private|"
    )
    Unit <- E.must_eq("empty_usage", empty_query_active(), "#birc")
    Unit <- E.must("fuzzy", Feed.search_text_matches("Hello World", "hlo"))
    Unit <- E.must_eq(
      "style04_only_literal",
      texts_at(take_client(Sub.submit(color_fixture(), "/search 04")), "*search*"),
      "[#birc] <bob> call 04 now|"
    )
    Unit <- E.must_eq(
      "hello_styled_traversal",
      texts_at(take_client(Sub.submit(color_fixture(), "/search hello")), "*search*"),
      "[#birc] <alice> " ++ ctl(3, "04hello") ++ "|"
    )
    Unit <- E.must_eq("full_count", Nat.show(CL.nbuf(full_search_client())), "16")
    Unit <- E.must_eq("full_active", Sub.active_name(full_search_client()), "#full13")
    Unit <- E.must(
      "full_error",
      String.contains(texts_at(full_search_client(), "#full13"), "search unavailable: buffer limit reached")
    )
    Unit <- E.must_eq(
      "cap",
      Nat.show(List.length(&2, Cl.Line, Feed.search_buf(cap_fixture(), "hit"))),
      Nat.show(Cl.SCROLL_CAP())
    )
    Unit <- E.must_eq("cap_first", first_text(Feed.search_buf(cap_fixture(), "hit")), "[#many] hit 1")
    Unit <- E.must_eq("cap_last", last_text(Feed.search_buf(cap_fixture(), "hit")), "[#many] hit 1024")
    IO.print("search_demo=ok")
