# Export the width of every Unicode scalar-range value for the parity test.
import Base
import ../../src/bend/columns.bend as Cols

def widths(fuel: Nat, +cp: U32, acc: String) -> String:
  match fuel:
    case 0n: String.reverse(acc)
    case 1n+p: widths(p, U32.add(cp, 1), SCon{Chr{U32.add(48, Cols.width(cp))}, acc})

def main() -> IO(Unit):
  IO.print(widths(U32.to_nat(1114112), 0, ""))
