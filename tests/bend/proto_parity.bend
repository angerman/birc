# M3 proto-parity — assert parse tags for fixtures/*.irc corpus (fail closed).
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

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- check_line("demo0", ":irc.birc.dev 001 me :Welcome", "NUM1:irc.birc.dev!001#1|me|Welcome")
    Unit <- check_line("demo1", ":alice!a@h PRIVMSG #birc :hello from fixture", "PRIVMSG:alice!PRIVMSG#0|#birc|hello from fixture")
    Unit <- check_line("demo2", ":bob!b@h PRIVMSG #birc :see *bold* text", "PRIVMSG:bob!PRIVMSG#0|#birc|see *bold* text")
    Unit <- check_line("welcome0", ":irc.example.net 001 me :Welcome to the network", "NUM1:irc.example.net!001#1|me|Welcome to the network")
    Unit <- check_line("welcome1", ":irc.example.net 002 me :Your host is irc.example.net", "NUM2:irc.example.net!002#2|me|Your host is irc.example.net")
    Unit <- check_line("action0", action_line(), "PRIVMSG:alice!PRIVMSG#0|#birc|" ++ soh() ++ "ACTION waves" ++ soh())
    Unit <- check_line("action1", ":bob!b@host PRIVMSG #birc :normal message", "PRIVMSG:bob!PRIVMSG#0|#birc|normal message")
    Unit <- check_line("odd0", "ping :OddToken", "PING:!ping#0|OddToken")
    Unit <- check_line("odd1", "PiNg :xyz", "PING:!PiNg#0|xyz")
    Unit <- check_line("odd2", ":Nick!u@h privmsg #Birc :HeLLo", "PRIVMSG:Nick!privmsg#0|#Birc|HeLLo")
    Unit <- check_line("adv0", ":flood!f@h JOIN #c0", "JOIN:flood!JOIN#0|#c0")
    Unit <- check_line("kick0", ":op!u@h KICK #birc me :bye", "KICK:op!KICK#0|#birc|me|bye")
    Unit <- check_line("num353_1459", ":irc.birc.dev 353 me #birc :me alice", "NUM353:irc.birc.dev!353#353|me|#birc|me alice")
    Unit <- E.must("overlong", Fr.overlong_drop_ok())
    Unit <- E.must("flood_cap", Cl.flood_buffers_capped())
    Unit <- E.must("tok_rt", V.tokenize_roundtrip("hello *bold* text"))
    Unit <- E.must("tok_plain", V.tokenize_roundtrip("no stars here"))
    IO.print("proto_parity=ok")
