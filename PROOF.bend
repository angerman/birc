# Protocol proofs. Each law is discharged by a same-named def.
import Base
import ./src/bend/irc.bend as Irc
import ./src/bend/buffer.bend as Cl
import ./src/bend/client.bend as Feed
import ./src/bend/submit.bend as Sub
import ./src/bend/frame.bend as Fr
import ./src/bend/view.bend as V
import ./src/bend/session.bend as Sess
import ./src/bend/base64.bend as B64
import ./src/bend/typing.bend as Ty
import ./src/bend/outbound.bend as Act
import ./src/bend/media.bend as Media
import ./src/bend/cards.bend as Cards
import ./src/bend/cap_notify.bend as CapNotify
import ./LAWS.bend as Laws

def Laws.first_server_welcome_assigns_nickname():
  {==}

def Laws.later_welcome_cannot_replace_nickname():
  {==}

def Laws.rejected_welcome_preserves_live_state(acc, line, stamp):
  {==}

def Laws.refused_startup_archive_keeps_current_client(current, snapshot):
  {==}

def Laws.absent_startup_target_keeps_current_client(current, line):
  {==}

def Laws.held_recovery_has_no_wire_output():
  {==}

def Laws.completed_recovery_does_not_repeat():
  {==}

def Laws.old_authentication_cannot_release_recovery():
  {==}

def Laws.reset_keeps_key_revision_and_hold():
  {==}

def Laws.new_endpoint_discards_previous_channel_keys():
  {==}

def Laws.delayed_membership_echo_cannot_erase_intent():
  {==}

def Laws.server_time_invalid_calendar_is_rejected():
  {==}

def Laws.server_time_retains_complete_utc_event():
  {==}

def Laws.server_time_leap_second_is_preserved():
  {==}

def Laws.duplicate_server_time_is_invalid():
  {==}

def Laws.captured_image_preference_is_preserved(cl, images, channels):
  {==}

def Laws.raw_command_cannot_inject_line():
  {==}

def Laws.explicit_empty_topic_is_sent():
  {==}

def Laws.message_chunks_preserve_combining_cluster():
  {==}

def Laws.notice_credentials_do_not_enter_composer_history():
  {==}

def Laws.default_irc_transport_is_tls():
  {==}

def Laws.explicit_tls_keeps_plain_number_port():
  {==}

def Laws.plain_default_uses_legacy_port():
  {==}

def Laws.explicit_plain_keeps_secure_number_port():
  {==}

def Laws.tls_default_keeps_explicit_port(secure, port):
  {==}

def Laws.tls_default_uses_secure_port():
  {==}

def Laws.transport_selectors_cannot_conflict():
  {==}

def Laws.endpoint_keeps_original_host_identity():
  {==}

def Laws.endpoint_same_explicit_ports_agree():
  {==}

def Laws.endpoint_differing_explicit_ports_refuse():
  {==}

def Laws.endpoint_port_is_bounded():
  {==}

def Laws.endpoint_ipv6_is_not_supported():
  {==}

def Laws.unknown_command_is_not_implicit_upload(rest):
  {==}

def Laws.path_shaped_drop_still_requires_upload_consent():
  {==}

def Laws.upload_requires_physical_consent():
  {==}

def Laws.upload_worker_one_shot():
  {==}

def Laws.upload_cancel_retains_owner_not_permission():
  {==}

def Laws.upload_warning_precedes_authorization():
  {==}

def Laws.upload_invalid_local_uri_keeps_intent():
  {==}

def Laws.media_retained_payload_coherence():
  {==}

def Laws.dns_response_opcode_matches_query():
  {==}

def Laws.dns_truncation_after_question_validation():
  {==}

def Laws.cluster_width_matches_native():
  {==}

def Laws.cluster_vs16_wrap_boundary():
  {==}

def Laws.cluster_zwj_one_column_boundary():
  {==}

def Laws.cluster_regional_pair_with_extension():
  {==}

def Laws.synthetic_search_identity_canonical():
  {==}

def Laws.synthetic_preview_identity_canonical():
  {==}

def Laws.ordinary_query_spelling_preserved():
  {==}

def Laws.split_reserved_rename_rejected():
  {==}

def Laws.split_ordinary_rename_allowed():
  {==}

def Laws.server_query_seeded():
  {==}

def Laws.verb_keeps_extra_separators():
  {==}

def Laws.word_drops_separators():
  {==}

def Laws.protocol_scan_keeps_separators():
  {==}

def Laws.log_command_has_completion():
  {==}

def Laws.reader_eof_is_not_writer_completion():
  {==}

def Laws.stale_writer_completion_rejected():
  {==}

def Laws.current_writer_completion_accepted():
  {==}

def Laws.media_encoded_png():
  {==}

def Laws.media_query_not_extension():
  {==}

def Laws.media_code_opaque():
  {==}

def Laws.media_queue_capped():
  {==}

def Laws.media_reset_hides_old_active():
  {==}

def media_unsupported_no_request.eligible(eligible: Bool, +on: Bool, +target: Media.Target, +url: String) -> {Media.pending_count(Media.enqueue.eligible(eligible, Media.set_supported(Media.initial(on), False{}), target, url)) == 0n : Nat}:
  match eligible:
    case False{}: {==}
    case True{}: {==}

def Laws.media_unsupported_no_request(on, target, url):
  media_unsupported_no_request.eligible(Media.enqueue_allowed(Media.set_supported(Media.initial(on), False{}), target, url), on, target, url)

def Laws.media_unsupported_keeps_preference(on):
  {==}

def Laws.media_virtual_rows_resize():
  {==}

def Laws.media_virtual_rows_six():
  {==}

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

def Laws.tokenize_unclosed_source_order():
  {==}

def Laws.code_span_dim():
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

def Laws.sasl_plain_golden():
  {==}

def Laws.sasl_idle_no_reply(event, user, pass):
  {==}

def Laws.sasl_done_no_reply(event, user, pass):
  {==}

def Laws.auth_preserves_settings(cl, phase):
  match cl:
    case Cl.Client{nick, server, bufs, active, now, stg, auth, seq}:
      {==}

def Laws.nickserv_untrusted_probe_no_reply(cl):
  {==}

def Laws.nickserv_untrusted_confirmation_no_success():
  {==}

def Laws.nickserv_disabled_notice_untrusted(cl, prefix, msg):
  {==}

def Laws.auth_without_credentials_idle(config):
  {==}

def Laws.auth_phase_preserves_profile(before, after, config, seq):
  {==}

def Laws.auth_phase_preserves_success(before, after, config, seq):
  {==}

def Laws.timestamp_preserves_log_sequence(cl, ts):
  match cl:
    case Cl.Client{nick, server, bufs, active, now, stg, auth, seq}:
      {==}

def Laws.server_time_extract():
  {==}

def Laws.tab_completion_slash():
  {==}

def Laws.search_empty_line(kind, ts, text):
  {==}

def Laws.split_focus_involution(focus):
  match focus:
    case False{}: {==}
    case True{}: {==}

def Laws.split_control_key(cl):
  {==}

def Laws.split_control_lookup(cl):
  {==}

def Laws.split_server_query_lookup(cl):
  {==}

def Laws.preview_file_url():
  {==}

def Laws.typing_active_boundary():
  {==}

def Laws.typing_message_clear():
  {==}

def Laws.typing_stale_tick():
  {==}

def Laws.bell_mentions_advance():
  {==}

def Laws.active_clears_unread():
  {==}

def Laws.reconnect_endpoint():
  {==}

def Laws.disconnect_drop():
  {==}

def Laws.actor_zero_split(xs):
  {==}

def Laws.actor_exhausted_keeps_pending(xs):
  {==}

def Laws.narrow_cluster_source_count():
  {==}

def Laws.wide_cluster_source_count():
  {==}

def Laws.formatting_nested_bits():
  {==}

def Laws.formatting_escaped_literal():
  {==}

def Laws.formatting_code_identity():
  {==}

def Laws.formatting_alias_literals():
  {==}

def Laws.formatting_url_identity():
  {==}

def Laws.formatting_unmatched_double():
  {==}

def Laws.formatting_styled_url_identity():
  {==}

def Laws.diagnostic_opaque_urls_private():
  {==}

def Laws.diagnostic_credentials_private():
  {==}

def Laws.diagnostic_helper_private():
  {==}

def Laws.diagnostic_preserves_focus():
  {==}

def Laws.diagnostic_mirror_single_event():
  {==}

def Laws.diagnostic_log_command():
  {==}

def Laws.wire_control_prefixed_log_rejected():
  {==}

def Laws.wire_literal_log_rejected():
  {==}

def Laws.wire_normal_channel_allowed():
  {==}

def Laws.synthetic_msg_has_no_wire_output():
  {==}

def Laws.synthetic_query_has_no_wire_output():
  {==}

def Laws.normal_channel_msg_has_exact_wire_output():
  {==}

def Laws.dns_absolute_name_question():
  {==}

def Laws.explicit_nickname_preserved(nick, user):
  {==}

def Laws.nickname_without_sasl_user_preserved(nick):
  {==}

def Laws.implicit_nickname_uses_sasl_user():
  {==}

def Laws.channel_target_created_by_query_is_channel():
  {==}

def Laws.closing_focused_tab_clears_replacement_unread():
  {==}

def Laws.history_control_prefixed_log_rejected():
  {==}

def Laws.history_zero_cap_restores_no_targets():
  {==}

def Laws.prepared_message_echo_matches_wire():
  {==}

def Laws.same_endpoint_dial_preserves_reconnect_intent():
  {==}

def Laws.new_endpoint_dial_has_no_reconnect_intent(net):
  {==}

def Laws.dns_labels_do_not_alias_dotted_names():
  {==}

def Laws.dns_error_requires_matching_question():
  {==}

def Laws.view_style_boundaries_keep_clusters():
  {==}

def Laws.view_words_keep_clusters_and_source():
  {==}

def Laws.view_hidden_header_does_not_paint():
  {==}

def Laws.view_header_uses_columns():
  {==}

def Laws.view_prefix_fallback_preserves_text():
  {==}

def Laws.view_prefix_width_includes_joined_closer():
  {==}

def Laws.color_without_background_preserves_literal_comma():
  {==}

def Laws.status_audience_keeps_local_channel_identity():
  {==}

def Laws.local_channel_prefix_is_not_status_audience():
  {==}

def Laws.channel_creation_keeps_status_like_prefix():
  {==}

def Laws.resident_channel_wins_over_status_fallback():
  {==}

def Laws.stored_plus_channel_keeps_identity():
  {==}

def Laws.legacy_at_audience_restores_channel():
  {==}

def Laws.typing_membership_target_is_not_status_audience():
  {==}

def Laws.saved_single_label_hosts_can_reconnect():
  {==}

def Laws.unconfigured_demo_cannot_reconnect():
  {==}

def Laws.user_notice_prefix_is_not_server():
  {==}

def Laws.join_lists_accept_masked_channels():
  {==}

def Laws.join_lists_reject_nonchannel_targets():
  {==}

def Laws.image_switch_keeps_exact_argument_policy():
  {==}

def Laws.serverid_routing_rejects_invalid_and_stale():
  {==}

def Laws.serverid_isolation_keeps_exact_secrets():
  {==}

def Laws.serverid_generations_bound_ids():
  {==}

def Laws.ipv6_literal_valid():
  {==}

def Laws.ipv6_endpoint_format():
  {==}

def Laws.ipv6_dial_plan():
  {==}

def Laws.draft_store_roundtrip():
  {==}

def Laws.draft_missing_is_empty():
  {==}

def Laws.draft_rename_moves_text():
  {==}

def Laws.draft_overlong_text_rejected():
  {==}

def Laws.draft_lines_split_separators():
  {==}

def Laws.draft_single_line_routes_verbatim():
  {==}

def Laws.draft_multiline_plan_bounded():
  {==}

def Laws.draft_command_multiline_rejected():
  {==}

def Laws.draft_focus_stashes_and_loads():
  {==}

def Laws.draft_entries_match_buffer_slots():
  {==}

def Laws.draft_control_query_coexist():
  {==}

def Laws.cards_queue_capped():
  {==}

def Laws.cards_image_urls_excluded():
  {==}

def Laws.cards_page_urls_eligible():
  {==}

def Laws.cards_http_rejected():
  {==}

def Laws.cards_http_image_dropped():
  {==}

def Laws.cards_observe_ignores_unlisted_buffers():
  {==}

def Laws.cards_observe_schedules_visible_candidate():
  {==}

def Laws.cards_fullscreen_closes_when_unsupported():
  {==}

def Laws.cards_fullscreen_closes_on_eviction():
  {==}

def Laws.cards_code_opaque():
  {==}

def Laws.cards_payload_title_bounded():
  {==}

def Laws.cards_fullscreen_closed_without_token():
  {==}

def Laws.cards_fullscreen_zero_token_paints_nothing():
  {==}

def Laws.cap_end_single_owner():
  {==}

def Laws.caps_ack_only_enable():
  {==}

def Laws.notify_parse_golden():
  {==}

def Laws.notify_rejects_invalid():
  {==}

def Laws.typing_out_bounded_quiet():
  {==}

def Laws.typing_out_lifecycle():
  {==}

def Laws.typing_out_unseen_first_tick():
  {==}

def Laws.cap_source_validated():
  {==}

def Laws.theme_default_is_dark():
  {==}

def Laws.theme_dark_msg_preserved():
  {==}

def Laws.theme_dark_highlight_gold():
  {==}

def Laws.theme_dark_matches_view_style():
  {==}

def Laws.theme_mono_is_uniform():
  {==}

def Laws.theme_parse_light():
  {==}

def Laws.theme_parse_rejects_unknown():
  {==}

def Laws.theme_nick_default_preserved():
  {==}

def Laws.theme_light_status_ok():
  {==}

def Laws.emoji_table_has_seventy():
  {==}

def Laws.emoji_new_alias_resolves():
  {==}

def Laws.emoji_unknown_has_no_alias():
  {==}

def Laws.notify_disabled_is_silent():
  {==}

def Laws.notify_mention_requests():
  {==}

def Laws.notify_event_only_once():
  {==}

def Laws.notify_chatter_is_silent():
  {==}

def Laws.notify_old_id_is_silent():
  {==}

def Laws.notify_seed_covers_history():
  {==}

def Laws.notify_scope_isolated():
  {==}

def Laws.notify_title_redacts_author():
  {==}

def Laws.notify_title_strips_controls():
  {==}

def Laws.theme_status_dark_online():
  {==}

def Laws.theme_status_dark_offline():
  {==}

def Laws.theme_status_dark_connecting():
  {==}

def Laws.theme_status_dark_other():
  {==}

def Laws.theme_status_matches_view():
  {==}

def Laws.emoji_birc2_load_keeps_source():
  {==}

def Laws.emoji_production_renders_glyph():
  {==}
