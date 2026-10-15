# SPDX-License-Identifier: Apache-2.0
# Slice 2: IRCv3 extended-join + account-tag.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/cap_notify.bend as Cap

def server_text(+cl: Cl.Client) -> String:
  CL.buf_texts(cl, 0n)

def chan_text(+cl: Cl.Client) -> String:
  CL.buf_texts(cl, 1n)

# Another user's JOIN only renders when we share the channel (join does not
# create buffers for others), so the render cases start from a self-join.
def in_chan() -> Cl.Client:
  Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #chan")

# Classic 1-param JOIN still renders (old servers).
def join_classic_ok() -> Bool:
  +cl = Feed.feed(in_chan(), ":alice!u@h JOIN #chan")
  Nat.is_eq(CL.nbuf(cl), 2n)
    && String.contains(chan_text(cl), "alice joined #chan")
    && Bool.not(String.contains(server_text(cl), "JOIN"))

# Extended 3-param JOIN renders exactly like the classic form; the account
# and realname are accepted but not rendered or stored.
def join_extended_ok() -> Bool:
  +cl = Feed.feed(in_chan(), ":alice!u@h JOIN #chan alice123 :Alice Real")
  Nat.is_eq(CL.nbuf(cl), 2n)
    && String.contains(chan_text(cl), "alice joined #chan")
    && Bool.not(String.contains(chan_text(cl), "alice123"))
    && Bool.not(String.contains(chan_text(cl), "Alice Real"))

# A logged-out account ('*') renders the same.
def join_extended_star_ok() -> Bool:
  +cl = Feed.feed(in_chan(), ":alice!u@h JOIN #chan * :Alice Real")
  Nat.is_eq(CL.nbuf(cl), 2n)
    && String.contains(chan_text(cl), "alice joined #chan")

# A JOIN for a channel we never joined creates nothing and logs nothing.
def join_foreign_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":alice!u@h JOIN #chan")
  Nat.is_eq(CL.nbuf(cl), 1n) && String.is_empty(server_text(cl))

# Extended self JOIN still focuses the channel.
def join_self_extended_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":me!u@h JOIN #chan myacct :Me Real")
  Nat.is_eq(Cl.active_of(cl), 1n)
    && String.contains(chan_text(cl), "me joined #chan")

# 2-param JOIN is rejected to the unknown path: no channel buffer, the raw
# verb is logged on the server buffer, and no join line renders.
def join_arity2_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":alice!u@h JOIN #chan alice123")
  Nat.is_eq(CL.nbuf(cl), 1n)
    && Bool.not(CL.has_buf(cl, "#chan"))
    && String.contains(server_text(cl), "JOIN")
    && Bool.not(String.contains(server_text(cl), "joined"))

# 0-param and 4-param JOINs are rejected the same way.
def join_arity04_ok() -> Bool:
  +bare = Feed.feed(Cl.init("me", "s"), ":alice!u@h JOIN")
  +four = Feed.feed(Cl.init("me", "s"), ":alice!u@h JOIN #chan a b c")
  Nat.is_eq(CL.nbuf(bare), 1n) && String.contains(server_text(bare), "JOIN")
    && Nat.is_eq(CL.nbuf(four), 1n) && String.contains(server_text(four), "JOIN")
    && Bool.not(String.contains(server_text(four), "joined"))

# Negotiated (_with) path stays in parity with the fixed path.
def join_with.fed(+cl: Cl.Client, +line: String) -> Cl.Client:
  Feed.feed_with(cl, Cl.dflt_cm(), Cl.dflt_types(), Cl.dflt_status(), Cl.dflt_sigils(), Cl.dflt_strip(), line)

def join_with.chan() -> Cl.Client:
  join_with.fed(Cl.init("me", "s"), ":me!u@h JOIN #chan")

def join_with_parity_ok() -> Bool:
  +classic = join_with.fed(join_with.chan(), ":alice!u@h JOIN #chan")
  +ext = join_with.fed(join_with.chan(), ":alice!u@h JOIN #chan alice123 :Alice Real")
  +bad = join_with.fed(Cl.init("me", "s"), ":alice!u@h JOIN #chan alice123")
  String.contains(CL.buf_texts(classic, 1n), "alice joined #chan")
    && String.contains(CL.buf_texts(ext, 1n), "alice joined #chan")
    && Nat.is_eq(CL.nbuf(bad), 1n)
    && String.contains(CL.buf_texts(bad, 0n), "JOIN")

def account_hit(m: Maybe<&2, String>, +want: String) -> Bool:
  match m:
    case Some{+v}: String.eq(v, want)
    case None{}: False{}

def account_miss(m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}: True{}
    case _: False{}

# account-tag lookup: positive, first-hit-wins, missing, empty, and untagged.
def account_tag_ok() -> Bool:
  +hit = Irc.account_tag(Irc.raw_tags("@account=alice123;+typing=active :alice!u@h PRIVMSG #c :hi"))
  +first = Irc.account_tag("account=one;account=two")
  +miss = Irc.account_tag(Irc.raw_tags("@+typing=active :alice!u@h PRIVMSG #c :hi"))
  +empty = Irc.account_tag("account=")
  +plain = Irc.account_tag("")
  account_hit(hit, "alice123") && account_hit(first, "one")
    && account_miss(miss) && account_miss(empty) && account_miss(plain)

# Registry bits: off by default, ACK enables, hostile ACK never enables, DEL
# clears one bit, and the REQ wire lines are exact.
def cap_bits_ok() -> Bool:
  +off = Cap.caps0()
  +on = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :extended-join account-tag", True{})
  +spoof = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":alice!u@h CAP me ACK :extended-join", True{})
  +del = Cap.caps_apply_line(on, "s", "me", ":s CAP me DEL :extended-join", True{})
  Bool.not(Cap.extjoin_ok(off)) && Bool.not(Cap.acctag_ok(off))
    && Cap.extjoin_ok(on) && Cap.acctag_ok(on)
    && Bool.not(Cap.extjoin_ok(spoof))
    && Bool.not(Cap.extjoin_ok(del)) && Cap.acctag_ok(del)
    && String.eq(Irc.format_cap_req(Cap.CAP_EXTJOIN()), "CAP REQ :extended-join")
    && String.eq(Irc.format_cap_req(Cap.CAP_ACCTAG()), "CAP REQ :account-tag")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("cap_end_owner", Cap.cap_end_single_owner_ok())
    Unit <- E.must("caps_ack_only", Cap.caps_ack_only_ok())
    Unit <- E.must("caps_parse", Cap.caps_parse_ok())
    Unit <- E.must("caps_removal", Cap.caps_removal_ok())
    Unit <- E.must("join_classic", join_classic_ok())
    Unit <- E.must("join_foreign", join_foreign_ok())
    Unit <- E.must("join_extended", join_extended_ok())
    Unit <- E.must("join_extended_star", join_extended_star_ok())
    Unit <- E.must("join_self_extended", join_self_extended_ok())
    Unit <- E.must("join_arity2", join_arity2_ok())
    Unit <- E.must("join_arity04", join_arity04_ok())
    Unit <- E.must("join_with_parity", join_with_parity_ok())
    Unit <- E.must("account_tag", account_tag_ok())
    Unit <- E.must("cap_bits", cap_bits_ok())
    IO.print("extended_join=ok")
