# Protocol + client laws. The human states them; PROOF.bend must prove them.
import Base
import ./src/bend/irc.bend as Irc
import ./src/bend/buffer.bend as Cl
import ./src/bend/client.bend as Feed
import ./src/bend/client_laws.bend as CL
import ./src/bend/submit.bend as Sub
import ./src/bend/frame.bend as Fr
import ./src/bend/view.bend as V
import ./src/bend/session.bend as Sess
import ./src/bend/clock.bend as Clock

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

# LAW: scroll clamp stays within bounds.
law scroll_bounds:
  {V.scroll_bounds_ok(100n, 10n, 5n) == True{} : Bool}

# LAW: body height is rows minus six chrome rows (header, tabs, borders,
# status), with a floor of 1. Layout is Bend DrawOp; C does not cap rows.
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

# LAW: M7.2 overlong framer input yields no lines.
law overlong_drop:
  {Fr.overlong_drop_ok() == True{} : Bool}

# LAW: M7.2 JOIN flood past MAX_BUFFERS stays capped.
law flood_buffers:
  {CL.flood_buffers_capped() == True{} : Bool}

# LAW: extra JOINs past the cap do not land on the server buffer.
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
  {V.style_self_ne_msg() == True{} : Bool}

# LAW: timestamp column is 8 cells (HH:MM:SS + space).
law ts_width_ok:
  {V.ts_width_ok() == True{} : Bool}

# LAW: visible window is oldest-to-newest.
law vis_chrono:
  {V.vis_chrono_ok() == True{} : Bool}

# LAW: body-line y values increase, end on the last inner row, count = vis_h.
law body_ys_ok:
  {V.body_ys_ok() == True{} : Bool}

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

# LAW: --frames 3 is 3 live ticks (one event each).
law live_fuel_small:
  {Nat.is_eq(Sess.live_fuel(3), 3n) == True{} : Bool}
