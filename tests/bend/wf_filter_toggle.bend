# Retroactive presence filter: feed always logs, the view hides on toggle.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/history.bend as H
import ../../src/bend/view.bend as V

def fed() -> Cl.Client:
  Feed.feed(
    Feed.feed(
      Feed.feed(
        Feed.feed(
          Feed.feed(
            Feed.feed(Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #t"), ":a!u@h JOIN #t"),
            ":a!u@h PRIVMSG #t :hi"),
          ":a!u@h NICK b"),
        ":b!u@h PART #t"),
      ":c!u@h JOIN #t"),
    ":c!u@h QUIT :bye")

def buf_lines.on(got: Maybe<&2, Cl.Buffer>) -> List<&2, Cl.Line>:
  match got:
    case None{}: Nil{}
    case Some{Cl.Buffer{_, _, _, +lines, _, _}}: lines

def buf_lines(+cl: Cl.Client, +i: Nat) -> List<&2, Cl.Line>:
  buf_lines.on(Cl.nth_buf(Cl.client_bufs(cl), i))

def chan_buf(+cl: Cl.Client) -> Cl.Buffer:
  V.active_buf.on(Cl.nth_buf(Cl.client_bufs(cl), 1n))

def ids.go(+xs: List<&2, Cl.Line>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{Cl.Line{_, _, _, _, +id}, t}: ids.go(t, acc ++ Nat.show(id) ++ "|")

def ids(+xs: List<&2, Cl.Line>) -> String:
  ids.go(xs, "")

def kinds.go(+xs: List<&2, Cl.Line>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{Cl.Line{+kind, _, _, _, _}, t}: kinds.go(t, acc ++ H.serialize_kind(kind) ++ "|")

def kinds(+xs: List<&2, Cl.Line>) -> String:
  kinds.go(xs, "")

def texts.go(+xs: List<&2, Cl.Line>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{Cl.Line{_, _, +text, _, _}, t}: texts.go(t, acc ++ text ++ "|")

def texts(+xs: List<&2, Cl.Line>) -> String:
  texts.go(xs, "")

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

def rows_text.go(+xs: List<&2, V.BodyRow>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+h, t}: rows_text.go(t, acc ++ row_text(h) ++ "|")

def rows_text(+xs: List<&2, V.BodyRow>) -> String:
  rows_text.go(xs, "")

def main() -> IO(Unit):
  +lines = buf_lines(fed(), 1n)
  +hidden = V.body_of.lines(lines, Nil{}, False{}, False{}, "#t", "s")
  +shown = V.body_of.lines(lines, Nil{}, True{}, True{}, "#t", "s")
  +hidden_cm = V.body_of.lines_cm(Cl.dflt_cm(), lines, Nil{}, False{}, False{}, "#t", "s")
  +muted = V.body_of.lines(lines, "a" <> Nil{}, True{}, True{}, "#t", "s")
  do IO<Unit>:
    Unit <- E.must_eq("feed logs presence and nick kinds", kinds(lines), "PRS|PRS|MSG|NCK|PRS|PRS|PRS|")
    Unit <- E.must_eq("hide drops presence and nick rows", texts(hidden), "<a> hi|")
    Unit <- E.must_eq("hide drops rows under casemapping", texts(hidden_cm), "<a> hi|")
    Unit <- E.must_eq("show restores identical ids", ids(shown), ids(lines))
    Unit <- E.must_eq("joins-only hide keeps nick rows", kinds(V.body_of.lines(lines, Nil{}, False{}, True{}, "#t", "s")), "MSG|NCK|")
    Unit <- E.must_eq("nicks-only hide keeps presence rows", kinds(V.body_of.lines(lines, Nil{}, True{}, False{}, "#t", "s")), "PRS|PRS|MSG|PRS|PRS|PRS|")
    Unit <- E.must_eq("mutes still apply first", texts(muted),
      "-> me joined #t|-> a joined #t|a is now known as b|<- b left #t|-> c joined #t|<- c quit (bye)|")
    Unit <- E.must_eq("paint hides toggled rows",
      rows_text(V.body_of.buf(chan_buf(fed()), 10n, 80, False{}, Nil{}, False{}, False{}, "s")), "<a> hi|")
    Unit <- E.must_eq("paint restores toggled rows",
      rows_text(V.body_of.buf(chan_buf(fed()), 10n, 80, False{}, Nil{}, True{}, True{}, "s")),
      "-> me joined #t|-> a joined #t|<a> hi|a is now known as b|<- b left #t|-> c joined #t|<- c quit (bye)|")
    IO.print("wf_filter_toggle=ok")
