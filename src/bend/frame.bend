# CRLF framer (M4.1). Octets List<&2,U32> -> lines & remainder.
import Base
import ./irc.bend as Irc

def CR() -> U32:
  13

def LF() -> U32:
  10

def LINE_OCTET_MAX() -> Nat:
  Irc.LINE_MAX()

def octets_to_string(+xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}:
      SNil{}
    case Con{+h, t}:
      SCon{Chr{h}, octets_to_string(t)}

def is_cont(+b: U32) -> Bool:
  U32.is_ge(b, 128) && U32.is_le(b, 191)

def utf8_cp2(+b0: U32, +b1: U32) -> U32:
  U32.or(U32.shln(U32.and(b0, 31), 6n), U32.and(b1, 63))

def utf8_cp3(+b0: U32, +b1: U32, +b2: U32) -> U32:
  U32.or(
    U32.shln(U32.and(b0, 15), 12n),
    U32.or(U32.shln(U32.and(b1, 63), 6n), U32.and(b2, 63))
  )

def utf8_cp4(+b0: U32, +b1: U32, +b2: U32, +b3: U32) -> U32:
  U32.or(
    U32.shln(U32.and(b0, 7), 18n),
    U32.or(
      U32.shln(U32.and(b1, 63), 12n),
      U32.or(U32.shln(U32.and(b2, 63), 6n), U32.and(b3, 63))
    )
  )

def utf8_3_b1.ed(ed: Bool, +b1: U32) -> Bool:
  match ed:
    case True{}:
      U32.is_ge(b1, 128) && U32.is_le(b1, 159)
    case False{}:
      is_cont(b1)

def utf8_3_b1.e0(e0: Bool, +b0: U32, +b1: U32) -> Bool:
  match e0:
    case True{}:
      U32.is_ge(b1, 160) && U32.is_le(b1, 191)
    case False{}:
      utf8_3_b1.ed(U32.is_eq(b0, 237), b1)

def utf8_3_b1(+b0: U32, +b1: U32) -> Bool:
  utf8_3_b1.e0(U32.is_eq(b0, 224), b0, b1)

def utf8_4_b1.f4(f4: Bool, +b1: U32) -> Bool:
  match f4:
    case True{}:
      U32.is_ge(b1, 128) && U32.is_le(b1, 143)
    case False{}:
      is_cont(b1)

def utf8_4_b1.f0(f0: Bool, +b0: U32, +b1: U32) -> Bool:
  match f0:
    case True{}:
      U32.is_ge(b1, 144) && U32.is_le(b1, 191)
    case False{}:
      utf8_4_b1.f4(U32.is_eq(b0, 244), b1)

def utf8_4_b1(+b0: U32, +b1: U32) -> Bool:
  utf8_4_b1.f0(U32.is_eq(b0, 240), b0, b1)

type Utf8Got is Data:
  Utf8Got{cp: U32, rest: List<&2, U32>}

def utf8_hit(+cp: U32, rest: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  Some{Utf8Got{cp, rest}}

def utf8_step.two_cont(ok: Bool, +b0: U32, +b1: U32, rest: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  match ok:
    case False{}:
      None{}
    case True{}:
      utf8_hit(utf8_cp2(b0, b1), rest)

def utf8_step.two_take(+b0: U32, t: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  match t:
    case Nil{}:
      None{}
    case Con{+b1, rest}:
      utf8_step.two_cont(is_cont(b1), b0, b1, rest)

def utf8_step.three_cont(
  ok: Bool,
  +b0: U32,
  +b1: U32,
  +b2: U32,
  rest: List<&2, U32>
) -> Maybe<&2, Utf8Got>:
  match ok:
    case False{}:
      None{}
    case True{}:
      utf8_hit(utf8_cp3(b0, b1, b2), rest)

def utf8_step.three_b2(
  ok: Bool,
  +b0: U32,
  +b1: U32,
  t2: List<&2, U32>
) -> Maybe<&2, Utf8Got>:
  match ok:
    case False{}:
      None{}
    case True{}:
      match t2:
        case Nil{}:
          None{}
        case Con{+b2, rest}:
          utf8_step.three_cont(is_cont(b2), b0, b1, b2, rest)

def utf8_step.three_take(+b0: U32, t: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  match t:
    case Nil{}:
      None{}
    case Con{+b1, t2}:
      utf8_step.three_b2(utf8_3_b1(b0, b1), b0, b1, t2)

def utf8_step.four_cont(
  ok: Bool,
  +b0: U32,
  +b1: U32,
  +b2: U32,
  +b3: U32,
  rest: List<&2, U32>
) -> Maybe<&2, Utf8Got>:
  match ok:
    case False{}:
      None{}
    case True{}:
      utf8_hit(utf8_cp4(b0, b1, b2, b3), rest)

def utf8_step.four_b3(
  ok: Bool,
  +b0: U32,
  +b1: U32,
  +b2: U32,
  t3: List<&2, U32>
) -> Maybe<&2, Utf8Got>:
  match ok:
    case False{}:
      None{}
    case True{}:
      match t3:
        case Nil{}:
          None{}
        case Con{+b3, rest}:
          utf8_step.four_cont(is_cont(b3), b0, b1, b2, b3, rest)

def utf8_step.four_b2(
  ok: Bool,
  +b0: U32,
  +b1: U32,
  t2: List<&2, U32>
) -> Maybe<&2, Utf8Got>:
  match ok:
    case False{}:
      None{}
    case True{}:
      match t2:
        case Nil{}:
          None{}
        case Con{+b2, t3}:
          utf8_step.four_b3(is_cont(b2), b0, b1, b2, t3)

def utf8_step.four_take(+b0: U32, t: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  match t:
    case Nil{}:
      None{}
    case Con{+b1, t2}:
      utf8_step.four_b2(utf8_4_b1(b0, b1), b0, b1, t2)

def utf8_step.four(ok: Bool, +b0: U32, t: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  match ok:
    case True{}:
      utf8_step.four_take(b0, t)
    case False{}:
      None{}

def utf8_step.three(ok: Bool, +b0: U32, t: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  match ok:
    case True{}:
      utf8_step.three_take(b0, t)
    case False{}:
      utf8_step.four(U32.is_ge(b0, 240) && U32.is_le(b0, 244), b0, t)

def utf8_step.two(ok: Bool, +b0: U32, t: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  match ok:
    case True{}:
      utf8_step.two_take(b0, t)
    case False{}:
      utf8_step.three(U32.is_ge(b0, 224) && U32.is_le(b0, 239), b0, t)

def utf8_step.ascii(ok: Bool, +b0: U32, t: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  match ok:
    case True{}:
      utf8_hit(b0, t)
    case False{}:
      utf8_step.two(U32.is_ge(b0, 194) && U32.is_le(b0, 223), b0, t)

def utf8_step.lead(+b0: U32, t: List<&2, U32>) -> Maybe<&2, Utf8Got>:
  utf8_step.ascii(U32.is_lt(b0, 128), b0, t)

type Utf8Acc is Data:
  Utf8Acc{rest: List<&2, U32>, acc: String}

def utf8_got(
  m: Maybe<&2, Utf8Got>,
  acc: String,
  k: Utf8Acc -> Maybe<&2, String>
) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{got}:
      match got:
        case Utf8Got{+cp, rest}:
          k(Utf8Acc{rest, SCon{Chr{cp}, acc}})

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed utf8_decode.go
def utf8_decode.go(fuel: Nat, st: Utf8Acc) -> Maybe<&2, String>:
  match fuel:
    case 0n:
      None{}
    case 1n+p:
      match st:
        case Utf8Acc{xs, acc}:
          match xs:
            case Nil{}:
              Some{String.reverse(acc)}
            case Con{+b0, t}:
              utf8_got(utf8_step.lead(b0, t), acc, nxt => utf8_decode.go(p, nxt))

def utf8_decode(+xs: List<&2, U32>) -> Maybe<&2, String>:
  utf8_decode.go(Nat.add(1n, List.length(&2, U32, xs)), Utf8Acc{xs, SNil{}})

def line_from_octets.on(m: Maybe<&2, String>, +xs: List<&2, U32>) -> String:
  match m:
    case Some{+s}:
      s
    case None{}:
      octets_to_string(xs)

def line_from_octets(+xs: List<&2, U32>) -> String:
  line_from_octets.on(utf8_decode(xs), xs)

def char_code(+c: Char) -> U32:
  Char.to_u32(c)

def string_to_octets(+s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{+h, t}:
      char_code(h) <> string_to_octets(t)

def crlf(+s: String) -> List<&2, U32>:
  List.append(&2, U32, string_to_octets(s), CR() <> LF() <> Nil{})

def emit_line(+rem_rev: List<&2, U32>, lines: List<&2, String>) -> List<&2, String>:
  Irc.sanitize_in(line_from_octets(List.reverse(&2, U32, rem_rev))) <> lines

type PushPhase is Data:
  PRead{}
  PClass{}
  PAct{}
  PCr{}
  PDrop{}
  PDropLf{}

# RFC 1459: a line ends in CRLF. A CR not followed by LF is a bare CR
# and drops the whole line, like the over-long case. A CR at the end of
# a chunk is held on rem (octet 13) so a split CRLF still emits.
def payload_n(+rem: List<&2, U32>) -> Nat:
  List.length(&2, U32, rem)

def push.go.halt(+lines: List<&2, String>, +rem: List<&2, U32>, drop: Bool) -> List<&2, String> & List<&2, U32> & Bool:
  (List.reverse(&2, String, lines), List.reverse(&2, U32, rem), drop)

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed push.go
def push.go(
  fuel: Nat,
  phase: PushPhase,
  +inp: List<&2, U32>,
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  is_lf: Bool,
  is_cr: Bool,
  over: Bool
) -> List<&2, String> & List<&2, U32> & Bool:
  match fuel:
    case 0n:
      # Fuel exhaustion keeps the current drop phase; do not reset to False.
      match phase:
        case PDrop{}:
          push.go.halt(lines, rem, True{})
        case PDropLf{}:
          push.go.halt(lines, rem, True{})
        case PCr{}:
          push.go.halt(lines, CR() <> rem, False{})
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
                  push.go(p, PCr{}, inp, rem, lines, n, 0, False{}, False{}, False{})
                case False{}:
                  match over:
                    case True{}:
                      push.go(p, PDrop{}, inp, Nil{}, lines, 0n, 0, False{}, False{}, False{})
                    case False{}:
                      push.go(p, PRead{}, inp, b <> rem, lines, 1n+n, 0, False{}, False{}, False{})
        case PCr{}:
          match inp:
            case Nil{}:
              push.go.halt(lines, CR() <> rem, False{})
            case Con{+hd, t}:
              +lf = U32.is_eq(hd, LF())
              push.go(
                p,
                Bool.pick(PushPhase, lf, PRead{}, PDrop{}),
                Bool.pick(List<&2, U32>, lf, t, hd <> t),
                Nil{},
                Bool.pick(List<&2, String>, lf, emit_line(rem, lines), lines),
                0n,
                0,
                False{},
                False{},
                False{}
              )
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

def push_ex.keep.hd(+chunk: List<&2, U32>, +n: Nat, +h: U32, t: List<&2, U32>, pend: Bool) -> List<&2, String> & List<&2, U32> & Bool:
  match pend:
    case True{}:
      push.go(Nat.add(1n, Nat.mul(4n, List.length(&2, U32, chunk))), PCr{}, chunk, t, Nil{}, Nat.sub(n, 1n), 0, False{}, False{}, False{})
    case False{}:
      push.go(Nat.add(1n, Nat.mul(4n, List.length(&2, U32, chunk))), PRead{}, chunk, h <> t, Nil{}, n, 0, False{}, False{}, False{})

def push_ex.keep.cr(+rev: List<&2, U32>, +chunk: List<&2, U32>, +n: Nat) -> List<&2, String> & List<&2, U32> & Bool:
  match rev:
    case Nil{}:
      push.go(Nat.add(1n, Nat.mul(4n, List.length(&2, U32, chunk))), PRead{}, chunk, Nil{}, Nil{}, n, 0, False{}, False{}, False{})
    case Con{+h, t}:
      push_ex.keep.hd(chunk, n, h, t, U32.is_eq(h, CR()))

def push_ex.keep(+rem: List<&2, U32>, +chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32> & Bool:
  push_ex.keep.cr(List.reverse(&2, U32, rem), chunk, payload_n(rem))

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

def octets_rev_onto(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      acc
    case Con{+h, t}:
      octets_rev_onto(t, h <> acc)

def join_lines.go(+xs: List<&2, String>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      List.reverse(&2, U32, acc)
    case Con{+h, t}:
      join_lines.go(t, octets_rev_onto(crlf(h), acc))

def join_lines(+xs: List<&2, String>) -> List<&2, U32>:
  join_lines.go(xs, Nil{})

def append_octets(+a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, a, b)

def octets_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
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
          Bool.pick(Bool, U32.is_eq(xa, xb), octets_eq(ta, tb), False{})

def str_eq(+a: String, +b: String) -> Bool:
  String.eq(a, b)

def strings_eq(+a: List<&2, String>, +b: List<&2, String>) -> Bool:
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
          Bool.pick(Bool, str_eq(xa, xb), strings_eq(ta, tb), False{})

def roundtrip_ok.cmp(+gl: List<&2, String>, +lines: List<&2, String>, +gr: List<&2, U32>, +rem: List<&2, U32>) -> Bool:
  strings_eq(gl, lines) && octets_eq(gr, rem)

def roundtrip_ok.pair(got: List<&2, String> & List<&2, U32>, +lines: List<&2, String>, +rem: List<&2, U32>) -> Bool:
  match got:
    case (gl, gr):
      roundtrip_ok.cmp(gl, lines, gr, rem)

def roundtrip_ok(+lines: List<&2, String>, +rem: List<&2, U32>) -> Bool:
  roundtrip_ok.pair(push(Nil{}, append_octets(join_lines(lines), rem)), lines, rem)

# M7.2 — overlong line (≥ LINE_OCTET_MAX octets before LF) is dropped.
def repeat_octet.go(n: Nat, +x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
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

# Bare CR (not the CR of CRLF) drops the line. Next CRLF line still parses.
def bare_cr_drop_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (lines, rem):
      strings_eq(lines, "hello" <> Nil{}) && octets_eq(rem, Nil{})

def bare_cr_drop_ok() -> Bool:
  bare_cr_drop_ok.fin(push(Nil{}, string_to_octets("abc" ++ SCon{Chr{13}, "def\r\nhello\r\n"})))

def bare_cr_old_merge_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (lines, _):
      strings_eq(lines, "abcdef" <> "hello" <> Nil{})

def bare_cr_old_merge_ok() -> Bool:
  bare_cr_old_merge_ok.fin(push(Nil{}, string_to_octets("abc" ++ SCon{Chr{13}, "def\r\nhello\r\n"})))

def short_text_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (lines, _):
      Nat.is_eq(List.length(&2, String, lines), 1n)

def short_text_ok() -> Bool:
  short_text_ok.fin(push(Nil{}, string_to_octets("PING :x\r\n")))
