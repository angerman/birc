import Base
import ./expect.bend as E
import ../../src/bend/clock.bend as Clock
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed

def stamp(got: Maybe<&2, String>) -> String:
  match got:
    case None{}: "missing"
    case Some{value}: value

def last_stamp(lines: List<&2, Cl.Line>, fallback: String) -> String:
  match lines:
    case Nil{}: fallback
    case Con{Cl.Line{_, ts, _, _, _}, rest}: last_stamp(rest, ts)

def message_stamp(+line: String, value: Maybe<&2, String>) -> String:
  last_stamp(Cl.active_buf_lines(Cl.set_active(Feed.feed_at(Cl.set_now(Cl.init("me", "irc"), "10:00:00"), line, value), 1n)), "none")

def joined() -> Cl.Client:
  Feed.feed_at(Cl.set_now(Cl.init("me", "irc"), "10:00:00"), "@time=2026-09-28T17:40:27.123Z :me!u@h JOIN #time", Some{"02:40:27"})

def receipt(cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, _, _, now, _, _, _, _}: now

def main() -> IO(Unit):
  +wire : String = "@time=2026-09-28T17:40:27.123Z :alice!u@h PRIVMSG me :hello"
  do IO<Unit>:
    local : Maybe<&2, String> <- Clock.line_stamp(wire)
    Unit <- E.must_eq("date-aware Seoul conversion", stamp(local), "2026-09-29 (Tuesday)|02:40:27")
    spaced : Maybe<&2, String> <- Clock.line_stamp(" " ++ wire)
    Unit <- E.must_eq("leading spaces still convert to local time", stamp(spaced), "2026-09-29 (Tuesday)|02:40:27")
    Unit <- E.must_eq("explicit local log override", message_stamp(wire, Some{"02:40:27"}), "02:40:27")
    Unit <- E.must_eq("pure parser unchanged", message_stamp(wire, None{}), "17:40:27")
    Unit <- E.must_eq("invalid time receipt fallback", message_stamp(wire, Some{""}), "10:00:00")
    Unit <- E.must_eq("JOIN uses event-local time", last_stamp(Cl.active_buf_lines(joined()), "none"), "02:40:27")
    Unit <- E.must_eq("event time does not replace receipt clock", receipt(joined()), "10:00:00")
    invalid : Maybe<&2, String> <- Clock.line_stamp("@time=bad :alice!u@h PRIVMSG me :hello")
    Unit <- E.must_eq("invalid tag override", stamp(invalid), "")
    spaced_invalid : Maybe<&2, String> <- Clock.line_stamp(" @time=garbageT11:22:33Z :alice!u@h PRIVMSG me :hello")
    Unit <- E.must_eq("leading spaces still invalidate malformed tag", stamp(spaced_invalid), "")
    missing : Maybe<&2, String> <- Clock.line_stamp(":alice!u@h PRIVMSG me :@time=bad")
    Unit <- E.must_eq("untagged unchanged", stamp(missing), "missing")
    leap : Maybe<&2, String> <- Clock.line_stamp("@time=2012-06-30T23:59:60.419Z :alice!u@h PRIVMSG me :hello")
    Unit <- E.must_eq("leap second", stamp(leap), "2012-07-01 (Sunday)|08:59:60")
    Unit <- E.must_eq("stamp_join keeps one civil+sod snapshot", Clock.stamp_join(20261020, 2, 3661), "2026-10-20 (Tuesday)|01:01:01")
    Unit <- E.must_eq("stamp_join fails closed on zero civil", Clock.stamp_join(0, 0, 1), "")
    Unit <- E.must_eq("hhmmss formats sod from the shared clock path", Clock.fmt_sod(3661), "01:01:01")
    Unit <- E.must_eq("buffer strip defaults match sigils+extra", Cl.dflt_strip(), "@+~&%")
    IO.print("clock_local_demo=ok")
