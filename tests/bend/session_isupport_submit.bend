# SPDX-License-Identifier: Apache-2.0
# Negotiated channel policy must reach the production Session Enter seam.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/isupport.bend as Is
import ../../src/bend/join_plan.bend as P
import ../../src/bend/media.bend as M
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/submit.bend as Sub
import ../../src/bend/theme.bend as Theme
import ../../src/bend/view.bend as V

def base() -> Cl.Client:
  Cl.init("me", "irc")

def dollar_server() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=$ :are supported")

def submit_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def dollar_channel() -> Cl.Client:
  submit_client(Sub.submit_with(dollar_server(), base(), "/join $room"))

def live(+iso: Is.State, +cl: Cl.Client, +chan: String) -> Sess.Session:
  Sess.session_set_iso(Sess.session_set_net(Sess.session_demo(cl, chan), Sess.Online{}), iso)

def wire(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (_, Sess.Cont{xs}, _): String.join(xs, "|")
    case _: ""

def result_client(trip: Sess.Session & Sess.NetCmd & Bool) -> Cl.Client:
  match trip:
    case (st, _, _): Sess.session_cl(st)

def result_session(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match trip:
    case (st, _, _): st

def desired(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (st, _, _): String.join(Sess.session_desired_channels(st), "|")

def flush_wire(got: P.Flush) -> String:
  match got:
    case P.Flush{_, outs, _}: String.join(outs, "|")

def reset_join_wire(+st: Sess.Session, +iso: Is.State) -> String:
  +cl = Sess.session_cl(st)
  +reset = P.reset(Sess.session_plan(st), cl, 6697)
  +welcomed = P.received(reset, cl, ":irc 001 me :welcome")
  flush_wire(P.flush_iso(welcomed, cl, iso))

def mute_pattern(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  String.join(Cl.settings_mutes(Cl.get_settings(result_client(trip))), "|")

def muted_old_count(trip: Sess.Session & Sess.NetCmd & Bool, +iso: Is.State) -> Nat:
  +cl = result_client(trip)
  +line = {Cl.Line{Cl.Msg{}, "", "<Alice> old", "Alice", 1n} : Cl.Line}
  List.length(&2, Cl.Line, Cl.filter_muted_lines_iso(Is.as_iso(iso), line <> Nil{},
    Cl.settings_mutes(Cl.get_settings(cl)), "$room", "irc"))

def session_mute_pattern(+st: Sess.Session) -> String:
  String.join(Cl.settings_mutes(Cl.get_settings(Sess.session_cl(st))), "|")

def session_muted_old_count(+st: Sess.Session, +iso: Is.State) -> Nat:
  +cl = Sess.session_cl(st)
  +line = {Cl.Line{Cl.Msg{}, "", "<Alice> old", "Alice", 1n} : Cl.Line}
  List.length(&2, Cl.Line, Cl.filter_muted_lines_iso(Is.as_iso(iso), line <> Nil{},
    Cl.settings_mutes(Cl.get_settings(cl)), "$room", "irc"))

def spans_text(spans: List<&2, V.SpanOp>) -> String:
  match spans:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text(t)

def ops_contain(ops: List<&2, V.DrawOp>, +text: String) -> Bool:
  match ops:
    case Nil{}: False{}
    case Con{V.OpLine{_, _, _, _, spans}, t}: String.contains(spans_text(spans), text) || ops_contain(t, text)
    case Con{_, t}: ops_contain(t, text)

def view_contains(vm: V.ViewModel, text: String) -> Bool:
  match vm:
    case V.ViewModel{ops, _}: ops_contain(ops, text)

def anchored_contains(rows: List<&2, V.AnchoredRow>, +text: String) -> Bool:
  match rows:
    case Nil{}: False{}
    case Con{V.AnchoredRow{_, _, Cl.Line{_, _, line, _, _}}, rest}:
      String.contains(line, text) || anchored_contains(rest, text)

def muted_client(+iso: Is.State, +chan: String) -> Sess.Session:
  +joined = submit_client(Sub.submit_with(iso, base(), "/join " ++ chan))
  +with_row = Cl.client_log_author_ts(joined, Cl.active_of(joined), Cl.Msg{}, "", "<Alice> old", "Alice")
  result_session(Sess.step_keys(live(iso, with_row, chan), Sess.keys_enter("/mute alice")))

def muted_paint_matches_window(+iso: Is.State, +chan: String) -> Bool:
  +st = muted_client(iso, chan)
  +cl = Sess.session_cl(st)
  +isc = Is.as_iso(iso)
  +vm = V.view_draft.state_typing_media_cards_iso_themed(isc, cl, 24, 80, "", "online", Nil{}, Sp.Off{}, M.empty(), Nil{}, Theme.Dark{}, Nil{})
  +rows = V.visible_anchored_panes_media_cards_iso(isc, cl, 24, 80, Sp.Off{}, M.empty(), Nil{})
  Bool.not(view_contains(vm, "<Alice> old")) && Bool.not(anchored_contains(rows, "<Alice> old"))

def main() -> IO(Unit):
  +iso = dollar_server()
  +cl = base()
  +dollar = dollar_channel()
  +joined = result_session(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room")))
  +offline_joined = Sess.session_set_net(joined, Sess.Offline{})
  +reconnecting_joined = Sess.session_set_net(result_session(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), Sess.Reconnecting{})
  +muted = result_session(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mute alice")))
  +unmuted = result_session(Sess.step_keys(muted, Sess.keys_enter("/unmute alice")))
  +seeded = Sess.session_seed_channels(live(Is.defaults(), cl, ""), ["$room"])
  do IO<Unit>:
    # −/+ pairs use step_keys/Enter, not Submit's lower-level negotiated seam.
    Unit <- E.must_eq("fixed Session JOIN rejects advertised-only type", wire(Sess.step_keys(live(Is.defaults(), cl, ""), Sess.keys_enter("/join $room"))), "")
    Unit <- E.must_eq("negotiated Session JOIN accepts advertised type", wire(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), "JOIN $room")
    Unit <- E.must_eq("fixed Session JOIN does not record advertised-only type", desired(Sess.step_keys(live(Is.defaults(), cl, ""), Sess.keys_enter("/join $room"))), "")
    Unit <- E.must_eq("negotiated Session JOIN records advertised type", desired(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), "$room")
    Unit <- E.must_eq("negotiated PART removes advertised desired type", desired(Sess.step_keys(joined, Sess.keys_enter("/part $room"))), "")
    Unit <- E.must_eq("reconnect emits JOIN for advertised desired type", reset_join_wire(result_session(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), iso), "JOIN $room")
    Unit <- E.must_eq("pre-005 desired candidate is retained", String.join(Sess.session_desired_channels(seeded), "|"), "$room")
    Unit <- E.must_eq("default policy does not wire saved negotiated-only candidate", reset_join_wire(seeded, Is.defaults()), "")
    Unit <- E.must_eq("trusted CHANTYPES admits saved negotiated-only candidate", reset_join_wire(seeded, iso), "JOIN $room")
    Unit <- E.must_eq("fixed Session PART rejects advertised-only type", wire(Sess.step_keys(live(Is.defaults(), cl, ""), Sess.keys_enter("/part $room"))), "")
    Unit <- E.must_eq("negotiated Session PART accepts advertised type", wire(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/part $room"))), "PART $room")
    Unit <- E.must_eq("fixed Session CLOSE rejects advertised-only type", wire(Sess.step_keys(live(Is.defaults(), cl, ""), Sess.keys_enter("/close $room"))), "")
    Unit <- E.must_eq("negotiated Session CLOSE accepts advertised type", wire(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/close $room"))), "PART $room")
    Unit <- E.must_eq("offline PART uses retained negotiated type", desired(Sess.step_keys(offline_joined, Sess.keys_enter("/part $room"))), "")
    Unit <- E.must_eq("reconnecting CLOSE uses retained negotiated type", desired(Sess.step_keys(reconnecting_joined, Sess.keys_enter("/close $room"))), "")
    Unit <- E.must_eq("fixed Session MUTE leaves advertised-only active target unscoped", mute_pattern(Sess.step_keys(live(Is.defaults(), dollar, "$room"), Sess.keys_enter("/mute alice"))), "alice*@irc")
    Unit <- E.must_eq("negotiated Session MUTE scopes advertised active target", mute_pattern(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mute alice"))), "alice$room@irc")
    # Fixed wrappers keep their default policy; negotiated Session dispatch
    # classifies both the active target and explicit command targets.
    Unit <- E.must_eq("fixed WHO broadens advertised-only active target", wire(Sess.step_keys(live(Is.defaults(), dollar, "$room"), Sess.keys_enter("/who"))), "WHO *")
    Unit <- E.must_eq("negotiated WHO targets advertised active channel", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/who"))), "WHO $room")
    Unit <- E.must_eq("fixed NAMES stays bare for advertised-only active target", wire(Sess.step_keys(live(Is.defaults(), dollar, "$room"), Sess.keys_enter("/names"))), "NAMES")
    Unit <- E.must_eq("negotiated NAMES targets advertised active channel", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/names"))), "NAMES $room")
    Unit <- E.must_eq("fixed TOPIC rejects advertised-only active target", wire(Sess.step_keys(live(Is.defaults(), dollar, "$room"), Sess.keys_enter("/topic :new"))), "")
    Unit <- E.must_eq("negotiated TOPIC targets advertised active channel", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/topic :new"))), "TOPIC $room :new")
    Unit <- E.must_eq("fixed MODE falls back to nick for advertised-only active target", wire(Sess.step_keys(live(Is.defaults(), dollar, "$room"), Sess.keys_enter("/mode"))), "MODE me")
    Unit <- E.must_eq("negotiated MODE targets advertised active channel", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mode"))), "MODE $room")
    Unit <- E.must_eq("fixed KICK rejects advertised-only active target", wire(Sess.step_keys(live(Is.defaults(), dollar, "$room"), Sess.keys_enter("/kick bob"))), "")
    Unit <- E.must_eq("negotiated KICK targets advertised active channel", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/kick bob"))), "KICK $room bob")
    Unit <- E.must_eq("STATUSMSG-only KICK target is rejected", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/kick @#room bob"))), "")
    Unit <- E.must_eq("bare KICK channel target is rejected", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/kick # bob"))), "")
    Unit <- E.must_eq("negotiated explicit KICK target is accepted", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/kick $room bob"))), "KICK $room bob")
    Unit <- E.must_eq("fixed INVITE rejects advertised-only active target", wire(Sess.step_keys(live(Is.defaults(), dollar, "$room"), Sess.keys_enter("/invite bob"))), "")
    Unit <- E.must_eq("negotiated INVITE targets advertised active channel", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/invite bob"))), "INVITE bob $room")
    Unit <- E.must_eq("STATUSMSG-only TOPIC target is rejected", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/topic @#room :new"))), "")
    Unit <- E.must_eq("bare TOPIC channel target is rejected", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/topic # :new"))), "")
    Unit <- E.must_eq("STATUSMSG-only INVITE target is rejected", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/invite bob @#room"))), "")
    Unit <- E.must_eq("bare INVITE channel target is rejected", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/invite bob #"))), "")
    Unit <- E.must_eq("STATUSMSG-only MODE target is rejected", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mode @#room +m"))), "")
    Unit <- E.must_eq("bare MODE channel target is rejected", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mode # +m"))), "")
    Unit <- E.must_eq("negotiated explicit MODE target is accepted", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mode $room +m"))), "MODE $room +m")
    Unit <- E.must("negotiated scoped mute filters existing Alice line", Nat.is_eq(session_muted_old_count(muted, iso), 0n))
    Unit <- E.must("negotiated production paint and scroll window omit muted advertised-channel row", muted_paint_matches_window(iso, "$room"))
    Unit <- E.must("default production paint still omits muted channel row", muted_paint_matches_window(Is.defaults(), "#room"))
    Unit <- E.must_eq("negotiated unmute removes scoped advertised-channel rule", session_mute_pattern(unmuted), "")
    Unit <- E.must("negotiated unmute restores existing Alice line", Nat.is_eq(session_muted_old_count(unmuted, iso), 1n))
    IO.print("session_isupport_submit=ok")
