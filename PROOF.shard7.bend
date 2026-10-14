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

def Laws.cards_adapter_endpoint_reset_closes_fullscreen():
  {==}

def Laws.cards_adapter_fullscreen_needs_live_token():
  {==}

def Laws.cards_adapter_key_step_preserves_wire():
  {==}

def Laws.cards_adapter_chunk_step_preserves_wire():
  {==}

def Laws.cards_view_overlay_revalidates_stale_token():
  {==}

def Laws.cards_adapter_exact_url_preserved():
  {==}

def Laws.cards_live_styled_infix_schedules_nothing():
  {==}

def Laws.cards_live_soh_prefix_schedules_nothing():
  {==}

def Laws.cards_live_ordinary_url_positive():
  {==}

def Laws.cards_live_media_soh_prefix_schedules_nothing():
  {==}

def Laws.cards_live_extract_shares_seam():
  {==}

def Laws.cards_live_bare_duplicate_kept():
  {==}

def Laws.cards_live_media_run_hit_image_intent():
  {==}

def Laws.cards_live_session_online_schedules_visible_page():
  {==}

def Laws.cards_live_session_disabled_schedules_nothing():
  {==}

def Laws.cards_live_session_exact_completion_accepted():
  {==}

def Laws.cards_live_session_stale_completion_rejected():
  {==}

def Laws.cards_live_stale_completion_stores_nothing():
  {==}

def Laws.cards_live_exact_completion_stores():
  {==}

def Laws.cards_live_dial_cards_resets_on_endpoint_change():
  {==}

def Laws.cards_live_dial_cards_retains_same_endpoint():
  {==}

def Laws.cards_live_dial_full_closes_on_change():
  {==}

def Laws.cards_live_reset_retains_active_worker():
  {==}

def Laws.cards_live_stale_keeps_worker():
  {==}

def Laws.cards_live_fullscreen_pick_newest_alive():
  {==}

def Laws.cards_live_fullscreen_open_live_token():
  {==}

def Laws.cards_live_f9_key_number():
  {==}

def Laws.cards_live_rows_cap_matches():
  {==}

def Laws.cards_live_empty_entries_match_baseline():
  {==}

def Laws.cards_live_ready_card_paints_rows():
  {==}

def Laws.cards_live_pending_never_paints():
  {==}

def Laws.chathistory_anchor_rejects_missing_ms():
  {==}

def Laws.chathistory_anchor_rejects_short_fraction():
  {==}

def Laws.chathistory_anchor_rejects_long_fraction():
  {==}

def Laws.chathistory_stamp_shape_accepts_millis():
  {==}

def Laws.history_ticket_advances():
  {==}

def Laws.history_page_admitted_live():
  {==}

def Laws.history_page_needs_cursor():
  {==}

def Laws.history_open_admitted_private():
  {==}

def Laws.history_open_rejects_symlink():
  {==}

def Laws.caps_chathistory_ack_enables():
  {==}

def Laws.caps_chathistory_nak_quiet():
  {==}

def Laws.chathistory_cap_shared_detection():
  {==}

def Laws.history_fetch_needs_connection():
  {==}

def Laws.history_search_needs_no_connection():
  {==}

def Laws.history_command_known():
  {==}

def Laws.history_import_seeds_log_seq():
  {==}

def Laws.proto_atom_strips_framing_styles():
  {==}

def Laws.proto_atom_matches_visible_on_soh():
  {==}

def Laws.styled_mode_flags_keep_key_private():
  {==}

def Laws.styled_mode_channel_keeps_key_private():
  {==}

def Laws.nonkey_mode_stays_visible():
  {==}

def Laws.styled_credential_author_suppressed():
  {==}

def Laws.infixed_credential_verb_suppressed():
  {==}

def Laws.peer_credential_stays_chat():
  {==}

def Laws.media_soh_scheme_has_no_target():
  {==}

def Laws.media_infixed_style_has_no_target():
  {==}

def Laws.media_styled_image_kept():
  {==}

def Laws.mention_styled_nick_hits():
  {==}

def Laws.mention_styled_continuation_misses():
  {==}

def Laws.mention_color_split_hits():
  {==}

def Laws.mention_reset_split_misses():
  {==}

def Laws.styled_self_kick_clears_intent():
  {==}

def Laws.styled_channel_kick_clears_client():
  {==}

def Laws.peer_kick_preserves_intent():
  {==}

def Laws.url_runs_share_view_exclusions():
  {==}
