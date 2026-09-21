# Fixture corpus via File.read + replay_lines (fail closed).
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/frame.bend as Fr
import ../../src/bend/client.bend as Cl
import ../../src/bend/view.bend as V

def soh() -> String:
  SCon{Chr{1}, SNil{}}

def action_line() -> String:
  ":alice!a@host PRIVMSG #birc :" ++ soh() ++ "ACTION waves" ++ soh()

def check_line(+name: String, +line: String, +want: String) -> IO(Unit):
  E.must_eq(name, Irc.show_parse(line), want)

def nth_line(+xs: List<&2, String>, +i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, i), "")

def check_nth(+name: String, +xs: List<&2, String>, +i: Nat, +want: String) -> IO(Unit):
  check_line(name, nth_line(xs, i), want)

def pad_x(n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      pad_x(p, acc ++ " x")

def nparams.on(m: Maybe<&2, Irc.Message>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{msg}:
      match msg:
        case Irc.Message{_, _, _, ps}:
          List.length(&2, String, ps)

def params_n_ok(+n: Nat) -> Bool:
  Nat.is_eq(nparams.on(Irc.parse("MODE" ++ pad_x(n, ""))), n)

def has_tag(+want: String, +xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+h, t}:
      Bool.or(String.eq(Irc.show_parse(h), want), has_tag(want, t))

def action_feed_ok() -> Bool:
  +cl = Cl.feed_all(Cl.init("me", "s"), ":me!m@h JOIN #birc" <> action_line() <> Nil{})
  String.eq(Cl.buf_texts(cl, 1n), "-> me joined #birc|* alice waves|")

def read_die(+path: String, +msg: String) -> IO(String):
  IO.die(String, 1, "fixture " ++ path ++ ": " ++ msg)

def read_got(+path: String, f: File, r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Fail{e}:
      match e:
        case (_, +msg):
          do IO<String>:
            Unit <- File.close(f)
            read_die(path, msg)
    case Done{+text}:
      do IO<String>:
        Unit <- File.close(f)
        return text

def read_pair(+path: String, pair: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match pair:
    case (f, r):
      read_got(path, f, r)

def read_open(+path: String, r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{e}:
      match e:
        case (_, +msg):
          read_die(path, msg)
    case Done{f}:
      do IO<String>:
        pair : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        read_pair(path, pair)

def read_file(+path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read_open(path, r)

def check_demo(+xs: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("demo_n", Nat.is_eq(List.length(&2, String, xs), 3n))
    Unit <- check_nth("demo0", xs, 0n, "NUM1:irc.birc.dev!001#1|me|Welcome")
    Unit <- check_nth("demo1", xs, 1n, "PRIVMSG:alice!PRIVMSG#0|#birc|hello from fixture")
    check_nth("demo2", xs, 2n, "PRIVMSG:bob!PRIVMSG#0|#birc|see *bold* text")

def check_welcome(+xs: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("welcome_n", Nat.is_eq(List.length(&2, String, xs), 2n))
    Unit <- check_nth("welcome0", xs, 0n, "NUM1:irc.example.net!001#1|me|Welcome to the network")
    check_nth("welcome1", xs, 1n, "NUM2:irc.example.net!002#2|me|Your host is irc.example.net")

def check_action(+xs: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("action_n", Nat.is_eq(List.length(&2, String, xs), 2n))
    Unit <- check_nth("action0", xs, 0n, "PRIVMSG:alice!PRIVMSG#0|#birc|" ++ soh() ++ "ACTION waves" ++ soh())
    check_nth("action1", xs, 1n, "PRIVMSG:bob!PRIVMSG#0|#birc|normal message")

def check_odd(+xs: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("odd_n", Nat.is_eq(List.length(&2, String, xs), 3n))
    Unit <- check_nth("odd0", xs, 0n, "PING:!ping#0|OddToken")
    Unit <- check_nth("odd1", xs, 1n, "PING:!PiNg#0|xyz")
    check_nth("odd2", xs, 2n, "PRIVMSG:Nick!privmsg#0|#Birc|HeLLo")

def check_adv(+xs: List<&2, String>) -> IO(Unit):
  E.must("adv0", has_tag("JOIN:flood!JOIN#0|#c0", xs))

def replay_file(+path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    text : String <- read_file(path)
    return Cl.replay_lines(text)

def main() -> IO(Unit):
  do IO<Unit>:
    demo : List<&2, String> <- replay_file("fixtures/demo.irc")
    Unit <- check_demo(demo)
    welcome : List<&2, String> <- replay_file("fixtures/welcome.irc")
    Unit <- check_welcome(welcome)
    action : List<&2, String> <- replay_file("fixtures/action.irc")
    Unit <- check_action(action)
    odd : List<&2, String> <- replay_file("fixtures/odd_casing.irc")
    Unit <- check_odd(odd)
    adv : List<&2, String> <- replay_file("fixtures/adversarial.irc")
    Unit <- check_adv(adv)
    Unit <- check_line("kick0", ":op!u@h KICK #birc me :bye", "KICK:op!KICK#0|#birc|me|bye")
    Unit <- check_line("num353_1459", ":irc.birc.dev 353 me #birc :me alice", "NUM353:irc.birc.dev!353#353|me|#birc|me alice")
    Unit <- E.must("action_feed", action_feed_ok())
    Unit <- E.must("overlong", Fr.overlong_drop_ok())
    Unit <- E.must("clamp_samples", Irc.clamp_samples_ok())
    Unit <- E.must("strip_nocr", Irc.strip_ctl_nocr_ok())
    Unit <- E.must("flood_cap", Cl.flood_buffers_capped())
    Unit <- E.must("tok_rt", V.tokenize_roundtrip("hello *bold* text"))
    Unit <- E.must("tok_plain", V.tokenize_roundtrip("no stars here"))
    Unit <- E.must("params16", params_n_ok(16n))
    Unit <- E.must("params20", params_n_ok(20n))
    IO.print("proto_parity=ok")
