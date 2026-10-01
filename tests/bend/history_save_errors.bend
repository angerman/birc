# Save errors return one bounded diagnostic after closing the descriptor.
import Base
import ../../src/bend/history.bend as H
import ../../src/bend/buffer.bend as Cl

def report(result: Maybe<&2, String>) -> IO(Unit):
  match result:
    case None{}: IO.print("save=ok")
    case Some{text}: IO.print("save=error:" ++ text)

def injected.open(result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "fixture open failed")
    case Done{f}:
      do IO<Unit>:
        result : Maybe<&2, String> <- H.history_append_file.done((f, Fail{(5, "private https://unused.invalid/secret?token=hidden")}))
        report(result)

def run(+path: String, mode: String) -> IO(Unit):
  match mode:
    case "inject":
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
        injected.open(result)
    case "disabled":
      do IO<Unit>:
        result : Maybe<&2, String> <- H.maybe_save_history.check(False{}, path, "s:6667", Cl.init("me", "s"), Cl.init("me", "s"))
        report(result)
    case "empty":
      do IO<Unit>:
        result : Maybe<&2, String> <- H.history_append_file(path, "")
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
