# SPDX-License-Identifier: Apache-2.0
# Desired keys and chat rows bind to exact saved host spelling and port.
import Base
import ./expect.bend as E
import ./reconnect_recovery.bend as R
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess

def rejoined(command: String) -> String:
  R.wire(R.chunk(R.enter(R.channels(), command), ":irc.example 001 me :welcome\r\n"))

def present(found: Maybe<&2, Nat>) -> Bool:
  match found:
    case None{}: False{}
    case Some{_}: True{}

def marked() -> Cl.Client:
  +cl = Sess.session_cl(R.channels())
  +settings = Cl.set_hist_cap(Cl.set_ts(Cl.get_settings(cl), False{}), 50)
  Cl.diagnostic(Cl.set_settings(cl, settings), Cl.System{}, "owned endpoint marker")

def client_controls() -> IO(Unit):
  +before = marked()
  +changed = Sess.endpoint_client(before, "IRC.EXAMPLE", 6667, 6667)
  do IO<Unit>:
    Unit <- E.must("case-only endpoint change clears old chat targets", Bool.not(present(Cl.buf_find(changed, "#other"))))
    Unit <- E.must("identical endpoint retains old chat targets", present(Cl.buf_find(Sess.endpoint_client(before, "irc.example", 6667, 6667), "#other")))
    Unit <- E.must("case-only scope change preserves event IDs", Nat.is_eq(Cl.log_seq_of(changed), Cl.log_seq_of(before)))
    Unit <- E.must("case-only scope change preserves log buffer", Nat.is_eq(List.length(&2, Cl.Buffer, Cl.log_buffers(changed)), 1n))
    Unit <- E.must("case-only scope change preserves history cap", U32.is_eq(Cl.settings_hist_cap(Cl.get_settings(changed)), 50))
    Unit <- E.must("case-only scope change preserves timestamp setting", Bool.not(Cl.settings_ts(Cl.get_settings(changed))))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("case-only host change cannot retain desired keys", rejoined("/connect IRC.EXAMPLE 6667"), "JOIN #start")
    Unit <- E.must_eq("identical host and port retain every desired key", rejoined("/connect irc.example 6667"), "JOIN #start|JOIN #other secret-key|JOIN +#third")
    Unit <- E.must_eq("different port cannot retain desired keys", rejoined("/connect irc.example 6668"), "JOIN #start")
    Unit <- E.must_eq("different host cannot retain desired keys", rejoined("/connect other.example 6667"), "JOIN #start")
    Unit <- E.must_eq("terminal root dot changes exact endpoint scope", rejoined("/connect irc.example. 6667"), "JOIN #start")
    Unit <- client_controls()
    IO.print("reconnect_endpoint=ok")
