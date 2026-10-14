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

def Laws.g6_live_reg_binding():
  {==}

def Laws.g6_live_tick_binding():
  {==}

def Laws.g6_live_tick_cm_alias():
  {==}

def Laws.g6_live_tick_cm_throttle():
  {==}

def Laws.g6_live_merge_owner():
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

def Laws.notify_full_table_rejects_unknown():
  {==}

def Laws.notify_cross_scope_replay_is_silent():
  {==}

def Laws.notify_retained_scope_fresh_id_notifies():
  {==}

def Laws.notify_table_stays_bounded():
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

def Laws.theme_dark_self_preserved():
  {==}

def Laws.theme_dark_system_preserved():
  {==}

def Laws.theme_dark_action_preserved():
  {==}

def Laws.theme_dark_notice_preserved():
  {==}

def Laws.theme_dark_error_preserved():
  {==}

def Laws.theme_dark_reconnect_preserved():
  {==}

def Laws.theme_dark_linkresult_preserved():
  {==}

def Laws.theme_nick_row_zero_fixed():
  {==}

def Laws.theme_nick_default_arm_fixed():
  {==}

def Laws.theme_status_matches_view_online():
  {==}

def Laws.theme_status_matches_view_offline():
  {==}

def Laws.theme_status_matches_view_other():
  {==}

def Laws.emoji_birc2_load_keeps_source():
  {==}

def Laws.emoji_production_renders_glyph():
  {==}

def Laws.isupport_defaults_golden():
  {==}

