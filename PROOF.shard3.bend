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

def Laws.draft_session_focus_gate_keeps_buffer_on_reject():
  {==}

def Laws.draft_session_split_gate_keeps_buffer_on_reject():
  {==}

def Laws.draft_session_endpoint_replace_clears_server():
  {==}

def Laws.draft_session_submit_clears_only_on_accept():
  {==}

def Laws.draft_session_multiline_submit_atomic():
  {==}

def Laws.draft_session_modal_stash_preserves_typed():
  {==}

def Laws.workspace_parts_isolate_state():
  WI.case_b_isolation()

def Laws.workspace_generations_drop_stale():
  {==}

def Laws.workspace_endpoint_replace_isolates():
  {==}

def Laws.draft_session_disconnected_multiline_holds():
  {==}

def Laws.draft_session_submit_focus_atomic():
  {==}

def Laws.draft_session_multiline_privacy_per_line():
  {==}

def Laws.draft_session_multiline_negotiated_mode_privacy():
  {==}

def Laws.draft_session_multiline_negotiated_implicit_privacy():
  {==}

def Laws.workspace_epoch_reuse_rejects_stale():
  {==}

def Laws.workspace_composer_reset_on_replace():
  {==}

def Laws.session_supplied_submit_completes_once():
  {==}

def Laws.workspace_runtime_applies_routed_inbound():
  {==}

def Laws.workspace_redial_emits_scoped_dial():
  {==}

def Laws.cards_queue_capped():
  {==}

def Laws.cards_image_urls_excluded():
  {==}

def Laws.cards_page_urls_eligible():
  {==}

def Laws.cards_http_rejected():
  {==}

