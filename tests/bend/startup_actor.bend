# An initial failure must not kill the actor with a newer Dial queued.
# (-) Down / absent reject headless may_await; setup cancel posts Down.
# (+) Booted may_await; successful initial boot still posts Booted.
# Booted is posted only after adopt + writer_kept (kept Cont/Pong before
# headless frames); see actor_queue bootlskept kept-before-Booted gate.
import Base
import ./expect.bend as E
import ../../src/bend/actor.bend as Act
import ../../src/bend/session.bend as Sess

def boot_expected(g: Maybe<&1, Act.Boot>, +failed: Bool) -> Bool:
  match g:
    case Some{Act.Down{_}}: failed
    case Some{Act.Booted{}}: Bool.not(failed)
    case _: False{}

def boot_cancel_expected(g: Maybe<&1, Act.Boot>, +dropped: Bool) -> Bool:
  match g:
    case Some{Act.Down{_}}: dropped
    case Some{Act.Booted{}}: Bool.not(dropped)
    case _: False{}

def may_await(g: Maybe<&1, Act.Boot>) -> Bool:
  match g:
    case Some{Act.Booted{}}: True{}
    case _: False{}

def is_up(g: Maybe<&1, Sess.UiMsg>) -> Bool:
  match g:
    case Some{Sess.FromNet{_, Sess.Up{}}}: True{}
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

def headless_gate() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("Down rejects provisional await", Bool.not(may_await(Some{Act.Down{"x"}})))
    Unit <- E.must("absent rejects provisional await", Bool.not(may_await(None{})))
    Unit <- E.must("cancel outcome is Down", boot_cancel_expected(Some{Act.Down{"connect cancelled"}}, True{}))
    Unit <- E.must("Booted is not a cancel outcome", Bool.not(boot_cancel_expected(Some{Act.Booted{}}, True{})))
    Unit <- E.must("Booted may await", may_await(Some{Act.Booted{}}))
    Unit <- E.must("ready outcome is Booted", boot_cancel_expected(Some{Act.Booted{}}, False{}))
    Unit <- E.must("Up event is registration success", is_up(Some{Sess.FromNet{1, Sess.Up{}}}))
    Unit <- E.must("Eof is not Up", Bool.not(is_up(Some{Sess.FromNet{1, Sess.Eof{}}})))
    return Unit{}

# Await initial boot before Dial B so setup-cancel Down cannot race registration.
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
    first : Maybe<&1, Act.Boot> <- Chan.recv(Act.Boot, boot)
    Unit <- E.must("initial outcome", boot_expected(first, failed))
    Unit <- Chan.close(Act.Boot, boot)
    _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", b, 2, "next"})
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
    Unit <- headless_gate()
    xs : List<&1, String> <- IO.args()
    args(xs)
