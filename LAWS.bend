# Protocol + client laws. The human states them; PROOF.bend must prove them.
import Base
import ./src/bend/irc.bend as Irc
import ./src/bend/buffer.bend as Cl
import ./src/bend/client.bend as Feed
import ./src/bend/client_laws.bend as CL
import ./src/bend/submit.bend as Sub
import ./src/bend/frame.bend as Fr
import ./src/bend/view.bend as V
import ./src/bend/view_laws.bend as VL
import ./src/bend/session.bend as Sess
import ./src/bend/clock_fmt.bend as Clock
import ./src/bend/dns_wire.bend as Wire
import ./src/bend/base64.bend as B64
import ./src/bend/split.bend as Sp
import ./src/bend/typing.bend as Ty
import ./src/bend/auth.bend as Auth
import ./src/bend/outbound.bend as Act
import ./src/bend/diagnostic.bend as Diagnostic
import ./src/bend/media.bend as Media
import ./src/bend/args.bend as Args
import ./src/bend/history.bend as Hist
import ./tests/bend/m20_media_preds.bend as MediaReview
import ./tests/bend/dns_validation_preds.bend as DnsValidation
import ./src/bend/columns.bend as Columns

law media_retained_payload_coherence:
  {MediaReview.coherence_ok() == True{} : Bool}

law dns_response_opcode_matches_query:
  {DnsValidation.opcode_ok() == True{} : Bool}

law dns_truncation_after_question_validation:
  {DnsValidation.truncated_validation_ok() == True{} : Bool}

law cluster_width_matches_native:
  {Columns.text_width("👩‍💻❤️🇰") == 6 : U32}

law cluster_vs16_wrap_boundary:
  {Columns.take("❤️x", 2) == Columns.Cut{"❤️", "x", 2} : Columns.Cut}

law cluster_zwj_one_column_boundary:
  {Columns.take("👩‍💻x", 1) == Columns.Cut{"", "👩‍💻x", 0} : Columns.Cut}

law cluster_regional_pair_with_extension:
  {Columns.cluster("🇰́🇷x") == Columns.Cut{"🇰́🇷", "x", 2} : Columns.Cut}

law synthetic_search_identity_canonical:
  {Cl.target_name("*SEARCH*") == "*search*" : String}

law synthetic_preview_identity_canonical:
  {Cl.target_name("*PREVIEW*") == "*preview*" : String}

law ordinary_query_spelling_preserved:
  {Cl.target_name("ALIce") == "ALIce" : String}

law split_reserved_rename_rejected:
  {Cl.nick_rename_allowed("alice", "*server*") == False{} : Bool}

law split_ordinary_rename_allowed:
  {Cl.nick_rename_allowed("alice", "bob") == True{} : Bool}

law server_query_seeded:
  {Cl.empty_buf("server", False{}) == Cl.Buffer{"server", False{}, "", Nil{}, "server" <> Nil{}, Cl.ScrollAt{0n, 0n}} : Cl.Buffer}

law verb_keeps_extra_separators:
  {Sub.take_verb("cmd   rest") == ("cmd", "  rest") : String & String}

law word_drops_separators:
  {Sub.take_word("cmd   rest") == ("cmd", "rest") : String & String}

law protocol_scan_keeps_separators:
  {Irc.take_until_space("cmd   rest") == ("cmd", "   rest") : String & String}

law log_command_has_completion:
  {Sess.comp_candidates(Cl.init("me", "s"), "/lo") == "/log" <> Nil{} : List<&2, String>}

law reader_eof_is_not_writer_completion:
  {Sess.writer_done_current(Sess.FromNet{1, Sess.Eof{}}, 1) == False{} : Bool}

law stale_writer_completion_rejected:
  {Sess.writer_done_current(Sess.FromNet{0, Sess.WriterDone{}}, 1) == False{} : Bool}

law current_writer_completion_accepted:
  {Sess.writer_done_current(Sess.FromNet{1, Sess.WriterDone{}}, 1) == True{} : Bool}

# Media is view-only, bounded and exact-identity scheduled.
law media_encoded_png:
  {Media.auto_url("https://example.test/Screenshot%202026.png?q=exact#part") == True{} : Bool}

law media_query_not_extension:
  {Media.auto_url("https://example.test/raw?image=a.png") == False{} : Bool}

law media_code_opaque:
  {List.is_empty(&2, String, Media.targets("`https://example.test/a.png`")) == True{} : Bool}

law media_queue_capped:
  {Media.pending_count(Media.enqueue_urls(["http://x/1.png", "http://x/2.png", "http://x/3.png", "http://x/4.png", "http://x/5.png", "http://x/6.png", "http://x/7.png", "http://x/8.png", "http://x/9.png"], Media.initial(True{}), Media.Inline{1n})) == 8n : Nat}

law media_reset_hides_old_active:
  {List.is_empty(&2, String, Media.known_urls(Media.reset(Media.State{True{}, 1n, 2n, Some{Media.Request{Media.Inline{1n}, "http://x/a.png", 1n, 1n}}, Nil{}, Nil{}}), Media.Inline{1n})) == True{} : Bool}

law media_virtual_rows_resize:
  {Nat.is_eq(V.rows_chars(V.media_rows(7, 1)), V.rows_chars(V.media_rows(7, 80))) == True{} : Bool}

law media_virtual_rows_six:
  {V.rows_chars(V.media_rows(7, 80)) == 6n : Nat}

# LAW: a concrete PING line is classified as Ping.
law ping_classified:
  {Irc.is_ping_line("PING :irc.example.net") == True{} : Bool}

# LAW: PING with a token auto-replies as PONG :<token>.
law pong_concrete:
  {Irc.pong_for("PING :irc.example.net") == "PONG :irc.example.net" : String}

# LAW: case-insensitive verb match treats PiNg as PING.
law ping_casefold:
  {Irc.is_ping_line("PiNg :xyz") == True{} : Bool}

# LAW: '#' introduces a channel name.
law hash_is_channel:
  {Irc.starts_channel("#birc") == True{} : Bool}

# LAW: a bare nick is not a channel.
law nick_not_channel:
  {Irc.starts_channel("alice") == False{} : Bool}

# LAW: empty input is not a channel.
law empty_not_channel:
  {Irc.starts_channel("") == False{} : Bool}

# LAW: clamp of the empty string is within LINE_MAX.
law clamp_empty_ok:
  {Irc.line_ok(Irc.clamp_line("")) == True{} : Bool}

# LAW: clamp samples (empty, short, 80, 600) are line_ok. Quantified
# `for s: String` needs a proof term; `{==}` is not enough (T1).
law clamp_samples:
  {Irc.clamp_samples_ok() == True{} : Bool}

# LAW: strip_ctl drops CR and LF on a mixed sample.
law strip_ctl_nocr:
  {Irc.strip_ctl_nocr_ok() == True{} : Bool}

# LAW: strip_ctl never leaves CR or LF, for every string.
law strip_ctl_clean:
  for s: String
  {Irc.has_crlf(Irc.strip_ctl(s)) == False{} : Bool}

# LAW: ASCII case-insensitive equality agrees on PING/ping.
law ieq_ping:
  {Irc.ieq("PING", "ping") == True{} : Bool}

# LAW: feed on empty line preserves buffer count.
law feed_empty_id:
  {CL.feed_id(Cl.init("me", "irc.birc.dev"), "") == True{} : Bool}

# LAW: PING does not change buffer count.
law feed_ping_nbuf:
  {Nat.is_eq(CL.nbuf(Cl.init("me", "s")), CL.nbuf(Feed.feed(Cl.init("me", "s"), "PING :x"))) == True{} : Bool}

# LAW: submit outbound lines satisfy line_ok.
law submit_line_ok:
  {Sub.submit_ok(Cl.init("me", "s"), "/quit") == True{} : Bool}

# LAW: empty submit is ok (no outbound).
law submit_empty_ok:
  {Sub.submit_ok(Cl.init("me", "s"), "") == True{} : Bool}

# LAW: CRLF framer roundtrip for two lines + tail remainder.
law framer_roundtrip:
  {Fr.roundtrip_ok("a" <> "b" <> Nil{}, Fr.string_to_octets("tail")) == True{} : Bool}

# LAW: concrete scroll clamp sample stays within bounds (100, 10, 5).
law scroll_bounds:
  {VL.scroll_bounds_ok(100n, 10n, 5n) == True{} : Bool}

# LAW: body height is rows minus five chrome rows (tabs, borders,
# status, composer), with a floor of 1. Layout is Bend DrawOp; C does not cap rows.
law body_h_fits:
  {Sess.body_h_ok() == True{} : Bool}


# LAW: M5.3 tokenize roundtrips *bold* markup.
law tokenize_bold:
  {V.tokenize_roundtrip("hello *bold* text") == True{} : Bool}

# LAW: *bold* is a Bold span, not an identity echo.
law tokenize_has_bold:
  {V.tokenize_has_bold("hello *bold* text") == True{} : Bool}

# LAW: _em_ is an Italic span.
law tokenize_has_italic:
  {V.tokenize_has_italic("_em_") == True{} : Bool}

# LAW: `code` is a Code span.
law tokenize_has_code:
  {V.tokenize_has_code("`code`") == True{} : Bool}

# LAW: https URL becomes a Link span.
law tokenize_has_link:
  {V.tokenize_has_link("see https://timui.dev x") == True{} : Bool}

# LAW: unclosed *foo stays plain (no Bold).
law tokenize_unclosed:
  {V.unclosed_star_plain() == True{} : Bool}

# LAW: unmatched markup remains plain with the opener in its source position.
law tokenize_unclosed_source_order:
  {V.tokenize_roundtrip("*foo") && V.tokenize_roundtrip("_foo") && V.tokenize_roundtrip("`foo") == True{} : Bool}

# LAW: the live operation for inline code retains the dim attribute.
law code_span_dim:
  {V.span_op(V.Code{"code"}) == V.Spn{2, "code"} : V.SpanOp}

# LAW: M7.2 overlong framer input yields no lines.
law overlong_drop:
  {Fr.overlong_drop_ok() == True{} : Bool}

# LAW: M7.2 JOIN flood past MAX_BUFFERS stays capped.
law flood_buffers:
  {CL.flood_buffers_capped() == True{} : Bool}

# LAW: the 24-JOIN sample adds rejection diagnostics to the server buffer.
law flood_server_clean:
  {CL.flood_server_clean() == True{} : Bool}

# LAW: NOTICE * is a server broadcast (no extra query buffer).
law notice_star_server:
  {CL.notice_star_server() == True{} : Bool}

# LAW: PRIVMSG to our nick opens a query buffer.
law privmsg_query_opens:
  {CL.privmsg_query_opens() == True{} : Bool}

# LAW: 001 lands on the server buffer.
law welcome_server_line:
  {CL.welcome_server_line() == True{} : Bool}

# LAW: RFC 1459 353 puts nicks on the channel, not a bogus buffer.
law names_1459:
  {CL.names_1459_ok() == True{} : Bool}

# LAW: self KICK drops the channel buffer.
law kick_self_drops:
  {CL.kick_self_drops() == True{} : Bool}

# LAW: buffer log stays oldest-to-newest (take_last must not reverse).
law log_chrono:
  {CL.log_chrono_ok() == True{} : Bool}

# LAW: Shift+Right wraps the active buffer.
law cycle_tab:
  {CL.cycle_ok() == True{} : Bool}

# LAW: Self and Msg use different paint colours.
law style_self_ne_msg:
  {VL.style_self_ne_msg() == True{} : Bool}

# LAW: timestamp column is 8 cells (HH:MM:SS + space).
law ts_width_ok:
  {VL.ts_width_ok() == True{} : Bool}

# LAW: visible window is oldest-to-newest.
law vis_chrono:
  {VL.vis_chrono_ok() == True{} : Bool}

# LAW: body-line y values increase, end on the last inner row, count = vis_h.
law body_ys_ok:
  {VL.body_ys_ok() == True{} : Bool}

# LAW: demo/online net labels.
law net_demo_ok:
  {Sess.net_demo_ok() == True{} : Bool}

# LAW: page-up adds to buffer scroll.
law scroll_page:
  {CL.scroll_page_ok() == True{} : Bool}

# LAW: submit snaps scroll to newest.
law snap_scroll:
  {CL.snap_ok() == True{} : Bool}

# LAW: composer history caps at 64, oldest dropped first.
law hist_cap:
  {Sess.hist_cap_ok() == True{} : Bool}

# LAW: /quit is a halt command; plain text is not.
law submit_halt:
  {Sub.submit_halt_ok() == True{} : Bool}

# LAW: /connect host port parses.
law connect_parse:
  {Sub.connect_parse_ok() == True{} : Bool}

# LAW: /connect from demo yields Dial; online is a no-op Cont.
law connect_dial:
  {Sess.cmd_connect_ok() == True{} : Bool}

# LAW: HH:MM:SS pad is two digits.
law fmt_hms_ok:
  {Clock.fmt_hms_ok() == True{} : Bool}

# LAW: buf_log_ts stores ts at log time; later lines do not rewrite earlier ts.
law log_ts_ok:
  {CL.log_ts_ok() == True{} : Bool}

# LAW: live string framer drops overlong lines (same cap as octet push).
law overlong_text_drop:
  {Fr.overlong_text_drop_ok() == True{} : Bool}

# LAW: a CR flood cannot grow the remainder past 510.
law cr_flood_cap:
  {Fr.cr_flood_ok() == True{} : Bool}

# LAW: a bare CR drops that line; the next CRLF line still parses.
law bare_cr_drop:
  {Fr.bare_cr_drop_ok() == True{} : Bool}

# LAW: 510 payload + CRLF is a legal IRC line.
law legal_max_line:
  {Fr.legal_max_ok() == True{} : Bool}

# LAW: 509 payload + CRLF still frames.
law legal_509_line:
  {Fr.legal_509_ok() == True{} : Bool}

# LAW: short CRLF text still frames.
law short_text_ok:
  {Fr.short_text_ok() == True{} : Bool}

# LAW: 510 payload octets stay in rem (at LINE_OCTET_MAX).
law push_rem_510:
  {Fr.rem510_ok() == True{} : Bool}

# LAW: 510 'a' + CR at a chunk boundary is held at LINE_OCTET_MAX+1.
law push_rem_511:
  {Fr.rem511_ok() == True{} : Bool}

# LAW: for every chunk, the remainder of push(Nil, chunk) has length
# at most LINE_OCTET_MAX+1. A CR held at a chunk boundary is the +1.
law push_rem_bound:
  for xs: List<&2, U32>
  {Fr.push_rem_le(xs) == True{} : Bool}

# LAW: parse_id on a short packet is not Done.
law parse_id_short:
  {Wire.parse_id_mismatch_ok(1, Nil{}) == True{} : Bool}

# LAW: parse_id is not Done on a full packet whose id is 2 and want is 1.
law parse_id_bad:
  {Wire.parse_id_mismatch_ok(1, Wire.sample_bad_id()) == True{} : Bool}

# LAW: --frames 3 is 3 live ticks (one event each).
law live_fuel_small:
  {Nat.is_eq(Sess.live_fuel(3), 3n) == True{} : Bool}

# LAW: a zero split keeps every pending line, for any queue.
law actor_zero_split:
  for xs: List<&2, String>
  {Act.split_at(xs, 0n) == (Nil{}, xs) : List<&2, String> & List<&2, String>}

# LAW: an exhausted writer neither emits nor discards pending lines.
law actor_exhausted_keeps_pending:
  for xs: List<&2, String>
  {Act.batch(xs, Act.Limited{0, 0}) == Act.Batch{Nil{}, xs, Act.Limited{0, 0}} : Act.Batch}

# LAW: this multi-codepoint cluster keeps its source length when a one-column
# pane substitutes a single visible glyph. This is a concrete regression law.
law narrow_cluster_source_count:
  {V.rows_chars(V.wrap_line(Cl.Line{Cl.Msg{}, "", "👩‍💻x", "", 0n}, 1, False{})) == 4n : Nat}

# LAW: widening the same concrete line preserves its source length.
law wide_cluster_source_count:
  {V.rows_chars(V.wrap_line(Cl.Line{Cl.Msg{}, "", "👩‍💻x", "", 0n}, 4, False{})) == 4n : Nat}

# LAW: SASL PLAIN Base64 encoding matches standard test vectors.
law sasl_plain_golden:
  {B64.sasl_plain_ok() == True{} : Bool}

# LAW: any control event is inert when credentials are disabled.
law sasl_idle_no_reply:
  for event: Irc.SaslEvent
  for user: String
  for pass: String
  {Auth.step(Cl.AuthIdle{}, event, user, pass) == Auth.unchanged(Cl.AuthIdle{}) : Auth.Reply}

# LAW: completed authentication cannot restart or release credentials again.
law sasl_done_no_reply:
  for event: Irc.SaslEvent
  for user: String
  for pass: String
  {Auth.step(Cl.AuthDone{}, event, user, pass) == Auth.unchanged(Cl.AuthDone{}) : Auth.Reply}

# LAW: changing authentication phase preserves configuration and alert state.
law auth_preserves_settings:
  for cl: Cl.Client
  for phase: Cl.AuthPhase
  {Cl.get_settings(Cl.set_auth(cl, phase)) == Cl.get_settings(cl) : Cl.Settings}

# LAW: applying an IO timestamp cannot reuse or reset a log event ID.
law timestamp_preserves_log_sequence:
  for cl: Cl.Client
  for ts: String
  {Cl.log_seq_of(Cl.set_now(cl, ts)) == Cl.log_seq_of(cl) : Nat}

# LAW: server-time extracts HH:MM:SS from ISO-8601 message tags.
law server_time_extract:
  {Irc.server_time_sample_ok() == True{} : Bool}

# LAW: Tab on slash command prefix completes to command with trailing space.
law tab_completion_slash:
  {Sess.comp_step_ok() == True{} : Bool}

# LAW: an empty search query never matches a scrollback line.
law search_empty_line:
  for kind: Cl.LineKind
  for ts: String
  for text: String
  {Feed.line_matches_query(Cl.Line{kind, ts, text, "", 0n}, "") == False{} : Bool}

# LAW: toggling focus twice restores either valid pane focus.
law split_focus_involution:
  for focus: Bool
  {Sp.focus_twice_ok(focus) == True{} : Bool}

# LAW: the control pane's internal key is independent of every query name.
law split_control_key:
  for cl: Cl.Client
  {Sp.name_at(cl, 0n) == "*server*" : String}

law split_control_lookup:
  for cl: Cl.Client
  {Sp.named_idx(cl, "*server*") == Some{0n} : Maybe<&2, Nat>}

law split_server_query_lookup:
  for cl: Cl.Client
  {Sp.named_idx(cl, "server") == Cl.buf_find(cl, "server") : Maybe<&2, Nat>}

# LAW: file:// preview URLs become local filesystem paths in Bend.
law preview_file_url:
  {Sub.preview_file_url_ok() == True{} : Bool}

# LAW: an active typing notice is present before 6 s and absent at 6 s.
law typing_active_boundary:
  {Ty.active_boundary_ok() == True{} : Bool}

# LAW: a received message, with or without tags, clears typing even when
# scrollback policy is separate.
law typing_message_clear:
  {Ty.message_clear_ok() == True{} : Bool}

# LAW: an older timer tick cannot expire a newer typing event.
law typing_stale_tick:
  {Ty.stale_tick_ok() == True{} : Bool}

# LAW: each received mention advances the bell event sequence; ordinary
# messages do not.
law bell_mentions_advance:
  {CL.bell_mentions_advance_ok() == True{} : Bool}

# LAW: selecting an alerted buffer clears its ordinary and highlight unread
# state.
law active_clears_unread:
  {CL.active_clears_unread_ok() == True{} : Bool}

# LAW: automatic reconnect preserves the selected server endpoint.
law reconnect_endpoint:
  {Sess.reconnect_endpoint_ok() == True{} : Bool}

# LAW: reconnect-off disconnects explicitly release the network actor socket.
law disconnect_drop:
  {Sess.disconnect_drop_ok() == True{} : Bool}

# LAW: double bold and nested italic compose independent attribute bits.
law formatting_nested_bits:
  {V.span_ops(V.tokenize("**B _BI_ B**")) == [V.Spn{1, "B "}, V.Spn{5, "BI"}, V.Spn{1, " B"}] : List<&2, V.SpanOp>}

# LAW: escaped markers remain literal, without becoming style delimiters.
law formatting_escaped_literal:
  {V.span_ops(V.tokenize("\\*literal\\*")) == [V.Spn{0, "*literal*"}] : List<&2, V.SpanOp>}

# LAW: bold + opaque dim code is not interpreted as a URL tag.
law formatting_code_identity:
  {V.span_ops(V.tokenize("*`:eyes:`*")) == [V.Spn{3, ":eyes:"}] : List<&2, V.SpanOp>}

# LAW: aliases are view-only and case sensitive; unknown names remain literal.
law formatting_alias_literals:
  {V.span_ops(V.tokenize(":eyes: :Eyes: :unknown:")) == [V.Spn{0, "👀 :Eyes: :unknown:"}] : List<&2, V.SpanOp>}

# LAW: alias-like and markup-like URL bytes remain exact and opaque.
law formatting_url_identity:
  {V.span_ops(V.tokenize("https://x.test/a_b/:eyes:?q=**z**,")) == [V.Lnk{"https://x.test/a_b/:eyes:?q=**z**", "https://x.test/a_b/:eyes:?q=**z**"}, V.Spn{0, ","}] : List<&2, V.SpanOp>}

# LAW: a greedy unmatched double opener retains both source characters.
law formatting_unmatched_double:
  {V.span_ops(V.tokenize("**one*")) == [V.Spn{0, "**one*"}] : List<&2, V.SpanOp>}

# LAW: nested style closers do not split or rewrite a URL's internal bytes.
law formatting_styled_url_identity:
  {V.span_ops(V.tokenize("_**https://x.test/a_b/:eyes:**_")) == [V.Spn{5, "https://x.test/a_b/:eyes:"}] : List<&2, V.SpanOp>}

# LAW: diagnostic copies redact URLs inside opaque code and styled text.
law diagnostic_opaque_urls_private:
  {Bool.not(String.contains(Diagnostic.text("_https://x.invalid/a_ `https://x.invalid/b`", "", ""), "x.invalid")) == True{} : Bool}

# LAW: configured secrets are redacted before truncation, even inside code.
law diagnostic_credentials_private:
  {Diagnostic.text("`secret`", "", "secret") == "`[redacted]`" : String}

# LAW: helpers report only caller-owned labels and numeric codes.
law diagnostic_helper_private:
  {Diagnostic.process_result("clipboard", Fail{(2, "private secret")}) == Some{"clipboard failed (OS 2)"} : Maybe<&2, String>}

# LAW: app-session diagnostics are lazy and do not steal chat focus.
law diagnostic_preserves_focus:
  {Cl.active_of(Cl.diagnostic(Cl.init("me", "s"), Cl.System{}, "connected")) == 0n : Nat}

# LAW: a diagnostic copy uses the original event ID rather than a new event.
law diagnostic_mirror_single_event:
  {Cl.log_seq_of(Cl.client_log(Cl.init("me", "s"), 0n, Cl.Error{}, "failed")) == 1n : Nat}

# LAW: /log focuses its canonical internal buffer without IRC output.
law diagnostic_log_command:
  {Sub.submit(Cl.init("me", "s"), "/log") == (Cl.log_open(Cl.init("me", "s")), Nil{}) : Cl.Client & List<&2, String>}

# Fresh review: identity policy is applied after incoming-name normalization.
law wire_control_prefixed_log_rejected:
  {Feed.wire_name(SCon{Chr{31}, "*log*"}) == False{} : Bool}

law wire_literal_log_rejected:
  {Feed.wire_name("*log*") == False{} : Bool}

law wire_normal_channel_allowed:
  {Feed.wire_name("#room") == True{} : Bool}

# Every send entry point shares the local synthetic-target boundary.
law synthetic_msg_has_no_wire_output:
  {Pair.snd(Cl.Client, List<&2, String>, Sub.submit(Cl.init("me", "s"), "/msg *search* text")) == Nil{} : List<&2, String>}

law synthetic_query_has_no_wire_output:
  {Pair.snd(Cl.Client, List<&2, String>, Sub.submit(Cl.init("me", "s"), "/query *settings* text")) == Nil{} : List<&2, String>}

law normal_channel_msg_has_exact_wire_output:
  {Pair.snd(Cl.Client, List<&2, String>, Sub.submit(Cl.init("me", "s"), "/msg #room text")) == ["PRIVMSG #room :text"] : List<&2, String>}

# An absolute DNS name has the same question bytes as its root-relative form.
law dns_absolute_name_question:
  {Wire.encode_edns("a.example.") == Wire.encode_edns("a.example") : Result<&1, &1, U32 & String, List<&2, U32>>}

# Explicitness is configuration state, never inferred from the nickname value.
law explicit_nickname_preserved:
  for nick: String
  for user: String
  {Args.resolve_nick(nick, True{}, user) == nick : String}

law nickname_without_sasl_user_preserved:
  for nick: String
  {Args.resolve_nick(nick, False{}, "") == nick : String}

law implicit_nickname_uses_sasl_user:
  {Args.resolve_nick("birc", False{}, "alice") == "alice" : String}

law channel_target_created_by_query_is_channel:
  {CL.channel_identity_get_ok() == True{} : Bool}

law closing_focused_tab_clears_replacement_unread:
  {CL.close_replacement_read_ok() == True{} : Bool}

law history_control_prefixed_log_rejected:
  {Hist.parse_line_for("a:6667", "BIRC2\ta:6667\t" ++ SCon{Chr{31}, "*log*"} ++ "\tMSG\t\talice\tsecret") == None{} : Maybe<&2, Hist.HistEntry>}

law history_zero_cap_restores_no_targets:
  {Hist.read_record.entry(Some{Hist.Entry{"alice", Cl.Line{Cl.Msg{}, "", "hi", "alice", 0n}}}, Cl.init("me", "a"), 0) == Cl.init("me", "a") : Cl.Client}

law prepared_message_echo_matches_wire:
  {Sub.prepare_message("#room", "hello") == Some{Sub.MessageBody{"hello", "PRIVMSG #room :hello"}} : Maybe<&2, Sub.MessageBody>}

law same_endpoint_dial_preserves_reconnect_intent:
  {Sess.dialing_state(True{}, Sess.Online{}) == Sess.Reconnecting{} : Sess.NetState}

law new_endpoint_dial_has_no_reconnect_intent:
  for net: Sess.NetState
  {Sess.dialing_state(False{}, net) == Sess.Connecting{} : Sess.NetState}
