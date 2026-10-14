# SPDX-License-Identifier: Apache-2.0
# Actual Process.run helper seam; Python supplies only private fixture paths.
import Base
import ../../src/bend/preferences.bend as P
import ../../src/bend/preferences_io.bend as F

def fixture() -> String:
  "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\nmute\talice*#room@irc.example\nchannel\t+#room\nchannel\t#日本語\n"

def loaded(pair: Maybe<&2, P.Preferences> & U32) -> IO(Unit):
  match pair:
    case (None{}, code): IO.print(U32.show(code) ++ ":absent\n")
    case (Some{prefs}, code): IO.print(U32.show(code) ++ ":" ++ P.show(prefs))

def write.parsed(got: Maybe<&2, P.Preferences>) -> IO(Unit):
  match got:
    case None{}: IO.die(Unit, 1, "invalid fixture")
    case Some{prefs}:
      do IO<Unit>:
        code : U32 <- F.save("irc.example", 6697, prefs)
        IO.print(U32.show(code) ++ "\n")

def mode(name: String) -> IO(Unit):
  match name:
    case "write": write.parsed(P.parse(fixture()))
    case _:
      do IO<Unit>:
        result : Maybe<&2, P.Preferences> & U32 <- F.load("irc.example", 6697)
        loaded(result)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{name, Nil{}}}: mode(name)
    case _: IO.die(Unit, 1, "expected read or write")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
