# Session/drafts wiring goldens: focus gating, endpoint replacement, submit
# clearing, multiline routing, and modal stash. Positive controls switch and
# send; negative controls keep the old buffer, preserve text, and reject
# atomically.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as S
import ../../src/bend/session.bend as Sess
import ../../src/bend/isupport.bend as Iso
import ../../src/bend/server_key.bend as Key
import ../../src/bend/drafts.bend as D
import ../../src/bend/session_drafts.bend as AD
import ../../src/bend/upload.bend as U

def submitted.got(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl2, _): cl2

def submitted(+cl: Cl.Client, +input: String) -> Cl.Client:
  submitted.got(S.submit(cl, input))

def rooms() -> Cl.Client:
  submitted(submitted(Cl.init("me", "irc.example"), "/join #a"), "/join #b")

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def bad4() -> Key.ServerId:
  Key.ServerId{4n}

def demo() -> AD.AD:
  AD.wrap(Sess.session_demo(rooms(), "#a"), s0())

def offline() -> AD.AD:
  AD.wrap(Sess.session_with_client(rooms(), "#a"), s0())

# The existing offline() fixture is Connecting; keep a literal Offline control.
def literal_offline() -> AD.AD:
  AD.wrap(Sess.session_set_net(Sess.session_with_client(rooms(), "#a"), Sess.Offline{}), s0())

def online() -> AD.AD:
  AD.wrap(Sess.session_online(Sess.session_with_client(rooms(), "#a")), s0())

def offered() -> AD.AD:
  AD.do_enter(online(), "/upload '/tmp/private file.txt'")

def presented() -> AD.AD:
  +ad = offered()
  AD.with_drafts(Sess.session_upload_present(AD.ad_session(ad), AD.ad_session(ad)), AD.ad_drafts(ad), s0())

def drafts_of(+ad: AD.AD, +key: String) -> String:
  D.get(AD.ad_drafts(ad), s0(), key)

def has_draft(+ad: AD.AD, +key: String) -> Bool:
  D.has(AD.ad_drafts(ad), s0(), key)

def cl_of(+ad: AD.AD) -> Cl.Client:
  Sess.session_cl(AD.ad_session(ad))

def nouts(+cmd: Sess.NetCmd) -> Nat:
  match cmd:
    case Sess.Cont{+outs}: List.length(&2, String, outs)
    case _: 999n

def outs_ok(+cmd: Sess.NetCmd) -> Bool:
  match cmd:
    case Sess.Cont{+outs}: S.out_all_ok(outs)
    case _: False{}

def line_block(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "a\n" ++ line_block(p)

def repeat(n: Nat, +s: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: s ++ repeat(p, s)

def fill(n: Nat, +ds: D.Drafts) -> D.Drafts:
  match n:
    case 0n: ds
    case 1n+p: fill(p, D.set(ds, s0(), "b" ++ Irc.stars.go(D.count(ds)), "x"))

def full() -> AD.AD:
  AD.with_drafts(Sess.session_demo(rooms(), "#a"), fill(16n, D.empty()), s0())

def split_open() -> AD.AD:
  AD.do_enter(demo(), "/split #a")

# Casemapping-alias fixtures: #a[ and #a{ are distinct buffers under
# negotiated ascii but one identity under the default rfc1459 map. Buffers
# are built directly (like Sess.typing_cm_client) because /join stages
# under the default map; navigation below is the real AD key path.
def ascii_iso() -> Iso.State:
  Iso.apply_line(Iso.defaults(), ":s 005 me CASEMAPPING=ascii :are supported")

def alias_bufs() -> List<&2, Cl.Buffer>:
  Cl.server_buf() <> Cl.empty_buf("#a[", True{}) <> Cl.empty_buf("#a{", True{}) <> Nil{}

def alias_cl(+active: Nat) -> Cl.Client:
  Cl.Client{"me", "irc.example", alias_bufs(), active, "", Cl.settings0(), Cl.AuthIdle{}, 0n, False{}}

def alias_ascii(+active: Nat) -> AD.AD:
  AD.wrap(Sess.session_set_iso(Sess.session_demo(alias_cl(active), "#a["), ascii_iso()), s0())

def alias_dflt(+active: Nat) -> AD.AD:
  AD.wrap(Sess.session_demo(alias_cl(active), "#a["), s0())

# Production reads fold under the session's own negotiated map.
def drafts_live(+ad: AD.AD, +key: String) -> String:
  D.get_cm(AD.ad_drafts(ad), s0(), key, Sess.session_cm(AD.ad_session(ad)))

def has_live(+ad: AD.AD, +key: String) -> Bool:
  D.has_cm(AD.ad_drafts(ad), s0(), key, Sess.session_cm(AD.ad_session(ad)))

type ADBox is Data:
  ADBox{cell: List<&2, AD.AD>}

# Singleton-list box: AD embeds Session by value, so ~10 live AD captures
# flatten past the 247-word native continuation limit ("an arity over 247").
# Boxing each fixture behind a recursive List cell keeps bind captures
# narrow (live_context/preferences_live use the same pattern); use sites
# unbox transiently. The Nil arm is unreachable by construction.
def box(+ad: AD.AD) -> ADBox:
  ADBox{ad <> Nil{}}

def unbox.cell(+cell: List<&2, AD.AD>) -> AD.AD:
  match cell:
    case Con{+ad, _}: ad
    case Nil{}: demo()

def unbox(+b: ADBox) -> AD.AD:
  match b:
    case ADBox{+cell}: unbox.cell(cell)

# The pinned native backend permits at most 247 flattened capture words
# per continuation (AGENTS.md). One main with ~35 live AD captures breaches
# it ("an arity over 247"); each phase below holds at most ~11, and main
# only sequences phases. Assertions are unchanged, in the same order.
def ph_typing_tab() -> IO(Unit):
  +ad = box(demo())
  +typed = box(AD.do_step(unbox(ad), AD.typing_keys("bb")))
  +big = Irc.stars.go(4097n)
  +over33 = line_block(33n)
  +moved = box(AD.do_step(unbox(typed), AD.tab_keys("bb", Cl.TabPrev{})))
  +stuck = box(AD.do_step(unbox(typed), AD.tab_keys(big, Cl.TabPrev{})))
  +stuck_lines = box(AD.do_step(unbox(typed), AD.tab_keys(over33, Cl.TabPrev{})))
  +stuck_full = box(AD.do_step(full(), AD.tab_keys("kept", Cl.TabPrev{})))
  +seeded = box(AD.with_drafts(AD.ad_session(unbox(typed)), D.set(AD.ad_drafts(unbox(typed)), s0(), "#a", "aa"), s0()))
  +loaded = box(AD.do_step(unbox(seeded), AD.tab_keys("bb", Cl.TabPrev{})))
  do IO<Unit>:
    Unit <- E.must_eq("typing stashes per buffer", drafts_of(unbox(typed), "#b"), "bb")
    Unit <- E.must("empty typing clears entry", Bool.not(has_draft(AD.do_step(unbox(typed), AD.typing_keys("")), "#b")))
    Unit <- E.must_eq("admitted tab switches buffer", AD.ad_active(unbox(moved)), "#a")
    Unit <- E.must_eq("admitted tab stashes outgoing", drafts_of(unbox(moved), "#b"), "bb")
    Unit <- E.must_eq("admitted tab loads next draft", AD.ad_composer(unbox(loaded)), "aa")
    Unit <- E.must("admitted tab reseeds composer", U32.is_eq(AD.ad_seed(unbox(loaded)), 1))
    Unit <- E.must_eq("rejected tab keeps buffer", AD.ad_active(unbox(stuck)), "#b")
    Unit <- E.must_eq("rejected tab keeps composer", AD.ad_composer(unbox(stuck)), big)
    Unit <- E.must_eq("rejected tab keeps old stash", drafts_of(unbox(stuck), "#b"), "bb")
    Unit <- E.must("rejected tab skips reseed", U32.is_eq(AD.ad_seed(unbox(stuck)), 0))
    Unit <- E.must_eq("rejected tab leaves #a untouched", CL.buf_texts(cl_of(unbox(stuck)), 1n), CL.buf_texts(cl_of(unbox(typed)), 1n))
    Unit <- E.must_eq("rejected tab leaves #b untouched", CL.buf_texts(cl_of(unbox(stuck)), 2n), CL.buf_texts(cl_of(unbox(typed)), 2n))
    Unit <- E.must_eq("over-line tab keeps buffer", AD.ad_active(unbox(stuck_lines)), "#b")
    Unit <- E.must_eq("full-store tab keeps buffer", AD.ad_active(unbox(stuck_full)), "#b")
    Unit <- E.must_eq("full-store tab keeps composer", AD.ad_composer(unbox(stuck_full)), "kept")
    return Unit{}

def ph_click() -> IO(Unit):
  +ad = box(demo())
  +typed = box(AD.do_step(unbox(ad), AD.typing_keys("bb")))
  +big = Irc.stars.go(4097n)
  +seeded = box(AD.with_drafts(AD.ad_session(unbox(typed)), D.set(AD.ad_drafts(unbox(typed)), s0(), "#a", "aa"), s0()))
  +clicked = box(AD.do_step(unbox(seeded), AD.click_keys("bb", 1n)))
  +click_stuck = box(AD.do_step(unbox(typed), AD.click_keys(big, 1n)))
  do IO<Unit>:
    Unit <- E.must_eq("click switches buffer", AD.ad_active(unbox(clicked)), "#a")
    Unit <- E.must_eq("click loads next draft", AD.ad_composer(unbox(clicked)), "aa")
    Unit <- E.must_eq("rejected click keeps buffer", AD.ad_active(unbox(click_stuck)), "#b")
    return Unit{}

def ph_split_server() -> IO(Unit):
  +ad = box(demo())
  +typed = box(AD.do_step(unbox(ad), AD.typing_keys("bb")))
  +big = Irc.stars.go(4097n)
  +split = box(split_open())
  +f6 = box(AD.do_step(unbox(split), AD.focus_keys("")))
  +f6_stuck = box(AD.do_step(unbox(split), AD.focus_keys(big)))
  +split_cmd = box(AD.do_enter(unbox(split), "/focus"))
  +full_split = box(AD.with_drafts(AD.ad_session(unbox(split)), fill(16n, D.empty()), s0()))
  +split_blocked = box(AD.do_enter(unbox(full_split), "/focus"))
  +bad_server = box(AD.with_drafts(AD.ad_session(unbox(typed)), AD.ad_drafts(unbox(typed)), bad4()))
  +bad_tab = box(AD.do_step(unbox(bad_server), AD.tab_keys("bb", Cl.TabPrev{})))
  do IO<Unit>:
    Unit <- E.must_eq("split open keeps active", AD.ad_active(unbox(split)), "#b")
    Unit <- E.must_eq("F6 focus switches pane", AD.ad_active(unbox(f6)), "#a")
    Unit <- E.must_eq("rejected F6 keeps buffer", AD.ad_active(unbox(f6_stuck)), "#b")
    Unit <- E.must_eq("rejected F6 keeps composer", AD.ad_composer(unbox(f6_stuck)), big)
    Unit <- E.must_eq("split focus command switches", AD.ad_active(unbox(split_cmd)), "#a")
    Unit <- E.must_eq("blocked split keeps buffer", AD.ad_active(unbox(split_blocked)), "#b")
    Unit <- E.must("blocked split echoes reason", String.contains(CL.buf_texts(cl_of(unbox(split_blocked)), 2n), "cannot switch buffer"))
    Unit <- E.must_eq("blocked split keeps composer", AD.ad_composer(unbox(split_blocked)), "/focus")
    Unit <- E.must("blocked split keeps store", Nat.is_eq(D.count(AD.ad_drafts(unbox(split_blocked))), 16n))
    Unit <- E.must_eq("invalid server keeps buffer", AD.ad_active(unbox(bad_tab)), "#b")
    return Unit{}

def ph_endpoint_submit() -> IO(Unit):
  +ad = box(demo())
  +typed = box(AD.do_step(unbox(ad), AD.typing_keys("bb")))
  +dialed = box(AD.do_enter(unbox(typed), "/connect other.example 6697"))
  +same = box(AD.do_enter(unbox(typed), "/connect irc.example 6697"))
  +sent = box(AD.do_enter(unbox(typed), "hello"))
  +rej = box(AD.do_enter(unbox(typed), "/reconnect"))
  +off = box(AD.do_enter(offline(), "hi"))
  +literal_off = box(AD.do_enter(literal_offline(), "hi"))
  do IO<Unit>:
    Unit <- E.must_eq("endpoint change dials out", Sess.show_netcmd(AD.step_cmd(unbox(typed), Sess.keys_enter("/connect other.example 6697"))), "dial:other.example:6697")
    Unit <- E.must("endpoint change clears drafts", Bool.not(has_draft(unbox(dialed), "#b")))
    Unit <- E.must("same endpoint keeps drafts", has_draft(unbox(same), "#b"))
    Unit <- E.must("accepted send emits one wire", Nat.is_eq(nouts(AD.step_cmd(unbox(typed), Sess.keys_enter("hello"))), 1n))
    Unit <- E.must("accepted wires fit 512 bytes", outs_ok(AD.step_cmd(unbox(typed), Sess.keys_enter("hello"))))
    Unit <- E.must("accepted send clears draft", Bool.not(has_draft(unbox(sent), "#b")))
    Unit <- E.must_eq("accepted send clears composer", AD.ad_composer(unbox(sent)), "")
    Unit <- E.must("rejected send emits nothing", Nat.is_eq(nouts(AD.step_cmd(unbox(typed), Sess.keys_enter("/reconnect"))), 0n))
    Unit <- E.must_eq("rejected send stashes typed", drafts_of(unbox(rej), "#b"), "/reconnect")
    Unit <- E.must_eq("rejected send restores composer", AD.ad_composer(unbox(rej)), "/reconnect")
    Unit <- E.must_eq("offline send stashes typed", drafts_of(unbox(off), "#b"), "hi")
    Unit <- E.must_eq("offline send restores composer", AD.ad_composer(unbox(off)), "hi")
    Unit <- E.must_eq("literal Offline precondition", Sess.net_label(Sess.session_net(AD.ad_session(literal_offline()))), "offline")
    Unit <- E.must("literal Offline send emits nothing", Nat.is_eq(nouts(AD.step_cmd(literal_offline(), Sess.keys_enter("hi"))), 0n))
    Unit <- E.must_eq("literal Offline send stashes typed", drafts_of(unbox(literal_off), "#b"), "hi")
    Unit <- E.must_eq("literal Offline send restores composer", AD.ad_composer(unbox(literal_off)), "hi")
    Unit <- E.must_eq("literal Offline send has no local echo", CL.buf_texts(cl_of(unbox(literal_off)), 2n), CL.buf_texts(cl_of(literal_offline()), 2n))
    return Unit{}

def ph_multi() -> IO(Unit):
  +over = "ok\n" ++ "e" ++ repeat(260n, SCon{Chr{769}, ""})
  +multi = box(AD.do_enter(demo(), "aa\nbb"))
  +multi_gap = box(AD.do_enter(demo(), "aa\n\nbb"))
  +multi_bad = box(AD.do_enter(demo(), "hi\n/quit"))
  +multi_over = box(AD.do_enter(demo(), over))
  do IO<Unit>:
    Unit <- E.must("multiline emits ordered wires", Nat.is_eq(nouts(AD.step_cmd(demo(), Sess.keys_enter("aa\nbb"))), 2n))
    Unit <- E.must("multiline wires fit 512 bytes", outs_ok(AD.step_cmd(demo(), Sess.keys_enter("aa\nbb"))))
    Unit <- E.must_eq("multiline complete wire order", AD.s2_outs(AD.step_cmd(demo(), Sess.keys_enter("aa\nbb"))), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must("multiline echoes first line", String.contains(CL.buf_texts(cl_of(unbox(multi)), 2n), "aa"))
    Unit <- E.must("multiline echoes second line", String.contains(CL.buf_texts(cl_of(unbox(multi)), 2n), "bb"))
    Unit <- E.must_eq("multiline complete local echo order", CL.buf_texts(cl_of(unbox(multi)), 2n), "<me> aa|<me> bb|")
    Unit <- E.must("multiline clears draft", Bool.not(has_draft(unbox(multi), "#b")))
    Unit <- E.must("blank line collapses, still two wires", Nat.is_eq(nouts(AD.step_cmd(demo(), Sess.keys_enter("aa\n\nbb"))), 2n))
    Unit <- E.must_eq("collapsed multiline complete wire order", AD.s2_outs(AD.step_cmd(demo(), Sess.keys_enter("aa\n\nbb"))), "PRIVMSG #b :aa|PRIVMSG #b :bb")
    Unit <- E.must_eq("collapsed multiline complete local echoes", CL.buf_texts(cl_of(unbox(multi_gap)), 2n), "<me> aa|<me> bb|")
    Unit <- E.must("collapsed multiline clears draft", Bool.not(has_draft(unbox(multi_gap), "#b")))
    Unit <- E.must("oversize multiline emits nothing", Nat.is_eq(nouts(AD.step_cmd(demo(), Sess.keys_enter(over))), 0n))
    Unit <- E.must("oversize multiline echoes cluster reason", String.contains(CL.buf_texts(cl_of(unbox(multi_over)), 2n), "message cluster exceeds IRC line limit"))
    Unit <- E.must_eq("oversize multiline has only rejection echo", CL.buf_texts(cl_of(unbox(multi_over)), 2n), "message cluster exceeds IRC line limit|")
    Unit <- E.must_eq("oversize multiline keeps draft", drafts_of(unbox(multi_over), "#b"), over)
    Unit <- E.must("command multiline emits nothing", Nat.is_eq(nouts(AD.step_cmd(demo(), Sess.keys_enter("hi\n/quit"))), 0n))
    Unit <- E.must("command multiline echoes reason", String.contains(CL.buf_texts(cl_of(unbox(multi_bad)), 2n), "multiline commands are not sent"))
    Unit <- E.must_eq("command multiline has only rejection echo", CL.buf_texts(cl_of(unbox(multi_bad)), 2n), "multiline commands are not sent|")
    Unit <- E.must_eq("command multiline keeps draft", drafts_of(unbox(multi_bad), "#b"), "hi\n/quit")
    Unit <- E.must_eq("command multiline restores composer", AD.ad_composer(unbox(multi_bad)), "hi\n/quit")
    Unit <- E.must("command multiline never halts", Bool.not(AD.step_halt(demo(), Sess.keys_enter("hi\n/quit"))))
    Unit <- E.must("plain send never halts", Bool.not(AD.step_halt(demo(), Sess.keys_enter("hello"))))
    Unit <- E.must("quit still halts", AD.step_halt(demo(), Sess.keys_enter("/quit")))
    return Unit{}

def ph_ctl_modal() -> IO(Unit):
  +big = Irc.stars.go(4097n)
  +ctl = box(AD.do_step(demo(), AD.click_keys("", 0n)))
  +ctl_multi = box(AD.do_enter(unbox(ctl), "aa\nbb"))
  +modal = box(AD.do_enter(presented(), "typed text"))
  +modal_tab = box(AD.do_step(presented(), AD.tab_keys("t", Cl.TabPrev{})))
  +modal_stuck = box(AD.do_step(presented(), AD.tab_keys(big, Cl.TabPrev{})))
  do IO<Unit>:
    Unit <- E.must_eq("control key is server scoped", drafts_of(AD.do_step(unbox(ctl), AD.typing_keys("C")), "*server*"), "C")
    Unit <- E.must("control multiline is read-only", Nat.is_eq(nouts(AD.step_cmd(unbox(ctl), Sess.keys_enter("aa\nbb"))), 0n))
    Unit <- E.must_eq("control reject keeps draft", drafts_of(unbox(ctl_multi), "*server*"), "aa\nbb")
    Unit <- E.must("modal enter sends nothing", Nat.is_eq(nouts(AD.step_cmd(presented(), Sess.keys_enter("typed text"))), 0n))
    Unit <- E.must_eq("modal stash preserves typed", drafts_of(unbox(modal), "#b"), "typed text")
    Unit <- E.must_eq("modal keeps composer", AD.ad_composer(unbox(modal)), "typed text")
    Unit <- E.must_eq("modal admits tab move", AD.ad_active(unbox(modal_tab)), "#a")
    Unit <- E.must_eq("modal rejects over-cap tab", AD.ad_active(unbox(modal_stuck)), "#b")
    return Unit{}

def ph_cm_alias() -> IO(Unit):
  +base = box(alias_ascii(2n))
  +typed = box(AD.do_step(unbox(base), AD.typing_keys("bb")))
  +moved = box(AD.do_step(unbox(typed), AD.tab_keys("bb", Cl.TabPrev{})))
  +typed2 = box(AD.do_step(unbox(moved), AD.typing_keys("cc")))
  +back = box(AD.do_step(unbox(typed2), AD.click_keys("cc", 2n)))
  +r = box(alias_dflt(1n))
  +rt = box(AD.do_step(unbox(r), AD.typing_keys("x")))
  +rnav = box(AD.do_step(unbox(rt), AD.click_keys("x", 2n)))
  do IO<Unit>:
    Unit <- E.must_eq("ascii typing stashes exact key", drafts_live(unbox(typed), "#a{"), "bb")
    Unit <- E.must_eq("ascii stash hides from alias", drafts_live(unbox(typed), "#a["), "")
    Unit <- E.must("ascii stash present under exact key", has_live(unbox(typed), "#a{"))
    Unit <- E.must("ascii stash absent under alias", Bool.not(has_live(unbox(typed), "#a[")))
    Unit <- E.must_eq("ascii tab moves across alias pair", AD.ad_active(unbox(moved)), "#a[")
    Unit <- E.must_eq("ascii move reseeds empty draft", AD.ad_composer(unbox(moved)), "")
    Unit <- E.must("ascii move reseeds seed", U32.is_eq(AD.ad_seed(unbox(moved)), 1))
    Unit <- E.must_eq("ascii move keeps origin draft", drafts_live(unbox(moved), "#a{"), "bb")
    Unit <- E.must_eq("ascii second stash stays distinct", drafts_live(unbox(typed2), "#a["), "cc")
    Unit <- E.must_eq("ascii first stash survives", drafts_live(unbox(typed2), "#a{"), "bb")
    Unit <- E.must_eq("ascii return navigates back", AD.ad_active(unbox(back)), "#a{")
    Unit <- E.must_eq("ascii return reseeds origin draft", AD.ad_composer(unbox(back)), "bb")
    Unit <- E.must_eq("ascii return keeps other draft", drafts_live(unbox(back), "#a["), "cc")
    Unit <- E.must_eq("rfc1459 alias click navigates", AD.ad_active(unbox(rnav)), "#a{")
    Unit <- E.must_eq("rfc1459 alias click keeps composer", AD.ad_composer(unbox(rnav)), "x")
    Unit <- E.must("rfc1459 alias shares one entry", Nat.is_eq(D.count(AD.ad_drafts(unbox(rnav))), 1n))
    Unit <- E.must_eq("rfc1459 alias reads either spelling", drafts_of(unbox(rnav), "#a{"), "x")
    Unit <- E.must_eq("rfc1459 alias keeps stored spelling", drafts_of(unbox(rnav), "#a["), "x")
    return Unit{}

# Actual adapter-route controls for the recursive pre-step Session carrier.
# Busy comes from the existing consent/take APIs, never a fake completion.
def carrier_keyed(pair: Sess.Session & Bool) -> Sess.Session:
  match pair:
    case (st, _): st

def carrier_taken(pair: Sess.Session & Maybe<&2, U.Request>) -> Sess.Session:
  match pair:
    case (st, _): st

def carrier_busy() -> AD.AD:
  +ad = presented()
  +st = carrier_taken(Sess.session_upload_take(carrier_keyed(Sess.session_upload_key(AD.ad_session(ad), 22, 0))))
  AD.with_drafts(st, AD.ad_drafts(ad), s0())

def carrier_allowed(state: U.State) -> Bool:
  match state:
    case U.Busy{_, _, allowed}: allowed
    case _: False{}

def carrier_empty_trip() -> AD.AD & Sess.NetCmd & Bool:
  AD.step_keys.delegated(Nil{}, Sess.step_keys(AD.ad_session(demo()), Sess.keys_enter("never send")), D.empty(), s0(), "never send", True{}, "#b", False{})

def ph_saved_session() -> IO(Unit):
  +before = box(carrier_busy())
  +full_before = box(AD.with_drafts(AD.ad_session(unbox(before)), fill(16n, D.empty()), s0()))
  +rejected = box(AD.do_enter(unbox(full_before), "/join #new"))
  +admitted = box(AD.do_enter(unbox(before), "/join #new"))
  +error = box(AD.do_enter(demo(), "/not-a-command"))
  +ported = box(AD.do_step(AD.wrap(Sess.session_demo_at(rooms(), "#a", 7777), s0()), AD.typing_keys("bb")))
  +same = box(AD.do_enter(unbox(ported), "/connect irc.example 7777"))
  +changed = box(AD.do_enter(unbox(ported), "/connect irc.example 6667"))
  do IO<Unit>:
    Unit <- E.must("carrier precondition owns busy worker", carrier_allowed(Sess.session_upload(AD.ad_session(unbox(before)))))
    Unit <- E.must_eq("carrier rejection errors at original buffer", AD.ad_active(unbox(rejected)), "#b")
    Unit <- E.must("carrier rejection drops speculative destination", Maybe.is_none(&2, Nat, Cl.buf_find(cl_of(unbox(rejected)), "#new")))
    Unit <- E.must("carrier rejection echoes old-buffer reason", String.contains(CL.buf_texts(cl_of(unbox(rejected)), 2n), "cannot switch buffer"))
    Unit <- E.must_eq("carrier rejection preserves typed composer", AD.ad_composer(unbox(rejected)), "/join #new")
    Unit <- E.must("carrier rejection preserves original worker permission", carrier_allowed(Sess.session_upload(AD.ad_session(unbox(rejected)))))
    Unit <- E.must("carrier rejection emits no speculative join", Nat.is_eq(nouts(AD.step_cmd(unbox(full_before), Sess.keys_enter("/join #new"))), 0n))
    Unit <- E.must_eq("carrier admitted join moves", AD.ad_active(unbox(admitted)), "#new")
    Unit <- E.must("carrier admitted transition cannot revive worker permission", Bool.not(carrier_allowed(Sess.session_upload(AD.ad_session(unbox(admitted))))))
    Unit <- E.must_eq("carrier actual submit error preserves draft", drafts_of(unbox(error), "#b"), "/not-a-command")
    Unit <- E.must("carrier same endpoint uses original port", has_draft(unbox(same), "#b"))
    Unit <- E.must("carrier changed port clears origin drafts", Bool.not(has_draft(unbox(changed), "#b")))
    Unit <- E.must("carrier absent-state precondition has actual wire", Nat.is_eq(nouts(AD.step_cmd(demo(), Sess.keys_enter("never send"))), 1n))
    Unit <- E.must("carrier absent state halts fail closed", AD.step_halt.got(carrier_empty_trip()))
    Unit <- E.must("carrier absent state emits nothing", Nat.is_eq(nouts(AD.step_cmd.got(carrier_empty_trip())), 0n))
    return Unit{}

def history_off_ad() -> AD.AD:
  +cl = rooms()
  AD.wrap(Sess.session_demo(Cl.set_settings(cl, Cl.set_history(Cl.get_settings(cl), False{})), "#a"), s0())

# Enabled /history search and page are Search with no live_only Error, and
# the unchanged buffer's composer and draft stay empty. History off stays
# Cont, echoes the disabled refusal, and keeps the typed command.
def ph_history_enter() -> IO(Unit):
  +searched = box(AD.do_enter(demo(), "/history search needle"))
  +paged = box(AD.do_enter(demo(), "/history page 0 needle"))
  +off_search = box(AD.do_enter(history_off_ad(), "/history search needle"))
  +off_page = box(AD.do_enter(history_off_ad(), "/history page 0 needle"))
  do IO<Unit>:
    Unit <- E.must_eq("history search yields Search", Sess.show_netcmd(AD.step_cmd(demo(), Sess.keys_enter("/history search needle"))), "search:needle||16777216")
    Unit <- E.must_eq("history search keeps buffer", AD.ad_active(unbox(searched)), "#b")
    Unit <- E.must_eq("history search buffer has no live_only", CL.buf_texts(cl_of(unbox(searched)), 2n), CL.buf_texts(cl_of(demo()), 2n))
    Unit <- E.must_eq("history search clears composer", AD.ad_composer(unbox(searched)), "")
    Unit <- E.must_eq("history search clears draft", drafts_of(unbox(searched), "#b"), "")
    Unit <- E.must("history search draft absent", Bool.not(has_draft(unbox(searched), "#b")))
    Unit <- E.must_eq("history page yields Search", Sess.show_netcmd(AD.step_cmd(demo(), Sess.keys_enter("/history page 0 needle"))), "search:needle||0")
    Unit <- E.must_eq("history page keeps buffer", AD.ad_active(unbox(paged)), "#b")
    Unit <- E.must_eq("history page buffer has no live_only", CL.buf_texts(cl_of(unbox(paged)), 2n), CL.buf_texts(cl_of(demo()), 2n))
    Unit <- E.must_eq("history page clears composer", AD.ad_composer(unbox(paged)), "")
    Unit <- E.must_eq("history page clears draft", drafts_of(unbox(paged), "#b"), "")
    Unit <- E.must_eq("history off stays Cont", Sess.show_netcmd(AD.step_cmd(history_off_ad(), Sess.keys_enter("/history search needle"))), "cont")
    Unit <- E.must("history off sends no search", Nat.is_eq(nouts(AD.step_cmd(history_off_ad(), Sess.keys_enter("/history search needle"))), 0n))
    Unit <- E.must("history off echoes disabled", String.ends_with(CL.buf_texts(cl_of(unbox(off_search)), 2n), "disk history is disabled|"))
    Unit <- E.must("history off has no live_only", Bool.not(String.contains(CL.buf_texts(cl_of(unbox(off_search)), 2n), "disk history search runs in the live session")))
    Unit <- E.must_eq("history off keeps composer", AD.ad_composer(unbox(off_search)), "/history search needle")
    Unit <- E.must_eq("history off keeps draft", drafts_of(unbox(off_search), "#b"), "/history search needle")
    Unit <- E.must_eq("history off page stays Cont", Sess.show_netcmd(AD.step_cmd(history_off_ad(), Sess.keys_enter("/history page 0 needle"))), "cont")
    Unit <- E.must("history off page sends no search", Nat.is_eq(nouts(AD.step_cmd(history_off_ad(), Sess.keys_enter("/history page 0 needle"))), 0n))
    Unit <- E.must("history off page echoes disabled", String.ends_with(CL.buf_texts(cl_of(unbox(off_page)), 2n), "disk history is disabled|"))
    Unit <- E.must_eq("history off page keeps composer", AD.ad_composer(unbox(off_page)), "/history page 0 needle")
    Unit <- E.must_eq("history off page keeps draft", drafts_of(unbox(off_page), "#b"), "/history page 0 needle")
    return Unit{}

def ph_laws() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("focus gate law holds", AD.focus_gate_ok())
    Unit <- E.must("split gate law holds", AD.split_gate_ok())
    Unit <- E.must("endpoint replace law holds", AD.endpoint_replace_ok())
    Unit <- E.must("submit clear law holds", AD.submit_clear_ok())
    Unit <- E.must("multiline law holds", AD.multiline_ok())
    Unit <- E.must("modal stash law holds", AD.modal_stash_ok())
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- ph_typing_tab()
    Unit <- ph_click()
    Unit <- ph_split_server()
    Unit <- ph_endpoint_submit()
    Unit <- ph_multi()
    Unit <- ph_ctl_modal()
    Unit <- ph_cm_alias()
    Unit <- ph_laws()
    Unit <- ph_saved_session()
    Unit <- ph_history_enter()
    IO.print("session_drafts_demo=ok")
