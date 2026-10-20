# SPDX-License-Identifier: Apache-2.0
# Named color themes for chat chrome. Dark is the established palette and
# must stay byte-identical to the historic values; Light suits bright
# terminals; Mono uses one foreground for every kind. RGB U32, 0xRRGGBB.
import Base
import ./buffer.bend as Cl
import ./irc.bend as Irc

type Id is Data:
  Dark{}
  Light{}
  Mono{}

def default() -> Id:
  Dark{}

def show(+id: Id) -> String:
  match id:
    case Dark{}: "dark"
    case Light{}: "light"
    case Mono{}: "mono"

def parse.go(+dark: Bool, +light: Bool, +mono: Bool) -> Maybe<&2, Id>:
  match dark:
    case True{}: Some{Dark{}}
    case False{}:
      match light:
        case True{}: Some{Light{}}
        case False{}:
          match mono:
            case True{}: Some{Mono{}}
            case False{}: None{}

def parse(+name: String) -> Maybe<&2, Id>:
  parse.go(Irc.ieq(name, "dark"), Irc.ieq(name, "light"), Irc.ieq(name, "mono"))

# Halve each 0xRRGGBB channel (mask 0x7F7F7F keeps channels separate).
def dim_fg(+c: U32) -> U32:
  U32.and(U32.shrn(c, 1n), 8355711)

# Historic dark values, one per LineKind, shared by the fixed View adapter.
# Pending renders its inner kind dimmed; Mono dims at kind_fg below.
def kind_dark(k: Cl.LineKind) -> U32:
  match k:
    case Cl.Msg{}: 13158600
    case Cl.Self{}: 5893695
    case Cl.System{}: 10526880
    case Cl.Action{}: 13079274
    case Cl.Notice{}: 8563455
    case Cl.Error{}: 16223340
    case Cl.Highlight{}: 16766720
    case Cl.Reconnect{}: 10526880
    case Cl.LinkResult{}: 10526880
    case Cl.Presence{}: 10526880
    case Cl.Nick{}: 10526880
    case Cl.Day{}: 10526880
    case Cl.Pending{+inner}: dim_fg(kind_dark(inner))

# Dark-on-light variants: readable on a white background.
def kind_light(k: Cl.LineKind) -> U32:
  match k:
    case Cl.Msg{}: 3355443
    case Cl.Self{}: 31293
    case Cl.System{}: 6710886
    case Cl.Action{}: 8072383
    case Cl.Notice{}: 745471
    case Cl.Error{}: 12988207
    case Cl.Highlight{}: 9071872
    case Cl.Reconnect{}: 6710886
    case Cl.LinkResult{}: 6710886
    case Cl.Presence{}: 6710886
    case Cl.Nick{}: 6710886
    case Cl.Day{}: 6710886
    case Cl.Pending{+inner}: dim_fg(kind_light(inner))

def MONO_FG() -> U32:
  14211288

def kind_fg.dim(+fg: U32, pending: Bool) -> U32:
  match pending:
    case True{}: dim_fg(fg)
    case False{}: fg

def kind_fg(+id: Id, +k: Cl.LineKind) -> U32:
  match id:
    case Dark{}: kind_dark(k)
    case Light{}: kind_light(k)
    case Mono{}: kind_fg.dim(MONO_FG(), Cl.kind_pending(k))

# Historic dark nick hash palette (16 slots plus the default arm).
def nick_dark(+idx: U32) -> U32:
  match idx:
    case 0: 16738914
    case 1: 5635925
    case 2: 16766770
    case 3: 5547007
    case 4: 13079039
    case 5: 5635999
    case 6: 16747674
    case 7: 10485606
    case 8: 16753920
    case 9: 10079487
    case 10: 14467071
    case 11: 7526270
    case 12: 16763030
    case 13: 8576972
    case 14: 16744652
    case _: 14540253

# Darker nick slots for bright terminals.
def nick_light(+idx: U32) -> U32:
  match idx:
    case 0: 11749120
    case 1: 31293
    case 2: 9071872
    case 3: 745471
    case 4: 8072383
    case 5: 26972
    case 6: 11352832
    case 7: 4871528
    case 8: 12988207
    case 9: 3108655
    case 10: 9726720
    case 11: 23705
    case 12: 10494048
    case 13: 4020990
    case 14: 7162945
    case 15: 3622735
    case _: 4871528

def nick_row(+id: Id, +idx: U32) -> U32:
  match id:
    case Dark{}: nick_dark(idx)
    case Light{}: nick_light(idx)
    case Mono{}: MONO_FG()

# Status slots: online ok, offline err, connecting warn, other dim.
def status_ok(+id: Id) -> U32:
  match id:
    case Dark{}: 5635925
    case Light{}: 31293
    case Mono{}: MONO_FG()

def status_err(+id: Id) -> U32:
  match id:
    case Dark{}: 16223340
    case Light{}: 12988207
    case Mono{}: MONO_FG()

def status_warn(+id: Id) -> U32:
  match id:
    case Dark{}: 15720050
    case Light{}: 10119680
    case Mono{}: MONO_FG()

def status_dim(+id: Id) -> U32:
  match id:
    case Dark{}: 10526880
    case Light{}: 6710886
    case Mono{}: MONO_FG()

# Canonical status selector for fixed and themed View adapters.
# Online accepts a lowercase prefix; offline and connecting match exactly.
def status_of.on(+ok: U32, +err: U32, +warn: U32, +dim: U32, +online: Bool, +offline: Bool, +conn: Bool) -> U32:
  match online:
    case True{}: ok
    case False{}:
      match offline:
        case True{}: err
        case False{}:
          match conn:
            case True{}: warn
            case False{}: dim

def status_of(+id: Id, +net: String) -> U32:
  status_of.on(status_ok(id), status_err(id), status_warn(id), status_dim(id),
    String.starts_with(net, "online"), String.eq(net, "offline"), String.eq(net, "connecting"))

# Mention/private tab chip. Dark is the historic C pair: background
# 0x1E1E2E (1973806) and foreground 0xFFD700 (16766720), same gold as
# kind_dark Highlight. Light uses that theme's highlight gold on a warm
# paper chip (0xFFF6D5). Mono keeps one foreground on the dark chip.
# Activity alerts are reverse video and have no colour here.
# C still paints the dark pair. OpTabs (view.bend) has no fields for these
# words, so the constructor change is outside this module.
def tab_mention_bg(+id: Id) -> U32:
  match id:
    case Dark{}: 1973806
    case Light{}: 16774869
    case Mono{}: 1973806

def tab_mention_fg(+id: Id) -> U32:
  match id:
    case Dark{}: 16766720
    case Light{}: 9071872
    case Mono{}: MONO_FG()
