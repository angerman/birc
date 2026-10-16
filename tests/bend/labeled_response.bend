# SPDX-License-Identifier: Apache-2.0
# Slice 3: IRCv3 labeled-response (live sends attach labels; ACK stays visual).
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
  +neg = Feed.feed_with(Cl.init("me", "s"), Cl.Iso.defaults(), "@label=abc :s ACK")
  +neg_bad = Feed.feed_with(Cl.init("me", "s"), Cl.Iso.defaults(), ":s ACK a b c")
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

def chan0() -> Cl.Client:
  Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #c")

def labeled_reg() -> Cap.Reg:
  Cap.Reg{Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :labeled-response", True{}), Cap.out0()}

def labeled_session() -> Sess.Session:
  Sess.session_set_reg(Sess.session_demo(chan0(), "#c"), labeled_reg())

def plain_session() -> Sess.Session:
  Sess.session_demo(chan0(), "#c")

def trip_st(t: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match t:
    case (st, _, _): st

def trip_outs(t: Sess.Session & Sess.NetCmd & Bool) -> List<&2, String>:
  match t:
    case (_, cmd, _):
      match cmd:
        case Sess.Cont{+xs}: xs
        case _: Nil{}

def trip_wire(t: Sess.Session & Sess.NetCmd & Bool) -> String:
  String.join(trip_outs(t), "|")

def live_wire(+st: Sess.Session, +text: String) -> String:
  trip_wire(Sess.step_enter(st, text))

def live_outs(+st: Sess.Session, +text: String) -> List<&2, String>:
  trip_outs(Sess.step_enter(st, text))

def live_labels(+st: Sess.Session, +text: String) -> Nat:
  Sess.session_labels(trip_st(Sess.step_enter(st, text)))

def outs_fit(+xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, +t}: Irc.line_ok(h) && outs_fit(t)

def session_gate_ok() -> Bool:
  Bool.not(Sess.session_labeled_ok(Sess.session0("me", "s", "#c")))
    && Sess.session_labeled_ok(labeled_session())

# Live send mints birc-0 and tags while negotiated.
def live_first_ok() -> Bool:
  String.eq(live_wire(labeled_session(), "hello"), "@label=birc-0 PRIVMSG #c :hello")
    && outs_fit(live_outs(labeled_session(), "hello"))
    && Nat.is_eq(live_labels(labeled_session(), "hello"), 1n)

# Counter consumed per send: the next send mints birc-1.
def live_second_ok() -> Bool:
  +st1 = trip_st(Sess.step_enter(labeled_session(), "hello"))
  String.eq(live_wire(st1, "again"), "@label=birc-1 PRIVMSG #c :again")
    && outs_fit(live_outs(st1, "again"))
    && Nat.is_eq(live_labels(st1, "again"), 2n)

# NOTICE shares the labeled path.
def live_notice_ok() -> Bool:
  String.eq(live_wire(labeled_session(), "/notice #c hi"), "@label=birc-0 NOTICE #c :hi")
    && outs_fit(live_outs(labeled_session(), "/notice #c hi"))
    && Nat.is_eq(live_labels(labeled_session(), "/notice #c hi"), 1n)

# Multiline mints once per wire, in order.
def live_multiline_ok() -> Bool:
  String.eq(live_wire(labeled_session(), "aa\nbb"), "@label=birc-0 PRIVMSG #c :aa|@label=birc-1 PRIVMSG #c :bb")
    && outs_fit(live_outs(labeled_session(), "aa\nbb"))
    && Nat.is_eq(live_labels(labeled_session(), "aa\nbb"), 2n)

# Unnegotiated sessions emit the plain wire (mint still consumed per send).
def live_untagged_ok() -> Bool:
  String.eq(live_wire(plain_session(), "hello"), "PRIVMSG #c :hello")
    && outs_fit(live_outs(plain_session(), "hello"))
    && Nat.is_eq(live_labels(plain_session(), "hello"), 1n)

# Non-message wires pass through untouched without minting.
def live_join_untouched_ok() -> Bool:
  String.eq(live_wire(labeled_session(), "/join #x"), "JOIN #x")
    && Nat.is_eq(live_labels(labeled_session(), "/join #x"), 0n)

def long_body.go(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "x" ++ long_body.go(p)

# Downgrade: negotiated but tagged-overlong emits the plain fitting wire.
def live_downgrade_ok() -> Bool:
  +body = long_body.go(490n)
  String.eq(live_wire(labeled_session(), body), "PRIVMSG #c :" ++ body)
    && outs_fit(live_outs(labeled_session(), body))
    && Nat.is_eq(live_labels(labeled_session(), body), 1n)

# ACK correlation stays visual-only: the minted label renders back, and an
# unknown label renders too (no registry lookup, no wire effect).
def live_ack_ok() -> Bool:
  +cl = Sess.session_cl(trip_st(Sess.step_enter(labeled_session(), "hello")))
  fed = Feed.feed(cl, "@label=birc-0 :s ACK")
  stray = Feed.feed(cl, "@label=birc-99 :s ACK")
  String.contains(server_text(fed), "acknowledged birc-0")
    && String.contains(server_text(stray), "acknowledged birc-99")

# Client-only paths stay unlabeled.
def client_outs(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, +xs): String.join(xs, "|")

def client_unlabeled_ok() -> Bool:
  String.eq(client_outs(Sub.submit(chan0(), "hello")), "PRIVMSG #c :hello")
    && String.eq(client_outs(Sub.submit(chan0(), "/notice #c hi")), "NOTICE #c :hi")

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
    Unit <- E.must("session_gate", session_gate_ok())
    Unit <- E.must("live_first", live_first_ok())
    Unit <- E.must("live_second", live_second_ok())
    Unit <- E.must("live_notice", live_notice_ok())
    Unit <- E.must("live_multiline", live_multiline_ok())
    Unit <- E.must("live_untagged", live_untagged_ok())
    Unit <- E.must("live_join_untouched", live_join_untouched_ok())
    Unit <- E.must("live_downgrade", live_downgrade_ok())
    Unit <- E.must("live_ack", live_ack_ok())
    Unit <- E.must("client_unlabeled", client_unlabeled_ok())
    IO.print("labeled_response=ok")
