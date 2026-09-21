# CRLF framer (M4.1). Octets List<&2,U32> -> lines & remainder.
import Base
import ./irc.bend as Irc

def CR() -> U32:
  13

def LF() -> U32:
  10

def LINE_OCTET_MAX() -> Nat:
  Irc.LINE_MAX()

def octets_to_string.go(fuel: Nat, +xs: List<&2, U32>, +acc: String) -> String:
  match fuel:
    case 0n:
      String.reverse(acc)
    case 1n+p:
      match xs:
        case Nil{}:
          String.reverse(acc)
        case Con{+h, t}:
          octets_to_string.go(p, t, SCon{Chr{h}, acc})

def octets_to_string(+xs: List<&2, U32>) -> String:
  octets_to_string.go(Nat.add(1n, List.length(&2, U32, xs)), xs, "")

def char_code(+c: Char) -> U32:
  match c:
    case Chr{code}:
      code

def string_to_octets.go(fuel: Nat, +s: String, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+p:
      match s:
        case SNil{}:
          List.reverse(&2, U32, acc)
        case SCon{+h, t}:
          string_to_octets.go(p, t, char_code(h) <> acc)

def string_to_octets(+s: String) -> List<&2, U32>:
  string_to_octets.go(Nat.add(1n, String.length(s)), s, Nil{})

def crlf(+s: String) -> List<&2, U32>:
  List.append(&2, U32, string_to_octets(s), CR() <> LF() <> Nil{})

def emit_line.cr(+h: U32, +t: List<&2, U32>, lines: List<&2, String>, was_cr: Bool) -> List<&2, String>:
  match was_cr:
    case True{}:
      Irc.sanitize_in(octets_to_string(List.reverse(&2, U32, t))) <> lines
    case False{}:
      Irc.sanitize_in(octets_to_string(List.reverse(&2, U32, h <> t))) <> lines

def emit_line(+rem_rev: List<&2, U32>, lines: List<&2, String>) -> List<&2, String>:
  match rem_rev:
    case Nil{}:
      "" <> lines
    case Con{+h, t}:
      emit_line.cr(h, t, lines, U32.is_eq(h, CR()))

type PushPhase is Data:
  PRead{}
  PClass{}
  PAct{}
  PDrop{}
  PDropLf{}

def payload_n.dec(len: Nat) -> Nat:
  match len:
    case 0n:
      0n
    case 1n+p:
      p

def payload_n.adj(trail_cr: Bool, +len: Nat) -> Nat:
  match trail_cr:
    case True{}:
      payload_n.dec(len)
    case False{}:
      len

def payload_n.rev(+rev: List<&2, U32>, +len: Nat) -> Nat:
  match rev:
    case Nil{}:
      0n
    case Con{+h, _}:
      payload_n.adj(U32.is_eq(h, CR()), len)

def payload_n(+rem: List<&2, U32>) -> Nat:
  payload_n.rev(List.reverse(&2, U32, rem), List.length(&2, U32, rem))

def push.go.halt(+lines: List<&2, String>, +rem: List<&2, U32>, drop: Bool) -> List<&2, String> & List<&2, U32> & Bool:
  (List.reverse(&2, String, lines), List.reverse(&2, U32, rem), drop)

def push.go(
  fuel: Nat,
  phase: PushPhase,
  +inp: List<&2, U32>,
  +rem: List<&2, U32>,
  lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  is_lf: Bool,
  is_cr: Bool,
  over: Bool
) -> List<&2, String> & List<&2, U32> & Bool:
  match fuel:
    case 0n:
      # F3 — keep the current drop phase; do not reset to False.
      match phase:
        case PDrop{}:
          push.go.halt(lines, rem, True{})
        case PDropLf{}:
          push.go.halt(lines, rem, True{})
        case _:
          push.go.halt(lines, rem, False{})
    case 1n+p:
      match phase:
        case PRead{}:
          match inp:
            case Nil{}:
              push.go.halt(lines, rem, False{})
            case Con{+hd, t}:
              push.go(p, PClass{}, t, rem, lines, n, hd, False{}, False{}, False{})
        case PClass{}:
          push.go(p, PAct{}, inp, rem, lines, n, b, U32.is_eq(b, LF()), U32.is_eq(b, CR()), Nat.is_ge(n, LINE_OCTET_MAX()))
        case PAct{}:
          match is_lf:
            case True{}:
              push.go(p, PRead{}, inp, Nil{}, emit_line(rem, lines), 0n, 0, False{}, False{}, False{})
            case False{}:
              match is_cr:
                case True{}:
                  push.go(p, PRead{}, inp, rem, lines, n, 0, False{}, False{}, False{})
                case False{}:
                  match over:
                    case True{}:
                      push.go(p, PDrop{}, inp, Nil{}, lines, 0n, 0, False{}, False{}, False{})
                    case False{}:
                      push.go(p, PRead{}, inp, b <> rem, lines, 1n+n, 0, False{}, False{}, False{})
        case PDrop{}:
          match inp:
            case Nil{}:
              push.go.halt(lines, Nil{}, True{})
            case Con{+hd, t}:
              push.go(p, PDropLf{}, t, Nil{}, lines, 0n, hd, U32.is_eq(hd, LF()), False{}, False{})
        case PDropLf{}:
          match is_lf:
            case True{}:
              push.go(p, PRead{}, inp, Nil{}, lines, 0n, 0, False{}, False{}, False{})
            case False{}:
              push.go(p, PDrop{}, inp, Nil{}, lines, 0n, 0, False{}, False{}, False{})

def push_ex.keep(+rem: List<&2, U32>, +chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32> & Bool:
  push.go(
    Nat.add(1n, Nat.mul(4n, List.length(&2, U32, chunk))),
    PRead{},
    chunk,
    List.reverse(&2, U32, rem),
    Nil{},
    payload_n(rem),
    0,
    False{},
    False{},
    False{}
  )

def push_ex.drop(+chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32> & Bool:
  push.go(
    Nat.add(1n, Nat.mul(4n, List.length(&2, U32, chunk))),
    PDrop{},
    chunk,
    Nil{},
    Nil{},
    0n,
    0,
    False{},
    False{},
    False{}
  )

def push_ex.on(drop: Bool, +rem: List<&2, U32>, +chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32> & Bool:
  match drop:
    case True{}:
      push_ex.drop(chunk)
    case False{}:
      push_ex.keep(rem, chunk)

def push_ex(+drop: Bool, +rem: List<&2, U32>, +chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32> & Bool:
  push_ex.on(drop, rem, chunk)

def push.pair(got: List<&2, String> & List<&2, U32> & Bool) -> List<&2, String> & List<&2, U32>:
  match got:
    case (ls, rem, _):
      (ls, rem)

def push(+rem: List<&2, U32>, +chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32>:
  push.pair(push_ex(False{}, rem, chunk))

def join_lines.go(fuel: Nat, +xs: List<&2, String>, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{+h, t}:
          join_lines.go(p, t, List.append(&2, U32, acc, crlf(h)))

def join_lines(+xs: List<&2, String>) -> List<&2, U32>:
  join_lines.go(Nat.add(1n, List.length(&2, String, xs)), xs, Nil{})

def append_octets(+a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, a, b)

type EqPhase is Data:
  EqBoth{}
  EqHead{}

def octets_eq.go(fuel: Nat, phase: EqPhase, +a: List<&2, U32>, +b: List<&2, U32>, +ha: U32, +hb: U32, eq: Bool) -> Bool:
  match fuel:
    case 0n:
      False{}  # F3 fail-closed
    case 1n+p:
      match phase:
        case EqBoth{}:
          match a:
            case Nil{}:
              match b:
                case Nil{}:
                  True{}
                case Con{_, _}:
                  False{}
            case Con{+xa, ta}:
              match b:
                case Nil{}:
                  False{}
                case Con{+xb, tb}:
                  octets_eq.go(p, EqHead{}, ta, tb, xa, xb, U32.is_eq(xa, xb))
        case EqHead{}:
          match eq:
            case False{}:
              False{}
            case True{}:
              octets_eq.go(p, EqBoth{}, a, b, 0, 0, True{})

def octets_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  octets_eq.go(Nat.add(1n, Nat.mul(2n, Nat.add(List.length(&2, U32, a), List.length(&2, U32, b)))), EqBoth{}, a, b, 0, 0, True{})

def str_eq(+a: String, +b: String) -> Bool:
  String.eq(a, b)

def strings_eq.go(fuel: Nat, phase: EqPhase, +a: List<&2, String>, +b: List<&2, String>, +ha: String, +hb: String, eq: Bool) -> Bool:
  match fuel:
    case 0n:
      False{}  # F3 fail-closed
    case 1n+p:
      match phase:
        case EqBoth{}:
          match a:
            case Nil{}:
              match b:
                case Nil{}:
                  True{}
                case Con{_, _}:
                  False{}
            case Con{+xa, ta}:
              match b:
                case Nil{}:
                  False{}
                case Con{+xb, tb}:
                  strings_eq.go(p, EqHead{}, ta, tb, xa, xb, str_eq(xa, xb))
        case EqHead{}:
          match eq:
            case False{}:
              False{}
            case True{}:
              strings_eq.go(p, EqBoth{}, a, b, "", "", True{})

def strings_eq(+a: List<&2, String>, +b: List<&2, String>) -> Bool:
  strings_eq.go(Nat.add(1n, Nat.mul(2n, Nat.add(List.length(&2, String, a), List.length(&2, String, b)))), EqBoth{}, a, b, "", "", True{})

def roundtrip_ok.cmp(+gl: List<&2, String>, +lines: List<&2, String>, +gr: List<&2, U32>, +rem: List<&2, U32>) -> Bool:
  strings_eq(gl, lines) && octets_eq(gr, rem)

def roundtrip_ok.pair(got: List<&2, String> & List<&2, U32>, +lines: List<&2, String>, +rem: List<&2, U32>) -> Bool:
  match got:
    case (gl, gr):
      roundtrip_ok.cmp(gl, lines, gr, rem)

def roundtrip_ok(+lines: List<&2, String>, +rem: List<&2, U32>) -> Bool:
  roundtrip_ok.pair(push(Nil{}, append_octets(join_lines(lines), rem)), lines, rem)

# M7.2 — overlong line (≥ LINE_OCTET_MAX octets before LF) is dropped.
def repeat_octet.go(fuel: Nat, +x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      repeat_octet.go(p, x, x <> acc)

def a_line(+n: Nat) -> List<&2, U32>:
  List.append(&2, U32, repeat_octet.go(n, 65, Nil{}), CR() <> LF() <> Nil{})

def overlong_chunk() -> List<&2, U32>:
  a_line(511n)

def overlong_drop_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (lines, _):
      Nat.is_eq(List.length(&2, String, lines), 0n)

def overlong_drop_ok() -> Bool:
  overlong_drop_ok.fin(push(Nil{}, overlong_chunk()))

def one_line_len.rest(+want: Nat, +got: Nat, +t: List<&2, String>) -> Bool:
  match t:
    case Nil{}:
      Nat.is_eq(want, got)
    case Con{_, _}:
      False{}

def one_line_len(+want: Nat, +lines: List<&2, String>) -> Bool:
  match lines:
    case Nil{}:
      False{}
    case Con{+h, t}:
      one_line_len.rest(want, String.length(h), t)

def legal_max_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (lines, _):
      one_line_len(510n, lines)

def legal_max_ok() -> Bool:
  legal_max_ok.fin(push(Nil{}, a_line(510n)))

def legal_509_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (lines, _):
      one_line_len(509n, lines)

def legal_509_ok() -> Bool:
  legal_509_ok.fin(push(Nil{}, a_line(509n)))

def cr_flood_oct_ok.fin(got: List<&2, String> & List<&2, U32> & Bool) -> Bool:
  match got:
    case (lines, rem, _):
      Nat.is_eq(List.length(&2, String, lines), 0n) && Nat.is_le(List.length(&2, U32, rem), LINE_OCTET_MAX())

def cr_flood_oct_ok() -> Bool:
  cr_flood_oct_ok.fin(push_ex(False{}, Nil{}, repeat_octet.go(1200n, 13, Nil{})))

def overlong_text_drop_ok() -> Bool:
  overlong_drop_ok()

def cr_flood_ok() -> Bool:
  cr_flood_oct_ok()

def short_text_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (lines, _):
      Nat.is_eq(List.length(&2, String, lines), 1n)

def short_text_ok() -> Bool:
  short_text_ok.fin(push(Nil{}, string_to_octets("PING :x\r\n")))

# Latin-1: byte 0xE9 split from CRLF still becomes one line, not U+FFFD.
def split_high_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (ls, rem):
      match ls:
        case Con{+h, Nil{}}:
          match rem:
            case Nil{}:
              String.eq(h, SCon{Chr{233}, SNil{}})
            case Con{_, _}:
              False{}
        case _:
          False{}

def split_high_ok.go(st: List<&2, String> & List<&2, U32>) -> Bool:
  match st:
    case (_, rem):
      split_high_ok.fin(push(rem, CR() <> LF() <> Nil{}))

def split_high_ok() -> Bool:
  split_high_ok.go(push(Nil{}, 233 <> Nil{}))
