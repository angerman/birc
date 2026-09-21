# Uncited UTF-8 / Latin-1 / split-high samples. Framer laws stay in src.
import Base
import ../../src/bend/frame.bend as Fr

def cafe_oct() -> List<&2, U32>:
  99 <> 97 <> 102 <> 195 <> 169 <> Nil{}

def cafe_str() -> String:
  "caf" ++ SCon{Chr{233}, SNil{}}

def utf8_cafe_ok() -> Bool:
  String.eq(Fr.line_from_octets(cafe_oct()), cafe_str())

def utf8_han_ok() -> Bool:
  String.eq(Fr.line_from_octets(230 <> 188 <> 162 <> Nil{}), SCon{Chr{28450}, SNil{}})

def utf8_emoji_ok() -> Bool:
  String.eq(Fr.line_from_octets(240 <> 159 <> 152 <> 128 <> Nil{}), SCon{Chr{128512}, SNil{}})

def latin1_e9_ok() -> Bool:
  String.eq(Fr.line_from_octets(233 <> Nil{}), SCon{Chr{233}, SNil{}})

def latin1_overlong_ok() -> Bool:
  String.eq(Fr.line_from_octets(192 <> 128 <> Nil{}), SCon{Chr{192}, SCon{Chr{128}, SNil{}}})

def naive_priv_oct() -> List<&2, U32>:
  List.append(
    &2,
    U32,
    Fr.string_to_octets(":a!a@h PRIVMSG #t :na"),
    239 <> Fr.string_to_octets("ve latin1")
  )

def naive_priv_str() -> String:
  ":a!a@h PRIVMSG #t :na" ++ SCon{Chr{239}, "ve latin1"}

def latin1_naive_ok() -> Bool:
  String.eq(Fr.line_from_octets(naive_priv_oct()), naive_priv_str())

# First chunk ends 0xC3, second starts 0xA9 → one UTF-8 line "café".
def split_high_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (ls, rem):
      match ls:
        case Con{+h, Nil{}}:
          match rem:
            case Nil{}:
              String.eq(h, cafe_str())
            case Con{_, _}:
              False{}
        case _:
          False{}

def split_high_ok.go(st: List<&2, String> & List<&2, U32>) -> Bool:
  match st:
    case (_, rem):
      split_high_ok.fin(Fr.push(rem, 169 <> Fr.CR() <> Fr.LF() <> Nil{}))

def split_high_ok() -> Bool:
  split_high_ok.go(Fr.push(Nil{}, 99 <> 97 <> 102 <> 195 <> Nil{}))
