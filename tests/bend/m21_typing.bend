# SPDX-License-Identifier: Apache-2.0
# Session routes typing with the same resident channel identity as chat.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as S
import ../../src/bend/typing.bend as T
import ../../src/bend/irc.bend as I
import ../../src/bend/frame.bend as F

def chunk(st: S.Session, text: String) -> S.Session:
  S.st_of_chunk(S.step_on_chunk_ms(st, F.string_to_octets(text), 1000))

def base() -> S.Session:
  chunk(S.session_online(S.session0("me", "irc", "#room")),
    ":me!u@h JOIN #room\r\n:me!u@h JOIN +#room\r\n")

def seeded(st: S.Session) -> S.Session:
  match st:
    case S.Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, _, port, media, plan, edits, +iso, +hlbox, +cf, +regbox, +theme, labelsbox, +pends}:
      S.Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split,
        T.apply(T.apply(T.empty(), I.TypingSet{"alice", "#room", I.TypingActive{}}, 1000),
          I.TypingSet{"alice", "+#room", I.TypingActive{}}, 1000), port, media, plan, edits, iso, hlbox, cf, regbox, theme, labelsbox, pends}

def actual_set_ok() -> Bool:
  +st = chunk(base(), "@+typing=active :alice!u@h TAGMSG +#room\r\n")
  T.has(S.session_typing(st), "+#room", "alice")
    && Bool.not(T.has(S.session_typing(st), "#room", "alice"))

def clears_actual(+command: String) -> Bool:
  +st = chunk(seeded(base()), command)
  Bool.not(T.has(S.session_typing(st), "+#room", "alice"))
    && T.has(S.session_typing(st), "#room", "alice")

def actual_clears_ok() -> Bool:
  clears_actual("@+typing=done :alice!u@h TAGMSG +#room\r\n")
    && clears_actual(":alice!u@h PRIVMSG +#room :hello\r\n")
    && clears_actual(":alice!u@h NOTICE +#room :hello\r\n")
    && clears_actual(":alice!u@h PART +#room :bye\r\n")
    && clears_actual(":op!u@h KICK +#room alice :bye\r\n")

def status_ok() -> Bool:
  +joined = chunk(S.session_online(S.session0("me", "irc", "#room")), ":me!u@h JOIN #room\r\n")
  +active = chunk(joined, "@+typing=active :alice!u@h TAGMSG +#room\r\n")
  +paused = chunk(joined, "@+typing=paused :alice!u@h TAGMSG @#room\r\n")
  T.has(S.session_typing(active), "#room", "alice")
    && Bool.not(T.has(S.session_typing(active), "+#room", "alice"))
    && T.has(S.session_typing(paused), "#room", "alice")
    && Bool.not(T.has(S.session_typing(chunk(active, ":alice!u@h PRIVMSG +#room :hello\r\n")), "#room", "alice"))
    && Bool.not(T.has(S.session_typing(chunk(paused, ":alice!u@h NOTICE @#room :hello\r\n")), "#room", "alice"))

def unknown_membership_ok() -> Bool:
  +joined = chunk(S.session_online(S.session0("me", "irc", "#room")), ":me!u@h JOIN #room\r\n")
  +active = seeded(joined)
  T.has(S.session_typing(chunk(active, ":alice!u@h PART +#room :bye\r\n")), "#room", "alice")
    && T.has(S.session_typing(chunk(active, ":op!u@h KICK +#room alice :bye\r\n")), "#room", "alice")

def same_chunk_ok() -> Bool:
  +st = chunk(S.session_online(S.session0("me", "irc", "#room")),
    ":me!u@h JOIN #room\r\n:me!u@h JOIN +#room\r\n@+typing=active :alice!u@h TAGMSG +#room\r\n")
  T.has(S.session_typing(st), "+#room", "alice")
    && Bool.not(T.has(S.session_typing(st), "#room", "alice"))
    && Bool.not(T.has(S.session_typing(chunk(st, ":alice!u@h PART +#room :bye\r\n")), "+#room", "alice"))

def private_ok() -> Bool:
  +joined = chunk(base(), ":alice!u@h PRIVMSG me :hello\r\n")
  +active = chunk(joined, "@+typing=active :alice!u@h TAGMSG me\r\n")
  T.has(S.session_typing(active), "alice", "alice")
    && Bool.not(T.has(S.session_typing(chunk(active, ":alice!u@h PRIVMSG me :done\r\n")), "alice", "alice"))

def depart_rejoin_ok() -> Bool:
  +st = chunk(seeded(base()), ":me!u@h PART +#room :bye\r\n:me!u@h JOIN +#room\r\n")
  Bool.not(T.has(S.session_typing(st), "+#room", "alice"))
    && T.has(S.session_typing(st), "#room", "alice")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("typing actual channel", actual_set_ok())
    Unit <- E.must("typing actual clears preserve ordinary channel", actual_clears_ok())
    Unit <- E.must("typing STATUSMSG controls", status_ok())
    Unit <- E.must("typing membership targets are not audiences", unknown_membership_ok())
    Unit <- E.must("typing follows same-chunk JOIN context", same_chunk_ok())
    Unit <- E.must("typing private control", private_ok())
    Unit <- E.must("typing departs before same-chunk rejoin", depart_rejoin_ok())
    IO.print("m21_typing=ok")
