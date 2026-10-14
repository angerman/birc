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

def Laws.isupport_malformed_prefix_ignored():
  {==}

def Laws.isupport_prefix_rank_order():
  {==}

def Laws.isupport_default_strip_matches_roster():
  {==}

def Laws.isupport_unknown_mode_takes_arg():
  {==}

def Laws.isupport_precise_key_redaction():
  {==}

def Laws.isupport_uncertain_mode_hides_all():
  {==}

def Laws.isupport_ordinary_mode_renders():
  {==}

def Laws.isupport_peer_005_ignored():
  {==}

def Laws.isupport_server_005_applied():
  {==}

def Laws.isupport_join_admit_unupdated():
  {==}

def Laws.isupport_join_admit_server_bound():
  {==}

def Laws.isupport_neg_token_resets_default():
  {==}

def Laws.isupport_empty_statusmsg_clears():
  {==}

def Laws.isupport_wrong_recipient_ignored():
  {==}

def Laws.isupport_strip_keeps_interior_sigils():
  {==}

def Laws.isupport_advertised_chantypes_join():
  {==}

def Laws.isupport_duplicate_prefix_rejected():
  {==}

def Laws.isupport_chan_target_prefers_resident():
  {==}

def Laws.isupport_casemapping_ascii_strict():
  {==}

def Laws.isupport_324_redacts_key():
  {==}

def Laws.isupport_join_swap_rejects_log():
  {==}

def Laws.isupport_join_swap_rejects_log_upper():
  {==}

def Laws.isupport_neg_token_with_value_ignored():
  {==}

def Laws.isupport_neg_statusmsg_disables():
  {==}

def Laws.isupport_statusmsg_requires_prefix_subset():
  {==}

def Laws.isupport_statusmsg_subset_accepted():
  {==}

def Laws.isupport_chanmodes_withdrawal_uncertain():
  {==}

def Laws.isupport_chanmodes_withdrawal_hides_key():
  {==}

def Laws.isupport_chanmodes_known_precise():
  {==}

def Laws.isupport_lifecycle_stale_refused():
  {==}

def Laws.isupport_lifecycle_subset_accepted():
  {==}

def Laws.isupport_lifecycle_burst_order1_refuses():
  {==}

def Laws.isupport_lifecycle_burst_order2_refuses():
  {==}

def Laws.isupport_lifecycle_resident_preserved():
  {==}

def Laws.isupport_statusmsg_first_separate_stores():
  {==}

def Laws.isupport_statusmsg_first_separate_authorizes():
  {==}

def Laws.isupport_burst_hat_order1_authorizes():
  {==}

def Laws.isupport_burst_hat_order2_authorizes():
  {==}

def Laws.isupport_prefix_first_stale_refused():
  {==}

def Laws.isupport_malformed_statusmsg_keeps_empty():
  {==}

def Laws.isupport_withdrawn_invalid_stays_uncertain():
  {==}

def Laws.isupport_readvert_after_invalid_precise():
  {==}

def Laws.isupport_live_holds_defaults():
  {==}

def Laws.isupport_live_admit_gates():
  {==}

def Laws.isupport_live_endpoint_resets():
  {==}

def Laws.mode_maybe_key_flags_unsigned():
  {==}

def Laws.mode_maybe_key_rejects_monkey():
  {==}

def Laws.isupport_malformed_signed_hides():
  {==}

def Laws.mode_audience_key_detected():
  {==}

def Laws.mode_audience_key_agrees():
  {==}

def Laws.mode_maybe_key_rejects_user():
  {==}

def Laws.mode_raw_plus_channel_explicit():
  {==}

def Laws.mode_opaque_plus_channel_sensitive():
  {==}

def Laws.mode_explicit_plus_contrast():
  {==}

def Laws.isupport_unsigned_k_hidden():
  {==}

def Laws.session_redact_wire_hides_dollar():
  {==}

def Laws.session_redact_wire_keeps_ordinary():
  {==}

def Laws.flush_iso_drops_refused():
  {==}

def Laws.flush_iso_keeps_admitted():
  {==}

def Laws.session_outs_refuse_foreign():
  {==}

def Laws.session_outs_admit_own():
  {==}

def Laws.session_cm_eq_ascii_brackets():
  {==}

def Laws.session_chan_target_prefers_live_resident():
  {==}

def Laws.registration_iso_ascii_refuses():
  {==}

def Laws.fold_casemap_ascii():
  {==}

def Laws.fold_casemap_strict():
  {==}

def Laws.isupport_chanmodes_overlap_rejected():
  {==}

