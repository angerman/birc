# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/upload_io.bend as U

def shown(pair: String & U32) -> String:
  match pair:
    case (out, code): U32.show(code) ++ ":" ++ out

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("unset helper uses native effect", U.program.env(Fail{(2, "private error")}), "native")
    Unit <- E.must_eq("empty helper uses native effect", U.program.env(Done{""}), "native")
    Unit <- E.must_eq("helper override is one literal executable", U.program.env(Done{"/owned/helper path"}), "/owned/helper path")
    Unit <- E.must_eq("success preserves exact stdout only", shown(U.result(Done{(0, ("https://0x0.st/a.jpg\n", "private stderr"))})), "0:https://0x0.st/a.jpg\n")
    Unit <- E.must_eq("failure drops stdout and stderr", shown(U.result(Done{(7, ("private stdout", "private stderr"))})), "7:")
    Unit <- E.must_eq("OS failure drops private text", shown(U.result(Fail{(5, "private error")})), "5:")
    Unit <- E.must_eq("zero OS error cannot look successful", shown(U.result(Fail{(0, "private error")})), "1:")
    IO.print("upload_io_demo=ok\n")
