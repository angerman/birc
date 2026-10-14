# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/cards.bend as C
import ../../src/bend/view.bend as V

def page() -> String:
  "https://x.test/read"

def img() -> String:
  "https://x.test/i.png"

def url_only() -> C.CardReady:
  C.CardReady{C.CardInline{1n}, page(), "", "", ""}

def image_only() -> C.CardReady:
  C.CardReady{C.CardInline{1n}, page(), "", "", img()}

def full_card() -> C.CardReady:
  C.CardReady{C.CardInline{1n}, page(), "Hello", "A description", img()}

def with_ready(+r: C.CardReady) -> C.State:
  C.State{True{}, 1n, 2n, None{}, Nil{}, [r]}

def all_texts(xs: List<&2, V.CardEntry>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{V.CardEntry{_, +texts}, t}: List.append(&2, String, texts, all_texts(t))

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text(t)

def row_text(row: V.BodyRow) -> String:
  match row:
    case V.BodyRow{_, _, _, _, _, spans, _}: spans_text(spans)
    case _: "#"

def sequence(xs: List<&2, V.BodyRow>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, Nil{}}: row_text(h)
    case Con{h, t}: row_text(h) ++ "|" ++ sequence(t)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("url-only rows_for is zero", Nat.show(List.length(&2, V.BodyRow, C.rows_for(url_only(), 80))), "0")
    Unit <- E.must_eq("url-only paint entry kept", Nat.show(List.length(&2, V.CardEntry, C.paint_entries(with_ready(url_only())))), "1")
    Unit <- E.must_eq("url-only paint texts empty", Nat.show(List.length(&2, String, all_texts(C.paint_entries(with_ready(url_only()))))), "0")
    Unit <- E.must_eq("url-only view cascade is zero", Nat.show(List.length(&2, V.BodyRow, V.card_rows_for(C.paint_entries(with_ready(url_only())), 1n, 80))), "0")
    Unit <- E.must_eq("image-only rows_for is one", Nat.show(List.length(&2, V.BodyRow, C.rows_for(image_only(), 80))), "1")
    Unit <- E.must_eq("image-only keeps thumbnail row", sequence(C.rows_for(image_only(), 80)), "image: " ++ img())
    Unit <- E.must_eq("image-only view cascade is one", Nat.show(List.length(&2, V.BodyRow, V.card_rows_for(C.paint_entries(with_ready(image_only())), 1n, 80))), "1")
    Unit <- E.must_eq("full card still three rows", Nat.show(List.length(&2, V.BodyRow, C.rows_for(full_card(), 80))), "3")
    Unit <- E.must_eq("full card text unchanged", sequence(C.rows_for(full_card(), 80)), "Hello|A description|image: " ++ img())
    Unit <- E.must_eq("full card view cascade unchanged", Nat.show(List.length(&2, V.BodyRow, V.card_rows_for(C.paint_entries(with_ready(full_card())), 1n, 80))), "3")
    Unit <- E.must_eq("empty title still falls back with desc", sequence(C.rows_for(C.CardReady{C.CardInline{1n}, page(), "", "D", ""}, 80)), page() ++ "|D")
    IO.print("cards_empty_rows=ok")
