import Base
import ./expect.bend as E
import ../../src/bend/links.bend as Links
import ../../src/bend/emoji.bend as Emoji

def alias_first_hit.got(got: Maybe<&2, Links.Alias>) -> Bool:
  match got:
    case Some{Links.Alias{+text, +rest}}: String.eq(text, "👀") && String.eq(rest, " hi")
    case None{}: False{}

def alias_first_hit() -> Bool:
  +got = Links.alias.go(Emoji.Entry{":eyes:", "👀"} <> Emoji.Entry{":wave:", "👋"} <> Nil{}, ":eyes: hi")
  alias_first_hit.got(got)

def alias_first_miss_tail.got(got: Maybe<&2, Links.Alias>) -> Bool:
  match got:
    case None{}: True{}
    case Some{_}: False{}

def alias_first_miss_tail() -> Bool:
  +got = Links.alias.go(Emoji.Entry{":wave:", "👋"} <> Nil{}, ":eyes:")
  alias_first_miss_tail.got(got)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("positive urls", String.join(Links.extract("see https://one.test, then (http://two.test)."), ","), "https://one.test,http://two.test")
    Unit <- E.must_eq("word boundary", String.join(Links.extract("xhttps://not.test https://yes.test"), ","), "https://yes.test")
    Unit <- E.must_eq("code excluded", String.join(Links.extract("`https://not.test` https://yes.test"), ","), "https://yes.test")
    Unit <- E.must_eq("styles excluded", String.join(Links.extract("*https://not.test* _http://not.test_ https://yes.test"), ","), "https://yes.test")
    Unit <- E.must_eq("style reset", String.join(Links.extract("*bold*https://yes.test"), ","), "https://yes.test")
    Unit <- E.must("alias_first_hit", alias_first_hit())
    Unit <- E.must("alias_first_miss_tail", alias_first_miss_tail())
    Unit <- E.must_eq(
      "alias_render_eyes",
      String.join(Links.extract(":eyes: see https://yes.test"), ","),
      "https://yes.test"
    )
    IO.print("links_demo=ok")
