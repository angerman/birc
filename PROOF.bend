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

def Laws.push_rem_nil():
  {==}

def Laws.push_rem_crlf():
  {==}

def Laws.parse_id_short():
  {==}

def Laws.parse_id_bad():
  {==}

# P8 quantified attempts (2026-09-22). Kept as comments with checker output.
#
# law push_rem_bound:
#   for xs: List<&2, U32>
#   {Fr.push_rem_le(xs) == True{} : Bool}
# Proof by match xs / IH on t:
# Error:
# - expected : {Cmp.is_le(Nat.cmp(src/bend/frame.rem_len(src/bend/frame.push.pair(src/bend/frame.push.go(Nat.add(List.length(&2, U32, t), 1n+Nat.add(List.length(&2, U32, t), 1n+Nat.add(List.length(&2, U32, t), 1n+Nat.add(List.length(&2, U32, t), 0n)))), src/bend/frame.PAct{}, t, [], [], 0n, _, Cmp.is_eq(U32.cmp(_, 10)), Cmp.is_eq(U32.cmp(_, 13)), False{}))), 510n)) == True{} : Bool}
# - observed : {Cmp.is_le(Nat.cmp(src/bend/frame.rem_len(src/bend/frame.push.pair(src/bend/frame.push.go(1n+Nat.add(List.length(&2, U32, t), Nat.add(List.length(&2, U32, t), Nat.add(List.length(&2, U32, t), Nat.add(List.length(&2, U32, t), 0n)))), src/bend/frame.PRead{}, t, [], [], 0n, 0, False{}, False{}, False{}))), 510n)) == True{} : Bool}
# Context:
# - _ : U32
# - t : List<&2, U32>
# Location: LAWS.push_rem_bound
# The IH is push.go(PRead, empty rem) on the tail; the step is push.go(PAct)
# with the head byte. A phase-indexed invariant is out of reach here.
#
# law parse_id_mismatch:
#   for want: U32
#   for xs: List<&2, U32>
#   {Wire.parse_id_mismatch_ok(want, xs) == True{} : Bool}
# Not reached: push_rem_bound failed first. parse_id goes through parse_hdr
# / hdr_chks; a Client-universal nbuf cap has the same shape of blocker.

def Laws.live_fuel_small():
  {==}
