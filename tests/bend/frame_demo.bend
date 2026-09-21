# M4.2 framer goldens. Live path uses octet Fr.push (Latin-1 bytes).
import Base
import ./expect.bend as E
import ../../src/bend/frame.bend as Fr
import ./frame_preds.bend as FP

def show_lines.go(fuel: Nat, +xs: List<&2, String>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_lines.go(p, t, acc ++ h ++ "|")

def show_lines(+xs: List<&2, String>) -> String:
  show_lines.go(Nat.add(1n, List.length(&2, String, xs)), xs, "")

def show_rem.go(fuel: Nat, +xs: List<&2, U32>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_rem.go(p, t, acc ++ U32.show(h) ++ ",")

def show_rem(+xs: List<&2, U32>) -> String:
  show_rem.go(Nat.add(1n, List.length(&2, U32, xs)), xs, "")

def report_pair(got: List<&2, String> & List<&2, U32>) -> String:
  match got:
    case (ls, rem):
      "lines=" ++ show_lines(ls) ++ " rem=" ++ show_rem(rem)

def chunk() -> List<&2, U32>:
  Fr.append_octets(Fr.crlf("PING :x"), Fr.string_to_octets("partial"))

def report_ex(got: List<&2, String> & List<&2, U32> & Bool) -> String:
  match got:
    case (ls, rem, drop):
      "lines=" ++ show_lines(ls) ++ " rem=" ++ show_rem(rem) ++ " drop=" ++ Bool.show(drop)

def drop_across_oct.p2go(+drop: Bool, +rem: List<&2, U32>) -> String:
  "d1=" ++ Bool.show(drop) ++ " " ++ report_ex(Fr.push_ex(drop, rem, Fr.string_to_octets("XYZ\r\nPING :x\r\n")))

def drop_across_oct.p2(st: List<&2, String> & List<&2, U32> & Bool) -> String:
  match st:
    case (_, rem, drop):
      drop_across_oct.p2go(drop, rem)

def drop_across_oct() -> String:
  drop_across_oct.p2(Fr.push_ex(False{}, Nil{}, Fr.repeat_octet.go(600n, 65, Nil{})))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq(
      "push",
      report_pair(Fr.push(Nil{}, chunk())),
      "lines=PING :x| rem=112,97,114,116,105,97,108,"
    )
    Unit <- E.must("rt", Fr.roundtrip_ok("a" <> "b" <> Nil{}, Fr.string_to_octets("tail")))
    Unit <- E.must("overlong_octets", Fr.overlong_drop_ok())
    Unit <- E.must("cr_flood_oct", Fr.cr_flood_oct_ok())
    Unit <- E.must("legal_max", Fr.legal_max_ok())
    Unit <- E.must("legal_509", Fr.legal_509_ok())
    Unit <- E.must("utf8_cafe", FP.utf8_cafe_ok())
    Unit <- E.must("utf8_han", FP.utf8_han_ok())
    Unit <- E.must("utf8_emoji", FP.utf8_emoji_ok())
    Unit <- E.must("latin1_e9", FP.latin1_e9_ok())
    Unit <- E.must("latin1_overlong", FP.latin1_overlong_ok())
    Unit <- E.must("latin1_naive", FP.latin1_naive_ok())
    Unit <- E.must("split_high", FP.split_high_ok())
    Unit <- E.must_eq(
      "drop_across_oct",
      drop_across_oct(),
      "d1=True lines=PING :x| rem= drop=False"
    )
    Unit <- E.must_eq(
      "c0_us",
      report_ex(Fr.push_ex(False{}, Nil{}, Fr.string_to_octets("ab" ++ SCon{Chr{31}, "cd\r\n"}))),
      "lines=abcd| rem= drop=False"
    )
    Unit <- E.must("overlong_octets_again", Fr.overlong_drop_ok())
    Unit <- E.must("legal_max_again", Fr.legal_max_ok())
    Unit <- E.must_eq(
      "fuel0_pdrop",
      report_ex(Fr.push.go(0n, Fr.PDrop{}, Fr.string_to_octets("A"), Nil{}, Nil{}, 0n, 0, False{}, False{}, False{})),
      "lines= rem= drop=True"
    )
    Unit <- E.must_eq(
      "pdrop_empty",
      report_ex(Fr.push.go(1n, Fr.PDrop{}, Nil{}, Nil{}, Nil{}, 0n, 0, False{}, False{}, False{})),
      "lines= rem= drop=True"
    )
    Unit <- E.must_eq(
      "fuel0_pread",
      report_ex(Fr.push.go(0n, Fr.PRead{}, Nil{}, Nil{}, Nil{}, 0n, 0, False{}, False{}, False{})),
      "lines= rem= drop=False"
    )
    Unit <- E.must_eq(
      "pread_empty",
      report_ex(Fr.push.go(1n, Fr.PRead{}, Nil{}, Nil{}, Nil{}, 0n, 0, False{}, False{}, False{})),
      "lines= rem= drop=False"
    )
    Unit <- E.must(
      "octets_eq_diff",
      Bool.not(Fr.octets_eq(1 <> Nil{}, 2 <> Nil{}))
    )
    Unit <- E.must(
      "strings_eq_diff",
      Bool.not(Fr.strings_eq("a" <> Nil{}, "b" <> Nil{}))
    )
    Unit <- E.must("str_eq_empty", Fr.str_eq("", ""))
    Unit <- E.must("str_eq_same", Fr.str_eq("a", "a"))
    Unit <- E.must("str_eq_diff", Bool.not(Fr.str_eq("a", "b")))
    IO.print("frame_demo=ok")
