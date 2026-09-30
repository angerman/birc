# Exercise the Session path used by the UI, not Submit's separate pure path.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as Sess
import ../../src/bend/history.bend as H

def source() -> Cl.Client:
  +old = Cl.client_log_author_ts(Cl.init("me", "s"), 0n, Cl.Msg{}, "", "old https://old.example/path.", "a")
  Cl.client_log_author_ts(old, 0n, Cl.Msg{}, "", "new https://new.example/path", "a")

def opened_url(pair: Sess.Session & Sess.NetCmd & Bool) -> String:
  match pair:
    case (_, (Sess.OpenUrl{url}, _)): url
    case _: ""

def no_open(pair: Sess.Session & Sess.NetCmd & Bool) -> Bool:
  match pair:
    case (_, (Sess.Cont{Nil{}}, False{})): True{}
    case _: False{}

def two_urls(urls: List<&2, String>) -> Bool:
  match urls:
    case Con{new, Con{old, Nil{}}}:
      String.eq(new, "https://new.example/path") && String.eq(old, "https://old.example/path")
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    +old: Cl.Client = source()
    +start: Sess.Session = Sess.session_online(Sess.session_demo(old, "#t"))
    +opened: Sess.Session = Sess.st_of_keys(Sess.step_enter(start, "/open 1"))
    +open_cl: Cl.Client = Sess.session_cl(opened)
    Unit <- E.must_eq("session opens newest URL", opened_url(Sess.step_enter(start, "/open 1")), "https://new.example/path")
    Unit <- E.must("session opener echo is not a link source", two_urls(Sub.active_buf_urls(open_cl)))
    Unit <- E.must("session opener echo is not persisted", String.is_empty(H.extract_new_history_for("s:6667", old, open_cl)))
    +listed: Sess.Session = Sess.st_of_keys(Sess.step_enter(opened, "/links"))
    +twice: Cl.Client = Sess.session_cl(Sess.st_of_keys(Sess.step_enter(listed, "/links")))
    Unit <- E.must("session numbering remains newest then oldest", two_urls(Sub.active_buf_urls(twice)))
    Unit <- E.must("session listings are not persisted", String.is_empty(H.extract_new_history_for("s:6667", old, twice)))
    Unit <- E.must_eq("session listings replace opener echo", Nat.show(CL.buf_nlines(twice, 0n)), "5")
    Unit <- E.must("session lists exactly two entries", String.ends_with(CL.buf_texts(twice, 0n), "recent links:|[1] https://new.example/path|[2] https://old.example/path|"))
    Unit <- E.must("regular chat still persists", String.ends_with(H.extract_new_history_for("s:6667", old, Cl.client_log(old, 0n, Cl.Msg{}, "regular chat")), "regular chat\n"))
    +empty: Sess.Session = Sess.session_demo(Cl.init("me", "s"), "#t")
    Unit <- E.must("missing URL does not launch", no_open(Sess.step_enter(empty, "/open 1")))
    Unit <- E.must("missing URL remains visible", String.ends_with(CL.buf_texts(Sess.session_cl(Sess.st_of_keys(Sess.step_enter(empty, "/open 1"))), 0n), "no link found|"))
    IO.print("session_links_demo=ok")
