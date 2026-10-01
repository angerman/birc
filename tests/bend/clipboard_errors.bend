import Base
import ../../src/bend/timui.bend as T

def report(result: Maybe<&2, String>) -> IO(Unit):
  match result:
    case None{}: IO.print("clipboard=ok")
    case Some{text}: IO.print("clipboard=error:" ++ text)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{program, Nil{}}}:
      do IO<Unit>:
        result : Maybe<&2, String> <- T.Sys.copy_clipboard.program(program, "pasted-secret https://unused.invalid/private")
        report(result)
    case _: IO.die(Unit, 1, "expected clipboard program")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
