# M1.6 — feed DEMO_LINES plus NOTICE*/001 regressions. Assert, do not print-and-pass.
import Base
import ./expect.bend as E
import ../../src/bend/client.bend as Cl
import ../../src/bend/view.bend as V
import ../../src/bend/clock.bend as Clock
import ../../src/bend/irc.bend as Irc

def forge_msg() -> String:
  ":a!a@h PRIVMSG me :look "
    ++ SCon{Chr{31}, "Lhttps://evil.example"}
    ++ SCon{Chr{29}, "https://github.com/zw3rk/birc"}

def no_forge_pack() -> Bool:
  String.eq(
    Cl.buf_texts(Cl.feed(Cl.init("me", "s"), forge_msg()), 1n),
    "<a> look Lhttps://evil.examplehttps://github.com/zw3rk/birc|"
  )

def join_us_name() -> Bool:
  +cl = Cl.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #a" ++ SCon{Chr{31}, "b"})
  Cl.has_buf(cl, "#ab") && Bool.not(Cl.has_buf(cl, "#a" ++ SCon{Chr{31}, "b"}))

def naive_body() -> String:
  "na" ++ SCon{Chr{239}, "ve latin1"}

def naive_pack() -> String:
  V.show_spans(V.tokenize("<a> " ++ naive_body()))

def main_on(+demo: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq(
      "feed",
      Cl.show_client(demo),
      "me@irc.birc.dev[1]:server{|1|};#birc#{birc — Bend 2 + timui.h IRC|4|me alice bob carol };"
    )
    Unit <- E.must_eq("nbuf", Nat.show(Cl.nbuf(demo)), "2")
    Unit <- E.must("notice*", Cl.notice_star_server())
    Unit <- E.must("query", Cl.privmsg_query_opens())
    Unit <- E.must("welcome", Cl.welcome_server_line())
    Unit <- E.must("empty_id", Cl.feed_id(Cl.init("me", "s"), ""))
    Unit <- E.must("num_last", Cl.numeric_last_ok())
    Unit <- E.must("nick433", Cl.nick433_ok())
    Unit <- E.must("nick433_star", Cl.nick433_star_ok())
    Unit <- E.must("nick433_same", Cl.nick433_same_ok())
    Unit <- E.must("flood", Cl.flood_buffers_capped())
    Unit <- E.must("flood_server", Cl.flood_server_clean())
    Unit <- E.must(
      "foreign_join",
      Nat.is_eq(Cl.nbuf(Cl.feed(Cl.init("me", "s"), ":rando!r@h JOIN #never-joined")), 1n)
    )
    Unit <- E.must(
      "cap_active",
      Nat.is_lt(Cl.active_of(Cl.feed_all(Cl.init("me", "s"), Cl.flood_joins(24n))), 16n)
    )
    Unit <- E.must("names1459", Cl.names_1459_ok())
    Unit <- E.must("statusmsg", Cl.statusmsg_ok())
    Unit <- E.must("notice_auth", Cl.notice_auth_ok())
    Unit <- E.must("kick_self", Cl.kick_self_drops())
    Unit <- E.must("chrono", Cl.log_chrono_ok())
    Unit <- E.must("cycle", Cl.cycle_ok())
    Unit <- E.must("style", V.style_self_ne_msg())
    Unit <- E.must("style_spec", V.style_spec_ok())
    Unit <- E.must("pack_fg", V.pack_fg_ok())
    Unit <- E.must("kcode", V.kind_code_ok())
    Unit <- E.must("draw_line", V.draw_line_ok())
    Unit <- E.must("draw_link", V.draw_link_ok())
    Unit <- E.must("draw_hostile", V.draw_hostile_ok())
    Unit <- E.must("draw_tabs", V.draw_tabs_ok())
    Unit <- E.must("draw_nicks", V.draw_nicks_ok())
    Unit <- E.must("body_ys", V.body_ys_ok())
    Unit <- E.must("tsw", V.ts_width_ok())
    Unit <- E.must("vchrono", V.vis_chrono_ok())
    Unit <- E.must("tok_italic", V.tokenize_has_italic("_em_"))
    Unit <- E.must("tok_code", V.tokenize_has_code("`code`"))
    Unit <- E.must("tok_link", V.tokenize_has_link("see https://timui.dev x"))
    Unit <- E.must("tok_unclosed", V.unclosed_star_plain())
    Unit <- E.must("tok_no_italic", Bool.not(V.tokenize_has_italic("no marks")))
    Unit <- E.must("page", Cl.scroll_page_ok())
    Unit <- E.must("scroll_clamp", Cl.scroll_clamp_ok())
    Unit <- E.must("nick_query", Cl.nick_query_renames())
    Unit <- E.must("quit_query", Cl.quit_query_logs())
    Unit <- E.must("mode_chan", Cl.mode_channel_logs())
    Unit <- E.must("part_nonmember", Cl.part_nonmember_silent())
    Unit <- E.must("server_nick", Cl.server_nick_query())
    Unit <- E.must("ieq1459", Cl.ieq_rfc1459_ok())
    Unit <- E.must("self_priv", Cl.self_priv_query())
    Unit <- E.must("bare_join", Cl.bare_join_ok())
    Unit <- E.must("tok_no_embed", V.tokenize_no_embed())
    Unit <- E.must("tok_trim_dot", V.tokenize_trim_dot())
    Unit <- E.must("snap", Cl.snap_ok())
    Unit <- E.must("self_part", Cl.self_part_drops())
    # F8: roundtrip alone is satisfied by an identity tokenizer; require a Bold span.
    Unit <- E.must("tok_rt", V.tokenize_roundtrip("hello *bold* text"))
    Unit <- E.must("tok_bold", V.tokenize_has_bold("hello *bold* text"))
    Unit <- E.must("tok_plain", Bool.not(V.tokenize_has_bold("no stars here")))
    Unit <- E.must("log_ts", Cl.log_ts_ok())
    Unit <- E.must("sanitize", Irc.sanitize_in_ok())
    Unit <- E.must("no_forge", no_forge_pack())
    Unit <- E.must("join_us", join_us_name())
    Unit <- E.must_eq(
      "naive_feed",
      Cl.buf_texts(
        Cl.feed(Cl.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #t"), ":a!a@h PRIVMSG #t :" ++ naive_body()),
        1n
      ),
      "-> me joined #t|<a> " ++ naive_body() ++ "|"
    )
    Unit <- E.must_eq("naive_pack", naive_pack(), "<a> " ++ naive_body())
    Unit <- E.must("hms", Clock.fmt_hms_ok())
    Unit <- E.must_eq(
      "replay_lines",
      Nat.show(List.length(&2, String, Cl.replay_lines("a\r\n\nb\n"))),
      "2"
    )
    IO.print("feed_demo=ok")

def main() -> IO(Unit):
  main_on(Cl.feed_all(Cl.init("me", "irc.birc.dev"), Cl.demo_lines()))
