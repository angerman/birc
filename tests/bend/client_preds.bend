# Uncited client *_ok predicates. Laws keep the ones LAWS.bend names.
import Base
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL

def ieq_rfc1459_ok() -> Bool:
  Irc.ieq("foo[]", "foo{}") && Irc.ieq("A\\B", "a|b")

def scroll_clamp_ok() -> Bool:
  +cl0 = Cl.set_active(Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #birc"), 1n)
  +cl1 = Cl.apply_active_scroll(cl0, 50n, 0n)
  Nat.is_eq(Cl.buf_scroll_of(cl1, 1n), CL.buf_nlines(cl1, 1n))

def bare_join_ok() -> Bool:
  Nat.is_eq(CL.nbuf(Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN")), 1n)

def statusmsg_ok() -> Bool:
  +cl = Feed.feed_all(
    Cl.init("me", "s"),
    ":me!me@localhost JOIN #birc" <> ":op!u@h PRIVMSG @#birc :ops" <> Nil{})
  Nat.is_eq(CL.nbuf(cl), 2n) && CL.has_buf(cl, "#birc") && Bool.not(CL.has_buf(cl, "@#birc")) && Nat.is_eq(CL.buf_nlines(cl, 1n), 2n)

def notice_auth_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":irc NOTICE AUTH :hi")
  Nat.is_eq(CL.nbuf(cl), 1n) && Nat.is_eq(CL.buf_nlines(cl, 0n), 1n)

def numeric_last_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":irc.example.net 403 me #nope :No such channel")
  String.eq(CL.buf_texts(cl, 0n), "[403] No such channel|")

# After registration, 433 me newnick is a rejected /nick: stay me, only log.
def nick433_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":irc.example.net 433 me newnick :Nickname is already in use")
  String.eq(Cl.nick_of(cl), "me") && String.eq(CL.buf_texts(cl, 0n), "[433] Nickname is already in use|")

# Registration: 433 * me and 433 me me mean our nick is taken; retry as me_.
def nick433_star_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":irc.example.net 433 * me :Nickname is already in use")
  String.eq(Cl.nick_of(cl), "me_") && String.eq(CL.buf_texts(cl, 0n), "[433] Nickname is already in use|")

def nick433_same_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":irc.example.net 433 me me :Nickname is already in use")
  String.eq(Cl.nick_of(cl), "me_") && String.eq(CL.buf_texts(cl, 0n), "[433] Nickname is already in use|")

def nick437_star_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":irc.example.net 437 * me :Nick/channel is temporarily unavailable")
  String.eq(Cl.nick_of(cl), "me_") && String.eq(CL.buf_texts(cl, 0n), "[437] Nick/channel is temporarily unavailable|")
