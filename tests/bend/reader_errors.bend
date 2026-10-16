# The real reader branch must distinguish a read failure from orderly EOF.
import Base
import ./expect.bend as E
import ../../src/bend/actor.bend as A
import ../../src/bend/outbound.bend as Out
import ../../src/bend/session.bend as S
import ../../src/bend/transport.bend as Tr

def checked(message: Maybe<&1, S.UiMsg>, failed: Bool) -> IO(Unit):
  match message:
    case Some{S.FromNet{7, S.NetFail{msg}}}:
      do IO<Unit>:
        Unit <- E.must("read error retains safe numeric diagnostic", failed && String.eq(msg, "receive failed (OS 5)"))
        return Unit{}
    case Some{S.FromNet{7, S.Eof{}}}:
      E.must("orderly EOF is not a read failure", Bool.not(failed))
    case _:
      IO.die(Unit, 1, "missing or wrong reader event")

def entered(dup: Tr.Conn, fr: A.ReadFr, +msg: String) -> IO(Unit):
  match fr:
    case A.ReadFr{_, _, _}:
      do IO<Unit>:
        Unit <- Tr.close(dup)
        IO.die(Unit, 1, msg)

def close_conn(dup: Tr.Conn, fr: A.ReadFr) -> IO(Unit):
  match fr:
    case A.ReadFr{_, _, _}:
      Tr.close(dup)

def frame() -> A.ReadFr:
  A.ReadFr{False{}, Nil{}, Out.pong_first(7)}

def event(sock: Tr.Conn, +evt: Chan(S.UiMsg), +cmd: Chan(S.NetCmd), failed: Bool) -> IO(Unit):
  match failed:
    case True{}:
      A.reader_r(sock, evt, 7, Fail{(5, "private https://unused.invalid/secret")}, cmd, frame(),
        dup => fr => entered(dup, fr, "failed read entered continuation"))
    case False{}:
      A.reader_xs(sock, evt, 7, Nil{}, cmd, frame(),
        dup => fr => entered(dup, fr, "EOF entered continuation"))

def run(+failed: Bool) -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind("127.0.0.1", 0))
    +evt : Chan(S.UiMsg) <- Chan.new(S.UiMsg, 1)
    +cmd : Chan(S.NetCmd) <- Chan.new(S.NetCmd, 1)
    Unit <- event(Tr.Plain{socket}, evt, cmd, failed)
    message : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
    Unit <- Chan.close(S.UiMsg, evt)
    Unit <- Chan.close(S.NetCmd, cmd)
    checked(message, failed)

def checked_empty(message: Maybe<&1, S.UiMsg>) -> IO(Unit):
  match message:
    case None{}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "no-data read reported failure or EOF")

def no_data() -> IO(Unit):
  do IO<Unit>:
    socket : Socket <- IO.try(Socket, UDP.bind("127.0.0.1", 0))
    +evt : Chan(S.UiMsg) <- Chan.new(S.UiMsg, 1)
    +cmd : Chan(S.NetCmd) <- Chan.new(S.NetCmd, 1)
    Unit <- A.reader_r(Tr.Plain{socket}, evt, 7, Done{None{}}, cmd, frame(), dup => fr => close_conn(dup, fr))
    Unit <- Chan.close(S.UiMsg, evt)
    Unit <- Chan.close(S.NetCmd, cmd)
    message : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
    checked_empty(message)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- run(False{})
    Unit <- no_data()
    Unit <- run(True{})
    IO.print("reader_errors=ok")
