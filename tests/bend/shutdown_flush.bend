# SPDX-License-Identifier: Apache-2.0
# Actual Net.shutdown with a real reader and a deliberately deferred writer.
# The delay controls task scheduling; it does not fabricate an EOF event.
import Base
import ../../src/bend/actor.bend as Act
import ../../src/bend/transport.bend as Tr
import ../../src/bend/outbound.bend as Out
import ../../src/bend/session.bend as Sess
import ../../src/bend/dns.bend as Dns
import ../../src/bend/net.bend as Net
import ../../src/bend/timui.bend as T
import ../../src/bend/app.bend as App

def reader(dup: Socket, +evt: Chan(Sess.UiMsg), +done: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Act.reader_run(Tr.Plain{dup}, evt, 1)
    _ : Bool <- Chan.send(Unit, done, Unit{})
    return Unit{}

def writer(st: Act.Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Act.Boot), +gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    _ : Maybe<&1, Unit> <- Chan.recv(Unit, gate)
    Act.writer_go(st, evt, cmd, boot, False{})

def release(+gate: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(250)
    _ : Bool <- Chan.send(Unit, gate, Unit{})
    return Unit{}

def await_reader(half_close: Bool, +done: Chan(Unit)) -> IO(Unit):
  match half_close:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        _ : Maybe<&1, Unit> <- Chan.recv(Unit, done)
        return Unit{}

def run(sock: Socket, dup: Socket, +half_close: Bool) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +ack : Chan(Unit) <- Chan.new(Unit, 1)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    +done : Chan(Unit) <- Chan.new(Unit, 1)
    +gate : Chan(Unit) <- Chan.new(Unit, 1)
    # A stale acknowledgement must not release either shutdown case.
    _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.FromNet{0, Sess.WriterDone{}})
    Unit <- IO.spawn(Unit, reader(dup, evt, done))
    Unit <- IO.spawn(Unit, writer(Act.Writer{Some{Tr.Plain{sock}}, 1, "NOTICE #t :pending" <> "QUIT :shutdown-test" <> Nil{}, Out.budget_frames(1), False{}}, evt, cmd, boot, gate))
    Unit <- await_reader(half_close, done)
    Unit <- IO.spawn(Unit, release(gate))
    Net.shutdown(ui, cmd, ack, evt, 1, True{})

def idle(net: Sess.NetState, +gen: U32) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +ack : Chan(Unit) <- Chan.new(Unit, 1)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    +gate : Chan(Unit) <- Chan.new(Unit, 1)
    Unit <- IO.spawn(Unit, writer(Act.Writer{None{}, gen, Nil{}, Out.budget_frames(1), False{}}, evt, cmd, boot, gate))
    Unit <- IO.spawn(Unit, release(gate))
    Net.shutdown(ui, cmd, ack, evt, gen, Net.shutdown_waits(net))

def doubled(pair: Socket & Result<&1, &1, U32 & String, Socket>, half_close: Bool) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dup failed")
        case Done{dup}: run(sock, dup, half_close)

def connected(r: Result<&1, &1, U32 & String, Socket>, half_close: Bool) -> IO(Unit):
  match r:
    case Fail{_}: IO.die(Unit, 1, "connect failed")
    case Done{sock}:
      do IO<Unit>:
        pair : Socket & Result<&1, &1, U32 & String, Socket> <- Dns.Socket.dup(sock)
        doubled(pair, half_close)

def parsed(port: Maybe<&2, U32>, +mode: String) -> IO(Unit):
  match port:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{p}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("127.0.0.1", p, 1000)
        connected(r, String.eq(mode, "half_close"))

def dispatch(p: String, +mode: String, app: Bool) -> IO(Unit):
  match app:
    # Preserve all production FFI IDs; the local guard does not run this arm.
    case True{}: App.main()
    case False{}: parsed(U32.read(p), mode)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{_, Con{"demo", Nil{}}}}: idle(Sess.Demo{}, 0)
    case Con{_, Con{_, Con{"offline", Nil{}}}}: idle(Sess.Offline{}, 7)
    case Con{_, Con{p, Con{+mode, Nil{}}}}: dispatch(p, mode, String.eq(mode, "app"))
    case _: IO.die(Unit, 1, "expected port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
