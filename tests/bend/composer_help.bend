# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/composer_ui.bend as Cu
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/view_laws.bend as VL
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed

def demo() -> Sess.Session:
  Sess.session_demo(Cl.init("me", "s"), "#a")

def online() -> Sess.Session:
  +cl = Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #a")
  Sess.session_online(Sess.session_with_client(Cl.set_active(cl, 1n), "#a"))

def st_of(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match trip:
    case (st, _, _): st

def cmd_of(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.NetCmd:
  match trip:
    case (_, cmd, _): cmd

def wire(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (_, Sess.Cont{outs}, _): String.join(outs, "|")
    case _: "other"

def wires(cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Cont{xs}:
      match xs:
        case Nil{}: ""
        case _: "wires"
    case _: "other"

def comp_show(comp: Sess.Comp) -> String:
  match comp:
    case Sess.CompNone{}: "N"
    case Sess.CompHelp{+topic}: "H:" ++ topic
    case Sess.CompHidden{}: "D"
    case Sess.CompPick{idx}: "P:" ++ Nat.show(idx)
    case Sess.CompActive{_, _, _}: "A"
    case Sess.CompUpload{_, _, _}: "U"

def keys_code(+typed: String, +code: U32) -> Sess.Keys:
  Sess.Keys{typed, False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, code, 0}

def opened_show(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (+st, cmd, _):
      Sess.session_draft(st) ++ ";" ++ comp_show(Sess.session_comp(st)) ++ ";" ++ wires(cmd) ++ ";" ++ U32.show(Sess.session_seed(st)) ++ ";" ++ comp_show(Sess.session_comp(st_of(Sess.step_keys(st, keys_code("x", 0)))))

def ghosted_ok(trip: Sess.Session & Sess.NetCmd & Bool) -> Bool:
  match trip:
    case (+st, _, _):
      String.eq(Sess.session_draft(st), "/join") && String.eq(U32.show(Sess.session_seed(st)), "1")

def keys_down(+typed: String) -> Sess.Keys:
  Sess.Keys{typed, False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistNext{}, 0, 0}

def keys_up(+typed: String) -> Sess.Keys:
  Sess.Keys{typed, False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistPrev{}, 0, 0}

def draft_of(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  Sess.session_draft(st_of(trip))

def picked(trip: Sess.Session & Sess.NetCmd & Bool, +want: String) -> Bool:
  match trip:
    case (+st, _, _):
      String.eq(comp_show(Sess.session_comp(st)), want) && String.eq(Sess.session_draft(st), "/")

def arrow_at(+n: Nat, xs: List<&2, String>) -> Bool:
  match n:
    case 0n:
      match xs:
        case Nil{}: False{}
        case Con{+h, _}: String.starts_with(h, "→")
    case 1n+p:
      match xs:
        case Nil{}: False{}
        case Con{_, t}: arrow_at(p, t)

def hid_ok(trip: Sess.Session & Sess.NetCmd & Bool) -> Bool:
  match trip:
    case (st, _, _):
      String.eq(comp_show(Sess.session_comp(st)), "D")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("layout", VL.body_ys_ok())
    Unit <- E.must("page", Sp.page_height_ok())
    Unit <- E.must("body", Sess.body_h_ok())
    Unit <- E.must("pol", Sess.key_pol_ok())
    Unit <- E.must("ghost", Cu.ghost_ok())
    Unit <- E.must("menu", Cu.menu_ok())
    Unit <- E.must_eq("rofl", Cu.emoji_commit(":rofl:"), "🤣")
    Unit <- E.must_eq("rolling", Cu.emoji_commit(":rolling-on-the-floor-laughing:"), "🤣")
    Unit <- E.must_eq("joy sentence", Cu.emoji_commit("hi :joy:"), "hi 🤣")
    Unit <- E.must_eq("open rof", Cu.emoji_commit(":rof"), ":rof")
    Unit <- E.must_eq("url", Cu.emoji_commit("http://x"), "http://x")
    Unit <- E.must_eq("ghost rof", Cu.ghost_at(":rof", 0n), "l:")
    Unit <- E.must_eq("accept rof", Cu.compose_accept(":rof", 0n), "🤣")
    Unit <- E.must_eq("accept fire", Cu.compose_accept(":fire", 0n), "🔥")
    Unit <- E.must_eq("rof row", Cu.emoji_line0(Cu.emoji_lines(":rof", 0n)), "→ 🤣  :rofl:")
    Unit <- E.must_eq("s row", Cu.emoji_line1(Cu.emoji_lines(":s", 1n)), "→ ⭐  :star:")
    Unit <- E.must("emoji menu", Cu.emoji_ok())
    Unit <- E.must("help lines", Cu.help_ok())
    Unit <- E.must_eq("F8 key", U32.show(Sess.KEY_F8()), "22")
    Unit <- E.must_eq("help opens locally", opened_show(Sess.step_enter(demo(), "/help join")), ";H:join;;1;N")
    Unit <- E.must("right accepts ghost", ghosted_ok(Sess.step_keys(demo(), keys_code("/j", 2))))
    Unit <- E.must("tab accepts ghost", ghosted_ok(Sess.step_keys(demo(), keys_code("/j", 1))))
    Unit <- E.must("esc hides menu", hid_ok(Sess.step_keys(Sess.session_set_draft(demo(), "/"), keys_code("/", 3))))
    Unit <- E.must("down selects next", picked(Sess.step_keys(Sess.session_set_draft(demo(), "/"), keys_down("/")), "P:1"))
    Unit <- E.must("down highlights join", arrow_at(1n, Sess.panel_lines(Sess.session_comp(st_of(Sess.step_keys(Sess.session_set_draft(demo(), "/"), keys_down("/")))), "/", "", Nil{})))
    Unit <- E.must("up stays on first", picked(Sess.step_keys(Sess.session_set_draft(demo(), "/"), keys_up("/")), "P:0"))
    Unit <- E.must("tab accepts selected slash", String.eq(draft_of(Sess.step_keys(st_of(Sess.step_keys(Sess.session_set_draft(demo(), "/"), keys_down("/"))), keys_code("/", 1))), "/join "))
    # − typed frames keep raw shortcodes (no auto emoji_commit on HistStay)
    Unit <- E.must_eq("typed keeps joy shortcode", draft_of(Sess.step_keys(demo(), keys_code(":joy:", 0))), ":joy:")
    Unit <- E.must_eq("typed keeps fire shortcode", draft_of(Sess.step_keys(demo(), keys_code("hi :fire:", 0))), "hi :fire:")
    Unit <- E.must_eq("enter keeps fire shortcode", wire(Sess.step_enter(online(), "hi :fire:")), "PRIVMSG #a :hi :fire:")
    # + explicit Tab/Right accept still inserts the glyph
    Unit <- E.must("right inserts rofl", String.eq(Sess.session_draft(st_of(Sess.step_keys(Sess.session_set_draft(demo(), ":rof"), keys_code(":rof", 2)))), "🤣"))
    Unit <- E.must("tab inserts rofl", String.eq(Sess.session_draft(st_of(Sess.step_keys(Sess.session_set_draft(demo(), ":rof"), keys_code(":rof", 1)))), "🤣"))
    Unit <- E.must("down moves emoji", String.eq(comp_show(Sess.session_comp(st_of(Sess.step_keys(Sess.session_set_draft(demo(), ":s"), keys_down(":s"))))), "P:1"))
    Unit <- E.must("tab inserts selected emoji", String.eq(draft_of(Sess.step_keys(st_of(Sess.step_keys(Sess.session_set_draft(demo(), ":s"), keys_down(":s"))), keys_code(":s", 1))), "⭐"))
    Unit <- E.must("esc does not quit", Sess.pol_eq(Sess.key_pol_for(Sess.session_set_draft(demo(), "/"), Sess.KEY_ESCAPE(), 0, 0, 0, 24), 0, 0, 0, 0, 0, 3, 0))
    Unit <- E.must("esc on help draft", Sess.pol_eq(Sess.key_pol_for(Sess.session_set_draft(demo(), "/help"), Sess.KEY_ESCAPE(), 0, 0, 0, 24), 0, 0, 0, 0, 0, 3, 0))
    Unit <- E.must("help draft shows catalog", Bool.not(List.is_empty(&2, String, Sess.panel_lines(Sess.comp0(), "/help", "", Nil{}))))
    Unit <- E.must("esc hides help draft", List.is_empty(&2, String, Sess.panel_lines(Sess.CompHidden{}, "/help", "", Nil{})))
    Unit <- E.must("shift right keeps tabs", Sess.pol_eq(Sess.key_pol_for(demo(), Sess.KEY_RIGHT(), Sess.MOD_SHIFT(), 0, 0, 24), 1, 0, 0, 0, 0, 0, 0))
    IO.print("composer_help=ok\n")
