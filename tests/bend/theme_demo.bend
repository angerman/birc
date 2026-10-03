# SPDX-License-Identifier: Apache-2.0
# Theme palettes: default preserves historic colors, new themes are total.
import Base
import ./expect.bend as E
import ../../src/bend/theme.bend as Theme
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/view.bend as V

def parsed.show(got: Maybe<&2, Theme.Id>) -> String:
  match got:
    case Some{Theme.Dark{}}: "dark"
    case Some{Theme.Light{}}: "light"
    case Some{Theme.Mono{}}: "mono"
    case None{}: "none"

def parsed(+name: String) -> String:
  parsed.show(Theme.parse(name))

def nick_rows.go(+id: Theme.Id, left: Nat, +idx: U32) -> String:
  match left:
    case 0n: ""
    case 1n+p: U32.show(Theme.nick_row(id, idx)) ++ "," ++ nick_rows.go(id, p, U32.add(idx, 1))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("default is dark", Theme.show(Theme.default()), "dark")
    Unit <- E.must_eq("parse dark", parsed("dark"), "dark")
    Unit <- E.must_eq("parse light", parsed("light"), "light")
    Unit <- E.must_eq("parse mono", parsed("mono"), "mono")
    Unit <- E.must_eq("parse is case-insensitive", parsed("DARK"), "dark")
    Unit <- E.must_eq("parse rejects unknown", parsed("neon"), "none")
    Unit <- E.must_eq("parse rejects empty", parsed(""), "none")
    Unit <- E.must_eq("dark msg preserved", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.Msg{})), "13158600")
    Unit <- E.must_eq("dark self preserved", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.Self{})), "5893695")
    Unit <- E.must_eq("dark system preserved", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.System{})), "10526880")
    Unit <- E.must_eq("dark action preserved", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.Action{})), "13079274")
    Unit <- E.must_eq("dark notice preserved", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.Notice{})), "8563455")
    Unit <- E.must_eq("dark error preserved", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.Error{})), "16223340")
    Unit <- E.must_eq("dark highlight gold", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.Highlight{})), "16766720")
    Unit <- E.must_eq("dark reconnect preserved", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.Reconnect{})), "10526880")
    Unit <- E.must_eq("dark linkresult preserved", U32.show(Theme.kind_fg(Theme.Dark{}, Cl.LinkResult{})), "10526880")
    Unit <- E.must_eq("view default msg matches", U32.show(V.style_of_themed(Theme.default(), Cl.Msg{})), U32.show(V.style_of(Cl.Msg{})))
    Unit <- E.must_eq("view default highlight matches", U32.show(V.style_of_themed(Theme.default(), Cl.Highlight{})), U32.show(V.style_of(Cl.Highlight{})))
    Unit <- E.must_eq("light msg is dark-on-light", U32.show(Theme.kind_fg(Theme.Light{}, Cl.Msg{})), "3355443")
    Unit <- E.must_eq("light error is dark red", U32.show(Theme.kind_fg(Theme.Light{}, Cl.Error{})), "12988207")
    Unit <- E.must_eq("mono msg uniform", U32.show(Theme.kind_fg(Theme.Mono{}, Cl.Msg{})), "14211288")
    Unit <- E.must_eq("mono error uniform", U32.show(Theme.kind_fg(Theme.Mono{}, Cl.Error{})), "14211288")
    Unit <- E.must_eq("mono highlight uniform", U32.show(Theme.kind_fg(Theme.Mono{}, Cl.Highlight{})), "14211288")
    Unit <- E.must_eq("dark nick rows preserved",
      nick_rows.go(Theme.Dark{}, 17n, 0),
      "16738914,5635925,16766770,5547007,13079039,5635999,16747674,10485606,16753920,10079487,14467071,7526270,16763030,8576972,16744652,14540253,14540253,")
    Unit <- E.must_eq("view nick delegation preserved", U32.show(V.nick_color_idx(0)), "16738914")
    Unit <- E.must_eq("view nick default arm preserved", U32.show(V.nick_color_idx(99)), "14540253")
    Unit <- E.must_eq("view nick matches themed default",
      U32.show(V.nick_color("alice")), U32.show(V.nick_color_themed(Theme.default(), "alice")))
    Unit <- E.must_eq("light nick row 0", U32.show(Theme.nick_row(Theme.Light{}, 0)), "11749120")
    Unit <- E.must_eq("light nick row 15", U32.show(Theme.nick_row(Theme.Light{}, 15)), "3622735")
    Unit <- E.must_eq("light nick default arm", U32.show(Theme.nick_row(Theme.Light{}, 99)), "4871528")
    Unit <- E.must_eq("mono nick uniform", U32.show(Theme.nick_row(Theme.Mono{}, 7)), "14211288")
    Unit <- E.must_eq("dark status ok", U32.show(Theme.status_ok(Theme.Dark{})), "5635925")
    Unit <- E.must_eq("dark status err", U32.show(Theme.status_err(Theme.Dark{})), "16223340")
    Unit <- E.must_eq("dark status warn", U32.show(Theme.status_warn(Theme.Dark{})), "15720050")
    Unit <- E.must_eq("dark status dim", U32.show(Theme.status_dim(Theme.Dark{})), "10526880")
    Unit <- E.must_eq("light status ok", U32.show(Theme.status_ok(Theme.Light{})), "31293")
    Unit <- E.must_eq("light status err", U32.show(Theme.status_err(Theme.Light{})), "12988207")
    Unit <- E.must_eq("light status warn", U32.show(Theme.status_warn(Theme.Light{})), "10119680")
    Unit <- E.must_eq("light status dim", U32.show(Theme.status_dim(Theme.Light{})), "6710886")
    Unit <- E.must_eq("mono status uniform", U32.show(Theme.status_err(Theme.Mono{})), "14211288")
    Unit <- E.must_eq("view status online matches",
      U32.show(V.status_color_themed(Theme.default(), "online · 3ms")), U32.show(V.status_color("online · 3ms")))
    Unit <- E.must_eq("view status offline matches",
      U32.show(V.status_color_themed(Theme.default(), "offline")), U32.show(V.status_color("offline")))
    Unit <- E.must_eq("light status online", U32.show(V.status_color_themed(Theme.Light{}, "online")), "31293")
    Unit <- E.must_eq("mono status offline", U32.show(V.status_color_themed(Theme.Mono{}, "offline")), "14211288")
    IO.print("theme_demo=ok")
