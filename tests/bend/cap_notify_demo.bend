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
  String.eq(String.join(plain, "|"), "CAP LS 302|CAP REQ :server-time|CAP REQ :message-tags|CAP REQ :account-notify|CAP REQ :away-notify|CAP REQ :draft/chathistory|CAP REQ :echo-message|CAP REQ :extended-join|CAP REQ :account-tag|CAP REQ :labeled-response|CAP REQ :cap-notify|CAP END|NICK me|USER me 0 * :me")
    && String.eq(String.join(sasl, "|"), "CAP LS 302|CAP REQ :sasl|CAP REQ :server-time|CAP REQ :message-tags|CAP REQ :account-notify|CAP REQ :away-notify|CAP REQ :draft/chathistory|CAP REQ :echo-message|CAP REQ :extended-join|CAP REQ :account-tag|CAP REQ :labeled-response|CAP REQ :cap-notify|NICK me|USER me 0 * :me")

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
# enables; our server addressing us or preregistration '*' does.
def hostile_cap_ok() -> Bool:
  +legit = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :message-tags", True{})
  +star = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * ACK :message-tags", False{})
  +spoof = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":alice!u@h CAP me ACK :message-tags", True{})
  +other = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP other ACK :message-tags", True{})
  +bare = Cap.caps_apply_line(Cap.caps0(), "s", "me", "CAP me ACK :message-tags", True{})
  Cap.tags_ok(legit) && Cap.tags_ok(star)
    && Bool.not(Cap.tags_ok(spoof)) && Bool.not(Cap.tags_ok(other)) && Bool.not(Cap.tags_ok(bare))

# G6.2: ACK -cap / DEL clear; enable and re-enable still work.
def cap_removal_ok() -> Bool:
  +on = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :message-tags", True{})
  +neg = Cap.caps_apply_line(on, "s", "me", ":s CAP me ACK :-message-tags", True{})
  +del = Cap.caps_apply_line(on, "s", "me", ":s CAP me DEL :message-tags", True{})
  +reack = Cap.caps_apply_line(neg, "s", "me", ":s CAP me ACK :message-tags", True{})
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

# G6.5: the uninitialized typing state is unobserved, not a timestamp: the first
# composing tick at now=2^31 emits active; an established backward tick stays
# quiet and unchanged; genuine forward U32 wrap stays live.
def g65_first_ok(pair: Cap.OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, +xs):
      String.eq(String.concat(xs), "@+typing=active TAGMSG #a") && Cap.out_live(st) && U32.is_eq(Cap.out_sent_ms(st), 2147483648)

def g65_stale_ok(pair: Cap.OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, +xs):
      String.is_empty(String.concat(xs)) && Cap.out_live(st) && U32.is_eq(Cap.out_sent_ms(st), 1000)

def g65_wrap_quiet_ok(pair: Cap.OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, +xs):
      String.is_empty(String.concat(xs)) && Cap.out_live(st) && U32.is_eq(Cap.out_sent_ms(st), 4294967295)

def g65_wrap_fire_ok(pair: Cap.OutState & List<&2, String>) -> Bool:
  match pair:
    case (+st, +xs):
      String.eq(String.concat(xs), "@+typing=active TAGMSG #a") && Cap.out_live(st) && U32.is_eq(Cap.out_sent_ms(st), 4000)

def g65_unseen_ok() -> Bool:
  g65_first_ok(Cap.step_out(Cap.out0(), 2147483648, True{}, True{}, "#a", True{}))
    && g65_stale_ok(Cap.step_out(Cap.Out{"#a", True{}, 1000, True{}}, 999, True{}, True{}, "#a", True{}))
    && g65_wrap_quiet_ok(Cap.step_out(Cap.Out{"#a", True{}, 4294967295, True{}}, 100, True{}, True{}, "#a", True{}))
    && g65_wrap_fire_ok(Cap.step_out(Cap.Out{"#a", True{}, 4294967295, True{}}, 4000, True{}, True{}, "#a", True{}))

# Sentinel collision: an observed offline reset lands on the same
# Out{"",False{},0} shape as out0, so a field-sniffing unseen test mistakes a
# backward observed0 -> max tick for a first observation and emits active. The
# observed state must stay quiet at max while a truly fresh out0 at max fires.
def g66_observed_max_quiet_ok() -> Bool:
  +obs = Cap.step_state(Cap.step_out(Cap.out0(), 0, False{}, True{}, "#a", False{}))
  String.is_empty(Cap.step_text(Cap.step_out(obs, 4294967295, True{}, True{}, "#a", True{})))

def g66_fresh_max_fire_ok() -> Bool:
  String.eq(Cap.step_text(Cap.step_out(Cap.out0(), 4294967295, True{}, True{}, "#a", True{})), "@+typing=active TAGMSG #a")

def g66_sentinel_ok() -> Bool:
  g66_observed_max_quiet_ok() && g66_fresh_max_fire_ok()

# Malformed sources: a configured single-label server and a valid dotted
# server are trusted; URL, delimiter, and empty-label sources are not. A
# valid single-label server is never user presence.
def source_gate_ok() -> Bool:
  +single = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :message-tags", True{})
  +dotted = Cap.caps_apply_line(Cap.caps0(), "irc.example.com", "me", ":irc.example.com CAP me ACK :message-tags", True{})
  +url = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":http://evil.com/x CAP me ACK :message-tags", True{})
  +colon = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":a:b.c CAP me ACK :message-tags", True{})
  +comma = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":a,b.c CAP me ACK :message-tags", True{})
  +empty_label = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":a..b CAP me ACK :message-tags", True{})
  +hub = Feed.feed(Cl.init("me", "s"), ":hub AWAY :nightly restart")
  Cap.tags_ok(single) && Cap.tags_ok(dotted)
    && Bool.not(Cap.tags_ok(url)) && Bool.not(Cap.tags_ok(colon)) && Bool.not(Cap.tags_ok(comma)) && Bool.not(Cap.tags_ok(empty_label))
    && String.contains(server_text(hub), "AWAY") && Bool.not(String.contains(server_text(hub), "is away"))

def ph_cap(+p: Cl.AuthPhase) -> Bool:
  match p:
    case Cl.AuthCap{}: True{}
    case _: False{}

def ph_challenge(+p: Cl.AuthPhase) -> Bool:
  match p:
    case Cl.AuthChallenge{}: True{}
    case _: False{}

def ph_result(+p: Cl.AuthPhase) -> Bool:
  match p:
    case Cl.AuthResult{}: True{}
    case _: False{}

def ph_done(+p: Cl.AuthPhase) -> Bool:
  match p:
    case Cl.AuthDone{}: True{}
    case _: False{}

def fold_ls_ok(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (+cl, +xs): ph_cap(Cl.get_auth(cl)) && String.is_empty(String.concat(xs))

def fold_ack_ok(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (+cl, +xs): ph_challenge(Cl.get_auth(cl)) && String.eq(String.concat(xs), "AUTHENTICATE PLAIN")

def fold_plus_ok(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (+cl, +xs): ph_result(Cl.get_auth(cl)) && String.eq(String.concat(xs), "AUTHENTICATE PLAINAUTHENTICATE AHVzZXIAcGFzcw==")

def fold_903_ok(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (+cl, +xs): ph_done(Cl.get_auth(cl)) && String.eq(String.concat(xs), "AUTHENTICATE PLAINAUTHENTICATE AHVzZXIAcGFzcw==CAP END")

def fold_after_ok(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (+cl, +xs): ph_done(Cl.get_auth(cl)) && String.eq(String.concat(xs), "AUTHENTICATE PLAINAUTHENTICATE AHVzZXIAcGFzcw==CAP END")

# STAR-to-SASL fold: one registration/CAP-END owner across the star and SASL
# paths — no CAP END until the terminal SASL entry, then exactly one, and a
# duplicate post-terminal ACK emits no second CAP END.
def star_sasl_cap_end_ok() -> Bool:
  +c0 = credentials()
  fold_ls_ok(Sess.fold_lines(c0, ":s CAP * LS :sasl message-tags" <> Nil{}))
    && fold_ack_ok(Sess.fold_lines(c0, ":s CAP * LS :sasl message-tags" <> ":s CAP * ACK :sasl" <> Nil{}))
    && fold_plus_ok(Sess.fold_lines(c0, ":s CAP * LS :sasl message-tags" <> ":s CAP * ACK :sasl" <> "AUTHENTICATE +" <> Nil{}))
    && fold_903_ok(Sess.fold_lines(c0, ":s CAP * LS :sasl message-tags" <> ":s CAP * ACK :sasl" <> "AUTHENTICATE +" <> ":s 903 me :ok" <> Nil{}))
    && fold_after_ok(Sess.fold_lines(c0, ":s CAP * LS :sasl message-tags" <> ":s CAP * ACK :sasl" <> "AUTHENTICATE +" <> ":s 903 me :ok" <> ":s CAP me ACK :sasl" <> Nil{}))

# Live tick bundle for the Session/Net binding: composing is a nonempty
# composer on a valid target; online + negotiated tags + composing emits
# active; offline resets quietly; empty draft ends with done; untagged or
# mistargeted ticks stay quiet.
def live_tagged() -> Cap.Reg:
  Cap.Reg{Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :message-tags", True{}), Cap.out0()}

def live_tick_ok() -> Bool:
  +fire_tx = Cap.reg_text(Cap.live_tick(live_tagged(), 1000, True{}, "#a", "hi"))
  +dark_tx = Cap.reg_text(Cap.live_tick(live_tagged(), 1000, False{}, "#a", "hi"))
  +dark_target = Cap.reg_target(Cap.step_reg(Cap.live_tick(live_tagged(), 1000, False{}, "#a", "hi")))
  +live1 = Cap.step_reg(Cap.live_tick(live_tagged(), 1000, True{}, "#a", "hi"))
  +idle_tx = Cap.reg_text(Cap.live_tick(live1, 1100, True{}, "#a", ""))
  +untagged_tx = Cap.reg_text(Cap.live_tick(Cap.reg0(), 1000, True{}, "#a", "hi"))
  +mistargeted_tx = Cap.reg_text(Cap.live_tick(live_tagged(), 1000, True{}, "a b", "hi"))
  String.eq(fire_tx, "@+typing=active TAGMSG #a")
    && String.is_empty(dark_tx) && String.eq(dark_target, "")
    && String.eq(idle_tx, "@+typing=done TAGMSG #a")
    && String.is_empty(untagged_tx) && String.is_empty(mistargeted_tx)

# G6.4: stale ticks stay quiet AND preserve live/sent state; fresh ticks act.
def stale_quiet_ok() -> Bool:
  +live: Cap.OutState = Cap.Out{"#a", True{}, 1000, True{}}
  +idle: Cap.OutState = Cap.Out{"#a", False{}, 1000, True{}}
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
    Unit <- E.must("cap_prereg_star_ack_enables", Cap.tags_ok(Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * ACK :message-tags", False{})))
    Unit <- E.must("cap_registered_star_ack_rejected", Bool.not(Cap.tags_ok(Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * ACK :message-tags", True{}))))
    Unit <- E.must("cap_registered_star_del_retains_tags", Cap.tags_ok(Cap.caps_apply_line(Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me ACK :message-tags", True{}), "s", "me", ":s CAP * DEL :message-tags", True{})))
    Unit <- E.must("g62_cap_removal", cap_removal_ok())
    Unit <- E.must("g63_hostile_notify", hostile_notify_ok())
    Unit <- E.must("g64_stale_quiet", stale_quiet_ok())
    Unit <- E.must("g65_unseen_first_tick", g65_unseen_ok())
    Unit <- E.must("g66_observed_sentinel", g66_sentinel_ok())
    Unit <- E.must("out_sentinel", Cap.out_sentinel_ok())
    Unit <- E.must("out_unseen", Cap.out_unseen_ok())
    Unit <- E.must("source_gate_validated", source_gate_ok())
    Unit <- E.must("cap_source", Cap.cap_source_ok())
    Unit <- E.must("star_sasl_cap_end_once", star_sasl_cap_end_ok())
    Unit <- E.must("live_tick_bundle", live_tick_ok())
    IO.print("cap_notify_demo=ok")
