# SPDX-License-Identifier: Apache-2.0
# Characterize the preexisting startup ordering; this is not the desired fix.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as H
import ../../src/bend/preferences.bend as P
import ../../src/bend/theme.bend as Theme

def restored() -> Cl.Client:
  H.apply_history(Cl.init("me", "irc.example"), H.parse_history_text("#t\tMSG\t\tone\n#t\tMSG\t\ttwo\n#t\tMSG\t\tthree\n"), "", 100)

def prefs(history: Bool, cap: U32) -> P.Preferences:
  P.Preferences{True{}, True{}, True{}, history, cap, False{}, True{}, True{}, Nil{}, Nil{}, True{}, Theme.Dark{}, True{}}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("late history off does not remove already restored rows", CL.buf_texts(P.apply(restored(), prefs(False{}, 1)), 1n), CL.buf_texts(restored(), 1n))
    Unit <- E.must_eq("late smaller cap does not trim already restored rows", CL.buf_texts(P.apply(restored(), prefs(True{}, 1)), 1n), CL.buf_texts(restored(), 1n))
    Unit <- E.must("history restored rows exist in this characterization", Bool.not(String.is_empty(CL.buf_texts(restored(), 1n))))
    IO.print("preferences_history_characterization=ok\n")
