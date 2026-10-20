# SessWS S1-S5 repair guards: epoch reuse, disconnected multiline, composer
# leak, submit-driven focus atomicity, per-line privacy. Negatives fail
# closed, positives control exact behavior. All synthetic, JS backend.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as S
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/frame.bend as F
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/drafts.bend as D
import ../../src/bend/session_drafts.bend as AD
import ../../src/bend/workspace.bend as W
import ../../src/bend/media.bend as M
import ../../src/bend/typing.bend as Ty
import ../../src/bend/history.bend as Hist
import ../../src/bend/history_search.bend as Hs
import ../../src/bend/outbound.bend as Out
import ../../src/bend/isupport.bend as Iso

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

def bad4() -> Key.ServerId:
  Key.ServerId{4n}

def ad_submitted.got(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl2, _): cl2

def ad_submitted(+cl: Cl.Client, +input: String) -> Cl.Client:
  ad_submitted.got(S.submit(cl, input))

def ad_rooms() -> Cl.Client:
  ad_submitted(ad_submitted(Cl.init("me", "irc.example"), "/join #a"), "/join #b")

def ad_demo() -> AD.AD:
  AD.wrap(Sess.session_demo(ad_rooms(), "#a"), s0())

def ad_online() -> AD.AD:
  AD.wrap(Sess.session_online(Sess.session_with_client(ad_rooms(), "#a")), s0())

def ad_with_net(net: Sess.NetState) -> AD.AD:
  AD.wrap(Sess.session_set_net(Sess.session_with_client(ad_rooms(), "#a"), net), s0())

def ad_cl(+ad: AD.AD) -> Cl.Client:
  Sess.session_cl(AD.ad_session(ad))

def ad_nbufs(+ad: AD.AD) -> Nat:
  List.length(&2, Cl.Buffer, Cl.client_bufs(ad_cl(ad)))

def ad_drafts_of(+ad: AD.AD, +key: String) -> String:
  D.get(AD.ad_drafts(ad), s0(), key)

def ad_has_draft(+ad: AD.AD, +key: String) -> Bool:
  D.has(AD.ad_drafts(ad), s0(), key)

def ad_nouts(+cmd: Sess.NetCmd) -> Nat:
  match cmd:
    case Sess.Cont{+outs}: List.length(&2, String, outs)
    case _: 999n

def ad_outs_ok(+cmd: Sess.NetCmd) -> Bool:
  match cmd:
    case Sess.Cont{+outs}: S.out_all_ok(outs)
    case _: False{}

def ad_hist_joined.hist(+hist: Sess.Hist) -> String:
  match hist:
    case Sess.Hist{lines, _}: String.join(lines, "|")

def ad_hist_joined.st(+st: Sess.Session) -> String:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, hist, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: ad_hist_joined.hist(hist)

def ad_hist_joined(+ad: AD.AD) -> String:
  ad_hist_joined.st(AD.ad_session(ad))

def ad_hist_len.hist(+hist: Sess.Hist) -> Nat:
  Sess.hist_len(hist)

def ad_hist_len.st(+st: Sess.Session) -> Nat:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, hist, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: ad_hist_len.hist(hist)

def ad_hist_len(+ad: AD.AD) -> Nat:
  ad_hist_len.st(AD.ad_session(ad))

def hist_keys() -> Sess.Keys:
  Sess.Keys{"", False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistPrev{}, 0, 0}

def ad_recall(+ad: AD.AD) -> String:
  AD.ad_composer(AD.do_step(ad, hist_keys()))

def ad_fill(n: Nat, +ds: D.Drafts) -> D.Drafts:
  match n:
    case 0n: ds
    case 1n+p: ad_fill(p, D.set(ds, s0(), "b" ++ Irc.stars.go(D.count(ds)), "x"))

def ad_full() -> AD.AD:
  AD.with_drafts(Sess.session_demo(ad_rooms(), "#a"), ad_fill(16n, D.empty()), s0())

def ws_pair() -> W.Workspace:
  W.do_add(W.single("a.example", 6697, False{}, "me", "#a"), "b.example", 6697, False{}, "me", "#b")

def ws_online.got(+ws: W.Workspace, +got: Maybe<&2, W.Part>) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, +st}:
          W.replace_part(ws, W.Part{id, gen, scope, Sess.session_online(st)})

def ws_online(+ws: W.Workspace, +id: Key.ServerId) -> W.Workspace:
  ws_online.got(ws, W.find_part(ws, id))

def ws_rooms() -> W.Workspace:
  +ws = ws_online(ws_online(ws_pair(), s0()), s1())
  W.do_enter(W.do_switch(W.do_enter(ws, "/join #a"), s1()), "/join #b")

def ws_cl_of(+ws: W.Workspace, +id: Key.ServerId) -> Cl.Client:
  W.isolation.client_of(ws, id)

def ws_nbufs(+ws: W.Workspace, +id: Key.ServerId) -> Nat:
  List.length(&2, Cl.Buffer, Cl.client_bufs(ws_cl_of(ws, id)))

def ws_texts(+ws: W.Workspace, +id: Key.ServerId, +i: Nat) -> String:
  CL.buf_texts(ws_cl_of(ws, id), i)

def ws_part_st.got(+got: Maybe<&2, W.Part>) -> Sess.Session:
  match got:
    case None{}: Sess.session_demo(Cl.init("nobody", "nowhere.example"), "#lost")
    case Some{+p}: W.part_session(p)

def ws_part_st(+ws: W.Workspace, +id: Key.ServerId) -> Sess.Session:
  ws_part_st.got(W.find_part(ws, id))

def ws_composer(+ws: W.Workspace, +id: Key.ServerId) -> String:
  Sess.session_draft(ws_part_st(ws, id))

def comp_keys(+typed: String) -> Sess.Keys:
  Sess.Keys{typed, False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 1, 0}

def ws_comp.show(+c: Sess.Comp) -> String:
  match c:
    case Sess.CompNone{}: "N"
    case Sess.CompActive{+pre, +word, idx}: "A:" ++ pre ++ "|" ++ word ++ "|" ++ Nat.show(idx)
    case Sess.CompUpload{_, _, _}: "U"
    case Sess.CompHelp{_}: "H"
    case Sess.CompHidden{}: "D"
    case Sess.CompPick{idx}: "P:" ++ Nat.show(idx)

def ws_comp.st(+st: Sess.Session) -> String:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, _, _, _, +comp, _, _, _, _, _, _, _, _, _, _, _, _, _}: ws_comp.show(comp)

def ws_comp(+ws: W.Workspace, +id: Key.ServerId) -> String:
  ws_comp.st(ws_part_st(ws, id))

def ws_seed(+ws: W.Workspace, +id: Key.ServerId) -> U32:
  Sess.session_seed(ws_part_st(ws, id))

def ws_size.show(+s: Sess.Size) -> String:
  match s:
    case Sess.Size{rows, cols}: U32.show(rows) ++ "x" ++ U32.show(cols)

def ws_size(+ws: W.Workspace, +id: Key.ServerId) -> String:
  ws_size.show(Sess.session_size(ws_part_st(ws, id)))

def ws_media_on(+ws: W.Workspace, +id: Key.ServerId) -> Bool:
  M.supported(Sess.session_media(ws_part_st(ws, id)))

def ws_drafts_of(+ws: W.Workspace, +id: Key.ServerId, +key: String) -> String:
  D.get(W.ws_drafts(ws), id, key)

def ws_has_draft(+ws: W.Workspace, +id: Key.ServerId, +key: String) -> Bool:
  D.has(W.ws_drafts(ws), id, key)

def ws_key_or(+got: Maybe<&2, String>) -> String:
  match got:
    case None{}: "[none]"
    case Some{+k}: k

def sid_show(+s: Key.ServerId) -> String:
  match s:
    case Key.ServerId{n}: Nat.show(n)

def dial_show(+cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Dial{+host, port, gen, +nick}: host ++ ":" ++ U32.show(port) ++ "@" ++ U32.show(gen) ++ "/" ++ nick
    case Sess.Cont{+outs}: "cont:" ++ Nat.show(List.length(&2, String, outs))
    case Sess.Drop{}: "drop"
    case Sess.Pump{gen}: "pump:" ++ U32.show(gen)
    case Sess.OpenUrl{+url}: "open:" ++ url
    case Sess.Begin{gen}: "begin:" ++ U32.show(gen)
    case Sess.Pong{gen, _, _}: "pong:" ++ U32.show(gen)
    case Sess.Search{+text, +target, +cursor, _, _, _, _, _, _}: "search:" ++ text ++ "|" ++ target ++ "|" ++ Nat.show(cursor)

def rc_show(+rc: Sid.RoutedCmd) -> String:
  match rc:
    case Sid.RoutedCmd{+s, +cmd}: sid_show(s) ++ ">" ++ dial_show(cmd)

def rcc_show(+got: Maybe<&2, Sid.RoutedCmd>) -> String:
  match got:
    case None{}: "[none]"
    case Some{+rc}: rc_show(rc)

def intent_show(+i: Sid.Intent) -> String:
  match i:
    case Sid.Intent{+s, gen, +host, port, v6}: sid_show(s) ++ ":" ++ U32.show(gen) ++ ":" ++ host ++ ":" ++ U32.show(port) ++ ":" ++ Bool.show(v6)

def int_show(+got: Maybe<&2, Sid.Intent>) -> String:
  match got:
    case None{}: "[none]"
    case Some{+i}: intent_show(i)

def intent_or_dead(+got: Maybe<&2, Sid.Intent>) -> Sid.Intent:
  match got:
    case None{}: Sid.Intent{bad4(), 0, "dead.invalid", 0, False{}}
    case Some{+i}: i

def ws_net(+ws: W.Workspace, +id: Key.ServerId) -> String:
  Sess.net_label(Sess.session_net(ws_part_st(ws, id)))

# G4 supplied-seam contract probes: build the same supplied submit + history
# the adapter hands Session and compare the seam triple field by field.
def t_quad.pair(pair: Cl.Client & List<&2, String>, split: Sp.State) -> Cl.Client & String & Sess.NetCmd & Sp.State:
  match pair:
    case (+cl2, +outs): (cl2, "", Sess.Cont{outs}, Sp.follow_active(cl2, split))

def t_outs(+cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Cont{+outs}: String.join(outs, "|")
    case _: "[noncont]"

# Production-submit projections: Sess.step_keys is the real entry the live
# frame loop calls (Net.apply_frame). These pin the Drafts/multiline seam
# through that entry, not through the adapter.
def prod_cmd.trip(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.NetCmd:
  match trip:
    case (_, +cmd, _): cmd

def prod_st.trip(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match trip:
    case (+st, _, _): st

def prod_halt.trip(trip: Sess.Session & Sess.NetCmd & Bool) -> Bool:
  match trip:
    case (_, _, halt): halt

def prod_outs(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  t_outs(prod_cmd.trip(trip))

def prod_texts(trip: Sess.Session & Sess.NetCmd & Bool, +i: Nat) -> String:
  CL.buf_texts(Sess.session_cl(prod_st.trip(trip)), i)

def prod_draft(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  Sess.session_draft(prod_st.trip(trip))

def prod_hist(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  ad_hist_joined.st(prod_st.trip(trip))

def prod_hist_len(trip: Sess.Session & Sess.NetCmd & Bool) -> Nat:
  ad_hist_len.st(prod_st.trip(trip))

def prod_halt(trip: Sess.Session & Sess.NetCmd & Bool) -> Bool:
  prod_halt.trip(trip)

# Triples are linear single-use, so each production assert below re-runs
# Sess.step_keys on a fresh fixture through these one-shot entries.
def prod_enter_outs(+line: String) -> String:
  prod_outs(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(line)))

def prod_enter_texts(+line: String, +i: Nat) -> String:
  prod_texts(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(line)), i)

def prod_enter_draft(+line: String) -> String:
  prod_draft(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(line)))

def prod_enter_hist(+line: String) -> String:
  prod_hist(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(line)))

def prod_enter_hist_len(+line: String) -> Nat:
  prod_hist_len(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(line)))

def prod_enter_halt(+line: String) -> Bool:
  prod_halt(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(line)))

def prod_enter_recall(+line: String) -> String:
  prod_draft(Sess.step_keys(prod_st.trip(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(line))), hist_keys()))

def prod_off_outs(+line: String) -> String:
  prod_outs(Sess.step_keys(Sess.session_set_net(Sess.session_with_client(ad_rooms(), "#a"), Sess.Offline{}), Sess.keys_enter(line)))

def prod_off_draft(+line: String) -> String:
  prod_draft(Sess.step_keys(Sess.session_set_net(Sess.session_with_client(ad_rooms(), "#a"), Sess.Offline{}), Sess.keys_enter(line)))

def prod_cred_outs(+first: String, +line: String) -> String:
  prod_outs(Sess.step_keys(prod_st.trip(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(first))), Sess.keys_enter(line)))

def prod_cred_texts(+first: String, +line: String, +i: Nat) -> String:
  prod_texts(Sess.step_keys(prod_st.trip(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(first))), Sess.keys_enter(line)), i)

def prod_cred_hist(+first: String, +line: String) -> String:
  prod_hist(Sess.step_keys(prod_st.trip(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.keys_enter(first))), Sess.keys_enter(line)))

def s2p_repeat(n: Nat, +s: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: s ++ s2p_repeat(p, s)

def t_summary.trip(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (+st2, +cmd, halt):
      t_outs(cmd) ++ ";" ++ Sess.session_draft(st2) ++ ";" ++ ad_hist_joined.st(st2)
        ++ ";" ++ Bool.show(halt) ++ ";" ++ AD.active_key(Sess.session_cl(st2))
        ++ ";" ++ U32.show(Sess.session_seed(st2))

# Painted bell sequence: the exact value wsnet hands native. Native rings
# iff it differs from its adopted last, so focus-only paints must repeat
# the value and each inbound alert must advance it exactly once.
def bl_painted(+ws: W.Workspace, +bell: U32) -> U32:
  Cl.client_bell_seq(Sess.session_cl(W.paint_session(ws, bell)))

# Event-ID readers: every stamped line ID in a client, for cross-Sid
# uniqueness (disjoint ranges), old-ID stability, and stale checks.
def id_line(+l: Cl.Line) -> Nat:
  match l:
    case Cl.Line{_, _, _, _, +id}: id

def id_lines.go(+xs: List<&2, Cl.Line>, +acc: List<&2, Nat>) -> List<&2, Nat>:
  match xs:
    case Nil{}: acc
    case Con{+h, +t}: id_lines.go(t, id_line(h) <> acc)

def id_buf.all(+b: Cl.Buffer, +acc: List<&2, Nat>) -> List<&2, Nat>:
  match b:
    case Cl.Buffer{_, _, _, +lines, _, _, _, _}: id_lines.go(lines, acc)

def id_all.go(+xs: List<&2, Cl.Buffer>, +acc: List<&2, Nat>) -> List<&2, Nat>:
  match xs:
    case Nil{}: acc
    case Con{+h, +t}: id_all.go(t, id_buf.all(h, acc))

def id_all(+cl: Cl.Client) -> List<&2, Nat>:
  id_all.go(Cl.client_bufs(cl), Nil{})

def id_shows.go(+xs: List<&2, Nat>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+h, +t}: id_shows.go(t, acc ++ Nat.show(h) ++ ";")

def id_shows(+xs: List<&2, Nat>) -> String:
  id_shows.go(xs, "")

def id_mem(+xs: List<&2, Nat>, +n: Nat) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, +t}: Nat.is_eq(h, n) || id_mem(t, n)

def id_disjoint(+a: List<&2, Nat>, +b: List<&2, Nat>) -> Bool:
  match a:
    case Nil{}: True{}
    case Con{+h, +t}: Bool.not(id_mem(b, h)) && id_disjoint(t, b)

def id_all_ge(+xs: List<&2, Nat>, +lo: Nat) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, +t}: Bool.not(Nat.is_lt(h, lo)) && id_all_ge(t, lo)

def id_all_lt(+xs: List<&2, Nat>, +hi: Nat) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, +t}: Nat.is_lt(h, hi) && id_all_lt(t, hi)

def id_seq(+ws: W.Workspace, +id: Key.ServerId) -> String:
  Nat.show(Cl.log_seq_of(ws_cl_of(ws, id)))

# G1 rejected-line probes: buffer existence, unread level, bell delta.
def g1_has_buf.got(+got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def g1_has_buf(+ws: W.Workspace, +id: Key.ServerId, +name: String) -> Bool:
  g1_has_buf.got(Cl.buf_find(ws_cl_of(ws, id), name))

def g1_unread(+ws: W.Workspace, +id: Key.ServerId, +name: String) -> U32:
  Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(ws_cl_of(ws, id))), name)

def g1_texts_at.got(+ws: W.Workspace, +id: Key.ServerId, +got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "[absent]"
    case Some{+i}: ws_texts(ws, id, i)

def g1_texts_named(+ws: W.Workspace, +id: Key.ServerId, +name: String) -> String:
  g1_texts_at.got(ws, id, Cl.buf_find(ws_cl_of(ws, id), name))

# MSS NICK rejected/fitting probes: split pane identity under ceiling admission.
def ws_panes(+st: Sp.State) -> String:
  match st:
    case Sp.Off{}: "off"
    case Sp.On{_, +first, +second, +focus}: first ++ "|" ++ second ++ "@" ++ U32.show(focus)

def ws_panes_of(+ws: W.Workspace, +id: Key.ServerId) -> String:
  ws_panes(Sess.session_split(ws_part_st(ws, id)))

def s2() -> Key.ServerId:
  Key.ServerId{2n}

def tk_count(+ws: W.Workspace, +id: Key.ServerId) -> Nat:
  Ty.count(Sess.session_typing(ws_part_st(ws, id)))

# Launch-profile workspaces: the primary part carries the exact-endpoint
# credentialed client (live_client parity); extras stay bare.
def au_client(+mode: Cl.AuthMode) -> Cl.Client:
  +bare = Cl.client_set_auth(Cl.init("me", "a.example"), mode, "a.example", 6697, "NickServ!service@services.example", "You are now identified as account.", "account", "secret")
  Cl.set_settings(bare, Cl.set_autoreconn(Cl.get_settings(bare), True{}))

def au_ws() -> W.Workspace:
  W.single_client("a.example", 6697, False{}, au_client(Cl.SaslOnly{}), "#a")

def au_ns_ws() -> W.Workspace:
  W.single_client("a.example", 6697, False{}, au_client(Cl.NickServOnly{}), "#a")

def au_seq(+ws: W.Workspace, +id: Key.ServerId) -> String:
  Nat.show(Cl.auth_success_seq(ws_cl_of(ws, id)))

def au_pass(+ws: W.Workspace, +id: Key.ServerId) -> String:
  Cl.client_sasl_pass(ws_cl_of(ws, id))

# Residual R1: native ring model for the shared bell. The FFI keeps one
# adopted last_bell_seq; it arms bell_pending iff already seen && painted
# enabled && painted seq differs, then adopts the painted seq either way
# (src/ffi/timui_ffi.c, birc_bell_update). A paint that adopts a fresh seq
# while disabled is unrecoverable: later focus paints repeat the same seq,
# so the ring is lost, not deferred.
def bo_rings(seen: Bool, +on: Bool, +last: U32, +painted: U32) -> Bool:
  seen && on && Bool.not(U32.is_eq(painted, last))

def bo_on(+ws: W.Workspace, +id: Key.ServerId) -> Bool:
  Cl.settings_bell(Cl.get_settings(ws_cl_of(ws, id)))

def bo_painted_on(+ws: W.Workspace, +bell: U32) -> Bool:
  Cl.settings_bell(Cl.get_settings(Sess.session_cl(W.paint_session(ws, bell))))

# Residual R2: first stamped ID, duplicate-ID scan, dead scope fallback.
def id_first(+xs: List<&2, Nat>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{+h, _}: h

def id_nubbed.go(+xs: List<&2, Nat>, +seen: List<&2, Nat>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, +t}: Bool.not(id_mem(seen, h)) && id_nubbed.go(t, h <> seen)

def id_nubbed(+xs: List<&2, Nat>) -> Bool:
  id_nubbed.go(xs, Nil{})

def scope_or_dead(+got: Maybe<&2, Sid.Scope>) -> Sid.Scope:
  match got:
    case None{}: Sid.Scope{"dead.invalid", 0, False{}}
    case Some{+s}: s

# Residual R4: edge counting and custom-service privacy fixtures. The custom
# target pins negotiation: a fixed NickServ-only classifier would miss a
# configured AuthServ service.
def b2n(+b: Bool) -> Nat:
  match b:
    case True{}: 1n
    case False{}: 0n

def svc_cl() -> Cl.Client:
  Cl.client_set_auth(Cl.init("me", "irc.example"), Cl.SaslOnly{}, "irc.example", 6697, "AuthServ!x@y", "You are now identified.", "account", "secret")

def svc_rooms() -> Cl.Client:
  ad_submitted(ad_submitted(svc_cl(), "/join #a"), "/join #b")

def prod_svc_outs(+line: String) -> String:
  prod_outs(Sess.step_keys(Sess.session_demo(svc_rooms(), "#a"), Sess.keys_enter(line)))

def prod_svc_hist(+line: String) -> String:
  prod_hist(Sess.step_keys(Sess.session_demo(svc_rooms(), "#a"), Sess.keys_enter(line)))

def prod_svc_recall(+line: String) -> String:
  prod_draft(Sess.step_keys(prod_st.trip(Sess.step_keys(Sess.session_demo(svc_rooms(), "#a"), Sess.keys_enter(line))), hist_keys()))

def prod_svc2_outs(+first: String, +line: String) -> String:
  prod_outs(Sess.step_keys(prod_st.trip(Sess.step_keys(Sess.session_demo(svc_rooms(), "#a"), Sess.keys_enter(first))), Sess.keys_enter(line)))

def prod_svc2_texts(+first: String, +line: String, +i: Nat) -> String:
  prod_texts(Sess.step_keys(prod_st.trip(Sess.step_keys(Sess.session_demo(svc_rooms(), "#a"), Sess.keys_enter(first))), Sess.keys_enter(line)), i)

def prod_svc2_hist(+first: String, +line: String) -> String:
  prod_hist(Sess.step_keys(prod_st.trip(Sess.step_keys(Sess.session_demo(svc_rooms(), "#a"), Sess.keys_enter(first))), Sess.keys_enter(line)))

# ---- workspace parity gates (Q5/H5/G6/Search) -------------------------------
# Gate4 Q5: the carried PONG request ID survives the workspace dispatcher.
def q5_req() -> U32:
  Out.pong_first(0)

def q5_stamps() -> List<&2, Maybe<&2, String>>:
  None{} <> Nil{}

def q5_ws() -> W.Workspace:
  ws_rooms()

def q5_octets() -> List<&2, U32>:
  F.string_to_octets(":alice!x@y PRIVMSG #a :hi\r\n")

def q5_chunk0() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{q5_octets(), 0}}}

def q5_chunk_req() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{q5_octets(), q5_req()}}}

def q5_chunk_stale() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{7, Sess.Chunk{q5_octets(), q5_req()}}}

def q5_eof() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Eof{}}}

def q5_out0() -> W.LiveMsgOut:
  W.live_on_msg(q5_ws(), q5_chunk0(), q5_stamps(), 0, "00:00:03")

def q5_out_req() -> W.LiveMsgOut:
  W.live_on_msg(q5_ws(), q5_chunk_req(), q5_stamps(), 0, "00:00:03")

def q5_out_stale() -> W.LiveMsgOut:
  W.live_on_msg(q5_ws(), q5_chunk_stale(), q5_stamps(), 0, "00:00:03")

# Shared part-session installer for armed fixtures.
def srch_install.got(+ws: W.Workspace, +got: Maybe<&2, W.Part>, +st2: Sess.Session) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, _}: W.replace_part(ws, W.Part{id, gen, scope, st2})

def srch_install(+ws: W.Workspace, +id: Key.ServerId, +st2: Sess.Session) -> W.Workspace:
  srch_install.got(ws, W.find_part(ws, id), st2)

# Gate1 Search: command production plus async completion through the owner.
def srch_cmd_text.cmd(cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Search{+text, _, _, _, _, _, _, _, _}: text
    case _: "other"

def srch_cmd_text(+rc: Sid.RoutedCmd) -> String:
  match rc:
    case Sid.RoutedCmd{_, +cmd}: srch_cmd_text.cmd(cmd)

def srch_ws() -> W.Workspace:
  ws_rooms()

def srch_routed() -> Sid.RoutedCmd:
  W.step_routed(srch_ws(), Sess.keys_enter("/history search needle"))

def srch_base_st() -> Sess.Session:
  ws_part_st(srch_ws(), s0())

def srch_noted() -> Sess.Session:
  Sess.history_note_endpoint(srch_base_st(), 3n, "a.example:6697")

def srch_begun() -> Sess.Session & Nat:
  Sess.history_search_begin(srch_noted())

def srch_begun_st(pair: Sess.Session & Nat) -> Sess.Session:
  match pair:
    case (+st, _): st

def srch_begun_ticket(pair: Sess.Session & Nat) -> Nat:
  match pair:
    case (_, +ticket): ticket

def srch_ws_armed() -> W.Workspace:
  srch_install(srch_ws(), s0(), srch_begun_st(srch_begun()))

def srch_ticket() -> Nat:
  srch_begun_ticket(srch_begun())

def srch_page() -> Hs.DiskResult:
  Hs.DiskFound{Hs.empty_page()}

def srch_wgen() -> U32:
  W.part_gen_of(srch_ws_armed(), s0())

def srch_done_ok() -> W.Workspace & Bool:
  W.on_search_done(srch_ws_armed(), s0(), srch_ticket(), 3n, srch_wgen(), "a.example:6697", "needle", srch_page())

def srch_done_stale() -> W.Workspace & Bool:
  W.on_search_done(srch_ws_armed(), s0(), Nat.add(srch_ticket(), 1n), 3n, srch_wgen(), "a.example:6697", "needle", srch_page())

# Gate B incarnation fence: search, remove/readd the SAME endpoint, search
# again. Both first searches stamp ticket1/hgen0/endpoint, so Session stamps
# alone cannot fence the delayed old completion; only the carried part
# incarnation (0 old, 1 new) separates them.
def sr2_sig.cmd(cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Search{_, _, _, +orig, +endpoint, _, +ticket, +gen, +wgen}:
      Nat.show(ticket) ++ "|" ++ Nat.show(gen) ++ "|" ++ U32.show(wgen) ++ "|" ++ endpoint ++ "|" ++ orig
    case _: "other"

def sr2_sig(+rc: Sid.RoutedCmd) -> String:
  match rc:
    case Sid.RoutedCmd{_, +cmd}: sr2_sig.cmd(cmd)

def sr2_base() -> W.Workspace:
  W.do_switch(ws_pair(), s1())

def sr2_old_rc() -> Sid.RoutedCmd:
  W.step_routed(sr2_base(), Sess.keys_enter("/history search needle"))

def sr2_old_ws() -> W.Workspace:
  W.do_enter(sr2_base(), "/history search needle")

def sr2_re() -> W.Workspace:
  W.do_add(W.do_remove(sr2_old_ws(), s1()), "b.example", 6697, False{}, "me", "#b")

def sr2_new_base() -> W.Workspace:
  W.do_switch(sr2_re(), s1())

def sr2_new_rc() -> Sid.RoutedCmd:
  W.step_routed(sr2_new_base(), Sess.keys_enter("/history search needle"))

def sr2_new_ws() -> W.Workspace:
  W.do_enter(sr2_new_base(), "/history search needle")

def sr2_used(+ws: W.Workspace) -> Nat:
  Hs.hist_live_used(Sess.session_hist_live(ws_part_st(ws, s1())))

def sr2_want(+ws: W.Workspace) -> Nat:
  Hs.hist_stamp_ticket(Hs.hist_live_want(Sess.session_hist_live(ws_part_st(ws, s1()))))

def sr2_archived(+ws: W.Workspace) -> List<&2, Nat>:
  Hs.hist_live_archived(Sess.session_hist_live(ws_part_st(ws, s1())))

def sr2_old_done() -> W.Workspace & Bool:
  W.on_search_done(sr2_new_ws(), s1(), 1n, 0n, 0, "b.example:6697", "needle", srch_page())

def sr2_new_done() -> W.Workspace & Bool:
  W.on_search_done(sr2_new_ws(), s1(), 1n, 0n, 1, "b.example:6697", "needle", srch_page())

def sr2_replay() -> W.Workspace & Bool:
  W.on_search_done(W.search_ws(sr2_new_done()), s1(), 1n, 0n, 1, "b.example:6697", "needle", srch_page())

# Gate2 H5: armed import plus unarmed/stale quiet through live_on_msg.
def h5_stamps1() -> List<&2, Maybe<&2, String>>:
  None{} <> Nil{}

def h5_stamps3() -> List<&2, Maybe<&2, String>>:
  None{} <> None{} <> None{} <> Nil{}

def h5_stamps4() -> List<&2, Maybe<&2, String>>:
  None{} <> None{} <> None{} <> None{} <> Nil{}

def h5_ws() -> W.Workspace:
  ws_rooms()

def h5_base_st() -> Sess.Session:
  ws_part_st(h5_ws(), s0())

def h5_noted() -> Sess.Session:
  Sess.history_note_endpoint(h5_base_st(), 3n, "a.example:6697")

def h5_begun() -> Sess.Session & Nat:
  Sess.history_fetch_begin(h5_noted(), "#a")

def h5_begun_st(pair: Sess.Session & Nat) -> Sess.Session:
  match pair:
    case (+st, _): st

def h5_ws_armed() -> W.Workspace:
  srch_install(h5_ws(), s0(), h5_begun_st(h5_begun()))

def h5_batch() -> String:
  ":irc.test BATCH +abc chathistory #a\r\n"
  ++ "@batch=abc;msgid=m1 :alice!u@h PRIVMSG #a :archive one\r\n"
  ++ ":irc.test BATCH -abc\r\n"

def h5_octets() -> List<&2, U32>:
  F.string_to_octets(h5_batch())

def h5_chunk() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{h5_octets(), 0}}}

def h5_chunk_stale() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{7, Sess.Chunk{h5_octets(), 0}}}

def h5_out_armed() -> W.LiveMsgOut:
  W.live_on_msg(h5_ws_armed(), h5_chunk(), h5_stamps3(), 0, "00:00:03")

def h5_out_unarmed() -> W.LiveMsgOut:
  W.live_on_msg(h5_ws(), h5_chunk(), h5_stamps3(), 0, "00:00:03")

def h5_out_stale() -> W.LiveMsgOut:
  W.live_on_msg(h5_ws_armed(), h5_chunk_stale(), h5_stamps3(), 0, "00:00:03")

def h5n_pm_alice() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":alice!u@h PRIVMSG me :hello\r\n"), 0}}}

def h5n_pm_mallory() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":mallory!u@h PRIVMSG me :hi\r\n"), 0}}}

def h5n_ws1() -> W.Workspace:
  W.live_ws(W.live_on_msg(h5_ws(), h5n_pm_alice(), h5_stamps1(), 0, "00:00:03"))

def h5n_ws2() -> W.Workspace:
  W.live_ws(W.live_on_msg(h5n_ws1(), h5n_pm_mallory(), h5_stamps1(), 0, "00:00:04"))

def h5n_batch() -> String:
  ":irc.test BATCH +abc chathistory #a\r\n"
  ++ "@batch=abc;msgid=m9 :alice!u@h NICK alicia\r\n"
  ++ ":irc.test BATCH -abc\r\n"
  ++ ":mallory!u@h NICK mel\r\n"

def h5n_octets() -> List<&2, U32>:
  F.string_to_octets(h5n_batch())

def h5n_chunk() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{h5n_octets(), 0}}}

def h5n_out() -> W.LiveMsgOut:
  W.live_on_msg(h5n_ws2(), h5n_chunk(), h5_stamps4(), 0, "00:00:05")

def h5n_w() -> W.Workspace:
  W.live_ws(h5n_out())

# Gate A drain ceiling: the live fold bounds live rows, but the armed
# archive drain mints through the same bound. Full (ceiling-1) and
# one-slot-left (ceiling-2) drains that would overflow refuse atomically
# with live state and wire outs kept; fitting drains import once.
def h5c_ceil() -> Nat:
  W.id_ceiling(s0())

def h5c_armed_at(+seq: Nat) -> W.Workspace:
  W.replace_part(h5_ws_armed(), W.Part{s0(), W.part_gen_of(h5_ws_armed(), s0()),
    scope_or_dead(W.scope_of(h5_ws_armed(), s0())),
    Sess.session_set_client(ws_part_st(h5_ws_armed(), s0()), Cl.set_log_seq(ws_cl_of(h5_ws_armed(), s0()), seq))})

def h5c_full_ws() -> W.Workspace:
  h5c_armed_at(Nat.sub(h5c_ceil(), 1n))

def h5c_one_ws() -> W.Workspace:
  h5c_armed_at(Nat.sub(h5c_ceil(), 2n))

def h5c_archived(+ws: W.Workspace) -> List<&2, Nat>:
  Hs.hist_live_archived(Sess.session_hist_live(ws_part_st(ws, s0())))

def h5c_ping_chunk() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets("PING :x\r\n" ++ h5_batch()), 0}}}

def h5c_full_out() -> W.LiveMsgOut:
  W.live_on_msg(h5c_full_ws(), h5c_ping_chunk(), h5_stamps4(), 0, "00:00:06")

def h5c_ping_only() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets("PING :x\r\n"), 0}}}

def h5c_full_live_only() -> W.LiveMsgOut:
  W.live_on_msg(h5c_full_ws(), h5c_ping_only(), h5_stamps1(), 0, "00:00:06")

def h5c_batch2() -> String:
  ":irc.test BATCH +abc chathistory #a\r\n"
  ++ "@batch=abc;msgid=m1 :alice!u@h PRIVMSG #a :archive one\r\n"
  ++ "@batch=abc;msgid=m2 :bob!u@h PRIVMSG #a :archive two\r\n"
  ++ ":irc.test BATCH -abc\r\n"

def h5c_chunk2() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(h5c_batch2()), 0}}}

def h5c_two_out() -> W.LiveMsgOut:
  W.live_on_msg(h5c_one_ws(), h5c_chunk2(), h5_stamps4(), 0, "00:00:06")

def h5c_one_out() -> W.LiveMsgOut:
  W.live_on_msg(h5c_one_ws(), h5_chunk(), h5_stamps3(), 0, "00:00:06")

def h5c_one_replay() -> W.LiveMsgOut:
  W.live_on_msg(W.live_ws(h5c_one_out()), h5_chunk(), h5_stamps3(), 0, "00:00:07")

def h5c_roomy_replay() -> W.LiveMsgOut:
  W.live_on_msg(W.live_ws(h5_out_armed()), h5_chunk(), h5_stamps3(), 0, "00:00:07")

def h5c_roomy_pre() -> Nat:
  Cl.log_seq_of(ws_cl_of(h5_ws_armed(), s0()))

# Gate3 G6: frame/tick typing through the shared owner.
def tick_first_outs(+outs: List<&2, W.ServerOuts>) -> String:
  match outs:
    case Nil{}: ""
    case Con{W.ServerOuts{_, +o}, _}: String.join(o, "|")

def frame_outs.cmd(cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Cont{+outs}: String.join(outs, "|")
    case _: "other"

def frame_outs(+rc: Sid.RoutedCmd) -> String:
  match rc:
    case Sid.RoutedCmd{_, +cmd}: frame_outs.cmd(cmd)

def frame_trip_outs(trip: W.Workspace & Sid.RoutedCmd & Bool) -> String:
  match trip:
    case (_, +rc, _): frame_outs(rc)

def frame_trip_halt(trip: W.Workspace & Sid.RoutedCmd & Bool) -> Bool:
  match trip:
    case (_, _, halt): halt

def typ_cap_chunk() -> Sid.RoutedMsg:
  Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":s CAP me ACK :message-tags\r\n"), 0}}}

def typ_ws_tagged() -> W.Workspace:
  W.do_switch(W.live_ws(W.live_on_msg(ws_rooms(), typ_cap_chunk(), h5_stamps1(), 0, "00:00:01")), s0())

def typ_frame() -> W.Workspace & Sid.RoutedCmd & Bool:
  W.live_step_keys_typing(typ_ws_tagged(), AD.typing_keys("hi"), 1000)

def typ_frame_ws.go(trip: W.Workspace & Sid.RoutedCmd & Bool) -> W.Workspace:
  match trip:
    case (+ws2, _, _): ws2

def typ_frame_ws() -> W.Workspace:
  typ_frame_ws.go(typ_frame())

def typ_halt() -> W.Workspace & Sid.RoutedCmd & Bool:
  W.live_step_keys_typing(typ_frame_ws(), Sess.keys_enter("/quit"), 1100)

def typ_tick() -> W.TickOut:
  W.tick_typing(typ_frame_ws(), 1100)

def typ_off_st() -> Sess.Session:
  Sess.session_fail(ws_part_st(typ_frame_ws(), s0()), "lost")

def typ_off_ws() -> W.Workspace:
  srch_install(typ_frame_ws(), s0(), typ_off_st())

def typ_off_tick() -> W.TickOut:
  W.tick_typing(typ_off_ws(), 2000)

def typ_cm_iso() -> Iso.State:
  Iso.apply_line(Iso.defaults(), ":s 005 me CASEMAPPING=ascii :are supported")

def typ_cm_client() -> Cl.Client:
  Cl.Client{"me", "s", Cl.server_buf() <> Cl.empty_buf("a[b", False{}) <> Cl.empty_buf("a{b", False{}) <> Nil{}, 1n, "", Cl.settings0(), Cl.AuthIdle{}, 0n, False{}}

def typ_cm_tagged() -> Sess.Session:
  Sess.st_of_chunk(Sess.step_on_chunk_ms(Sess.session_online(Sess.session_with_client(typ_cm_client(), "#a")), F.string_to_octets(":s CAP me ACK :message-tags\r\n"), 0))

def typ_cm_keyed(+st: Sess.Session, +text: String) -> Sess.Session:
  Sess.st_of_keys(Sess.step_keys(st, Sess.keys_of(text, False{}, 0, 0, 0, 0, 0, 0, 0)))

def typ_cm_focus(+st: Sess.Session, +i: Nat) -> Sess.Session:
  Sess.session_set_client(st, Cl.set_active(Sess.session_cl(st), i))

def typ_cm_base() -> Sess.Session:
  typ_cm_focus(Sess.session_set_iso(typ_cm_tagged(), typ_cm_iso()), 1n)

def typ_cm_k1() -> Sess.Session:
  typ_cm_keyed(typ_cm_base(), "hi")

def typ_cm_ws_k1() -> W.Workspace:
  srch_install(ws_rooms(), s0(), typ_cm_k1())

def typ_cm_tick1() -> W.TickOut:
  W.tick_typing(typ_cm_ws_k1(), 1000)

def typ_cm_ws_t1() -> W.Workspace:
  W.tick_ws(typ_cm_tick1())

def typ_cm_moved_st() -> Sess.Session:
  typ_cm_focus(ws_part_st(typ_cm_ws_t1(), s0()), 2n)

def typ_cm_ws_moved() -> W.Workspace:
  srch_install(typ_cm_ws_t1(), s0(), typ_cm_moved_st())

def typ_cm_tick2() -> W.TickOut:
  W.tick_typing(typ_cm_ws_moved(), 1100)

def typ_cm_ws_t2() -> W.Workspace:
  W.tick_ws(typ_cm_tick2())

def typ_cm_tick3() -> W.TickOut:
  W.tick_typing(typ_cm_ws_t2(), 1200)

def main() -> IO(Unit):
  +s1a_base = ws_pair()
  +s1a_removed = W.do_remove(s1a_base, s1())
  +s1a_readded = W.do_add(s1a_removed, "b.example", 6697, False{}, "me", "#b")
  +s1a_newgen = W.part_gen_of(s1a_readded, s1())
  +s1a_old_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{Nil{}, 0}}}
  +s1a_old_done : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.WriterDone{}}}
  +s1a_old_intent : Sid.Intent = Sid.Intent{s1(), 0, "b.example", 6697, False{}}
  +s1a_fresh_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{s1a_newgen, Sess.Chunk{Nil{}, 0}}}
  +s1a_sib_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{Nil{}, 0}}}
  +s1b_on = ws_online(ws_pair(), s1())
  +s1b_dialed = W.do_enter(W.do_switch(s1b_on, s1()), "/connect c.example 6697")
  +s1b_removed = W.do_remove(s1b_dialed, s1())
  +s1b_readded = W.do_add(s1b_removed, "c.example", 6697, False{}, "me", "#c")
  +s1b_redialed = W.do_enter(W.do_switch(s1b_readded, s1()), "/connect c.example 6697")
  +s1b_newgen = W.part_gen_of(s1b_redialed, s1())
  +s1b_old_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{1, Sess.Chunk{Nil{}, 0}}}
  +s1b_old_done : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{1, Sess.WriterDone{}}}
  +s1b_old_intent : Sid.Intent = Sid.Intent{s1(), 1, "c.example", 6697, False{}}
  +s1b_fresh_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{s1b_newgen, Sess.Chunk{Nil{}, 0}}}
  +s1b_sib_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{Nil{}, 0}}}
  +s2_conn = AD.do_enter(ad_with_net(Sess.Connecting{}), "aa\nbb")
  +s2_recon = AD.do_enter(ad_with_net(Sess.Reconnecting{}), "aa\nbb")
  +s2_off = AD.do_enter(ad_with_net(Sess.Offline{}), "aa\nbb")
  +s2_stop = AD.do_enter(ad_with_net(Sess.Stopping{True{}}), "aa\nbb")
  +s2_on = AD.do_enter(ad_online(), "aa\nbb")
  +s2_demo = AD.do_enter(ad_demo(), "aa\nbb")
  +s3_base = ws_rooms()
  +s3_s0 = W.do_switch(s3_base, s0())
  +s3_typed = W.do_step(s3_s0, AD.typing_keys("aa"))
  +s3_both = W.do_step(W.do_switch(s3_typed, s1()), AD.typing_keys("bb"))
  +s3_moved = W.do_replace(s3_both, s0(), "c.example", 6697, False{})
  +s3_same = W.do_replace(s3_both, s0(), "a.example", 6697, False{})
  +s3_port = W.do_replace(s3_both, s0(), "a.example", 6698, False{})
  +s3_back = W.do_switch(s3_moved, s0())
  +s4_full = ad_full()
  +s4_rej = AD.do_enter(s4_full, "/query bob hello")
  +s4_seeded = AD.with_drafts(AD.ad_session(ad_demo()), D.set(AD.ad_drafts(ad_demo()), s0(), "bob", "prior"), s0())
  +s4_admit = AD.do_enter(s4_seeded, "/query bob")
  +s5_q = AD.do_enter(ad_demo(), "/query NickServ")
  +s5_mixed = AD.do_enter(s5_q, "hello\nIDENTIFY hunter2")
  +s5_login = AD.do_enter(s5_q, "hi\nLOGIN acc sekrit")
  +s5_plain = AD.do_enter(ad_demo(), "aa\nbb")
  +g2_blank = AD.do_enter(ad_demo(), "aa\n\nbb")
  +g2_crlf = AD.do_enter(ad_demo(), "aa\r\nbb")
  +g3_bare = AD.do_enter(ad_full(), "/query alice")
  +g3_bare_cmd = AD.step_cmd(ad_full(), Sess.keys_enter("/query alice"))
  +g3_admit_bare = AD.do_enter(ad_demo(), "/query carol")
  +g3_admit_bare_cmd = AD.step_cmd(ad_demo(), Sess.keys_enter("/query carol"))
  +g5_pair = ws_pair()
  +g5_up0msg : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}
  +g5_up0 = W.on_routed_up(g5_pair, g5_up0msg, "00:00:01")
  +g5_up1msg : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Up{}}}
  +g5_up1 = W.on_routed_up(W.do_switch(g5_up0, s1()), g5_up1msg, "00:00:02")
  +g5_set0 = W.do_enter(W.do_switch(g5_up1, s0()), "/set autoreconn on")
  +g5_j0 = W.do_enter(g5_set0, "/join #a")
  +g5_j1 = W.do_enter(W.do_switch(g5_j0, s1()), "/join #b")
  +g5_s1hi = W.do_enter(g5_j1, "s1hi")
  +g5_chunk0 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":alice!x@y PRIVMSG #a :hi\r\n"), 0}}}
  +g5_stamps : List<&2, Maybe<&2, String>> = None{} <> Nil{}
  +g5_in0 = W.do_on_chunk(g5_s1hi, g5_chunk0, g5_stamps, 0)
  +g5_in0outs = W.on_chunk_outs(g5_s1hi, g5_chunk0, g5_stamps, 0)
  +g5_stale_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{7, Sess.Chunk{F.string_to_octets(":mallory!x@y PRIVMSG #a :yo\r\n"), 0}}}
  +g5_stale = W.do_on_chunk(g5_in0, g5_stale_chunk, g5_stamps, 0)
  +g5_stale_outs = W.on_chunk_outs(g5_in0, g5_stale_chunk, g5_stamps, 0)
  +g5_unk_chunk : Sid.RoutedMsg = Sid.RoutedMsg{bad4(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":mallory!x@y PRIVMSG #a :yo\r\n"), 0}}}
  +g5_unk = W.do_on_chunk(g5_in0, g5_unk_chunk, g5_stamps, 0)
  +g5_dialrc = W.step_routed(W.do_switch(g5_in0, s0()), Sess.keys_enter("/connect d.example 6697"))
  +g5_dialed = W.do_step(W.do_switch(g5_in0, s0()), Sess.keys_enter("/connect d.example 6697"))
  +g5_up_stale = W.on_routed_up(g5_dialed, g5_up0msg, "00:00:03")
  +g5_up1msg : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Up{}}}
  +g5_up_fresh = W.on_routed_up(g5_dialed, g5_up1msg, "00:00:04")
  +g5_eof : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Eof{}}}
  +g5_fail = W.do_on_fail(g5_up_fresh, g5_eof, "00:00:05")
  +g5_fail_cmd = W.on_fail_cmd(g5_up_fresh, g5_eof, "00:00:05")
  +g5_fail_int = W.on_fail_intent(g5_up_fresh, g5_eof, "00:00:05")
  +g5_eof_stale : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Eof{}}}
  +g5_fail_stale = W.do_on_fail(g5_up_fresh, g5_eof_stale, "00:00:05")
  +g5_fail_stale_cmd = W.on_fail_cmd(g5_up_fresh, g5_eof_stale, "00:00:05")
  +g5_red = W.do_redial(g5_fail, s0(), intent_or_dead(g5_fail_int))
  +g5_red_cmd = W.redial_cmd(g5_fail, s0(), intent_or_dead(g5_fail_int))
  +g5_red_stale = W.redial_cmd(g5_fail, s0(), Sid.Intent{s0(), 0, "d.example", 6697, False{}})
  +g5_red_evil = W.redial_cmd(g5_red, s0(), Sid.Intent{s0(), 2, "evil.example", 6697, False{}})
  +g5_fail_off = W.do_enter(g5_fail, "/set autoreconn off")
  +g5_red_off = W.do_redial(g5_fail_off, s0(), intent_or_dead(g5_fail_int))
  +g5_red_off_cmd = W.redial_cmd(g5_fail_off, s0(), intent_or_dead(g5_fail_int))
  +g5_conn_after = W.step_routed(g5_red_off, Sess.keys_enter("/connect d.example 6697"))
  +g5_red_stale_ws = W.do_redial(g5_fail, s0(), Sid.Intent{s0(), 0, "d.example", 6697, False{}})
  +g5_red_stale_off = W.do_redial(g5_fail_off, s0(), Sid.Intent{s0(), 0, "d.example", 6697, False{}})
  +s2p_over_text = "ok\n" ++ "e" ++ s2p_repeat(260n, SCon{Chr{769}, ""})
  +lm_chunk = W.live_on_msg(g5_s1hi, g5_chunk0, g5_stamps, 0, "00:00:03")
  +lm_stale = W.live_on_msg(g5_in0, g5_stale_chunk, g5_stamps, 0, "00:00:03")
  +lm_up = W.live_on_msg(g5_dialed, g5_up1msg, g5_stamps, 0, "00:00:04")
  +lm_fail = W.live_on_msg(g5_up_fresh, g5_eof, g5_stamps, 0, "00:00:05")
  +lm_fail_stale = W.live_on_msg(g5_up_fresh, g5_eof_stale, g5_stamps, 0, "00:00:05")
  +lm_init : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.InitialFail{"connect failed"}}}
  +lm_init_out = W.live_on_msg(g5_dialed, lm_init, g5_stamps, 0, "00:00:03")
  +lm_init_stale : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.InitialFail{"connect failed"}}}
  +lm_init_stale_out = W.live_on_msg(g5_dialed, lm_init_stale, g5_stamps, 0, "00:00:03")
  +lm_key : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.UiKey{}}
  +lm_key_out = W.live_on_msg(g5_in0, lm_key, g5_stamps, 0, "00:00:03")
  +lm_done : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.WriterDone{}}}
  +lm_done_out = W.live_on_msg(g5_in0, lm_done, g5_stamps, 0, "00:00:03")
  +ls_base = W.do_switch(g5_up1, s0())
  +ls_switched = W.live_do_step(ls_base, Sess.keys_enter("/server 2"))
  +ls_absent = W.live_do_step(ls_base, Sess.keys_enter("/server 3"))
  +ls_bad = W.live_do_step(ls_base, Sess.keys_enter("/server 9"))
  +ls_bare = W.live_do_step(ls_base, Sess.keys_enter("/server"))
  +ls_chat = W.live_do_step(ls_base, Sess.keys_enter("/join #a"))
  +cy_base = W.do_step(g5_s1hi, AD.typing_keys("S1D"))
  +cy_single_base = W.single("a.example", 6697, False{}, "me", "#a")
  +sz_base = ws_rooms()
  +sz_set = W.set_current_size(sz_base, 30, 100)
  +med_off = W.set_media_supported(sz_base, False{})
  +med_on = W.set_media_supported(sz_base, True{})
  +g4_st = Sess.session_demo(ad_rooms(), "#a")
  +g4_keys = Sess.keys_enter("aa\nbb")
  +g4_cl = Sess.session_cl(g4_st)
  +g4_bi = Cl.active_of(g4_cl)
  +g4_hist2 = Sess.hist_after_enter(Sess.session_hist(g4_st), "aa\nbb", True{})
  g4_quad = t_quad.pair(D.submit_lines(g4_cl, g4_bi, Sp.name_at(g4_cl, g4_bi), "aa\nbb", False{}), Sess.session_split(g4_st))
  +g4_seam = t_summary.trip(Sess.step_keys.supplied(g4_st, g4_keys, g4_hist2, g4_quad))
  +g4_ad = AD.do_enter(ad_demo(), "aa\nbb")
  +g4_ad_cmd = AD.step_cmd(ad_demo(), Sess.keys_enter("aa\nbb"))
  +g1_base = ws_rooms()
  +g1_s0 = W.do_switch(g1_base, s0())
  +g1_tab0 = W.do_step(g1_s0, comp_keys("old /j"))
  +g1_both = W.do_step(W.do_switch(g1_tab0, s1()), comp_keys("old /j"))
  +g1_moved = W.do_replace(g1_both, s0(), "c.example", 6697, False{})
  +g1_port = W.do_replace(g1_both, s0(), "a.example", 6698, False{})
  +g1_same = W.do_replace(g1_both, s0(), "a.example", 6697, False{})
  +g1_next = W.do_step(W.do_switch(g1_moved, s0()), comp_keys(""))
  +g1_next_port = W.do_step(W.do_switch(g1_port, s0()), comp_keys(""))
  +g1_next_same = W.do_step(W.do_switch(g1_same, s0()), comp_keys(""))
  +g1_next_sib = W.do_step(W.do_switch(g1_moved, s1()), comp_keys(""))
  +bl_base = g5_j1
  +bl_pm0 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":alice!x@y PRIVMSG me :hello\r\n"), 0}}}
  +bl_o1 = W.live_on_msg(bl_base, bl_pm0, g5_stamps, 0, "00:00:06")
  +bl_w1 = W.live_ws(bl_o1)
  +bl_b1 = W.bell_after(W.part_bell(bl_base, s0()), W.part_bell(bl_w1, s0()), 0)
  +bl_sw0 = W.do_switch(bl_w1, s0())
  +bl_pm1 : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":bob!b@y PRIVMSG me :yo\r\n"), 0}}}
  +bl_o2 = W.live_on_msg(bl_sw0, bl_pm1, g5_stamps, 0, "00:00:07")
  +bl_w2 = W.live_ws(bl_o2)
  +bl_b2 = W.bell_after(W.part_bell(bl_sw0, s1()), W.part_bell(bl_w2, s1()), bl_b1)
  +bl_sw1 = W.do_switch(bl_w2, s1())
  +bl_sw0b = W.do_switch(bl_sw1, s0())
  +bl_stale : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{7, Sess.Chunk{F.string_to_octets(":mallory!x@y PRIVMSG me :yo\r\n"), 0}}}
  +bl_oS = W.live_on_msg(bl_sw0b, bl_stale, g5_stamps, 0, "00:00:08")
  +bl_wS = W.live_ws(bl_oS)
  +bl_bS = W.bell_after(W.part_bell(bl_sw0b, s0()), W.part_bell(bl_wS, s0()), bl_b2)
  +bl_plain : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":bob!b@y PRIVMSG #a :hi\r\n"), 0}}}
  +bl_oP = W.live_on_msg(bl_sw0b, bl_plain, g5_stamps, 0, "00:00:09")
  +bl_wP = W.live_ws(bl_oP)
  +bl_bP = W.bell_after(W.part_bell(bl_sw0b, s0()), W.part_bell(bl_wP, s0()), bl_b2)
  +bl_pm0b : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":carol!c@z PRIVMSG me :again\r\n"), 0}}}
  +bl_o3 = W.live_on_msg(bl_wP, bl_pm0b, g5_stamps, 0, "00:00:10")
  +bl_w3 = W.live_ws(bl_o3)
  +bl_b3 = W.bell_after(W.part_bell(bl_wP, s0()), W.part_bell(bl_w3, s0()), bl_bP)
  +au_stamps3 : List<&2, Maybe<&2, String>> = None{} <> None{} <> None{} <> Nil{}
  +au_base = au_ws()
  +au_upm : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}
  +au_up = W.live_ws(W.live_on_msg(au_base, au_upm, g5_stamps, 0, "00:00:01"))
  +au_sasl : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":a.example CAP me ACK :sasl\r\nAUTHENTICATE +\r\n:a.example 903 me :ok\r\n"), 0}}}
  +au_o = W.live_on_msg(au_up, au_sasl, au_stamps3, 0, "00:00:02")
  +au_w = W.live_ws(au_o)
  +au_x = W.do_add(au_base, "b.example", 6697, False{}, "me", "#b")
  +au_xupm : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Up{}}}
  +au_xup = W.live_ws(W.live_on_msg(au_x, au_xupm, g5_stamps, 0, "00:00:01"))
  +au_xsasl : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":b.example CAP me ACK :sasl\r\nAUTHENTICATE +\r\n:b.example 903 me :ok\r\n"), 0}}}
  +au_xo = W.live_on_msg(au_xup, au_xsasl, au_stamps3, 0, "00:00:02")
  +au_p = W.do_add(au_base, "a.example", 6698, False{}, "me", "#b")
  +au_pup = W.live_ws(W.live_on_msg(au_p, au_xupm, g5_stamps, 0, "00:00:01"))
  +au_po = W.live_on_msg(au_pup, au_xsasl, au_stamps3, 0, "00:00:02")
  +au_ns = au_ns_ws()
  +au_nsup = W.live_ws(W.live_on_msg(au_ns, au_upm, g5_stamps, 0, "00:00:01"))
  +au_001 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":a.example 001 me :welcome\r\n"), 0}}}
  +au_nso = W.live_on_msg(au_nsup, au_001, g5_stamps, 0, "00:00:02")
  +au_nx = W.do_add(au_ns, "b.example", 6697, False{}, "me", "#b")
  +au_nxup = W.live_ws(W.live_on_msg(au_nx, au_xupm, g5_stamps, 0, "00:00:01"))
  +au_nx001 : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":b.example 001 me :welcome\r\n"), 0}}}
  +au_nxo = W.live_on_msg(au_nxup, au_nx001, g5_stamps, 0, "00:00:02")
  +au_nxw = W.live_ws(au_nxo)
  +au_nxnotice : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":NickServ!service@services.example NOTICE me :service help\r\n"), 0}}}
  +au_nxno = W.live_on_msg(au_nxw, au_nxnotice, g5_stamps, 0, "00:00:03")
  +au_mv = W.do_replace(au_base, s0(), "other.example", 6697, False{})
  +au_mvp = W.do_replace(au_base, s0(), "a.example", 6698, False{})
  +au_same = W.do_replace(au_base, s0(), "a.example", 6697, False{})
  +au_con = W.do_enter(au_up, "/connect other.example 6697")
  +au_eof : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Eof{}}}
  +au_fail = W.do_on_fail(au_up, au_eof, "00:00:03")
  +au_red = W.do_redial(au_fail, s0(), intent_or_dead(W.on_fail_intent(au_up, au_eof, "00:00:03")))
  +id_pair = ws_pair()
  +id_up0 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Up{}}}
  +id_w0 = W.live_ws(W.live_on_msg(id_pair, id_up0, g5_stamps, 0, "00:00:01"))
  +id_up1 : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Up{}}}
  +id_w1 = W.live_ws(W.live_on_msg(id_w0, id_up1, g5_stamps, 0, "00:00:02"))
  +id_pm0 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":alice!x@y PRIVMSG me :hello\r\n"), 0}}}
  +id_a = W.live_ws(W.live_on_msg(id_w1, id_pm0, g5_stamps, 0, "00:00:03"))
  +id_s0_before = id_shows(id_all(ws_cl_of(id_a, s0())))
  +id_pm1 : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":bob!b@y PRIVMSG me :yo\r\n"), 0}}}
  +id_b = W.live_ws(W.live_on_msg(id_a, id_pm1, g5_stamps, 0, "00:00:04"))
  +id_stale : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{7, Sess.Chunk{F.string_to_octets(":mallory!x@y PRIVMSG me :yo\r\n"), 0}}}
  +id_c = W.live_ws(W.live_on_msg(id_b, id_stale, g5_stamps, 0, "00:00:05"))
  +id_s2 = W.do_add(id_b, "c.example", 6697, False{}, "me", "#c")
  +id_mv = W.do_replace(id_b, s1(), "x.example", 6697, False{})
  +id_re = W.do_add(W.do_remove(id_b, s1()), "b.example", 6697, False{}, "me", "#b")
  +tk_j0 = W.do_enter(id_w1, "/join #a")
  +tk_j1 = W.do_enter(W.do_switch(tk_j0, s1()), "/join #b")
  +tk_tm0 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets("@+typing=active :alice!x@y TAGMSG #a\r\n"), 0}}}
  +tk_a = W.live_ws(W.live_on_msg(tk_j1, tk_tm0, g5_stamps, 1000, "00:00:03"))
  +tk_tm1 : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets("@+typing=active :bob!b@y TAGMSG #b\r\n"), 0}}}
  +tk_b = W.live_ws(W.live_on_msg(tk_a, tk_tm1, g5_stamps, 1000, "00:00:04"))
  +tk_early = W.tick_typing(tk_b, 1000)
  +tk_late = W.tick_typing(tk_b, 8000)
  +bo_rooms = ws_rooms()
  +bo_a0 = W.do_enter(W.do_switch(bo_rooms, s1()), "/set bell off")
  +bo_a = W.do_switch(bo_a0, s0())
  +bo_a_pm : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":bob!b@y PRIVMSG me :yo\r\n"), 0}}}
  +bo_a_o = W.live_on_msg(bo_a, bo_a_pm, g5_stamps, 0, "00:00:07")
  +bo_a_w = W.live_ws(bo_a_o)
  +bo_a_b = W.bell_after_on(W.part_bell(bo_a, s1()), W.part_bell(bo_a_w, s1()), 0, W.part_bell_on(bo_a, s1()))
  +bo_b0 = W.do_enter(W.do_switch(bo_rooms, s0()), "/set bell off")
  +bo_b = bo_b0
  +bo_b_pm : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":bob!b@y PRIVMSG me :yo\r\n"), 0}}}
  +bo_b_o = W.live_on_msg(bo_b, bo_b_pm, g5_stamps, 0, "00:00:07")
  +bo_b_w = W.live_ws(bo_b_o)
  +bo_b_b = W.bell_after_on(W.part_bell(bo_b, s1()), W.part_bell(bo_b_w, s1()), 0, W.part_bell_on(bo_b, s1()))
  +bo_swap_b = W.bell_after_on(W.part_bell(bo_b_w, s1()), W.part_bell(bo_b, s1()), 0, W.part_bell_on(bo_b, s1()))
  +bo_b_f = W.do_switch(bo_b_w, s1())
  +bo_c0 = W.do_enter(W.do_switch(bo_rooms, s0()), "/set bell off")
  +bo_c_pm : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":alice!x@y PRIVMSG me :hi\r\n"), 0}}}
  +bo_c_o = W.live_on_msg(bo_c0, bo_c_pm, g5_stamps, 0, "00:00:07")
  +bo_c_w = W.live_ws(bo_c_o)
  +bo_c_b = W.bell_after_on(W.part_bell(bo_c0, s0()), W.part_bell(bo_c_w, s0()), 0, W.part_bell_on(bo_c0, s0()))
  +bo_c1 = W.do_enter(bo_c_w, "/set bell on")
  +bo_c_o2 = W.live_on_msg(bo_c1, bo_c_pm, g5_stamps, 0, "00:00:08")
  +bo_c_w2 = W.live_ws(bo_c_o2)
  +bo_c_b2 = W.bell_after_on(W.part_bell(bo_c1, s0()), W.part_bell(bo_c_w2, s0()), bo_c_b, W.part_bell_on(bo_c1, s0()))
  +bo_m0 = W.do_enter(W.do_enter(W.do_switch(bo_rooms, s1()), "/query bob"), "/mute bob")
  +bo_m = W.do_switch(bo_m0, s0())
  +bo_m_pm : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":bob!b@y PRIVMSG me :yo\r\n"), 0}}}
  +bo_m_o = W.live_on_msg(bo_m, bo_m_pm, g5_stamps, 0, "00:00:07")
  +bo_m_w = W.live_ws(bo_m_o)
  +bo_m_b = W.bell_after_on(W.part_bell(bo_m, s1()), W.part_bell(bo_m_w, s1()), 0, W.part_bell_on(bo_m, s1()))
  +id2_old_first = id_first(id_all(ws_cl_of(id_b, s1())))
  +id2_re = W.do_add(W.do_remove(id_b, s1()), "b.example", 6697, False{}, "me", "#b")
  +id2_gen = W.part_gen_of(id2_re, s1())
  +id2_up : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{id2_gen, Sess.Up{}}}
  +id2_on = W.live_ws(W.live_on_msg(id2_re, id2_up, g5_stamps, 0, "00:00:05"))
  +id2_pm : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{id2_gen, Sess.Chunk{F.string_to_octets(":carol!c@z PRIVMSG me :fresh\r\n"), 0}}}
  +id2_o = W.live_on_msg(id2_on, id2_pm, g5_stamps, 0, "00:00:06")
  +id2_new = W.live_ws(id2_o)
  +id2_ch = W.do_add(W.do_remove(id_b, s1()), "x.example", 6697, False{}, "me", "#x")
  +id2_chgen = W.part_gen_of(id2_ch, s1())
  +id2_chup : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{id2_chgen, Sess.Up{}}}
  +id2_chon = W.live_ws(W.live_on_msg(id2_ch, id2_chup, g5_stamps, 0, "00:00:05"))
  +id2_chm : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{id2_chgen, Sess.Chunk{F.string_to_octets(":carol!c@z PRIVMSG me :fresh\r\n"), 0}}}
  +id2_cho = W.live_on_msg(id2_chon, id2_chm, g5_stamps, 0, "00:00:06")
  +id2_chw = W.live_ws(id2_cho)
  +id2_stale : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":mallory!x@y PRIVMSG me :yo\r\n"), 0}}}
  +id2_staled = W.live_ws(W.live_on_msg(id2_new, id2_stale, g5_stamps, 0, "00:00:07"))
  +id2_dave : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":dave!d@w PRIVMSG me :one\r\n"), 0}}}
  +id2_q1 = W.live_ws(W.live_on_msg(id_b, id2_dave, g5_stamps, 0, "00:00:06"))
  +id2_erin : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":erin!e@v PRIVMSG me :two\r\n"), 0}}}
  +id2_q2 = W.live_ws(W.live_on_msg(id2_q1, id2_erin, g5_stamps, 0, "00:00:07"))
  +seam1_sup = Cl.client_log(Cl.init("me", "a.example"), 0n, Cl.Msg{}, "kept row")
  +seam1_ws = W.single_client("a.example", 6697, False{}, seam1_sup, "#a")
  +seam2_cap = Nat.sub(Nat.add(W.id_base(s1()), W.id_range()), 1n)
  +seam2_cl = Cl.set_log_seq(ws_cl_of(id_b, s1()), seam2_cap)
  +seam2_st = Sess.session_set_client(ws_part_st(id_b, s1()), seam2_cl)
  +seam2_ws = W.replace_part(id_b, W.Part{s1(), W.part_gen_of(id_b, s1()), scope_or_dead(W.scope_of(id_b, s1())), seam2_st})
  +seam2_pm : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{W.part_gen_of(id_b, s1()), Sess.Chunk{F.string_to_octets(":zed!z@z PRIVMSG me :late\r\n"), 0}}}
  +seam2_o = W.live_on_msg(seam2_ws, seam2_pm, g5_stamps, 0, "00:00:08")
  +seam2_w = W.live_ws(seam2_o)
  +seam3_live = Cl.log_seq_of(ws_cl_of(id_b, s1()))
  +seam3_arch = Hist.parse_history_text("#b\tMSG\t\tarch one\n#b\tMSG\t\tarch two\n")
  +seam3_bound = Hist.apply_history(ws_cl_of(id_b, s1()), seam3_arch, "00:00:09", 100)
  +seam3_after = Cl.log_seq_of(seam3_bound)
  +seam3_st = Sess.session_set_client(ws_part_st(id_b, s1()), seam3_bound)
  +seam3_ws = W.replace_part(id_b, W.Part{s1(), W.part_gen_of(id_b, s1()), scope_or_dead(W.scope_of(id_b, s1())), seam3_st})
  +seam3_pm : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{W.part_gen_of(id_b, s1()), Sess.Chunk{F.string_to_octets(":frank!f@u PRIVMSG me :live after\r\n"), 0}}}
  +seam3_w = W.live_ws(W.live_on_msg(seam3_ws, seam3_pm, g5_stamps, 0, "00:00:10"))
  +aq_up1 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Up{}}}
  +aq_up2 = W.live_ws(W.live_on_msg(au_red, aq_up1, g5_stamps, 0, "00:00:04"))
  +aq_sasl : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Chunk{F.string_to_octets(":a.example CAP me ACK :sasl\r\nAUTHENTICATE +\r\n:a.example 903 me :ok\r\n"), 0}}}
  +aq_o2 = W.live_on_msg(aq_up2, aq_sasl, au_stamps3, 0, "00:00:05")
  +aq_w2 = W.live_ws(aq_o2)
  +aq_dupm : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":a.example 903 me :ok\r\n"), 0}}}
  +aq_dupw = W.live_ws(W.live_on_msg(au_w, aq_dupm, g5_stamps, 0, "00:00:06"))
  +aq_e_dup = W.auth_edge(au_w, aq_dupw)
  +aq_stalem : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{7, Sess.Chunk{F.string_to_octets(":a.example 903 me :ok\r\n"), 0}}}
  +aq_stalew = W.live_ws(W.live_on_msg(au_w, aq_stalem, g5_stamps, 0, "00:00:07"))
  +aq_e_stale = W.auth_edge(au_w, aq_stalew)
  +aq_e_for = W.auth_edge(au_base, au_mv)
  +aq_total = Nat.add(b2n(W.auth_edge(au_up, au_w)), Nat.add(b2n(aq_e_dup), Nat.add(b2n(aq_e_stale), b2n(aq_e_for))))
  +aq_fail904 : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":b.example 904 me :sasl failed\r\n"), 0}}}
  +aq_fo = W.live_on_msg(au_xup, aq_fail904, g5_stamps, 0, "00:00:03")
  +aq_fw = W.live_ws(aq_fo)
  +g1_ceil = W.id_ceiling(s1())
  +g1_one_seq = Nat.sub(g1_ceil, 2n)
  +g1_one_cl = Cl.set_log_seq(ws_cl_of(id_b, s1()), g1_one_seq)
  +g1_one_st = Sess.session_set_client(ws_part_st(id_b, s1()), g1_one_cl)
  +g1_one_ws = W.replace_part(id_b, W.Part{s1(), W.part_gen_of(id_b, s1()), scope_or_dead(W.scope_of(id_b, s1())), g1_one_st})
  +g1_stamps2 : List<&2, Maybe<&2, String>> = None{} <> None{} <> Nil{}
  +g1_two_msg : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{W.part_gen_of(id_b, s1()), Sess.Chunk{F.string_to_octets(":carol!c@z PRIVMSG me :first\r\n:dave!d@w PRIVMSG me :second\r\n"), 0}}}
  +g1_one_o = W.live_on_msg(g1_one_ws, g1_two_msg, g1_stamps2, 0, "00:00:11")
  +g1_one_w = W.live_ws(g1_one_o)
  +g1_keys_full_sw = W.do_switch(seam2_ws, s1())
  +g1_keys_full = W.live_do_step(g1_keys_full_sw, Sess.keys_enter("hello"))
  +g1_keys_full_rc = W.live_step_routed(g1_keys_full_sw, Sess.keys_enter("hello"))
  +g1_keys_one_sw = W.do_switch(g1_one_ws, s1())
  +g1_keys_one = W.live_do_step(g1_keys_one_sw, Sess.keys_enter("hello"))
  +g1_keys_multi_q = W.do_enter(g1_keys_one_sw, "/query bob")
  +g1_keys_multi = W.live_do_step(g1_keys_multi_q, Sess.keys_enter("aa\nbb"))
  +g1_hist_arch2 = Hist.parse_history_text("#b\tMSG\t\tarch one\n#b\tMSG\t\tarch two\n")
  +g1_hist_one = W.bind_history(g1_one_ws, s1(), g1_hist_arch2, "00:00:12", 100)
  +g1_hist_arch1 = Hist.parse_history_text("#b\tMSG\t\tarch one\n")
  +g1_hist_pos_seq = Nat.sub(g1_ceil, 4n)
  +g1_hist_pos_cl = Cl.set_log_seq(ws_cl_of(id_b, s1()), g1_hist_pos_seq)
  +g1_hist_pos_st = Sess.session_set_client(ws_part_st(id_b, s1()), g1_hist_pos_cl)
  +g1_hist_pos_ws = W.replace_part(id_b, W.Part{s1(), W.part_gen_of(id_b, s1()), scope_or_dead(W.scope_of(id_b, s1())), g1_hist_pos_st})
  +g1_hist_pos = W.bind_history(g1_hist_pos_ws, s1(), g1_hist_arch1, "00:00:12", 100)
  +g1_hist_full = W.bind_history(seam2_ws, s1(), g1_hist_arch1, "00:00:12", 100)
  +g1_diag_full = W.auth_noticed(seam2_ws, s1(), 5)
  +g1_diag_one = W.auth_noticed(g1_one_ws, s1(), 5)
  +g1_single_msg : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{W.part_gen_of(id_b, s1()), Sess.Chunk{F.string_to_octets(":carol!c@z PRIVMSG me :first\r\n"), 0}}}
  +g1_single_o = W.live_on_msg(g1_one_ws, g1_single_msg, g5_stamps, 0, "00:00:11")
  +g1_single_w = W.live_ws(g1_single_o)
  +g1_ping_dm_msg : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{W.part_gen_of(id_b, s1()), Sess.Chunk{F.string_to_octets("PING :x\r\n:dave!d@w PRIVMSG me :late\r\n"), 0}}}
  +g1_ping_dm_o = W.live_on_msg(seam2_ws, g1_ping_dm_msg, g1_stamps2, 0, "00:00:11")
  +g1_ping_dm_w = W.live_ws(g1_ping_dm_o)
  +g1_dm_ping_msg : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{W.part_gen_of(id_b, s1()), Sess.Chunk{F.string_to_octets(":carol!c@z PRIVMSG me :first\r\nPING :x\r\n"), 0}}}
  +g1_dm_ping_o = W.live_on_msg(g1_one_ws, g1_dm_ping_msg, g1_stamps2, 0, "00:00:11")
  +g1_dm_ping_w = W.live_ws(g1_dm_ping_o)
  +nk_s1 = W.do_switch(id_w1, s1())
  +nk_room = W.do_enter(nk_s1, "/join #room")
  +nk_q = W.do_enter(nk_room, "/query alice")
  +nk_sp = W.do_enter(nk_q, "/split #room")
  +nk_gen = W.part_gen_of(nk_sp, s1())
  +nk_scope = scope_or_dead(W.scope_of(nk_sp, s1()))
  +nk_msg : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{nk_gen, Sess.Chunk{F.string_to_octets(":alice!u@h NICK :bob\r\n"), 0}}}
  +nk_chain : Sid.RoutedMsg = Sid.RoutedMsg{s1(), Sess.FromNet{nk_gen, Sess.Chunk{F.string_to_octets(":alice!u@h NICK :bob\r\n:bob!u@h NICK :carol\r\n"), 0}}}
  +nk_stamps2 : List<&2, Maybe<&2, String>> = None{} <> None{} <> Nil{}
  +nk_rej_ws = W.replace_part(nk_sp, W.Part{s1(), nk_gen, nk_scope, Sess.session_set_client(ws_part_st(nk_sp, s1()), Cl.set_log_seq(ws_cl_of(nk_sp, s1()), Nat.sub(g1_ceil, 1n)))})
  +nk_rej_o = W.live_on_msg(nk_rej_ws, nk_msg, g5_stamps, 0, "00:00:11")
  +nk_rej_w = W.live_ws(nk_rej_o)
  +nk_fit_ws = W.replace_part(nk_sp, W.Part{s1(), nk_gen, nk_scope, Sess.session_set_client(ws_part_st(nk_sp, s1()), Cl.set_log_seq(ws_cl_of(nk_sp, s1()), Nat.sub(g1_ceil, 2n)))})
  +nk_fit_o = W.live_on_msg(nk_fit_ws, nk_msg, g5_stamps, 0, "00:00:11")
  +nk_fit_w = W.live_ws(nk_fit_o)
  +nk_half_o = W.live_on_msg(nk_fit_ws, nk_chain, nk_stamps2, 0, "00:00:11")
  +nk_half_w = W.live_ws(nk_half_o)
  +nk_chain_ws = W.replace_part(nk_sp, W.Part{s1(), nk_gen, nk_scope, Sess.session_set_client(ws_part_st(nk_sp, s1()), Cl.set_log_seq(ws_cl_of(nk_sp, s1()), Nat.sub(g1_ceil, 3n)))})
  +nk_chain_o = W.live_on_msg(nk_chain_ws, nk_chain, nk_stamps2, 0, "00:00:11")
  +nk_chain_w = W.live_ws(nk_chain_o)
  +g3_sasl_w0 : Nat = 0n
  +g3_sasl_w1 = W.pipe_after(g3_sasl_w0, W.auth_edge(au_up, au_w))
  +g3_sasl_w2 = W.pipe_after(g3_sasl_w1, aq_e_dup)
  +g3_sasl_w3 = W.pipe_after(g3_sasl_w2, aq_e_stale)
  +g3_sasl_w4 = W.pipe_after(g3_sasl_w3, aq_e_for)
  +g3_sasl_re = W.auth_edge(aq_up2, aq_w2)
  +g3_sasl_w5 = W.pipe_after(g3_sasl_w4, g3_sasl_re)
  +g3_ns_chunk : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":a.example 001 me :welcome\r\n:NickServ!service@services.example NOTICE me :You are now identified as account.\r\n:NickServ!service@services.example NOTICE me :You are now identified as account.\r\n"), 0}}}
  +g3_ns_o = W.live_on_msg(au_nsup, g3_ns_chunk, au_stamps3, 0, "00:00:03")
  +g3_ns_w = W.live_ws(g3_ns_o)
  +g3_ns_edge = W.auth_edge(au_nsup, g3_ns_w)
  +g3_ns_w0 : Nat = 0n
  +g3_ns_w1 = W.pipe_after(g3_ns_w0, g3_ns_edge)
  +g3_ns_dupm : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":NickServ!service@services.example NOTICE me :You are now identified as account.\r\n"), 0}}}
  +g3_ns_dupw = W.live_ws(W.live_on_msg(g3_ns_w, g3_ns_dupm, g5_stamps, 0, "00:00:04"))
  +g3_ns_e_dup = W.auth_edge(g3_ns_w, g3_ns_dupw)
  +g3_ns_w2 = W.pipe_after(g3_ns_w1, g3_ns_e_dup)
  +g3_ns_stalem : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{7, Sess.Chunk{F.string_to_octets(":NickServ!service@services.example NOTICE me :You are now identified as account.\r\n"), 0}}}
  +g3_ns_stalew = W.live_ws(W.live_on_msg(g3_ns_w, g3_ns_stalem, g5_stamps, 0, "00:00:05"))
  +g3_ns_e_stale = W.auth_edge(g3_ns_w, g3_ns_stalew)
  +g3_ns_w3 = W.pipe_after(g3_ns_w2, g3_ns_e_stale)
  +g3_ns_mv = W.do_replace(au_ns_ws(), s0(), "other.example", 6697, False{})
  +g3_ns_e_for = W.auth_edge(au_ns_ws(), g3_ns_mv)
  +g3_ns_w4 = W.pipe_after(g3_ns_w3, g3_ns_e_for)
  +g3_ns_eof : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Eof{}}}
  +g3_ns_fail = W.do_on_fail(au_nsup, g3_ns_eof, "00:00:06")
  +g3_ns_red = W.do_redial(g3_ns_fail, s0(), intent_or_dead(W.on_fail_intent(au_nsup, g3_ns_eof, "00:00:06")))
  +g3_ns_up1 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Up{}}}
  +g3_ns_up2 = W.live_ws(W.live_on_msg(g3_ns_red, g3_ns_up1, g5_stamps, 0, "00:00:07"))
  +g3_ns_chunk2 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Chunk{F.string_to_octets(":a.example 001 me :welcome\r\n:NickServ!service@services.example NOTICE me :You are now identified as account.\r\n:NickServ!service@services.example NOTICE me :You are now identified as account.\r\n"), 0}}}
  +g3_ns_o2 = W.live_on_msg(g3_ns_up2, g3_ns_chunk2, au_stamps3, 0, "00:00:08")
  +g3_ns_rw = W.live_ws(g3_ns_o2)
  +g3_ns_re = W.auth_edge(g3_ns_up2, g3_ns_rw)
  +g3_ns_w5 = W.pipe_after(g3_ns_w4, g3_ns_re)
  +g3_sasl_001 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(":a.example 001 me :welcome\r\n"), 0}}}
  +g3_sasl_join_o = W.live_on_msg(au_w, g3_sasl_001, g5_stamps, 0, "00:00:03")
  +g3_sasl_join_w = W.live_ws(g3_sasl_join_o)
  +g3_sasl_re001 : Sid.RoutedMsg = Sid.RoutedMsg{s0(), Sess.FromNet{1, Sess.Chunk{F.string_to_octets(":a.example 001 me :welcome\r\n"), 0}}}
  +g3_sasl_rejoin_o = W.live_on_msg(aq_w2, g3_sasl_re001, g5_stamps, 0, "00:00:06")
  +g3_sasl_rejoin_w = W.live_ws(g3_sasl_rejoin_o)
  +g3_sasl_rejoin_edge = W.auth_edge(aq_w2, g3_sasl_rejoin_w)
  +g3_sasl_w6 = W.pipe_after(g3_sasl_w5, g3_sasl_rejoin_edge)
  do IO<Unit>:
    Unit <- E.must_eq("s1a reuses lowest slot", ws_key_or(W.history_key(s1a_readded, s1())), "b.example:6697")
    Unit <- E.must("s1a new incarnation differs", Bool.not(U32.is_eq(s1a_newgen, 0)))
    Unit <- E.must("s1a old chunk rejected", Bool.not(W.msg_admitted(s1a_readded, s1a_old_chunk)))
    Unit <- E.must("s1a old writerdone rejected", Bool.not(W.writer_done_acked(s1a_readded, s1a_old_done)))
    Unit <- E.must("s1a old intent rejected", Bool.not(W.redial_ok(s1a_readded, s1(), s1a_old_intent)))
    Unit <- E.must("s1a fresh chunk admitted", W.msg_admitted(s1a_readded, s1a_fresh_chunk))
    Unit <- E.must("s1a sibling unaffected", W.msg_admitted(s1a_readded, s1a_sib_chunk))
    Unit <- E.must("s1b redial differs from old", Bool.not(U32.is_eq(s1b_newgen, 1)))
    Unit <- E.must("s1b old chunk rejected after redial", Bool.not(W.msg_admitted(s1b_redialed, s1b_old_chunk)))
    Unit <- E.must("s1b old writerdone rejected after redial", Bool.not(W.writer_done_acked(s1b_redialed, s1b_old_done)))
    Unit <- E.must("s1b old intent rejected after redial", Bool.not(W.redial_ok(s1b_redialed, s1(), s1b_old_intent)))
    Unit <- E.must("s1b fresh chunk admitted", W.msg_admitted(s1b_redialed, s1b_fresh_chunk))
    Unit <- E.must("s1b sibling unaffected", W.msg_admitted(s1b_redialed, s1b_sib_chunk))
    Unit <- E.must("s2 connecting nil wires", Nat.is_eq(ad_nouts(AD.step_cmd(ad_with_net(Sess.Connecting{}), Sess.keys_enter("aa\nbb"))), 0n))
    Unit <- E.must("s2 connecting no self aa", Bool.not(String.contains(CL.buf_texts(ad_cl(s2_conn), 2n), "aa")))
    Unit <- E.must("s2 connecting no self bb", Bool.not(String.contains(CL.buf_texts(ad_cl(s2_conn), 2n), "bb")))
    Unit <- E.must("s2 connecting draft preserved", String.eq(ad_drafts_of(s2_conn, "#b"), "aa\nbb"))
    Unit <- E.must("s2 reconnecting nil wires", Nat.is_eq(ad_nouts(AD.step_cmd(ad_with_net(Sess.Reconnecting{}), Sess.keys_enter("aa\nbb"))), 0n))
    Unit <- E.must("s2 reconnecting draft preserved", String.eq(ad_drafts_of(s2_recon, "#b"), "aa\nbb"))
    Unit <- E.must("s2 offline nil wires", Nat.is_eq(ad_nouts(AD.step_cmd(ad_with_net(Sess.Offline{}), Sess.keys_enter("aa\nbb"))), 0n))
    Unit <- E.must("s2 offline draft preserved", String.eq(ad_drafts_of(s2_off, "#b"), "aa\nbb"))
    Unit <- E.must("s2 stopping nil wires", Nat.is_eq(ad_nouts(AD.step_cmd(ad_with_net(Sess.Stopping{True{}}), Sess.keys_enter("aa\nbb"))), 0n))
    Unit <- E.must("s2 stopping draft preserved", String.eq(ad_drafts_of(s2_stop, "#b"), "aa\nbb"))
    Unit <- E.must("s2 online exact two wires", Nat.is_eq(ad_nouts(AD.step_cmd(ad_online(), Sess.keys_enter("aa\nbb"))), 2n))
    Unit <- E.must("s2 online clears draft", Bool.not(ad_has_draft(s2_on, "#b")))
    Unit <- E.must("s2 demo exact two wires", Nat.is_eq(ad_nouts(AD.step_cmd(ad_demo(), Sess.keys_enter("aa\nbb"))), 2n))
    Unit <- E.must("s2 demo clears draft", Bool.not(ad_has_draft(s2_demo, "#b")))
    Unit <- E.must("s3 changed clears drafts", Bool.not(ws_has_draft(s3_moved, s0(), "#a")))
    Unit <- E.must_eq("s3 changed empties composer", ws_composer(s3_moved, s0()), "")
    Unit <- E.must("s3 changed reseeds", U32.is_eq(ws_seed(s3_moved, s0()), 1))
    Unit <- E.must_eq("s3 no revival after switch", ws_composer(s3_back, s0()), "")
    Unit <- E.must("s3 port change resets", String.eq(ws_composer(s3_port, s0()), ""))
    Unit <- E.must("s3 same keeps drafts", ws_has_draft(s3_same, s0(), "#a"))
    Unit <- E.must_eq("s3 same retains composer", ws_composer(s3_same, s0()), "aa")
    Unit <- E.must_eq("s3 sibling draft untouched", ws_drafts_of(s3_moved, s1(), "#b"), "bb")
    Unit <- E.must_eq("s3 sibling composer untouched", ws_composer(s3_moved, s1()), "bb")
    Unit <- E.must_eq("s4 full rejects keeps buffer", AD.ad_active(s4_rej), "#b")
    Unit <- E.must("s4 full rejects no query buffer", Bool.not(CL.has_buf(ad_cl(s4_rej), "bob")))
    Unit <- E.must("s4 full rejects nil wires", Nat.is_eq(ad_nouts(AD.step_cmd(s4_full, Sess.keys_enter("/query bob hello"))), 0n))
    Unit <- E.must("s4 full rejects echoes gate", String.contains(CL.buf_texts(ad_cl(s4_rej), 2n), "cannot switch buffer"))
    Unit <- E.must_eq("s4 admitted switches", AD.ad_active(s4_admit), "bob")
    Unit <- E.must("s4 admitted consumes origin", Bool.not(ad_has_draft(s4_admit, "#b")))
    Unit <- E.must_eq("s4 admitted loads destination", AD.ad_composer(s4_admit), "prior")
    Unit <- E.must("s5 mixed wires both lines", Nat.is_eq(ad_nouts(AD.step_cmd(s5_q, Sess.keys_enter("hello\nIDENTIFY hunter2"))), 2n))
    Unit <- E.must("g2 mixed history len one", Nat.is_eq(ad_hist_len(s5_mixed), 1n))
    Unit <- E.must_eq("g2 mixed history exact query", ad_hist_joined(s5_mixed), "/query NickServ")
    Unit <- E.must_eq("g2 mixed echo exact", CL.buf_texts(ad_cl(s5_mixed), 3n), "<me> hello|<me> [credential command sent]|")
    Unit <- E.must_eq("g2 mixed recall exact query", ad_recall(s5_mixed), "/query NickServ")
    Unit <- E.must("g2 login history len one", Nat.is_eq(ad_hist_len(s5_login), 1n))
    Unit <- E.must_eq("g2 login history exact query", ad_hist_joined(s5_login), "/query NickServ")
    Unit <- E.must_eq("g2 login echo exact", CL.buf_texts(ad_cl(s5_login), 3n), "<me> hi|<me> [credential command sent]|")
    Unit <- E.must("g2 plain history len one", Nat.is_eq(ad_hist_len(s5_plain), 1n))
    Unit <- E.must_eq("g2 plain history exact", ad_hist_joined(s5_plain), "aa\nbb")
    Unit <- E.must_eq("g2 plain recall exact", ad_recall(s5_plain), "aa\nbb")
    Unit <- E.must("g2 blank history len one", Nat.is_eq(ad_hist_len(g2_blank), 1n))
    Unit <- E.must_eq("g2 blank history exact", ad_hist_joined(g2_blank), "aa\n\nbb")
    Unit <- E.must_eq("g2 blank recall exact", ad_recall(g2_blank), "aa\n\nbb")
    Unit <- E.must("g2 crlf history len one", Nat.is_eq(ad_hist_len(g2_crlf), 1n))
    Unit <- E.must_eq("g2 crlf history exact", ad_hist_joined(g2_crlf), "aa\r\nbb")
    Unit <- E.must_eq("g2 crlf recall exact", ad_recall(g2_crlf), "aa\r\nbb")
    Unit <- E.must_eq("g4 seam summary exact", g4_seam, "PRIVMSG #b :aa|PRIVMSG #b :bb;;aa\nbb;False;#b;0")
    Unit <- E.must_eq("g4 adapter outs match seam", t_outs(g4_ad_cmd), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("g4 adapter draft match seam", AD.ad_composer(g4_ad), "")
    Unit <- E.must("g4 adapter halt match seam", Bool.not(AD.step_halt(ad_demo(), Sess.keys_enter("aa\nbb"))))
    Unit <- E.must_eq("g4 adapter active match seam", AD.ad_active(g4_ad), "#b")
    Unit <- E.must_eq("g1 preset comp active", ws_comp(g1_both, s0()), "A:old |/j|0")
    Unit <- E.must_eq("g1 preset composer", ws_composer(g1_both, s0()), "old /join ")
    Unit <- E.must_eq("g1 changed resets comp", ws_comp(g1_moved, s0()), "N")
    Unit <- E.must("g1 changed no revival", Bool.not(String.eq(ws_composer(g1_next, s0()), "old /join ")))
    Unit <- E.must_eq("g1 changed next exact", ws_composer(g1_next, s0()), "")
    Unit <- E.must_eq("g1 port resets comp", ws_comp(g1_port, s0()), "N")
    Unit <- E.must("g1 port no revival", Bool.not(String.eq(ws_composer(g1_next_port, s0()), "old /join ")))
    Unit <- E.must_eq("g1 same retains comp", ws_comp(g1_same, s0()), "A:old |/j|0")
    Unit <- E.must_eq("g1 same revives", ws_composer(g1_next_same, s0()), "old /join ")
    Unit <- E.must_eq("g1 sibling comp untouched", ws_comp(g1_moved, s1()), "A:old |/j|0")
    Unit <- E.must_eq("g1 sibling revives", ws_composer(g1_next_sib, s1()), "old /join ")
    Unit <- E.must_eq("g3 online outs fifo", t_outs(AD.step_cmd(ad_online(), Sess.keys_enter("aa\nbb"))), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("g3 demo echo fifo", CL.buf_texts(ad_cl(s2_demo), 2n), "<me> aa|<me> bb|")
    Unit <- E.must_eq("g3 mixed outs fifo", t_outs(AD.step_cmd(s5_q, Sess.keys_enter("hello\nIDENTIFY hunter2"))), "PRIVMSG NickServ :hello|PRIVMSG NickServ :IDENTIFY hunter2")
    Unit <- E.must_eq("g3 login outs fifo", t_outs(AD.step_cmd(s5_q, Sess.keys_enter("hi\nLOGIN acc sekrit"))), "PRIVMSG NickServ :hi|PRIVMSG NickServ :LOGIN acc sekrit")
    Unit <- E.must_eq("g3 bare keeps buffer", AD.ad_active(g3_bare), "#b")
    Unit <- E.must_eq("g3 bare rejected composer", AD.ad_composer(g3_bare), "/query alice")
    Unit <- E.must_eq("g3 bare nil wires", t_outs(g3_bare_cmd), "")
    Unit <- E.must("g3 bare no query buffer", Bool.not(CL.has_buf(ad_cl(g3_bare), "alice")))
    Unit <- E.must_eq("g3 bare gate echo exact", CL.buf_texts(ad_cl(g3_bare), 2n), "cannot switch buffer: draft exceeds limits|")
    Unit <- E.must_eq("g3 admit bare switches", AD.ad_active(g3_admit_bare), "carol")
    Unit <- E.must_eq("g3 admit bare composer empty", AD.ad_composer(g3_admit_bare), "")
    Unit <- E.must("g3 admit bare consumes origin", Bool.not(ad_has_draft(g3_admit_bare, "#b")))
    Unit <- E.must_eq("g3 admit bare nil wires", t_outs(g3_admit_bare_cmd), "")
    Unit <- E.must_eq("g5 up0 online", ws_net(g5_up0, s0()), "online")
    Unit <- E.must_eq("g5 up0 sibling connecting", ws_net(g5_up0, s1()), "connecting")
    Unit <- E.must("g5 up0 sibling one buf", Nat.is_eq(ws_nbufs(g5_up0, s1()), 1n))
    Unit <- E.must_eq("g5 up1 online", ws_net(g5_up1, s1()), "online")
    Unit <- E.must_eq("g5 s1 chat echo", ws_texts(g5_s1hi, s1(), 1n), "<me> s1hi|")
    Unit <- E.must_eq("g5 inbound outs empty", g5_in0outs, "")
    Unit <- E.must_eq("g5 inbound s0 exact", ws_texts(g5_in0, s0(), 1n), "<alice> hi|")
    Unit <- E.must_eq("g5 inbound s1 untouched", ws_texts(g5_in0, s1(), 1n), "<me> s1hi|")
    Unit <- E.must_eq("g5 stale outs empty", g5_stale_outs, "")
    Unit <- E.must_eq("g5 stale s0 unchanged", ws_texts(g5_stale, s0(), 1n), ws_texts(g5_in0, s0(), 1n))
    Unit <- E.must_eq("g5 unknown s0 unchanged", ws_texts(g5_unk, s0(), 1n), ws_texts(g5_in0, s0(), 1n))
    Unit <- E.must_eq("g5 dial routed exact", rc_show(g5_dialrc), "0>d.example:6697@1/me")
    Unit <- E.must("g5 dial gen adopted", U32.is_eq(W.part_gen_of(g5_dialed, s0()), 1))
    Unit <- E.must("g5 dial rebuilds bufs", Nat.is_eq(ws_nbufs(g5_dialed, s0()), 1n))
    Unit <- E.must_eq("g5 stale up stays connecting", ws_net(g5_up_stale, s0()), "connecting")
    Unit <- E.must_eq("g5 fresh up online", ws_net(g5_up_fresh, s0()), "online")
    Unit <- E.must_eq("g5 fail cmd drop", rcc_show(g5_fail_cmd), "0>drop")
    Unit <- E.must_eq("g5 fail intent exact", int_show(g5_fail_int), "0:1:d.example:6697:False")
    Unit <- E.must_eq("g5 fail net reconnecting", ws_net(g5_fail, s0()), "connecting")
    Unit <- E.must_eq("g5 fail s1 untouched", ws_texts(g5_fail, s1(), 1n), "<me> s1hi|")
    Unit <- E.must_eq("g5 fail stale net online", ws_net(g5_fail_stale, s0()), "online")
    Unit <- E.must_eq("g5 fail stale cmd none", rcc_show(g5_fail_stale_cmd), "[none]")
    Unit <- E.must_eq("g5 redial cmd exact", rcc_show(g5_red_cmd), "0>d.example:6697@2/me")
    Unit <- E.must("g5 redial gen adopted", U32.is_eq(W.part_gen_of(g5_red, s0()), 2))
    Unit <- E.must_eq("g5 redial stale none", rcc_show(g5_red_stale), "[none]")
    Unit <- E.must_eq("g5 redial evil none", rcc_show(g5_red_evil), "[none]")
    Unit <- E.must_eq("g5 stale redial keeps reconnecting", ws_net(g5_red_stale_ws, s0()), "connecting")
    Unit <- E.must("g5 stale redial keeps generation", U32.is_eq(W.part_gen_of(g5_red_stale_ws, s0()), 1))
    Unit <- E.must_eq("g5 autoreconn off redial emits nothing", rcc_show(g5_red_off_cmd), "[none]")
    Unit <- E.must_eq("g5 autoreconn off redial leaves offline", ws_net(g5_red_off, s0()), "offline")
    Unit <- E.must_eq("g5 manual connect works after cancel", rc_show(g5_conn_after), "0>d.example:6697@2/me")
    Unit <- E.must_eq("g5 stale redial never cancels", ws_net(g5_red_stale_off, s0()), "connecting")
    Unit <- E.must_eq("s2p production multiline outs fifo", prod_enter_outs("aa\nbb"), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("s2p production multiline echo fifo", prod_enter_texts("aa\nbb", 2n), "<me> aa|<me> bb|")
    Unit <- E.must_eq("s2p production multiline history exact", prod_enter_hist("aa\nbb"), "aa\nbb")
    Unit <- E.must("s2p production multiline history len one", Nat.is_eq(prod_enter_hist_len("aa\nbb"), 1n))
    Unit <- E.must_eq("s2p production multiline recall exact", prod_enter_recall("aa\nbb"), "aa\nbb")
    Unit <- E.must_eq("s2p production blank outs fifo", prod_enter_outs("aa\n\nbb"), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("s2p production crlf outs fifo", prod_enter_outs("aa\r\nbb"), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("s2p production command multiline nil wires", prod_enter_outs("hi\n/quit"), "")
    Unit <- E.must("s2p production command multiline echoes reason", String.contains(prod_enter_texts("hi\n/quit", 2n), "multiline commands are not sent"))
    Unit <- E.must_eq("s2p production command multiline keeps draft", prod_enter_draft("hi\n/quit"), "hi\n/quit")
    Unit <- E.must("s2p production command multiline never halts", Bool.not(prod_enter_halt("hi\n/quit")))
    Unit <- E.must_eq("s2p production oversize nil wires", prod_enter_outs(s2p_over_text), "")
    Unit <- E.must("s2p production oversize echoes cluster reason", String.contains(prod_enter_texts(s2p_over_text, 2n), "message cluster exceeds IRC line limit"))
    Unit <- E.must_eq("s2p production oversize keeps draft", prod_enter_draft(s2p_over_text), s2p_over_text)
    Unit <- E.must_eq("s2p production single unchanged", prod_enter_outs("hello"), "PRIVMSG #b :hello")
    Unit <- E.must("s2p production quit still halts", prod_enter_halt("/quit"))
    Unit <- E.must_eq("s2p production join unchanged", prod_enter_outs("/join #x"), "JOIN #x")
    Unit <- E.must_eq("s2p production offline multiline nil wires", prod_off_outs("aa\nbb"), "")
    Unit <- E.must_eq("s2p production offline multiline keeps draft", prod_off_draft("aa\nbb"), "aa\nbb")
    Unit <- E.must_eq("s2p production cred outs wired", prod_cred_outs("/query NickServ", "hello\nIDENTIFY hunter2"), "PRIVMSG NickServ :hello|PRIVMSG NickServ :IDENTIFY hunter2")
    Unit <- E.must_eq("s2p production cred echo masked", prod_cred_texts("/query NickServ", "hello\nIDENTIFY hunter2", 3n), "<me> hello|<me> [credential command sent]|")
    Unit <- E.must_eq("s2p production cred history suppressed", prod_cred_hist("/query NickServ", "hello\nIDENTIFY hunter2"), "/query NickServ")
    Unit <- E.must_eq("pr secret paste nil wires", prod_enter_outs("hello\n/msg NickServ IDENTIFY s3cret"), "")
    Unit <- E.must_eq("pr secret paste no history", prod_enter_hist("hello\n/msg NickServ IDENTIFY s3cret"), "")
    Unit <- E.must("pr secret paste hist len zero", Nat.is_eq(prod_enter_hist_len("hello\n/msg NickServ IDENTIFY s3cret"), 0n))
    Unit <- E.must_eq("pr secret paste no recall", prod_enter_recall("hello\n/msg NickServ IDENTIFY s3cret"), "")
    Unit <- E.must_eq("pr secret paste keeps draft", prod_enter_draft("hello\n/msg NickServ IDENTIFY s3cret"), "hello\n/msg NickServ IDENTIFY s3cret")
    Unit <- E.must("pr secret paste never halts", Bool.not(prod_enter_halt("hello\n/msg NickServ IDENTIFY s3cret")))
    Unit <- E.must_eq("pr raw paste nil wires", prod_enter_outs("hello\n/raw PRIVMSG NickServ :IDENTIFY s3cret"), "")
    Unit <- E.must_eq("pr raw paste no history", prod_enter_hist("hello\n/raw PRIVMSG NickServ :IDENTIFY s3cret"), "")
    Unit <- E.must_eq("pr raw paste no recall", prod_enter_recall("hello\n/raw PRIVMSG NickServ :IDENTIFY s3cret"), "")
    Unit <- E.must_eq("pr join-key paste nil wires", prod_enter_outs("hello\n/join #c sekrit"), "")
    Unit <- E.must_eq("pr join-key paste no history", prod_enter_hist("hello\n/join #c sekrit"), "")
    Unit <- E.must_eq("pr mode-key paste nil wires", prod_enter_outs("hello\n/mode #b +k sekrit"), "")
    Unit <- E.must_eq("pr mode-key paste no history", prod_enter_hist("hello\n/mode #b +k sekrit"), "")
    Unit <- E.must("pr adapter secret paste hist len zero", Nat.is_eq(ad_hist_len(AD.do_enter(ad_demo(), "hello\n/msg NickServ IDENTIFY s3cret")), 0n))
    Unit <- E.must("pr adapter secret paste nil wires", Nat.is_eq(ad_nouts(AD.step_cmd(ad_demo(), Sess.keys_enter("hello\n/msg NickServ IDENTIFY s3cret"))), 0n))
    Unit <- E.must_eq("s2p shared production CR fifo", prod_enter_outs("aa\rbb"), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("s2p shared production trimmed blank fifo", prod_enter_outs("\naa\n\nbb\n"), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("s2p shared production blank history exact", prod_enter_hist("\naa\n\nbb\n"), "\naa\n\nbb\n")
    Unit <- E.must_eq("s2p shared adapter CR fifo", AD.s2_outs(AD.step_cmd(ad_demo(), Sess.keys_enter("aa\rbb"))), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("s2p shared adapter blank fifo", AD.s2_outs(AD.step_cmd(ad_demo(), Sess.keys_enter("\naa\n\nbb\n"))), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("s2p multiline first quit rejects wires", prod_enter_outs("/quit bye\nhello"), "")
    Unit <- E.must_eq("s2p multiline first quit keeps draft", prod_enter_draft("/quit bye\nhello"), "/quit bye\nhello")
    Unit <- E.must("s2p multiline first quit never halts", Bool.not(prod_enter_halt("/quit bye\nhello")))
    Unit <- E.must("s2p adapter multiline first quit never halts", Bool.not(AD.step_halt(ad_demo(), Sess.keys_enter("/quit bye\nhello"))))
    Unit <- E.must_eq("s2p multiline first action rejects wires", prod_enter_outs("/me waves\nhello"), "")
    Unit <- E.must_eq("s2p multiline first action keeps draft", prod_enter_draft("/me waves\nhello"), "/me waves\nhello")
    Unit <- E.must_eq("s2p single action keeps wire semantics", prod_enter_outs("/me waves"), "PRIVMSG #b :" ++ SCon{Chr{1}, "ACTION waves" ++ SCon{Chr{1}, ""}})
    Unit <- E.must_eq("s2p offline rejected multiline PART keeps membership", String.join(Sess.session_desired_channels(prod_st.trip(Sess.step_keys(Sess.session_set_net(Sess.session_with_client(ad_rooms(), "#a"), Sess.Offline{}), Sess.keys_enter("/part #b bye\nhello")))), "|"), String.join(Sess.session_desired_channels(Sess.session_set_net(Sess.session_with_client(ad_rooms(), "#a"), Sess.Offline{})), "|"))
    Unit <- E.must_eq("s2p typing multiline keeps exact composer", prod_draft(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.Keys{"aa\nbb", False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 0, 0})), "aa\nbb")
    Unit <- E.must_eq("s2p typing multiline emits no wires", prod_outs(Sess.step_keys(Sess.session_demo(ad_rooms(), "#a"), Sess.Keys{"aa\nbb", False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 0, 0})), "")
    Unit <- E.must("bl s0 alert bumps global once", U32.is_eq(bl_b1, 1))
    Unit <- E.must("bl background alert paints advanced", U32.is_eq(bl_painted(bl_w1, bl_b1), 1))
    Unit <- E.must("bl sibling bell isolated", U32.is_eq(W.part_bell(bl_w1, s1()), 0))
    Unit <- E.must("bl focus-only unequal switch never rings", U32.is_eq(bl_painted(bl_sw0, bl_b1), 1))
    Unit <- E.must("bl s1 alert bumps global again", U32.is_eq(bl_b2, 2))
    Unit <- E.must("bl second alert paints advanced", U32.is_eq(bl_painted(bl_w2, bl_b2), 2))
    Unit <- E.must("bl focus-only equal switch never rings", U32.is_eq(bl_painted(bl_sw1, bl_b2), 2))
    Unit <- E.must("bl focus-only switch back never rings", U32.is_eq(bl_painted(bl_sw0b, bl_b2), 2))
    Unit <- E.must("bl stale alert never bumps", U32.is_eq(bl_bS, 2))
    Unit <- E.must("bl stale paint unchanged", U32.is_eq(bl_painted(bl_wS, bl_bS), 2))
    Unit <- E.must("bl plain inbound never bumps", U32.is_eq(bl_bP, 2))
    Unit <- E.must("bl repeat alert bumps exactly once more", U32.is_eq(bl_b3, 3))
    Unit <- E.must("bl repeat alert paints advanced", U32.is_eq(bl_painted(bl_w3, bl_b3), 3))
    Unit <- E.must("au primary holds launch profile", W.part_has_sasl(au_base, s0()))
    Unit <- E.must_eq("au primary exchange exact", W.live_outs(au_o), "AUTHENTICATE PLAIN|AUTHENTICATE AGFjY291bnQAc2VjcmV0|CAP END")
    Unit <- E.must_eq("au primary sasl success", au_seq(au_w, s0()), "1")
    Unit <- E.must("au extra host holds no profile", Bool.not(W.part_has_sasl(au_x, s1())))
    Unit <- E.must_eq("au extra host creds empty", au_pass(au_x, s1()), "")
    Unit <- E.must("au extra host no authenticate", Bool.not(String.contains(W.live_outs(au_xo), "AUTHENTICATE")))
    Unit <- E.must("au extra port holds no profile", Bool.not(W.part_has_sasl(au_p, s1())))
    Unit <- E.must("au extra port no authenticate", Bool.not(String.contains(W.live_outs(au_po), "AUTHENTICATE")))
    Unit <- E.must_eq("au nickserv primary probes", W.live_outs(au_nso), "PRIVMSG NickServ :HELP")
    Unit <- E.must("au nickserv extra no nickserv traffic", Bool.not(String.contains(W.live_outs(au_nxo), "NickServ")))
    Unit <- E.must("au nickserv extra notice no identify", Bool.not(String.contains(W.live_outs(au_nxno), "IDENTIFY")))
    Unit <- E.must_eq("au host change clears credential", au_pass(au_mv, s0()), "")
    Unit <- E.must("au host change disables sasl", Bool.not(W.part_has_sasl(au_mv, s0())))
    Unit <- E.must_eq("au port change clears credential", au_pass(au_mvp, s0()), "")
    Unit <- E.must_eq("au same endpoint retains credential", au_pass(au_same, s0()), "secret")
    Unit <- E.must_eq("au connect change clears credential", au_pass(au_con, s0()), "")
    Unit <- E.must_eq("au same-endpoint redial retains credential", au_pass(au_red, s0()), "secret")
    Unit <- E.must("au same-endpoint redial retains sasl", W.part_has_sasl(au_red, s0()))
    Unit <- E.must_eq("id s0 base zero", Nat.show(W.id_base(s0())), "0")
    Unit <- E.must_eq("id s1 base exact", Nat.show(W.id_base(s1())), "17592186044416")
    Unit <- E.must_eq("id up allocates nothing", id_seq(id_w1, s0()) ++ "/" ++ id_seq(id_w1, s1()), "0/17592186044416")
    Unit <- E.must("id s1 first above s0 range", id_all_lt(id_all(ws_cl_of(id_a, s0())), W.id_base(s1())))
    Unit <- E.must("id admitted ids disjoint", id_disjoint(id_all(ws_cl_of(id_b, s0())), id_all(ws_cl_of(id_b, s1()))))
    Unit <- E.must("id s1 ids above base", id_all_ge(id_all(ws_cl_of(id_b, s1())), W.id_base(s1())))
    Unit <- E.must("id s0 ids below base", id_all_lt(id_all(ws_cl_of(id_b, s0())), W.id_base(s1())))
    Unit <- E.must_eq("id s0 olds stable", id_shows(id_all(ws_cl_of(id_b, s0()))), id_s0_before)
    Unit <- E.must_eq("id stale allocates nothing", id_seq(id_c, s0()) ++ "/" ++ id_seq(id_c, s1()), id_seq(id_b, s0()) ++ "/" ++ id_seq(id_b, s1()))
    Unit <- E.must_eq("id s2 seed exact", id_seq(id_s2, s2()), "35184372088832")
    Unit <- E.must("id replace keeps range", id_all_ge(id_all(ws_cl_of(id_mv, s1())), W.id_base(s1())))
    Unit <- E.must_eq("id2 same readd seeds above retired", id_seq(id2_re, s1()), "17592186044417")
    Unit <- E.must("id2 same fresh distinct from old", Bool.not(id_mem(id_all(ws_cl_of(id2_new, s1())), id2_old_first)))
    Unit <- E.must_eq("id2 same fresh exact next", id_shows(id_all(ws_cl_of(id2_new, s1()))), "17592186044418;")
    Unit <- E.must_eq("id2 changed readd seeds above retired", id_seq(id2_ch, s1()), "17592186044417")
    Unit <- E.must_eq("id2 changed fresh exact next", id_shows(id_all(ws_cl_of(id2_chw, s1()))), "17592186044418;")
    Unit <- E.must_eq("id2 stale after readd allocates nothing", id_seq(id2_staled, s1()), id_seq(id2_new, s1()))
    Unit <- E.must("id2 ordinary pair distinct", id_mem(id_all(ws_cl_of(id2_q2, s0())), 2n) && id_mem(id_all(ws_cl_of(id2_q2, s0())), 3n))
    Unit <- E.must_eq("id2 ordinary pair advances two", id_seq(id2_q2, s0()), "3")
    Unit <- E.must("tk both parts show typers", Nat.is_eq(tk_count(tk_b, s0()), 1n) && Nat.is_eq(tk_count(tk_b, s1()), 1n))
    Unit <- E.must("tk early tick changes nothing", Bool.not(W.tick_changed(tk_early)))
    Unit <- E.must("tk early tick keeps typers", Nat.is_eq(tk_count(W.tick_ws(tk_early), s0()), 1n) && Nat.is_eq(tk_count(W.tick_ws(tk_early), s1()), 1n))
    Unit <- E.must("tk late tick reports change", W.tick_changed(tk_late))
    Unit <- E.must("tk late tick expires focused", Nat.is_eq(tk_count(W.tick_ws(tk_late), s0()), 0n))
    Unit <- E.must("tk late tick expires background", Nat.is_eq(tk_count(W.tick_ws(tk_late), s1()), 0n))
    Unit <- E.must("le focus keeps gen", U32.is_eq(W.part_gen_of(W.do_switch(id_b, s1()), s0()), W.part_gen_of(id_b, s0())))
    Unit <- E.must("le focus keeps bells", U32.is_eq(W.part_bell(W.do_switch(id_b, s1()), s0()), W.part_bell(id_b, s0())) && U32.is_eq(W.part_bell(W.do_switch(id_b, s1()), s1()), W.part_bell(id_b, s1())))
    Unit <- E.must_eq("le focus keeps creds", au_pass(W.do_switch(au_x, s1()), s0()), "secret")
    Unit <- E.must("le focus keeps intent", W.redial_ok(W.do_switch(g5_fail, s1()), s0(), intent_or_dead(g5_fail_int)))
    Unit <- E.must("le switch twice restores current", Key.eq(W.ws_current(W.do_switch(W.do_switch(id_b, s1()), s0())), s0()))
    Unit <- E.must("au primary success edge fires", W.auth_edge(au_up, au_w))
    Unit <- E.must("au no-auth edge quiet", Bool.not(W.auth_edge(au_base, au_up)))
    Unit <- E.must("au endpoint change edge quiet", Bool.not(W.auth_edge(au_base, au_mv)))
    Unit <- E.must_eq("au notice zero allocates nothing", id_seq(W.auth_noticed(au_xup, s0(), 0), s0()), id_seq(au_xup, s0()))
    Unit <- E.must("au notice failure allocates once", Nat.is_eq(Nat.add(Cl.log_seq_of(ws_cl_of(au_xup, s0())), 1n), Cl.log_seq_of(ws_cl_of(W.auth_noticed(au_xup, s0(), 5), s0()))))
    Unit <- E.must_eq("au notice spares sibling", id_seq(W.auth_noticed(au_xup, s0(), 5), s1()), id_seq(au_xup, s1()))
    Unit <- E.must_eq("lm dispatch chunk outs empty", W.live_outs(lm_chunk), "")
    Unit <- E.must_eq("lm dispatch chunk s0 exact", ws_texts(W.live_ws(lm_chunk), s0(), 1n), "<alice> hi|")
    Unit <- E.must_eq("lm dispatch chunk s1 untouched", ws_texts(W.live_ws(lm_chunk), s1(), 1n), "<me> s1hi|")
    Unit <- E.must_eq("lm dispatch stale outs empty", W.live_outs(lm_stale), "")
    Unit <- E.must_eq("lm dispatch stale s0 unchanged", ws_texts(W.live_ws(lm_stale), s0(), 1n), ws_texts(g5_in0, s0(), 1n))
    Unit <- E.must_eq("lm dispatch up online", ws_net(W.live_ws(lm_up), s0()), "online")
    Unit <- E.must_eq("lm dispatch up emits nothing", W.live_outs(lm_up), "")
    Unit <- E.must_eq("lm dispatch fail cmd drop", rcc_show(W.live_cmd(lm_fail)), "0>drop")
    Unit <- E.must_eq("lm dispatch fail intent exact", int_show(W.live_intent(lm_fail)), "0:1:d.example:6697:False")
    Unit <- E.must_eq("lm dispatch fail net reconnecting", ws_net(W.live_ws(lm_fail), s0()), "connecting")
    Unit <- E.must_eq("lm dispatch stale fail stays online", ws_net(W.live_ws(lm_fail_stale), s0()), "online")
    Unit <- E.must_eq("lm dispatch stale fail cmd none", rcc_show(W.live_cmd(lm_fail_stale)), "[none]")
    Unit <- E.must_eq("lm dispatch initial fail offline", ws_net(W.live_ws(lm_init_out), s0()), "offline")
    Unit <- E.must("lm dispatch initial fail echoes reason", String.contains(ws_texts(W.live_ws(lm_init_out), s0(), 0n), "connect failed"))
    Unit <- E.must_eq("lm dispatch initial fail cmd none", rcc_show(W.live_cmd(lm_init_out)), "[none]")
    Unit <- E.must_eq("lm dispatch initial fail intent none", int_show(W.live_intent(lm_init_out)), "[none]")
    Unit <- E.must_eq("lm dispatch initial fail stale ignored", ws_net(W.live_ws(lm_init_stale_out), s0()), "connecting")
    Unit <- E.must_eq("lm dispatch non-net ignored", ws_texts(W.live_ws(lm_key_out), s0(), 1n), ws_texts(g5_in0, s0(), 1n))
    Unit <- E.must_eq("lm dispatch writerdone ignored", ws_texts(W.live_ws(lm_done_out), s0(), 1n), ws_texts(g5_in0, s0(), 1n))
    Unit <- E.must("ls server switch admits", Key.eq(W.ws_current(ls_switched), s1()))
    Unit <- E.must_eq("ls server switch emits nothing", rc_show(W.live_step_routed(ls_base, Sess.keys_enter("/server 2"))), "1>cont:0")
    Unit <- E.must("ls server switch never halts", Bool.not(W.live_step_halt(ls_base, Sess.keys_enter("/server 2"))))
    Unit <- E.must_eq("ls server switch clears command", ws_composer(ls_switched, s0()), "")
    Unit <- E.must_eq("ls server switch keeps sibling draft", ws_composer(ls_switched, s1()), ws_composer(ls_base, s1()))
    Unit <- E.must("ls server absent keeps current", Key.eq(W.ws_current(ls_absent), s0()))
    Unit <- E.must("ls server absent echoes reason", String.contains(ws_texts(ls_absent, s0(), 1n), "no such server"))
    Unit <- E.must_eq("ls server absent clears command", ws_composer(ls_absent, s0()), "")
    Unit <- E.must("ls server bad index keeps current", Key.eq(W.ws_current(ls_bad), s0()))
    Unit <- E.must("ls server bad index falls through", String.contains(ws_texts(ls_bad, s0(), 1n), "unknown command: /server"))
    Unit <- E.must("ls server bare keeps current", Key.eq(W.ws_current(ls_bare), s0()))
    Unit <- E.must_eq("ls server chat routes current", rc_show(W.live_step_routed(ls_chat, Sess.keys_enter("hello"))), "0>cont:1")
    Unit <- E.must("ls server cycle admits", Key.eq(W.ws_current(W.cycle_ws(W.cycle_server(cy_base, "S1D"))), s0()))
    Unit <- E.must("ls server cycle moved", W.cycle_moved(W.cycle_server(cy_base, "S1D")))
    Unit <- E.must_eq("ls server cycle stashes typed", ws_drafts_of(W.cycle_ws(W.cycle_server(cy_base, "S1D")), s1(), "#b"), "S1D")
    Unit <- E.must_eq("ls server cycle loads next", ws_composer(W.cycle_ws(W.cycle_server(cy_base, "S1D")), s0()), "")
    Unit <- E.must("ls server cycle reseeds", U32.is_eq(ws_seed(W.cycle_ws(W.cycle_server(cy_base, "S1D")), s0()), 1))
    Unit <- E.must("ls server cycle single stays", Key.eq(W.ws_current(W.cycle_ws(W.cycle_server(cy_single_base, "x"))), s0()))
    Unit <- E.must("ls server cycle single unmoved", Bool.not(W.cycle_moved(W.cycle_server(cy_single_base, "x"))))
    Unit <- E.must("ls f7 ignored by single-server keys", Sess.pol_eq(Sess.key_pol_raw(Sess.KEY_F7(), 0, 0, 0, 9n), 0, 0, 0, 0, 0, 0, 0))
    Unit <- E.must_eq("ws size sets current", ws_size(sz_set, s1()), "30x100")
    Unit <- E.must_eq("ws size keeps sibling", ws_size(sz_set, s0()), "24x80")
    Unit <- E.must("ws media off clears all", Bool.not(ws_media_on(med_off, s0())) && Bool.not(ws_media_on(med_off, s1())))
    Unit <- E.must("ws media on sets all", ws_media_on(med_on, s0()) && ws_media_on(med_on, s1()))
    Unit <- E.must_eq("g5 redial s1 untouched", ws_texts(g5_red, s1(), 1n), "<me> s1hi|")
    Unit <- E.must("g5 s1 gen zero", U32.is_eq(W.part_gen_of(g5_red, s1()), 0))
    Unit <- E.must_eq("g5 current d", Cl.server_of(Sess.session_cl(W.current_session(g5_dialed))), "d.example")
    Unit <- E.must_eq("g5 current b", Cl.server_of(Sess.session_cl(W.current_session(W.do_switch(g5_dialed, s1())))), "b.example")
    Unit <- E.must("bo s1 opt-out keeps local count", U32.is_eq(W.part_bell(bo_a_w, s1()), 1))
    Unit <- E.must("bo origin flag reads per-part", Bool.not(bo_on(bo_a, s1())) && bo_on(bo_a, s0()))
    Unit <- E.must("bo opted-out event never advances", U32.is_eq(bo_a_b, 0))
    Unit <- E.must("bo opted-out paint repeats seq", U32.is_eq(bl_painted(bo_a_w, bo_a_b), 0))
    Unit <- E.must("bo opted-out model never rings", Bool.not(bo_rings(True{}, bo_painted_on(bo_a_w, bo_a_b), 0, bl_painted(bo_a_w, bo_a_b))))
    Unit <- E.must("bo muted sender never advances", U32.is_eq(bo_m_b, 0))
    Unit <- E.must("bo muted paint repeats seq", U32.is_eq(bl_painted(bo_m_w, bo_m_b), 0))
    Unit <- E.must_eq("bo muted drops text", ws_texts(bo_m_w, s1(), 1n), ws_texts(bo_m, s1(), 1n))
    Unit <- E.must("bo enabled bg advances exactly once", U32.is_eq(bo_b_b, 1))
    Unit <- E.must("bo swapped old/new never advances", U32.is_eq(bo_swap_b, 0))
    Unit <- E.must("bo hoist old/new order matters", Bool.not(U32.is_eq(bo_swap_b, bo_b_b)))
    Unit <- E.must("bo enabled paint advances with enable", U32.is_eq(bl_painted(bo_b_w, bo_b_b), 1) && bo_painted_on(bo_b_w, bo_b_b))
    Unit <- E.must("bo enabled model rings", bo_rings(True{}, bo_painted_on(bo_b_w, bo_b_b), 0, bl_painted(bo_b_w, bo_b_b)))
    Unit <- E.must("bo refocus never re-rings", U32.is_eq(bl_painted(bo_b_f, bo_b_b), 1) && Bool.not(bo_rings(True{}, bo_painted_on(bo_b_f, bo_b_b), 1, bl_painted(bo_b_f, bo_b_b))))
    Unit <- E.must("bo focused opt-out never advances", U32.is_eq(bo_c_b, 0))
    Unit <- E.must("bo re-enabled counts only new", U32.is_eq(bo_c_b2, 1))
    Unit <- E.must("seam1 supplied rows preserved", String.contains(ws_texts(seam1_ws, s0(), 0n), "kept row"))
    Unit <- E.must_eq("seam1 supplied seq preserved", id_seq(seam1_ws, s0()), "1")
    Unit <- E.must("seam2 ceiling predicate admits ordinary", Bool.not(W.seq_full(W.id_base(s1()), s1())))
    Unit <- E.must("seam2 ceiling predicate refuses cap", W.seq_full(seam2_cap, s1()))
    Unit <- E.must_eq("seam2 exhausted chunk dropped", W.live_outs(seam2_o), "")
    Unit <- E.must_eq("seam2 exhausted text unchanged", ws_texts(seam2_w, s1(), 1n), ws_texts(seam2_ws, s1(), 1n))
    Unit <- E.must_eq("seam2 exhausted seq unchanged", id_seq(seam2_w, s1()), id_seq(seam2_ws, s1()))
    Unit <- E.must_eq("seam2 sibling unaffected", ws_texts(seam2_w, s0(), 1n), ws_texts(id_b, s0(), 1n))
    Unit <- E.must("seam3 bind advances never rewinds", Nat.is_gt(seam3_after, seam3_live))
    Unit <- E.must("seam3 bound ids distinct", id_nubbed(id_all(seam3_bound)))
    Unit <- E.must_eq("seam3 final live continues above bind", id_seq(seam3_w, s1()), Nat.show(Nat.add(seam3_after, 1n)))
    Unit <- E.must("seam3 final ids distinct", id_nubbed(id_all(ws_cl_of(seam3_w, s1()))))
    Unit <- E.must("seam3 seed fresh is base", Nat.is_eq(W.seed_floor(s1(), 0n, 0n), W.id_base(s1())))
    Unit <- E.must("seam3 seed mark wins", Nat.is_eq(W.seed_floor(s1(), Nat.add(W.id_base(s1()), 5n), 0n), Nat.add(W.id_base(s1()), 5n)))
    Unit <- E.must("seam3 seed supplied wins", Nat.is_eq(W.seed_floor(s0(), 0n, 7n), 7n))
    Unit <- E.must_eq("aq redial up online", ws_net(aq_up2, s0()), "online")
    Unit <- E.must_eq("aq redial exchange exact", W.live_outs(aq_o2), "AUTHENTICATE PLAIN|AUTHENTICATE AGFjY291bnQAc2VjcmV0|CAP END")
    Unit <- E.must_eq("aq redial success recorded", au_seq(aq_w2, s0()), "1")
    Unit <- E.must("aq bridge fires once across dup/stale/foreign", Nat.is_eq(aq_total, 1n))
    Unit <- E.must("aq duplicate emits none", Bool.not(aq_e_dup))
    Unit <- E.must("aq stale emits none", Bool.not(aq_e_stale))
    Unit <- E.must("aq foreign emits none", Bool.not(aq_e_for))
    Unit <- E.must("aq no-secret failure silent", Bool.not(String.contains(W.live_outs(aq_fo), "AUTHENTICATE")) && Bool.not(W.auth_edge(au_xup, aq_fw)))
    Unit <- E.must_eq("aq no-secret seq stays zero", au_seq(aq_fw, s1()), "0")
    Unit <- E.must_eq("pr svc paste nil wires", prod_svc_outs("hello\n/msg AuthServ IDENTIFY x"), "")
    Unit <- E.must_eq("pr svc paste no history", prod_svc_hist("hello\n/msg AuthServ IDENTIFY x"), "")
    Unit <- E.must_eq("pr svc paste no recall", prod_svc_recall("hello\n/msg AuthServ IDENTIFY x"), "")
    Unit <- E.must_eq("pr svc notice paste nil wires", prod_svc_outs("hello\n/notice AuthServ LOGIN x"), "")
    Unit <- E.must_eq("pr svc notice paste no history", prod_svc_hist("hello\n/notice AuthServ LOGIN x"), "")
    Unit <- E.must_eq("pr svc wired outs fifo", prod_svc2_outs("/query AuthServ", "hello\nIDENTIFY x"), "PRIVMSG AuthServ :hello|PRIVMSG AuthServ :IDENTIFY x")
    Unit <- E.must_eq("pr svc wired echo masked", prod_svc2_texts("/query AuthServ", "hello\nIDENTIFY x", 3n), "<me> hello|<me> [credential command sent]|")
    Unit <- E.must_eq("pr svc wired history suppressed", prod_svc2_hist("/query AuthServ", "hello\nIDENTIFY x"), "/query AuthServ")
    Unit <- E.must("g1 two-line no overflow past ceiling", id_all_lt(id_all(ws_cl_of(g1_one_w, s1())), g1_ceil))
    Unit <- E.must_eq("g1 two-line one fitting admitted", id_seq(g1_one_w, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must("g1 two-line existing preserved", id_mem(id_all(ws_cl_of(g1_one_w, s1())), id2_old_first))
    Unit <- E.must("g1 keys full no overflow", id_all_lt(id_all(ws_cl_of(g1_keys_full, s1())), g1_ceil))
    Unit <- E.must_eq("g1 keys full fail-closed seq", id_seq(g1_keys_full, s1()), id_seq(seam2_ws, s1()))
    Unit <- E.must_eq("g1 keys full no wire", rc_show(g1_keys_full_rc), "1>cont:0")
    Unit <- E.must("g1 keys multi no overflow", id_all_lt(id_all(ws_cl_of(g1_keys_multi, s1())), g1_ceil))
    Unit <- E.must_eq("g1 keys multi fail-closed seq", id_seq(g1_keys_multi, s1()), id_seq(g1_keys_multi_q, s1()))
    Unit <- E.must("g1 hist bind no overflow", id_all_lt(id_all(ws_cl_of(g1_hist_one, s1())), g1_ceil))
    Unit <- E.must_eq("g1 hist bind fail-closed seq", id_seq(g1_hist_one, s1()), id_seq(g1_one_ws, s1()))
    Unit <- E.must_eq("g1 hist single admitted", id_seq(g1_hist_pos, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must_eq("g1 hist full fail-closed seq", id_seq(g1_hist_full, s1()), id_seq(seam2_ws, s1()))
    Unit <- E.must_eq("g1 diag full allocates nothing", id_seq(g1_diag_full, s1()), id_seq(seam2_ws, s1()))
    Unit <- E.must("g1 diag full no overflow", id_all_lt(id_all(ws_cl_of(g1_diag_full, s1())), g1_ceil))
    Unit <- E.must_eq("g1 diag one admits once", id_seq(g1_diag_one, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must_eq("g1 keys one admits", id_seq(g1_keys_one, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must_eq("g1 two-line no rejected outs", W.live_outs(g1_one_o), "")
    Unit <- E.must("g1 two-line carol admitted", g1_has_buf(g1_one_w, s1(), "carol"))
    Unit <- E.must("g1 two-line carol text exact", String.contains(g1_texts_named(g1_one_w, s1(), "carol"), "first"))
    Unit <- E.must("g1 two-line dave rejected absent", Bool.not(g1_has_buf(g1_one_w, s1(), "dave")))
    Unit <- E.must_eq("g1 two-line dave text absent", g1_texts_named(g1_one_w, s1(), "dave"), "[absent]")
    Unit <- E.must("g1 two-line one buffer added", Nat.is_eq(ws_nbufs(g1_one_w, s1()), Nat.add(ws_nbufs(g1_one_ws, s1()), 1n)))
    Unit <- E.must("g1 two-line bell advances once", U32.is_eq(U32.sub(W.part_bell(g1_one_w, s1()), W.part_bell(g1_one_ws, s1())), 1))
    Unit <- E.must("g1 two-line carol unread set", U32.is_eq(g1_unread(g1_one_w, s1(), "carol"), 2))
    Unit <- E.must("g1 two-line dave unread clear", U32.is_eq(g1_unread(g1_one_w, s1(), "dave"), 0))
    Unit <- E.must_eq("g1 single fits seq", id_seq(g1_single_w, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must("g1 single carol admitted", g1_has_buf(g1_single_w, s1(), "carol"))
    Unit <- E.must("g1 single bell advances once", U32.is_eq(U32.sub(W.part_bell(g1_single_w, s1()), W.part_bell(g1_one_ws, s1())), 1))
    Unit <- E.must_eq("g1 single no outs", W.live_outs(g1_single_o), "")
    Unit <- E.must_eq("g1 full ping no Session output", W.live_outs(g1_ping_dm_o), "")
    Unit <- E.must_eq("g1 full ping dm seq unchanged", id_seq(g1_ping_dm_w, s1()), id_seq(seam2_ws, s1()))
    Unit <- E.must("g1 full ping dm dave absent", Bool.not(g1_has_buf(g1_ping_dm_w, s1(), "dave")))
    Unit <- E.must("g1 full ping dm bell quiet", U32.is_eq(W.part_bell(g1_ping_dm_w, s1()), W.part_bell(seam2_ws, s1())))
    Unit <- E.must_eq("g1 one dm ping no Session output", W.live_outs(g1_dm_ping_o), "")
    Unit <- E.must_eq("g1 one dm ping seq", id_seq(g1_dm_ping_w, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must("g1 one dm ping carol admitted", g1_has_buf(g1_dm_ping_w, s1(), "carol"))
    Unit <- E.must_eq("nk setup pane exact", ws_panes_of(nk_sp, s1()), "alice|#room@0")
    Unit <- E.must("nk setup query alice", g1_has_buf(nk_sp, s1(), "alice"))
    Unit <- E.must_eq("nk rej pane exact", ws_panes_of(nk_rej_w, s1()), "alice|#room@0")
    Unit <- E.must("nk rej query alice kept", g1_has_buf(nk_rej_w, s1(), "alice"))
    Unit <- E.must("nk rej bob absent", Bool.not(g1_has_buf(nk_rej_w, s1(), "bob")))
    Unit <- E.must_eq("nk rej seq unchanged", id_seq(nk_rej_w, s1()), id_seq(nk_rej_ws, s1()))
    Unit <- E.must_eq("nk rej outs empty", W.live_outs(nk_rej_o), "")
    Unit <- E.must("nk rej bell quiet", U32.is_eq(W.part_bell(nk_rej_w, s1()), W.part_bell(nk_rej_ws, s1())))
    Unit <- E.must_eq("nk rej alice text unchanged", g1_texts_named(nk_rej_w, s1(), "alice"), g1_texts_named(nk_rej_ws, s1(), "alice"))
    Unit <- E.must_eq("nk fit pane exact", ws_panes_of(nk_fit_w, s1()), "bob|#room@0")
    Unit <- E.must("nk fit bob renamed", g1_has_buf(nk_fit_w, s1(), "bob"))
    Unit <- E.must("nk fit alice gone", Bool.not(g1_has_buf(nk_fit_w, s1(), "alice")))
    Unit <- E.must_eq("nk fit seq", id_seq(nk_fit_w, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must_eq("nk fit outs empty", W.live_outs(nk_fit_o), "")
    Unit <- E.must("nk fit bell quiet", U32.is_eq(W.part_bell(nk_fit_w, s1()), W.part_bell(nk_fit_ws, s1())))
    Unit <- E.must("nk fit change row exact", String.contains(g1_texts_named(nk_fit_w, s1(), "bob"), "alice is now known as bob"))
    Unit <- E.must_eq("nk half pane exact", ws_panes_of(nk_half_w, s1()), "bob|#room@0")
    Unit <- E.must("nk half bob kept", g1_has_buf(nk_half_w, s1(), "bob"))
    Unit <- E.must("nk half carol absent", Bool.not(g1_has_buf(nk_half_w, s1(), "carol")))
    Unit <- E.must_eq("nk half seq", id_seq(nk_half_w, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must_eq("nk chain pane exact", ws_panes_of(nk_chain_w, s1()), "carol|#room@0")
    Unit <- E.must("nk chain carol renamed", g1_has_buf(nk_chain_w, s1(), "carol"))
    Unit <- E.must("nk chain bob gone", Bool.not(g1_has_buf(nk_chain_w, s1(), "bob")))
    Unit <- E.must_eq("nk chain seq", id_seq(nk_chain_w, s1()), Nat.show(Nat.sub(g1_ceil, 1n)))
    Unit <- E.must("g3 sasl trusted writes once", Nat.is_eq(g3_sasl_w1, 1n))
    Unit <- E.must("g3 sasl dup writes zero", Nat.is_eq(g3_sasl_w2, g3_sasl_w1))
    Unit <- E.must("g3 sasl stale writes zero", Nat.is_eq(g3_sasl_w3, g3_sasl_w2))
    Unit <- E.must("g3 sasl foreign writes zero", Nat.is_eq(g3_sasl_w4, g3_sasl_w3))
    Unit <- E.must("g3 sasl exactly one pipe write", Nat.is_eq(g3_sasl_w4, 1n))
    Unit <- E.must("g3 sasl reconnect edge renews", g3_sasl_re)
    Unit <- E.must("g3 sasl reconnect one-shot", Nat.is_eq(g3_sasl_w5, 1n))
    Unit <- E.must("g3 ns trusted edge fires", g3_ns_edge)
    Unit <- E.must_eq("g3 ns success recorded", au_seq(g3_ns_w, s0()), "1")
    Unit <- E.must("g3 ns exchange probes", String.contains(W.live_outs(g3_ns_o), "PRIVMSG NickServ :HELP"))
    Unit <- E.must("g3 ns exchange identifies", String.contains(W.live_outs(g3_ns_o), "PRIVMSG NickServ :IDENTIFY account secret"))
    Unit <- E.must("g3 ns trusted writes once", Nat.is_eq(g3_ns_w1, 1n))
    Unit <- E.must("g3 ns dup writes zero", Nat.is_eq(g3_ns_w2, g3_ns_w1))
    Unit <- E.must("g3 ns stale writes zero", Nat.is_eq(g3_ns_w3, g3_ns_w2))
    Unit <- E.must("g3 ns foreign writes zero", Nat.is_eq(g3_ns_w4, g3_ns_w3))
    Unit <- E.must("g3 ns exactly one pipe write", Nat.is_eq(g3_ns_w4, 1n))
    Unit <- E.must("g3 ns reconnect edge renews", g3_ns_re)
    Unit <- E.must_eq("g3 ns reconnect success recorded", au_seq(g3_ns_rw, s0()), "1")
    Unit <- E.must("g3 ns reconnect exchange renews", String.contains(W.live_outs(g3_ns_o2), "PRIVMSG NickServ :IDENTIFY account secret"))
    Unit <- E.must("g3 ns reconnect one-shot", Nat.is_eq(g3_ns_w5, 1n))
    Unit <- E.must("g3 sasl post-auth JOIN #a", String.contains(W.live_outs(g3_sasl_join_o), "JOIN #a"))
    Unit <- E.must("g3 sasl renewed JOIN #a", String.contains(W.live_outs(g3_sasl_rejoin_o), "JOIN #a"))
    Unit <- E.must("g3 sasl rejoin no new edge", Bool.not(g3_sasl_rejoin_edge))
    Unit <- E.must("g3 sasl rejoin one-shot", Nat.is_eq(g3_sasl_w6, 1n))
    Unit <- E.must("g3 ns post-auth JOIN #a", String.contains(W.live_outs(g3_ns_o), "JOIN #a"))
    Unit <- E.must("g3 ns renewed JOIN #a", String.contains(W.live_outs(g3_ns_o2), "JOIN #a"))
    Unit <- E.must("seam law holds", Sess.supplied_seam_ok())
    Unit <- E.must("s1 epoch reuse law holds", W.epoch_reuse_ok())
    Unit <- E.must("s2 disconnected multiline law holds", AD.disconnected_multiline_ok())
    Unit <- E.must("s3 composer reset law holds", W.composer_reset_ok())
    Unit <- E.must("runtime inbound law holds", W.runtime_inbound_ok())
    Unit <- E.must("runtime redial law holds", W.runtime_redial_ok())
    Unit <- E.must("s4 submit focus atomic law holds", AD.submit_focus_atomic_ok())
    Unit <- E.must("s5 multiline privacy law holds", AD.multiline_privacy_ok())
    Unit <- E.must("q5 req preserved", U32.is_eq(W.routed_chunk_req(q5_chunk_req()), q5_req()))
    Unit <- E.must("q5 non-chunk zero", U32.is_eq(W.routed_chunk_req(q5_eof()), 0))
    Unit <- E.must_eq("q5 feed outs same", W.live_outs(q5_out_req()), W.live_outs(q5_out0()))
    Unit <- E.must_eq("q5 feed texts same", ws_texts(W.live_ws(q5_out_req()), s0(), 1n), ws_texts(W.live_ws(q5_out0()), s0(), 1n))
    Unit <- E.must_eq("q5 stale outs empty", W.live_outs(q5_out_stale()), "")
    Unit <- E.must_eq("q5 stale texts unchanged", ws_texts(W.live_ws(q5_out_stale()), s0(), 1n), ws_texts(q5_ws(), s0(), 1n))
    Unit <- E.must_eq("srch cmd produces search", srch_cmd_text(srch_routed()), "needle")
    Unit <- E.must("srch done lands", W.search_landed(srch_done_ok()))
    Unit <- E.must("srch buffer created", g1_has_buf(W.search_ws(srch_done_ok()), s0(), "*search*"))
    Unit <- E.must("srch stale quiet", Bool.not(W.search_landed(srch_done_stale())))
    Unit <- E.must("srch stale no buffer", Bool.not(g1_has_buf(W.search_ws(srch_done_stale()), s0(), "*search*")))
    Unit <- E.must("h5 armed imports", String.contains(ws_texts(W.live_ws(h5_out_armed()), s0(), 1n), "archive one"))
    Unit <- E.must("h5 unarmed quiet", Bool.not(String.contains(ws_texts(W.live_ws(h5_out_unarmed()), s0(), 1n), "archive one")))
    Unit <- E.must_eq("h5 stale outs empty", W.live_outs(h5_out_stale()), "")
    Unit <- E.must_eq("h5 stale texts unchanged", ws_texts(W.live_ws(h5_out_stale()), s0(), 1n), ws_texts(h5_ws_armed(), s0(), 1n))
    Unit <- E.must("h5 archived nick suppressed", Bool.not(g1_has_buf(h5n_w(), s0(), "alicia")))
    Unit <- E.must("h5 live nick renamed", g1_has_buf(h5n_w(), s0(), "mel"))
    Unit <- E.must("h5 live rename row", String.contains(g1_texts_named(h5n_w(), s0(), "mel"), "is now known as"))
    Unit <- E.must("typ frame active", String.contains(frame_trip_outs(typ_frame()), "active TAGMSG #a"))
    Unit <- E.must("typ halt no typing", Bool.not(String.contains(frame_trip_outs(typ_halt()), "TAGMSG")))
    Unit <- E.must("typ halt flag", frame_trip_halt(typ_halt()))
    Unit <- E.must_eq("typ tick throttled quiet", tick_first_outs(W.tick_outs(typ_tick())), "")
    Unit <- E.must_eq("typ offline quiet", tick_first_outs(W.tick_outs(typ_off_tick())), "")
    Unit <- E.must_eq("typ cm ascii", Sess.session_cm(ws_part_st(typ_cm_ws_k1(), s0())), "ascii")
    Unit <- E.must_eq("typ cm tick active", tick_first_outs(W.tick_outs(typ_cm_tick1())), "@+typing=active TAGMSG a[b")
    Unit <- E.must_eq("typ cm switch done", tick_first_outs(W.tick_outs(typ_cm_tick2())), "@+typing=done TAGMSG a[b")
    Unit <- E.must_eq("typ cm switch active", tick_first_outs(W.tick_outs(typ_cm_tick3())), "@+typing=active TAGMSG a{b")
    Unit <- E.must_eq("h5c full drain refused seq", id_seq(W.live_ws(h5c_full_out()), s0()), id_seq(h5c_full_ws(), s0()))
    Unit <- E.must("h5c full no archive text", Bool.not(String.contains(ws_texts(W.live_ws(h5c_full_out()), s0(), 1n), "archive one")))
    Unit <- E.must_eq("h5c full live wire kept", W.live_outs(h5c_full_out()), W.live_outs(h5c_full_live_only()))
    Unit <- E.must_eq("h5c full live texts kept", ws_texts(W.live_ws(h5c_full_out()), s0(), 1n), ws_texts(h5c_full_ws(), s0(), 1n))
    Unit <- E.must("h5c full no checkpoint", List.is_empty(&2, Nat, h5c_archived(W.live_ws(h5c_full_out()))))
    Unit <- E.must("h5c full no overflow", id_all_lt(id_all(ws_cl_of(W.live_ws(h5c_full_out()), s0())), h5c_ceil()))
    Unit <- E.must_eq("h5c one two refused seq", id_seq(W.live_ws(h5c_two_out()), s0()), id_seq(h5c_one_ws(), s0()))
    Unit <- E.must("h5c one two refused quiet", Bool.not(String.contains(ws_texts(W.live_ws(h5c_two_out()), s0(), 1n), "archive one")) && Bool.not(String.contains(ws_texts(W.live_ws(h5c_two_out()), s0(), 1n), "archive two")))
    Unit <- E.must("h5c one two no checkpoint", List.is_empty(&2, Nat, h5c_archived(W.live_ws(h5c_two_out()))))
    Unit <- E.must_eq("h5c one single admitted seq", id_seq(W.live_ws(h5c_one_out()), s0()), Nat.show(Nat.sub(h5c_ceil(), 1n)))
    Unit <- E.must("h5c one single imports", String.contains(ws_texts(W.live_ws(h5c_one_out()), s0(), 1n), "archive one"))
    Unit <- E.must("h5c one single checkpoint exact", Nat.is_eq(List.length(&2, Nat, h5c_archived(W.live_ws(h5c_one_out()))), 1n) && Hs.batch_claimed_member(h5c_archived(W.live_ws(h5c_one_out())), Nat.sub(h5c_ceil(), 1n)))
    Unit <- E.must_eq("h5c one replay quiet", id_seq(W.live_ws(h5c_one_replay()), s0()), id_seq(W.live_ws(h5c_one_out()), s0()))
    Unit <- E.must("h5c roomy checkpoint exact", Nat.is_eq(List.length(&2, Nat, h5c_archived(W.live_ws(h5_out_armed()))), 1n) && Hs.batch_claimed_member(h5c_archived(W.live_ws(h5_out_armed())), Nat.add(h5c_roomy_pre(), 1n)))
    Unit <- E.must_eq("h5c roomy replay quiet", id_seq(W.live_ws(h5c_roomy_replay()), s0()), id_seq(W.live_ws(h5_out_armed()), s0()))
    Unit <- E.must_eq("sr2 old search stamps", sr2_sig(sr2_old_rc()), "1|0|0|b.example:6697|needle")
    Unit <- E.must_eq("sr2 new search stamps", sr2_sig(sr2_new_rc()), "1|0|1|b.example:6697|needle")
    Unit <- E.must("sr2 stale fenced", Bool.not(W.search_landed(sr2_old_done())))
    Unit <- E.must_eq("sr2 stale want kept", Nat.show(sr2_want(W.search_ws(sr2_old_done()))), Nat.show(sr2_want(sr2_new_ws())))
    Unit <- E.must_eq("sr2 stale used kept", Nat.show(sr2_used(W.search_ws(sr2_old_done()))), Nat.show(sr2_used(sr2_new_ws())))
    Unit <- E.must_eq("sr2 stale seq kept", id_seq(W.search_ws(sr2_old_done()), s1()), id_seq(sr2_new_ws(), s1()))
    Unit <- E.must("sr2 stale no buffer", Bool.not(g1_has_buf(W.search_ws(sr2_old_done()), s1(), "*search*")))
    Unit <- E.must("sr2 stale no checkpoint", List.is_empty(&2, Nat, sr2_archived(W.search_ws(sr2_old_done()))))
    Unit <- E.must("sr2 fresh lands", W.search_landed(sr2_new_done()))
    Unit <- E.must("sr2 fresh buffer created", g1_has_buf(W.search_ws(sr2_new_done()), s1(), "*search*"))
    Unit <- E.must_eq("sr2 fresh consumes once", Nat.show(sr2_used(W.search_ws(sr2_new_done()))), "1")
    Unit <- E.must("sr2 fresh replay quiet", Bool.not(W.search_landed(sr2_replay())))
    Unit <- E.must_eq("sr2 fresh replay texts kept", g1_texts_named(W.search_ws(sr2_replay()), s1(), "*search*"), g1_texts_named(W.search_ws(sr2_new_done()), s1(), "*search*"))
    Unit <- E.must_eq("dial inspector pong dedicated", dial_show(Sess.Pong{7, "PONG :synthetic" <> Nil{}, 11}), "pong:7")
    Unit <- E.must("dial inspector pong not cont", Bool.not(String.eq(dial_show(Sess.Pong{7, "PONG :synthetic" <> Nil{}, 11}), dial_show(Sess.Cont{"PONG :synthetic" <> Nil{}}))))
    Unit <- E.must_eq("dial inspector search dedicated", dial_show(Sess.Search{"needle", "#a", 3n, "needle", "a.example:6697", True{}, 5n, 9n, 11}), "search:needle|#a|3")
    Unit <- E.must("dial inspector search not cont", Bool.not(String.eq(dial_show(Sess.Search{"needle", "#a", 3n, "needle", "a.example:6697", True{}, 5n, 9n, 11}), dial_show(Sess.Cont{Nil{}}))))
    IO.print("sessws_s1s5_demo=ok")
