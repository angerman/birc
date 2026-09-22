# Protocol self-test harness. Asserts golden tags (fail closed).
# Native: `bend tests/bend/proto_demo.bend -o build/birc-proto && ./build/birc-proto`
import Base
import ../../src/bend/irc.bend as Irc
import ./expect.bend as E
import ./irc_show.bend as Tag

def check(+tag: String, +line: String, +want: String) -> IO(Unit):
  E.must_eq(tag, Tag.show_parse(line), want)

def check_pong(+tag: String, +line: String, +want: String) -> IO(Unit):
  E.must_eq(tag, Irc.pong_for(line), want)

def check_chan(+tag: String, +name: String, +want: String) -> IO(Unit):
  E.must_eq(tag, Bool.show(Irc.starts_channel(name)), want)

def check_clamp(+tag: String, +s: String, +want: String) -> IO(Unit):
  E.must_eq(tag, Bool.show(Irc.line_ok(Irc.clamp_line(s))), want)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- check("ping", "PING :irc.example.net", "PING:!PING#0|irc.example.net")
    Unit <- check("ping_ci", "ping :xyz", "PING:!ping#0|xyz")
    Unit <- check("privmsg", ":alice!a@host PRIVMSG #birc :hello *bold*", "PRIVMSG:alice!PRIVMSG#0|#birc|hello *bold*")
    Unit <- check("join", ":me!me@localhost JOIN #birc", "JOIN:me!JOIN#0|#birc")
    Unit <- check("welcome", ":irc.example.net 001 me :Welcome", "NUM1:irc.example.net!001#1|me|Welcome")
    Unit <- check("empty", "", "NONE")
    Unit <- check("spaces", "   ", "NONE")
    Unit <- check_pong("pong", "PING :irc.example.net", "PONG :irc.example.net")
    Unit <- check_pong("pong_empty", "PING", "PONG")
    Unit <- check_chan("chan_hash", "#birc", "True")
    Unit <- check_chan("chan_nick", "alice", "False")
    Unit <- check_clamp("clamp", Irc.format_privmsg("#birc", "hi"), "True")
    Unit <- E.must_eq("ieq", Bool.show(Irc.ieq("PiNg", "ping")), "True")
    Unit <- E.must_eq("nick", Irc.format_nick("birc"), "NICK birc")
    Unit <- E.must_eq("user", Irc.format_user("birc"), "USER birc 0 * :birc")
    Unit <- E.must_eq("join_fmt", Irc.format_join("#birc"), "JOIN #birc")
    IO.print("proto_demo=ok")
