# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/preferences_io.bend as P
import ../../src/bend/preferences.bend as Pref

def load_shown(pair: Maybe<&2, Pref.Preferences> & U32) -> String:
  match pair:
    case (None{}, code): U32.show(code) ++ ":absent"
    case (Some{_}, code): U32.show(code) ++ ":present"

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("unset preferences helper uses literal executable", P.program.env(Fail{(2, "private error")}), "birc-preferences")
    Unit <- E.must_eq("empty preferences helper uses literal executable", P.program.env(Done{""}), "birc-preferences")
    Unit <- E.must_eq("helper path is literal", P.program.env(Done{"/owned/helper path"}), "/owned/helper path")
    Unit <- E.must_eq("missing optional snapshot is success", load_shown(P.load_result(Done{(0, ("", "private stderr"))})), "0:absent")
    Unit <- E.must_eq("malformed helper stdout is rejected", load_shown(P.load_result(Done{(0, ("private malformed stdout", "private stderr"))})), "2:absent")
    Unit <- E.must_eq("helper failure drops stdout and stderr", load_shown(P.load_result(Done{(7, ("private stdout", "private stderr"))})), "7:absent")
    Unit <- E.must_eq("OS failure drops private diagnostic", load_shown(P.load_result(Fail{(5, "private OS error")})), "5:absent")
    Unit <- E.must_eq("zero OS error still fails", load_shown(P.load_result(Fail{(0, "private OS error")})), "1:absent")
    Unit <- E.must("write success has no diagnostic", U32.is_zero(P.save_result(Done{(0, ("", ""))})))
    Unit <- E.must("write unexpected output fails", U32.is_eq(P.save_result(Done{(0, ("private output", ""))}), 2))
    IO.print("preferences_io_demo=ok\n")
