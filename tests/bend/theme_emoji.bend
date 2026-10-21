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
  +b: Cl.Buffer = Cl.buf_indexed("server", False{}, "", Cl.Line{Cl.Msg{}, "", "a:gem:b", "", 1n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})
  +scrolled = V.hold_buf(V.scroll_buf(b, 1n, 1, False{}, Nil{}, True{}, True{}, "s", 1n, 0n))
  String.eq(row_text(V.body_of.buf(scrolled, 1n, 1, False{}, Nil{}, True{}, True{}, "s")), "�")
    && String.eq(row_text(V.body_of.buf(scrolled, 1n, 2, False{}, Nil{}, True{}, True{}, "s")), "💎")

def each_resolves(xs: List<&2, Emoji.Entry>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{Emoji.Entry{name, text}, t}:
      String.eq(rendered(name), "0[" ++ text ++ "]") && each_resolves(t)

# N9.7: incoming Feed -> BIRC2 load -> production renderer roundtrip.
def no_line() -> Cl.Line:
  Cl.Line{Cl.Msg{}, "", "", "", 0n}

def fed_chan() -> Cl.Client:
  Feed.feed(Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #t"),
    ":alice!u@h PRIVMSG #t :hi :smile: *bold* https://x.test/a")

def buf_lines(+got: Maybe<&2, Cl.Buffer>) -> List<&2, Cl.Line>:
  match got:
    case None{}: Nil{}
    case Some{Cl.Buffer{_, _, _, lines, _, _, _, _}}: lines

def chan_lines(+cl: Cl.Client) -> List<&2, Cl.Line>:
  buf_lines(Cl.nth_buf(Cl.client_bufs(cl), 1n))

def last_line.go(xs: List<&2, Cl.Line>, +acc: Cl.Line) -> Cl.Line:
  match xs:
    case Nil{}: acc
    case Con{h, t}: last_line.go(t, h)

def stored_line() -> Cl.Line:
  last_line.go(chan_lines(fed_chan()), no_line())

def stored_text() -> String:
  line_text(stored_line())

def endpoint() -> String:
  "irc.test:6697"

def record() -> String:
  H.serialize_line_for(endpoint(), "#t", stored_line())

def record_body() -> String:
  String.take(record(), Nat.sub(String.length(record()), 1n))

def loaded_line.got(got: Maybe<&2, H.HistEntry>) -> Cl.Line:
  match got:
    case None{}: no_line()
    case Some{e}: H.entry_line(e)

def loaded_line() -> Cl.Line:
  loaded_line.got(H.parse_line_for(endpoint(), record_body()))

def line_kind(+ln: Cl.Line) -> String:
  match ln:
    case Cl.Line{kind, _, _, _, _}: H.serialize_kind(kind)

def line_author(+ln: Cl.Line) -> String:
  match ln:
    case Cl.Line{_, _, _, author, _}: author

def prod(+text: String) -> List<&2, V.SpanOp>:
  V.line_spans_for(Cl.Msg{}, text)

def prod_show(+text: String) -> String:
  show(prod(text))

def prod_text(+text: String) -> String:
  spans_text(prod(text))

def has_link.go(xs: List<&2, V.SpanOp>, +url: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{V.Lnk{+u, _}, t}: String.eq(u, url) || has_link.go(t, url)
    case Con{_, t}: has_link.go(t, url)

def has_bold.go(xs: List<&2, V.SpanOp>, +word: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{V.Spn{1, +text}, t}: String.eq(text, word) || has_bold.go(t, word)
    case Con{_, t}: has_bold.go(t, word)

def has_nick.go(xs: List<&2, V.SpanOp>, +nick: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{V.Col{_, _, +text}, t}: String.eq(text, nick) || has_nick.go(t, nick)
    case Con{_, t}: has_nick.go(t, nick)

def fed_code() -> Cl.Client:
  Feed.feed(Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #t"),
    ":bob!u@h PRIVMSG #t ::check: `:smile:` :nope: https://x.test/a.")

def stored_code() -> String:
  line_text(last_line.go(chan_lines(fed_code()), no_line()))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("table has 72 entries", Nat.show(List.length(&2, Emoji.Entry, Emoji.aliases())), "72")
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
    Unit <- E.must_eq("feed keeps raw source", stored_text(), "<alice> hi :smile: *bold* https://x.test/a")
    Unit <- E.must_eq("birc2 record keeps raw source", record(),
      "BIRC2\tirc.test:6697\t#t\tMSG\t\talice\t<alice> hi :smile: *bold* https://x.test/a\n")
    Unit <- E.must_eq("birc2 load restores text", line_text(loaded_line()), stored_text())
    Unit <- E.must_eq("birc2 load restores kind", line_kind(loaded_line()), "MSG")
    Unit <- E.must_eq("birc2 load restores author", line_author(loaded_line()), "alice")
    Unit <- E.must_eq("production renders glyph and styles",
      prod_text(line_text(loaded_line())), "<alice> hi 😄 bold https://x.test/a")
    Unit <- E.must("production keeps exact url", has_link.go(prod(line_text(loaded_line())), "https://x.test/a"))
    Unit <- E.must("production keeps bold style", has_bold.go(prod(line_text(loaded_line())), "bold"))
    Unit <- E.must("production colors nick", has_nick.go(prod(line_text(loaded_line())), "alice"))
    Unit <- E.must_eq("production spans exact", prod_show(line_text(loaded_line())),
      "0[<]1[alice]0[> hi 😄 ]1[bold]0[ ]L[https://x.test/a][https://x.test/a]")
    Unit <- E.must_eq("code feed keeps raw source", stored_code(), "<bob> :check: `:smile:` :nope: https://x.test/a.")
    Unit <- E.must_eq("production keeps code opaque", prod_text(stored_code()), "<bob> ✅ :smile: :nope: https://x.test/a.")
    Unit <- E.must("production trims url punctuation", has_link.go(prod(stored_code()), "https://x.test/a"))
    Unit <- E.must("unknown alias has no link", Bool.not(has_link.go(prod(":nope: here"), ":nope:")))
    IO.print("theme_emoji=ok")
