# SPDX-License-Identifier: Apache-2.0
# IRCv3 standard replies: FAIL/WARN/NOTE route to the server log.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL

def server_text(+cl: Cl.Client) -> String:
  CL.buf_texts(cl, 0n)

def feed_fail_ok() -> Bool:
  +four = Feed.feed(Cl.init("me", "s"), ":s FAIL PRIVMSG BAD #c :gone")
  +three = Feed.feed(Cl.init("me", "s"), ":s FAIL PRIVMSG BAD :gone")
  String.eq(server_text(four), "FAIL PRIVMSG [BAD] (#c): gone|")
    && String.eq(server_text(three), "FAIL PRIVMSG [BAD]: gone|")

def feed_warn_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":s WARN PRIVMSG SLOW :Slow down")
  String.eq(server_text(cl), "WARN PRIVMSG [SLOW]: Slow down|")

def feed_note_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":s NOTE PRIVMSG ROUND #c :Next round")
  String.eq(server_text(cl), "NOTE PRIVMSG [ROUND] (#c): Next round|")

def feed_labeled_ok() -> Bool:
  +tagged = Feed.feed(Cl.init("me", "s"), "@label=birc-7 :s FAIL PRIVMSG BAD :gone")
  +empty = Feed.feed(Cl.init("me", "s"), "@label= :s FAIL PRIVMSG BAD :gone")
  +other = Feed.feed(Cl.init("me", "s"), "@time=x;label=zz :s NOTE P C :d")
  String.eq(server_text(tagged), "FAIL PRIVMSG [BAD]: gone [label=birc-7]|")
    && String.eq(server_text(empty), "FAIL PRIVMSG [BAD]: gone|")
    && String.eq(server_text(other), "NOTE P [C]: d [label=zz]|")

def feed_negotiated_ok() -> Bool:
  +cl = Feed.feed_with(Cl.init("me", "s"), Cl.dflt_cm(), Cl.dflt_types(), Cl.dflt_status(), Cl.dflt_sigils(), Cl.dflt_strip(), "@label=birc-7 :s WARN P C #c :slow")
  String.eq(server_text(cl), "WARN P [C] (#c): slow [label=birc-7]|")

def feed_malformed_ok() -> Bool:
  +arity2 = Feed.feed(Cl.init("me", "s"), ":s FAIL PRIVMSG :oops")
  +arity5 = Feed.feed(Cl.init("me", "s"), ":s FAIL A B C D :oops")
  +empty_desc = Feed.feed(Cl.init("me", "s"), ":s FAIL PRIVMSG BAD :")
  +ctl_desc = Feed.feed(Cl.init("me", "s"), ":s FAIL PRIVMSG BAD :" ++ SCon{Chr{7}, ""})
  String.contains(server_text(arity2), "FAIL PRIVMSG")
    && Bool.not(String.contains(server_text(arity2), "["))
    && String.contains(server_text(arity5), "FAIL A")
    && Bool.not(String.contains(server_text(arity5), "["))
    && String.contains(server_text(empty_desc), "FAIL PRIVMSG")
    && Bool.not(String.contains(server_text(empty_desc), "[BAD]"))
    && String.contains(server_text(ctl_desc), "FAIL PRIVMSG")
    && Bool.not(String.contains(server_text(ctl_desc), "[BAD]"))

def feed_forge_ok() -> Bool:
  +peer = Feed.feed(Cl.init("me", "s"), ":alice!u@h FAIL PRIVMSG BAD :Nope")
  +bare = Feed.feed(Cl.init("me", "s"), "FAIL PRIVMSG BAD :Nope")
  +peer_warn = Feed.feed(Cl.init("me", "s"), ":alice!u@h WARN P C :Nope")
  String.contains(server_text(peer), "FAIL PRIVMSG")
    && Bool.not(String.contains(server_text(peer), "[BAD]"))
    && String.contains(server_text(bare), "FAIL PRIVMSG")
    && Bool.not(String.contains(server_text(bare), "[BAD]"))
    && String.contains(server_text(peer_warn), "WARN P")
    && Bool.not(String.contains(server_text(peer_warn), "[C]"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("stdreply_laws", Irc.stdreply_laws_ok())
    Unit <- E.must("label_tag", Irc.label_tag_ok())
    Unit <- E.must("feed_fail", feed_fail_ok())
    Unit <- E.must("feed_warn", feed_warn_ok())
    Unit <- E.must("feed_note", feed_note_ok())
    Unit <- E.must("feed_labeled", feed_labeled_ok())
    Unit <- E.must("feed_negotiated", feed_negotiated_ok())
    Unit <- E.must("feed_malformed", feed_malformed_ok())
    Unit <- E.must("feed_forge", feed_forge_ok())
    IO.print("stdreply_demo=ok")
