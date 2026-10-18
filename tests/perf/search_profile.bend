# Search benchmark at the production maximum: 16 buffers x 1024 lines.
# Default prints only the match count. BIRC_SEARCH_PROFILE=parallel or
# BIRC_SEARCH_PROFILE=serial also prints tree-build and scan times in ms.
import Base
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed

def bench_lines(+n: Nat, +i: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Cl.Line{Cl.Msg{}, "", "needle line " ++ Nat.show(i), "", 0n}
        <> bench_lines(p, Nat.add(i, 1n))

def bench_bufs(+n: Nat, +i: Nat) -> List<&2, Cl.Buffer>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Cl.buf_indexed("#bench" ++ Nat.show(i), True{}, "", bench_lines(Cl.SCROLL_CAP(), 0n), Nil{}, 0n) <> bench_bufs(p, Nat.add(i, 1n))

def bench_tree() -> Feed.SearchTree:
  Feed.bufs_to_tree(bench_bufs(Cl.MAX_BUFFERS(), 0n))

def serial_search(t: Feed.SearchTree, +q: String) -> List<&2, Cl.Line>:
  match t:
    case Feed.STLeaf{}:
      Nil{}
    case Feed.STOne{+name, +line}:
      Feed.search_match_line(name, line, q)
    case Feed.STNode{left, right}:
      List.append(&2, Cl.Line, serial_search(left, q), serial_search(right, q))

def run_search(serial: Bool, tree: Feed.SearchTree) -> List<&2, Cl.Line>:
  match serial:
    case True{}:
      serial_search(tree, "needle")
    case False{}:
      Feed.search_tree(tree, "needle")

def result_line(serial: Bool, n: Nat) -> String:
  match serial:
    case True{}:
      "mode=serial matches=" ++ Nat.show(n)
    case False{}:
      "mode=parallel matches=" ++ Nat.show(n)

def plain() -> IO(Unit):
  IO.print(Nat.show(List.length(&2, Cl.Line, Feed.search_tree(bench_tree(), "needle"))))

def phase_show(+t0: Nat, +t1: Nat, serial: Bool, matches: List<&2, Cl.Line>) -> IO(Unit):
  do IO<Unit>:
    t2 : Nat <- IO.now()
    IO.print("phase build_ms=" ++ Nat.show(Nat.sub(t1, t0)))
    IO.print("phase scan_ms=" ++ Nat.show(Nat.sub(t2, t1)))
    IO.print(result_line(serial, List.length(&2, Cl.Line, matches)))

def phase_mid(+t0: Nat, +serial: Bool, tree: Feed.SearchTree) -> IO(Unit):
  do IO<Unit>:
    t1 : Nat <- IO.now()
    phase_show(t0, t1, serial, run_search(serial, tree))

def phase_go(serial: Bool) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    phase_mid(t0, serial, bench_tree())

def phase_mode(+mode: String) -> IO(Unit):
  phase_go(String.eq(mode, "serial"))

def after_env(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Fail{_}:
      plain()
    case Done{mode}:
      phase_mode(mode)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_SEARCH_PROFILE")
    after_env(r)
