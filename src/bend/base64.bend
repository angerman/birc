# Base64 encoding for SASL PLAIN (M14.10). Pure Bend 2.
import Base

def b64_char.upper(+idx: U32) -> Char:
  Chr{U32.add(65, idx)}

def b64_char.lower(+idx: U32) -> Char:
  Chr{U32.add(71, idx)}

def b64_char.digit(+idx: U32) -> Char:
  Chr{U32.sub(idx, 4)}

def b64_char.sym(+idx: U32, is_plus: Bool) -> Char:
  match is_plus:
    case True{}:
      Chr{43} # '+'
    case False{}:
      Chr{47} # '/'

def b64_char.on_digits(+idx: U32, lt62: Bool) -> Char:
  match lt62:
    case True{}:
      b64_char.digit(idx)
    case False{}:
      b64_char.sym(idx, U32.is_eq(idx, 62))

def b64_char.on_lower(+idx: U32, lt52: Bool) -> Char:
  match lt52:
    case True{}:
      b64_char.lower(idx)
    case False{}:
      b64_char.on_digits(idx, U32.is_lt(idx, 62))

def b64_char.on_upper(+idx: U32, lt26: Bool) -> Char:
  match lt26:
    case True{}:
      b64_char.upper(idx)
    case False{}:
      b64_char.on_lower(idx, U32.is_lt(idx, 52))

def b64_char(+idx: U32) -> Char:
  b64_char.on_upper(idx, U32.is_lt(idx, 26))

def encode_triplet(+b0: U32, +b1: U32, +b2: U32) -> String:
  +c0 = U32.shrn(b0, 2n)
  +c1 = U32.or(U32.shln(U32.and(b0, 3), 4n), U32.shrn(b1, 4n))
  +c2 = U32.or(U32.shln(U32.and(b1, 15), 2n), U32.shrn(b2, 6n))
  +c3 = U32.and(b2, 63)
  SCon{b64_char(c0), SCon{b64_char(c1), SCon{b64_char(c2), SCon{b64_char(c3), SNil{}}}}}

def encode_pair(+b0: U32, +b1: U32) -> String:
  +c0 = U32.shrn(b0, 2n)
  +c1 = U32.or(U32.shln(U32.and(b0, 3), 4n), U32.shrn(b1, 4n))
  +c2 = U32.shln(U32.and(b1, 15), 2n)
  SCon{b64_char(c0), SCon{b64_char(c1), SCon{b64_char(c2), SCon{Chr{61}, SNil{}}}}}

def encode_single(+b0: U32) -> String:
  +c0 = U32.shrn(b0, 2n)
  +c1 = U32.shln(U32.and(b0, 3), 4n)
  SCon{b64_char(c0), SCon{b64_char(c1), SCon{Chr{61}, SCon{Chr{61}, SNil{}}}}}

def encode_bytes.tail(tail: String, +b0: U32, +b1: U32, +b2: U32) -> String:
  encode_triplet(b0, b1, b2) ++ tail

def encode_bytes.go(fuel: Nat, bytes: List<&2, U32>) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+p:
      match bytes:
        case Nil{}:
          ""
        case Con{+b0, t}:
          match t:
            case Nil{}:
              encode_single(b0)
            case Con{+b1, t2}:
              match t2:
                case Nil{}:
                  encode_pair(b0, b1)
                case Con{+b2, rest}:
                  encode_bytes.tail(encode_bytes.go(p, rest), b0, b1, b2)

def encode_bytes(+bytes: List<&2, U32>) -> String:
  encode_bytes.go(Nat.add(1n, List.length(&2, U32, bytes)), bytes)

def str_to_bytes.go(fuel: Nat, s: String) -> List<&2, U32>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      match s:
        case SNil{}:
          Nil{}
        case SCon{+h, +t}:
          Char.to_u32(h) <> str_to_bytes.go(p, t)

def str_to_bytes(+s: String) -> List<&2, U32>:
  str_to_bytes.go(Nat.add(1n, String.length(s)), s)

def sasl_plain_bytes(+user: String, +pass: String) -> List<&2, U32>:
  0 <> List.append(&2, U32, str_to_bytes(user), 0 <> str_to_bytes(pass))

def sasl_plain(+user: String, +pass: String) -> String:
  encode_bytes(sasl_plain_bytes(user, pass))

def sasl_plain_ok() -> Bool:
  String.eq(sasl_plain("user", "pass"), "AHVzZXIAcGFzcw==")
    && String.eq(sasl_plain("alice", "secret"), "AGFsaWNlAHNlY3JldA==")
    && String.eq(sasl_plain("", ""), "AAA=")
