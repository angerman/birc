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

def Laws.isupport_overlap_withdrawn_stays_uncertain():
  {==}

def Laws.isupport_overlap_hides_all():
  {==}

def Laws.isupport_valid_limit_key_precise():
  {==}

def Laws.mode_dollar_key_negotiated_sensitive():
  {==}

def Laws.mode_dollar_long_key_negotiated_sensitive():
  {==}

def Laws.mode_dollar_ordinary_recallable():
  {==}

def Laws.mode_sensitive_target_agrees_audience():
  {==}

def Laws.mode_styled_target_suppressed():
  {==}

def Laws.mode_styled_target_wire_rejected():
  {==}

def Laws.mode_ordinary_explicit_recallable():
  {==}

def Laws.typing_out_observed_sentinel():
  {==}

def Laws.disk_search_rejects_empty_query():
  {==}

def Laws.disk_search_target_prefix():
  {==}

def Laws.disk_search_cursor_is_oldest_offset():
  {==}

def Laws.disk_import_preserves_log_seq():
  {==}

def Laws.chathistory_cap_detected():
  {==}

def Laws.chathistory_cap_absent():
  {==}

def Laws.chathistory_latest_needs_negotiation():
  {==}

def Laws.chathistory_latest_valid():
  {==}

def Laws.chathistory_rejects_synthetic_target():
  {==}

def Laws.history_cursor_initial_fetch_is_latest():
  {==}

def Laws.chathistory_batch_opens_on_valid_line():
  {==}

def Laws.chathistory_batch_ignores_foreign_target():
  {==}

def Laws.chathistory_batch_requires_batch_tag():
  {==}

def Laws.chathistory_batch_accepts_matching_tag():
  {==}

def Laws.history_cursor_before_moves_oldest_only():
  {==}

def Laws.history_cursor_after_moves_newest_only():
  {==}

def Laws.disk_scan_eof_truncated():
  {==}

def Laws.disk_scan_eof_complete():
  {==}

def Laws.chathistory_cap_accepts_server_self():
  {==}

def Laws.chathistory_cap_rejects_user_prefix():
  {==}

def Laws.chathistory_cap_rejects_wrong_recipient():
  {==}

def Laws.chathistory_before_prefixes_msgid():
  {==}

def Laws.chathistory_anchor_rejects_malformed():
  {==}

def Laws.chathistory_between_prefixes_both():
  {==}

def Laws.chathistory_batch_open_rejects_user_prefix():
  {==}

def Laws.chathistory_private_rejects_third_party():
  {==}

def Laws.chathistory_private_accepts_subject():
  {==}

def Laws.history_filter_dedups_within_batch():
  {==}

def Laws.history_search_completion_admitted():
  {==}

def Laws.history_search_completion_rejects_stale_gen():
  {==}

def Laws.search_emit_spawns_worker():
  {==}

def Laws.pong_emit_stays_quiet():
  {==}

def Laws.disk_file_admitted_private():
  {==}

def Laws.disk_file_rejects_symlink():
  {==}

def Laws.chat_negotiation_resets_on_endpoint_move():
  {==}

def Laws.disk_search_needs_preference():
  {==}

def Laws.history_fetch_older_opaque_stamp_stays_msgid():
  {==}

def Laws.history_fetch_older_equals_stays_msgid():
  {==}

def Laws.chathistory_explicit_msgid_accepts_equals():
  {==}

def Laws.chathistory_around_accepts_explicit_stamp():
  {==}

def Laws.history_filter_keeps_saved_tail_under_cap():
  {==}

def Laws.chathistory_before_accepts_millis_stamp():
  {==}

def Laws.chathistory_explicit_stamp_accepts_millis():
  {==}

def Laws.chathistory_anchor_rejects_bad_stamp_date():
  {==}

def Laws.chathistory_explicit_stamp_rejects_bad_shape():
  {==}

def Laws.chathistory_cap_accepts_prereg_star():
  {==}

def Laws.chathistory_cap_rejects_star_when_registered():
  {==}

def Laws.chathistory_cap_rejects_wrong_recipient_prereg():
  {==}

def Laws.cards_adapter_demo_schedules_nothing():
  {==}

def Laws.cards_adapter_stopping_schedules_nothing():
  {==}

def Laws.cards_adapter_online_schedules_visible_page():
  {==}

def Laws.cards_adapter_disabled_schedules_nothing():
  {==}

def Laws.cards_adapter_exact_completion_accepted():
  {==}

def Laws.cards_adapter_wrong_ticket_rejected():
  {==}

def Laws.cards_adapter_stale_completion_stores_nothing():
  {==}

def Laws.cards_adapter_endpoint_reset_drops_queue():
  {==}

