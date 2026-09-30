import Base
import ./expect.bend as E
import ../../src/bend/links.bend as Links

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("positive urls", String.join(Links.extract("see https://one.test, then (http://two.test)."), ","), "https://one.test,http://two.test")
    Unit <- E.must_eq("word boundary", String.join(Links.extract("xhttps://not.test https://yes.test"), ","), "https://yes.test")
    Unit <- E.must_eq("code excluded", String.join(Links.extract("`https://not.test` https://yes.test"), ","), "https://yes.test")
    Unit <- E.must_eq("styles excluded", String.join(Links.extract("*https://not.test* _http://not.test_ https://yes.test"), ","), "https://yes.test")
    Unit <- E.must_eq("style reset", String.join(Links.extract("*bold*https://yes.test"), ","), "https://yes.test")
    IO.print("links_demo=ok")
