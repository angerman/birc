# M16.2 split-view red/green goldens.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/view.bend as V
import ../../src/bend/view_laws.bend as VL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/typing.bend as Ty
import ../../src/bend/frame.bend as Fr
import ../../src/bend/client.bend as Feed

def add_buf(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def test_client() -> Cl.Client:
  +cl0 = Cl.init("me", "s")
  +cl1 = add_buf(Cl.buf_get(cl0, "#one", True{}, True{}))
  +cl2 = add_buf(Cl.buf_get(cl1, "#two", True{}, True{}))
  Cl.set_active(cl2, 1n)

def cmd_first(c: Sess.NetCmd) -> String:
  match c:
    case Sess.Cont{xs}:
      match xs:
        case Con{+h, _}: h
        case Nil{}: ""
    case _: ""

def trip_state(t: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match t:
    case (st, _, _): st

def trip_cmd(t: Sess.Session & Sess.NetCmd & Bool) -> Sess.NetCmd:
  match t:
    case (_, cmd, _): cmd

def focused_send_ok() -> Bool:
  +st0 = Sess.session_demo(test_client(), "#one")
  +st1 = trip_state(Sess.step_enter(st0, "/split #two"))
  +st2 = trip_state(Sess.step_keys(st1, Sess.keys_focus()))
  String.eq(Cl.active_buf_name(Sess.session_cl(st2)), "#two")
    && String.eq(cmd_first(trip_cmd(Sess.step_enter(st2, "hello"))), "PRIVMSG #two :hello")

def no_phantom_ok() -> Bool:
  +st0 = Sess.session_demo(test_client(), "#one")
  +st1 = trip_state(Sess.step_enter(st0, "/split #missing"))
  Nat.is_eq(Cl.buf_count(Cl.client_bufs(Sess.session_cl(st1))), 4n)
    && String.eq(Sp.show_state(Sess.session_split(st1)), "off")

def invalid_preserves_split_ok() -> Bool:
  +st0 = Sess.session_demo(test_client(), "#one")
  +st1 = trip_state(Sess.step_enter(st0, "/split server"))
  +st2 = trip_state(Sess.step_enter(st1, "/split #missing"))
  Nat.is_eq(Cl.buf_count(Cl.client_bufs(Sess.session_cl(st2))), 4n)
    && String.eq(Sp.show_state(Sess.session_split(st2)), "stacked:#one:server:0")

def lines(n: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p: Cl.Line{Cl.Msg{}, "", "line", "", 0n} <> lines(p)

def focused_scroll_ok() -> Bool:
  +cl = Cl.buf_set_lines_at(test_client(), 2n, lines(30n))
  +st0 = Sess.session_demo(cl, "#one")
  +st1 = trip_state(Sess.step_enter(st0, "/split #two"))
  +st2 = trip_state(Sess.step_keys(st1, Sess.keys_focus()))
  +st3 = trip_state(Sess.step_keys(st2, Sess.keys_of("", False{}, 0, 0, 8, 0, 0, 0, 0)))
  Nat.is_eq(Cl.buf_scroll_of(Sess.session_cl(st3), 1n), 0n)
    && Nat.is_eq(Cl.buf_scroll_of(Sess.session_cl(st3), 2n), 8n)
    && Sess.pol_eq(Sess.key_pol_for(st2, Sess.KEY_PAGE_UP(), 0, 0, 0, 24), 0, 8, 0, 0, 0, 0, 0)

def submit_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def integrated_ops.go(ops: List<&2, V.DrawOp>, image: Bool, typing: Bool) -> Bool:
  match ops:
    case Nil{}: image && typing
    case Con{V.OpImage{_, _, _, _, +path}, t}:
      integrated_ops.go(t, image || String.eq(path, "/tmp/split.png"), typing)
    case Con{V.OpText{_, _, _, _, _, +text}, t}:
      integrated_ops.go(t, image, typing || String.eq(text, "alice is typing..."))
    case Con{_, t}: integrated_ops.go(t, image, typing)

def integrated_ops(vm: V.ViewModel) -> Bool:
  match vm:
    case V.ViewModel{ops, _}: integrated_ops.go(ops, False{}, False{})

def preview_typing_view_ok() -> Bool:
  +cl0 = submit_client(Sub.submit(test_client(), "/preview /tmp/split.png"))
  +cl = Cl.set_active(cl0, 1n)
  integrated_ops(V.view_draft.state_typing(cl, 24, 80, "", "demo", "alice" <> Nil{}, Sp.On{Sp.Stacked{}, "*preview*", "#one", 1}))

def typing_preserves_split_ok() -> Bool:
  +st0 = trip_state(Sess.step_enter(Sess.session_demo(test_client(), "#one"), "/split #two"))
  +st1 = Sess.st_of_chunk(Sess.step_on_chunk_ms(st0, Fr.string_to_octets("@+typing=active :alice!a@h TAGMSG #one\r\n"), 1000))
  Sp.is_on(Sess.session_split(st1)) && Ty.has(Sess.session_typing(st1), "#one", "alice")

def server_query_client() -> Cl.Client:
  +control = Cl.client_log(test_client(), 0n, Cl.System{}, "CONTROL-WELCOME")
  Cl.set_active(Feed.feed(control, ":server!u@h PRIVMSG me :PRIVATE-SERVER-QUERY"), 3n)

def idx_is(idx: Maybe<&2, Nat>, expected: Nat) -> Bool:
  match idx:
    case None{}: False{}
    case Some{i}: Nat.is_eq(i, expected)

def split_identity_ok() -> Bool:
  +cl = server_query_client()
  String.eq(Sp.name_at(cl, 0n), "*server*")
    && String.eq(Sp.name_at(cl, 3n), "server")
    && idx_is(Sp.named_idx(cl, "*server*"), 0n)
    && idx_is(Sp.named_idx(cl, "server"), 3n)
    && idx_is(Sp.target_idx(cl, "server"), 3n)
    && idx_is(Sp.target_idx(test_client(), "server"), 0n)
    && idx_is(Sp.target_idx(cl, "*server*"), 0n)
    && Bool.not(Sp.found(test_client(), "server"))

def spans_text(spans: List<&2, V.SpanOp>) -> String:
  match spans:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text(t)

def ops_contain(ops: List<&2, V.DrawOp>, +text: String) -> Bool:
  match ops:
    case Nil{}: False{}
    case Con{V.OpLine{_, _, _, _, spans}, t}:
      String.contains(spans_text(spans), text) || ops_contain(t, text)
    case Con{_, t}: ops_contain(t, text)

def view_contains(vm: V.ViewModel, text: String) -> Bool:
  match vm:
    case V.ViewModel{ops, _}: ops_contain(ops, text)

def split_server_view_ok() -> Bool:
  +st0 = Sess.session_demo(server_query_client(), "#one")
  +st = trip_state(Sess.step_enter(st0, "/vsplit #one"))
  +vm = V.view_draft_split(Sess.session_cl(st), 30, 120, "", "demo", Sess.session_split(st))
  view_contains(vm, "PRIVATE-SERVER-QUERY") && Bool.not(view_contains(vm, "CONTROL-WELCOME"))

# Each step keeps at most two Sessions. A four-session && chain exceeds
# the pinned 247-word backend cap.
def split_server_focus_ok.line(+st: Sess.Session, +text: String) -> Bool:
  String.eq(cmd_first(trip_cmd(Sess.step_enter(st, text))), "PRIVMSG server :" ++ text)

def split_server_focus_ok.after_before(ok: Bool, +st2: Sess.Session) -> Bool:
  match ok:
    case False{}: False{}
    case True{}: split_server_focus_ok.line(st2, "after")

def split_server_focus_ok.active2(ok2: Bool, +st0: Sess.Session, +st2: Sess.Session) -> Bool:
  match ok2:
    case False{}: False{}
    case True{}: split_server_focus_ok.after_before(split_server_focus_ok.line(st0, "before"), st2)

def split_server_focus_ok.on2(+st0: Sess.Session, +st2: Sess.Session) -> Bool:
  split_server_focus_ok.active2(Nat.is_eq(Cl.active_of(Sess.session_cl(st2)), 3n), st0, st2)

def split_server_focus_ok.from2(ok1: Bool, +st0: Sess.Session, +st1: Sess.Session) -> Bool:
  match ok1:
    case False{}: False{}
    case True{}: split_server_focus_ok.on2(st0, trip_state(Sess.step_keys(st1, Sess.keys_focus())))

def split_server_focus_ok.from1(+st0: Sess.Session, +st1: Sess.Session) -> Bool:
  split_server_focus_ok.from2(Nat.is_eq(Cl.active_of(Sess.session_cl(st1)), 1n), st0, st1)

def split_server_focus_ok() -> Bool:
  +st0 = trip_state(Sess.step_enter(Sess.session_demo(server_query_client(), "#one"), "/vsplit #one"))
  split_server_focus_ok.from1(st0, trip_state(Sess.step_keys(st0, Sess.keys_focus())))

def ascii_brackets() -> Cl.Client:
  Cl.Client{"me", "s", Cl.server_buf() <> Cl.empty_buf("#x{", True{}) <> Cl.empty_buf("#x[", True{}) <> Nil{}, 1n, "", Cl.settings0(), Cl.AuthIdle{}, 0n, False{}}

def ascii_pane_lookup_ok() -> Bool:
  +cl = ascii_brackets()
  idx_is(Sp.named_idx(cl, "*server*"), 0n)
    && idx_is(Sp.named_idx_cm("ascii", cl, "*server*"), 0n)
    && idx_is(Sp.named_idx(cl, "#x{"), 1n)
    && idx_is(Sp.named_idx(cl, "#x["), 1n)
    && idx_is(Sp.named_idx_cm("ascii", cl, "#x{"), 1n)
    && idx_is(Sp.named_idx_cm("ascii", cl, "#x["), 2n)

def ascii_split_on_ok() -> Bool:
  +cl = ascii_brackets()
  Sp.is_on(Sp.normalize_cm("ascii", cl, Sp.On{Sp.Stacked{}, "#x[", "#x{", 0}))

def removed_query_split_ok() -> Bool:
  +st = trip_state(Sess.step_enter(Sess.session_demo(server_query_client(), "#one"), "/vsplit #one"))
  +closed = Cl.drop_buf(Sess.session_cl(st), 3n)
  Bool.not(Sp.is_on(Sp.normalize(closed, Sess.session_split(st))))
    && Bool.not(Sp.found(closed, "server"))

def split_control_query_ok() -> Bool:
  +cl = Cl.set_active(server_query_client(), 0n)
  +st = trip_state(Sess.step_enter(Sess.session_demo(cl, "#one"), "/split server"))
  +focused = trip_state(Sess.step_keys(st, Sess.keys_focus()))
  Sp.is_on(Sess.session_split(st))
    && String.eq(Sp.show_state(Sess.session_split(st)), "stacked:server:server:0")
    && Nat.is_eq(Cl.active_of(Sess.session_cl(focused)), 3n)
    && String.eq(cmd_first(trip_cmd(Sess.step_enter(focused, "hello"))), "PRIVMSG server :hello")

def split_explicit_control_ok() -> Bool:
  +st = trip_state(Sess.step_enter(Sess.session_demo(server_query_client(), "#one"), "/split *server*"))
  +vm = V.view_draft_split(Sess.session_cl(st), 30, 120, "", "demo", Sess.session_split(st))
  view_ok = Sp.is_on(Sess.session_split(st)) && view_contains(vm, "CONTROL-WELCOME")
    && view_contains(vm, "PRIVATE-SERVER-QUERY")
  +control = trip_state(Sess.step_keys(st, Sess.keys_focus()))
  control_active = Cl.active_of(Sess.session_cl(control))
  control_local = String.is_empty(cmd_first(trip_cmd(Sess.step_enter(control, "local"))))
  +query = trip_state(Sess.step_keys(control, Sess.keys_focus()))
  view_ok && Nat.is_eq(control_active, 0n)
    && Nat.is_eq(Cl.active_of(Sess.session_cl(query)), 3n)
    && control_local
    && String.eq(cmd_first(trip_cmd(Sess.step_enter(query, "hello"))), "PRIVMSG server :hello")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("parse", Sp.parse_ok())
    Unit <- E.must("bounds", Sp.bounds_ok())
    Unit <- E.must("page", Sp.page_height_ok())
    Unit <- E.must("no_phantom", no_phantom_ok())
    Unit <- E.must("invalid_preserves_split", invalid_preserves_split_ok())
    Unit <- E.must("focused_send", focused_send_ok())
    Unit <- E.must("focused_scroll", focused_scroll_ok())
    Unit <- E.must("draw", VL.split_draw_ok())
    Unit <- E.must("preview_typing_view", preview_typing_view_ok())
    Unit <- E.must("typing_preserves_split", typing_preserves_split_ok())
    Unit <- E.must("split_control_query_identity", split_identity_ok())
    Unit <- E.must("split_server_view", split_server_view_ok())
    Unit <- E.must("split_server_focus_send", split_server_focus_ok())
    Unit <- E.must("removed_query_closes_split", removed_query_split_ok())
    Unit <- E.must("split_control_query", split_control_query_ok())
    Unit <- E.must("split_explicit_control", split_explicit_control_ok())
    Unit <- E.must("ascii panes stay distinct", ascii_pane_lookup_ok())
    Unit <- E.must("ascii bracket split stays on", ascii_split_on_ok())
    Unit <- E.must("ctrl_w", Sess.split_key_ok())
    IO.print("split_demo=ok")
