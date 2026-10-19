# SPDX-License-Identifier: Apache-2.0
# Negotiated channel policy must reach the production Session Enter seam.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/isupport.bend as Is
import ../../src/bend/join_plan.bend as P
import ../../src/bend/session.bend as Sess
import ../../src/bend/submit.bend as Sub

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

def main() -> IO(Unit):
  +iso = dollar_server()
  +cl = base()
  +dollar = dollar_channel()
  +joined = result_session(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room")))
  +offline_joined = Sess.session_set_net(joined, Sess.Offline{})
  +reconnecting_joined = Sess.session_set_net(result_session(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), Sess.Reconnecting{})
  do IO<Unit>:
    # −/+ pairs use step_keys/Enter, not Submit's lower-level negotiated seam.
    Unit <- E.must_eq("fixed Session JOIN rejects advertised-only type", wire(Sess.step_keys(live(Is.defaults(), cl, ""), Sess.keys_enter("/join $room"))), "")
    Unit <- E.must_eq("negotiated Session JOIN accepts advertised type", wire(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), "JOIN $room")
    Unit <- E.must_eq("fixed Session JOIN does not record advertised-only type", desired(Sess.step_keys(live(Is.defaults(), cl, ""), Sess.keys_enter("/join $room"))), "")
    Unit <- E.must_eq("negotiated Session JOIN records advertised type", desired(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), "$room")
    Unit <- E.must_eq("negotiated PART removes advertised desired type", desired(Sess.step_keys(joined, Sess.keys_enter("/part $room"))), "")
    Unit <- E.must_eq("reconnect emits JOIN for advertised desired type", reset_join_wire(result_session(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), iso), "JOIN $room")
    Unit <- E.must_eq("fixed Session PART rejects advertised-only type", wire(Sess.step_keys(live(Is.defaults(), cl, ""), Sess.keys_enter("/part $room"))), "")
    Unit <- E.must_eq("negotiated Session PART accepts advertised type", wire(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/part $room"))), "PART $room")
    Unit <- E.must_eq("fixed Session CLOSE rejects advertised-only type", wire(Sess.step_keys(live(Is.defaults(), cl, ""), Sess.keys_enter("/close $room"))), "")
    Unit <- E.must_eq("negotiated Session CLOSE accepts advertised type", wire(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/close $room"))), "PART $room")
    Unit <- E.must_eq("offline PART uses retained negotiated type", desired(Sess.step_keys(offline_joined, Sess.keys_enter("/part $room"))), "")
    Unit <- E.must_eq("reconnecting CLOSE uses retained negotiated type", desired(Sess.step_keys(reconnecting_joined, Sess.keys_enter("/close $room"))), "")
    Unit <- E.must_eq("fixed Session MUTE leaves advertised-only active target unscoped", mute_pattern(Sess.step_keys(live(Is.defaults(), dollar, "$room"), Sess.keys_enter("/mute alice"))), "alice*@irc")
    Unit <- E.must_eq("negotiated Session MUTE scopes advertised active target", mute_pattern(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mute alice"))), "alice$room@irc")
    IO.print("session_isupport_submit=ok")
