# SPDX-License-Identifier: Apache-2.0
# Slice 3: IRCv3 labeled-response (attach + surface only).
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/session.bend as Sess
import ../../src/bend/cap_notify.bend as Cap
import ../../src/bend/submit.bend as Sub

def server_text(+cl: Cl.Client) -> String:
  CL.buf_texts(cl, 0n)

# Own REQ line only: the wanted union is integrator-owned, so this demo
# asserts its line via the wire-format owner, never via wanted.
def cap_line_ok() -> Bool:
  String.eq(Cap.CAP_LABELED(), "labeled-response")
    && String.eq(Irc.format_cap_req(Cap.CAP_LABELED()), "CAP REQ :labeled-response")

def bit_ok() -> Bool:
  +on = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :labeled-response", True{})
  +nak = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NAK :labeled-response", True{})
  +del = Cap.caps_apply_line(on, "s", "me", ":s CAP me DEL :labeled-response", True{})
  Bool.not(Cap.labeled_ok(Cap.caps0()))
    && Cap.labeled_ok(on)
    && Bool.not(Cap.labeled_ok(nak))
    && Bool.not(Cap.labeled_ok(del))

# Hostile post-register `CAP * ACK` must not enable (trust gate reuse).
def hostile_ok() -> Bool:
  +star = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * ACK :labeled-response", True{})
  +spoof = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":alice!u@h CAP me ACK :labeled-response", True{})
  Bool.not(Cap.labeled_ok(star)) && Bool.not(Cap.labeled_ok(spoof))

def ack_feed_ok() -> Bool:
  +bare = Feed.feed(Cl.init("me", "s"), ":s ACK")
  +labeled = Feed.feed(Cl.init("me", "s"), "@label=abc :s ACK")
  +tagged_ctx = Feed.feed(Cl.init("me", "s"), "@label=abc :s ACK #c")
  +bad = Feed.feed(Cl.init("me", "s"), ":s ACK a b c")
  String.contains(server_text(bare), "acknowledged")
    && String.contains(server_text(labeled), "acknowledged abc")
    && String.contains(server_text(tagged_ctx), "acknowledged abc")
    && String.contains(server_text(bad), "ACK")
    && Bool.not(String.contains(server_text(bad), "acknowledged"))

def ack_with_ok() -> Bool:
  +fixed = Feed.feed(Cl.init("me", "s"), "@label=abc :s ACK")
  +neg = Feed.feed_with(Cl.init("me", "s"), Cl.dflt_cm(), Cl.dflt_types(), Cl.dflt_status(), Cl.dflt_sigils(), Cl.dflt_strip(), "@label=abc :s ACK")
  +neg_bad = Feed.feed_with(Cl.init("me", "s"), Cl.dflt_cm(), Cl.dflt_types(), Cl.dflt_status(), Cl.dflt_sigils(), Cl.dflt_strip(), ":s ACK a b c")
  String.eq(server_text(fixed), server_text(neg))
    && String.contains(server_text(neg_bad), "ACK")
    && Bool.not(String.contains(server_text(neg_bad), "acknowledged"))

# Counter increments and survives unrelated Session ops (set_reg here).
def counter_fourth(p4: Sess.Session & String, +l1: String, +l2: String) -> Bool:
  match p4:
    case (+st4, +l4):
      String.eq(l1, "birc-0")
        && String.eq(l2, "birc-1")
        && String.eq(l4, "birc-2")
        && Nat.is_eq(Sess.session_labels(st4), 3n)

def counter_third(p2: Sess.Session & String, +l1: String) -> Bool:
  match p2:
    case (+st2, +l2):
      counter_fourth(Sess.session_next_label(Sess.session_set_reg(st2, Cap.reg0())), l1, l2)

def counter_second(p1: Sess.Session & String) -> Bool:
  match p1:
    case (+st1, +l1):
      counter_third(Sess.session_next_label(st1), l1)

def counter_ok() -> Bool:
  counter_second(Sess.session_next_label(Sess.session0("me", "s", "#c")))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("cap_line", cap_line_ok())
    Unit <- E.must("bit", bit_ok())
    Unit <- E.must("hostile", hostile_ok())
    Unit <- E.must("caps_ack_only", Cap.caps_ack_only_ok())
    Unit <- E.must("label_wire", Irc.label_wire_ok())
    Unit <- E.must("labeled_send", Sub.labeled_wire_ok())
    Unit <- E.must("ack_feed", ack_feed_ok())
    Unit <- E.must("ack_with", ack_with_ok())
    Unit <- E.must("counter", counter_ok())
    IO.print("labeled_response=ok")
