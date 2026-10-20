# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
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

def bars.keep(day: Bool, +text: String, +acc: String) -> String:
  match day:
    case True{}: acc ++ "BAR " ++ text ++ "|"
    case False{}: acc

def bars.go(rows: List<&2, V.BodyRow>, +acc: String) -> String:
  match rows:
    case Nil{}: acc
    case Con{V.BodyRecon{+text, _}, +t}: bars.go(t, bars.keep(String.starts_with(text, "@"), text, acc))
    case Con{_, +t}: bars.go(t, acc)

def paint.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{+b}: paint.go(V.paint_body_of(b, 20n, 40, True{}, Nil{}, True{}, True{}, "irc", V.paint_text()), "")

def bars.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{+b}: bars.go(V.paint_body_of(b, 20n, 40, True{}, Nil{}, True{}, True{}, "irc", V.paint_text()), "")

def bars.hide_joins.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{+b}: bars.go(V.paint_body_of(b, 20n, 40, True{}, Nil{}, False{}, True{}, "irc", V.paint_text()), "")

def paint_buf(cl: Cl.Client) -> String:
  paint.got(Cl.nth_buf(Cl.client_bufs(cl), 0n))

def bars_buf(cl: Cl.Client) -> String:
  bars.got(Cl.nth_buf(Cl.client_bufs(cl), 0n))

def bars_hide_joins(cl: Cl.Client) -> String:
  bars.hide_joins.got(Cl.nth_buf(Cl.client_bufs(cl), 0n))

def bars.scrolled.got(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{+b}:
      bars.go(V.paint_body_of(Cl.set_buf_anchor(b, Cl.ScrollAt{1n, 0n}), 20n, 40, True{}, Nil{}, False{}, True{}, "irc", V.paint_text()), "")

def bars_hide_joins_scrolled(cl: Cl.Client) -> String:
  bars.scrolled.got(Cl.nth_buf(Cl.client_bufs(cl), 0n))

def day_anchor_tails.keep(day: Bool, +tail: Nat, +acc: String) -> String:
  match day:
    case True{}: acc ++ Nat.show(tail) ++ "|"
    case False{}: acc

def day_anchor_tails.go(rows: List<&2, V.AnchoredRow>, +acc: String) -> String:
  match rows:
    case Nil{}: acc
    case Con{V.AnchoredRow{V.BodyRecon{+text, _}, Cl.ScrollAt{_, +tail}, _}, +t}:
      day_anchor_tails.go(t, day_anchor_tails.keep(String.starts_with(text, "@"), tail, acc))
    case Con{_, +t}: day_anchor_tails.go(t, acc)

def day_anchor_tails.buf(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{+name, _, _, +lines, _, _, _, _}}:
      day_anchor_tails.go(V.paint_anchored(lines, name, 40, True{}, Nil{}, True{}, True{}, "irc", List.length(&2, Cl.Line, lines), V.paint_text()), "")

def day_anchor_tails(cl: Cl.Client) -> String:
  day_anchor_tails.buf(Cl.nth_buf(Cl.client_bufs(cl), 0n))

# Deep older history beyond day_tag_cap must still seed the in-window day bar.
def deep_monday.go(fuel: Nat, cl: Cl.Client) -> Cl.Client:
  match fuel:
    case 0n: cl
    case 1n+p: deep_monday.go(p, Cl.client_log(cl, 0n, Cl.Msg{}, "<a> pad"))

def deep_live_bars() -> String:
  +monday = Cl.set_now(Cl.init("me", "irc"), "2026-10-19 (Monday)|23:00:00")
  +padded = deep_monday.go(200n, monday)
  +tuesday = Cl.client_log(Cl.set_now(padded, "2026-10-20 (Tuesday)|00:01:00"), 0n, Cl.Msg{}, "<a> early")
  bars_hide_joins(tuesday)

def last_ts.go(lines: List<&2, Cl.Line>, +acc: String) -> String:
  match lines:
    case Nil{}: acc
    case Con{Cl.Line{_, +ts, _, _, _}, +t}: last_ts.go(t, ts)

def last_ts(cl: Cl.Client) -> String:
  last_ts.go(Cl.active_buf_lines(cl), "")

def main() -> IO(Unit):
  +monday = Cl.set_now(Cl.init("me", "irc"), "2026-10-19 (Monday)|23:00:00")
  +late = Cl.client_log(monday, 0n, Cl.Msg{}, "<a> late")
  +again = Cl.client_log(late, 0n, Cl.Msg{}, "<a> still")
  +tuesday = Cl.client_log(Cl.set_now(again, "2026-10-20 (Tuesday)|00:01:00"), 0n, Cl.Msg{}, "<a> early")
  +dated: Cl.Line = Cl.Line{Cl.Msg{}, "2026-10-19 (Monday)|23:00:00", "<a> late", "", 1n}
  +other_pend: Cl.PendSend = Cl.PendSend{"#other", "#other", "", "x", "x", "x", "00:00:00", Cl.Self{}, 0n}
  +here_pend: Cl.PendSend = Cl.PendSend{"server", "server", "", "x", "x", "x", "00:00:00", Cl.Self{}, 0n}
  +joined = Feed.feed(Cl.set_now(Cl.init("me", "irc"), "2026-10-19 (Monday)|23:00:00"), ":me!u@h JOIN #x")
  +stamped = Cl.set_active(Feed.feed_at(joined, ":alice!a@h PRIVMSG #x :hi", Some{"00:01:00"}), 1n)
  +recon = Cl.buf_modify_client(again, 0n, b => Cl.buf_reconnect(b, "23:01:00"))
  +after_recon = Cl.client_log(recon, 0n, Cl.Msg{}, "<a> later")
  +join_first = Cl.client_log(Cl.set_now(again, "2026-10-20 (Tuesday)|00:01:00"), 0n, Cl.Presence{}, "* a joined")
  +after_hidden_day = Cl.client_log(join_first, 0n, Cl.Msg{}, "<a> early")
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
    Unit <- E.must_eq("server-time PRIVMSG stores the combined stamp", last_ts(stamped), "2026-10-19 (Monday)|00:01:00")
    Unit <- E.must_eq("reconnect HMS does not reprint the same day bar", bars_buf(after_recon), "BAR @2026-10-19 (Monday)|")
    Unit <- E.must_eq("hidden first-of-day still paints the next visible day bar", bars_hide_joins(after_hidden_day),
      "BAR @2026-10-19 (Monday)|BAR @2026-10-20 (Tuesday)|")
    Unit <- E.must_eq("scrolled hide-joins keeps the same day bars", bars_hide_joins_scrolled(after_hidden_day),
      "BAR @2026-10-19 (Monday)|BAR @2026-10-20 (Tuesday)|")
    Unit <- E.must("live paint seeds day bars past a deep older spine",
      String.contains(deep_live_bars(), "BAR @2026-10-20 (Tuesday)"))
    Unit <- E.must_eq("day bar ScrollAt.tail stays above the live-bottom zero sentinel", day_anchor_tails(tuesday), "9|10|")
    Unit <- E.must("reconnect bar stays a reconnect bar", String.contains(V.recon_divider("", 40), "Reconnected"))
    Unit <- E.must("day bar names the local date", String.contains(V.recon_divider("@2026-10-19 (Monday)", 40), "2026-10-19 (Monday)"))
    Unit <- E.must("day bar is not a reconnect label", Bool.not(String.contains(V.recon_divider("@2026-10-19 (Monday)", 40), "Reconnected")))
    IO.print("day_bar=ok")
