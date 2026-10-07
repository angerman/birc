# SPDX-License-Identifier: Apache-2.0
# Fixed/default and themed View colors preserve exact status boundaries.
import Base
import ./expect.bend as E
import ../../src/bend/theme.bend as Theme
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/view.bend as V

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("fixed kind uses historic dark", U32.show(V.style_of(Cl.Msg{})), "13158600")
    Unit <- E.must_eq("light kind does not use fixed dark", U32.show(V.style_of_themed(Theme.Light{}, Cl.Msg{})), "3355443")
    Unit <- E.must_eq("mono kind remains uniform", U32.show(V.style_of_themed(Theme.Mono{}, Cl.Msg{})), "14211288")
    Unit <- E.must_eq("fixed online is prefix-based", U32.show(V.status_color("onlineish")), "5635925")
    Unit <- E.must_eq("fixed online is case-sensitive", U32.show(V.status_color("Online")), "10526880")
    Unit <- E.must_eq("fixed offline is not prefix-based", U32.show(V.status_color("offline · 3ms")), "10526880")
    Unit <- E.must_eq("fixed connecting is not prefix-based", U32.show(V.status_color("connecting · 3ms")), "10526880")
    Unit <- E.must_eq("fixed empty status is dim", U32.show(V.status_color("")), "10526880")
    Unit <- E.must_eq("light online is prefix-based", U32.show(V.status_color_themed(Theme.Light{}, "onlineish")), "31293")
    Unit <- E.must_eq("light online is case-sensitive", U32.show(V.status_color_themed(Theme.Light{}, "Online")), "6710886")
    Unit <- E.must_eq("light offline is not prefix-based", U32.show(V.status_color_themed(Theme.Light{}, "offline · 3ms")), "6710886")
    Unit <- E.must_eq("light connecting is not prefix-based", U32.show(V.status_color_themed(Theme.Light{}, "connecting · 3ms")), "6710886")
    Unit <- E.must_eq("light empty status is dim", U32.show(V.status_color_themed(Theme.Light{}, "")), "6710886")
    Unit <- E.must_eq("mono online stays uniform", U32.show(V.status_color_themed(Theme.Mono{}, "onlineish")), "14211288")
    Unit <- E.must_eq("mono fallback stays uniform", U32.show(V.status_color_themed(Theme.Mono{}, "offline · 3ms")), "14211288")
    IO.print("theme_selector_boundaries=ok")
