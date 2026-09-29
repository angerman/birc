# M16.4 IRCv3 +typing protocol and transient-state goldens.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/typing.bend as Ty
import ../../src/bend/session.bend as Sess
import ../../src/bend/view.bend as V
import ../../src/bend/frame.bend as Fr

def event_is_set(e: Maybe<&2, Irc.TypingEvent>, +nick: String, +target: String, paused: Bool) -> Bool:
  match e:
    case None{}:
      False{}
    case Some{Irc.TypingSet{+n, +t, st}}:
      match st:
        case Irc.TypingActive{}:
          String.eq(n, nick) && String.eq(t, target) && Bool.not(paused)
        case Irc.TypingPaused{}:
          String.eq(n, nick) && String.eq(t, target) && paused
        case Irc.TypingDone{}:
          False{}
    case Some{_}:
      False{}

def event_is_clear(e: Maybe<&2, Irc.TypingEvent>, +nick: String, +target: String) -> Bool:
  match e:
    case Some{Irc.TypingClear{+n, +t}}:
      String.eq(n, nick) && String.eq(t, target)
    case _:
      False{}

def event_is_clear_all(e: Maybe<&2, Irc.TypingEvent>, +nick: String) -> Bool:
  match e:
    case Some{Irc.TypingClearAll{+n}}:
      String.eq(n, nick)
    case _:
      False{}

def protocol_ok() -> Bool:
  event_is_set(Irc.typing_event("@+typing=active :alice!a@h TAGMSG #birc"), "alice", "#birc", False{})
    && event_is_set(Irc.typing_event("@time=x;+typing=paused :alice!a@h TAGMSG #birc"), "alice", "#birc", True{})
    && event_is_clear(Irc.typing_event("@+typing=done :alice!a@h TAGMSG #birc"), "alice", "#birc")
    && event_is_clear(Irc.typing_event(":alice!a@h PRIVMSG #birc :hello"), "alice", "#birc")
    && event_is_clear(Irc.typing_event(":alice!a@h NOTICE me :hello"), "alice", "alice")
    && event_is_clear(Irc.typing_event(":alice!a@h PART #birc :bye"), "alice", "#birc")
    && event_is_clear(Irc.typing_event(":op!o@h KICK #birc alice :bye"), "alice", "#birc")
    && event_is_clear_all(Irc.typing_event(":alice!a@h QUIT :bye"), "alice")
    && event_is_clear_all(Irc.typing_event(":alice!a@h NICK :alice2"), "alice")

def protocol_rejects_invalid() -> Bool:
  Maybe.is_none(&2, Irc.TypingEvent, Irc.typing_event("@typing=active :alice!a@h TAGMSG #birc"))
    && Maybe.is_none(&2, Irc.TypingEvent, Irc.typing_event("@+typing=active :alice!a@h PRIVMSG #birc :hello"))
    && Maybe.is_none(&2, Irc.TypingEvent, Irc.typing_event("@+typing=unknown :alice!a@h TAGMSG #birc"))

def active_expiry_ok() -> Bool:
  +s0 = Ty.empty()
  +s1 = Ty.apply_line(s0, "@+typing=active :alice!a@h TAGMSG #birc", 1000)
  Ty.has(Ty.expire(s1, 6999), "#birc", "alice")
    && Bool.not(Ty.has(Ty.expire(s1, 7000), "#birc", "alice"))

def paused_expiry_ok() -> Bool:
  +s0 = Ty.empty()
  +s1 = Ty.apply_line(s0, "@+typing=paused :alice!a@h TAGMSG #birc", 1000)
  Ty.has(Ty.expire(s1, 30999), "#birc", "alice")
    && Bool.not(Ty.has(Ty.expire(s1, 31000), "#birc", "alice"))

def done_and_message_ok() -> Bool:
  +s0 = Ty.apply_line(Ty.empty(), "@+typing=active :alice!a@h TAGMSG #birc", 1000)
  +s1 = Ty.apply_line(s0, "@+typing=done :alice!a@h TAGMSG #birc", 1100)
  +s2 = Ty.apply_line(Ty.empty(), "@+typing=active :alice!a@h TAGMSG #birc", 1000)
  +s3 = Ty.apply_line(s2, ":alice!a@h PRIVMSG #birc :muted text still clears", 1100)
  Bool.not(Ty.has(s1, "#birc", "alice")) && Bool.not(Ty.has(s3, "#birc", "alice"))

def refresh_and_wrap_ok() -> Bool:
  +s0 = Ty.apply_line(Ty.empty(), "@+typing=active :alice!a@h TAGMSG #birc", 4294965000)
  +s1 = Ty.apply_line(s0, "@+typing=active :alice!a@h TAGMSG #birc", 4294966000)
  Nat.is_eq(Ty.count(s1), 1n)
    && Ty.has(Ty.expire(s1, 4000), "#birc", "alice")
    && Bool.not(Ty.has(Ty.expire(s1, 4704), "#birc", "alice"))

def fill.go(n: Nat, +i: Nat, +s: Ty.State) -> Ty.State:
  match n:
    case 0n:
      s
    case 1n+p:
      fill.go(p, Nat.add(i, 1n), Ty.apply(s, Irc.TypingSet{"nick" ++ Nat.show(i), "#birc", Irc.TypingActive{}}, 1000))

def bound_ok() -> Bool:
  Nat.is_eq(Ty.count(fill.go(40n, 0n, Ty.empty())), Ty.MAX_TYPERS())

def list_has(+xs: List<&2, String>, +want: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+h, t}:
      String.eq(h, want) || list_has(t, want)

def capability_ok() -> Bool:
  +plain = Sess.handshake_lines("me", False{})
  +sasl = Sess.handshake_lines("me", True{})
  list_has(plain, "CAP LS 302")
    && list_has(plain, "CAP REQ :message-tags")
    && list_has(sasl, "CAP LS 302")
    && list_has(sasl, "CAP REQ :message-tags")

def view_ok() -> Bool:
  String.eq(V.typing_notice(Nil{}), "")
    && String.eq(V.typing_notice("alice" <> Nil{}), "alice is typing...")
    && String.eq(V.typing_notice("alice" <> "bob" <> Nil{}), "alice, bob are typing...")

def expired_session(pair: Sess.Session & Bool) -> Bool:
  match pair:
    case (+st, changed):
      changed && Bool.not(Ty.has(Sess.session_typing(st), "#birc", "alice"))

def session_path_ok() -> Bool:
  +s0 = Sess.session_online(Sess.session0("me", "irc.example", "#birc"))
  +s1 = Sess.st_of_chunk(Sess.step_on_chunk_ms(s0, Fr.string_to_octets(":me!m@h JOIN #birc\r\n"), 900))
  +s2 = Sess.st_of_keys(Sess.step_enter(s1, "/mute alice"))
  +s3 = Sess.st_of_chunk(Sess.step_on_chunk_ms(s2, Fr.string_to_octets("@+typing=active :alice!a@h TAGMSG #birc\r\n"), 1000))
  +s4 = Sess.st_of_chunk(Sess.step_on_chunk_ms(s3, Fr.string_to_octets(":alice!a@h PRIVMSG #birc :hidden\r\n"), 1100))
  Ty.has(Sess.session_typing(s3), "#birc", "alice")
    && list_has(Sess.session_typers(s3), "alice")
    && Bool.not(Ty.has(Sess.session_typing(s4), "#birc", "alice"))
    && expired_session(Sess.session_expire_typing(s3, 7000))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("protocol", protocol_ok())
    Unit <- E.must("protocol_rejects_invalid", protocol_rejects_invalid())
    Unit <- E.must("active_expiry", active_expiry_ok())
    Unit <- E.must("paused_expiry", paused_expiry_ok())
    Unit <- E.must("done_and_message", done_and_message_ok())
    Unit <- E.must("refresh_and_wrap", refresh_and_wrap_ok())
    Unit <- E.must("bound", bound_ok())
    Unit <- E.must("capability", capability_ok())
    Unit <- E.must("view", view_ok())
    Unit <- E.must("session_path", session_path_ok())
    IO.print("typing_demo=ok")
