# SPDX-License-Identifier: Apache-2.0
# Characterize the measured media branches without changing latency gates.
import Base
import ./expect.bend as E
import ./ascii_row_projection.bend as P
import ../../src/bend/view.bend as V
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/media.bend as M

def span_eq(a: V.SpanOp, b: V.SpanOp) -> Bool:
  match a b:
    case V.Spn{x, s} V.Spn{y, t}: U32.is_eq(x, y) && String.eq(s, t)
    case V.Lnk{u, s} V.Lnk{v, t}: String.eq(u, v) && String.eq(s, t)
    case V.Col{x, c, s} V.Col{y, d, t}: U32.is_eq(x, y) && U32.is_eq(c, d) && String.eq(s, t)
    case _ _: False{}

def spans_eq(a: List<&2, V.SpanOp>, b: List<&2, V.SpanOp>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x, xs} Con{y, ys}: span_eq(x, y) && spans_eq(xs, ys)
    case _ _: False{}

def row_eq(a: V.BodyRow, b: V.BodyRow) -> Bool:
  match a b:
    case V.BodyRow{ts, tw, off, w, fg, spans, chars} V.BodyRow{ts2, tw2, off2, w2, fg2, spans2, chars2}:
      String.eq(ts, ts2) && U32.is_eq(tw, tw2) && U32.is_eq(off, off2) && U32.is_eq(w, w2)
        && U32.is_eq(fg, fg2) && spans_eq(spans, spans2) && Nat.is_eq(chars, chars2)
    case V.BodyRecon{text, w} V.BodyRecon{text2, w2}: String.eq(text, text2) && U32.is_eq(w, w2)
    case V.BodyMedia{token, w, h, row} V.BodyMedia{token2, w2, h2, row2}:
      U32.is_eq(token, token2) && U32.is_eq(w, w2) && U32.is_eq(h, h2) && U32.is_eq(row, row2)
    case _ _: False{}

def rows_eq(a: List<&2, V.BodyRow>, b: List<&2, V.BodyRow>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x, xs} Con{y, ys}: row_eq(x, y) && rows_eq(xs, ys)
    case _ _: False{}

def image_url() -> String:
  "https://x.test/image.png"

def ordinary_links(+n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: " https://x.test/page" ++ Nat.show(n) ++ ".html" ++ ordinary_links(p)

def corpus() -> String:
  "alice: 7 " ++ image_url() ++ ordinary_links(15n) ++ " tail"

def media(id: Nat) -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.Ready{M.Inline{id}, image_url(), 7}]}

def fallback_lines() -> List<&2, Cl.Line>:
  [Cl.Line{Cl.Highlight{}, "12:34:56", "alice: **bold** _italic_ :eyes: 漢👩‍💻 " ++ image_url(), "alice", 1n},
   Cl.Line{Cl.Error{}, "01:02:03", SCon{Chr{3}, "04red" ++ SCon{Chr{15}, " empty"}}, "", 2n},
   Cl.Line{Cl.Reconnect{}, "00:00:00", "IRC connection established", "", 3n},
   Cl.Line{Cl.System{}, "23:59:59", "", "", 4n}]

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, tail}: V.span_text(h) ++ spans_text(tail)

def row_sequence(xs: List<&2, V.BodyRow>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.BodyRow{_, _, _, _, _, spans, chars}, tail}: P.show(spans, chars) ++ row_sequence(tail)
    case Con{V.BodyMedia{_, _, _, _}, tail}: "#" ++ row_sequence(tail)
    case Con{_, tail}: "unexpected reconnect" ++ row_sequence(tail)

def images(xs: List<&2, V.BodyRow>) -> List<&2, V.BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{V.BodyMedia{token, w, h, row}, tail}: V.BodyMedia{token, w, h, row} <> images(tail)
    case Con{_, tail}: images(tail)

def flat_parts(xs: List<&2, V.MediaPart>) -> List<&2, V.SpanOp>:
  match xs:
    case Nil{}: Nil{}
    case Con{V.MediaPart{spans, _}, tail}: List.append(&2, V.SpanOp, spans, flat_parts(tail))

def ends_at_image(xs: List<&2, V.SpanOp>) -> Bool:
  match xs:
    case Con{V.Lnk{u, text}, Nil{}}: String.eq(u, image_url()) && String.eq(text, image_url())
    case Con{_, tail}: ends_at_image(tail)
    case Nil{}: False{}

def parts_shape(xs: List<&2, V.MediaPart>) -> Bool:
  match xs:
    case Con{V.MediaPart{first, Some{url}}, Con{V.MediaPart{rest, None{}}, Nil{}}}:
      String.eq(url, image_url()) && ends_at_image(first) && String.eq(spans_text(rest), ordinary_links(15n) ++ " tail")
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    +text : String = "alice: **bold** _italic_ :eyes: 漢👩‍💻 " ++ image_url()
    Unit <- E.must("empty media full stamped wrapped rows", rows_eq(V.wrapped_media(Cl.Highlight{}, "12:34:56", text, 24, True{}, 1n, M.empty()), V.wrapped_rows(Cl.Highlight{}, "12:34:56", text, 24, True{})))
    Unit <- E.must("wrong target full unstamped wrapped rows", rows_eq(V.wrapped_media(Cl.Highlight{}, "12:34:56", text, 1, False{}, 1n, media(999n)), V.wrapped_rows(Cl.Highlight{}, "12:34:56", text, 1, False{})))
    Unit <- E.must("empty media full body rows", rows_eq(V.body_rows_media(fallback_lines(), "#t", 24, True{}, M.empty()), V.body_rows(fallback_lines(), "#t", 24, True{})))
    Unit <- E.must("wrong target full body rows", rows_eq(V.body_rows_media(fallback_lines(), "#t", 1, False{}, media(999n)), V.body_rows(fallback_lines(), "#t", 1, False{})))
    Unit <- E.must("settings empty media stays unwrapped", rows_eq(V.body_rows_media(fallback_lines(), "*settings*", 24, True{}, M.empty()), V.body_rows(fallback_lines(), "*settings*", 24, True{})))
    Unit <- E.must("settings matching media stays unwrapped", rows_eq(V.body_rows_media(fallback_lines(), "*settings*", 1, False{}, media(1n)), V.body_rows(fallback_lines(), "*settings*", 1, False{})))
    +spans : List<&2, V.SpanOp> = V.line_spans_for(Cl.Msg{}, corpus())
    +parts : List<&2, V.MediaPart> = V.media_parts(spans, Nil{}, M.known_urls(media(1n), M.Inline{1n}))
    Unit <- E.must("sixteen links keep every complete span", spans_eq(flat_parts(parts), spans))
    Unit <- E.must("only known URL splits media parts", parts_shape(parts))
    +rows : List<&2, V.BodyRow> = V.wrapped_media(Cl.Msg{}, "", corpus(), 80, False{}, 1n, media(1n))
    Unit <- E.must("six exact known-token image rows", rows_eq(images(rows), V.media_rows(7, 80)))
    Unit <- E.must_eq("image rows directly follow known URL", row_sequence(rows), "alice: 7 " ++ image_url() ++ "######" ++ ordinary_links(15n) ++ " tail")
    Unit <- E.must("sixteen wrong-target links use legacy rows", rows_eq(V.wrapped_media(Cl.Msg{}, "", corpus(), 80, False{}, 1n, media(2n)), V.wrapped_rows(Cl.Msg{}, "", corpus(), 80, False{})))
    IO.print("media_branches=ok")
