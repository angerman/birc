# Scope 6: CAP registry/CAP-END owner, account/away notify, outbound typing.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/session.bend as Sess
import ../../src/bend/cap_notify.bend as Cap

def credentials() -> Cl.Client:
  Cl.client_set_sasl(Cl.init("me", "s"), "user", "pass")

def outs(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, +xs): String.concat(xs)

def server_text(+cl: Cl.Client) -> String:
  CL.buf_texts(cl, 0n)

def handshake_ok() -> Bool:
  +plain = Sess.handshake_lines("me", False{})
  +sasl = Sess.handshake_lines("me", True{})
  String.eq(String.join(plain, "|"), "CAP LS 302|CAP REQ :server-time|CAP REQ :message-tags|CAP REQ :account-notify|CAP REQ :away-notify|CAP END|NICK me|USER me 0 * :me")
    && String.eq(String.join(sasl, "|"), "CAP LS 302|CAP REQ :sasl|CAP REQ :server-time|CAP REQ :message-tags|CAP REQ :account-notify|CAP REQ :away-notify|NICK me|USER me 0 * :me")

def auth_delegation_ok() -> Bool:
  String.eq(outs(Sess.fold_lines(credentials(), ":s CAP me NAK :sasl" <> Nil{})), "CAP END")
    && String.eq(outs(Sess.fold_lines(credentials(), ":s CAP me ACK :sasl" <> "AUTHENTICATE +" <> ":s 903 me :ok" <> Nil{})), "AUTHENTICATE PLAINAUTHENTICATE AHVzZXIAcGFzcw==CAP END")

def feed_account_ok() -> Bool:
  +login = Feed.feed(Cl.init("me", "s"), ":alice!u@h ACCOUNT alice123")
  +logout = Feed.feed(Cl.init("me", "s"), ":alice!u@h ACCOUNT *")
  String.contains(server_text(login), "alice signed in as alice123")
    && String.contains(server_text(logout), "alice signed out")
    && Bool.not(String.contains(server_text(login), "ACCOUNT"))

def feed_away_ok() -> Bool:
  +away_set = Feed.feed(Cl.init("me", "s"), ":bob!u@h AWAY :out to lunch")
  +bare = Feed.feed(Cl.init("me", "s"), ":bob!u@h AWAY :")
  +clear = Feed.feed(Cl.init("me", "s"), ":bob!u@h AWAY")
  String.contains(server_text(away_set), "bob is away: out to lunch")
    && String.contains(server_text(bare), "bob is away")
    && String.contains(server_text(clear), "bob is back")
    && Bool.not(String.contains(server_text(away_set), "AWAY"))

def feed_malformed_ok() -> Bool:
  +arity = Feed.feed(Cl.init("me", "s"), ":alice!u@h ACCOUNT")
  +chan = Feed.feed(Cl.init("me", "s"), ":#room ACCOUNT alice123")
  +away_arity = Feed.feed(Cl.init("me", "s"), ":bob!u@h AWAY a b")
  String.contains(server_text(arity), "ACCOUNT")
    && Bool.not(String.contains(server_text(arity), "signed"))
    && String.contains(server_text(chan), "ACCOUNT")
    && Bool.not(String.contains(server_text(chan), "signed"))
    && String.contains(server_text(away_arity), "AWAY")
    && Bool.not(String.contains(server_text(away_arity), "is away"))

def out_wire_ok() -> Bool:
  +started_st = Cap.step_state(Cap.step_out(Cap.out0(), 1000, True{}, True{}, "#a", True{}))
  String.eq(Cap.step_text(Cap.step_out(Cap.out0(), 1000, True{}, True{}, "#a", True{})), "@+typing=active TAGMSG #a")
    && String.eq(Cap.step_text(Cap.step_out(started_st, 1100, True{}, True{}, "#a", False{})), "@+typing=done TAGMSG #a")
    && String.is_empty(Cap.step_text(Cap.step_out(started_st, 1100, False{}, True{}, "#a", False{})))
    && Bool.not(Cap.step_live(Cap.step_out(started_st, 1100, False{}, True{}, "#a", False{})))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("cap_end_owner", Cap.cap_end_single_owner_ok())
    Unit <- E.must("caps_ack_only", Cap.caps_ack_only_ok())
    Unit <- E.must("notify_parse", Cap.notify_parse_ok())
    Unit <- E.must("notify_reject", Cap.notify_reject_ok())
    Unit <- E.must("out_bound", Cap.out_bound_ok())
    Unit <- E.must("out_lifecycle", Cap.out_lifecycle_ok())
    Unit <- E.must("reg_gating", Cap.reg_gating_ok())
    Unit <- E.must("handshake", handshake_ok())
    Unit <- E.must("auth_delegation", auth_delegation_ok())
    Unit <- E.must("feed_account", feed_account_ok())
    Unit <- E.must("feed_away", feed_away_ok())
    Unit <- E.must("feed_malformed", feed_malformed_ok())
    Unit <- E.must("out_wire", out_wire_ok())
    IO.print("cap_notify_demo=ok")
