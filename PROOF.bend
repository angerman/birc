# Protocol proofs. Each law is discharged by a same-named def.
import Base
import ./src/bend/irc.bend as Irc
import ./src/bend/buffer.bend as Cl
import ./src/bend/client.bend as Feed
import ./src/bend/submit.bend as Sub
import ./src/bend/frame.bend as Fr
import ./src/bend/view.bend as V
import ./src/bend/session.bend as Sess
import ./LAWS.bend as Laws

def Laws.ping_classified():
  {==}

def Laws.pong_concrete():
  {==}

def Laws.ping_casefold():
  {==}

def Laws.hash_is_channel():
  {==}

def Laws.nick_not_channel():
  {==}

def Laws.empty_not_channel():
  {==}

def Laws.clamp_empty_ok():
  {==}

def Laws.clamp_samples():
  {==}

def Laws.strip_ctl_nocr():
  {==}

def strip_ctl_clean.keep_false(
  +h: Char,
  r: String,
  deq: {Irc.is_crlf(h) == False{} : Bool},
  e: {Irc.has_crlf(r) == False{} : Bool}
) -> {Irc.has_crlf(SCon{h, r}) == False{} : Bool}:
  %Equal.sym(Bool, Irc.is_crlf(h), False{}, deq) : {Bool.or(_, Irc.has_crlf(r)) == False{} : Bool}
  e

def strip_ctl_clean.step(
  +h: Char,
  r: String,
  drop: Bool,
  deq: {Irc.is_crlf(h) == drop : Bool},
  e: {Irc.has_crlf(r) == False{} : Bool}
) -> {Irc.has_crlf(Irc.strip_ctl.keep(h, r, drop)) == False{} : Bool}:
  match drop:
    case True{}:
      e
    case False{}:
      strip_ctl_clean.keep_false(h, r, deq, e)

def Laws.strip_ctl_clean(s):
  match s:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      strip_ctl_clean.step(h, Irc.strip_ctl(t), Irc.is_crlf(h), {==}, Laws.strip_ctl_clean(t))

def Laws.ieq_ping():
  {==}

def Laws.feed_empty_id():
  {==}

def Laws.feed_ping_nbuf():
  {==}

def Laws.submit_line_ok():
  {==}

def Laws.submit_empty_ok():
  {==}

def Laws.framer_roundtrip():
  {==}

def Laws.scroll_bounds():
  {==}

def Laws.body_h_fits():
  {==}

def Laws.tokenize_bold():
  {==}

def Laws.tokenize_has_bold():
  {==}

def Laws.tokenize_has_italic():
  {==}

def Laws.tokenize_has_code():
  {==}

def Laws.tokenize_has_link():
  {==}

def Laws.tokenize_unclosed():
  {==}

def Laws.overlong_drop():
  {==}

def Laws.flood_buffers():
  {==}

def Laws.flood_server_clean():
  {==}

def Laws.notice_star_server():
  {==}

def Laws.privmsg_query_opens():
  {==}

def Laws.welcome_server_line():
  {==}

def Laws.names_1459():
  {==}

def Laws.kick_self_drops():
  {==}

def Laws.log_chrono():
  {==}

def Laws.cycle_tab():
  {==}

def Laws.style_self_ne_msg():
  {==}

def Laws.ts_width_ok():
  {==}

def Laws.vis_chrono():
  {==}

def Laws.body_ys_ok():
  {==}

def Laws.net_demo_ok():
  {==}

def Laws.scroll_page():
  {==}

def Laws.snap_scroll():
  {==}

def Laws.hist_cap():
  {==}

def Laws.submit_halt():
  {==}

def Laws.connect_parse():
  {==}

def Laws.connect_dial():
  {==}

def Laws.fmt_hms_ok():
  {==}

def Laws.log_ts_ok():
  {==}

def Laws.overlong_text_drop():
  {==}

def Laws.cr_flood_cap():
  {==}

def Laws.bare_cr_drop():
  {==}

def Laws.legal_max_line():
  {==}

def Laws.legal_509_line():
  {==}

def Laws.short_text_ok():
  {==}

def Laws.push_rem_510():
  {==}

def Laws.push_rem_511():
  {==}

def Laws.parse_id_short():
  {==}

def Laws.parse_id_bad():
  {==}

# Q2: law push_rem_bound. For every xs, the remainder of push(Nil, xs)
# has length ≤ LINE_OCTET_MAX+1.
# inv: Normal and AfterCr keep n ≤ 510 and n = length(rem). The held CR
# is not stored yet, so finish adds at most one octet. Drop keeps rem
# empty and n = 0.
# step_ok follows the same matches as step and shows step preserves inv.
# walk_le inducts on the input: Nil finishes, Con{b,t} recurses on the
# tail after step. fin_normal and fin_after turn inv into the public
# bound. reverse does not change length. n ≤ 510 implies n ≤ 511 and
# 1+n ≤ 511. Point laws push_rem_510 and push_rem_511 stay.

def clash.at(A: Type, b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      A

def clash(-A: Type, e: {True{} == False{} : Bool}) -> A:
  %e : clash.at(A, _)
  Unit{}

def bad_eq.at(A: Type, c: Cmp) -> Type:
  match c:
    case LT{}:
      A
    case EQ{}:
      Unit
    case GT{}:
      Unit

def bad_eq(-A: Type, e: {EQ{} == LT{} : Cmp}) -> A:
  %e : bad_eq.at(A, _)
  Unit{}

def bad_gt.at(A: Type, c: Cmp) -> Type:
  match c:
    case LT{}:
      A
    case EQ{}:
      Unit
    case GT{}:
      Unit

def bad_gt(-A: Type, e: {GT{} == LT{} : Cmp}) -> A:
  %e : bad_gt.at(A, _)
  Unit{}

def and_true(a: Bool, b: Bool, ea: {a == True{} : Bool}, eb: {b == True{} : Bool}) -> {Bool.and(a, b) == True{} : Bool}:
  %Equal.sym(Bool, a, True{}, ea) : {Bool.and(_, b) == True{} : Bool}
  eb

def and_l(a: Bool, -b: Bool, e: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      e

def and_r(a: Bool, b: Bool, e: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  match a:
    case True{}:
      e
    case False{}:
      clash({b == True{} : Bool}, Equal.sym(Bool, False{}, True{}, e))

def and_split(a: Bool, b: Bool, e: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool} & {b == True{} : Bool}:
  match a:
    case False{}:
      clash(({a == True{} : Bool} & {b == True{} : Bool}), Equal.sym(Bool, False{}, True{}, e))
    case True{}:
      ({==}, e)

def add_zero(a: Nat) -> {Nat.add(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

def add_succ(a: Nat, -b: Nat) -> {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ(p, b) : {1n+Nat.add(p, 1n+b) == 1n+_ : Nat}
      {==}

def eq_trans(a: Nat, b: Nat, c: Nat, eab: {a == b : Nat}, ebc: {b == c : Nat}) -> {a == c : Nat}:
  %Equal.sym(Nat, a, b, eab) : {_ == c : Nat}
  ebc

def le_succ(n: Nat, m: Nat, e: {Nat.is_le(n, m) == True{} : Bool}) -> {Nat.is_le(1n+n, 1n+m) == True{} : Bool}:
  e

def le_widen(n: Nat, m: Nat, e: {Nat.is_le(n, m) == True{} : Bool}) -> {Nat.is_le(n, 1n+m) == True{} : Bool}:
  match n m:
    case 0n _:
      {==}
    case 1n+np 0n:
      clash({Nat.is_le(1n+np, 1n) == True{} : Bool}, Equal.sym(Bool, False{}, True{}, e))
    case 1n+np 1n+mp:
      le_widen(np, mp, e)

def cmp_lt(c: Cmp, le: {Cmp.is_le(c) == True{} : Bool}, nge: {Cmp.is_ge(c) == False{} : Bool}) -> {c == LT{} : Cmp}:
  match c:
    case LT{}:
      {==}
    case EQ{}:
      clash({EQ{} == LT{} : Cmp}, nge)
    case GT{}:
      clash({GT{} == LT{} : Cmp}, Equal.sym(Bool, False{}, True{}, le))

def lt_zero(mp: Nat) -> {Cmp.is_le(Nat.cmp(1n, 1n+mp)) == True{} : Bool}:
  match mp:
    case 0n:
      {==}
    case 1n+_:
      {==}

def lt_succ_le(n: Nat, m: Nat, e: {Nat.cmp(n, m) == LT{} : Cmp}) -> {Cmp.is_le(Nat.cmp(1n+n, m)) == True{} : Bool}:
  match n m:
    case 0n 0n:
      bad_eq({Cmp.is_le(Nat.cmp(1n, 0n)) == True{} : Bool}, e)
    case 0n 1n+mp:
      lt_zero(mp)
    case 1n+np 0n:
      bad_gt({Cmp.is_le(Nat.cmp(1n+1n+np, 0n)) == True{} : Bool}, e)
    case 1n+np 1n+mp:
      lt_succ_le(np, mp, e)

def le_step(+n: Nat, +m: Nat, ele: {Nat.is_le(n, m) == True{} : Bool}, nge: {Nat.is_ge(n, m) == False{} : Bool}) -> {Nat.is_le(1n+n, m) == True{} : Bool}:
  lt_succ_le(n, m, cmp_lt(Nat.cmp(n, m), ele, nge))

def len_succ(+b: U32, rem: List<&2, U32>, n: Nat, e: {Fr.len_ok(rem, n) == True{} : Bool}) -> {Fr.len_ok(b <> rem, 1n+n) == True{} : Bool}:
  e

def nat_eq(a: Nat, b: Nat, e: {Nat.is_eq(a, b) == True{} : Bool}) -> {a == b : Nat}:
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+bp:
      clash({0n == 1n+bp : Nat}, Equal.sym(Bool, False{}, True{}, e))
    case 1n+ap 0n:
      clash({1n+ap == 0n : Nat}, Equal.sym(Bool, False{}, True{}, e))
    case 1n+ap 1n+bp:
      %nat_eq(ap, bp, e) : {1n+ap == 1n+_ : Nat}
      {==}

def le_replace(a: Nat, b: Nat, m: Nat, eab: {b == a : Nat}, ele: {Nat.is_le(b, m) == True{} : Bool}) -> {Nat.is_le(a, m) == True{} : Bool}:
  %eab : {Nat.is_le(_, m) == True{} : Bool}
  ele

def rev_acc(xs: List<&2, U32>, +acc: List<&2, U32>) -> {List.length(&2, U32, List.reverse.go(&2, U32, xs, acc)) == Nat.add(List.length(&2, U32, xs), List.length(&2, U32, acc)) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case +h <> +t:
      %add_succ(List.length(&2, U32, t), List.length(&2, U32, acc)) : {List.length(&2, U32, List.reverse.go(&2, U32, t, h <> acc)) == _ : Nat}
      rev_acc(t, h <> acc)

def rev_len(+xs: List<&2, U32>) -> {List.length(&2, U32, List.reverse(&2, U32, xs)) == List.length(&2, U32, xs) : Nat}:
  eq_trans(
    List.length(&2, U32, List.reverse.go(&2, U32, xs, Nil{})),
    Nat.add(List.length(&2, U32, xs), 0n),
    List.length(&2, U32, xs),
    rev_acc(xs, Nil{}),
    add_zero(List.length(&2, U32, xs))
  )

def succ_cong(a: Nat, b: Nat, e: {a == b : Nat}) -> {1n+a == 1n+b : Nat}:
  %e : {1n+a == 1n+_ : Nat}
  {==}

def store_ok(
  +rem: List<&2, U32>,
  +n: Nat,
  +b: U32,
  ele: {Nat.is_le(n, Fr.LINE_OCTET_MAX()) == True{} : Bool},
  elen: {Fr.len_ok(rem, n) == True{} : Bool},
  nge: {Nat.is_ge(n, Fr.LINE_OCTET_MAX()) == False{} : Bool}
) -> {Fr.mode_ok(Fr.Normal{}, b <> rem, 1n+n) == True{} : Bool}:
  and_true(
    Nat.is_le(1n+n, Fr.LINE_OCTET_MAX()),
    Fr.len_ok(b <> rem, 1n+n),
    le_step(n, Fr.LINE_OCTET_MAX(), ele, nge),
    len_succ(b, rem, n, elen)
  )

def step_store(
  +rem: List<&2, U32>,
  +n: Nat,
  +b: U32,
  nge: {Nat.is_ge(n, Fr.LINE_OCTET_MAX()) == False{} : Bool},
  parts: {Nat.is_le(n, Fr.LINE_OCTET_MAX()) == True{} : Bool} & {Fr.len_ok(rem, n) == True{} : Bool}
) -> {Fr.mode_ok(Fr.Normal{}, b <> rem, 1n+n) == True{} : Bool}:
  match parts:
    case (ele, elen):
      store_ok(rem, n, b, ele, elen, nge)

def step_ok_over(
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  over: Bool,
  deq: {Nat.is_ge(n, Fr.LINE_OCTET_MAX()) == over : Bool},
  e: {Fr.mode_ok(Fr.Normal{}, rem, n) == True{} : Bool}
) -> {Fr.inv(Fr.step_normal.over(rem, lines, n, b, over)) == True{} : Bool}:
  match over:
    case True{}:
      {==}
    case False{}:
      step_store(rem, n, b, deq, and_split(Nat.is_le(n, Fr.LINE_OCTET_MAX()), Fr.len_ok(rem, n), e))

def step_ok_cr(
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  is_cr: Bool,
  over: Bool,
  deq_cr: {U32.is_eq(b, Fr.CR()) == is_cr : Bool},
  deq_over: {Nat.is_ge(n, Fr.LINE_OCTET_MAX()) == over : Bool},
  e: {Fr.mode_ok(Fr.Normal{}, rem, n) == True{} : Bool}
) -> {Fr.inv(Fr.step_normal.cr(rem, lines, n, b, is_cr, over)) == True{} : Bool}:
  match is_cr:
    case True{}:
      e
    case False{}:
      step_ok_over(rem, lines, n, b, over, deq_over, e)

def step_ok_n(
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  is_lf: Bool,
  is_cr: Bool,
  over: Bool,
  deq_lf: {U32.is_eq(b, Fr.LF()) == is_lf : Bool},
  deq_cr: {U32.is_eq(b, Fr.CR()) == is_cr : Bool},
  deq_over: {Nat.is_ge(n, Fr.LINE_OCTET_MAX()) == over : Bool},
  e: {Fr.mode_ok(Fr.Normal{}, rem, n) == True{} : Bool}
) -> {Fr.inv(Fr.step_normal(rem, lines, n, b, is_lf, is_cr, over)) == True{} : Bool}:
  match is_lf:
    case True{}:
      {==}
    case False{}:
      step_ok_cr(rem, lines, n, b, is_cr, over, deq_cr, deq_over, e)

def step_ok_a(
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  is_lf: Bool,
  deq: {U32.is_eq(b, Fr.LF()) == is_lf : Bool},
  e: {Fr.mode_ok(Fr.AfterCr{}, rem, n) == True{} : Bool}
) -> {Fr.inv(Fr.step_after(rem, lines, n, is_lf)) == True{} : Bool}:
  match is_lf:
    case True{}:
      {==}
    case False{}:
      {==}

def step_ok_d(
  +lines: List<&2, String>,
  is_lf: Bool
) -> {Fr.inv(Fr.step_dropping(lines, is_lf)) == True{} : Bool}:
  match is_lf:
    case True{}:
      {==}
    case False{}:
      {==}

def step_ok_mode(
  mode: Fr.FrMode,
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  +b: U32,
  e: {Fr.mode_ok(mode, rem, n) == True{} : Bool}
) -> {Fr.inv(Fr.step_mode(mode, rem, lines, n, b)) == True{} : Bool}:
  match mode:
    case Fr.Normal{}:
      step_ok_n(
        rem,
        lines,
        n,
        b,
        U32.is_eq(b, Fr.LF()),
        U32.is_eq(b, Fr.CR()),
        Nat.is_ge(n, Fr.LINE_OCTET_MAX()),
        {==},
        {==},
        {==},
        e
      )
    case Fr.AfterCr{}:
      step_ok_a(rem, lines, n, b, U32.is_eq(b, Fr.LF()), {==}, e)
    case Fr.Drop{}:
      step_ok_d(lines, U32.is_eq(b, Fr.LF()))

def step_ok(+st: Fr.FrSt, +b: U32, e: {Fr.inv(st) == True{} : Bool}) -> {Fr.inv(Fr.step(st, b)) == True{} : Bool}:
  match st:
    case Fr.FrSt{+rem, +lines, +n, mode}:
      step_ok_mode(mode, rem, lines, n, b, e)

def fin_normal.go(
  +rem: List<&2, U32>,
  +n: Nat,
  ele: {Nat.is_le(n, Fr.LINE_OCTET_MAX()) == True{} : Bool},
  elen: {Fr.len_ok(rem, n) == True{} : Bool}
) -> {Nat.is_le(List.length(&2, U32, List.reverse(&2, U32, rem)), Fr.LINE_REM_MAX()) == True{} : Bool}:
  le_replace(
    List.length(&2, U32, List.reverse(&2, U32, rem)),
    n,
    Fr.LINE_REM_MAX(),
    Equal.sym(
      Nat,
      List.length(&2, U32, List.reverse(&2, U32, rem)),
      n,
      eq_trans(
        List.length(&2, U32, List.reverse(&2, U32, rem)),
        List.length(&2, U32, rem),
        n,
        rev_len(rem),
        nat_eq(List.length(&2, U32, rem), n, elen)
      )
    ),
    le_widen(n, Fr.LINE_OCTET_MAX(), ele)
  )

def fin_normal.on(
  +rem: List<&2, U32>,
  +n: Nat,
  parts: {Nat.is_le(n, Fr.LINE_OCTET_MAX()) == True{} : Bool} & {Fr.len_ok(rem, n) == True{} : Bool}
) -> {Nat.is_le(List.length(&2, U32, List.reverse(&2, U32, rem)), Fr.LINE_REM_MAX()) == True{} : Bool}:
  match parts:
    case (ele, elen):
      fin_normal.go(rem, n, ele, elen)

def fin_normal(
  +rem: List<&2, U32>,
  +n: Nat,
  e: {Fr.mode_ok(Fr.Normal{}, rem, n) == True{} : Bool}
) -> {Nat.is_le(List.length(&2, U32, List.reverse(&2, U32, rem)), Fr.LINE_REM_MAX()) == True{} : Bool}:
  fin_normal.on(rem, n, and_split(Nat.is_le(n, Fr.LINE_OCTET_MAX()), Fr.len_ok(rem, n), e))

def fin_after.go(
  +rem: List<&2, U32>,
  +n: Nat,
  ele: {Nat.is_le(n, Fr.LINE_OCTET_MAX()) == True{} : Bool},
  elen: {Fr.len_ok(rem, n) == True{} : Bool}
) -> {Nat.is_le(List.length(&2, U32, List.reverse(&2, U32, Fr.CR() <> rem)), Fr.LINE_REM_MAX()) == True{} : Bool}:
  le_replace(
    List.length(&2, U32, List.reverse(&2, U32, Fr.CR() <> rem)),
    1n+n,
    Fr.LINE_REM_MAX(),
    Equal.sym(
      Nat,
      List.length(&2, U32, List.reverse(&2, U32, Fr.CR() <> rem)),
      1n+n,
      eq_trans(
        List.length(&2, U32, List.reverse(&2, U32, Fr.CR() <> rem)),
        1n+List.length(&2, U32, rem),
        1n+n,
        rev_len(Fr.CR() <> rem),
        succ_cong(List.length(&2, U32, rem), n, nat_eq(List.length(&2, U32, rem), n, elen))
      )
    ),
    le_succ(n, Fr.LINE_OCTET_MAX(), ele)
  )

def fin_after.on(
  +rem: List<&2, U32>,
  +n: Nat,
  parts: {Nat.is_le(n, Fr.LINE_OCTET_MAX()) == True{} : Bool} & {Fr.len_ok(rem, n) == True{} : Bool}
) -> {Nat.is_le(List.length(&2, U32, List.reverse(&2, U32, Fr.CR() <> rem)), Fr.LINE_REM_MAX()) == True{} : Bool}:
  match parts:
    case (ele, elen):
      fin_after.go(rem, n, ele, elen)

def fin_after(
  +rem: List<&2, U32>,
  +n: Nat,
  e: {Fr.mode_ok(Fr.AfterCr{}, rem, n) == True{} : Bool}
) -> {Nat.is_le(List.length(&2, U32, List.reverse(&2, U32, Fr.CR() <> rem)), Fr.LINE_REM_MAX()) == True{} : Bool}:
  fin_after.on(rem, n, and_split(Nat.is_le(n, Fr.LINE_OCTET_MAX()), Fr.len_ok(rem, n), e))

def fin_mode(
  mode: Fr.FrMode,
  +rem: List<&2, U32>,
  +lines: List<&2, String>,
  +n: Nat,
  e: {Fr.mode_ok(mode, rem, n) == True{} : Bool}
) -> {Nat.is_le(Fr.rem_len(Fr.push.pair(Fr.finish_mode(mode, rem, lines))), Fr.LINE_REM_MAX()) == True{} : Bool}:
  match mode:
    case Fr.Normal{}:
      fin_normal(rem, n, e)
    case Fr.AfterCr{}:
      fin_after(rem, n, e)
    case Fr.Drop{}:
      {==}

def fin_le(st: Fr.FrSt, e: {Fr.inv(st) == True{} : Bool}) -> {Nat.is_le(Fr.rem_len(Fr.push.pair(Fr.finish(st))), Fr.LINE_REM_MAX()) == True{} : Bool}:
  match st:
    case Fr.FrSt{+rem, +lines, +n, mode}:
      fin_mode(mode, rem, lines, n, e)

def walk_le(
  +inp: List<&2, U32>,
  +st: Fr.FrSt,
  e: {Fr.inv(st) == True{} : Bool}
) -> {Nat.is_le(Fr.rem_len(Fr.push.pair(Fr.walk(inp, st))), Fr.LINE_REM_MAX()) == True{} : Bool}:
  match inp:
    case Nil{}:
      fin_le(st, e)
    case +b <> t:
      walk_le(t, Fr.step(st, b), step_ok(st, b, e))

def empty_inv() -> {Fr.inv(Fr.reopen(False{}, Nil{})) == True{} : Bool}:
  {==}

def Laws.push_rem_bound(xs):
  walk_le(xs, Fr.reopen(False{}, Nil{}), empty_inv())

def Laws.live_fuel_small():
  {==}
