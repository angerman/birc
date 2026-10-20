# Workspace wiring goldens: per-server partitions, server+generation
# routing, credential/history isolation, and endpoint replacement.
# Positive controls route and admit; negative controls fail closed.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as S
import ../../src/bend/session.bend as Sess
import ../../src/bend/isupport.bend as Iso
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/drafts.bend as D
import ../../src/bend/session_drafts.bend as AD
import ../../src/bend/workspace.bend as W
import ../../src/bend/typing.bend as Ty
import ../../src/bend/frame.bend as Fr

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

def s2() -> Key.ServerId:
  Key.ServerId{2n}

def s3() -> Key.ServerId:
  Key.ServerId{3n}

def bad4() -> Key.ServerId:
  Key.ServerId{4n}

def pair() -> W.Workspace:
  W.do_add(W.single("a.example", 6697, False{}, "me", "#a"), "b.example", 6697, False{}, "me", "#b")

def online.got(+ws: W.Workspace, +got: Maybe<&2, W.Part>) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, +st}:
          W.replace_part(ws, W.Part{id, gen, scope, Sess.session_online(st)})

def online(+ws: W.Workspace, +id: Key.ServerId) -> W.Workspace:
  online.got(ws, W.find_part(ws, id))

def rooms() -> W.Workspace:
  +ws = online(online(pair(), s0()), s1())
  W.do_enter(W.do_switch(W.do_enter(ws, "/join #a"), s1()), "/join #b")

def cl_of(+ws: W.Workspace, +id: Key.ServerId) -> Cl.Client:
  W.isolation.client_of(ws, id)

def nbufs(+ws: W.Workspace, +id: Key.ServerId) -> Nat:
  List.length(&2, Cl.Buffer, Cl.client_bufs(cl_of(ws, id)))

def texts(+ws: W.Workspace, +id: Key.ServerId, +i: Nat) -> String:
  CL.buf_texts(cl_of(ws, id), i)

def part_st.got(+got: Maybe<&2, W.Part>) -> Sess.Session:
  match got:
    case None{}: Sess.session_demo(Cl.init("nobody", "nowhere.example"), "#lost")
    case Some{+p}: W.part_session(p)

def part_st(+ws: W.Workspace, +id: Key.ServerId) -> Sess.Session:
  part_st.got(W.find_part(ws, id))

def add_ok.got(trip: W.Workspace & Bool) -> Bool:
  match trip:
    case (_, ok): ok

def add_ok(+ws: W.Workspace, +host: String, +port: U32, v6: Bool, +nick: String, +chan: String) -> Bool:
  add_ok.got(W.add_server(ws, host, port, v6, nick, chan))

def switch_ok.got(trip: W.Workspace & Bool) -> Bool:
  match trip:
    case (_, ok): ok

def switch_ok(+ws: W.Workspace, +id: Key.ServerId) -> Bool:
  switch_ok.got(W.switch_server(ws, id))

def remove_ok.got(trip: W.Workspace & Bool) -> Bool:
  match trip:
    case (_, ok): ok

def remove_ok(+ws: W.Workspace, +id: Key.ServerId) -> Bool:
  remove_ok.got(W.remove_server(ws, id))

def drafts_of(+ws: W.Workspace, +id: Key.ServerId, +key: String) -> String:
  D.get(W.ws_drafts(ws), id, key)

def has_draft(+ws: W.Workspace, +id: Key.ServerId, +key: String) -> Bool:
  D.has(W.ws_drafts(ws), id, key)

def key_or(+got: Maybe<&2, String>) -> String:
  match got:
    case None{}: "[none]"
    case Some{+k}: k

def routed_outs(+rc: Sid.RoutedCmd) -> List<&2, String>:
  match rc:
    case Sid.RoutedCmd{_, +cmd}:
      match cmd:
        case Sess.Cont{+outs}: outs
        case _: Nil{}

def credentialed.got(+ws: W.Workspace, +got: Maybe<&2, W.Part>, +host: String) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, +st}:
          +cl = Cl.client_set_auth(Sess.session_cl(st), Cl.SaslOnly{}, host, 6697, "", "", "u", "p")
          W.replace_part(ws, W.Part{id, gen, scope, Sess.session_set_client(st, cl)})

def credentialed(+ws: W.Workspace, +id: Key.ServerId, +host: String) -> W.Workspace:
  credentialed.got(ws, W.find_part(ws, id), host)

def edited.got(+ws: W.Workspace, +got: Maybe<&2, W.Part>) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, +st}:
          W.replace_part(ws, W.Part{id, gen, scope, Sess.session_preference_record(Some{"bell"}, st)})

def edited(+ws: W.Workspace, +id: Key.ServerId) -> W.Workspace:
  edited.got(ws, W.find_part(ws, id))

# F7 casemapping-alias fixture: part s0 carries ascii-negotiated #a[/#a{
# buffers (built directly because /join stages under the default map);
# sibling parts keep their own maps. Reads fold under each part's own map.
def ascii_iso() -> Iso.State:
  Iso.apply_line(Iso.defaults(), ":s 005 me CASEMAPPING=ascii :are supported")

def alias_bufs() -> List<&2, Cl.Buffer>:
  Cl.server_buf() <> Cl.empty_buf("#a[", True{}) <> Cl.empty_buf("#a{", True{}) <> Nil{}

def alias_ascii.got(+ws: W.Workspace, +got: Maybe<&2, W.Part>) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, +st}:
          +cl : Cl.Client = Cl.Client{"me", "a.example", alias_bufs(), 2n, "", Cl.settings0(), Cl.AuthIdle{}, 0n, False{}}
          W.replace_part(ws, W.Part{id, gen, scope, Sess.session_set_iso(Sess.session_set_client(st, cl), ascii_iso())})

def alias_ascii(+ws: W.Workspace, +id: Key.ServerId) -> W.Workspace:
  alias_ascii.got(ws, W.find_part(ws, id))

def drafts_live(+ws: W.Workspace, +id: Key.ServerId, +key: String) -> String:
  D.get_cm(W.ws_drafts(ws), id, key, Sess.session_cm(part_st(ws, id)))

def cur_composer(+ws: W.Workspace) -> String:
  Sess.session_draft(part_st(ws, W.ws_current(ws)))

def ctl(+n: U32, +s: String) -> String:
  SCon{Chr{n}, s}

# G3 routed fixture: A negotiates ascii + $ CHANTYPE; B stays default.
# Both parts receive the SAME styled a[/a{ pair (B on #room).
def g3_005a() -> String:
  ":a.example 005 me CASEMAPPING=ascii CHANTYPES=#&+!$ :are supported\r\n"

def g3_joina() -> String:
  ":me!u@h JOIN $room\r\n"

def g3_joinb() -> String:
  ":me!u@h JOIN #room\r\n"

def g3_tags_a() -> String:
  "@+typing=active :a[" ++ ctl(2, "b") ++ "!u@h TAGMSG " ++ ctl(2, "$room") ++ "\r\n@+typing=active :a{" ++ ctl(2, "b") ++ "!u@h TAGMSG " ++ ctl(2, "$room") ++ "\r\n"

def g3_tags_b() -> String:
  "@+typing=active :a[" ++ ctl(2, "b") ++ "!u@h TAGMSG #room\r\n@+typing=active :a{" ++ ctl(2, "b") ++ "!u@h TAGMSG #room\r\n"

def g3_clears_a() -> String:
  ":a{b!u@h PRIVMSG $room :hi\r\n"

def g3_feed.got(+o: W.LiveMsgOut) -> W.Workspace:
  match o:
    case W.LiveMsgOut{+ws2, _, _, _}:
      ws2

def g3_feed(+ws: W.Workspace, +id: Key.ServerId, +text: String) -> W.Workspace:
  g3_feed.got(W.live_on_msg(ws, Sid.RoutedMsg{id, Sess.FromNet{W.part_gen_of(ws, id), Sess.Chunk{Fr.string_to_octets(text), 0}}}, Nil{}, 1000, "00:00:00"))

def g3_joined() -> W.Workspace:
  +w0 = online(online(pair(), s0()), s1())
  +w1 = g3_feed(w0, s0(), g3_005a())
  +w2 = g3_feed(w1, s0(), g3_joina())
  g3_feed(w2, s1(), g3_joinb())

def g3_set_stage() -> W.Workspace:
  +w0 = g3_joined()
  +w1 = g3_feed(w0, s0(), g3_tags_a())
  g3_feed(w1, s1(), g3_tags_b())

def g3_clear_stage(+ws: W.Workspace) -> W.Workspace:
  g3_feed(ws, s0(), g3_clears_a())

def g3_count(+ws: W.Workspace, +id: Key.ServerId) -> Nat:
  Ty.count(Sess.session_typing(part_st(ws, id)))

def g3_cm(+ws: W.Workspace, +id: Key.ServerId) -> String:
  Sess.session_cm(part_st(ws, id))

def g3_ty(+ws: W.Workspace, +id: Key.ServerId) -> Ty.State:
  Sess.session_typing(part_st(ws, id))

def g3_a_set_ok(+ws: W.Workspace) -> Bool:
  Ty.has_cm("ascii", g3_ty(ws, s0()), "$room", "a[b")
    && Ty.has_cm("ascii", g3_ty(ws, s0()), "$room", "a{b")

def g3_a_clr_ok(+ws: W.Workspace) -> Bool:
  Ty.has_cm("ascii", g3_ty(ws, s0()), "$room", "a[b")
    && Bool.not(Ty.has_cm("ascii", g3_ty(ws, s0()), "$room", "a{b"))

def g3_b_fold_ok(+ws: W.Workspace) -> Bool:
  Ty.has_cm("rfc1459", g3_ty(ws, s1()), "#room", "a[b")
    && Ty.has_cm("rfc1459", g3_ty(ws, s1()), "#room", "a{b")

def main() -> IO(Unit):
  +one = W.single("a.example", 6697, False{}, "me", "#a")
  +two = pair()
  +full = W.do_add(W.do_add(two, "c.example", 6697, False{}, "me", "#c"), "d.example", 6697, False{}, "me", "#d")
  +ws = rooms()
  +stepped = W.do_enter(ws, "/join #extra")
  +rc = W.step_routed(ws, Sess.keys_enter("/join #extra"))
  +on_a = W.do_switch(W.do_enter(W.do_switch(ws, s0()), "/join #x"), s1())
  +both_x = W.do_enter(on_a, "/join #x")
  +typed_a = W.do_step(W.do_switch(both_x, s0()), AD.typing_keys("A0"))
  +typed_b = W.do_step(W.do_switch(typed_a, s1()), AD.typing_keys("B1"))
  +dial_ws = online(pair(), s0())
  +dialed = W.do_enter(dial_ws, "/connect c.example 6697")
  +gen1 = W.part_gen_of(dialed, s0())
  +removed = W.do_remove(W.do_switch(two, s1()), s1())
  +cred = credentialed(credentialed(two, s0(), "a.example"), s1(), "b.example")
  +cred_same = W.do_replace(cred, s0(), "a.example", 6697, False{})
  +cred_case = W.do_replace(cred, s0(), "A.example", 6697, False{})
  +cred_port = W.do_replace(cred, s0(), "a.example", 6698, False{})
  +v6 = W.do_add(two, "::1", 6697, True{}, "me", "#v6")
  +alias0 = alias_ascii(pair(), s0())
  +wtyped = W.do_step(alias0, AD.typing_keys("B"))
  +wclick = W.do_step(wtyped, AD.click_keys("B", 1n))
  +wtyped2 = W.do_step(wclick, AD.typing_keys("A"))
  +wback = W.do_step(wtyped2, AD.click_keys("A", 2n))
  +waway = W.cycle_ws(W.cycle_server(wback, "B"))
  +wret = W.cycle_ws(W.cycle_server(waway, ""))
  +tset = g3_set_stage()
  +tclr = g3_clear_stage(tset)
  do IO<Unit>:
    Unit <- E.must("single starts with one part", Nat.is_eq(W.ws_nparts(one), 1n))
    Unit <- E.must("single current is first", Key.eq(W.ws_current(one), s0()))
    Unit <- E.must_eq("single history key is scope", key_or(W.history_key(one, s0())), "a.example:6697")
    Unit <- E.must("add admits second server", add_ok(one, "b.example", 6697, False{}, "me", "#b"))
    Unit <- E.must("add keeps current", Key.eq(W.ws_current(two), s0()))
    Unit <- E.must("third and fourth admit", add_ok(W.do_add(two, "c.example", 6697, False{}, "me", "#c"), "d.example", 6697, False{}, "me", "#d"))
    Unit <- E.must("fifth server refused", Bool.not(add_ok(full, "e.example", 6697, False{}, "me", "#e")))
    Unit <- E.must("full keeps four parts", Nat.is_eq(W.ws_nparts(full), 4n))
    Unit <- E.must("switch to present admits", switch_ok(two, s1()))
    Unit <- E.must("switch to invalid refuses", Bool.not(switch_ok(two, bad4())))
    Unit <- E.must("switch to absent valid refuses", Bool.not(switch_ok(two, s3())))
    Unit <- E.must("switch keeps current on refuse", Key.eq(W.ws_current(W.do_switch(two, bad4())), s0()))
    Unit <- E.must("step joins on current only", Nat.is_eq(nbufs(stepped, s1()), 3n))
    Unit <- E.must("step leaves other part alone", Nat.is_eq(nbufs(stepped, s0()), nbufs(ws, s0())))
    Unit <- E.must_eq("other part text untouched", texts(stepped, s0(), 1n), texts(ws, s0(), 1n))
    Unit <- E.must("routed command tags current", Key.eq(W.routed_server(rc), s1()))
    Unit <- E.must_eq("routed join is cont", Sess.show_netcmd(W.routed_cmd(rc)), "cont")
    Unit <- E.must_eq("server zero keeps own draft", drafts_of(typed_b, s0(), "#x"), "A0")
    Unit <- E.must_eq("server one keeps own draft", drafts_of(typed_b, s1(), "#x"), "B1")
    Unit <- E.must("plans partition per server", String.contains(String.join(Sess.session_desired_channels(part_st(both_x, s0())), "|"), "#a"))
    Unit <- E.must("other plan omits foreign room", Bool.not(String.contains(String.join(Sess.session_desired_channels(part_st(both_x, s1())), "|"), "#a")))
    Unit <- E.must("prefs partition per server", String.contains(String.join(Sess.session_preference_edits(part_st(edited(two, s0()), s0())), "|"), "bell"))
    Unit <- E.must("other prefs stay empty", List.is_empty(&2, String, Sess.session_preference_edits(part_st(edited(two, s0()), s1()))))
    Unit <- E.must("dial bumps generation", U32.is_eq(gen1, 1))
    Unit <- E.must_eq("dial routes with new scope", Sess.show_netcmd(W.routed_cmd(W.step_routed(dial_ws, Sess.keys_enter("/connect c.example 6697")))), "dial:c.example:6697")
    Unit <- E.must_eq("dial refreshes scope key", key_or(W.history_key(dialed, s0())), "c.example:6697")
    Unit <- E.must("stale dial dropped", Bool.not(W.cmd_admitted(dialed, Sid.dial_for(s0(), "c.example", 6697, 0, "me"))))
    Unit <- E.must("fresh dial admitted", W.cmd_admitted(dialed, Sid.dial_for(s0(), "c.example", 6697, gen1, "me")))
    Unit <- E.must("stale pump dropped", Bool.not(W.cmd_admitted(dialed, Sid.RoutedCmd{s0(), Sess.Pump{0}})))
    Unit <- E.must("fresh pump admitted", W.cmd_admitted(dialed, Sid.RoutedCmd{s0(), Sess.Pump{gen1}}))
    Unit <- E.must("stale pong dropped", Bool.not(W.cmd_admitted(dialed, Sid.RoutedCmd{s0(), Sess.Pong{0, "PONG :x" <> Nil{}, 0}})))
    Unit <- E.must("fresh pong admitted", W.cmd_admitted(dialed, Sid.RoutedCmd{s0(), Sess.Pong{gen1, "PONG :x" <> Nil{}, 0}}))
    Unit <- E.must("search needs server only", W.cmd_admitted(dialed, Sid.RoutedCmd{s0(), Sess.Search{"q", "#a", 0n, "q", "a.example:6697", True{}, 1n, 3n, 0}}))
    Unit <- E.must("search invalid server dropped", Bool.not(W.cmd_admitted(dialed, Sid.RoutedCmd{bad4(), Sess.Search{"q", "#a", 0n, "q", "a.example:6697", True{}, 1n, 3n, 0}})))
    Unit <- E.must("cont needs no generation", W.cmd_admitted(dialed, Sid.cont_for(s0(), Nil{})))
    Unit <- E.must("cross-server dial dropped", Bool.not(W.cmd_admitted(dialed, Sid.dial_for(s1(), "c.example", 6697, gen1, "me"))))
    Unit <- E.must("invalid-id dial dropped", Bool.not(W.cmd_admitted(dialed, Sid.dial_for(bad4(), "c.example", 6697, gen1, "me"))))
    Unit <- E.must("absent-part dial dropped", Bool.not(W.cmd_admitted(dialed, Sid.dial_for(s3(), "c.example", 6697, gen1, "me"))))
    Unit <- E.must("stale event dropped", Bool.not(W.msg_admitted(dialed, Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Eof{}}})))
    Unit <- E.must("fresh event admitted", W.msg_admitted(dialed, Sid.RoutedMsg{s0(), Sess.FromNet{gen1, Sess.Eof{}}}))
    Unit <- E.must("sibling keeps own generation", W.msg_admitted(dialed, Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Eof{}}}))
    Unit <- E.must("generation is per server", Bool.not(W.msg_admitted(dialed, Sid.RoutedMsg{s1(), Sess.FromNet{gen1, Sess.Eof{}}})))
    Unit <- E.must("gen-free event admitted", W.msg_admitted(dialed, Sid.RoutedMsg{s0(), Sess.UiKey{}}))
    Unit <- E.must("invalid-id event dropped", Bool.not(W.msg_admitted(dialed, Sid.RoutedMsg{bad4(), Sess.UiKey{}})))
    Unit <- E.must("current writer done acks", W.writer_done_acked(dialed, Sid.RoutedMsg{s0(), Sess.FromNet{gen1, Sess.WriterDone{}}}))
    Unit <- E.must("stale writer done ignored", Bool.not(W.writer_done_acked(dialed, Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.WriterDone{}}})))
    # The next negative carries s0's generation, which is stale for s1.
    # A sibling's own current generation must acknowledge that sibling.
    Unit <- E.must("sibling writer done ignored", Bool.not(W.writer_done_acked(dialed, Sid.RoutedMsg{s1(), Sess.FromNet{gen1, Sess.WriterDone{}}})))
    Unit <- E.must("sibling current writer done acks its own part", W.writer_done_acked(dialed, Sid.RoutedMsg{s1(), Sess.FromNet{W.part_gen_of(dialed, s1()), Sess.WriterDone{}}}))
    Unit <- E.must("reader eof never acks", Bool.not(W.writer_done_acked(dialed, Sid.RoutedMsg{s0(), Sess.FromNet{gen1, Sess.Eof{}}})))
    Unit <- E.must("same endpoint keeps drafts", has_draft(W.do_replace(W.do_step(two, AD.typing_keys("aa")), s0(), "a.example", 6697, False{}), s0(), "*server*"))
    Unit <- E.must("slot replace clears drafts", Bool.not(has_draft(W.do_replace(W.do_step(two, AD.typing_keys("aa")), s0(), "c.example", 6697, False{}), s0(), "*server*")))
    Unit <- E.must("slot replace keeps sibling drafts", has_draft(W.do_replace(W.do_step(W.do_switch(two, s1()), AD.typing_keys("bb")), s0(), "c.example", 6697, False{}), s1(), "*server*"))
    Unit <- E.must("same endpoint keeps credentials", Cl.client_has_credentials(cl_of(cred_same, s0())))
    Unit <- E.must("case change clears credentials", Bool.not(Cl.client_has_credentials(cl_of(cred_case, s0()))))
    Unit <- E.must("port change clears credentials", Bool.not(Cl.client_has_credentials(cl_of(cred_port, s0()))))
    Unit <- E.must("replace keeps sibling credentials", Cl.client_has_credentials(cl_of(cred_case, s1())))
    Unit <- E.must("credential scope exact admits", W.credential_ok(two, s0(), "a.example", 6697))
    Unit <- E.must("credential scope case refuses", Bool.not(W.credential_ok(two, s0(), "A.example", 6697)))
    Unit <- E.must("credential scope port refuses", Bool.not(W.credential_ok(two, s0(), "a.example", 6698)))
    Unit <- E.must("credential scope zero port refuses", Bool.not(W.credential_ok(two, s0(), "a.example", 0)))
    Unit <- E.must("credential scope unknown refuses", Bool.not(W.credential_ok(two, s3(), "a.example", 6697)))
    Unit <- E.must("history admits exact scope", W.history_admits(two, s0(), "a.example:6697"))
    Unit <- E.must("history admits case-folded scope", W.history_admits(two, s0(), "A.Example:6697"))
    Unit <- E.must("history refuses sibling scope", Bool.not(W.history_admits(two, s0(), "b.example:6697")))
    Unit <- E.must("history refuses other port", Bool.not(W.history_admits(two, s0(), "a.example:6698")))
    Unit <- E.must("history refuses unknown part", Bool.not(W.history_admits(two, s3(), "a.example:6697")))
    Unit <- E.must_eq("v6 history key brackets literal", key_or(W.history_key(v6, s2())), "[::1]:6697")
    Unit <- E.must("remove refuses unknown", Bool.not(remove_ok(two, s3())))
    Unit <- E.must("remove refuses last part", Bool.not(remove_ok(one, s0())))
    Unit <- E.must("remove drops part", Nat.is_eq(W.ws_nparts(removed), 1n))
    Unit <- E.must("remove current falls back", Key.eq(W.ws_current(removed), s0()))
    Unit <- E.must("remove clears slot drafts", Bool.not(has_draft(W.do_remove(W.do_step(W.do_switch(two, s1()), AD.typing_keys("bb")), s1()), s1(), "*server*")))
    Unit <- E.must("multiline routes on current", Nat.is_eq(List.length(&2, String, routed_outs(W.step_routed(ws, Sess.keys_enter("aa\nbb")))), 2n))
    Unit <- E.must("routed wires fit 512 bytes", S.out_all_ok(routed_outs(W.step_routed(ws, Sess.keys_enter("aa\nbb")))))
    Unit <- E.must_eq("routed multiline complete wire order", String.join(routed_outs(W.step_routed(ws, Sess.keys_enter("aa\nbb"))), "|"), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must("missing current fails closed", String.eq(Sess.show_netcmd(W.routed_cmd(W.step_routed(W.Workspace{W.ws_parts(two), bad4(), W.ws_drafts(two), W.ws_retired(two)}, Sess.keys_enter("hi")))), "drop"))
    Unit <- E.must_eq("f7 setup keeps first alias draft", drafts_live(wback, s0(), "#a["), "A")
    Unit <- E.must_eq("f7 setup keeps origin draft", drafts_live(wback, s0(), "#a{"), "B")
    Unit <- E.must_eq("f7 setup reseeds origin", cur_composer(wback), "B")
    Unit <- E.must("f7 cycle away moves", W.cycle_moved(W.cycle_server(wback, "B")))
    Unit <- E.must("f7 cycle away switches server", Key.eq(W.ws_current(waway), s1()))
    Unit <- E.must_eq("f7 cycle loads sibling draft", cur_composer(waway), "")
    Unit <- E.must_eq("f7 cycle keeps origin draft", drafts_live(waway, s0(), "#a["), "A")
    Unit <- E.must("f7 cycle back moves", W.cycle_moved(W.cycle_server(waway, "")))
    Unit <- E.must("f7 cycle back restores server", Key.eq(W.ws_current(wret), s0()))
    Unit <- E.must_eq("f7 cycle back reseeds origin draft", cur_composer(wret), "B")
    Unit <- E.must_eq("f7 origin draft exact after cycle", drafts_live(wret, s0(), "#a{"), "B")
    Unit <- E.must_eq("f7 sibling draft stays empty", drafts_live(wret, s1(), "*server*"), "")
    Unit <- E.must("isolation law holds", W.isolation_ok())
    Unit <- E.must("generation law holds", W.generation_ok())
    Unit <- E.must("endpoint law holds", W.endpoint_ok())
    Unit <- E.must("routed ascii part holds styled pair", Nat.is_eq(g3_count(tset, s0()), 2n))
    Unit <- E.must("routed default part holds one typer", Nat.is_eq(g3_count(tset, s1()), 1n))
    Unit <- E.must("matching clear leaves one ascii survivor", Nat.is_eq(g3_count(tclr, s0()), 1n))
    Unit <- E.must("clear leaves sibling part unchanged", Nat.is_eq(g3_count(tclr, s1()), 1n))
    Unit <- E.must_eq("routed ascii part cm", g3_cm(tset, s0()), "ascii")
    Unit <- E.must_eq("routed default part cm", g3_cm(tset, s1()), "rfc1459")
    Unit <- E.must("ascii pair identities exact", g3_a_set_ok(tset))
    Unit <- E.must("ascii clear keeps exact survivor", g3_a_clr_ok(tclr))
    Unit <- E.must("default part folds bracket pair", g3_b_fold_ok(tset))
    Unit <- E.must("clear leaves default fold unchanged", g3_b_fold_ok(tclr))
    IO.print("workspace_demo=ok")
