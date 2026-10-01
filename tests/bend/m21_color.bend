# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/frame.bend as Fr
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL

def framed.got(pair: List<&2, String> & List<&2, U32> & Bool) -> String:
  match pair:
    case (lines, _, _): CL.buf_texts(Feed.feed_all(Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #t"), lines), 1n)

def framed(+body: String) -> String:
  framed.got(Fr.push_ex(False{}, Nil{}, Fr.string_to_octets(":alice!u@h PRIVMSG #t :" ++ body ++ "\r\n")))

def color(text: String) -> String:
  SCon{Chr{3}, text}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("foreground comma without background digit is text", Irc.sanitize_in(color("4,hello")), ",hello")
    Unit <- E.must_eq("two foreground digits and terminal comma", Irc.sanitize_in(color("04,")), ",")
    Unit <- E.must_eq("valid background digits removed", Irc.sanitize_in(color("04,12hello")), "hello")
    Unit <- E.must_eq("no foreground comma remains text", Irc.sanitize_in(color(",hello")), ",hello")
    Unit <- E.must_eq("ordinary comma unchanged", Irc.sanitize_in("a,b"), "a,b")
    Unit <- E.must("live framed path preserves literal comma", String.contains(framed(color("4,hello")), "<alice> ,hello"))
    Unit <- E.must("live framed valid color remains stripped", String.contains(framed(color("4,5hello")), "<alice> hello"))
    IO.print("m21_color=ok")
