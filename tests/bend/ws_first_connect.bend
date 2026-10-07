# SPDX-License-Identifier: Apache-2.0
# Startup-only connection override through the actual pure ws_first entry.
# No actor/frame/helper/socket/timer starts. Existing live busy policy stays.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/wsnet.bend as WsNet
import ../../src/bend/drafts.bend as D
import ../../src/bend/upload.bend as Up

type FirstOut is Data:
  FirstOut{ws: W.Workspace, rc: Sid.RoutedCmd, halt: Bool}

def result.r1(rest: Sid.RoutedCmd & Bool, +ws: W.Workspace) -> FirstOut:
  match rest:
    case (+rc, +halt): FirstOut{ws, rc, halt}

def result(trip: W.Workspace & Sid.RoutedCmd & Bool) -> FirstOut:
  match trip:
    case (+ws, rest): result.r1(rest, ws)

def out_ws(+out: FirstOut) -> W.Workspace:
  match out:
    case FirstOut{+ws, _, _}: ws

def out_rc(out: FirstOut) -> Sid.RoutedCmd:
  match out:
    case FirstOut{_, rc, _}: rc

def out_halt(out: FirstOut) -> Bool:
  match out:
    case FirstOut{_, _, halt}: halt

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

def seed() -> W.Workspace:
  +cl = Cl.client_set_auth(Cl.init("me", "a.example"), Cl.SaslOnly{}, "a.example", 6697, "", "", "account", "synthetic-secret")
  +ws = W.do_add(W.single_client("a.example", 6697, False{}, cl, "#a"), "sibling.example", 6697, False{}, "me", "#b")
  W.Workspace{W.ws_parts(ws), W.ws_current(ws), D.set(D.set(W.ws_drafts(ws), s0(), "#draft", "primary draft"), s1(), "#sibling", "sibling draft"), W.ws_retired(ws)}

def with_net(+ws: W.Workspace, net: Sess.NetState) -> W.Workspace:
  WsNet.ws_replace(ws, s0(), Sess.session_set_net(W.current_session(ws), net))

def first_keys(+ws: W.Workspace, +typed: String, enter: Bool, key: U32, f7: Bool, restore: Bool) -> FirstOut:
  result(WsNet.ws_first.act(ws, typed, enter, 24, 80, 0, key, 0, 0, 0, f7, restore))

def first(+ws: W.Workspace, +typed: String) -> FirstOut:
  first_keys(ws, typed, True{}, 0, False{}, False{})

def quiet_cmd(cmd: Sess.NetCmd) -> Bool:
  match cmd:
    case Sess.Cont{Nil{}}: True{}
    case _: False{}

def quiet_rc(rc: Sid.RoutedCmd) -> Bool:
  match rc:
    case Sid.RoutedCmd{Key.ServerId{0n}, cmd}: quiet_cmd(cmd)
    case _: False{}

def sibling_kept(+ws: W.Workspace) -> Bool:
  U32.is_eq(W.part_gen_of(ws, s1()), 0)
    && String.eq(Cl.server_of(W.isolation.client_of(ws, s1())), "sibling.example")
    && String.eq(D.get(W.ws_drafts(ws), s1(), "#sibling"), "sibling draft")
    && Bool.not(Cl.client_has_sasl(W.isolation.client_of(ws, s1())))

# The status display deliberately labels both dialing states "connecting".
# These guards need their distinct structural NetState, not that display text.
def net_is.state(net: Sess.NetState, +label: String) -> Bool:
  match net:
    case Sess.Connecting{}: String.eq(label, "connecting")
    case Sess.Reconnecting{}: String.eq(label, "reconnecting")
    case _: False{}

def net_is(+ws: W.Workspace, +label: String) -> Bool:
  net_is.state(Sess.session_net(W.current_session(ws)), label)

def route_ok(+out: FirstOut, +host: String, +gen: U32) -> Bool:
  W.routed_dial_exact(out_rc(out), s0(), host, 6697, gen, "me")
    && W.cmd_admitted(out_ws(out), out_rc(out))
    && U32.is_eq(W.part_gen_of(out_ws(out), s0()), gen)
    && String.eq(Cl.server_of(Sess.session_cl(W.current_session(out_ws(out)))), host)
    && Bool.not(out_halt(out))

def direct_changed() -> Bool:
  +out = first(seed(), "/connect b.example 6697")
  +ws = out_ws(out)
  +cl = Sess.session_cl(W.current_session(ws))
  route_ok(out, "b.example", 1) && net_is(ws, "connecting")
    && Bool.not(Cl.client_has_sasl(cl))
    && String.is_empty(Cl.settings_sasl_user(Cl.get_settings(cl)))
    && String.is_empty(Cl.settings_sasl_pass(Cl.get_settings(cl)))
    && String.is_empty(D.get(W.ws_drafts(ws), s0(), "#draft"))
    && sibling_kept(ws)
    && WsNet.ws_start.drop_boot_dial(False{}, ws, out_rc(out))
    && Bool.not(WsNet.ws_start.drop_boot_dial(True{}, ws, out_rc(out)))

def deferred_changed() -> Bool:
  +out = first(WsNet.ws_deferred(seed()), "/connect b.example:6697")
  route_ok(out, "b.example", 2) && net_is(out_ws(out), "connecting")
    && Bool.not(Cl.client_has_sasl(Sess.session_cl(W.current_session(out_ws(out)))))

def same_endpoint(+typed: String) -> Bool:
  +out = first(seed(), typed)
  +ws = out_ws(out)
  +st = W.current_session(ws)
  +upped = Sess.session_reconnected(st, "12:00:00")
  route_ok(out, "a.example", 1) && net_is(ws, "connecting")
    && Cl.client_has_sasl(Sess.session_cl(st))
    && String.eq(D.get(W.ws_drafts(ws), s0(), "#draft"), "primary draft")
    && sibling_kept(ws)
    && Bool.not(Sess.session_needs_reconnect_marker(st))
    && Nat.is_eq(Cl.log_seq_of(Sess.session_cl(st)), Cl.log_seq_of(Sess.session_cl(upped)))

def reconnecting_intent() -> Bool:
  +out = first(with_net(seed(), Sess.Reconnecting{}), "/reconnect")
  route_ok(out, "a.example", 1) && net_is(out_ws(out), "reconnecting")
    && Sess.session_needs_reconnect_marker(W.current_session(out_ws(out)))

def unchanged_scope(+out: FirstOut, +label: String) -> Bool:
  +ws = out_ws(out)
  quiet_rc(out_rc(out)) && U32.is_eq(W.part_gen_of(ws, s0()), 0)
    && String.eq(Cl.server_of(Sess.session_cl(W.current_session(ws))), "a.example")
    && net_is(ws, label) && Cl.client_has_sasl(Sess.session_cl(W.current_session(ws)))
    && String.eq(D.get(W.ws_drafts(ws), s0(), "#draft"), "primary draft")
    && sibling_kept(ws)

def invalid_keeps(+typed: String) -> Bool:
  +out = first(seed(), typed)
  unchanged_scope(out, "connecting") && Bool.not(out_halt(out))

def live_keeps(net: Sess.NetState, +label: String) -> Bool:
  +out = result(W.live_step_keys(with_net(seed(), net), Sess.keys_enter("/connect b.example 6697")))
  unchanged_scope(out, label) && Bool.not(out_halt(out))

def halt_keeps() -> Bool:
  +out = first_keys(seed(), "/connect b.example 6697", True{}, Sess.KEY_F10(), False{}, False{})
  unchanged_scope(out, "connecting") && out_halt(out)

def restored_keeps() -> Bool:
  +out = first_keys(seed(), "/connect b.example 6697", True{}, 0, False{}, True{})
  unchanged_scope(out, "connecting")
    && String.eq(Sess.session_draft(W.current_session(out_ws(out))), "/connect b.example 6697")

def f7_keeps() -> Bool:
  +out = first_keys(seed(), "/connect b.example 6697", True{}, Sess.KEY_F7(), True{}, False{})
  +ws = out_ws(out)
  Key.eq(W.ws_current(ws), s1()) && U32.is_eq(W.part_gen_of(ws, s0()), 0)
    && U32.is_eq(W.part_gen_of(ws, s1()), 0)
    && String.eq(Cl.server_of(W.isolation.client_of(ws, s0())), "a.example")
    && Cl.client_has_sasl(W.isolation.client_of(ws, s0()))
    && Bool.not(out_halt(out))

def upload_seed() -> W.Workspace:
  +ws = seed()
  +request : Up.Request = Up.Request{Up.Scope{"a.example", 6697, "*server*"}, "/synthetic-owned-file"}
  +st = Sess.session_set_upload(W.current_session(ws), Up.Busy{request, Nil{}, True{}})
  WsNet.ws_replace(ws, s0(), st)

def upload_invalidated(state: Up.State) -> Bool:
  match state:
    case Up.Busy{Up.Request{Up.Scope{"a.example", 6697, "*server*"}, "/synthetic-owned-file"}, Nil{}, False{}}: True{}
    case _: False{}

def upload_keeps_owner() -> Bool:
  +out = first(upload_seed(), "/connect b.example 6697")
  route_ok(out, "b.example", 1)
    && upload_invalidated(Sess.session_upload(W.current_session(out_ws(out))))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("first direct connect changes endpoint, clears only primary credentials/drafts, and emits exactly one scoped Dial", direct_changed())
    Unit <- E.must("first deferred connect carries the post-input generation", deferred_changed())
    Unit <- E.must("first same-endpoint connect retains credentials/drafts without an initial divider", same_endpoint("/connect a.example 6697"))
    Unit <- E.must("first configured reconnect retains credentials without an initial divider", same_endpoint("/reconnect"))
    Unit <- E.must("preexisting reconnect intent stays marked", reconnecting_intent())
    Unit <- E.must("missing endpoint leaves startup scope/net unchanged", invalid_keeps("/connect"))
    Unit <- E.must("invalid port leaves startup scope/net unchanged", invalid_keeps("/connect b.example 0"))
    Unit <- E.must("conflicting ports leave startup scope/net unchanged", invalid_keeps("/connect b.example:6697 6667"))
    Unit <- E.must("empty Enter leaves startup scope/net unchanged", invalid_keeps(""))
    Unit <- E.must("plain Enter cannot unlock startup registration", invalid_keeps("hello"))
    Unit <- E.must("non-enter connect text cannot unlock startup registration", unchanged_scope(first_keys(seed(), "/connect b.example 6697", False{}, 0, False{}, False{}), "connecting"))
    Unit <- E.must("no-input frame keeps startup state", unchanged_scope(first_keys(seed(), "", False{}, 0, False{}, False{}), "connecting"))
    Unit <- E.must("later live Connecting remains busy", live_keeps(Sess.Connecting{}, "connecting"))
    Unit <- E.must("later live Reconnecting remains busy", live_keeps(Sess.Reconnecting{}, "reconnecting"))
    Unit <- E.must("first-frame halt cannot unlock registration", halt_keeps())
    Unit <- E.must("upload-restored frame preserves its unsent composer", restored_keeps())
    Unit <- E.must("F7 keeps its existing focus/generation policy", f7_keeps())
    Unit <- E.must("endpoint change invalidates upload permission but keeps physical owner", upload_keeps_owner())
    IO.print("ws_first_connect=ok")
