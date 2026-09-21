# Uncited rem/drop predicates (A1). Not cited by LAWS.bend.
import Base
import ../../src/bend/frame.bend as Fr
import ../../src/bend/session.bend as Sess

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
