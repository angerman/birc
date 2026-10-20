# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/history.bend as H
import ../../src/bend/view.bend as V

def show.go(lines: List<&2, Cl.Line>, +acc: String) -> String:
  match lines:
    case Nil{}: acc
    case Con{+h, +t}:
      match h:
        case Cl.Line{Cl.Day{}, _, +text, _, _}: show.go(t, acc ++ "DAY " ++ text ++ "|")
        case Cl.Line{_, +ts, +text, _, _}: show.go(t, acc ++ ts ++ " " ++ text ++ "|")

def show.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{_, _, _, +lines, _, _, _, _}}: show.go(lines, "")

def show(cl: Cl.Client) -> String:
  show.got(Cl.nth_buf(Cl.client_bufs(cl), 0n))

def paint.go(rows: List<&2, V.BodyRow>, +acc: String) -> String:
  match rows:
    case Nil{}: acc
    case Con{V.BodyRecon{+text, _}, +t}: paint.go(t, acc ++ "BAR " ++ text ++ "|")
    case Con{V.BodyRow{+ts, _, _, _, _, _, _}, +t}: paint.go(t, acc ++ "ROW " ++ ts ++ "|")
    case Con{_, +t}: paint.go(t, acc ++ "OTHER|")

def paint.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{+b}: paint.go(V.paint_body_of(b, 20n, 40, True{}, Nil{}, True{}, True{}, "irc", V.paint_text()), "")

def paint_buf(cl: Cl.Client) -> String:
  paint.got(Cl.nth_buf(Cl.client_bufs(cl), 0n))

def main() -> IO(Unit):
  +monday = Cl.set_now(Cl.init("me", "irc"), "2026-10-19 (Monday)|23:00:00")
  +late = Cl.client_log(monday, 0n, Cl.Msg{}, "<a> late")
  +again = Cl.client_log(late, 0n, Cl.Msg{}, "<a> still")
  +tuesday = Cl.client_log(Cl.set_now(again, "2026-10-20 (Tuesday)|00:01:00"), 0n, Cl.Msg{}, "<a> early")
  +dated: Cl.Line = Cl.Line{Cl.Msg{}, "2026-10-19 (Monday)|23:00:00", "<a> late", "", 1n}
  +other_pend: Cl.PendSend = Cl.PendSend{"#other", "#other", "", "x", "x", "x", "00:00:00", Cl.Self{}, 0n}
  +here_pend: Cl.PendSend = Cl.PendSend{"server", "server", "", "x", "x", "x", "00:00:00", Cl.Self{}, 0n}
  do IO<Unit>:
    Unit <- E.must_eq("history stores dated stamps, not Day lines", show(again), "2026-10-19 (Monday)|23:00:00 <a> late|2026-10-19 (Monday)|23:00:00 <a> still|")
    Unit <- E.must_eq("midnight keeps the next day's stamp on the message", show(tuesday), "2026-10-19 (Monday)|23:00:00 <a> late|2026-10-19 (Monday)|23:00:00 <a> still|2026-10-20 (Tuesday)|00:01:00 <a> early|")
    Unit <- E.must_eq("history wire keeps the day/time stamp", H.serialize_line("#room", dated), "#room\tMSG\t2026-10-19 (Monday)|23:00:00\t<a> late\n")
    Unit <- E.must("paint inserts a day bar for the first local day", String.contains(paint_buf(again), "BAR @2026-10-19 (Monday)"))
    Unit <- E.must("paint inserts the next local day bar after midnight", String.contains(paint_buf(tuesday), "BAR @2026-10-20 (Tuesday)"))
    Unit <- E.must("time gutter stays HMS", String.contains(paint_buf(tuesday), "ROW 00:01:00"))
    Unit <- E.must("foreign pending sends keep the live scroll spine", V.spine_live_pends("server", other_pend <> Nil{}))
    Unit <- E.must("local pending sends leave the live scroll spine", Bool.not(V.spine_live_pends("server", here_pend <> Nil{})))
    Unit <- E.must_eq("server-time keeps the receipt local day", Cl.stamp_combine("2026-10-19 (Monday)|23:00:00", "00:01:00"), "2026-10-19 (Monday)|00:01:00")
    Unit <- E.must("reconnect bar stays a reconnect bar", String.contains(V.recon_divider("", 40), "Reconnected"))
    Unit <- E.must("day bar names the local date", String.contains(V.recon_divider("@2026-10-19 (Monday)", 40), "2026-10-19 (Monday)"))
    Unit <- E.must("day bar is not a reconnect label", Bool.not(String.contains(V.recon_divider("@2026-10-19 (Monday)", 40), "Reconnected")))
    IO.print("day_bar=ok")
