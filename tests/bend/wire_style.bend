# SPDX-License-Identifier: Apache-2.0
# Native IRC wire formatting in the view: toggles, mIRC colors, safe reset
# and control handling, exact visible text, and unforgeable URLs. Local
# Markdown styles and view-only aliases keep working inside style runs.
import Base
import ./expect.bend as E
import ./view_preds.bend as VP
import ../../src/bend/view.bend as V
import ../../src/bend/view_laws.bend as VL
import ../../src/bend/wire_style.bend as Ws
import ../../src/bend/irc.bend as Irc
import ../../src/bend/links.bend as Links
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as H
import ../../src/bend/frame.bend as Fr
import ../../src/bend/replay.bend as R
import ../../src/bend/submit.bend as Sub
import ../../src/bend/media.bend as M
import ../../src/bend/typing.bend as Ty

def ctl(+n: U32, +s: String) -> String:
  SCon{Chr{n}, s}

def show(ops: List<&2, V.SpanOp>) -> String:
  match ops:
    case Nil{}: ""
    case Con{V.Spn{attrs, +text}, t}: U32.show(attrs) ++ "[" ++ text ++ "]" ++ show(t)
    case Con{V.Lnk{+url, +text}, t}: "L[" ++ url ++ "][" ++ text ++ "]" ++ show(t)
    case Con{V.Col{attrs, fg, +text}, t}: "C" ++ U32.show(fg) ++ "," ++ U32.show(attrs) ++ "[" ++ text ++ "]" ++ show(t)

def rendered(text: String) -> String:
  show(V.render_spans(text))

def legacy(text: String) -> String:
  show(VL.span_ops(VL.tokenize(text)))

def styled(text: String) -> String:
  show(V.line_spans_for(Cl.Msg{}, text))

def has_control(+s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{+h, t}: Ws.wire_drop(h) || has_control(t)

def spans_clean(+xs: List<&2, V.SpanOp>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+sp, t}: Bool.not(has_control(V.span_text(sp))) && spans_clean(t)

def actionstyled(text: String) -> String:
  show(V.line_spans_for(Cl.Action{}, text))

def styled_url() -> String:
  "https://x.test/a"

def styled_privmsg() -> String:
  ":a!a@h PRIVMSG #t :" ++ ctl(2, "bold") ++ " see " ++ ctl(3, "04" ++ styled_url()) ++ " end"

def styled_client() -> Cl.Client:
  Feed.feed_all(Cl.init("me", "s"), ":me!m@h JOIN #t" <> styled_privmsg() <> Nil{})

def styled_birc2() -> String:
  H.extract_new_history_for("s:6667", Cl.init("me", "s"), styled_client())

def restored.state(state: H.ReadState) -> Cl.Client:
  match state:
    case H.ReadState{cl, _, _, _}: cl

def restored(+text: String) -> Cl.Client:
  restored.state(H.read_chunk(Fr.string_to_octets(text), H.ReadState{Cl.init("me", "s"), Nil{}, 0n, False{}}, "s:6667", 1024))

def last_line.rev(+xs: List<&2, Cl.Line>) -> Cl.Line:
  match xs:
    case Nil{}: Cl.Line{Cl.Msg{}, "", "", "", 0n}
    case Con{+h, _}: h

def last_line(+xs: List<&2, Cl.Line>) -> Cl.Line:
  last_line.rev(List.reverse(&2, Cl.Line, xs))

def last_text.line(+line: Cl.Line) -> String:
  match line:
    case Cl.Line{_, _, +text, _, _}: text

def last_text(+xs: List<&2, Cl.Line>) -> String:
  last_text.line(last_line(xs))

def replayed.state(+state: R.ReadState) -> Cl.Client:
  match state:
    case R.ReadState{+cl, _, _}: cl

def replayed() -> Cl.Client:
  replayed.state(R.chunk(R.ReadState{Cl.init("me", "s"), Nil{}, False{}}, List.append(&2, U32, Fr.crlf(":me!m@h JOIN #t"), Fr.crlf(styled_privmsg()))))

def buf_last_text.on(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{_, _, _, +lines, _, _}}: last_text(lines)

def buf_last_text(+cl: Cl.Client, +i: Nat) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _}:
      buf_last_text.on(Cl.nth_buf(bufs, i))

def buf_topic.on(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{_, _, +topic, _, _, _}}: topic

def buf_topic(+cl: Cl.Client, +i: Nat) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _}:
      buf_topic.on(Cl.nth_buf(bufs, i))

def palette() -> String:
  U32.show(Ws.fg_of(0)) ++ "," ++ U32.show(Ws.fg_of(1)) ++ "," ++ U32.show(Ws.fg_of(2)) ++ "," ++ U32.show(Ws.fg_of(3))
    ++ "," ++ U32.show(Ws.fg_of(4)) ++ "," ++ U32.show(Ws.fg_of(5)) ++ "," ++ U32.show(Ws.fg_of(6)) ++ "," ++ U32.show(Ws.fg_of(7))
    ++ "," ++ U32.show(Ws.fg_of(8)) ++ "," ++ U32.show(Ws.fg_of(9)) ++ "," ++ U32.show(Ws.fg_of(10)) ++ "," ++ U32.show(Ws.fg_of(11))
    ++ "," ++ U32.show(Ws.fg_of(12)) ++ "," ++ U32.show(Ws.fg_of(13)) ++ "," ++ U32.show(Ws.fg_of(14)) ++ "," ++ U32.show(Ws.fg_of(15))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("bold toggle", rendered(ctl(2, "hi" ++ ctl(2, ""))), "1[hi]")
    Unit <- E.must_eq("unclosed toggle ends with line", rendered(ctl(2, "hi")), "1[hi]")
    Unit <- E.must_eq("toggle pair cancels", rendered(ctl(2, "a" ++ ctl(2, "b"))), "1[a]0[b]")
    Unit <- E.must_eq("italic underline reverse strike", rendered(ctl(29, "i" ++ ctl(29, ctl(31, "u" ++ ctl(31, ctl(22, "r" ++ ctl(22, ctl(30, "s" ++ ctl(30, ""))))))))), "4[i]8[u]16[r]64[s]")
    Unit <- E.must_eq("combined toggles OR", rendered(ctl(2, ctl(29, "bi" ++ ctl(15, "")))), "5[bi]")
    Unit <- E.must_eq("reset clears toggles", rendered(ctl(2, "a" ++ ctl(15, "b"))), "1[a]0[b]")
    Unit <- E.must_eq("monospace consumed silently", rendered("a" ++ ctl(17, "b" ++ ctl(17, "c"))), "0[a]0[b]0[c]")
    Unit <- E.must_eq("two digit color", rendered(ctl(3, "04red" ++ ctl(15, " end"))), "C16711680,0[red]0[ end]")
    Unit <- E.must_eq("one digit color", rendered(ctl(3, "4red")), "C16711680,0[red]")
    Unit <- E.must_eq("background consumed and ignored", rendered(ctl(3, "04,02red")), "C16711680,0[red]")
    Unit <- E.must_eq("bare color resets fg", rendered(ctl(3, "04a" ++ ctl(3, "b"))), "C16711680,0[a]0[b]")
    Unit <- E.must_eq("reset clears color", rendered(ctl(3, "04a" ++ ctl(15, "b"))), "C16711680,0[a]0[b]")
    Unit <- E.must_eq("color keeps toggles", rendered(ctl(2, ctl(3, "04a" ++ ctl(15, "")))), "C16711680,1[a]")
    Unit <- E.must_eq("invalid color resets fg", rendered(ctl(3, "99x")), "0[x]")
    Unit <- E.must_eq("invalid color after valid resets fg", rendered(ctl(3, "04a" ++ ctl(3, "99b"))), "C16711680,0[a]0[b]")
    Unit <- E.must_eq("comma without fg is text", rendered(ctl(3, ",hello")), "0[,hello]")
    Unit <- E.must_eq("comma without bg digit is text", rendered(ctl(3, "4,hello")), "C16711680,0[,hello]")
    Unit <- E.must_eq("trailing comma is text", rendered(ctl(3, "04,")), "C16711680,0[,]")
    Unit <- E.must_eq("color at end of line", rendered("a" ++ ctl(3, "")), "0[a]")
    Unit <- E.must_eq("color digits at end of line", rendered("a" ++ ctl(3, "04")), "0[a]")
    Unit <- E.must_eq("full palette", palette(), "16777215,0,127,37632,16711680,8323072,10223772,16547584,16776960,64512,37779,65535,252,16711935,8355711,13816530")
    Unit <- E.must_eq("markdown inside wire style", rendered(ctl(2, "*md*" ++ ctl(15, ""))), "1[md]")
    Unit <- E.must_eq("wire breaks markdown spans", rendered("*a" ++ ctl(2, "b*")), "0[*a]1[b*]")
    Unit <- E.must_eq("alias inside color", rendered(ctl(3, "04:eyes:")), "C16711680,0[👀]")
    Unit <- E.must_eq("colored URL stays exact link", rendered(ctl(3, "04see https://x.test/a end" ++ ctl(15, ""))), "C16711680,0[see ]L[https://x.test/a][https://x.test/a]C16711680,0[ end]")
    Unit <- E.must_eq("style cannot forge link after alnum", rendered("a" ++ ctl(2, "https://x.test")), "0[a]1[https://x.test]")
    Unit <- E.must_eq("style keeps link after boundary", rendered(" " ++ ctl(2, "https://x.test")), "0[ ]L[https://x.test][https://x.test]")
    Unit <- E.must_eq("split URL stays literal", rendered("https://x.test" ++ ctl(2, ".frag")), "0[https://x.test]1[.frag]")
    Unit <- E.must_eq("complete URL before space keeps link", rendered("https://x.test" ++ ctl(2, " end")), "L[https://x.test][https://x.test]1[ end]")
    Unit <- E.must_eq("controls dropped from spans", rendered("a" ++ ctl(1, "b" ++ ctl(7, "c" ++ ctl(27, "d" ++ ctl(0, "e" ++ ctl(127, "f")))))), "0[a]0[b]0[c]0[d]0[e]0[f]")
    Unit <- E.must("painted spans are control free", spans_clean(V.render_spans("a" ++ ctl(1, "b" ++ ctl(2, "c" ++ ctl(3, "04d" ++ ctl(27, "e")))))))
    Unit <- E.must("styles never cross lines", String.eq(rendered(ctl(2, "a")), "1[a]") && String.eq(rendered("b"), "0[b]"))
    Unit <- E.must_eq("visible matches sanitize colors", Ws.visible(Ws.parse(ctl(3, "04red" ++ ctl(15, " end")))), Irc.sanitize_in(ctl(3, "04red" ++ ctl(15, " end"))))
    Unit <- E.must_eq("visible matches sanitize toggles", Ws.visible(Ws.parse(ctl(2, "a" ++ ctl(29, "b" ++ ctl(15, "c"))))), Irc.sanitize_in(ctl(2, "a" ++ ctl(29, "b" ++ ctl(15, "c")))))
    Unit <- E.must_eq("visible matches sanitize digits", Ws.visible(Ws.parse(ctl(3, "04,12x" ++ ctl(3, "99y")))), Irc.sanitize_in(ctl(3, "04,12x" ++ ctl(3, "99y"))))
    Unit <- E.must_eq("source bytes retained in line", V.spans_text(V.render_spans(ctl(3, "04red"))), "red")
    Unit <- E.must_eq("legacy adapter agrees", legacy(ctl(3, "04*a* " ++ ctl(2, "b"))), rendered(ctl(3, "04*a* " ++ ctl(2, "b"))))
    Unit <- E.must_eq("nick line keeps colors", styled("<a> " ++ ctl(3, "04hi")), "0[<]C16747674,1[a]0[> ]C16711680,0[hi]")
    Unit <- E.must_eq("leading color keeps safe fallback", styled(ctl(3, "04<a> hi")), "C16711680,0[<a> hi]")
    Unit <- E.must_eq("styled URL extracts exact", String.join(Links.extract(Ws.visible(Ws.parse(ctl(3, "04see https://x.test/a" ++ ctl(15, ""))))), ","), "https://x.test/a")
    Unit <- E.must_eq("hostile controls lexed safe", VP.show_ops(V.line_ops(Cl.Line{Cl.Msg{}, "", VP.hostile_body(), "", 0n})), "L:0|13158600|look Lhttps://evil.examplehttps://github.com/zw3rk/bircx")
    Unit <- E.must_eq("split spans keep exact text", V.spans_text(V.render_spans("a" ++ ctl(1, "b" ++ ctl(7, "c")))), "abc")
    Unit <- E.must_eq("soh splits spans", rendered("a" ++ ctl(1, "b")), "0[a]0[b]")
    Unit <- E.must_eq("soh cannot forge link", rendered("htt" ++ ctl(1, "ps://x.test")), "0[htt]0[ps://x.test]")
    Unit <- E.must("soh glued text has no painted link", Bool.not(VL.tokenize_has_link("htt" ++ ctl(1, "ps://x.test"))))
    Unit <- E.must_eq("soh byte suppressed", V.spans_text(V.render_spans("a" ++ ctl(1, "b"))), "ab")
    Unit <- E.must_eq("bell cannot glue link", rendered("htt" ++ ctl(7, "ps://x.test")), "0[htt]0[ps://x.test]")
    Unit <- E.must_eq("esc cannot glue link", rendered("htt" ++ ctl(27, "ps://x.test")), "0[htt]0[ps://x.test]")
    Unit <- E.must_eq("monospace cannot glue link", rendered("htt" ++ ctl(17, "ps://x.test")), "0[htt]0[ps://x.test]")
    Unit <- E.must_eq("adjacent toggles around url", rendered(ctl(2, ctl(29, styled_url() ++ ctl(15, "")))), "L[" ++ styled_url() ++ "][" ++ styled_url() ++ "]")
    Unit <- E.must_eq("trailing punct then style degrades", rendered("https://x.test." ++ ctl(2, "evil")), "0[https://x.test]0[.]1[evil]")
    Unit <- E.must("trailing punct style has no painted link", Bool.not(VL.tokenize_has_link("https://x.test." ++ ctl(2, "evil"))))
    Unit <- E.must_eq("punct space then style keeps link", rendered("https://x.test. " ++ ctl(2, "evil")), "L[https://x.test][https://x.test]0[. ]1[evil]")
    Unit <- E.must_eq("mid seg url then style keeps link", rendered("see https://a.test ok" ++ ctl(2, "more")), "0[see ]L[https://a.test][https://a.test]0[ ok]1[more]")
    Unit <- E.must_eq("url then style then more degrades", rendered("see https://a.test" ++ ctl(2, "more")), "0[see ]0[https://a.test]1[more]")
    Unit <- E.must_eq("url comma space keeps link", rendered("see " ++ styled_url() ++ ", ok"), "0[see ]L[" ++ styled_url() ++ "][" ++ styled_url() ++ "]0[, ok]")
    Unit <- E.must_eq("combining kept with style", rendered(ctl(2, "e" ++ SCon{Chr{769}, ""})), "1[e" ++ SCon{Chr{769}, "]"})
    Unit <- E.must_eq("toggle inside cluster keeps cluster", styled("e" ++ ctl(2, SCon{Chr{769}, "x"})), "0[e" ++ SCon{Chr{769}, "]1[x]"})
    Unit <- E.must_eq("toggle inside zwj keeps cluster", V.spans_text(V.line_spans_for(Cl.Msg{}, "👩" ++ ctl(2, SCon{Chr{8205}, "💻"}))), "👩" ++ SCon{Chr{8205}, "💻"})
    Unit <- E.must_eq("action stores styles", CL.buf_texts(Feed.feed_all(Cl.init("me", "s"), ":me!m@h JOIN #t" <> (":a!a@h PRIVMSG #t :" ++ ctl(1, "ACTION " ++ ctl(2, "waves") ++ ctl(1, ""))) <> Nil{}), 1n), "-> me joined #t|* a " ++ ctl(2, "waves") ++ "|")
    Unit <- E.must_eq("action paints styles", actionstyled("* a " ++ ctl(2, "waves")), "0[* ]C16747674,1[a]0[ ]1[waves]")
    Unit <- E.must_eq("keep style controls", Irc.sanitize_keep_style("a" ++ ctl(2, "b" ++ ctl(3, "04c" ++ ctl(15, "d")))), "a" ++ ctl(2, "b" ++ ctl(3, "04c" ++ ctl(15, "d"))))
    Unit <- E.must_eq("keep drops field breaks", Irc.sanitize_keep_style("a\tb\rc\nd" ++ ctl(7, "e")), "abcde")
    Unit <- E.must_eq("keep visible matches sanitize", Ws.visible(Ws.parse(Irc.sanitize_keep_style(ctl(3, "04red" ++ ctl(15, " end"))))), Irc.sanitize_in(ctl(3, "04red" ++ ctl(15, " end"))))
    Unit <- E.must("control verb still dispatches", CL.has_buf(Feed.feed(Cl.init("me", "s"), ":me!u@h JO" ++ ctl(31, "IN #room")), "#room"))
    Unit <- E.must_eq("001 strips style nick", Cl.nick_of(Feed.feed(Cl.init("me", "s"), ":s 001 " ++ ctl(2, "bob") ++ " :welcome")), "bob")
    Unit <- E.must_eq("353 strips style nicks", CL.buf_nicks.idx(Feed.feed_all(Cl.init("me", "s"), ":me!m@h JOIN #t" <> (":s 353 me = #t :@alice " ++ ctl(2, "bob")) <> Nil{}), 1n), "me alice bob ")
    Unit <- E.must_eq("topic store strips styles", buf_topic(Feed.feed_all(Cl.init("me", "s"), ":me!m@h JOIN #t" <> (":a!a@h TOPIC #t :" ++ ctl(2, "hello")) <> Nil{}), 1n), "hello")
    Unit <- E.must_eq("topic log keeps styles", CL.buf_texts(Feed.feed_all(Cl.init("me", "s"), ":me!m@h JOIN #t" <> (":a!a@h TOPIC #t :" ++ ctl(2, "hello")) <> Nil{}), 1n), "-> me joined #t|a set topic: " ++ ctl(2, "hello") ++ "|")
    Unit <- E.must_eq("typing strips style nick", String.join(Ty.names(Ty.apply_line(Ty.empty(), "@+typing=active :a" ++ ctl(2, "li") ++ "ce!u@h TAGMSG #t", 1), "#t"), ","), "alice")
    Unit <- E.must_eq("feed stores style bytes", CL.buf_texts(styled_client(), 1n), "-> me joined #t|<a> " ++ ctl(2, "bold") ++ " see " ++ ctl(3, "04" ++ styled_url()) ++ " end|")
    Unit <- E.must("birc2 keeps style bytes", String.contains(styled_birc2(), ctl(2, "bold")) && String.contains(styled_birc2(), ctl(3, "04" ++ styled_url())))
    Unit <- E.must_eq("birc2 drops field breaks", H.serialize_line_for("e", "#t", Cl.Line{Cl.Msg{}, "ts", "a\tb\nc", "au", 0n}), "BIRC2\te\t#t\tMSG\tts\tau\tabc\n")
    Unit <- E.must_eq("birc2 roundtrip exact", CL.buf_texts(restored(styled_birc2()), 1n), CL.buf_texts(styled_client(), 1n))
    Unit <- E.must_eq("restored view keeps styles", show(V.line_spans_for(Cl.Msg{}, buf_last_text(restored(styled_birc2()), 1n))), "0[<]C16747674,1[a]0[> ]1[bold see ]L[" ++ styled_url() ++ "][" ++ styled_url() ++ "]C16711680,1[ end]")
    Unit <- E.must_eq("replay framer keeps styles", CL.buf_texts(replayed(), 1n), "-> me joined #t|<a> " ++ ctl(2, "bold") ++ " see " ++ ctl(3, "04" ++ styled_url()) ++ " end|")
    Unit <- E.must_eq("open extracts styled link", String.join(Sub.extract_urls(ctl(3, "04see " ++ styled_url() ++ ctl(15, ""))), ","), styled_url())
    Unit <- E.must_eq("open skips degraded link", String.join(Sub.extract_urls("https://x.test." ++ ctl(2, "evil")), ","), "")
    Unit <- E.must_eq("media sees visible image url", String.join(M.targets("pic " ++ ctl(2, "https://x.test/a.png") ++ " end"), ","), "https://x.test/a.png")
    IO.print("wire_style=ok")
