# SPDX-License-Identifier: Apache-2.0
# The production deferred actor uses these exact pure admission transitions.
import Base
import ./expect.bend as E
import ../../src/bend/actor.bend as A
import ../../src/bend/session.bend as S

def initial() -> A.Deferred:
  A.deferred_initial("irc.example", 6697, "me", True{})

def waiting(step: A.DeferredStep) -> A.Deferred:
  match step:
    case A.Waiting{st}: st
    case _: A.Deferred{None{}, 0, A.AuthScope{"", 0, False{}}}

def started(step: A.DeferredStep, +host: String, +gen: U32, +sasl: Bool, +boot: Bool) -> Bool:
  match step:
    case A.Starting{A.PendingDial{+actual, 6697, +nick}, got, +scope, +first}:
      String.eq(actual, host) && String.eq(nick, "me") && U32.is_eq(got, gen)
        && Bool.not(A.auth_scope_enabled(scope) && Bool.not(sasl))
        && Bool.not(sasl && Bool.not(A.auth_scope_enabled(scope)))
        && Bool.not(first && Bool.not(boot)) && Bool.not(boot && Bool.not(first))
    case _: False{}

def positive() -> Bool:
  +ignored = waiting(A.deferred_command(S.Cont{"PRIVMSG peer :never send" <> Nil{}}, initial()))
  started(A.deferred_command(S.Begin{1}, ignored), "irc.example", 1, True{}, True{})
    && started(A.deferred_command(S.Begin{2}, waiting(A.deferred_command(S.Dial{"irc.example", 6697, 2, "me"}, initial()))), "irc.example", 2, True{}, False{})

def no_begin(step: A.DeferredStep) -> Bool:
  match step:
    case A.Waiting{_}: True{}
    case _: False{}

def released(step: A.DeferredStep) -> Bool:
  match step:
    case A.Released{1, scope}: A.auth_scope_enabled(A.auth_scope_dial(scope, "irc.example", 6697))
    case _: False{}

def negative() -> Bool:
  +other = waiting(A.deferred_command(S.Dial{"other.example", 6697, 2, "me"}, initial()))
  +back = waiting(A.deferred_command(S.Dial{"irc.example", 6697, 3, "me"}, other))
  +dropped = waiting(A.deferred_command(S.Drop{}, initial()))
  no_begin(A.deferred_command(S.Begin{0}, initial()))
    && no_begin(A.deferred_command(S.Begin{1}, other))
    && started(A.deferred_command(S.Begin{3}, back), "irc.example", 3, False{}, False{})
    && no_begin(A.deferred_command(S.Begin{0}, dropped))
    && released(A.deferred_command(S.Begin{1}, dropped))

def acknowledgement(got: Maybe<&1, S.UiMsg>, +gen: U32, +done: Bool) -> Bool:
  match got:
    case Some{S.FromNet{got, S.Eof{}}}: U32.is_eq(got, gen) && Bool.not(done)
    case Some{S.FromNet{got, S.WriterDone{}}}: U32.is_eq(got, gen) && done
    case _: False{}

def closed(+evt: Chan(S.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    first : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
    Unit <- E.must("held/canceled actor closes without dialing", acknowledgement(first, gen, False{}))
    second : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
    Unit <- E.must("held/canceled actor acknowledges current generation", acknowledgement(second, gen, True{}))
    IO.pure(Unit, Unit{})

def cancel_commands(cancel: Bool, +cmd: Chan(S.NetCmd)) -> IO(Unit):
  match cancel:
    case False{}: Chan.close(S.NetCmd, cmd)
    case True{}:
      do IO<Unit>:
        _ : Result<&1, &1, S.NetCmd, Unit> <- Chan.send(S.NetCmd, cmd, S.Cont{"PRIVMSG peer :must never send" <> Nil{}})
        _ : Result<&1, &1, S.NetCmd, Unit> <- Chan.send(S.NetCmd, cmd, S.Dial{"127.0.0.1", 0, 2, "me"})
        _ : Result<&1, &1, S.NetCmd, Unit> <- Chan.send(S.NetCmd, cmd, S.Begin{1})
        _ : Result<&1, &1, S.NetCmd, Unit> <- Chan.send(S.NetCmd, cmd, S.Drop{})
        _ : Result<&1, &1, S.NetCmd, Unit> <- Chan.send(S.NetCmd, cmd, S.Begin{2})
        Chan.close(S.NetCmd, cmd)

def cancellation(+cancel: Bool) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(S.UiMsg) <- Chan.new(S.UiMsg, 8)
    +cmd : Chan(S.NetCmd) <- Chan.new(S.NetCmd, 8)
    +boot : Chan(A.Boot) <- Chan.new(A.Boot, 1)
    # Port zero cannot name a service. No connect is allowed on either path.
    Unit <- IO.spawn(Unit, A.deferred_start_tls("127.0.0.1", 0, "me", evt, cmd, boot, True{}, 0, False{}))
    Unit <- cancel_commands(cancel, cmd)
    Unit <- closed(evt, Bool.pick(U32, cancel, 2, 1))
    Unit <- Chan.close(S.UiMsg, evt)
    Chan.close(A.Boot, boot)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("only matching Begin starts the current endpoint with retained SASL and correct Boot policy", positive())
    Unit <- E.must("stale Begin cannot start; endpoint scope never revives; canceled Begin releases idle writer", negative())
    Unit <- cancellation(False{})
    Unit <- cancellation(True{})
    IO.print("deferred_actor=ok")
