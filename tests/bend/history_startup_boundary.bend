# SPDX-License-Identifier: Apache-2.0
# Full archive snapshots must not spend their row budget on a temporary marker.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/history_startup.bend as H
import ../../src/bend/history_startup_io.bend as F
import ../../src/bend/history.bend as Hist

def lines(cl: Cl.Client) -> List<&2, Cl.Line>:
  match cl:
    case Cl.Client{_, _, Con{_, Con{Cl.Buffer{_, _, _, rows, _, _, _, _}, _}}, _, _, _, _, _}: rows
    case _: Nil{}

def first(rows: List<&2, Cl.Line>) -> String:
  match rows:
    case Con{Cl.Line{_, _, text, _, _}, _}: text
    case _: ""

def last(rows: List<&2, Cl.Line>) -> String:
  match rows:
    case Con{Cl.Line{_, _, text, _, _}, Nil{}}: text
    case Con{_, rest}: last(rest)
    case _: ""

def report(+cl: Cl.Client, +cap: U32, +expected_first: String) -> IO(Unit):
  +rows = lines(cl)
  do IO<Unit>:
    Unit <- IO.print("cap=" ++ U32.show(cap) ++ " rows=" ++ Nat.show(List.length(&2, Cl.Line, rows)) ++ " first=" ++ first(rows) ++ " last=" ++ last(rows))
    Unit <- E.must("snapshot retains every allowed archived row", Nat.is_eq(List.length(&2, Cl.Line, rows), U32.to_nat(cap)))
    Unit <- E.must_eq("snapshot begins at expected recent record", first(rows), expected_first)
    E.must_eq("snapshot retains latest record", last(rows), "row1023")

def control_rows(cl: Cl.Client) -> List<&2, Cl.Line>:
  match cl:
    case Cl.Client{_, _, Con{Cl.Buffer{_, _, _, rows, _, _, _, _}, _}, _, _, _, _, _}: rows
    case _: Nil{}

def failed_read(path: String, snapshot: Cl.Client) -> IO(Cl.Client):
  do IO<Cl.Client>:
    f : File <- IO.try(File, File.open(path, "r"))
    Hist.read_loop.got.mode((f, Fail{(5, "synthetic read failure")}), True{}, Hist.ReadState{snapshot, Nil{}, 0n, False{}},
      "irc.example:6667", 1024, "12:00:00", 1n,
      f2 => state => rest => do IO<Cl.Client>:
        Unit <- File.close(f2)
        IO.die(Cl.Client, 1, "failed read called continuation"))

def run(+path: String) -> IO(Unit):
  do IO<Unit>:
    below : Cl.Client <- F.load(path, "irc.example:6667", 1023, "archive", "irc.example", "12:00:00")
    Unit <- report(H.install(Cl.init_with_cap("me", "irc.example", 1023), below), 1023, "row1")
    +full : Cl.Client <- F.load(path, "irc.example:6667", 1024, "archive", "irc.example", "12:00:00")
    Unit <- report(H.install(Cl.init_with_cap("me", "irc.example", 1024), full), 1024, "row0")
    +failed : Cl.Client <- failed_read(path, full)
    Unit <- E.must("snapshot failure is log-only and cannot trim completed archive rows",
      Nat.is_eq(List.length(&2, String, H.diagnostics(failed)), 1n) && List.is_empty(&2, Cl.Line, control_rows(failed)))
    Unit <- report(H.install(Cl.init_with_cap("me", "irc.example", 1024), failed), 1024, "row0")
    +legacy : Cl.Client <- Hist.history_init_client(path, "irc.example:6667", 1023, "archive", "irc.example", "12:00:00")
    Unit <- E.must("ordinary reader retains its legacy divider behavior", Nat.is_eq(List.length(&2, Cl.Line, lines(legacy)), 1024n)
      && String.eq(first(lines(legacy)), "row1") && String.eq(last(lines(legacy)), "12:00:00"))
    IO.print("history_startup_boundary=ok")

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Nil{}}}: run(path)
    case _: IO.die(Unit, 1, "expected synthetic history path")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
