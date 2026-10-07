# CM NICK-to-draft rename guards: the live inbound path moves same-server
# drafts with admitted query renames under the negotiated CASEMAPPING.
# Positive controls move text; archived, ceiling-reverted, unknown-nick,
# channel, and control negatives keep every draft untouched.
# Driver: make test-draft-nick-rename (registered in test-review-pure).
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/frame.bend as F
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/drafts.bend as D
import ../../src/bend/workspace.bend as W
import ../../src/bend/isupport.bend as Iso
import ../../src/bend/history_search.bend as Hs

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

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

def ws_part_st.got(+got: Maybe<&2, W.Part>) -> Sess.Session:
  match got:
    case None{}: Sess.session_demo(Cl.init("nobody", "nowhere.example"), "#lost")
    case Some{+p}: W.part_session(p)

def ws_part_st(+ws: W.Workspace, +id: Key.ServerId) -> Sess.Session:
  ws_part_st.got(W.find_part(ws, id))

def srch_install.got(+ws: W.Workspace, +got: Maybe<&2, W.Part>, +st2: Sess.Session) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, _}: W.replace_part(ws, W.Part{id, gen, scope, st2})

def srch_install(+ws: W.Workspace, +id: Key.ServerId, +st2: Sess.Session) -> W.Workspace:
  srch_install.got(ws, W.find_part(ws, id), st2)

def ws_with_drafts(+ws: W.Workspace, +ds: D.Drafts) -> W.Workspace:
  match ws:
    case W.Workspace{+parts, +cur, _, +rt}: W.Workspace{parts, cur, ds, rt}

def has_buf.got(+got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def has_buf(+ws: W.Workspace, +id: Key.ServerId, +name: String) -> Bool:
  has_buf.got(Cl.buf_find(ws_cl_of(ws, id), name))

def has_buf_cm(+ws: W.Workspace, +id: Key.ServerId, +cm: String, +name: String) -> Bool:
  has_buf.got(Cl.buf_find_cm(ws_cl_of(ws, id), cm, name))

def ctl() -> String:
  D.key_of(True{}, "server")

def qclient() -> Cl.Client:
  Cl.Client{"me", "a.example", Cl.server_buf() <> Cl.empty_buf("#a", True{}) <> Cl.empty_buf("alice", False{}) <> Nil{}, 2n, "", Cl.settings0(), Cl.AuthIdle{}, 0n}

def qsession() -> Sess.Session:
  Sess.session_online(Sess.session_with_client(qclient(), "#a"))

def aclient() -> Cl.Client:
  Cl.Client{"me", "a.example", Cl.server_buf() <> Cl.empty_buf("#a", True{}) <> Cl.empty_buf("a[b", False{}) <> Cl.empty_buf("a{b", False{}) <> Nil{}, 2n, "", Cl.settings0(), Cl.AuthIdle{}, 0n}

def ascii_iso() -> Iso.State:
  Iso.apply_line(Iso.defaults(), ":s 005 me CASEMAPPING=ascii :are supported")

def asession() -> Sess.Session:
  Sess.session_set_iso(Sess.session_online(Sess.session_with_client(aclient(), "#a")), ascii_iso())

def qw() -> W.Workspace:
  srch_install(ws_rooms(), s0(), qsession())

def qa() -> W.Workspace:
  srch_install(ws_rooms(), s0(), asession())

def qds() -> D.Drafts:
  D.set(D.set(D.set(D.empty(), s0(), "alice", "hi alice"), s0(), "#a", "chan draft"), s0(), ctl(), "C")

def ads() -> D.Drafts:
  D.set_cm(D.set_cm(D.empty(), s0(), "a[b", "X", "ascii"), s0(), "a{b", "Y", "ascii")

def qwd() -> W.Workspace:
  ws_with_drafts(qw(), qds())

def qad() -> W.Workspace:
  ws_with_drafts(qa(), ads())

def stamps1() -> List<&2, Maybe<&2, String>>:
  None{} <> Nil{}

def stamps2() -> List<&2, Maybe<&2, String>>:
  None{} <> None{} <> Nil{}

def stamps3() -> List<&2, Maybe<&2, String>>:
  None{} <> None{} <> None{} <> Nil{}

def stamps4() -> List<&2, Maybe<&2, String>>:
  None{} <> None{} <> None{} <> None{} <> Nil{}

def stamps5() -> List<&2, Maybe<&2, String>>:
  None{} <> None{} <> None{} <> None{} <> None{} <> Nil{}

def feed(+ws: W.Workspace, +text: String, +stamps: List<&2, Maybe<&2, String>>, +ts: String) -> W.Workspace:
  W.live_ws(W.live_on_msg(ws, Sid.RoutedMsg{s0(), Sess.FromNet{0, Sess.Chunk{F.string_to_octets(text), 0}}}, stamps, 0, ts))

def live_moved() -> W.Workspace:
  feed(qwd(), ":alice!u@h NICK :bob\r\n", stamps1(), "00:00:01")

def live_chain() -> W.Workspace:
  feed(qwd(), ":alice!u@h NICK :bob\r\n:bob!u@h NICK :carol\r\n", stamps2(), "00:00:01")

def live_archived() -> W.Workspace:
  feed(qwd(), "@batch=zzz;msgid=n1 :alice!u@h NICK :bob\r\n", stamps1(), "00:00:01")

def live_mixed() -> W.Workspace:
  feed(qwd(), "@batch=zzz;msgid=n1 :alice!u@h NICK :bob\r\n:alice!u@h NICK :carol\r\n", stamps2(), "00:00:01")

def live_mixed_rev() -> W.Workspace:
  feed(qwd(), ":alice!u@h NICK :bob\r\n@batch=zzz;msgid=n2 :bob!u@h NICK :carol\r\n", stamps2(), "00:00:01")

def live_unknown() -> W.Workspace:
  feed(qwd(), ":mallory!u@h NICK :mel\r\n", stamps1(), "00:00:01")

def live_ascii() -> W.Workspace:
  feed(qad(), ":a[b!u@h NICK :c\r\n", stamps1(), "00:00:01")

def s0ceil() -> Nat:
  W.id_ceiling(s0())

def capped_st() -> Sess.Session:
  Sess.session_set_client(qsession(), Cl.set_log_seq(Sess.session_cl(qsession()), Nat.sub(s0ceil(), 1n)))

def capped() -> W.Workspace:
  ws_with_drafts(srch_install(ws_rooms(), s0(), capped_st()), qds())

def live_capped() -> W.Workspace:
  feed(capped(), ":alice!u@h NICK :bob\r\n", stamps1(), "00:00:01")

# Same-chunk NICK +/- guards: BATCH open/close control lines share one chunk
# with archived and live NICK lines. Archived NICKs emit no rename effect in
# any position; the close drains once; a live NICK in the same chunk still
# moves exactly one draft in arrival order. Closing batches carry one valid
# PRIVMSG: batch_collect admits only PRIVMSG/NOTICE, so a NICK-only batch
# cannot complete and stays ChatDone with no claims.
def batch_open() -> String:
  ":a.example BATCH +abc chathistory #a\r\n"

def arch_nick() -> String:
  "@batch=abc;msgid=n1 :alice!u@h NICK :bob\r\n"

def arch_nick_bob() -> String:
  "@batch=abc;msgid=n2 :bob!u@h NICK :carol\r\n"

def arch_priv() -> String:
  "@batch=abc;msgid=m1 :alice!u@h PRIVMSG #a :archive one\r\n"

def batch_close() -> String:
  ":a.example BATCH -abc\r\n"

def live_to_carol() -> String:
  ":alice!u@h NICK :carol\r\n"

def live_to_bob() -> String:
  ":alice!u@h NICK :bob\r\n"

def begun_st(pair: Sess.Session & Nat) -> Sess.Session:
  match pair:
    case (+st, _): st

def qsession_armed() -> Sess.Session:
  begun_st(Sess.history_fetch_begin(Sess.history_note_endpoint(qsession(), Cl.log_seq_of(Sess.session_cl(qsession())), "a.example:6697"), "#a"))

def qwad() -> W.Workspace:
  ws_with_drafts(srch_install(ws_rooms(), s0(), qsession_armed()), qds())

def batch_done_ws(+ws: W.Workspace) -> Bool:
  Hs.batch_done(Hs.hist_live_batch(Sess.session_hist_live(ws_part_st(ws, s0()))))

def arch_ids_ws(+ws: W.Workspace) -> List<&2, Nat>:
  Hs.hist_live_archived(Sess.session_hist_live(ws_part_st(ws, s0())))

def live_plus_arch() -> W.Workspace:
  feed(qwad(), batch_open() ++ arch_nick(), stamps2(), "00:00:01")

def live_plus_arch_minus() -> W.Workspace:
  feed(qwad(), batch_open() ++ arch_nick() ++ arch_priv() ++ batch_close(), stamps4(), "00:00:01")

def live_plus_arch_minus_live() -> W.Workspace:
  feed(qwad(), batch_open() ++ arch_nick() ++ arch_priv() ++ batch_close() ++ live_to_carol(), stamps5(), "00:00:01")

def live_live_plus_arch() -> W.Workspace:
  feed(qwad(), live_to_bob() ++ batch_open() ++ arch_nick_bob(), stamps3(), "00:00:01")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("store cm predicate", D.rename_cm_ok())
    Unit <- E.must_eq("line moves draft", D.get(D.rename_nick.line_cm(D.set(D.empty(), s0(), "alice", "hi"), s0(), ":alice!u@h NICK :bob", "rfc1459"), s0(), "bob"), "hi")
    Unit <- E.must("line clears old", Bool.not(D.has(D.rename_nick.line_cm(D.set(D.empty(), s0(), "alice", "hi"), s0(), ":alice!u@h NICK :bob", "rfc1459"), s0(), "alice")))
    Unit <- E.must("privmsg line no-op", Nat.is_eq(D.count(D.rename_nick.line_cm(D.set(D.empty(), s0(), "alice", "hi"), s0(), ":alice!u@h PRIVMSG me :hi", "rfc1459")), 1n))
    Unit <- E.must("invalid line no-op", Nat.is_eq(D.count(D.rename_nick.line_cm(D.set(D.empty(), s0(), "alice", "hi"), s0(), "garbage {{{", "rfc1459")), 1n))
    Unit <- E.must_eq("live moves draft", D.get(W.ws_drafts(live_moved()), s0(), "bob"), "hi alice")
    Unit <- E.must("live clears old draft", Bool.not(D.has(W.ws_drafts(live_moved()), s0(), "alice")))
    Unit <- E.must("live renames buffer", has_buf(live_moved(), s0(), "bob"))
    Unit <- E.must("live drops old buffer", Bool.not(has_buf(live_moved(), s0(), "alice")))
    Unit <- E.must_eq("live keeps chan draft", D.get(W.ws_drafts(live_moved()), s0(), "#a"), "chan draft")
    Unit <- E.must_eq("live keeps control draft", D.get(W.ws_drafts(live_moved()), s0(), ctl()), "C")
    Unit <- E.must_eq("chain ends carol", D.get(W.ws_drafts(live_chain()), s0(), "carol"), "hi alice")
    Unit <- E.must("chain buffer carol", has_buf(live_chain(), s0(), "carol"))
    Unit <- E.must_eq("archived keeps draft", D.get(W.ws_drafts(live_archived()), s0(), "alice"), "hi alice")
    Unit <- E.must("archived keeps buffer", has_buf(live_archived(), s0(), "alice"))
    Unit <- E.must("archived opens nothing", Bool.not(has_buf(live_archived(), s0(), "bob")))
    Unit <- E.must_eq("mixed carol holds", D.get(W.ws_drafts(live_mixed()), s0(), "carol"), "hi alice")
    Unit <- E.must("mixed bob empty", Bool.not(D.has(W.ws_drafts(live_mixed()), s0(), "bob")))
    Unit <- E.must("mixed alice cleared", Bool.not(D.has(W.ws_drafts(live_mixed()), s0(), "alice")))
    Unit <- E.must("mixed buffer carol", has_buf(live_mixed(), s0(), "carol"))
    Unit <- E.must("mixed opens no bob", Bool.not(has_buf(live_mixed(), s0(), "bob")))
    Unit <- E.must_eq("mixedrev bob holds", D.get(W.ws_drafts(live_mixed_rev()), s0(), "bob"), "hi alice")
    Unit <- E.must("mixedrev carol empty", Bool.not(D.has(W.ws_drafts(live_mixed_rev()), s0(), "carol")))
    Unit <- E.must("mixedrev buffer bob", has_buf(live_mixed_rev(), s0(), "bob"))
    Unit <- E.must("mixedrev opens no carol", Bool.not(has_buf(live_mixed_rev(), s0(), "carol")))
    Unit <- E.must("unknown drafts unchanged", Nat.is_eq(D.count(W.ws_drafts(live_unknown())), 3n))
    Unit <- E.must("unknown opens nothing", Bool.not(has_buf(live_unknown(), s0(), "mel")))
    Unit <- E.must_eq("ascii cm negotiated", Sess.session_cm(ws_part_st(qa(), s0())), "ascii")
    Unit <- E.must_eq("ascii moves hit draft", D.get(W.ws_drafts(live_ascii()), s0(), "c"), "X")
    Unit <- E.must_eq("ascii keeps sibling draft", D.get(W.ws_drafts(live_ascii()), s0(), "a{b"), "Y")
    Unit <- E.must("ascii buffer c", has_buf_cm(live_ascii(), s0(), "ascii", "c"))
    Unit <- E.must("ascii buffer sibling", has_buf_cm(live_ascii(), s0(), "ascii", "a{b"))
    Unit <- E.must("ascii drops old", Bool.not(has_buf_cm(live_ascii(), s0(), "ascii", "a[b")))
    Unit <- E.must_eq("capped keeps draft", D.get(W.ws_drafts(live_capped()), s0(), "alice"), "hi alice")
    Unit <- E.must("capped keeps buffer", has_buf(live_capped(), s0(), "alice"))
    Unit <- E.must("capped opens nothing", Bool.not(has_buf(live_capped(), s0(), "bob")))
    Unit <- E.must_eq("capped seq kept", Nat.show(Cl.log_seq_of(ws_cl_of(live_capped(), s0()))), Nat.show(Nat.sub(s0ceil(), 1n)))
    Unit <- E.must("plus archived collecting", Bool.not(batch_done_ws(live_plus_arch())))
    Unit <- E.must_eq("plus archived keeps draft", D.get(W.ws_drafts(live_plus_arch()), s0(), "alice"), "hi alice")
    Unit <- E.must("plus archived no bob draft", Bool.not(D.has(W.ws_drafts(live_plus_arch()), s0(), "bob")))
    Unit <- E.must("plus archived no bob buffer", Bool.not(has_buf(live_plus_arch(), s0(), "bob")))
    Unit <- E.must("full chunk batch cleared", Bool.not(batch_done_ws(live_plus_arch_minus())))
    Unit <- E.must_eq("full chunk claims one", Nat.show(List.length(&2, Nat, arch_ids_ws(live_plus_arch_minus()))), "1")
    Unit <- E.must_eq("full chunk keeps draft", D.get(W.ws_drafts(live_plus_arch_minus()), s0(), "alice"), "hi alice")
    Unit <- E.must("full chunk no bob draft", Bool.not(D.has(W.ws_drafts(live_plus_arch_minus()), s0(), "bob")))
    Unit <- E.must("full chunk no bob buffer", Bool.not(has_buf(live_plus_arch_minus(), s0(), "bob")))
    Unit <- E.must("trailing batch cleared", Bool.not(batch_done_ws(live_plus_arch_minus_live())))
    Unit <- E.must_eq("trailing claims one", Nat.show(List.length(&2, Nat, arch_ids_ws(live_plus_arch_minus_live()))), "1")
    Unit <- E.must_eq("trailing carol holds", D.get(W.ws_drafts(live_plus_arch_minus_live()), s0(), "carol"), "hi alice")
    Unit <- E.must("trailing buffer carol", has_buf(live_plus_arch_minus_live(), s0(), "carol"))
    Unit <- E.must("trailing no bob draft", Bool.not(D.has(W.ws_drafts(live_plus_arch_minus_live()), s0(), "bob")))
    Unit <- E.must("trailing no bob buffer", Bool.not(has_buf(live_plus_arch_minus_live(), s0(), "bob")))
    Unit <- E.must("lead collecting", Bool.not(batch_done_ws(live_live_plus_arch())))
    Unit <- E.must_eq("lead bob holds", D.get(W.ws_drafts(live_live_plus_arch()), s0(), "bob"), "hi alice")
    Unit <- E.must("lead buffer bob", has_buf(live_live_plus_arch(), s0(), "bob"))
    Unit <- E.must("lead no carol draft", Bool.not(D.has(W.ws_drafts(live_live_plus_arch()), s0(), "carol")))
    Unit <- E.must("lead no carol buffer", Bool.not(has_buf(live_live_plus_arch(), s0(), "carol")))
    IO.print("draft_nick_rename=ok")
