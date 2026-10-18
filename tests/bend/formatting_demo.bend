# SPDX-License-Identifier: Apache-2.0
# View-only formatting: raw source is not a rewritten IRC message.
import Base
import ./expect.bend as E
import ../../src/bend/view.bend as V
import ../../src/bend/view_laws.bend as VL
import ../../src/bend/links.bend as Links
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/submit.bend as Sub
import ../../src/bend/history.bend as H

def show(ops: List<&2, V.SpanOp>) -> String:
  match ops:
    case Nil{}: ""
    case Con{V.Spn{attrs, +text}, t}: U32.show(attrs) ++ "[" ++ text ++ "]" ++ show(t)
    case Con{V.Lnk{+url, +text}, t}: "L[" ++ url ++ "][" ++ text ++ "]" ++ show(t)
    case Con{V.Col{attrs, _, +text}, t}: U32.show(attrs) ++ "[" ++ text ++ "]" ++ show(t)

def rendered(text: String) -> String:
  show(VL.span_ops(VL.tokenize(text)))

def spans_text(spans: List<&2, V.SpanOp>) -> String:
  match spans:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text(t)

def row_text(rows: List<&2, V.BodyRow>) -> String:
  match rows:
    case Nil{}: ""
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, t}:
      spans_text(spans) ++ row_text(t)
    case _: "unexpected reconnect"

def line_text(line: Cl.Line) -> String:
  match line:
    case Cl.Line{_, _, text, _, _}: text

def sent(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, lines): String.join(lines, "|")

def alias_anchor() -> Bool:
  +b: Cl.Buffer = Cl.buf_indexed("server", False{}, "", Cl.Line{Cl.Msg{}, "", "a:eyes:b漢👩‍💻z", "", 1n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})
  +scrolled = V.scroll_buf(b, 1n, 2, False{}, Nil{}, True{}, True{}, "s", 3n, 0n)
  String.eq(row_text(V.body_of.buf(scrolled, 1n, 2, False{}, Nil{}, True{}, True{}, "s")), "b")
    && String.eq(row_text(V.body_of.buf(scrolled, 1n, 3, False{}, Nil{}, True{}, True{}, "s")), "b漢")

def narrow_alias_anchor() -> Bool:
  +b: Cl.Buffer = Cl.buf_indexed("server", False{}, "", Cl.Line{Cl.Msg{}, "", "a:eyes:b", "", 1n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})
  +scrolled = V.scroll_buf(b, 1n, 1, False{}, Nil{}, True{}, True{}, "s", 1n, 0n)
  String.eq(row_text(V.body_of.buf(scrolled, 1n, 1, False{}, Nil{}, True{}, True{}, "s")), "�")
    && String.eq(row_text(V.body_of.buf(scrolled, 1n, 2, False{}, Nil{}, True{}, True{}, "s")), "👀")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("single bold retained", rendered("*one*"), "1[one]")
    Unit <- E.must_eq("double bold", rendered("**two**"), "1[two]")
    Unit <- E.must_eq("nested bold italic", rendered("**B _BI_ B**"), "1[B ]5[BI]1[ B]")
    Unit <- E.must_eq("nested italic bold", rendered("_I *IB* I_"), "4[I ]5[IB]4[ I]")
    Unit <- E.must_eq("escaped literal markers", rendered("\\*plain\\* \\_plain\\_ \\`plain\\` \\\\tail"), "0[*plain* _plain_ `plain` \\tail]")
    Unit <- E.must_eq("opaque code", rendered("`**bold** _italic_ :eyes: https://x.test`"), "2[**bold** _italic_ :eyes: https://x.test]")
    Unit <- E.must_eq("bold code is not a URL", rendered("*`CODE`*"), "3[CODE]")
    Unit <- E.must_eq("known aliases", rendered(":eyes: :thumbs-up: :+1: :joy: :heart:"), "0[👀 👍 👍 🤣 ❤]")
    Unit <- E.must_eq("complete upstream table", rendered(":eyes::wave::thumbsup::thumbs-up::+1::tada::fire::rocket::heart::sparkles::bulb::clap::brain::zap::star::joy::raised_hands::bow::party::bug::globe::boom:"), "0[👀👋👍👍👍🎉🔥🚀❤✨💡👏🧠⚡⭐🤣🙌🙇🥳🐛🌍💥]")
    Unit <- E.must_eq("alias within style", rendered("**:eyes:**"), "1[👀]")
    Unit <- E.must_eq("unknown and case sensitive", rendered(":Eyes: :unknown:"), "0[:Eyes: :unknown:]")
    Unit <- E.must_eq("escaped alias", rendered("\\:eyes:"), "0[:eyes:]")
    Unit <- E.must_eq("exact opaque URL", rendered("https://x.test/a_b/:eyes:?q=**z**,"), "L[https://x.test/a_b/:eyes:?q=**z**][https://x.test/a_b/:eyes:?q=**z**]0[,]")
    Unit <- E.must_eq("styled URL remains opaque", rendered("_https://x.test/a_b/:eyes:_"), "4[https://x.test/a_b/:eyes:]")
    Unit <- E.must_eq("nested styled URL remains opaque", rendered("_**https://x.test/a_b/:eyes:**_"), "5[https://x.test/a_b/:eyes:]")
    Unit <- E.must_eq("nested URL style may close separately", rendered("**_https://x.test/a_b/:eyes:_ rest**"), "5[https://x.test/a_b/:eyes:]1[ rest]")
    Unit <- E.must_eq("ordinary style can close before a word", rendered("*bold*next"), "1[bold]0[next]")
    Unit <- E.must_eq("URL internal marker is literal and exact", rendered("*https://x.test*next"), "0[*]L[https://x.test*next][https://x.test*next]")
    Unit <- E.must_eq("opaque code does not escape its close", rendered("`\\`"), "2[\\]")
    Unit <- E.must_eq("styled URLs still excluded", String.join(Links.extract("**https://no.test** *https://no.test* _http://no.test_ `https://no.test` https://yes.test"), ","), "https://yes.test")
    Unit <- E.must_eq("unmatched source order", rendered("before **unclosed"), "0[before **unclosed]")
    Unit <- E.must_eq("unmatched double stays one literal token", rendered("**one*"), "0[**one*]")
    Unit <- E.must_eq("unmatched nested marker keeps order", rendered("*A _B*"), "1[A _B]")
    Unit <- E.must_eq("unknown escapes remain literal", rendered("\\q end\\"), "0[\\q end\\]")
    Unit <- E.must_eq("escaped close is not a close", rendered("*A\\*B*"), "1[A*B]")
    Unit <- E.must_eq("single bold does not consume double closer", rendered("*A**"), "0[*A**]")
    Unit <- E.must_eq("greedy triple delimiters", rendered("***bold***"), "1[*bold]0[*]")
    +raw : Cl.Line = Cl.Line{Cl.Msg{}, "", "**B _BI_ :eyes:** \\* `:fire:`", "", 0n}
    Unit <- E.must_eq("raw message retained", line_text(raw), "**B _BI_ :eyes:** \\* `:fire:`")
    Unit <- E.must_eq("history stores raw source", H.serialize_line("#t", raw), "#t\tMSG\t\t**B _BI_ :eyes:** \\* `:fire:`\n")
    Unit <- E.must_eq("sent IRC stores raw source", sent(Sub.submit(Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #t"), "**B _BI_ :eyes:** \\* `:fire:`")), "PRIVMSG #t :**B _BI_ :eyes:** \\* `:fire:`")
    Unit <- E.must_eq("Unicode wrap", row_text(V.wrap_line(Cl.Line{Cl.Msg{}, "", ":eyes:漢:rocket:", "", 0n}, 2, False{})), "👀漢🚀")
    Unit <- E.must("alias and cluster resize anchor", alias_anchor())
    Unit <- E.must("forced alias resize anchor", narrow_alias_anchor())
    Unit <- E.must_eq("one-column alias keeps rendered source count", Nat.show(V.rows_chars(V.wrap_line(Cl.Line{Cl.Msg{}, "", ":eyes:👩‍💻x", "", 0n}, 1, False{}))), "5")
    Unit <- E.must_eq("wide alias keeps rendered source count", Nat.show(V.rows_chars(V.wrap_line(Cl.Line{Cl.Msg{}, "", ":eyes:👩‍💻x", "", 0n}, 4, False{}))), "5")
    IO.print("formatting_demo=ok")
