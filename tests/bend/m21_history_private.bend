# SPDX-License-Identifier: Apache-2.0
import Base
import ../../src/bend/history_io.bend as H
import ../../src/bend/buffer.bend as Cl

def report(result: Maybe<&2, String>) -> IO(Unit):
  match result:
    case None{}: IO.print("save=ok")
    case Some{text}: IO.print("save=error:" ++ text)

def report_append(got: H.Append) -> IO(Unit):
  match got:
    case H.Ok{}: IO.print("save=ok")
    case H.Skip{}: IO.print("save=skip")
    case H.Err{+msg}: IO.print("save=error:" ++ msg)

def run(+path: String, mode: String) -> IO(Unit):
  match mode:
    case "empty":
      do IO<Unit>:
        got : H.Append <- H.history_append_file.typed(path, "")
        report_append(got)
    case "disabled":
      do IO<Unit>:
        result : Maybe<&2, String> <- H.maybe_save_history.check(False{}, path, "s:6667", Cl.init("me", "s"), Cl.init("me", "s"))
        report(result)
    case _:
      do IO<Unit>:
        got : H.Append <- H.history_append_file.typed(path, "fixture\n")
        report_append(got)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Con{mode, Nil{}}}}: run(path, mode)
    case _: IO.die(Unit, 1, "expected path mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
