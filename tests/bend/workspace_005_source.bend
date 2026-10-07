# SPDX-License-Identifier: Apache-2.0
# Live completed-line 005 source/recipient gates and CHANMODES certainty.
# Feed line bodies without CRLF: the byte framer removes line delimiters.
# Iso.show omits cm_known; its checks cover rendered metadata only.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/isupport.bend as Iso

def state_of(prepped: Iso.State & String) -> Iso.State:
  match prepped:
    case (+st, _): st

def prepared(+line: String) -> Iso.State:
  state_of(Sess.live_step.prep(Iso.defaults(), Cl.init("me", "a.example"), line))

def burst(+source: String, +recipient: String) -> String:
  ":" ++ source ++ " 005 " ++ recipient ++ " CASEMAPPING=ascii CHANTYPES=#&+!$ :are supported"

def withdrawal(+source: String, +recipient: String) -> String:
  ":" ++ source ++ " 005 " ++ recipient ++ " -CHANMODES :are supported"

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("unrelated bare source leaves live 005 defaults", Iso.show(prepared(burst("irc", "me"))), Iso.show(Iso.defaults()))
    Unit <- E.must_eq("configured source applies ascii without 001", Iso.casemapping(prepared(burst("a.example", "me"))), "ascii")
    Unit <- E.must_eq("configured source applies dollar chantype", Iso.chantypes(prepared(burst("a.example", "me"))), "#&+!$")
    Unit <- E.must_eq("wrong recipient leaves live 005 defaults", Iso.show(prepared(burst("a.example", "other"))), Iso.show(Iso.defaults()))
    Unit <- E.must("configured source withdraws CHANMODES certainty", Bool.not(Iso.cm_known(prepared(withdrawal("a.example", "me")))))
    Unit <- E.must("unrelated bare source preserves CHANMODES certainty", Iso.cm_known(prepared(withdrawal("irc", "me"))))
    Unit <- E.must("wrong recipient preserves CHANMODES certainty", Iso.cm_known(prepared(withdrawal("a.example", "other"))))
    IO.print("workspace_005_source=ok")
