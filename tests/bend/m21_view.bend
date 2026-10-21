# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/view.bend as V
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/columns.bend as C
import ../../src/bend/history.bend as H

def text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ text(t)

def chunks(rows: List<&2, V.BodyRow>) -> List<&2, String>:
  match rows:
    case Nil{}: Nil{}
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}: text(spans) <> chunks(t)
    case Con{_, t}: chunks(t)

def line(+s: String) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", s, "", 1n}

def wrap(+s: String, w: U32) -> String:
  String.join(chunks(V.wrap_line(line(s), w, False{})), "|")

def span(+attrs: U32, +s: String) -> String:
  U32.show(attrs) ++ ":" ++ s

def styles(xs: List<&2, V.SpanOp>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{V.Spn{attrs, s}, t}: span(attrs, s) <> styles(t)
    case Con{V.Col{attrs, _, s}, t}: span(attrs, s) <> styles(t)
    case Con{V.Lnk{url, s}, t}: (url ++ ":" ++ s) <> styles(t)

def rendered(+s: String) -> String:
  String.join(styles(V.line_spans_for(Cl.Msg{}, s)), "|")

def header_bound(xs: List<&2, V.DrawOp>, +x0: U32, +y0: U32, +right: U32) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{V.OpText{+x, y, w, _, _, _}, t}:
      U32.is_ge(x, x0) && U32.is_eq(y, y0) && U32.is_le(U32.add(x, w), right)
        && header_bound(t, x0, y0, right)
    case _: False{}

def status_at(xs: List<&2, V.DrawOp>, +want: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{V.OpText{x, _, w, _, _, +s}, t}:
      (String.eq(s, "online") && U32.is_eq(x, want) && U32.is_eq(w, 6)) || status_at(t, want)
    case Con{_, t}: status_at(t, want)

def history_render(entry: Maybe<&2, H.HistEntry>) -> String:
  match entry:
    case Some{H.Entry{_, Cl.Line{_, _, source, _, _}}}: text(V.line_spans_for(Cl.Msg{}, source))
    case _: "rejected"

def history(+s: String) -> String:
  history_render(H.parse_line_for("irc:6667", "BIRC2\tirc:6667\talice\tMSG\t12:00:00\talice\t" ++ s))

def links(xs: List<&2, V.BodyRow>, +url: String) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{V.BodyRow{_, _, _, _, _, Con{V.Lnk{target, _}, Nil{}}, _}, t}:
      String.eq(target, url) && links(t, url)
    case _: False{}

def colored_cluster(xs: List<&2, V.SpanOp>) -> Bool:
  match xs:
    case Con{V.Col{attrs, fg, text}, Con{V.Spn{_, next}, Nil{}}}:
      U32.is_eq(attrs, 1) && U32.is_eq(fg, 123) && String.eq(text, "❤️") && String.eq(next, "X")
    case _: False{}

def word_anchor(+width: U32) -> String:
  +b: Cl.Buffer = Cl.buf_indexed("server", False{}, "", [line("hello   world again")], Nil{}, Cl.ScrollAt{0n, 0n})
  +paused = V.hold_buf(V.scroll_buf(b, 1n, 8, False{}, Nil{}, True{}, True{}, "irc", 1n, 0n))
  String.join(chunks(V.body_of.buf(paused, 1n, width, False{}, Nil{}, True{}, True{}, "irc")), "|")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("prefer whole words", wrap("hello world", 8), "hello|world")
    Unit <- E.must_eq("word boundaries cross styles", wrap("hello **world** again", 8), "hello|world|again")
    Unit <- E.must_eq("exact fit remains one row", wrap("hello world", 11), "hello world")
    Unit <- E.must_eq("oversize word hard wraps", wrap("abcdefghijk", 4), "abcd|efgh|ijk")
    Unit <- E.must_eq("space after exact word fit", wrap("hello world", 5), "hello|world")
    Unit <- E.must_eq("boundary space run is hidden", wrap("hello   world", 8), "hello|world")
    Unit <- E.must_eq("space run crosses hard boundary", wrap("hello   world", 6), "hello|world")
    Unit <- E.must_eq("hidden spaces retain source count", Nat.show(V.rows_chars(V.wrap_line(line("hello   world"), 8, False{}))), "13")
    Unit <- E.must_eq("combining style boundary", rendered("e*́*X"), "0:éX")
    Unit <- E.must_eq("emoji style boundary", wrap("👩*‍💻*X", 2), "👩‍💻|X")
    Unit <- E.must_eq("cluster-leading style", rendered("*e*́X"), "1:é|0:X")
    Unit <- E.must_eq("ordinary style boundary", rendered("e*X*"), "0:e|1:X")
    Unit <- E.must_eq("skin tone style boundary", wrap("👍*🏽*X", 2), "👍🏽|X")
    Unit <- E.must_eq("regional indicator style boundary", wrap("🇰*🇷*X", 2), "🇰🇷|X")
    Unit <- E.must_eq("variation selector style boundary", wrap("❤*️*X", 2), "❤️|X")
    Unit <- E.must_eq("empty runs do not steal cluster style", String.join(styles(V.cluster_spans([V.Spn{1, ""}, V.Spn{0, "e"}, V.Spn{1, "́"}, V.Spn{0, "X"}])), "|"), "0:éX")
    Unit <- E.must("cluster-leading color retained", colored_cluster(V.cluster_spans([V.Col{1, 123, "❤"}, V.Spn{0, "️X"}])))
    Unit <- E.must_eq("cluster attachment does not change exact link", String.join(styles(V.cluster_spans([V.Lnk{"https://example.test/e", "e"}, V.Spn{1, "́"}, V.Spn{0, "X"}])), "|"), "https://example.test/e:é|0:X")
    Unit <- E.must_eq("unsplit cluster positive", wrap("👩‍💻X", 2), "👩‍💻|X")
    Unit <- E.must_eq("CJK hard fallback", wrap("漢字漢字漢", 5), "漢字|漢字|漢")
    Unit <- E.must_eq("do not separate space plus combining mark", wrap("a ́b", 2), "a ́|b")
    Unit <- E.must_eq("word wrap keeps hanging prefix", wrap("<a> hello world", 11), "<a> hello|world")
    Unit <- E.must_eq("long first word does not strand prefix", wrap("<a> abcdef", 8), "<a> abcd|ef")
    Unit <- E.must_eq("prefix width includes cross-boundary ZWJ cluster", U32.show(V.msg_prefix_w("<👩‍> hello")), U32.show(C.text_width("<👩‍> ")))
    Unit <- E.must_eq("ordinary prefix width control", U32.show(V.msg_prefix_w("<alice> hello")), "8")
    Unit <- E.must_eq("combining nickname prefix width control", U32.show(V.msg_prefix_w("<́> hello")), U32.show(C.text_width("<́> ")))
    Unit <- E.must_eq("prefix owns an attached nickname combining mark", rendered("<́> hello"), "0:<́> hello")
    Unit <- E.must_eq("word anchor remains at unchanged width", word_anchor(8), "world")
    Unit <- E.must_eq("word anchor survives narrower wrap", word_anchor(5), "world")
    Unit <- E.must_eq("word anchor survives wider wrap", word_anchor(13), "hello   world")
    Unit <- E.must("hidden header", List.is_empty(&2, V.DrawOp, V.user_header_ops(V.Rect{0, 0, 0, 0}, "me", "irc", "online")))
    Unit <- E.must("zero-height header", List.is_empty(&2, V.DrawOp, V.user_header_ops(V.Rect{5, 2, 20, 0}, "me", "irc", "online")))
    Unit <- E.must("header constrained to allocated rectangle", header_bound(V.user_header_ops(V.Rect{5, 2, 4, 1}, "me", "irc", "online"), 5, 2, 9))
    Unit <- E.must("ASCII header control", status_at(V.user_header_ops(V.Rect{0, 0, 30, 1}, "me", "irc", "online"), 9))
    Unit <- E.must("wide header column allocation", status_at(V.user_header_ops(V.Rect{0, 0, 30, 1}, "漢", "irc", "online"), 9))
    Unit <- E.must("combining header column allocation", status_at(V.user_header_ops(V.Rect{0, 0, 30, 1}, "é", "irc", "online"), 8))
    Unit <- E.must_eq("header geometry uses display columns", U32.show(V.user_w("漢@irc · online")), U32.show(C.text_width("漢@irc · online")))
    Unit <- E.must_eq("history noncanonical prefix preserved", history("<alice>oops"), "<alice>oops")
    Unit <- E.must_eq("history missing closer preserved", history("<alice"), "<alice")
    Unit <- E.must_eq("ordinary history prefix control", history("<alice> hello"), "<alice> hello")
    +url : String = "https://example.test/very-long-path"
    Unit <- E.must("hard-wrapped URLs keep exact targets", links(V.wrap_line(line(url), 8, False{}), url))
    IO.print("m21_view=ok")
