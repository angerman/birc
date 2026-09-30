# Uncited rem/drop predicates (A1). Not cited by LAWS.bend.
import Base
import ../../src/bend/frame.bend as Fr
import ../../src/bend/session.bend as Sess
import ../../src/bend/buffer.bend as Cl

def rem_cleared_ok() -> Bool:
  +st1 = Sess.st_of_chunk(
    Sess.step_on_chunk(
      Sess.session_online(Sess.session0("me", "h", "#t")),
      Fr.string_to_octets(":a!a@h PRIVMSG #t :partial")
    )
  )
  +st2 = Sess.session_fail(st1, "disconnected")
  +st3 = Sess.st_of_keys(Sess.step_enter(st2, "/connect 127.0.0.1"))
  Bool.not(Sess.sess_rem_nil(st1)) && Sess.sess_rem_nil(st2) && Sess.sess_rem_nil(st3)

def drop_cleared_ok() -> Bool:
  +st1 = Sess.st_of_chunk(
    Sess.step_on_chunk(Sess.session_online(Sess.session0("me", "h", "#t")), Fr.repeat_octet.go(600n, 65, Nil{}))
  )
  +st2 = Sess.session_fail(st1, "d")
  +st3 = Sess.session_online(Sess.st_of_keys(Sess.step_enter(st2, "/connect 127.0.0.1")))
  Sess.sess_drop(st1) && Bool.not(Sess.sess_drop(st2)) && Bool.not(Sess.sess_drop(st3))

def reconnect_cmd_port(c: Sess.NetCmd, +want: U32) -> Bool:
  match c:
    case Sess.Dial{_, port, _}:
      U32.is_eq(port, want)
    case _:
      False{}

def reconnect_port.got(pair: Sess.Session & Sess.NetCmd) -> Bool:
  match pair:
    case (_, cmd):
      reconnect_cmd_port(cmd, 16668)

def reconnect_port_ok() -> Bool:
  +cl0 = Cl.init("me", "old.example")
  +cl1 = Cl.set_settings(cl0, Cl.set_autoreconn(Cl.get_settings(cl0), True{}))
  +s0 = Sess.session_fail(Sess.session_with_client(cl1, "#t"), "initial")
  +s1 = Sess.st_of_keys(Sess.step_enter(s0, "/connect 127.0.0.1 16668"))
  +s2 = Sess.session_fail(Sess.session_online(s1), "lost")
  reconnect_port.got(Sess.session_autoreconnect(s2))

def manual_reconnect_port.got(trip: Sess.Session & Sess.NetCmd & Bool) -> Bool:
  match trip:
    case (_, rest):
      match rest:
        case (cmd, _):
          reconnect_cmd_port(cmd, 16668)

def manual_reconnect_port_ok() -> Bool:
  +s0 = Sess.session_fail(Sess.session_with_client(Cl.init("me", "old.example"), "#t"), "initial")
  +s1 = Sess.st_of_keys(Sess.step_enter(s0, "/connect 127.0.0.1 16668"))
  manual_reconnect_port.got(Sess.step_enter(Sess.session_online(s1), "/reconnect"))

def reconnect_off_drops.got(pair: Sess.Session & Sess.NetCmd) -> Bool:
  match pair:
    case (_, cmd):
      match cmd:
        case Sess.Drop{}: True{}
        case _: False{}

def reconnect_off_drops_ok() -> Bool:
  +s0 = Sess.session_fail(Sess.session_with_client(Cl.init("me", "irc.example"), "#t"), "lost")
  reconnect_off_drops.got(Sess.session_autoreconnect(s0))
