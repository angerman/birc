# SPDX-License-Identifier: Apache-2.0
import Base
import ../../src/bend/history_io.bend as H
import ../../src/bend/buffer.bend as Cl

def report(result: Maybe<&2, String>) -> IO(Unit):
  match result:
    case None{}: IO.print("save=ok")
    case Some{text}: IO.print("save=error:" ++ text)

def run(+path: String, mode: String) -> IO(Unit):
  match mode:
    case "empty":
      do IO<Unit>:
        result : Maybe<&2, String> <- H.history_append_file(path, "")
        report(result)
    case "disabled":
      do IO<Unit>:
        result : Maybe<&2, String> <- H.maybe_save_history.check(False{}, path, "s:6667", Cl.init("me", "s"), Cl.init("me", "s"))
        report(result)
    case _:
      do IO<Unit>:
        result : Maybe<&2, String> <- H.history_append_file(path, "fixture\n")
        report(result)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Con{mode, Nil{}}}}: run(path, mode)
    case _: IO.die(Unit, 1, "expected path mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
