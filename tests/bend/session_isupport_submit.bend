# SPDX-License-Identifier: Apache-2.0
# Negotiated channel policy must reach the production Session Enter seam.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/frame.bend as Fr
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

def hash_server() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=# :are supported")

def ascii_server() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=# CASEMAPPING=ascii :are supported")

def rfc1459_hash_server() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=# CASEMAPPING=rfc1459 :are supported")

def submit_wire(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, xs): String.join(xs, "|")

def has_channel_cm.found(found: Maybe<&2, Nat>) -> Bool:
  match found:
    case None{}: False{}
    case Some{_}: True{}

def has_channel_cm(+cl: Cl.Client, +cm: String, +name: String) -> Bool:
  has_channel_cm.found(Cl.buf_find_cm(cl, cm, name))

def submit_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def ascii_bracket_client() -> Cl.Client:
  +iso = ascii_server()
  +left = submit_client(Sub.submit_with(iso, base(), "/join #a["))
  submit_client(Sub.submit_with(iso, left, "/join #a{"))

def rfc1459_bracket_client() -> Cl.Client:
  +iso = rfc1459_hash_server()
  +left = submit_client(Sub.submit_with(iso, base(), "/join #a["))
  submit_client(Sub.submit_with(iso, left, "/join #a{"))

def ascii_part_brace_keeps_bracket() -> Bool:
  +iso = ascii_server()
  +after = submit_client(Sub.submit_with(iso, ascii_bracket_client(), "/part #a{"))
  has_channel_cm(after, "ascii", "#a[") && Bool.not(has_channel_cm(after, "ascii", "#a{"))

def ascii_close_brace_keeps_bracket() -> Bool:
  +iso = ascii_server()
  +after = submit_client(Sub.submit_with(iso, ascii_bracket_client(), "/close #a{"))
  has_channel_cm(after, "ascii", "#a[") && Bool.not(has_channel_cm(after, "ascii", "#a{"))

def ascii_bracket_join_two_buffers() -> Bool:
  +cl = ascii_bracket_client()
  Nat.is_eq(Cl.normal_buffer_count(Cl.client_bufs(cl)), 3n)
    && has_channel_cm(cl, "ascii", "#a[")
    && has_channel_cm(cl, "ascii", "#a{")

def buf_topic.buf(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{_, _, +topic, _, _, _, _, _}}: topic

def buf_topic.at(+cl: Cl.Client, found: Maybe<&2, Nat>) -> String:
  match found:
    case None{}: ""
    case Some{+i}: buf_topic.buf(Cl.nth_buf(Cl.client_bufs(cl), i))

def buf_topic_cm(+cl: Cl.Client, +cm: String, +name: String) -> String:
  buf_topic.at(cl, Cl.buf_find_cm(cl, cm, name))

def ascii_topic_hits_brace_only() -> Bool:
  +iso = ascii_server()
  +cl = Feed.feed_with(ascii_bracket_client(), Is.as_iso(iso), ":op!u@h TOPIC #a{ :brace topic")
  String.eq(buf_topic_cm(cl, "ascii", "#a{"), "brace topic")
    && String.is_empty(buf_topic_cm(cl, "ascii", "#a["))

def show_buf_tail.rev(rev: List<&2, Cl.Line>) -> String:
  match rev:
    case Nil{}: ""
    case Con{Cl.Line{_, _, +text, _, _}, _}: text

def show_buf_tail.lines(lines: List<&2, Cl.Line>) -> String:
  show_buf_tail.rev(List.reverse(&2, Cl.Line, lines))

def show_buf_tail.buf(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{_, _, _, +lines, _, _, _, _}}: show_buf_tail.lines(lines)

def show_buf_tail.at(+cl: Cl.Client, found: Maybe<&2, Nat>) -> String:
  match found:
    case None{}: ""
    case Some{+i}: show_buf_tail.buf(Cl.nth_buf(Cl.client_bufs(cl), i))

def show_buf_tail_cm(+cl: Cl.Client, +cm: String, +name: String) -> String:
  show_buf_tail.at(cl, Cl.buf_find_cm(cl, cm, name))

def ascii_mode_logs_brace_only() -> Bool:
  +iso = ascii_server()
  +cl = Feed.feed_with(ascii_bracket_client(), Is.as_iso(iso), ":op!u@h MODE #a{ +m")
  String.contains(show_buf_tail_cm(cl, "ascii", "#a{"), "MODE")
    && Bool.not(String.contains(show_buf_tail_cm(cl, "ascii", "#a["), "MODE"))

def dollar_channel() -> Cl.Client:
  submit_client(Sub.submit_with(dollar_server(), base(), "/join $room"))

def hash_channel() -> Cl.Client:
  submit_client(Sub.submit_with(hash_server(), base(), "/join #room"))

def plus_resident() -> Cl.Client:
  +with_plus = submit_client(Sub.submit_with(Is.defaults(), base(), "/join +local"))
  submit_client(Sub.submit_with(Is.defaults(), with_plus, "/join #room"))

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
  +finished = P.received_with(Is.casemapping(iso), welcomed, cl, ":irc 376 me :end of MOTD")
  flush_wire(P.flush_iso(finished, cl, iso))

def chunk_state(pair: Sess.Session & List<&2, String>) -> Sess.Session:
  match pair:
    case (st, _): st

def chunk_wire(pair: Sess.Session & List<&2, String>) -> String:
  match pair:
    case (_, outs): String.join(outs, "|")

def receive(+st: Sess.Session, +line: String) -> Sess.Session & List<&2, String>:
  Sess.step_on_chunk(st, Fr.string_to_octets(line ++ "\r\n"))

def trusted(+st: Sess.Session, +line: String) -> Sess.Session:
  chunk_state(receive(st, line))

def ascii_session_topic_brace_only() -> Bool:
  +iso = ascii_server()
  +st = trusted(live(iso, ascii_bracket_client(), "#a{"), ":op!u@h TOPIC #a{ :session topic")
  String.eq(buf_topic_cm(Sess.session_cl(st), "ascii", "#a{"), "session topic")
    && String.is_empty(buf_topic_cm(Sess.session_cl(st), "ascii", "#a["))

def ascii_session_mode_brace_only() -> Bool:
  +iso = ascii_server()
  +st = trusted(live(iso, ascii_bracket_client(), "#a{"), ":op!u@h MODE #a{ +m")
  String.contains(show_buf_tail_cm(Sess.session_cl(st), "ascii", "#a{"), "MODE")
    && Bool.not(String.contains(show_buf_tail_cm(Sess.session_cl(st), "ascii", "#a["), "MODE"))

def saved(+names: List<&2, String>) -> Sess.Session:
  Sess.session_seed_channels(Sess.session_online(Sess.session_with_client_at(base(), "", 6697)), names)

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
  +hash = hash_channel()
  +joined = result_session(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room")))
  +offline_joined = Sess.session_set_net(joined, Sess.Offline{})
  +reconnecting_joined = Sess.session_set_net(result_session(Sess.step_keys(live(iso, cl, ""), Sess.keys_enter("/join $room"))), Sess.Reconnecting{})
  +muted = result_session(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mute alice")))
  +unmuted = result_session(Sess.step_keys(muted, Sess.keys_enter("/unmute alice")))
  +seeded = Sess.session_seed_channels(live(Is.defaults(), cl, ""), ["$room"])
  +burst_welcome = chunk_state(receive(saved(["$room", "#a[", "#a{"]), ":irc 001 me :welcome"))
  +burst_network = chunk_state(receive(burst_welcome, ":irc 005 me NETWORK=Example :are supported"))
  +burst_policy = chunk_state(receive(burst_network, ":irc 005 me CHANTYPES=#$ CASEMAPPING=ascii :are supported"))
  +hash_refused_welcome = chunk_state(receive(saved(["#room"]), ":irc 001 me :welcome"))
  +hash_refused_policy = chunk_state(receive(hash_refused_welcome, ":irc 005 me CHANTYPES=$ :are supported"))
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
    Unit <- E.must_eq("saved negotiated-only candidate survives 001", String.join(Sess.session_desired_channels(chunk_state(receive(saved(["$room"]), ":irc 001 me :welcome"))), "|"), "$room")
    Unit <- E.must_eq("001 does not flush saved negotiated-only candidate", chunk_wire(receive(saved(["$room"]), ":irc 001 me :welcome")), "")
    Unit <- E.must_eq("first 005 NETWORK does not delete or flush exact candidates", String.join(Sess.session_desired_channels(burst_network), "|"), "$room|#a[|#a{")
    Unit <- E.must_eq("first 005 NETWORK produces no JOIN", chunk_wire(receive(burst_welcome, ":irc 005 me NETWORK=Example :are supported")), "")
    Unit <- E.must_eq("later policy 005 still produces no JOIN", chunk_wire(receive(burst_network, ":irc 005 me CHANTYPES=#$ CASEMAPPING=ascii :are supported")), "")
    Unit <- E.must_eq("376 flushes all final-policy candidates once", chunk_wire(receive(burst_policy, ":irc 376 me :end of MOTD")), "JOIN $room|JOIN #a[|JOIN #a{")
    Unit <- E.must_eq("repeated 376 does not repeat JOINs", chunk_wire(receive(chunk_state(receive(burst_policy, ":irc 376 me :end of MOTD")), ":irc 376 me :end of MOTD")), "")
    Unit <- E.must_eq("376 does not JOIN saved hash channel refused by CHANTYPES", chunk_wire(receive(hash_refused_policy, ":irc 376 me :end of MOTD")), "")
    Unit <- E.must_eq("376 drops saved hash channel refused by CHANTYPES", String.join(Sess.session_desired_channels(chunk_state(receive(hash_refused_policy, ":irc 376 me :end of MOTD"))), "|"), "")
    Unit <- E.must_eq("001 then 376 without 005 emits ordinary saved channel", chunk_wire(receive(chunk_state(receive(saved(["#room"]), ":irc 001 me :welcome")), ":irc 376 me :end of MOTD")), "JOIN #room")
    Unit <- E.must_eq("422 also releases ordinary saved channel", chunk_wire(receive(chunk_state(receive(saved(["#room"]), ":irc 001 me :welcome")), ":irc 422 me :no MOTD")), "JOIN #room")
    Unit <- E.must_eq("out-of-order 376 cannot make a later 001 flush", chunk_wire(receive(chunk_state(receive(saved(["#room"]), ":irc 376 me :early")), ":irc 001 me :welcome")), "")
    Unit <- E.must_eq("other server 376 cannot release saved channel", chunk_wire(receive(chunk_state(receive(saved(["#room"]), ":irc 001 me :welcome")), ":other 376 me :end of MOTD")), "")
    Unit <- E.must_eq("provisional RFC1459 does not fold dormant candidates", String.join(Sess.session_desired_channels(chunk_state(receive(saved(["#a[", "#a{"]), ":irc 001 me :welcome"))), "|"), "#a[|#a{")
    Unit <- E.must_eq("post-001 ascii waits through 005", chunk_wire(receive(chunk_state(receive(saved(["#a[", "#a{"]), ":irc 001 me :welcome")), ":irc 005 me CASEMAPPING=ascii :are supported")), "")
    Unit <- E.must_eq("post-001 ascii emits both exact saved channels at 376", chunk_wire(receive(chunk_state(receive(chunk_state(receive(saved(["#a[", "#a{"]), ":irc 001 me :welcome")), ":irc 005 me CASEMAPPING=ascii :are supported")), ":irc 376 me :end of MOTD")), "JOIN #a[|JOIN #a{")
    Unit <- E.must_eq("post-001 RFC1459 folds once at 376", chunk_wire(receive(chunk_state(receive(chunk_state(receive(saved(["#a[", "#a{"]), ":irc 001 me :welcome")), ":irc 005 me CASEMAPPING=rfc1459 :are supported")), ":irc 376 me :end of MOTD")), "JOIN #a[")
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
    Unit <- E.must_eq("MODE plus flag targets active hash channel before 005", wire(Sess.step_keys(live(Is.defaults(), hash, "#room"), Sess.keys_enter("/mode +i"))), "MODE #room +i")
    Unit <- E.must_eq("MODE plus argument targets active hash channel before 005", wire(Sess.step_keys(live(Is.defaults(), hash, "#room"), Sess.keys_enter("/mode +o alice"))), "MODE #room +o alice")
    Unit <- E.must_eq("MODE plus key targets active hash channel before 005", wire(Sess.step_keys(live(Is.defaults(), hash, "#room"), Sess.keys_enter("/mode +k secret"))), "MODE #room +k secret")
    Unit <- E.must_eq("MODE plus flag targets active hash channel after trusted plus CHANTYPE withdrawal", wire(Sess.step_keys(trusted(live(Is.defaults(), hash, "#room"), ":irc 005 me CHANTYPES=# :are supported"), Sess.keys_enter("/mode +i"))), "MODE #room +i")
    Unit <- E.must_eq("MODE plus argument targets active hash channel", wire(Sess.step_keys(trusted(live(Is.defaults(), hash, "#room"), ":irc 005 me CHANTYPES=# :are supported"), Sess.keys_enter("/mode +o alice"))), "MODE #room +o alice")
    Unit <- E.must_eq("MODE plus-prefixed channel query remains explicit while plus is a CHANTYPE", wire(Sess.step_keys(live(Is.defaults(), hash, "#room"), Sess.keys_enter("/mode +#other"))), "MODE +#other")
    Unit <- E.must_eq("MODE plus negotiated-dollar channel remains explicit", wire(Sess.step_keys(live(iso, dollar, "$room"), Sess.keys_enter("/mode +$other"))), "MODE +$other")
    Unit <- E.must_eq("MODE signed letter word stays flags while plus is a CHANTYPE", wire(Sess.step_keys(live(Is.defaults(), hash, "#room"), Sess.keys_enter("/mode +other"))), "MODE #room +other")
    Unit <- E.must_eq("resident plus channel query is not active-channel flags", wire(Sess.step_keys(live(Is.defaults(), plus_resident(), "#room"), Sess.keys_enter("/mode +local"))), "MODE +local")
    Unit <- E.must_eq("resident plus channel with modes is not active-channel flags", wire(Sess.step_keys(live(Is.defaults(), plus_resident(), "#room"), Sess.keys_enter("/mode +local +m"))), "MODE +local +m")
    Unit <- E.must_eq("unseen plus word with a following mode is an explicit target", wire(Sess.step_keys(live(Is.defaults(), hash, "#room"), Sess.keys_enter("/mode +else +m"))), "MODE +else +m")
    Unit <- E.must_eq("MODE plus flag targets active negotiated dollar channel", wire(Sess.step_keys(trusted(live(Is.defaults(), dollar, "$room"), ":irc 005 me CHANTYPES=$ :are supported"), Sess.keys_enter("/mode +i"))), "MODE $room +i")
    Unit <- E.must_eq("TOPIC plus text stays active-channel text", wire(Sess.step_keys(trusted(live(Is.defaults(), hash, "#room"), ":irc 005 me CHANTYPES=# :are supported"), Sess.keys_enter("/topic +hello"))), "TOPIC #room :+hello")
    Unit <- E.must_eq("MODE still rejects non-word arguments", wire(Sess.step_keys(trusted(live(Is.defaults(), hash, "#room"), ":irc 005 me CHANTYPES=# :are supported"), Sess.keys_enter("/mode :bad"))), "")
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
    Unit <- E.must("ascii negotiated JOIN creates two distinct bracket buffers", ascii_bracket_join_two_buffers())
    Unit <- E.must("ascii negotiated PART removes only the exact bracket target", ascii_part_brace_keeps_bracket())
    Unit <- E.must("ascii negotiated CLOSE removes only the exact bracket target", ascii_close_brace_keeps_bracket())
    Unit <- E.must_eq("ascii negotiated MODE resident targets exact bracket sibling",
      submit_wire(Sub.submit_with(ascii_server(), ascii_bracket_client(), "/mode #a{ +m")), "MODE #a{ +m")
    Unit <- E.must("rfc1459 negotiated JOIN folds bracket siblings into one buffer",
      Nat.is_eq(Cl.normal_buffer_count(Cl.client_bufs(rfc1459_bracket_client())), 2n))
    Unit <- E.must("ascii negotiated TOPIC updates only the brace sibling", ascii_topic_hits_brace_only())
    Unit <- E.must("ascii negotiated MODE logs only the brace sibling", ascii_mode_logs_brace_only())
    Unit <- E.must("ascii Session TOPIC updates only the brace sibling", ascii_session_topic_brace_only())
    Unit <- E.must("ascii Session MODE logs only the brace sibling", ascii_session_mode_brace_only())
    IO.print("session_isupport_submit=ok")
