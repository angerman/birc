# SPDX-License-Identifier: Apache-2.0
# Page scroll keeps the walk the session stored; the next paint crops it.
# A one-notch move misses and still paints a full viewport.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/isupport.bend as Is
import ../../src/bend/session.bend as S
import ../../src/bend/view.bend as V

# 20 Monday lines then 20 Tuesday lines. Each line is one row at width 40.
def cons_dated(fuel: Nat, +id: Nat, +ts: String, +acc: List<&2, Cl.Line>) -> List<&2, Cl.Line>:
  match fuel:
    case 0n: acc
    case 1n+p:
      cons_dated(p, Nat.add(id, 1n), ts, Cl.Line{Cl.Msg{}, ts, "m" ++ Nat.show(id), "a", id} <> acc)

def many() -> Cl.Buffer:
  +older = cons_dated(20n, 1n, "2026-10-20 (Monday)|12:00:00", Nil{})
  +newer = cons_dated(20n, 21n, "2026-10-21 (Tuesday)|12:00:00", older)
  Cl.buf_indexed("#t", True{}, "", List.reverse(&2, Cl.Line, newer), Nil{}, Cl.ScrollAt{0n, 0n})

def quiet() -> Cl.Settings:
  Cl.set_ts(Cl.settings0(), False{})

def live_cl() -> Cl.Client:
  Cl.Client{"me", "s", many() <> Nil{}, 0n, "", quiet(), Cl.AuthIdle{}, 0n, False{}}

# 12x60 Off is an 8x40 history pane, the same window the old scroll golden used.
def base_st() -> S.Session:
  S.session_set_size(S.session_set_client(S.session0("me", "s", ""), live_cl()), 12, 60)

def keys_move(+up: Nat, +dn: Nat) -> S.Keys:
  S.Keys{"", False{}, Cl.TabStay{}, None{}, up, dn, S.HistStay{}, 0, 0}

def stepped(trip: S.Session & S.NetCmd & Bool) -> S.Session:
  match trip:
    case (+st, _, _): st

# Park 24 rows up from live, then move. Both steps go through session keys,
# which is the path that stores the walk for the next paint.
def parked_st() -> S.Session:
  stepped(S.step_keys(base_st(), keys_move(24n, 0n)))

def page_st() -> S.Session:
  stepped(S.step_keys(parked_st(), keys_move(0n, 8n)))

def notch_st() -> S.Session:
  stepped(S.step_keys(parked_st(), keys_move(1n, 0n)))

def with_joins(+st: S.Session, on: Bool) -> S.Session:
  +cl = S.session_cl(st)
  S.session_set_client(st, Cl.set_settings(cl, Cl.set_joins(Cl.get_settings(cl), on)))

# The frame painter. Nil hold is the cold full wrap of this same window.
def paint_st.at(+st: S.Session, size: S.Size, +hold: List<&2, V.ScrollHold>) -> V.ViewModel & List<&2, V.BodyRow> & Bool:
  match size:
    case S.Size{rows, cols}:
      V.view_draft.state_typing_media_cards_iso_themed(Is.as_iso(S.session_iso(st)), S.session_cl(st), rows, cols, "", "online", Nil{}, S.session_split(st), S.session_media(st), Nil{}, S.session_theme(st), S.session_pends(st), hold)

def paint_st(+st: S.Session, +hold: List<&2, V.ScrollHold>) -> V.ViewModel & List<&2, V.BodyRow> & Bool:
  paint_st.at(st, S.session_size(st), hold)

def paint_held(+st: S.Session) -> V.ViewModel & List<&2, V.BodyRow> & Bool:
  paint_st(st, S.session_scroll_hold(st))

def paint_cold(+st: S.Session) -> V.ViewModel & List<&2, V.BodyRow> & Bool:
  paint_st(st, Nil{})

def trip_rows(trip: V.ViewModel & List<&2, V.BodyRow> & Bool) -> List<&2, V.BodyRow>:
  match trip:
    case (_, +rows, _): rows

def trip_ok(trip: V.ViewModel & List<&2, V.BodyRow> & Bool) -> Bool:
  match trip:
    case (_, _, ok): ok

def trip_vm(trip: V.ViewModel & List<&2, V.BodyRow> & Bool) -> V.ViewModel:
  match trip:
    case (+vm, _, _): vm

def span_text(sp: V.SpanOp) -> String:
  match sp:
    case V.Spn{_, text}: text
    case V.Lnk{_, text}: text
    case V.Col{_, _, text}: text

def span_step(acc: String, sp: V.SpanOp) -> String:
  acc ++ span_text(sp)

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  List.foldl(~&2, ~V.SpanOp, ~String, ~span_step, xs, "")

def row_text(row: V.BodyRow) -> String:
  match row:
    case V.BodyRow{_, _, _, _, _, spans, _}: spans_text(spans)
    case V.BodyRecon{text, _}: text
    case V.BodyMedia{_, _, _, _}: ""

def row_step(acc: String, row: V.BodyRow) -> String:
  acc ++ "|" ++ row_text(row)

def row_texts(xs: List<&2, V.BodyRow>) -> String:
  List.foldl(~&2, ~V.BodyRow, ~String, ~row_step, xs, "")

def op_text(op: V.DrawOp) -> String:
  match op:
    case V.OpText{_, _, _, _, _, text}: text
    case V.OpLine{_, _, _, _, spans}: spans_text(spans)
    case V.OpGhost{_, _, _, _, text}: text
    case V.OpBox{_, _, _, _, _}: ""
    case V.OpSplit{_, _, _, _, _, _}: ""
    case V.OpTabs{_, _, _, _, _, _, _, _}: ""
    case V.OpImage{_, _, _, _, _}: ""
    case V.OpMedia{_, _, _, _, _, _, _}: ""

def op_step(acc: String, op: V.DrawOp) -> String:
  acc ++ "|" ++ op_text(op)

def ops_text(xs: List<&2, V.DrawOp>) -> String:
  List.foldl(~&2, ~V.DrawOp, ~String, ~op_step, xs, "")

def vm_text(+vm: V.ViewModel) -> String:
  match vm:
    case V.ViewModel{+ops, _}: ops_text(ops)

def scroll_at(s: Cl.Scroll) -> String:
  match s:
    case Cl.ScrollAt{after, tail}: Nat.show(after) ++ ":" ++ Nat.show(tail)

def client_at(+st: S.Session) -> String:
  scroll_at(Cl.active_scroll(S.session_cl(st)))

def hold_at(xs: List<&2, V.ScrollHold>) -> String:
  match xs:
    case Nil{}: "missing"
    case Con{+h, _}: scroll_at(Cl.buf_scroll(V.hold_buf(h)))

def hold_crop(xs: List<&2, V.ScrollHold>) -> List<&2, V.BodyRow>:
  match xs:
    case Nil{}: Nil{}
    case Con{+h, _}: V.visible_anchored(V.hold_rows(h), 8n, Cl.buf_scroll(V.hold_buf(h)))

def page_rows() -> String:
  row_texts(trip_rows(paint_held(page_st())))

def page_cold_rows() -> String:
  row_texts(trip_rows(paint_cold(page_st())))

def page_ops() -> String:
  vm_text(trip_vm(paint_held(page_st())))

def page_cold_ops() -> String:
  vm_text(trip_vm(paint_cold(page_st())))

def page_crop_rows() -> String:
  +st = page_st()
  row_texts(hold_crop(S.session_scroll_hold(st)))

def notch_rows() -> String:
  row_texts(trip_rows(paint_held(notch_st())))

def notch_cold_rows() -> String:
  row_texts(trip_rows(paint_cold(notch_st())))

def notch_ops() -> String:
  vm_text(trip_vm(paint_held(notch_st())))

def notch_cold_ops() -> String:
  vm_text(trip_vm(paint_cold(notch_st())))

def joins_st() -> S.Session:
  with_joins(page_st(), False{})

def joins_rows() -> String:
  row_texts(trip_rows(paint_held(joins_st())))

def joins_cold_rows() -> String:
  row_texts(trip_rows(paint_cold(joins_st())))

def differ(+tag: String, +a: String, +b: String) -> IO(Unit):
  E.must(tag ++ " a=[" ++ a ++ "] b=[" ++ b ++ "]", Bool.not(String.eq(a, b)))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("page_reuses_walk", trip_ok(paint_held(page_st())))
    Unit <- E.must_eq("page_text", page_rows(), page_cold_rows())
    Unit <- E.must_eq("page_ops", page_ops(), page_cold_ops())
    Unit <- E.must_eq("page_matches_walk_crop", page_rows(), page_crop_rows())
    Unit <- E.must_eq("page_anchor", client_at(page_st()), hold_at(S.session_scroll_hold(page_st())))
    Unit <- differ("page_left_park", client_at(page_st()), client_at(parked_st()))
    Unit <- differ("page_left_notch", client_at(page_st()), client_at(notch_st()))
    Unit <- E.must_eq("page_full_viewport", Nat.show(List.length(&2, V.BodyRow, trip_rows(paint_held(page_st())))), "8")
    Unit <- E.must("page_keeps_day_bar", String.contains(page_rows(), "@2026-10-21"))
    Unit <- E.must("notch_does_not_reuse", Bool.not(trip_ok(paint_held(notch_st()))))
    Unit <- E.must_eq("notch_text", notch_rows(), notch_cold_rows())
    Unit <- E.must_eq("notch_ops", notch_ops(), notch_cold_ops())
    Unit <- E.must_eq("notch_full_viewport", Nat.show(List.length(&2, V.BodyRow, trip_rows(paint_held(notch_st())))), "8")
    Unit <- E.must_eq("notch_anchor", client_at(notch_st()), hold_at(S.session_scroll_hold(notch_st())))
    Unit <- differ("notch_left_park", client_at(notch_st()), client_at(parked_st()))
    Unit <- E.must("joins_miss", Bool.not(trip_ok(paint_held(joins_st()))))
    Unit <- E.must_eq("joins_text", joins_rows(), joins_cold_rows())
    IO.print("scroll_reuse=ok")
