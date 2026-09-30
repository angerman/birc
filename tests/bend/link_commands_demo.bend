# /links and /open use one stable newest-first source list.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/history.bend as H

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def url_is(value: Maybe<&2, String>, +expected: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{url}: String.eq(url, expected)

def source() -> Cl.Client:
  +old = Cl.client_log_author_ts(Cl.init("me", "s"), 0n, Cl.Msg{}, "", "old https://old.example/path.", "a")
  Cl.client_log_author_ts(old, 0n, Cl.Msg{}, "", "new https://new.example/path", "a")

def stable_numbering_ok() -> Bool:
  +old = source()
  +listed = client(Sub.submit(old, "/links"))
  +twice = client(Sub.submit(listed, "/links"))
  +opened = client(Sub.submit(twice, "/open 1"))
  url_is(Sub.open_resolve_target(old, "1"), "https://new.example/path")
    && url_is(Sub.open_resolve_target(listed, "1"), "https://new.example/path")
    && url_is(Sub.open_resolve_target(twice, "2"), "https://old.example/path")
    && url_is(Sub.open_resolve_target(opened, "1"), "https://new.example/path")
    && Nat.is_eq(List.length(&2, String, Sub.active_buf_urls(opened)), 2n)
    && String.ends_with(CL.buf_texts(twice, 0n), "recent links:|[1] https://new.example/path|[2] https://old.example/path|")
    && Nat.is_eq(CL.buf_nlines(twice, 0n), 5n)
    && String.is_empty(H.extract_new_history(old, twice))

def one_exact_url(urls: List<&2, String>) -> Bool:
  match urls:
    case Con{url, Nil{}}: String.eq(url, "https://example/a/http://nested")
    case _: False{}

def lexical_ok() -> Bool:
  one_exact_url(Sub.extract_urls("https://example/a/http://nested"))
    && Nat.is_eq(List.length(&2, String, Sub.extract_urls("xhttps://not-link `https://code` https://yes.example)")), 1n)
    && url_is(Sub.nth_link(Sub.extract_urls("https://yes.example), tail"), 0n), "https://yes.example")
    && Sub.submit_is_open("/OPEN   2") && Bool.not(Sub.submit_is_open("open 2"))
    && Bool.not(Sub.submit_is_open("/openish 2")) && String.eq(Sub.open_arg_from_input("/OPEN   2"), "2")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("stable_numbering", stable_numbering_ok())
    Unit <- E.must("shared_lexical_rules", lexical_ok())
    IO.print("link_commands_demo=ok")
