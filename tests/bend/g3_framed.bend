# SPDX-License-Identifier: Apache-2.0
# G3 framed-regression guards: styled wire atoms normalize at identity,
# privacy, mention, media, and membership sites. Chat and history keep
# their original nonsecret styled bytes; only secrets, identity matching,
# and boundary-aware fetches change.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ./mode_view_guard.bend as ModeView
import ../../src/bend/history.bend as H
import ../../src/bend/frame.bend as F
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as S
import ../../src/bend/media.bend as M
import ../../src/bend/join_plan.bend as JP

def ctl(+n: U32, +s: String) -> String:
  SCon{Chr{n}, s}

def secret() -> String:
  "opaque-secret"

def passw() -> String:
  "synthetic-password"

def base() -> Cl.Client:
  Feed.feed(Cl.init("me", "irc"), ":me!u@h JOIN #room")

# ---- (1) framed MODE / 324 key privacy -------------------------------------
def mode_private(+wire: String) -> Bool:
  +cl = Feed.feed(base(), wire)
  Bool.not(String.contains(CL.buf_texts(cl, 0n) ++ CL.buf_texts(cl, 1n), secret()))
    && Bool.not(String.contains(H.extract_new_history_for("irc:6697", base(), cl), secret()))

def mode_visible(+wire: String, +want: String) -> Bool:
  String.contains(CL.buf_texts(Feed.feed(base(), wire), 1n), want)

# ---- (2) styled credential echoes -------------------------------------------
def echo_cl(+line: String) -> Cl.Client:
  S.session_cl(S.st_of_chunk(S.step_on_chunk_ms(
    S.session_online(S.session_with_client(Cl.init("me", "irc"), "#room")),
    F.string_to_octets(line ++ "\r\n"), 1000)))

def echo_suppressed(+line: String) -> Bool:
  +after = echo_cl(line)
  Nat.is_eq(CL.nbuf(after), 1n)
    && Bool.not(String.contains(CL.buf_texts(after, 0n), passw()))
    && Bool.not(String.contains(H.extract_new_history_for("irc:6667", Cl.init("me", "irc"), after), passw()))

# ---- (3) boundary-aware media ------------------------------------------------
def img() -> String:
  "https://x.test/a.png"

# ---- (4) styled mentions ------------------------------------------------------
def joined() -> Cl.Client:
  Feed.feed(Cl.init("me", "s"), ":me!m@h JOIN #birc")

def fed(+body: String) -> Cl.Client:
  Feed.feed(joined(), ":alice!a@h PRIVMSG #birc :" ++ body)

def mention_hit(+body: String) -> Bool:
  U32.is_eq(Cl.client_bell_seq(fed(body)), 1)

def mention_miss(+body: String) -> Bool:
  U32.is_eq(Cl.client_bell_seq(fed(body)), 0)

def mention_bytes(+body: String) -> Bool:
  +cl = fed(body)
  String.contains(CL.buf_texts(cl, 1n), body)
    && String.contains(H.extract_new_history_for("s:6667", joined(), cl), body)

# ---- (5) styled self-KICK ------------------------------------------------------
def kick_client(+wire: String) -> Cl.Client:
  Feed.feed_all(Cl.init("me", "s"), ":me!m@h JOIN #room" <> wire <> Nil{})

def kick_intent(+wire: String) -> String:
  String.join(JP.desired_names(JP.received(JP.initial("#room"), Cl.init("me", "s"), wire)), ",")

def self_kick_clears(+wire: String) -> Bool:
  +cl = kick_client(wire)
  Bool.not(CL.has_buf(cl, "#room")) && Nat.is_eq(CL.nbuf(cl), 1n) && String.eq(kick_intent(wire), "")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("styled mode flags never persist a key", mode_private(":alice!u@h MODE #room +" ++ ctl(2, "k") ++ " " ++ secret()))
    Unit <- E.must("styled mode channel never persists a key", mode_private(":alice!u@h MODE #ro" ++ ctl(2, "om") ++ " +k " ++ secret()))
    Unit <- E.must("soh-framed mode channel never persists a key", mode_private(":alice!u@h MODE #ro" ++ ctl(1, "om") ++ " +k " ++ secret()))
    Unit <- E.must("styled 324 flags never persist a key", mode_private(":irc 324 me #room +" ++ ctl(2, "k") ++ " " ++ secret()))
    Unit <- E.must("styled 324 channel never persists a key", mode_private(":irc 324 me #ro" ++ ctl(2, "om") ++ " +k " ++ secret()))
    Unit <- E.must_eq("MODE styled source preserves bold byte", ModeView.stored(Feed.feed(base(), ":alice!u@h MODE #ro" ++ ctl(2, "om") ++ " +o bob")), "alice MODE #ro" ++ ctl(2, "om") ++ " +o bob")
    Unit <- E.must_eq("MODE styled View keeps visible text", ModeView.visible(Feed.feed(base(), ":alice!u@h MODE #ro" ++ ctl(2, "om") ++ " +o bob")), "alice MODE #room +o bob")
    Unit <- E.must_eq("MODE ordinary View keeps visible text", ModeView.visible(Feed.feed(base(), ":alice!u@h MODE #room +o bob")), "alice MODE #room +o bob")
    Unit <- E.must_eq("MODE hostile ESC does not enter stored source", ModeView.stored(Feed.feed(base(), ":alice!u@h MODE #ro" ++ ctl(27, "om") ++ " +o bob")), "alice MODE #room +o bob")
    Unit <- E.must_eq("MODE hostile ESC does not enter View text", ModeView.visible(Feed.feed(base(), ":alice!u@h MODE #ro" ++ ctl(27, "om") ++ " +o bob")), "alice MODE #room +o bob")
    Unit <- E.must("ordinary mode key stays redacted", mode_private(":alice!u@h MODE #room +k " ++ secret()))
    Unit <- E.must("ordinary mode still renders", mode_visible(":alice!u@h MODE #room +o bob", "alice MODE #room +o bob"))
    Unit <- E.must("styled non-key mode still renders", mode_visible(":alice!u@h MODE #ro" ++ ctl(2, "om") ++ " +o bob", "alice MODE #ro" ++ ctl(2, "om") ++ " +o bob"))
    Unit <- E.must("styled self author echo suppressed", echo_suppressed(":me" ++ ctl(2, "") ++ "!u@h PRIVMSG NickServ :IDENTIFY " ++ passw()))
    Unit <- E.must("soh self author echo suppressed", echo_suppressed(":me" ++ ctl(1, "") ++ "!u@h PRIVMSG NickServ :IDENTIFY " ++ passw()))
    Unit <- E.must("infixed credential verb echo suppressed", echo_suppressed(":me!u@h PRIVMSG NickServ :IDENTI" ++ ctl(2, "FY") ++ " " ++ passw()))
    Unit <- E.must("soh-infixed credential verb echo suppressed", echo_suppressed(":me!u@h PRIVMSG NickServ :IDENTI" ++ ctl(1, "FY") ++ " " ++ passw()))
    Unit <- E.must("ordinary self echo stays suppressed", echo_suppressed(":me!u@h PRIVMSG NickServ :IDENTIFY " ++ passw()))
    Unit <- E.must("peer ordinary IDENTIFY remains chat", String.contains(CL.buf_texts(echo_cl(":alice!u@h PRIVMSG me :IDENTIFY " ++ passw()), 1n), passw()))
    Unit <- E.must_eq("soh-scheme glue never autofetches", String.join(M.targets("htt" ++ ctl(1, "ps://x.test/a.png")), ","), "")
    Unit <- E.must_eq("style-infixed url never autofetches", String.join(M.targets("https://x.test/a" ++ ctl(2, ".png")), ","), "")
    Unit <- E.must_eq("genuine styled image still fetches", String.join(M.targets("pic " ++ ctl(2, img()) ++ " end"), ","), img())
    Unit <- E.must_eq("ordinary image still fetches", String.join(M.targets("pic " ++ img() ++ " end"), ","), img())
    Unit <- E.must_eq("color-wrapped image still fetches", String.join(M.targets("see " ++ ctl(3, "04" ++ img()) ++ " end"), ","), img())
    Unit <- E.must_eq("open agrees on soh-scheme glue", String.join(Sub.extract_urls("htt" ++ ctl(1, "ps://x.test/a.png")), ","), "")
    Unit <- E.must_eq("open agrees on genuine styled image", String.join(Sub.extract_urls("pic " ++ ctl(2, img()) ++ " end"), ","), img())
    Unit <- E.must("styled nick mention hits", mention_hit("hi m" ++ ctl(2, "e")))
    Unit <- E.must("styled continuation is not a mention", mention_miss("me" ++ ctl(2, "ow")))
    Unit <- E.must("color-split nick mention hits", mention_hit("hi m" ++ ctl(3, "04e")))
    Unit <- E.must("color-split continuation is not a mention", mention_miss("me" ++ ctl(3, "04ow")))
    Unit <- E.must("reset-split nick mention hits", mention_hit("hi m" ++ ctl(15, "e")))
    Unit <- E.must("reset-split continuation is not a mention", mention_miss("me" ++ ctl(15, "ow")))
    Unit <- E.must("ordinary mention still hits", mention_hit("hi me"))
    Unit <- E.must("ordinary continuation still misses", mention_miss("hi meow"))
    Unit <- E.must("styled mention source stays byte-identical", mention_bytes("hi m" ++ ctl(2, "e")))
    Unit <- E.must("styled self-kick victim clears membership and intent", self_kick_clears(":op!u@h KICK #room me" ++ ctl(2, "") ++ " :bye"))
    Unit <- E.must("soh self-kick victim clears membership and intent", self_kick_clears(":op!u@h KICK #room me" ++ ctl(1, "") ++ " :bye"))
    Unit <- E.must("styled self-kick channel clears membership and intent", self_kick_clears(":op!u@h KICK #ro" ++ ctl(2, "om") ++ " me :bye"))
    Unit <- E.must("soh self-kick channel clears membership and intent", self_kick_clears(":op!u@h KICK #ro" ++ ctl(1, "om") ++ " me :bye"))
    Unit <- E.must("ordinary self-kick still clears", self_kick_clears(":op!u@h KICK #room me :bye"))
    Unit <- E.must("peer kick keeps membership", CL.has_buf(kick_client(":op!u@h KICK #room alice :bye"), "#room"))
    Unit <- E.must_eq("peer kick preserves intent", kick_intent(":op!u@h KICK #room alice :bye"), "#room")
    Unit <- E.must_eq("styled peer kick preserves intent", kick_intent(":op!u@h KICK #room alice" ++ ctl(2, "") ++ " :bye"), "#room")
    IO.print("g3_framed=ok")
