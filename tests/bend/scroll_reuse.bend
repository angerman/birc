import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/view.bend as V

# 20 Monday lines then 20 Tuesday lines. Each line is one row at width 40.
# A page-down from the Monday side crosses the day bar; a one-row move does not
# cover an 8-row viewport.
def cons_dated(fuel: Nat, +id: Nat, +ts: String, +acc: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match fuel:
    case 0n: acc
    case 1n+p:
      cons_dated(p, Nat.add(id, 1n), ts, Cl.Line{Cl.Msg{}, ts, "m" ++ Nat.show(id), "a", id} <> acc)

def many() -> Cl.Buffer:
  +older = cons_dated(20n, 1n, "2026-10-20 (Monday)|12:00:00", Nil{})
  +newer = cons_dated(20n, 21n, "2026-10-21 (Tuesday)|12:00:00", older)
  Cl.buf_indexed("#t", True{}, "", List.reverse(&2, Cl.Line, newer), Nil{}, Cl.ScrollAt{0n, 0n})

def parked() -> Cl.Buffer:
  V.scroll_buf(many(), 8n, 40, False{}, Nil{}, True{}, True{}, "s", 24n, 0n)

def page_hold() -> V.ScrollHold:
  V.scroll_hold(parked(), 8n, 40, False{}, Nil{}, True{}, True{}, "s", 0n, 8n)

def notch_hold() -> V.ScrollHold:
  V.scroll_hold(parked(), 8n, 40, False{}, Nil{}, True{}, True{}, "s", 1n, 0n)

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

def row_step(acc: String, row: V.BodyRow) -> String:
  acc ++ "|" ++ row_text(row)

def row_texts(xs: List<&2, V.BodyRow>) -> String:
  List.foldl(~&2, ~V.BodyRow, ~String, ~row_step, xs, "")

def pair_rows(pair: List<&2, V.BodyRow> & Bool) -> List<&2, V.BodyRow>:
  match pair:
    case (+rows, _): rows

def pair_reused(pair: List<&2, V.BodyRow> & Bool) -> Bool:
  match pair:
    case (_, +reused): reused

def paint_of(+hold: V.ScrollHold) -> List<&2, V.BodyRow> & Bool:
  V.paint_hold(hold, 8n, 40, False{}, Nil{}, True{}, True{}, "s", V.paint_text())

def cold_of(+b: Cl.Buffer) -> List<&2, V.BodyRow>:
  V.paint_body_of(b, 8n, 40, False{}, Nil{}, True{}, True{}, "s", V.paint_text())

def page_rows() -> List<&2, V.BodyRow>:
  pair_rows(paint_of(page_hold()))

def page_reused() -> Bool:
  pair_reused(paint_of(page_hold()))

def page_cold() -> List<&2, V.BodyRow>:
  cold_of(V.hold_buf(page_hold()))

def page_crop() -> List<&2, V.BodyRow>:
  +hold = page_hold()
  V.visible_anchored(V.hold_rows(hold), 8n, Cl.buf_scroll(V.hold_buf(hold)))

def page_anchor() -> Bool:
  Cl.scroll_eq(
    Cl.buf_scroll(V.hold_buf(page_hold())),
    Cl.buf_scroll(V.scroll_buf(parked(), 8n, 40, False{}, Nil{}, True{}, True{}, "s", 0n, 8n)))

def notch_rows() -> List<&2, V.BodyRow>:
  pair_rows(paint_of(notch_hold()))

def notch_reused() -> Bool:
  pair_reused(paint_of(notch_hold()))

def notch_cold() -> List<&2, V.BodyRow>:
  cold_of(V.hold_buf(notch_hold()))

def notch_anchor() -> Bool:
  Cl.scroll_eq(
    Cl.buf_scroll(V.hold_buf(notch_hold())),
    Cl.buf_scroll(V.scroll_buf(parked(), 8n, 40, False{}, Nil{}, True{}, True{}, "s", 1n, 0n)))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("page_reuses_walk", page_reused())
    Unit <- E.must_eq("page_text", row_texts(page_rows()), row_texts(page_cold()))
    Unit <- E.must_eq("page_matches_walk_crop", row_texts(page_rows()), row_texts(page_crop()))
    Unit <- E.must("page_anchor", page_anchor())
    Unit <- E.must_eq("page_full_viewport", Nat.show(List.length(&2, V.BodyRow, page_rows())), "8")
    Unit <- E.must("page_keeps_day_bar", String.contains(row_texts(page_rows()), "@2026-10-21"))
    Unit <- E.must("notch_does_not_reuse", Bool.not(notch_reused()))
    Unit <- E.must_eq("notch_text", row_texts(notch_rows()), row_texts(notch_cold()))
    Unit <- E.must_eq("notch_full_viewport", Nat.show(List.length(&2, V.BodyRow, notch_rows())), "8")
    Unit <- E.must("notch_anchor", notch_anchor())
    IO.print("scroll_reuse=ok")
