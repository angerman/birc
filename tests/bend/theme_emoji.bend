# SPDX-License-Identifier: Apache-2.0
# Extended view-only emoji aliases: every entry resolves, source is kept.
import Base
import ./expect.bend as E
import ../../src/bend/emoji.bend as Emoji
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

def sent(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, lines): String.join(lines, "|")

def line_text(line: Cl.Line) -> String:
  match line:
    case Cl.Line{_, _, text, _, _}: text

def narrow_new_alias() -> Bool:
  +b: Cl.Buffer = Cl.Buffer{"server", False{}, "", Cl.Line{Cl.Msg{}, "", "a:gem:b", "", 1n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}}
  +scrolled = V.scroll_buf(b, 1n, 1, False{}, Nil{}, "s", 1n, 0n)
  String.eq(row_text(V.body_of.buf(scrolled, 1n, 1, False{}, Nil{}, "s")), "�")
    && String.eq(row_text(V.body_of.buf(scrolled, 1n, 2, False{}, Nil{}, "s")), "💎")

def each_resolves(xs: List<&2, Emoji.Entry>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{Emoji.Entry{name, text}, t}:
      String.eq(rendered(name), "0[" ++ text ++ "]") && each_resolves(t)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("table has 70 entries", Nat.show(List.length(&2, Emoji.Entry, Emoji.aliases())), "70")
    Unit <- E.must("every entry resolves to its glyph", each_resolves(Emoji.aliases()))
    Unit <- E.must_eq("new aliases render", rendered(":smile: :check: :sun: :dog: :gem:"), "0[😄 ✅ ☀ 🐶 💎]")
    Unit <- E.must_eq("old table intact", rendered(":eyes: :thumbs-up: :+1: :joy: :heart:"), "0[👀 👍 👍 🤣 ❤]")
    Unit <- E.must_eq("sun is not sunglasses", rendered(":sun:glasses:"), "0[☀glasses:]")
    Unit <- E.must_eq("sunglasses resolves", rendered(":sunglasses:"), "0[😎]")
    Unit <- E.must_eq("car is not cake", rendered(":car:pet:"), "0[🚗pet:]")
    Unit <- E.must_eq("cry is not crossed_fingers", rendered(":cry:help:"), "0[😢help:]")
    Unit <- E.must_eq("repeated alias", rendered(":smile::smile:"), "0[😄😄]")
    Unit <- E.must_eq("unknown stays literal", rendered(":notanalias:"), "0[:notanalias:]")
    Unit <- E.must_eq("case sensitive", rendered(":SMILE: :Smile:"), "0[:SMILE: :Smile:]")
    Unit <- E.must_eq("unclosed stays literal", rendered(":smile"), "0[:smile]")
    Unit <- E.must_eq("alias within style", rendered("**:smile:**"), "1[😄]")
    Unit <- E.must_eq("code stays opaque", rendered("`:smile:`"), "2[:smile:]")
    Unit <- E.must_eq("url stays exact", rendered("https://x.test/:smile:"), "L[https://x.test/:smile:][https://x.test/:smile:]")
    Unit <- E.must_eq("styled url stays opaque", rendered("_https://x.test/:smile:_"), "4[https://x.test/:smile:]")
    Unit <- E.must_eq("escaped alias", rendered("\\:smile:"), "0[:smile:]")
    +raw : Cl.Line = Cl.Line{Cl.Msg{}, "", ":smile: `:check:`", "", 0n}
    Unit <- E.must_eq("raw message retained", line_text(raw), ":smile: `:check:`")
    Unit <- E.must_eq("history stores raw source", H.serialize_line("#t", raw), "#t\tMSG\t\t:smile: `:check:`\n")
    Unit <- E.must_eq("sent IRC stores raw source", sent(Sub.submit(Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #t"), ":smile: hi")), "PRIVMSG #t ::smile: hi")
    Unit <- E.must_eq("wide alias keeps rendered source count", Nat.show(V.rows_chars(V.wrap_line(Cl.Line{Cl.Msg{}, "", ":smile:👩‍💻x", "", 0n}, 4, False{}))), "5")
    Unit <- E.must_eq("one-column alias keeps rendered source count", Nat.show(V.rows_chars(V.wrap_line(Cl.Line{Cl.Msg{}, "", ":smile:👩‍💻x", "", 0n}, 1, False{}))), "5")
    Unit <- E.must("new alias resize anchor", narrow_new_alias())
    IO.print("theme_emoji=ok")
