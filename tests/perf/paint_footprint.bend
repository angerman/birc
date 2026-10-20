# SPDX-License-Identifier: Apache-2.0
# Physical-footprint reproducer for one capped rich buffer.
# Fills the server buffer to SCROLL_CAP with synthetic color, markdown,
# a URL, and emoji shortcodes, then repaints the production view.
# Usage: paint_footprint [PASSES]   (default 32, at most 64)
# Runtime flag --gpu off is consumed before these arguments.
# Each line is a sample point for an outer footprint driver:
#   filled LINES
#   paint INDEX CHECKSUM
#   done PASSES
# A climbing footprint across paint lines is retention in this view path.
# A plateau after filled means the capped client is not what grows.
import Base
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/media.bend as M
import ../../src/bend/split.bend as Sp
import ../../src/bend/theme.bend as Theme
import ../../src/bend/view.bend as V

def sample_line(n: Nat) -> String:
  "*bold* _italic_ `code` :smile: :rocket: https://example.test/p/"
    ++ Nat.show(n) ++ " "
    ++ SCon{Chr{2}, SCon{Chr{3}, "04paint "}}
    ++ String.repeat("word ", 8n)

def fill(+n: Nat, +cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p: fill(p, Cl.client_log(cl, 0n, Cl.Msg{}, sample_line(n)))

def span_len(sp: V.SpanOp) -> Nat:
  match sp:
    case V.Spn{_, text}: String.length(text)
    case V.Lnk{url, text}: Nat.add(String.length(url), String.length(text))
    case V.Col{_, _, text}: String.length(text)

def spans_len(xs: List<&2, V.SpanOp>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{sp, t}: Nat.add(span_len(sp), spans_len(t))

def names_len(xs: List<&2, String>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{s, t}: Nat.add(String.length(s), names_len(t))

def op_len(op: V.DrawOp) -> Nat:
  match op:
    case V.OpBox{_, _, _, _, _}: 0n
    case V.OpSplit{_, _, _, _, _, _}: 0n
    case V.OpText{_, _, _, _, _, text}: String.length(text)
    case V.OpTabs{_, _, _, _, names, _, _, _}: names_len(names)
    case V.OpLine{_, _, _, _, spans}: spans_len(spans)
    case V.OpImage{_, _, _, _, path}: String.length(path)
    case V.OpMedia{_, _, _, _, _, _, _}: 1n
    case V.OpGhost{_, _, _, _, text}: String.length(text)

def ops_len(xs: List<&2, V.DrawOp>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{op, t}: Nat.add(op_len(op), ops_len(t))

def vm_len(vm: V.ViewModel) -> Nat:
  match vm:
    case V.ViewModel{ops, input}: Nat.add(ops_len(ops), String.length(input))

def paint_vm(+cl: Cl.Client) -> V.ViewModel:
  # Empty pends: the probe paints the capped buffer, not optimistic-send rows.
  V.view_draft.state_typing_media_cards_cm_themed("", cl, U32.from_nat(45n), U32.from_nat(100n), "", "offline", Nil{}, Sp.state0(), M.empty(), Nil{}, Theme.Dark{}, Nil{})

def report(left: Nat, +seen: Nat, +cl: Cl.Client) -> IO(Unit):
  match left:
    case 0n:
      do IO<Unit>:
        Unit <- IO.print("done " ++ Nat.show(seen) ++ "\n")
        IO.sleep(300)
    case 1n+rest:
      do IO<Unit>:
        Unit <- IO.print("paint " ++ Nat.show(seen) ++ " " ++ Nat.show(vm_len(paint_vm(cl))) ++ "\n")
        Unit <- IO.sleep(300)
        report(rest, 1n+seen, cl)

def run(passes: Nat) -> IO(Unit):
  +cl = fill(Cl.SCROLL_CAP(), Cl.init("painter", "example.test"))
  do IO<Unit>:
    Unit <- IO.print("filled " ++ Nat.show(Cl.SCROLL_CAP()) ++ "\n")
    Unit <- IO.sleep(300)
    report(passes, 0n, cl)

def read_passes(n: Maybe<&2, Nat>) -> Nat:
  match n:
    case None{}: 0n
    case Some{k}: k

def passes_of(args: List<&1, String>) -> Nat:
  match args:
    case Con{_, Nil{}}: 32n
    case Con{_, Con{raw, Nil{}}}: read_passes(Nat.read(raw))
    case _: 0n

def go(ok: Bool, +passes: Nat) -> IO(Unit):
  match ok:
    case False{}: IO.die(Unit, 1, "usage: paint_footprint [PASSES]")
    case True{}: run(passes)

def dispatch(args: List<&1, String>) -> IO(Unit):
  +passes = passes_of(args)
  go(Nat.is_gt(passes, 0n) && Nat.is_le(passes, 64n), passes)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1, String> <- IO.args()
    dispatch(args)
