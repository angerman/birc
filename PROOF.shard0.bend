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

def Laws.first_server_welcome_assigns_nickname():
  {==}

def Laws.later_welcome_cannot_replace_nickname():
  {==}

def Laws.rejected_welcome_preserves_live_state(acc, line, stamp, welcomed):
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

