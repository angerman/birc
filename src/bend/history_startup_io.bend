# SPDX-License-Identifier: Apache-2.0
# Startup reads own an auth-free client, never a captured mutable Session.
import Base
import ./buffer.bend as Cl
import ./history_io.bend as HistIO
import ./session.bend as Sess

def load.enabled(on: Bool, +path: String, +endpoint: String, +cap: U32, nick: String, host: String, now: String) -> IO(Cl.Client):
  match on:
    case False{}: IO.pure(Cl.Client, Cl.set_now(Cl.init_with_cap(nick, host, cap), now))
    case True{}: HistIO.history_snapshot_client(path, endpoint, cap, Cl.set_now(Cl.init_with_cap(nick, host, cap), now))

def load(+path: String, +endpoint: String, +cap: U32, +nick: String, +host: String, now: String) -> IO(Cl.Client):
  load.enabled(Bool.not(String.is_empty(path) || U32.is_zero(cap)), path, endpoint,
    U32.from_nat(Cl.clamp_nat(U32.to_nat(cap), Cl.SCROLL_CAP())), nick, host, now)

# The snapshot reader closes its owned descriptor before it returns. Only the
# completed bounded snapshot crosses this channel; ticket/gen/endpoint belong
# to the outer gate, which rejects stale policy or connection completions.
def run(ticket: Nat, gen: U32, path: String, +endpoint: String, cap: U32, nick: String, host: String, now: String, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    cl : Cl.Client <- load(path, endpoint, cap, nick, host, now)
    _ : Result<&1, &1, Sess.UiMsg, Unit> <- Chan.send(Sess.UiMsg, evt, Sess.HistoryLoaded{ticket, gen, endpoint, cl})
    return Unit{}

def start(ticket: Nat, gen: U32, path: String, endpoint: String, cap: U32, nick: String, host: String, now: String, evt: Chan(Sess.UiMsg)) -> IO(Unit):
  IO.spawn(Unit, run(ticket, gen, path, endpoint, cap, nick, host, now, evt))
