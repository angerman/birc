# An initial failure must not kill the actor with a newer Dial queued.
import Base
import ./expect.bend as E
import ../../src/bend/actor.bend as Act
import ../../src/bend/session.bend as Sess

def boot_expected(g: Maybe<&1, Act.Boot>, +failed: Bool) -> Bool:
  match g:
    case Some{Act.Down{_}}: failed
    case Some{Act.Ready{}}: Bool.not(failed)
    case _: False{}

def arrived(g: Maybe<&1, Sess.UiMsg>, +up: Bool) -> Bool:
  match g:
    case Some{Sess.FromNet{2, Sess.Up{}}}: up
    case Some{Sess.FromNet{2, Sess.Eof{}}}: Bool.not(up)
    case _: False{}

def await_event.next(done: Bool, rest: IO(Unit)) -> IO(Unit):
  match done:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: rest

def await_event(fuel: Nat, +evt: Chan(Sess.UiMsg), +up: Bool) -> IO(Unit):
  match fuel:
    case 0n: IO.die(Unit, 1, "event limit")
    case 1n+p:
      do IO<Unit>:
        g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
        await_event.next(arrived(g, up), await_event(p, evt, up))

def run(a: U32, b: U32, +failed: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("same initial failure", Sess.event_current(Sess.FromNet{1, Sess.InitialFail{"initial"}}, 1))
    Unit <- E.must("stale initial failure", Bool.not(Sess.event_current(Sess.FromNet{1, Sess.InitialFail{"initial"}}, 2)))
    Unit <- E.must("fresh up", Sess.event_current(Sess.FromNet{2, Sess.Up{}}, 2))
    Unit <- E.must("stale eof", Bool.not(Sess.event_current(Sess.FromNet{1, Sess.Eof{}}, 2)))
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    Unit <- IO.spawn(Unit, Act.actor_boot("127.0.0.1", a, "probe", 1, evt, cmd, boot, False{}, 0))
    _ : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", b, 2, "next"})
    first : Maybe<&1, Act.Boot> <- Chan.recv(Act.Boot, boot)
    Unit <- E.must("initial outcome", boot_expected(first, failed))
    Unit <- Chan.close(Act.Boot, boot)
    Unit <- await_event(16n, evt, True{})
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- await_event(16n, evt, False{})
    Unit <- IO.print("startup_actor=ok")
    IO.die(Unit, 0, "")

def parsed(a: Maybe<&2, U32>, b: Maybe<&2, U32>, +mode: String) -> IO(Unit):
  match a:
    case Some{a}:
      match b:
        case Some{b}: run(a, b, String.eq(mode, "failed"))
        case _: IO.die(Unit, 1, "invalid second port")
    case _: IO.die(Unit, 1, "invalid first port")

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{a, Con{b, Con{+mode, Nil{}}}}}: parsed(U32.read(a), U32.read(b), mode)
    case _: IO.die(Unit, 1, "expected first-port second-port mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
