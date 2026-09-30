# M16.2 split-view red/green goldens.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/view.bend as V
import ../../src/bend/submit.bend as Sub
import ../../src/bend/typing.bend as Ty
import ../../src/bend/frame.bend as Fr

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
  Nat.is_eq(Cl.buf_count(Cl.client_bufs(Sess.session_cl(st1))), 3n)
    && String.eq(Sp.show_state(Sess.session_split(st1)), "off")

def invalid_preserves_split_ok() -> Bool:
  +st0 = Sess.session_demo(test_client(), "#one")
  +st1 = trip_state(Sess.step_enter(st0, "/split server"))
  +st2 = trip_state(Sess.step_enter(st1, "/split #missing"))
  Nat.is_eq(Cl.buf_count(Cl.client_bufs(Sess.session_cl(st2))), 3n)
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

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("parse", Sp.parse_ok())
    Unit <- E.must("bounds", Sp.bounds_ok())
    Unit <- E.must("page", Sp.page_height_ok())
    Unit <- E.must("no_phantom", no_phantom_ok())
    Unit <- E.must("invalid_preserves_split", invalid_preserves_split_ok())
    Unit <- E.must("focused_send", focused_send_ok())
    Unit <- E.must("focused_scroll", focused_scroll_ok())
    Unit <- E.must("draw", V.split_draw_ok())
    Unit <- E.must("preview_typing_view", preview_typing_view_ok())
    Unit <- E.must("typing_preserves_split", typing_preserves_split_ok())
    Unit <- E.must("ctrl_w", Sess.split_key_ok())
    IO.print("split_demo=ok")
