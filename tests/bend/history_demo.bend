# History identity and marker regressions.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/history.bend as H
import ../../src/bend/view.bend as V
import ../../src/bend/submit.bend as Sub
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/frame.bend as Fr

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

def rejected_local.got(pair: Cl.Client & List<&2, String>, +old: Cl.Client) -> Bool:
  match pair:
    case (+new, _):
      String.eq(H.extract_new_history(old, new), "server\tERR\t\tbuffer limit reached\n")
        && String.is_empty(H.extract_new_history(new, new))

def fill_channels(+n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p: fill_channels(p, Feed.feed(cl, ":me!u@h JOIN #" ++ Nat.show(n)))

def rejected_local_ok() -> Bool:
  +old = fill_channels(15n, Cl.init("me", "s"))
  rejected_local.got(Sub.submit(old, "/join #overflow"), old)

def no_entry(entry: Maybe<&2, H.HistEntry>) -> Bool:
  match entry:
    case None{}: True{}
    case Some{_}: False{}

def authored_entry(entry: Maybe<&2, H.HistEntry>) -> Bool:
  match entry:
    case Some{H.Entry{+target, Cl.Line{Cl.Notice{}, +ts, +text, +author, _}}}:
      String.eq(target, "#t") && String.eq(ts, "12:00:00") && String.eq(text, "notice") && String.eq(author, "alice")
    case _: False{}

def endpoint_ok() -> Bool:
  +record: String = "BIRC2\ta:6667\t#t\tNOT\t12:00:00\talice\tnotice"
  authored_entry(H.parse_line_for("A:6667", record))
    && no_entry(H.parse_line_for("b:6667", record))
    && no_entry(H.parse_line_for("a:6668", record))
    && no_entry(H.parse_line_for("a:6667", "#t\tMSG\t\tlegacy"))
    && no_entry(H.parse_line_for("a:6667", "BIRC2\ta:6667\t#t\tWRONG\t\ta\tx"))

def utf8_chunk.final(state: H.ReadState) -> Bool:
  match state:
    case H.ReadState{cl, _, +n, _}:
      String.eq(CL.buf_texts(cl, 0n), "é|") && Nat.is_eq(n, 0n)

def utf8_chunk_ok() -> Bool:
  +start: H.ReadState = H.ReadState{Cl.init("me", "a"), Nil{}, 0n, False{}}
  +first = H.read_chunk(List.append(&2, U32, Fr.string_to_octets("BIRC2\ta:6667\tserver\tMSG\t\ta\t"), 195 <> Nil{}), start, "a:6667", 2)
  utf8_chunk.final(H.read_chunk(169 <> 10 <> Nil{}, first, "a:6667", 2))

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
    Unit <- E.must("rejected_local", rejected_local_ok())
    Unit <- E.must("endpoint", endpoint_ok())
    Unit <- E.must("utf8_chunk", utf8_chunk_ok())
    IO.print("history_demo=ok")
