# M1.6 — feed DEMO_LINES plus NOTICE*/001 regressions. Assert, do not print-and-pass.
import Base
import ./expect.bend as E
import ../../src/bend/client.bend as Cl
import ../../src/bend/view.bend as V

def main_on(+demo: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq(
      "feed",
      Cl.show_client(demo),
      "me@irc.birc.dev[1]:server{|1|};#birc#{birc — Bend 2 + timui.h IRC|3|me alice bob carol };"
    )
    Unit <- E.must_eq("nbuf", Nat.show(Cl.nbuf(demo)), "2")
    Unit <- E.must("notice*", Cl.notice_star_server())
    Unit <- E.must("query", Cl.privmsg_query_opens())
    Unit <- E.must("welcome", Cl.welcome_server_line())
    Unit <- E.must("empty_id", Cl.feed_id(Cl.init("me", "s"), ""))
    Unit <- E.must("flood", Cl.flood_buffers_capped())
    Unit <- E.must("flood_server", Cl.flood_server_clean())
    Unit <- E.must("names1459", Cl.names_1459_ok())
    Unit <- E.must("statusmsg", Cl.statusmsg_ok())
    Unit <- E.must("notice_auth", Cl.notice_auth_ok())
    Unit <- E.must("kick_self", Cl.kick_self_drops())
    Unit <- E.must("chrono", Cl.log_chrono_ok())
    Unit <- E.must("cycle", Cl.cycle_ok())
    Unit <- E.must("style", V.style_self_ne_msg())
    Unit <- E.must("kcode", V.kind_code_ok())
    Unit <- E.must("tsw", V.ts_width_ok())
    Unit <- E.must("vchrono", V.vis_chrono_ok())
    Unit <- E.must("self_part", Cl.self_part_drops())
    # F8: roundtrip alone is satisfied by an identity tokenizer; require a Bold span.
    Unit <- E.must("tok_rt", V.tokenize_roundtrip("hello *bold* text"))
    Unit <- E.must("tok_bold", V.tokenize_has_bold("hello *bold* text"))
    Unit <- E.must("tok_plain", Bool.not(V.tokenize_has_bold("no stars here")))
    IO.print("feed_demo=ok")

def main() -> IO(Unit):
  main_on(Cl.feed_all(Cl.init("me", "irc.birc.dev"), Cl.demo_lines()))
