# M2.6 submit goldens — outbound lines must match, not merely print.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as Sess
import ../../src/bend/irc.bend as Irc

def hash() -> String:
  SCon{Chr{35}, SNil{}}

def join_cmd() -> String:
  "/join " ++ hash() ++ "birc"

def show_outs.go(fuel: Nat, +xs: List<&2, String>, +acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match xs:
        case Nil{}:
          acc
        case Con{+h, t}:
          show_outs.go(p, t, acc ++ h ++ "|")

def show_outs(+xs: List<&2, String>) -> String:
  show_outs.go(Nat.add(1n, List.length(&2, String, xs)), xs, "")

def tag_line(+cl2: Cl.Client, +outs: List<&2, String>) -> String:
  show_outs(outs) ++ " ok=" ++ Bool.show(Sub.out_all_ok(outs)) ++ " nbuf=" ++ Nat.show(CL.nbuf(cl2))

def line_of(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (cl2, outs):
      tag_line(cl2, outs)

def take_cl(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl2, _):
      cl2

def soh() -> String:
  SCon{Chr{1}, SNil{}}

def inj_input() -> String:
  "hello" ++ SCon{Chr{13}, SCon{Chr{10}, "QUIT :x"}}

def han_go(n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      han_go(p, SCon{Chr{28450}, acc})

def han600() -> String:
  han_go(600n, "")

def join_abc() -> List<&2, String>:
  ":me!me@localhost JOIN #a"
    <> ":me!me@localhost JOIN #b"
    <> ":me!me@localhost JOIN #c"
    <> Nil{}

def part_idx_tag(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (+cl2, _):
      Sub.active_name(cl2) ++ " nbuf=" ++ Nat.show(CL.nbuf(cl2))

def part_keeps_b() -> String:
  +cl = Feed.feed_all(Cl.init("me", "irc.birc.dev"), join_abc())
  +clb = Cl.set_active(cl, 2n)
  part_idx_tag(Sub.submit(clb, "/part #a"))

def first_out(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+h, _}:
      h

def inj_out(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, outs):
      first_out(outs)

def cmd_head(c: Sess.NetCmd) -> String:
  match c:
    case Sess.Cont{xs}:
      "cont:" ++ first_out(xs)
    case Sess.Dial{+host, port}:
      "dial:" ++ host ++ ":" ++ U32.show(port)
    case Sess.Handoff{take}:
      "handoff:" ++ Bool.show(take)

def trip_st(t: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match t:
    case (st, _):
      st

def trip_halt(t: Sess.Session & Sess.NetCmd & Bool) -> String:
  match t:
    case (_, rest):
      match rest:
        case (_, halt):
          Bool.show(halt)

def trip_cmd(t: Sess.Session & Sess.NetCmd & Bool) -> String:
  match t:
    case (_, rest):
      match rest:
        case (c, _):
          cmd_head(c)

def trip_nbuf(t: Sess.Session & Sess.NetCmd & Bool) -> String:
  match t:
    case (st, _):
      match st:
        case Sess.Session{+cl, _, _, _, _, _, _, _, _, _, _, _}:
          Nat.show(CL.nbuf(cl))

def trip_has_me.on(+cl: Cl.Client, +who: String, got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}:
      "none"
    case Some{b}:
      Bool.show(Cl.nick_has(b, who))

def trip_has_me(t: Sess.Session & Sess.NetCmd & Bool) -> String:
  match t:
    case (st, _):
      match st:
        case Sess.Session{+cl, _, _, _, _, _, _, _, _, _, _, _}:
          match cl:
            case Cl.Client{+nick, _, +bufs, +active, _}:
              trip_has_me.on(cl, nick, Cl.nth_buf(bufs, active))

def main_on.body(+cl0: Cl.Client, +cl1: Cl.Client, +join_line: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("out_nil", Sub.out_all_ok(Nil{}))
    Unit <- E.must(
      "out_over",
      Bool.not(Sub.out_all_ok(Irc.stars.go(511n) <> Nil{}))
    )
    Unit <- E.must_eq("empty", line_of(Sub.submit(cl0, "")), " ok=True nbuf=1")
    Unit <- E.must_eq("join", join_line, "JOIN #birc| ok=True nbuf=2")
    Unit <- E.must_eq("hi", line_of(Sub.submit(cl1, "hello")), "PRIVMSG #birc :hello| ok=True nbuf=2")
    Unit <- E.must_eq(
      "me",
      line_of(Sub.submit(cl1, "/me waves")),
      "PRIVMSG #birc :" ++ soh() ++ "ACTION waves" ++ soh() ++ "| ok=True nbuf=2"
    )
    Unit <- E.must_eq("msg", line_of(Sub.submit(cl1, "/msg alice hi there")), "PRIVMSG alice :hi there| ok=True nbuf=3")
    Unit <- E.must_eq("quit", line_of(Sub.submit(cl1, "/quit bye")), "QUIT :bye| ok=True nbuf=2")
    Unit <- E.must_eq("bad", line_of(Sub.submit(cl1, "/nope")), " ok=True nbuf=2")
    Unit <- E.must_eq("part_idx", part_keeps_b(), "#b nbuf=3")
    Unit <- E.must_eq(
      "part_server",
      line_of(Sub.submit(cl0, "/part")),
      " ok=True nbuf=1"
    )
    Unit <- E.must_eq("strip_ctl", inj_out(Sub.submit(cl1, inj_input())), "PRIVMSG #birc :helloQUIT :x")
    Unit <- E.must("clamp_utf8", Irc.line_ok(Irc.clamp_line(Irc.format_privmsg("#birc", han600()))))
    Unit <- E.must_eq("echo_nolf", Irc.sanitize_in("hi" ++ SCon{Chr{10}, "x"}), "hix")
    Unit <- E.must_eq(
      "echo_nolf_log",
      CL.buf_texts(
        take_cl(Sub.submit(take_cl(Sub.submit(Cl.init("me", "irc.birc.dev"), join_cmd())), "hi" ++ SCon{Chr{10}, "x"})),
        1n
      ),
      "<me> hix|"
    )
    Unit <- E.must("halt", Sub.submit_halt_ok())
    Unit <- E.must("conn", Sub.connect_parse_ok())
    Unit <- E.must("conn_port", Sub.connect_port_range_ok())
    Unit <- E.must("dial", Sess.cmd_connect_ok())
    Unit <- E.must_eq(
      "connect_out",
      trip_nbuf(Sess.step_enter(Sess.session_demo(cl0, "#birc"), "/connect irc.example.net 6668")),
      "1"
    )
    Unit <- E.must("connect_slash", Sub.submit_is_connect("/connect x"))
    Unit <- E.must("connect_not", Bool.not(Sub.submit_is_connect("/join #x")))
    Unit <- E.must_eq("body_h24", Nat.show(Sess.body_h(24)), "18")
    Unit <- E.must_eq("body_h16", Nat.show(Sess.body_h(16)), "10")
    Unit <- E.must_eq(
      "hist_seed",
      U32.show(Sess.session_seed(trip_st(Sess.step_keys(Sess.session0("me", "s", "#birc"), Sess.keys_of("kept", False{}, 0, 0, 0, 0, 2))))),
      "1"
    )
    Unit <- E.must_eq(
      "hist_clear",
      Sess.session_draft(trip_st(Sess.step_keys(Sess.session0("me", "s", "#birc"), Sess.keys_of("kept", False{}, 0, 0, 0, 0, 2)))),
      ""
    )
    Unit <- E.must_eq(
      "type_seed",
      U32.show(Sess.session_seed(trip_st(Sess.step_keys(Sess.session0("me", "s", "#birc"), Sess.keys_of("kept", False{}, 0, 0, 0, 0, 0))))),
      "0"
    )
    Unit <- E.must_eq("offline_msg", trip_cmd(Sess.step_enter(Sess.session0("me", "s", "#birc"), "hello")), "cont:")
    Unit <- E.must_eq("empty_enter", trip_halt(Sess.step_enter(Sess.session0("me", "s", "#birc"), "")), "False")
    Unit <- E.must_eq("quit_halt", trip_halt(Sess.step_enter(Sess.session0("me", "s", "#birc"), "/quit")), "True")
    Unit <- E.must_eq("quit_cmd", trip_cmd(Sess.step_enter(Sess.session0("me", "s", "#birc"), "/quit")), "cont:QUIT :birc")
    Unit <- E.must_eq("join_cmd", trip_cmd(Sess.step_enter(Sess.session_demo(cl0, "#birc"), join_cmd())), "cont:JOIN #birc")
    Unit <- E.must_eq("join_nbuf", trip_nbuf(Sess.step_enter(Sess.session_demo(cl0, "#birc"), join_cmd())), "2")
    Unit <- E.must_eq("join_self", trip_has_me(Sess.step_enter(Sess.session_demo(cl0, "#birc"), join_cmd())), "True")
    Unit <- E.must_eq("dial_demo", trip_cmd(Sess.step_enter(Sess.session_demo(cl0, "#birc"), "/connect irc.example.net 6668")), "dial:irc.example.net:6668")
    Unit <- E.must_eq("nodial_online", trip_cmd(Sess.step_enter(Sess.session_online(Sess.session0("me", "s", "#birc")), "/connect irc.example.net")), "cont:")
    Unit <- E.must_eq("nodial_connecting", trip_cmd(Sess.step_enter(Sess.session0("me", "s", "#birc"), "/connect irc.example.net")), "cont:")
    Unit <- E.must_eq("hold_demo", cmd_head(Sess.hold_cmd(Sess.Demo{}, Sess.Cont{"JOIN #x" <> Nil{}})), "cont:")
    Unit <- E.must_eq("hold_on", cmd_head(Sess.hold_cmd(Sess.Online{}, Sess.Cont{"JOIN #x" <> Nil{}})), "cont:JOIN #x")
    Unit <- E.must_eq(
      "merge_cont",
      cmd_head(Sess.merge_cmd("PONG :x" <> Nil{}, Sess.Cont{"JOIN #t" <> Nil{}})),
      "cont:PONG :x"
    )
    Unit <- E.must_eq(
      "merge_dial",
      cmd_head(Sess.merge_cmd("PONG :x" <> Nil{}, Sess.Dial{"h", 6667})),
      "dial:h:6667"
    )
    IO.print("submit_demo=ok")

def main_on.with(+cl0: Cl.Client, +cl1: Cl.Client, outs: List<&2, String>) -> IO(Unit):
  main_on.body(cl0, cl1, tag_line(cl1, outs))

def main_on(+cl0: Cl.Client, join_pair: Cl.Client & List<&2, String>) -> IO(Unit):
  match join_pair:
    case (cl1, outs):
      main_on.with(cl0, cl1, outs)

def main() -> IO(Unit):
  main_on(Cl.init("me", "irc.birc.dev"), Sub.submit(Cl.init("me", "irc.birc.dev"), join_cmd()))
