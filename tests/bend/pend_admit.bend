# SPDX-License-Identifier: Apache-2.0
# Live-tail admission uses the same pending prefix as paint.
# Eight one-row lines fill the 8-row pane exactly. The oldest line is the
# only image URL (admission ignores non-image links). One pending row at
# ScrollAt{0,0} makes nine rows, and the crop keeps the last eight, so
# that URL leaves both paint and admission. The pending row is Cl.Pending
# and stays ineligible. ScrollAt{1,0} does not prepend, so the URL stays.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/media.bend as M
import ../../src/bend/split.bend as Sp
import ../../src/bend/theme.bend as Theme
import ../../src/bend/view.bend as V

def line_text.on(url: Bool, +id: Nat) -> String:
  match url:
    case True{}: "http://a.co/a.png"
    case False{}: "m" ++ Nat.show(id)

def line_text(+id: Nat) -> String:
  line_text.on(Nat.is_eq(id, 1n), id)

# Newest-first. buf_indexed stores oldest-first and builds newest itself.
def cons_lines(fuel: Nat, +id: Nat, +acc: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match fuel:
    case 0n: acc
    case 1n+p:
      cons_lines(p, Nat.add(id, 1n), Cl.Line{Cl.Msg{}, "", line_text(id), "a", id} <> acc)

def chan_at(scroll: Cl.Scroll) -> Cl.Buffer:
  Cl.buf_indexed("#t", True{}, "", List.reverse(&2, Cl.Line, cons_lines(8n, 1n, Nil{})), Nil{}, scroll)

def chan() -> Cl.Buffer:
  chan_at(Cl.ScrollAt{0n, 0n})

def chan_up() -> Cl.Buffer:
  chan_at(Cl.ScrollAt{1n, 0n})

def quiet() -> Cl.Settings:
  Cl.set_ts(Cl.settings0(), False{})

def client(b: Cl.Buffer) -> Cl.Client:
  Cl.Client{"me", "s", b <> Nil{}, 0n, "", quiet(), Cl.AuthIdle{}, 0n, False{}}

def iso() -> Cl.Iso:
  Cl.Iso.defaults()

def one_pend() -> List<&2, Cl.PendSend>:
  Cl.PendSend{"#t", "", "", "", "", "pending-row http://b.co/b.png", "", Cl.Self{}, 0n} <> Nil{}

def pane_h() -> Nat:
  V.vis_h(12)

def pane_w() -> U32:
  V.rect_vis_w(V.lay_body_rect(V.lay(12, 60, 0)))

def boxed(pends: List<&2, Cl.PendSend>) -> List<&2, V.PaintOpts>:
  V.paint_media_cards_iso_theme(iso(), M.empty(), Nil{}, Theme.Dark{}, pends)

def paint_rows(b: Cl.Buffer, boxed: List<&2, V.PaintOpts>) -> List<&2, V.BodyRow>:
  V.paint_body_buf(b, pane_h(), pane_w(), False{}, Nil{}, True{}, True{}, "s", boxed)

def row_text(row: V.BodyRow) -> String:
  match row:
    case V.BodyRow{_, _, _, _, _, spans, _}: V.spans_text(spans)
    case V.BodyRecon{text, _}: text
    case V.BodyMedia{_, _, _, _}: ""

def row_step(acc: String, row: V.BodyRow) -> String:
  acc ++ "|" ++ row_text(row)

def row_texts(xs: List<&2, V.BodyRow>) -> String:
  List.foldl(~&2, ~V.BodyRow, ~String, ~row_step, xs, "")

def paint_pend() -> String:
  row_texts(paint_rows(chan(), boxed(one_pend())))

def paint_nil() -> String:
  row_texts(paint_rows(chan(), boxed(Nil{})))

def paint_plain() -> String:
  row_texts(paint_rows(chan(), V.paint_text()))

def cand_url(c: M.Candidate) -> String:
  match c:
    case M.Candidate{_, url}: url

def cand_step(acc: String, c: M.Candidate) -> String:
  acc ++ "|" ++ cand_url(c)

def cand_urls(xs: List<&2, M.Candidate>) -> String:
  List.foldl(~&2, ~M.Candidate, ~String, ~cand_step, xs, "")

def admit(b: Cl.Buffer, pends: List<&2, Cl.PendSend>) -> String:
  cand_urls(V.visible_media_candidates_cards_iso_pends(iso(), client(b), 12, 60, Sp.Off{}, M.empty(), Nil{}, pends))

def admit_pend() -> String:
  admit(chan(), one_pend())

def admit_nil() -> String:
  admit(chan(), Nil{})

def admit_up() -> String:
  admit(chan_up(), one_pend())

def seen(hit: Bool) -> String:
  match hit:
    case True{}: "yes"
    case False{}: "no"

def has(s: String, needle: String) -> String:
  seen(String.contains(s, needle))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("pend paint shows overlay", has(paint_pend(), "pending-row"), "yes")
    Unit <- E.must_eq("pend paint drops pushed url", has(paint_pend(), "a.co/a.png"), "no")
    Unit <- E.must_eq("pend admission drops pushed url", has(admit_pend(), "a.co/a.png"), "no")
    Unit <- E.must_eq("pend admission skips pending url", has(admit_pend(), "b.co/b.png"), "no")
    Unit <- E.must_eq("empty paint shows pushed url", has(paint_nil(), "a.co/a.png"), "yes")
    Unit <- E.must_eq("plain paint shows pushed url", has(paint_plain(), "a.co/a.png"), "yes")
    Unit <- E.must_eq("empty paint has no overlay", has(paint_nil(), "pending-row"), "no")
    Unit <- E.must_eq("empty admission shows pushed url", has(admit_nil(), "a.co/a.png"), "yes")
    Unit <- E.must_eq("scrolled admission keeps pushed url", has(admit_up(), "a.co/a.png"), "yes")
    Unit <- E.must_eq("live pend paint and admission agree", has(paint_pend(), "a.co/a.png"), has(admit_pend(), "a.co/a.png"))
    Unit <- E.must_eq("empty paint and admission agree", has(paint_nil(), "a.co/a.png"), has(admit_nil(), "a.co/a.png"))
    IO.print("pend_admit=ok")
