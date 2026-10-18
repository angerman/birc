import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/view.bend as V

def long_client() -> Cl.Client:
  Cl.client_log(Cl.init("me", "s"), 0n, Cl.Msg{}, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

# Scroll and paint share height/width so character anchors stay aligned.
def moved(+cl: Cl.Client, +up: Nat, +dn: Nat) -> Cl.Client:
  Cl.buf_modify_client(cl, 0n, b => V.scroll_buf(b, 3n, 8, False{}, Nil{}, True{}, True{}, "s", up, dn))

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
    case V.BodyMedia{_, _, _, _}: ""

def rows(+cl: Cl.Client, +w: U32) -> List<&2, V.BodyRow>:
  V.body_of.buf(V.active_buf.on(Cl.nth_buf(Cl.client_bufs(cl), 0n)), 3n, w, False{}, Nil{}, True{}, True{}, "s")

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
  +cl = Cl.buf_modify_client(long_client(), 0n, b => V.scroll_buf(b, 3n, 1, False{}, Nil{}, True{}, True{}, "s", 100n, 0n))
  String.eq(first(rows(cl, 1)), "A")

def muted_arrival() -> Bool:
  +cl = moved(long_client(), 3n, 0n)
  +after = Cl.client_log_author_ts(cl, 0n, Cl.Msg{}, "", "HIDDEN LONG WRAPPED ARRIVAL", "muted")
  +b = V.active_buf.on(Cl.nth_buf(Cl.client_bufs(after), 0n))
  String.eq(row_texts(rows(cl, 8)), row_texts(V.body_of.buf(b, 3n, 8, False{}, "muted" <> Nil{}, True{}, True{}, "s")))

def replacement_anchor() -> Bool:
  +b: Cl.Buffer = Cl.buf_indexed("server", False{}, "", Cl.Line{Cl.Msg{}, "", "abc👩‍💻uvwxyz", "", 1n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})
  +scrolled = V.scroll_buf(b, 1n, 1, False{}, Nil{}, True{}, True{}, "s", 7n, 0n)
  String.eq(last(V.body_of.buf(scrolled, 1n, 1, False{}, Nil{}, True{}, True{}, "s")), "c")
    && String.eq(last(V.body_of.buf(scrolled, 1n, 4, False{}, Nil{}, True{}, True{}, "s")), "abc")

def buf_scroll(+b: Cl.Buffer) -> Cl.Scroll:
  match b:
    case Cl.Buffer{_, _, _, _, _, +scroll, _, _}: scroll

def scroll_after(+sc: Cl.Scroll) -> Nat:
  match sc:
    case Cl.ScrollAt{+after, _}: after

def is_live(+sc: Cl.Scroll) -> Bool:
  match sc:
    case Cl.ScrollAt{+after, +tail}:
      Nat.is_eq(after, 0n) && Nat.is_eq(tail, 0n)

def cons_msgs(fuel: Nat, +id: Nat, +acc: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match fuel:
    case 0n: acc
    case 1n+p:
      cons_msgs(p, Nat.add(id, 1n), Cl.Line{Cl.Msg{}, "", "m" ++ Nat.show(id), "a", id} <> acc)

def cons_quits(fuel: Nat, +id: Nat, +acc: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match fuel:
    case 0n: acc
    case 1n+p:
      cons_quits(p, Nat.add(id, 1n), Cl.Line{Cl.Presence{}, "", "<- q quit", "q", id} <> acc)

# 30 visible messages + newest filtered JOIN. PageDown must still reach live.
def hidden_newest_buf() -> Cl.Buffer:
  Cl.buf_indexed("#t", True{}, "",
    List.reverse(&2, Cl.Line,
      Cl.Line{Cl.Presence{}, "", "-> z joined #t", "z", 31n} <> cons_msgs(30n, 1n, Nil{})),
    Nil{}, Cl.ScrollAt{0n, 0n})

def hidden_newest_paged() -> Cl.Buffer:
  +up = V.scroll_buf(hidden_newest_buf(), 3n, 40, False{}, Nil{}, False{}, True{}, "s", 100n, 0n)
  V.scroll_buf(V.scroll_buf(up, 3n, 40, False{}, Nil{}, False{}, True{}, "s", 0n, 100n),
    3n, 40, False{}, Nil{}, False{}, True{}, "s", 0n, 100n)

# −: must not remain anchored away from live after PageDown across a hidden newest JOIN.
def hidden_newest_not_stuck() -> Bool:
  Bool.not(Nat.is_gt(scroll_after(buf_scroll(hidden_newest_paged())), 0n))

# +: PageUp then PageDown reaches ScrollAt{0,0} even when newest paints no row.
def hidden_newest_reaches_live() -> Bool:
  is_live(buf_scroll(hidden_newest_paged()))

# OLD + 60 hidden QUITs + NEW. after=61 on OLD; dn=3 must cross the hidden run.
def long_hidden_buf() -> Cl.Buffer:
  Cl.buf_indexed("#t", True{}, "",
    List.reverse(&2, Cl.Line,
      Cl.Line{Cl.Msg{}, "", "NEW", "a", 62n}
        <> cons_quits(60n, 2n, Cl.Line{Cl.Msg{}, "", "OLD", "a", 1n} <> Nil{})),
    Nil{}, Cl.ScrollAt{61n, 0n})

# +: PageDown progresses past >dn+32 consecutive filtered lines.
def long_hidden_run_progresses() -> Bool:
  +b1 = V.scroll_buf(long_hidden_buf(), 3n, 40, False{}, Nil{}, False{}, True{}, "s", 0n, 3n)
  Nat.is_lt(scroll_after(buf_scroll(b1)), 61n)

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
    Unit <- E.must("hidden_newest_page_down_not_stuck", hidden_newest_not_stuck())
    Unit <- E.must("hidden_newest_page_down_reaches_live", hidden_newest_reaches_live())
    Unit <- E.must("long_hidden_run_page_down_progresses", long_hidden_run_progresses())
    IO.print("scroll_demo=ok")
