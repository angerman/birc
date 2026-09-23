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

# RFC 1459: a line ends in CRLF. A CR not followed by LF is a bare CR
# and drops the whole line, like the over-long case. A CR at the end of
# a chunk is held on rem (octet 13) so a split CRLF still emits.
# One byte, one step. walk recurses on the tail only (no fuel).
type FrMode is Data:
  Normal{}
  AfterCr{}
  Drop{}

type FrSt is Data:
  FrSt{rem: List<&2, U32>, lines: List<&2, String>, n: Nat, mode: FrMode}

def payload_n(+rem: List<&2, U32>) -> Nat:
  List.length(&2, U32, rem)

def step_emit(+rem: List<&2, U32>, +lines: List<&2, String>) -> FrSt:
  FrSt{Nil{}, emit_line(rem, lines), 0n, Normal{}}

def step_hold(+rem: List<&2, U32>, +lines: List<&2, String>, +n: Nat) -> FrSt:
  FrSt{rem, lines, n, AfterCr{}}

def step_store(+rem: List<&2, U32>, +lines: List<&2, String>, +n: Nat, +b: U32) -> FrSt:
  FrSt{b <> rem, lines, 1n+n, Normal{}}

def step_to_drop(+lines: List<&2, String>) -> FrSt:
  FrSt{Nil{}, lines, 0n, Drop{}}

def step_from_drop(+lines: List<&2, String>) -> FrSt:
  FrSt{Nil{}, lines, 0n, Normal{}}

def step_normal.over(
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  over: Bool
) -> FrSt:
  match over:
    case True{}:
      step_to_drop(lines)
    case False{}:
      step_store(rem, lines, n, b)

def step_normal.cr(
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  is_cr: Bool,
  over: Bool
) -> FrSt:
  match is_cr:
    case True{}:
      step_hold(rem, lines, n)
    case False{}:
      step_normal.over(rem, lines, n, b, over)

def step_normal(
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  is_lf: Bool,
  is_cr: Bool,
  over: Bool
) -> FrSt:
  match is_lf:
    case True{}:
      step_emit(rem, lines)
    case False{}:
      step_normal.cr(rem, lines, n, b, is_cr, over)

def step_after(+rem: List<&2, U32>, +lines: List<&2, String>, +n: Nat, is_lf: Bool) -> FrSt:
  match is_lf:
    case True{}:
      step_emit(rem, lines)
    case False{}:
      step_to_drop(lines)

def step_dropping(+lines: List<&2, String>, is_lf: Bool) -> FrSt:
  match is_lf:
    case True{}:
      step_from_drop(lines)
    case False{}:
      step_to_drop(lines)

def step_mode(
  mode: FrMode,
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32
) -> FrSt:
  match mode:
    case Normal{}:
      step_normal(rem, lines, n, b, U32.is_eq(b, LF()), U32.is_eq(b, CR()), Nat.is_ge(n, LINE_OCTET_MAX()))
    case AfterCr{}:
      step_after(rem, lines, n, U32.is_eq(b, LF()))
    case Drop{}:
      step_dropping(lines, U32.is_eq(b, LF()))

def step(st: FrSt, +b: U32) -> FrSt:
  match st:
    case FrSt{+rem, +lines, +n, mode}:
      step_mode(mode, rem, lines, n, b)

def finish.out(+lines: List<&2, String>, +rem: List<&2, U32>, drop: Bool) -> List<&2, String> & List<&2, U32> & Bool:
  (List.reverse(&2, String, lines), List.reverse(&2, U32, rem), drop)

def finish_mode(mode: FrMode, +rem: List<&2, U32>, +lines: List<&2, String>) -> List<&2, String> & List<&2, U32> & Bool:
  match mode:
    case Normal{}:
      finish.out(lines, rem, False{})
    case AfterCr{}:
      finish.out(lines, CR() <> rem, False{})
    case Drop{}:
      finish.out(lines, Nil{}, True{})

def finish(st: FrSt) -> List<&2, String> & List<&2, U32> & Bool:
  match st:
    case FrSt{+rem, +lines, _, mode}:
      finish_mode(mode, rem, lines)

def walk(+inp: List<&2, U32>, st: FrSt) -> List<&2, String> & List<&2, U32> & Bool:
  match inp:
    case Nil{}:
      finish(st)
    case Con{+b, t}:
      walk(t, step(st, b))

def reopen_hd(+h: U32, t: List<&2, U32>, +n: Nat, pend: Bool) -> FrSt:
  match pend:
    case True{}:
      FrSt{t, Nil{}, Nat.sub(n, 1n), AfterCr{}}
    case False{}:
      FrSt{h <> t, Nil{}, n, Normal{}}

def reopen_cr(+rev: List<&2, U32>, +n: Nat) -> FrSt:
  match rev:
    case Nil{}:
      FrSt{Nil{}, Nil{}, n, Normal{}}
    case Con{+h, t}:
      reopen_hd(h, t, n, U32.is_eq(h, CR()))

def reopen_keep(+rem: List<&2, U32>) -> FrSt:
  reopen_cr(List.reverse(&2, U32, rem), payload_n(rem))

def reopen(drop: Bool, +rem: List<&2, U32>) -> FrSt:
  match drop:
    case True{}:
      FrSt{Nil{}, Nil{}, 0n, Drop{}}
    case False{}:
      reopen_keep(rem)

def push_ex(+drop: Bool, +rem: List<&2, U32>, +chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32> & Bool:
  walk(chunk, reopen(drop, rem))

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

def rem_len(got: List<&2, String> & List<&2, U32>) -> Nat:
  match got:
    case (_, rem):
      List.length(&2, U32, rem)

# A CR at a chunk boundary is held (is_cr before over), so rem can be 511.
def LINE_REM_MAX() -> Nat:
  Nat.add(LINE_OCTET_MAX(), 1n)

def rem510() -> List<&2, U32>:
  repeat_octet.go(510n, 97, Nil{})

def rem510cr() -> List<&2, U32>:
  List.append(&2, U32, rem510(), CR() <> Nil{})

def push_rem_le(+xs: List<&2, U32>) -> Bool:
  Nat.is_le(rem_len(push(Nil{}, xs)), LINE_REM_MAX())

def rem510_ok() -> Bool:
  Nat.is_eq(rem_len(push(Nil{}, rem510())), LINE_OCTET_MAX())

def rem511_ok() -> Bool:
  Nat.is_eq(rem_len(push(Nil{}, rem510cr())), LINE_REM_MAX())

def short_text_ok.fin(got: List<&2, String> & List<&2, U32>) -> Bool:
  match got:
    case (lines, _):
      Nat.is_eq(List.length(&2, String, lines), 1n)

def short_text_ok() -> Bool:
  short_text_ok.fin(push(Nil{}, string_to_octets("PING :x\r\n")))
