# SPDX-License-Identifier: Apache-2.0
# Rich-text source order and operation attributes, including wrapped rows.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/view.bend as V
import ../../src/bend/view_laws.bend as VL

def show_op(op: V.SpanOp) -> String:
  match op:
    case V.Spn{attrs, +text}: "S" ++ U32.show(attrs) ++ "[" ++ text ++ "]"
    case V.Lnk{+url, +text}: "L[" ++ url ++ "][" ++ text ++ "]"
    case V.Col{attrs, fg, +text}: "C" ++ U32.show(attrs) ++ ":" ++ U32.show(fg) ++ "[" ++ text ++ "]"

def show_ops(ops: List<&2, V.SpanOp>) -> String:
  match ops:
    case Nil{}: ""
    case Con{h, t}: show_op(h) ++ show_ops(t)

def styled(+text: String) -> String:
  show_ops(VL.span_ops(VL.tokenize(text)))

def spans_text(spans: List<&2, V.SpanOp>) -> String:
  match spans:
    case Nil{}: ""
    case Con{+h, t}: V.span_text(h) ++ spans_text(t)

def dim_spans(spans: List<&2, V.SpanOp>) -> Bool:
  match spans:
    case Nil{}: True{}
    case Con{V.Spn{attrs, _}, t}: U32.is_eq(attrs, 2) && dim_spans(t)
    case _: False{}

def rows_text(rows: List<&2, V.BodyRow>) -> String:
  match rows:
    case Nil{}: ""
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: spans_text(spans) ++ rows_text(t)
    case _: "unexpected reconnect"

def dim_rows(rows: List<&2, V.BodyRow>) -> Bool:
  match rows:
    case Nil{}: True{}
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: dim_spans(spans) && dim_rows(t)
    case _: False{}

def line(text: String) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", text, "", 0n}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("plain positive", styled("plain"), "S0[plain]")
    Unit <- E.must_eq("closed bold positive", styled("*bold*"), "S1[bold]")
    Unit <- E.must_eq("closed italic positive", styled("_italic_"), "S4[italic]")
    Unit <- E.must_eq("double marker bold", styled("**bold**"), "S1[bold]")
    Unit <- E.must_eq("nested bold italic", styled("*bold _italic_*"), "S1[bold ]S5[italic]")
    Unit <- E.must_eq("link positive", styled("https://example.test"), "L[https://example.test][https://example.test]")
    Unit <- E.must_eq("unclosed star source order", VL.show_spans(VL.tokenize("before *unclosed")), "before *unclosed")
    Unit <- E.must_eq("unclosed underscore source order", VL.show_spans(VL.tokenize("before _unclosed")), "before _unclosed")
    Unit <- E.must_eq("unclosed tick source order", VL.show_spans(VL.tokenize("before `unclosed")), "before `unclosed")
    Unit <- E.must_eq("empty unmatched marker positive", styled("*"), "S0[*]")
    Unit <- E.must_eq("unclosed Unicode source order", styled("*漢字"), "S0[*漢字]")
    Unit <- E.must_eq("forced bold fallback", VL.show_spans(VL.tokenize.force_mode(VL.MdBold{}, String.reverse("abc"), Nil{})), "*abc")
    Unit <- E.must_eq("forced italic fallback", VL.show_spans(VL.tokenize.force_mode(VL.MdItalic{}, String.reverse("abc"), Nil{})), "_abc")
    Unit <- E.must_eq("forced code fallback", VL.show_spans(VL.tokenize.force_mode(VL.MdCode{}, String.reverse("abc"), Nil{})), "`abc")
    Unit <- E.must_eq("closed code dim", styled("`code`"), "S2[code]")
    Unit <- E.must_eq("code remains opaque", styled("`*bold* _italic_ https://example.test`"), "S2[*bold* _italic_ https://example.test]")
    Unit <- E.must_eq("unclosed code plain", styled("`code"), "S0[`code]")
    +code : List<&2, V.BodyRow> = V.wrap_line(line("`abcdefghijklmno`"), 5, False{})
    Unit <- E.must("code dim survives wrap", dim_rows(code))
    Unit <- E.must_eq("code wrap text positive", rows_text(code), "abcdefghijklmno")
    Unit <- E.must_eq("code wrap row count", Nat.show(List.length(&2, V.BodyRow, code)), "3")
    Unit <- E.must_eq("literal opener survives wrap", rows_text(V.wrap_line(line("*abcdefghijklmno"), 5, False{})), "*abcdefghijklmno")
    IO.print("richtext_demo=ok")
