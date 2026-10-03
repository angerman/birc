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

# G6.1: hostile CAP ACK (user prefix, wrong recipient, bare line) never
# enables; our server addressing us or '*' does.
def hostile_cap_ok() -> Bool:
  +legit = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :message-tags")
  +star = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * ACK :message-tags")
  +spoof = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":alice!u@h CAP me ACK :message-tags")
  +other = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP other ACK :message-tags")
  +bare = Cap.caps_apply_line(Cap.caps0(), "s", "me", "CAP me ACK :message-tags")
  Cap.tags_ok(legit) && Cap.tags_ok(star)
    && Bool.not(Cap.tags_ok(spoof)) && Bool.not(Cap.tags_ok(other)) && Bool.not(Cap.tags_ok(bare))

# G6.2: ACK -cap / DEL clear; enable and re-enable still work.
def cap_removal_ok() -> Bool:
  +on = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :message-tags")
  +neg = Cap.caps_apply_line(on, "s", "me", ":s CAP me ACK :-message-tags")
  +del = Cap.caps_apply_line(on, "s", "me", ":s CAP me DEL :message-tags")
  +reack = Cap.caps_apply_line(neg, "s", "me", ":s CAP me ACK :message-tags")
  Cap.tags_ok(on) && Bool.not(Cap.tags_ok(neg)) && Bool.not(Cap.tags_ok(del)) && Cap.tags_ok(reack)

# G6.3: server-shaped AWAY/ACCOUNT stay on the unknown-command path at feed
# level; user presence still renders (see feed_account/feed_away).
def hostile_notify_ok() -> Bool:
  +srv_away = Feed.feed(Cl.init("me", "s"), ":s AWAY :maintenance")
  +srv_acct = Feed.feed(Cl.init("me", "s"), ":s ACCOUNT alice123")
  +dot_away = Feed.feed(Cl.init("me", "irc.example.com"), ":irc.example.com AWAY :maintenance")
  +user_away = Feed.feed(Cl.init("me", "s"), ":bob!u@h AWAY :out to lunch")
  String.contains(server_text(srv_away), "AWAY") && Bool.not(String.contains(server_text(srv_away), "is away"))
    && String.contains(server_text(srv_acct), "ACCOUNT") && Bool.not(String.contains(server_text(srv_acct), "signed in"))
    && Bool.not(String.contains(server_text(dot_away), "is away"))
    && String.contains(server_text(user_away), "bob is away: out to lunch")

# G6.4: stale ticks stay quiet AND preserve live/sent state; fresh ticks act.
def stale_quiet_ok() -> Bool:
  +live: Cap.OutState = Cap.Out{"#a", True{}, 1000}
  +idle: Cap.OutState = Cap.Out{"#a", False{}, 1000}
  String.is_empty(Cap.step_text(Cap.step_out(live, 999, True{}, True{}, "#a", False{})))
    && Cap.step_live(Cap.step_out(live, 999, True{}, True{}, "#a", False{}))
    && U32.is_eq(Cap.step_sent_ms(Cap.step_out(live, 999, True{}, True{}, "#a", False{})), 1000)
    && String.is_empty(Cap.step_text(Cap.step_out(idle, 999, True{}, True{}, "#a", True{})))
    && Bool.not(Cap.step_live(Cap.step_out(idle, 999, True{}, True{}, "#a", True{})))
    && U32.is_eq(Cap.step_sent_ms(Cap.step_out(idle, 999, True{}, True{}, "#a", True{})), 1000)
    && String.eq(Cap.step_text(Cap.step_out(live, 2000, True{}, True{}, "#a", False{})), "@+typing=done TAGMSG #a")

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
    Unit <- E.must("g61_hostile_cap", hostile_cap_ok())
    Unit <- E.must("g62_cap_removal", cap_removal_ok())
    Unit <- E.must("g63_hostile_notify", hostile_notify_ok())
    Unit <- E.must("g64_stale_quiet", stale_quiet_ok())
    IO.print("cap_notify_demo=ok")
