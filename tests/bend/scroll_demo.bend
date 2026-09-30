import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/view.bend as V

def long_client() -> Cl.Client:
  Cl.client_log(Cl.init("me", "s"), 0n, Cl.Msg{}, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

def moved(+cl: Cl.Client, +up: Nat, +dn: Nat) -> Cl.Client:
  Sess.session_cl(Sess.st_of_keys(Sess.step_keys(Sess.session_set_size(Sess.session_demo(cl, "#t"), 8, 20), Sess.keys_of("", False{}, 0, 0, U32.from_nat(up), U32.from_nat(dn), 0, 0, 0))))

def span_text(sp: V.SpanOp) -> String:
  match sp:
    case V.Spn{_, text}: text
    case V.Lnk{_, text}: text
    case V.Col{_, _, text}: text

def span_step(acc: String, sp: V.SpanOp) -> String:
  acc ++ span_text(sp)

def row_text(row: V.BodyRow) -> String:
  match row:
    case V.BodyRow{_, _, _, _, _, spans, _}:
      List.foldl(~&2, ~V.SpanOp, ~String, ~span_step, spans, "")
    case V.BodyRecon{text, _}: text

def rows(+cl: Cl.Client, +w: U32) -> List<&2, V.BodyRow>:
  V.body_of.buf(V.active_buf.on(Cl.nth_buf(Cl.client_bufs(cl), 0n)), 3n, w, False{}, Nil{}, "s")

def first(xs: List<&2, V.BodyRow>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, _}: row_text(h)

def last(xs: List<&2, V.BodyRow>) -> String:
  first(List.reverse(&2, V.BodyRow, xs))

def row_step(acc: String, row: V.BodyRow) -> String:
  acc ++ "|" ++ row_text(row)

def row_texts(xs: List<&2, V.BodyRow>) -> String:
  List.foldl(~&2, ~V.BodyRow, ~String, ~row_step, xs, "")

def reaches_first() -> Bool:
  String.eq(first(rows(moved(long_client(), 100n, 0n), 8)), "ABCDEFGH")

def arrival_anchor() -> Bool:
  +cl = moved(long_client(), 3n, 0n)
  +after = Cl.client_log(cl, 0n, Cl.Msg{}, "NEW ARRIVAL WRAPS ACROSS MANY ROWS")
  String.eq(row_texts(rows(cl, 8)), row_texts(rows(after, 8)))

def resize_anchor() -> Bool:
  +cl = moved(long_client(), 3n, 0n)
  String.eq(last(rows(cl, 8)), "ghijklmn")
    && String.eq(last(rows(cl, 4)), "klmn")

def narrow_first() -> Bool:
  +cl = Cl.buf_modify_client(long_client(), 0n, b => V.scroll_buf(b, 3n, 1, False{}, Nil{}, "s", 100n, 0n))
  String.eq(first(rows(cl, 1)), "A")

def muted_arrival() -> Bool:
  +cl = moved(long_client(), 3n, 0n)
  +after = Cl.client_log_author_ts(cl, 0n, Cl.Msg{}, "", "HIDDEN LONG WRAPPED ARRIVAL", "muted")
  +b = V.active_buf.on(Cl.nth_buf(Cl.client_bufs(after), 0n))
  String.eq(row_texts(rows(cl, 8)), row_texts(V.body_of.buf(b, 3n, 8, False{}, "muted" <> Nil{}, "s")))

def replacement_anchor() -> Bool:
  +b: Cl.Buffer = Cl.Buffer{"server", False{}, "", Cl.Line{Cl.Msg{}, "", "abc👩‍💻uvwxyz", "", 1n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}}
  +scrolled = V.scroll_buf(b, 1n, 1, False{}, Nil{}, "s", 7n, 0n)
  String.eq(last(V.body_of.buf(scrolled, 1n, 1, False{}, Nil{}, "s")), "c")
    && String.eq(last(V.body_of.buf(scrolled, 1n, 4, False{}, Nil{}, "s")), "abc")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("first_row_of_one_wrapped_line", reaches_first())
    Unit <- E.must("arrival_keeps_anchor", arrival_anchor())
    Unit <- E.must("resize_keeps_character_anchor", resize_anchor())
    Unit <- E.must("one_column_reaches_first", narrow_first())
    Unit <- E.must("muted_arrival_keeps_anchor", muted_arrival())
    Unit <- E.must("forced_cluster_resize_keeps_source_anchor", replacement_anchor())
    Unit <- E.must("down_snaps_to_tail", String.eq(last(rows(moved(moved(long_client(), 100n, 0n), 0n, 100n), 8)), "456789"))
    Unit <- E.must("live_arrival_follows_tail", String.eq(last(rows(Cl.client_log(long_client(), 0n, Cl.Msg{}, "NEW"), 8)), "NEW"))
    IO.print("scroll_demo=ok")
