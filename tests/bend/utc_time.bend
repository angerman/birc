import Base
import ./expect.bend as E
import ../../src/bend/utc_time.bend as T

def valid(+text: String) -> Bool:
  Maybe.is_some(&2, T.Utc, T.parse(text))

def tag_show(tag: T.Stamp) -> String:
  match tag:
    case T.Missing{}: "missing"
    case T.Invalid{}: "invalid"
    case T.Valid{utc}: T.show(utc)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("canonical UTC", valid("2026-09-28T17:40:27.123Z"))
    Unit <- E.must("fractionless compatibility", valid("2023-01-02T03:04:05Z"))
    Unit <- E.must("leap day", valid("2024-02-29T23:59:59.9Z"))
    Unit <- E.must("leap second", valid("2012-06-30T23:59:60.419Z"))
    Unit <- E.must("wrong leap minute rejects", Bool.not(valid("2024-01-31T12:34:60Z")))
    Unit <- E.must("wrong leap date rejects", Bool.not(valid("2024-01-01T23:59:60Z")))
    Unit <- E.must("non-leap day rejected", Bool.not(valid("2023-02-29T00:00:00Z")))
    Unit <- E.must("invalid month rejected", Bool.not(valid("2024-13-01T00:00:00Z")))
    Unit <- E.must("invalid day rejected", Bool.not(valid("2024-04-31T00:00:00Z")))
    Unit <- E.must("invalid hour rejected", Bool.not(valid("2024-01-01T24:00:00Z")))
    Unit <- E.must("invalid minute rejected", Bool.not(valid("2024-01-01T00:60:00Z")))
    Unit <- E.must("invalid second rejected", Bool.not(valid("2024-01-01T00:00:61Z")))
    Unit <- E.must("digits only", Bool.not(valid("2024-01-01Txx:00:00Z")))
    Unit <- E.must("UTC only", Bool.not(valid("2024-01-01T00:00:00+09:00")))
    Unit <- E.must("empty fraction rejected", Bool.not(valid("2024-01-01T00:00:00.Z")))
    Unit <- E.must("bad fraction rejected", Bool.not(valid("2024-01-01T00:00:00.1xZ")))
    Unit <- E.must("suffix rejected", Bool.not(valid("2024-01-01T00:00:00Zjunk")))
    Unit <- E.must_eq("date parts", tag_show(T.line_stamp("@account=a;time=2026-09-28T17:40:27.123Z :a!u@h PRIVMSG #x :text")), "2026-9-28 17:40:27")
    Unit <- E.must_eq("leading IRC spaces", tag_show(T.line_stamp("  @time=2026-09-28T17:40:27Z :a!u@h PRIVMSG #x :text")), "2026-9-28 17:40:27")
    Unit <- E.must_eq("leading spaces cannot bypass invalid tag", tag_show(T.line_stamp("  @time=garbageT11:22:33Z :a!u@h PRIVMSG #x :text")), "invalid")
    Unit <- E.must_eq("leading spaces cannot bypass duplicate tag", tag_show(T.line_stamp(" @time=2024-01-01T00:00:00Z;time=2024-01-01T01:00:00Z :s NOTICE me :text")), "invalid")
    Unit <- E.must_eq("no tag", tag_show(T.line_stamp(":a!u@h PRIVMSG #x :@time=2026-09-28T17:40:27Z")), "missing")
    Unit <- E.must_eq("other tag", tag_show(T.line_stamp("@other-time=bad :a!u@h PRIVMSG #x :text")), "missing")
    Unit <- E.must_eq("invalid tag", tag_show(T.line_stamp("@time=bad :a!u@h PRIVMSG #x :text")), "invalid")
    Unit <- E.must_eq("duplicate tag", tag_show(T.line_stamp("@time=2024-01-01T00:00:00Z;time=2024-01-01T01:00:00Z :s NOTICE me :text")), "invalid")
    IO.print("utc_time=ok")
