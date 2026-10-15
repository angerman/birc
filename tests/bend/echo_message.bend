# SPDX-License-Identifier: Apache-2.0
# echo-message slice: CAP registry bit, gated local echo, single wire render.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/drafts.bend as Drafts
import ../../src/bend/session.bend as Sess
import ../../src/bend/isupport.bend as Is
import ../../src/bend/cap_notify.bend as Cap

def chan0() -> Cl.Client:
  Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #t")

def take_cl(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl2, _): cl2

def take_outs(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, +xs): String.concat(xs)

def chan_text(+cl: Cl.Client) -> String:
  CL.buf_texts(cl, 1n)

def echo_reg() -> Cap.Reg:
  Cap.Reg{Cap.caps_apply(Cap.caps0(), Cap.CapEvent{Cap.CapAck{}, "echo-message" <> Nil{}}), Cap.out0()}

def echo_session() -> Sess.Session:
  Sess.session_set_reg(Sess.session_demo(chan0(), "#t"), echo_reg())

def trip_cl(t: Sess.Session & Sess.NetCmd & Bool) -> Cl.Client:
  match t:
    case (st, _, _): Sess.session_cl(st)

def trip_outs(t: Sess.Session & Sess.NetCmd & Bool) -> String:
  match t:
    case (_, cmd, _):
      match cmd:
        case Sess.Cont{+xs}: String.concat(xs)
        case _: ""

def soh() -> String:
  SCon{Chr{1}, SNil{}}

def lf() -> String:
  SCon{Chr{10}, SNil{}}

# echo-on suppresses the local echo; the wire still carries the message.
def suppress_ok() -> Bool:
  +text = chan_text(take_cl(Sub.submit_echo(chan0(), "hello", True{})))
  +outs = take_outs(Sub.submit_echo(chan0(), "hello", True{}))
  String.eq(text, "-> me joined #t|")
    && String.eq(outs, "PRIVMSG #t :hello")

# echo-off keeps the local echo, byte-identical to the ungated path.
def unsuppressed_ok() -> Bool:
  +text = chan_text(take_cl(Sub.submit_echo(chan0(), "hello", False{})))
  +ptext = chan_text(take_cl(Sub.submit(chan0(), "hello")))
  +outs = take_outs(Sub.submit_echo(chan0(), "hello", False{}))
  +pouts = take_outs(Sub.submit(chan0(), "hello"))
  String.eq(text, "-> me joined #t|<me> hello|")
    && String.eq(text, ptext)
    && String.eq(outs, pouts)

# The wire echo is the single confirmation: suppressed submit plus the
# server copy renders exactly once (exact buffer equality pins the count).
def roundtrip_once_ok() -> Bool:
  sent = take_cl(Sub.submit_echo(chan0(), "hello", True{}))
  fed = Feed.feed(sent, ":me!me@localhost PRIVMSG #t :hello")
  String.eq(chan_text(fed), "-> me joined #t|<me> hello|")

# NOTICE echoes share the path: suppressed locally, rendered once on wire.
def notice_ok() -> Bool:
  +pre = chan_text(take_cl(Sub.submit_notice_echo(chan0(), "#t hi", True{})))
  +outs = take_outs(Sub.submit_notice_echo(chan0(), "#t hi", True{}))
  fed = Feed.feed(take_cl(Sub.submit_notice_echo(chan0(), "#t hi", True{})), ":me!me@localhost NOTICE #t :hi")
  String.eq(pre, "-> me joined #t|")
    && String.eq(outs, "NOTICE #t :hi")
    && String.eq(chan_text(fed), "-> me joined #t|<me> hi|")

# CTCP ACTION echoes share the path via the gated action echo.
def action_ok() -> Bool:
  +pre = chan_text(take_cl(Sub.submit_me_echo(chan0(), "waves", True{})))
  +outs = take_outs(Sub.submit_me_echo(chan0(), "waves", True{}))
  fed = Feed.feed(take_cl(Sub.submit_me_echo(chan0(), "waves", True{})), ":me!me@localhost PRIVMSG #t :" ++ soh() ++ "ACTION waves" ++ soh())
  String.eq(pre, "-> me joined #t|")
    && String.eq(outs, "PRIVMSG #t :" ++ soh() ++ "ACTION waves" ++ soh())
    && String.eq(chan_text(fed), "-> me joined #t|* me waves|")

# Credential sends keep their placeholder under echo-message: the server's
# copy is consumed by the credential_echo gate, never rendered.
def credential_ok() -> Bool:
  +text = CL.buf_texts(take_cl(Sub.submit_echo(Cl.init("me", "s"), "/msg NickServ identify secret", True{})), 1n)
  +outs = take_outs(Sub.submit_echo(Cl.init("me", "s"), "/msg NickServ identify secret", True{}))
  String.contains(text, "[credential command sent]")
    && String.eq(outs, "PRIVMSG NickServ :identify secret")

# Negotiated (_with) submit honors the same gate.
def with_ok() -> Bool:
  +on_text = chan_text(take_cl(Sub.submit_parsed_with_echo(Is.defaults(), chan0(), Sub.parse_input("hello"), True{})))
  +on_outs = take_outs(Sub.submit_parsed_with_echo(Is.defaults(), chan0(), Sub.parse_input("hello"), True{}))
  +off_text = chan_text(take_cl(Sub.submit_parsed_with_echo(Is.defaults(), chan0(), Sub.parse_input("hello"), False{})))
  String.eq(on_text, "-> me joined #t|")
    && String.eq(on_outs, "PRIVMSG #t :hello")
    && String.eq(off_text, "-> me joined #t|<me> hello|")

# Multiline draft submits suppress per line under echo-message.
def multiline_ok() -> Bool:
  +text = chan_text(take_cl(Drafts.submit_lines_echo(chan0(), 1n, "#t", "one" ++ lf() ++ "two", False{}, True{})))
  +outs = take_outs(Drafts.submit_lines_echo(chan0(), 1n, "#t", "one" ++ lf() ++ "two", False{}, True{}))
  String.eq(text, "-> me joined #t|")
    && String.eq(outs, "PRIVMSG #t :onePRIVMSG #t :two")

# Session gate follows the stored registry bit.
def session_gate_ok() -> Bool:
  Bool.not(Sess.session_echo_ok(Sess.session0("me", "s", "#t")))
    && Sess.session_echo_ok(echo_session())

# Live key-loop roundtrip: an echo-negotiated session submits without a
# local echo; an unnegotiated one keeps it. Wire identical in both.
def live_ok() -> Bool:
  +on_text = chan_text(trip_cl(Sess.step_keys(echo_session(), Sess.keys_of("hello", True{}, 0, 0, 0, 0, 0, 0, 0))))
  +on_outs = trip_outs(Sess.step_keys(echo_session(), Sess.keys_of("hello", True{}, 0, 0, 0, 0, 0, 0, 0)))
  +off_text = chan_text(trip_cl(Sess.step_keys(Sess.session_demo(chan0(), "#t"), Sess.keys_of("hello", True{}, 0, 0, 0, 0, 0, 0, 0))))
  +off_outs = trip_outs(Sess.step_keys(Sess.session_demo(chan0(), "#t"), Sess.keys_of("hello", True{}, 0, 0, 0, 0, 0, 0, 0)))
  String.eq(on_text, "-> me joined #t|")
    && String.eq(on_outs, "PRIVMSG #t :hello")
    && String.eq(off_text, "-> me joined #t|<me> hello|")
    && String.eq(off_outs, "PRIVMSG #t :hello")

# Hostile post-register CAP lines never arm the bit (trust gate reuse).
def hostile_ok() -> Bool:
  +star = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * ACK :echo-message", True{})
  +spoof = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":alice!u@h CAP me ACK :echo-message", True{})
  +bare = Cap.caps_apply_line(Cap.caps0(), "s", "me", "CAP me ACK :echo-message", True{})
  Bool.not(Cap.echo_ok(star)) && Bool.not(Cap.echo_ok(spoof)) && Bool.not(Cap.echo_ok(bare))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("caps_echo", Cap.caps_echo_ok())
    Unit <- E.must("caps_ack_only", Cap.caps_ack_only_ok())
    Unit <- E.must("caps_parse", Cap.caps_parse_ok())
    Unit <- E.must("caps_removal", Cap.caps_removal_ok())
    Unit <- E.must_eq("req_wire", Irc.format_cap_req(Cap.CAP_ECHO()), "CAP REQ :echo-message")
    Unit <- E.must("suppress", suppress_ok())
    Unit <- E.must("unsuppressed", unsuppressed_ok())
    Unit <- E.must("roundtrip_once", roundtrip_once_ok())
    Unit <- E.must("notice", notice_ok())
    Unit <- E.must("action", action_ok())
    Unit <- E.must("credential", credential_ok())
    Unit <- E.must("with_parity", with_ok())
    Unit <- E.must("multiline", multiline_ok())
    Unit <- E.must("session_gate", session_gate_ok())
    Unit <- E.must("live_roundtrip", live_ok())
    Unit <- E.must("hostile", hostile_ok())
    IO.print("echo_message=ok")
