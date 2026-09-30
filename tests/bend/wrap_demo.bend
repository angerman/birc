import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/columns.bend as Cols
import ../../src/bend/view.bend as V

def text(sp: V.SpanOp) -> String:
  match sp:
    case V.Spn{_, s}: s
    case V.Lnk{_, s}: s
    case V.Col{_, _, s}: s

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: text(h) ++ spans_text(t)

def rows_text(rows: List<&2, V.BodyRow>) -> String:
  match rows:
    case Nil{}: ""
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: spans_text(spans) ++ rows_text(t)
    case Con{V.BodyRecon{_, _}, t}: rows_text(t)

def links_exact(xs: List<&2, V.SpanOp>, +url: String) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{sp, t}:
      match sp:
        case V.Lnk{+actual, _}: String.eq(actual, url) && links_exact(t, url)
        case _: False{}

def link_rows(rows: List<&2, V.BodyRow>, +url: String) -> Bool:
  match rows:
    case Nil{}: True{}
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: links_exact(spans, url) && link_rows(t, url)
    case _: False{}

def bold_spans(xs: List<&2, V.SpanOp>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{V.Spn{attrs, _}, t}: U32.is_eq(attrs, 1) && bold_spans(t)
    case _: False{}

def bold_rows(rows: List<&2, V.BodyRow>) -> Bool:
  match rows:
    case Nil{}: True{}
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: bold_spans(spans) && bold_rows(t)
    case _: False{}

def widths_fit(rows: List<&2, V.BodyRow>) -> Bool:
  match rows:
    case Nil{}: True{}
    case Con{V.BodyRow{_, _, _, w, _, +spans, _}, t}: U32.is_le(Cols.text_width(spans_text(spans)), w) && widths_fit(t)
    case _: False{}

def row_chunks(rows: List<&2, V.BodyRow>) -> List<&2, String>:
  match rows:
    case Nil{}: Nil{}
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: spans_text(spans) <> row_chunks(t)
    case _: Nil{}

def line(+s: String) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", s, "", 0n}

def main() -> IO(Unit):
  do IO<Unit>:
    +url : String = "https://example.com/very-long-path"
    +link : List<&2, V.BodyRow> = V.wrap_line(line(url), 10, False{})
    Unit <- E.must("wrapped link exact target", link_rows(link, url))
    Unit <- E.must_eq("wrapped link visible text", rows_text(link), url)
    Unit <- E.must("link rows fit columns", widths_fit(link))
    +bold : List<&2, V.BodyRow> = V.wrap_line(line("*abcdefghijklmno*"), 5, False{})
    Unit <- E.must("style spans survive wrap", bold_rows(bold))
    Unit <- E.must_eq("style display text", rows_text(bold), "abcdefghijklmno")
    +wide : List<&2, V.BodyRow> = V.wrap_line(line("漢字漢字漢"), 5, False{})
    Unit <- E.must("wide rows fit columns", widths_fit(wide))
    Unit <- E.must_eq("wide characters kept", rows_text(wide), "漢字漢字漢")
    Unit <- E.must_eq("wide split", String.join(row_chunks(wide), "|"), "漢字|漢字|漢")
    Unit <- E.must_eq("combining stays with base", String.join(row_chunks(V.wrap_line(line("éx"), 1, False{})), "|"), "é|x")
    Unit <- E.must_eq("joiner cluster kept", String.join(row_chunks(V.wrap_line(line("a👩‍💻b"), 4, False{})), "|"), "a|👩‍💻|b")
    Unit <- E.must_eq("regional pair kept", String.join(row_chunks(V.wrap_line(line("a🇰🇷b"), 2, False{})), "|"), "a|🇰🇷|b")
    Unit <- E.must_eq("modifier kept", String.join(row_chunks(V.wrap_line(line("👍🏽x"), 2, False{})), "|"), "👍🏽|x")
    Unit <- E.must_eq("forced cluster keeps source character count", Nat.show(V.rows_chars(V.wrap_line(line("👩‍💻x"), 1, False{}))), "4")
    Unit <- E.must_eq("wide cluster source count matches", Nat.show(V.rows_chars(V.wrap_line(line("👩‍💻x"), 4, False{}))), "4")
    Unit <- E.must_eq("ASCII positive", String.join(row_chunks(V.wrap_line(line("abcde"), 3, False{})), "|"), "abc|de")
    Unit <- E.must_eq("zero-width geometry terminates", rows_text(V.wrap_line(line("abc"), 0, False{})), "abc")
    IO.print("wrap_demo=ok")
