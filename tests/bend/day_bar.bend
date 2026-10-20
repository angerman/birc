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

def main() -> IO(Unit):
  +monday = Cl.set_now(Cl.init("me", "irc"), "2026-10-19 (Monday)\n23:00:00")
  +late = Cl.client_log(monday, 0n, Cl.Msg{}, "<a> late")
  +again = Cl.client_log(late, 0n, Cl.Msg{}, "<a> still")
  +tuesday = Cl.client_log(Cl.set_now(again, "2026-10-20 (Tuesday)\n00:01:00"), 0n, Cl.Msg{}, "<a> early")
  +day: Cl.Line = Cl.Line{Cl.Day{}, "", "2026-10-19 (Monday)", "", 1n}
  do IO<Unit>:
    Unit <- E.must_eq("same local day inserts one bar", show(again), "DAY 2026-10-19 (Monday)|23:00:00 <a> late|23:00:00 <a> still|")
    Unit <- E.must_eq("local midnight inserts the next bar", show(tuesday), "DAY 2026-10-19 (Monday)|23:00:00 <a> late|23:00:00 <a> still|DAY 2026-10-20 (Tuesday)|00:01:00 <a> early|")
    Unit <- E.must_eq("day bars persist", H.serialize_line("#room", day), "#room\tDAY\t\t2026-10-19 (Monday)\n")
    Unit <- E.must("reconnect bar stays a reconnect bar", String.contains(V.recon_divider("", 40), "Reconnected"))
    Unit <- E.must("day bar names the local date", String.contains(V.recon_divider("@2026-10-19 (Monday)", 40), "2026-10-19 (Monday)"))
    Unit <- E.must("day bar is not a reconnect label", Bool.not(String.contains(V.recon_divider("@2026-10-19 (Monday)", 40), "Reconnected")))
    IO.print("day_bar=ok")
