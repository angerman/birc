import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc

def msg_time_test.on(m: Maybe<&2, Irc.Message>) -> String:
  match m:
    case None{}: "NONE"
    case Some{msg}: Irc.msg_time(msg)

def msg_time_test(line: String) -> String:
  msg_time_test.on(Irc.parse(line))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq(
      "tag_time",
      msg_time_test("@time=2026-09-28T17:40:27.123Z :alice!a@h PRIVMSG #birc :hello"),
      "17:40:27"
    )
    Unit <- E.must_eq(
      "tag_multi",
      msg_time_test("@account=user;time=2023-01-02T03:04:05Z;foo=bar :alice!a@h PRIVMSG #birc :hello"),
      "03:04:05"
    )
    Unit <- E.must_eq(
      "tag_none",
      msg_time_test(":alice!a@h PRIVMSG #birc :hello"),
      ""
    )
    IO.print("server_time_demo=ok")
