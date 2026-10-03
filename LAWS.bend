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
import ./tests/bend/m21_dns_preds.bend as DnsIdentity
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
import ./src/bend/upload.bend as Up
import ./src/bend/transport_policy.bend as Transport
import ./src/bend/endpoint.bend as Endpoint
import ./src/bend/utc_time.bend as Utc
import ./src/bend/preferences.bend as Prefs
import ./src/bend/irc_commands.bend as Commands
import ./src/bend/message_chunks.bend as Chunks
import ./src/bend/join_plan.bend as JoinPlan
import ./src/bend/history_startup.bend as StartupHistory
import ./src/bend/server_id.bend as Sid
import ./src/bend/ipv6.bend as V6
import ./src/bend/drafts.bend as Drafts

law first_server_welcome_assigns_nickname:
  {Sess.registration_client(False{}, Cl.init("me", "s"), ":s 001 Guest42 :welcome") == Some{Cl.init("Guest42", "s")} : Maybe<&2, Cl.Client>}

law later_welcome_cannot_replace_nickname:
  {Sess.registration_client(True{}, Cl.init("me", "s"), ":s 001 other :welcome") == None{} : Maybe<&2, Cl.Client>}

law rejected_welcome_preserves_live_state:
  for acc: Sess.LiveAcc
  for line: String
  for stamp: Maybe<&2, String>
  {Sess.live_step.registered(None{}, acc, line, stamp) == acc : Sess.LiveAcc}

law refused_startup_archive_keeps_current_client:
  for current: Cl.Client
  for snapshot: Cl.Client
  {StartupHistory.install.allowed(False{}, current, snapshot) == current : Cl.Client}

law absent_startup_target_keeps_current_client:
  for current: Cl.Client
  for line: Cl.Line
  {StartupHistory.restore.at(None{}, current, line) == current : Cl.Client}

law held_recovery_has_no_wire_output:
  {JoinPlan.flush(JoinPlan.State{[JoinPlan.Channel{"#room", "key"}], True{}, False{}, JoinPlan.NoAuth{}, True{}, 3n}, Cl.init("me", "s")) == JoinPlan.Flush{JoinPlan.State{[JoinPlan.Channel{"#room", "key"}], True{}, False{}, JoinPlan.NoAuth{}, True{}, 3n}, Nil{}, JoinPlan.Quiet{}} : JoinPlan.Flush}

law completed_recovery_does_not_repeat:
  {JoinPlan.flush(JoinPlan.demo("#room"), Cl.init("me", "s")) == JoinPlan.Flush{JoinPlan.demo("#room"), Nil{}, JoinPlan.Quiet{}} : JoinPlan.Flush}

law old_authentication_cannot_release_recovery:
  {JoinPlan.ready(JoinPlan.NeedAuth{0n, JoinPlan.Unreported{}}, Cl.init("me", "s")) == False{} : Bool}

law reset_keeps_key_revision_and_hold:
  {JoinPlan.reset(JoinPlan.State{[JoinPlan.Channel{"#room", "key"}], True{}, True{}, JoinPlan.NoAuth{}, True{}, 3n}, Cl.init("me", "s")) == JoinPlan.State{[JoinPlan.Channel{"#room", "key"}], False{}, False{}, JoinPlan.NoAuth{}, True{}, 3n} : JoinPlan.State}

law new_endpoint_discards_previous_channel_keys:
  {JoinPlan.endpoint(False{}, JoinPlan.State{[JoinPlan.Channel{"#old", "key"}], True{}, True{}, JoinPlan.NoAuth{}, False{}, 3n}, "#new", Cl.init("me", "s")) == JoinPlan.State{[JoinPlan.Channel{"#new", ""}], False{}, False{}, JoinPlan.NoAuth{}, False{}, 3n} : JoinPlan.State}

law delayed_membership_echo_cannot_erase_intent:
  {JoinPlan.received(JoinPlan.State{[JoinPlan.Channel{"#room", "new-key"}], True{}, True{}, JoinPlan.NoAuth{}, False{}, 3n}, Cl.init("me", "s"), ":me!u@h PART #room :old departure") == JoinPlan.State{[JoinPlan.Channel{"#room", "new-key"}], True{}, True{}, JoinPlan.NoAuth{}, False{}, 3n} : JoinPlan.State}

law server_time_invalid_calendar_is_rejected:
  {Utc.parse("2023-02-29T00:00:00Z") == None{} : Maybe<&2, Utc.Utc>}

law server_time_retains_complete_utc_event:
  {Utc.parse("2024-02-29T23:59:59.123Z") == Some{Utc.Utc{2024, 2, 29, 23, 59, 59}} : Maybe<&2, Utc.Utc>}

law server_time_leap_second_is_preserved:
  {Utc.parse("2012-06-30T23:59:60.419Z") == Some{Utc.Utc{2012, 6, 30, 23, 59, 60}} : Maybe<&2, Utc.Utc>}

law duplicate_server_time_is_invalid:
  {Utc.line_stamp("@time=2024-01-01T00:00:00Z;time=2024-01-01T01:00:00Z :s NOTICE me :text") == Utc.Invalid{} : Utc.Stamp}

law captured_image_preference_is_preserved:
  for cl: Cl.Client
  for images: Bool
  for channels: List<&2, String>
  {Prefs.images(Prefs.capture(cl, images, channels)) == images : Bool}

law raw_command_cannot_inject_line:
  {Commands.raw("PASS x\r\nQUIT :x") == None{} : Maybe<&2, String>}

law explicit_empty_topic_is_sent:
  {Commands.topic("#room", "#other :") == Some{"TOPIC #other :"} : Maybe<&2, String>}

law message_chunks_preserve_combining_cluster:
  {Chunks.split("éx", 3n) == Some{["é", "x"]} : Maybe<&2, List<&2, String>>}

law notice_credentials_do_not_enter_composer_history:
  {Sub.input_sensitive(Cl.init("me", "s"), "/notice NickServ :IDENTIFY secret") == True{} : Bool}

law default_irc_transport_is_tls:
  {Transport.default_secure() == True{} : Bool}

law explicit_tls_keeps_plain_number_port:
  {Transport.default_port(True{}, True{}, 6667) == 6667 : U32}

law plain_default_uses_legacy_port:
  {Transport.default_port(False{}, False{}, 6697) == 6667 : U32}

law explicit_plain_keeps_secure_number_port:
  {Transport.default_port(False{}, True{}, 6697) == 6697 : U32}

law tls_default_keeps_explicit_port:
  for secure: Bool
  for port: U32
  {Transport.default_port(secure, True{}, port) == port : U32}

law tls_default_uses_secure_port:
  {Transport.default_port(True{}, False{}, 6667) == 6697 : U32}

law transport_selectors_cannot_conflict:
  {Args.parse(["--plain", "--tls"]) == Args.Bad{"birc: --tls and --plain conflict"} : Args.Parsed}

law endpoint_keeps_original_host_identity:
  {Endpoint.parse("IRC.Example.:7000") == Done{Endpoint.Endpoint{"IRC.Example.", Some{7000}}} : Result<&2, &2, String, Endpoint.Endpoint>}

law endpoint_same_explicit_ports_agree:
  {Endpoint.select_port(Some{7000}, Some{7000}, 6697) == Some{7000} : Maybe<&2, U32>}

law endpoint_differing_explicit_ports_refuse:
  {Endpoint.select_port(Some{7000}, Some{7001}, 6697) == None{} : Maybe<&2, U32>}

law endpoint_port_is_bounded:
  {Endpoint.port("65536") == None{} : Maybe<&2, U32>}

law endpoint_ipv6_is_not_supported:
  {Endpoint.parse("[::1]:6697") == Fail{"bad endpoint"} : Result<&2, &2, String, Endpoint.Endpoint>}

law unknown_command_is_not_implicit_upload:
  for rest: String
  {Sess.upload_input.parsed(Sub.CommandInput{Sub.Unknown{}, "NO_SUCH_COMMAND", rest}, "/NO_SUCH_COMMAND " ++ rest) == Sess.NotUpload{} : Sess.UploadInput}

law path_shaped_drop_still_requires_upload_consent:
  {Sess.upload_input.parsed(Sub.parse_input("/tmp/image.png"), "/tmp/image.png") == Sess.UploadPaths{["/tmp/image.png"]} : Sess.UploadInput}

law upload_requires_physical_consent:
  {Up.consent_ok() == True{} : Bool}

law upload_worker_one_shot:
  {Up.one_shot_ok() == True{} : Bool}

law upload_cancel_retains_owner_not_permission:
  {Up.cancel_ok() == True{} : Bool}

law upload_warning_precedes_authorization:
  {Sess.upload_presentation_reset_ok() == True{} : Bool}

law upload_invalid_local_uri_keeps_intent:
  {Up.looks_local_drop("file:///fixture/private%FF.jpg") == True{} : Bool}

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
  {List.is_empty(&2, String, Media.known_urls(Media.reset(Media.State{True{}, 1n, 2n, Some{Media.Request{Media.Inline{1n}, "http://x/a.png", 1n, 1n}}, Nil{}, Nil{}, Media.Supported{}}), Media.Inline{1n})) == True{} : Bool}

# Unsupported terminal capability must block requests before helper admission.
law media_unsupported_no_request:
  for +on: Bool
  for +target: Media.Target
  for +url: String
  {Media.pending_count(Media.enqueue(Media.set_supported(Media.initial(on), False{}), target, url)) == 0n : Nat}

law media_unsupported_keeps_preference:
  for on: Bool
  {Media.enabled(Media.set_supported(Media.initial(on), False{})) == on : Bool}

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
  {VL.tokenize_roundtrip("hello *bold* text") == True{} : Bool}

# LAW: *bold* is a Bold span, not an identity echo.
law tokenize_has_bold:
  {VL.tokenize_has_bold("hello *bold* text") == True{} : Bool}

# LAW: _em_ is an Italic span.
law tokenize_has_italic:
  {VL.tokenize_has_italic("_em_") == True{} : Bool}

# LAW: `code` is a Code span.
law tokenize_has_code:
  {VL.tokenize_has_code("`code`") == True{} : Bool}

# LAW: https URL becomes a Link span.
law tokenize_has_link:
  {VL.tokenize_has_link("see https://timui.dev x") == True{} : Bool}

# LAW: unclosed *foo stays plain (no Bold).
law tokenize_unclosed:
  {VL.unclosed_star_plain() == True{} : Bool}

# LAW: unmatched markup remains plain with the opener in its source position.
law tokenize_unclosed_source_order:
  {VL.tokenize_roundtrip("*foo") && VL.tokenize_roundtrip("_foo") && VL.tokenize_roundtrip("`foo") == True{} : Bool}

# LAW: the live operation for inline code retains the dim attribute.
law code_span_dim:
  {VL.span_op(VL.Code{"code"}) == V.Spn{2, "code"} : V.SpanOp}

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

# LAW: a rejected service identity probe cannot release credentials.
law nickserv_untrusted_probe_no_reply:
  for cl: Cl.Client
  {Auth.nick_probed(False{}, cl) == Auth.unchanged(Cl.AuthNickProbe{}) : Auth.Reply}

# LAW: a rejected confirmation is not an authentication success.
law nickserv_untrusted_confirmation_no_success:
  {Auth.nick_confirm(False{}) == Auth.unchanged(Cl.AuthNickResult{}) : Auth.Reply}

# LAW: an absent profile cannot establish a trusted service notice.
law nickserv_disabled_notice_untrusted:
  for cl: Cl.Client
  for prefix: String
  for msg: Irc.Message
  {Auth.trusted_notice(Cl.AuthDisabled{}, cl, prefix, msg) == False{} : Bool}

# LAW: an absent credential pair cannot start either mechanism.
law auth_without_credentials_idle:
  for config: Cl.AuthConfig
  {Cl.auth_initial(False{}, config) == Cl.AuthIdle{} : Cl.AuthPhase}

# LAW: phase changes retain profile scope and success evidence.
law auth_phase_preserves_profile:
  for before: Cl.AuthPhase
  for after: Cl.AuthPhase
  for config: Cl.AuthConfig
  for seq: Nat
  {Cl.auth_config(Cl.auth_phase_set(Cl.AuthProfile{before, config, seq}, after)) == config : Cl.AuthConfig}

law auth_phase_preserves_success:
  for before: Cl.AuthPhase
  for after: Cl.AuthPhase
  for config: Cl.AuthConfig
  for seq: Nat
  {Cl.auth_seq(Cl.auth_phase_set(Cl.AuthProfile{before, config, seq}, after)) == seq : Nat}

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
  {VL.span_ops(VL.tokenize("**B _BI_ B**")) == [V.Spn{1, "B "}, V.Spn{5, "BI"}, V.Spn{1, " B"}] : List<&2, V.SpanOp>}

# LAW: escaped markers remain literal, without becoming style delimiters.
law formatting_escaped_literal:
  {VL.span_ops(VL.tokenize("\\*literal\\*")) == [V.Spn{0, "*literal*"}] : List<&2, V.SpanOp>}

# LAW: bold + opaque dim code is not interpreted as a URL tag.
law formatting_code_identity:
  {VL.span_ops(VL.tokenize("*`:eyes:`*")) == [V.Spn{3, ":eyes:"}] : List<&2, V.SpanOp>}

# LAW: aliases are view-only and case sensitive; unknown names remain literal.
law formatting_alias_literals:
  {VL.span_ops(VL.tokenize(":eyes: :Eyes: :unknown:")) == [V.Spn{0, "👀 :Eyes: :unknown:"}] : List<&2, V.SpanOp>}

# LAW: alias-like and markup-like URL bytes remain exact and opaque.
law formatting_url_identity:
  {VL.span_ops(VL.tokenize("https://x.test/a_b/:eyes:?q=**z**,")) == [V.Lnk{"https://x.test/a_b/:eyes:?q=**z**", "https://x.test/a_b/:eyes:?q=**z**"}, V.Spn{0, ","}] : List<&2, V.SpanOp>}

# LAW: a greedy unmatched double opener retains both source characters.
law formatting_unmatched_double:
  {VL.span_ops(VL.tokenize("**one*")) == [V.Spn{0, "**one*"}] : List<&2, V.SpanOp>}

# LAW: nested style closers do not split or rewrite a URL's internal bytes.
law formatting_styled_url_identity:
  {VL.span_ops(VL.tokenize("_**https://x.test/a_b/:eyes:**_")) == [V.Spn{5, "https://x.test/a_b/:eyes:"}] : List<&2, V.SpanOp>}

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

law dns_labels_do_not_alias_dotted_names:
  {DnsIdentity.label_identity_ok() == True{} : Bool}

law dns_error_requires_matching_question:
  {DnsIdentity.error_identity_ok() == True{} : Bool}

law view_style_boundaries_keep_clusters:
  {VL.styled_cluster_ok() == True{} : Bool}

law view_words_keep_clusters_and_source:
  {VL.word_wrap_ok() == True{} : Bool}

law view_hidden_header_does_not_paint:
  {VL.hidden_header_ok() == True{} : Bool}

law view_header_uses_columns:
  {VL.header_columns_ok() == True{} : Bool}

law view_prefix_fallback_preserves_text:
  {VL.prefix_fallback_ok() == True{} : Bool}

law view_prefix_width_includes_joined_closer:
  {V.msg_prefix_w("<👩‍> hello") == 4 : U32}

law color_without_background_preserves_literal_comma:
  {Irc.sanitize_in(SCon{Chr{3}, "4,hello"}) == ",hello" : String}

law status_audience_keeps_local_channel_identity:
  {Cl.target_key("@#room") == "#room" : String}

law local_channel_prefix_is_not_status_audience:
  {Cl.target_key("+local") == "+local" : String}

law channel_creation_keeps_status_like_prefix:
  {Cl.active_buf_name.on(Some{Cl.empty_buf("+#room", True{})}) == "+#room" : String}

law resident_channel_wins_over_status_fallback:
  {Cl.message_key.resident("+#room", Some{Cl.empty_buf("+#room", True{})}) == "+#room" : String}

law stored_plus_channel_keeps_identity:
  {Hist.history_key("+#room") == "+#room" : String}

law legacy_at_audience_restores_channel:
  {Hist.history_key("@#room") == "#room" : String}

law typing_membership_target_is_not_status_audience:
  {Ty.event_target(Cl.init("me", "s"), Irc.Message{"", "alice", "PART", 0, ["+#room"]}, Irc.Part{}) == "+#room" : String}

law saved_single_label_hosts_can_reconnect:
  {Sess.reconnect_configured(Sess.Offline{}, "s") && Sess.reconnect_configured(Sess.Offline{}, "demo") == True{} : Bool}

law unconfigured_demo_cannot_reconnect:
  {Sess.reconnect_configured(Sess.Demo{}, "s") == False{} : Bool}

law user_notice_prefix_is_not_server:
  {Irc.source_is_server("server!u@h", "server") == False{} : Bool}

law join_lists_accept_masked_channels:
  {Sub.join_channels(["#room:*.fi", "#b"]) == True{} : Bool}

law join_lists_reject_nonchannel_targets:
  {Sub.join_channels(["#a", "alice"]) == False{} : Bool}

law image_switch_keeps_exact_argument_policy:
  {Sub.images_arg("on") == Some{True{}} : Maybe<&2, Bool>}

law serverid_routing_rejects_invalid_and_stale:
  {Sid.routing_ok() == True{} : Bool}

law serverid_isolation_keeps_exact_secrets:
  {Sid.isolation_ok() == True{} : Bool}

law serverid_generations_bound_ids:
  {Sid.generation_ok() == True{} : Bool}

law ipv6_literal_valid:
  {V6.literal_ok() == True{} : Bool}

law ipv6_endpoint_format:
  {V6.endpoint_ok() == True{} : Bool}

law ipv6_dial_plan:
  {V6.dial_ok() == True{} : Bool}
law draft_store_roundtrip:
  {Drafts.roundtrip_ok() == True{} : Bool}

law draft_missing_is_empty:
  {Drafts.missing_ok() == True{} : Bool}

law draft_rename_moves_text:
  {Drafts.rename_ok() == True{} : Bool}

law draft_overlong_text_rejected:
  {Drafts.overcap_ok() == True{} : Bool}

law draft_lines_split_separators:
  {Drafts.split_ok() == True{} : Bool}

law draft_single_line_routes_verbatim:
  {Drafts.route_ok() == True{} : Bool}

law draft_multiline_plan_bounded:
  {Drafts.plan_ok() == True{} : Bool}

law draft_command_multiline_rejected:
  {Drafts.command_rejected_ok() == True{} : Bool}

law draft_focus_stashes_and_loads:
  {Drafts.focus_ok() == True{} : Bool}

law draft_entries_match_buffer_slots:
  {Drafts.entry_cap_ok() == True{} : Bool}

law draft_control_query_coexist:
  {Drafts.coexist_ok() == True{} : Bool}
