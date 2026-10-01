# An absolute DNS name has exactly one optional terminal root dot.
import Base
import ./expect.bend as E
import ../../src/bend/dns_wire.bend as Wire

def show_octets(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, t}: U32.show(h) ++ "," ++ show_octets(t)

def encoded(r: Result<&1, &1, U32 & String, List<&2, U32>>) -> String:
  match r:
    case Done{xs}: show_octets(xs)
    case Fail{(_, +msg)}: "fail:" ++ msg

def parsed(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+ip}: "ok:" ++ ip
    case Fail{(_, +msg)}: "fail:" ++ msg

def sample() -> List<&2, U32>:
  0 <> 1 <> 129 <> 128 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 0 <> 1 <> 97 <> 0 <> 0 <> 1 <> 0 <> 1 <> 192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("relative_question", parsed(Wire.parse_q(1, "a", sample())), "ok:1.2.3.4")
    Unit <- E.must_eq("absolute_wire", encoded(Wire.encode("a.example.")), encoded(Wire.encode("a.example")))
    Unit <- E.must_eq("absolute_edns_wire", encoded(Wire.encode_edns("a.example.")), encoded(Wire.encode_edns("a.example")))
    Unit <- E.must_eq("absolute_echoed_question", parsed(Wire.parse_q(1, "a.", sample())), "ok:1.2.3.4")
    Unit <- E.must_eq("absolute_casefolded_question", parsed(Wire.parse_q(1, "A.", sample())), "ok:1.2.3.4")
    Unit <- E.must_eq("interior_empty_label", encoded(Wire.encode("a..example")), "fail:bad name")
    Unit <- E.must_eq("double_root_dot", encoded(Wire.encode("a.example..")), "fail:bad name")
    Unit <- E.must_eq("triple_root_dot", encoded(Wire.encode_edns("a.example...")), "fail:bad name")
    Unit <- E.must_eq("empty_hostname", encoded(Wire.encode("")), "fail:bad name")
    Unit <- E.must_eq("root_is_not_hostname", encoded(Wire.encode(".")), "fail:bad name")
    IO.print("runtime_dns=ok")
