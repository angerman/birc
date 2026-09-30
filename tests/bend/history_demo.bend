# History identity and marker regressions.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/history.bend as H
import ../../src/bend/view.bend as V

def fill(n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p:
      fill(p, Cl.client_log_ts(cl, 0n, Cl.Msg{}, "12:00:00", "same"))

def duplicate_at_cap_ok() -> Bool:
  +old = fill(1024n, Cl.init("me", "s"))
  +new = Cl.client_log_ts(old, 0n, Cl.Msg{}, "12:00:00", "same")
  String.eq(H.extract_new_history(old, new), "server\tMSG\t12:00:00\tsame\n")

def no_op_ok() -> Bool:
  +cl = fill(3n, Cl.init("me", "s"))
  String.is_empty(H.extract_new_history(cl, cl))

def ordinary_marker_text_ok() -> Bool:
  String.eq(H.serialize_line("#t", Cl.Line{Cl.Msg{}, "12:00:00", "<a> Reconnected: wifi", "a", 1n}),
    "#t\tMSG\t12:00:00\t<a> Reconnected: wifi\n")

def ordinary_row(rows: List<&2, V.BodyRow>) -> Bool:
  match rows:
    case Con{V.BodyRow{_, _, _, _, _, _}, Nil{}}: True{}
    case _: False{}

def reconnect_row(rows: List<&2, V.BodyRow>) -> Bool:
  match rows:
    case Con{V.BodyRecon{_, _}, Nil{}}: True{}
    case _: False{}

def author_lines() -> List<&2, Cl.Line>:
  Cl.Line{Cl.Notice{}, "", "-visual- notice", "[Alice]", 1n}
    <> Cl.Line{Cl.Action{}, "", "* visual dances", "[Alice]", 2n}
    <> Cl.Line{Cl.Msg{}, "", "<[Alice]> spoofed prefix", "bob", 3n}
    <> Cl.Line{Cl.System{}, "", "<[Alice]> system", "[Alice]", 4n}
    <> Nil{}

def author_identity_ok() -> Bool:
  Nat.is_eq(List.length(&2, Cl.Line, Cl.purge_nick_lines(author_lines(), "{ALICE}")), 2n)
    && Nat.is_eq(List.length(&2, Cl.Line, Cl.filter_muted_lines(author_lines(), "{ALICE}" <> Nil{}, "#t", "s")), 2n)
    && Nat.is_eq(List.length(&2, Cl.Line, Cl.purge_nick_lines(author_lines(), "nobody")), 4n)

def edit_identity_ok() -> Bool:
  +old = Cl.client_log_author_ts(Cl.init("me", "s"), 0n, Cl.Msg{}, "", "<a> one", "a")
  +purged = Cl.purge_nick_from_active_buf(old, "a")
  +renamed = Cl.buf_modify_client(old, 0n, b => Cl.set_buf_name(b, "renamed"))
  String.is_empty(H.extract_new_history(old, purged)) && String.is_empty(H.extract_new_history(old, renamed))

def feed_identity_ok() -> Bool:
  +old = Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #t")
  +new = Feed.feed(old, ":a!u@h PRIVMSG #t :same")
  String.eq(H.extract_new_history(old, new), "#t\tMSG\t\t<a> same\n")

def loaded_identity_ok() -> Bool:
  +old = H.apply_history(Cl.init("me", "s"), H.parse_history_text("server\tMSG\t\told\n"), "12:00:00", 100)
  +new = Feed.feed(old, "PING :server")
  String.is_empty(H.extract_new_history(old, new))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("no_op", no_op_ok())
    Unit <- E.must("ordinary_marker_text", ordinary_marker_text_ok())
    Unit <- E.must("ordinary_marker_row", ordinary_row(V.wrap_line(Cl.Line{Cl.Msg{}, "", "<a> Reconnected: wifi", "a", 1n}, 80, False{})))
    Unit <- E.must("duplicate_at_cap", duplicate_at_cap_ok())
    Unit <- E.must("reconnect_not_persisted", String.is_empty(H.serialize_line("#t", Cl.Line{Cl.Reconnect{}, "", "12:00:00", "", 0n})))
    Unit <- E.must("reconnect_row", reconnect_row(V.wrap_line(Cl.Line{Cl.Reconnect{}, "", "12:00:00", "", 0n}, 80, False{})))
    Unit <- E.must("author_identity", author_identity_ok())
    Unit <- E.must("edit_identity", edit_identity_ok())
    Unit <- E.must("feed_identity", feed_identity_ok())
    Unit <- E.must("loaded_identity", loaded_identity_ok())
    IO.print("history_demo=ok")
