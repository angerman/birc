# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/columns.bend as C
import ../../src/bend/view.bend as V

def span_text(sp: V.SpanOp) -> String:
  match sp:
    case V.Spn{_, s}: s
    case V.Lnk{_, s}: s
    case V.Col{_, _, s}: s

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: span_text(h) ++ spans_text(t)

def chunks(xs: List<&2, V.BodyRow>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: spans_text(spans) <> chunks(t)
    case Con{_, t}: chunks(t)

def wrapped(s: String, w: U32) -> String:
  String.join(chunks(V.wrap_line(Cl.Line{Cl.Msg{}, "", s, "", 1n}, w, False{})), "|")

def cut_signature(piece: C.Cut) -> String:
  match piece:
    case C.Cut{head, tail, w}: U32.show(w) ++ ":" ++ head ++ ":" ++ tail

def parity_piece(piece: C.Cut, s: String) -> String:
  match piece:
    case C.Cut{head, _, w}:
      U32.show(C.text_width(s)) ++ " " ++ U32.show(w) ++ " " ++ Nat.show(String.length(head))

def parity_line(+s: String) -> String:
  parity_piece(C.cluster(s), s)

def parity(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{h, t}:
      do IO<Unit>:
        IO.print(parity_line(h))
        parity(t)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("ASCII width", U32.show(C.text_width("abc")), "3")
    Unit <- E.must_eq("combining width", U32.show(C.text_width("éx")), "2")
    Unit <- E.must_eq("modifier width", U32.show(C.text_width("👍🏽x")), "3")
    Unit <- E.must_eq("ZWJ width", U32.show(C.text_width("👩‍💻x")), "3")
    Unit <- E.must_eq("VS16 width", U32.show(C.text_width("❤️x")), "3")
    Unit <- E.must_eq("single RI is wide", U32.show(C.text_width("🇰x")), "3")
    Unit <- E.must_eq("RI pair width", U32.show(C.text_width("🇰🇷x")), "3")
    Unit <- E.must_eq("text VS stays narrow", U32.show(C.text_width("❤︎x")), "2")
    Unit <- E.must_eq("nonemoji VS16 stays narrow", U32.show(C.text_width("a️x")), "2")
    Unit <- E.must_eq("nonemoji ZWJ max base width", U32.show(C.text_width("a‍bx")), "2")
    Unit <- E.must_eq("first ZWJ is its own cluster", cut_signature(C.cluster("‍a")), "0:‍:a")
    Unit <- E.must_eq("control is not an extension", cut_signature(C.cluster("a\nb")), "1:a:\nb")
    Unit <- E.must_eq("CRLF is one cluster", cut_signature(C.cluster("\r\nx")), "0:\r\n:x")
    Unit <- E.must_eq("RI extension preserves pairing", cut_signature(C.cluster("🇰́🇷x")), "2:🇰́🇷:x")
    Unit <- E.must_eq("ZWJ fits two columns", cut_signature(C.take("👩‍💻x", 2)), "2:👩‍💻:x")
    Unit <- E.must_eq("VS16 does not overfit", cut_signature(C.take("❤️x", 2)), "2:❤️:x")
    Unit <- E.must_eq("cluster remains whole when too wide", cut_signature(C.take("👩‍💻x", 1)), "0::👩‍💻x")
    Unit <- E.must_eq("ZWJ row exact", wrapped("👩‍💻x", 2), "👩‍💻|x")
    Unit <- E.must_eq("VS16 row exact", wrapped("❤️x", 2), "❤️|x")
    Unit <- E.must_eq("one column fallback", wrapped("👩‍💻x", 1), "�|x")
    Unit <- E.must_eq("ASCII rows", wrapped("abcde", 3), "abc|de")
    Unit <- E.must_eq("combining rows", wrapped("éx", 1), "é|x")
    Unit <- E.must_eq("modifier rows", wrapped("👍🏽x", 2), "👍🏽|x")
    Unit <- E.must_eq("exact four columns", wrapped("a👩‍💻b", 4), "a👩‍💻b")
    xs : List<&1, String> <- IO.args()
    Unit <- parity(List.drop(&1, String, xs, 2n))
    IO.print("ui_review_columns=ok")
