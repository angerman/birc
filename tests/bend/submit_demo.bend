# M2.6 submit goldens — outbound lines must match, not merely print.
import Base
import ./expect.bend as E
import ../../src/bend/client.bend as Cl
import ../../src/bend/submit.bend as Sub

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
  show_outs(outs) ++ " ok=" ++ Bool.show(Sub.out_all_ok(outs)) ++ " nbuf=" ++ Nat.show(Cl.nbuf(cl2))

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

def join_abc() -> List<&2, String>:
  ":me!me@localhost JOIN #a"
    <> ":me!me@localhost JOIN #b"
    <> ":me!me@localhost JOIN #c"
    <> Nil{}

def part_idx_tag(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (+cl2, _):
      Sub.active_name(cl2) ++ " nbuf=" ++ Nat.show(Cl.nbuf(cl2))

def part_keeps_b() -> String:
  +cl = Cl.feed_all(Cl.init("me", "irc.birc.dev"), join_abc())
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

def main_on.body(+cl0: Cl.Client, +cl1: Cl.Client, +join_line: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("out_nil", Sub.out_all_ok(Nil{}))
    Unit <- E.must(
      "out_fuel0",
      Bool.not(Sub.out_all_ok.go(0n, "PRIVMSG #birc :x" <> Nil{}, True{}))
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
    Unit <- E.must_eq("strip_ctl", inj_out(Sub.submit(cl1, inj_input())), "PRIVMSG #birc :helloQUIT :x")
    IO.print("submit_demo=ok")

def main_on.with(+cl0: Cl.Client, +cl1: Cl.Client, outs: List<&2, String>) -> IO(Unit):
  main_on.body(cl0, cl1, tag_line(cl1, outs))

def main_on(+cl0: Cl.Client, join_pair: Cl.Client & List<&2, String>) -> IO(Unit):
  match join_pair:
    case (cl1, outs):
      main_on.with(cl0, cl1, outs)

def main() -> IO(Unit):
  main_on(Cl.init("me", "irc.birc.dev"), Sub.submit(Cl.init("me", "irc.birc.dev"), join_cmd()))
