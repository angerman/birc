# M16.2 split-view red/green goldens.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/view.bend as V

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

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("parse", Sp.parse_ok())
    Unit <- E.must("bounds", Sp.bounds_ok())
    Unit <- E.must("page", Sp.page_height_ok())
    Unit <- E.must("no_phantom", no_phantom_ok())
    Unit <- E.must("focused_send", focused_send_ok())
    Unit <- E.must("draw", V.split_draw_ok())
    Unit <- E.must("ctrl_w", Sess.split_key_ok())
    IO.print("split_demo=ok")
