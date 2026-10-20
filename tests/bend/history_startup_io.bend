# SPDX-License-Identifier: Apache-2.0
# Invoked only with the driver's owned synthetic history file.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history_startup.bend as H
import ../../src/bend/history_startup_io.bend as F
import ../../src/bend/session.bend as S

def auth_free(cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{_, _, _, _, _, +settings, Cl.AuthIdle{}, _, _}:
      String.is_empty(Cl.settings_sasl_user(settings)) && String.is_empty(Cl.settings_sasl_pass(settings))
    case _: False{}

def completed(got: Maybe<&1, S.UiMsg>) -> IO(Unit):
  match got:
    case Some{S.HistoryLoaded{7n, 3, "irc.example:6667", +snapshot}}:
      +current = Cl.client_log(Cl.init_with_cap("me", "irc.example", 1), 0n, Cl.System{}, "startup status")
      +loaded = H.install(current, snapshot)
      do IO<Unit>:
        Unit <- E.must("worker snapshot never carries credentials", auth_free(snapshot))
        Unit <- E.must_eq("owned snapshot selects latest row and endpoint", CL.buf_texts(loaded, 1n), "two|")
        Unit <- E.must_eq("worker import preserves current local status", CL.buf_texts(loaded, 0n), "startup status|")
        IO.print("history_startup_io=ok")
    case _: IO.die(Unit, 1, "wrong startup completion identity")

def run(+path: String) -> IO(Unit):
  do IO<Unit>:
    +zero : Cl.Client <- F.load(path, "irc.example:6667", 0, "archive", "irc.example", "12:00:00")
    Unit <- E.must("zero cap skips archive and remains auth-free", auth_free(zero) && Nat.is_eq(Cl.log_seq_of(zero), 0n))
    +evt : Chan(S.UiMsg) <- Chan.new(S.UiMsg, 1)
    Unit <- F.start(7n, 3, path, "irc.example:6667", 1, "archive", "irc.example", "12:00:00", evt)
    got : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
    Unit <- Chan.close(S.UiMsg, evt)
    completed(got)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Nil{}}}: run(path)
    case _: IO.die(Unit, 1, "expected synthetic history path")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
