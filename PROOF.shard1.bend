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
import ./src/bend/session_cards.bend as SessionCards
import ./src/bend/cards_view.bend as CardsView
import ./src/bend/workspace_isolation_proof.bend as WI
import ./LAWS.bend as Laws

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

def Laws.wire_toggle_twice_is_plain():
  {==}

def Laws.wire_reset_clears_style():
  {==}

def Laws.wire_visible_matches_sanitize():
  {==}

def Laws.wire_invalid_color_has_no_style():
  {==}

def Laws.wire_palette_red():
  {==}

def Laws.wire_controls_dropped():
  {==}

def Laws.wire_style_cannot_forge_link():
  {==}

def Laws.wire_soh_is_boundary():
  {==}

def Laws.wire_soh_cannot_forge_link():
  {==}

def Laws.wire_last_token_link_degrades():
  {==}

def Laws.wire_spaced_link_survives_style():
  {==}

def Laws.wire_keep_style_preserves_controls():
  {==}

def Laws.wire_keep_style_drops_tab():
  {==}

def Laws.wire_keep_visible_matches_sanitize():
  {==}

def Laws.wire_feed_preserves_style():
  {==}

def Laws.wire_history_preserves_style():
  {==}

def Laws.wire_verb_survives_style_byte():
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

