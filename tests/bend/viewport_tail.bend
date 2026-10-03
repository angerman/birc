# SPDX-License-Identifier: Apache-2.0
# Complete-row reference guards for the live tail and paused viewports.
import Base
import ./expect.bend as E
import ./media_branches.bend as B
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V

# Keep this explicit legacy path independent of prospective tail selection.
# Read the actual buffer fields, including its synthetic topic and anchor.
def legacy(b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +media: M.State) -> List<&2, V.BodyRow>:
  match b:
    case Cl.Buffer{+name, _, +topic, +raw, _, scroll}:
      +lines = V.media_display_lines(name, topic, raw, media)
      V.visible_anchored(V.anchored_lines_media(lines, name, w, show_ts, mutes, "s", List.length(&2, Cl.Line, lines), media), height, scroll)

def check(+tag: String, +b: Cl.Buffer, +height: Nat, +w: U32, +show_ts: Bool, +mutes: List<&2, String>, +media: M.State) -> IO(Unit):
  E.must(tag ++ " width=" ++ U32.show(w) ++ " height=" ++ Nat.show(height),
    B.rows_eq(V.body_of.buf_media(b, height, w, show_ts, mutes, "s", media), legacy(b, height, w, show_ts, mutes, media)))

def widths(xs: List<&2, U32>, +tag: String, +b: Cl.Buffer, +height: Nat, +show_ts: Bool, +mutes: List<&2, String>, +media: M.State) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{w, tail}:
      do IO<Unit>:
        Unit <- check(tag, b, height, w, show_ts, mutes, media)
        widths(tail, tag, b, height, show_ts, mutes, media)

def heights(xs: List<&2, Nat>, +tag: String, +b: Cl.Buffer, +show_ts: Bool, +mutes: List<&2, String>, +media: M.State) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{+height, tail}:
      do IO<Unit>:
        Unit <- widths([0, 1, 180], tag, b, height, show_ts, mutes, media)
        heights(tail, tag, b, show_ts, mutes, media)

def geometry(+tag: String, +b: Cl.Buffer, +mutes: List<&2, String>, +media: M.State) -> IO(Unit):
  do IO<Unit>:
    Unit <- heights([0n, 1n, 45n], tag ++ " stamped", b, True{}, mutes, media)
    heights([0n, 1n, 45n], tag ++ " unstamped", b, False{}, mutes, media)

def group(+tag: String, +b: Cl.Buffer, +mutes: List<&2, String>, +media: M.State) -> IO(Unit):
  do IO<Unit>:
    Unit <- geometry(tag ++ " bottom", b, mutes, media)
    Unit <- geometry(tag ++ " paused", Cl.set_buf_anchor(b, Cl.ScrollAt{1n, 3n}), mutes, media)
    Unit <- check(tag ++ " within-line anchor", Cl.set_buf_anchor(b, Cl.ScrollAt{0n, 2n}), 1n, 1, False{}, mutes, media)
    check(tag ++ " clamped anchor", Cl.set_buf_anchor(b, Cl.ScrollAt{999n, 999n}), 45n, 180, True{}, mutes, media)

def buffer(name: String, lines: List<&2, Cl.Line>) -> Cl.Buffer:
  Cl.Buffer{name, True{}, "", lines, ["alice", "bob"], Cl.ScrollAt{0n, 0n}}

def mixed() -> List<&2, Cl.Line>:
  [Cl.Line{Cl.Msg{}, "12:34:56", "<alice> **bold** :eyes: 漢👩‍💻 é " ++ B.image_url(), "alice", 1n},
   Cl.Line{Cl.Highlight{}, "01:02:03", "<bob> alice: visible _italic_", "bob", 2n},
   Cl.Line{Cl.Action{}, "02:03:04", "* alice :rocket: action", "ALICE", 3n},
   Cl.Line{Cl.Reconnect{}, "03:04:05", "IRC connection established", "alice", 4n},
   Cl.Line{Cl.System{}, "04:05:06", "control notice from alice", "alice", 5n},
   Cl.Line{Cl.Error{}, "05:06:07", SCon{Chr{3}, "04red" ++ SCon{Chr{15}, " end"}}, "", 6n},
   Cl.Line{Cl.Msg{}, "06:07:08", "", "bob", 17n}]

def long_lines(n: Nat, +id: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p:
      Cl.Line{Cl.Msg{}, "12:34:56", "<alice> row" ++ Nat.show(id) ++ " abcdefghijkl", "alice", id}
        <> long_lines(p, 1n+id)

def inline_pending() -> M.State:
  M.State{True{}, 1n, 3n, Some{M.Request{M.Inline{1n}, B.image_url(), 1n, 1n}},
    [M.Request{M.Inline{17n}, B.image_url(), 1n, 2n}], Nil{}, M.Supported{}}

def inline_ready() -> M.State:
  M.State{True{}, 1n, 3n, None{}, Nil{},
    [M.Ready{M.Inline{1n}, B.image_url(), 7}, M.Ready{M.Inline{17n}, B.image_url(), 9}], M.Supported{}}

def manual_pending() -> M.State:
  M.State{False{}, 1n, 2n, Some{M.Request{M.Manual{}, B.image_url(), 1n, 1n}}, Nil{}, Nil{}, M.Supported{}}

def manual_ready() -> M.State:
  M.State{False{}, 1n, 2n, None{}, Nil{}, [M.Ready{M.Manual{}, B.image_url(), 9}], M.Supported{}}

def manual_diagnostics() -> List<&2, Cl.Line>:
  [Cl.Line{Cl.Error{}, "12:34:56", "image preview unavailable", "", 18n},
   Cl.Line{Cl.System{}, "12:34:57", "retrying image preview", "", 19n}]

def manual() -> Cl.Buffer:
  Cl.Buffer{"*preview*", False{}, B.image_url(), manual_diagnostics(), Nil{}, Cl.ScrollAt{0n, 0n}}

def empty_known() -> Cl.Line:
  Cl.Line{Cl.Msg{}, "12:34:56", "", "alice", 17n}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- group("empty buffer", buffer("#t", Nil{}), Nil{}, M.empty())
    Unit <- group("short Unicode/style/reconnect", buffer("#t", mixed()), Nil{}, M.empty())
    Unit <- group("long buffer", buffer("#t", long_lines(64n, 1n)), Nil{}, M.empty())
    Unit <- group("matching scoped mute", buffer("#t", mixed()), ["alice#t@s"], M.empty())
    Unit <- group("nonmatching mute scope", buffer("#t", mixed()), ["alice#other@s"], M.empty())
    Unit <- group("all logical lines muted", buffer("#t", long_lines(8n, 1n)), ["alice#t@s"], M.empty())
    Unit <- group("muted tail preserves older visible row", buffer("#t", [Cl.Line{Cl.Msg{}, "01:02:03", "older visible text", "bob", 1n}, Cl.Line{Cl.Msg{}, "02:03:04", "newer muted text", "alice", 2n}]), ["alice#t@s"], M.empty())
    Unit <- group("unwrapped settings", buffer("*settings*", mixed()), Nil{}, inline_ready())
    Unit <- group("inline pending", buffer("#t", mixed()), Nil{}, inline_pending())
    Unit <- group("inline ready", buffer("#t", mixed()), Nil{}, inline_ready())
    Unit <- group("known empty line only", buffer("#t", [empty_known()]), Nil{}, inline_ready())
    Unit <- group("known zero-row tail after older text", buffer("#t", [Cl.Line{Cl.Msg{}, "01:02:03", "older visible text", "bob", 16n}, empty_known()]), Nil{}, inline_ready())
    Unit <- E.must("known empty source truly yields zero rows", B.rows_eq(V.body_rows_media([empty_known()], "#t", 180, True{}, inline_ready()), Nil{}))
    Unit <- group("manual pending plus diagnostics", manual(), Nil{}, manual_pending())
    Unit <- group("manual ready plus diagnostics", manual(), Nil{}, manual_ready())
    Unit <- group("manual absent plus diagnostics", manual(), Nil{}, M.empty())
    Unit <- check("manual live-bottom cropped image", manual(), 3n, 180, False{}, Nil{}, manual_ready())
    Unit <- E.must("manual live-bottom image and diagnostic rows", B.rows_eq(V.body_of.buf_media(manual(), 3n, 180, False{}, Nil{}, "s", manual_ready()), V.BodyMedia{9, 40, 6, 5} <> V.body_rows(manual_diagnostics(), "*preview*", 180, False{})))
    Unit <- check("manual image internal anchor", Cl.set_buf_anchor(manual(), Cl.ScrollAt{2n, 2n}), 1n, 180, False{}, Nil{}, manual_ready())
    Unit <- E.must("manual partial row metadata", B.rows_eq(V.body_of.buf_media(Cl.set_buf_anchor(manual(), Cl.ScrollAt{2n, 2n}), 1n, 180, False{}, Nil{}, "s", manual_ready()), [V.BodyMedia{9, 40, 6, 3}]))
    IO.print("viewport_tail=ok")
