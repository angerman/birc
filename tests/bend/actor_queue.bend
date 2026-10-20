# Local socket driver: inspect the finite budget before closing the command
# channel, then check that close flushes every remaining line exactly once.
import Base
import ../../src/bend/actor.bend as Act
import ../../src/bend/transport.bend as Tr
import ../../src/bend/outbound.bend as Out
import ../../src/bend/session.bend as Sess
import ../../src/bend/dns.bend as Dns

def lines(+n: Nat) -> List<&2, String>:
  match n:
    case 0n: Nil{}
    case 1n+p: ("NOTICE #t :" ++ Nat.show(n)) <> lines(p)

def queue_drop(drop: Bool, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  match drop:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Drop{})
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Cont{"NOTICE #t :offline" <> Nil{}})
        return Unit{}

def queue_redial(redial: Bool, port: U32, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  match redial:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", port, 2, "probe"})
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Cont{"NOTICE #t :fresh" <> Nil{}})
        return Unit{}

def wait_event(g: Maybe<&1, Sess.UiMsg>, k: Unit -> IO(Unit)) -> IO(Unit):
  match g:
    case Some{Sess.FromNet{_, Sess.Eof{}}}: IO.pure(Unit, Unit{})
    case _: k(Unit{})

@unsafe
def wait_eof(+evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    wait_event(g, _ => wait_eof(evt))

# Held-setup Drop (−): peer saturates the TCP backlog so Dial's connect parks;
# queue Drop, signal "held", then the peer frees the slot. Registration must
# send zero bytes. Sibling dialsetup (+): same hold, no Drop, CAP/NICK/USER.
# droptls (−): same hold with the TLS writer. The peer must see zero bytes,
# including no ClientHello.
def setup_drop(drop: Bool, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  match drop:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Drop{})
        return Unit{}

def setup_spawn(tls: Bool, st: Act.Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Act.Boot)) -> IO(Unit):
  match tls:
    case False{}: IO.spawn(Unit, Act.writer_go(st, evt, cmd, boot, False{}))
    case True{}: IO.spawn(Unit, Act.writer_go_tls(st, evt, cmd, boot, False{}))

def run_setup(+port: U32, +drop: Bool, +tls: Bool) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    Unit <- setup_spawn(tls, Act.Writer{None{}, 0, Nil{}, Nil{}, 1, Out.budget_frames(1), False{}}, evt, cmd, boot)
    _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", port, 1, "probe"})
    # Let Dial enter Dns.dial_dual before Drop races the accept release.
    Unit <- IO.sleep(100)
    Unit <- setup_drop(drop, cmd)
    Unit <- IO.print("held")
    Unit <- IO.sleep(500)
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- wait_eof(evt)
    IO.print("closed")

def run_socket(sock: Socket, +port: U32, +frames: U32, +count: Nat, +mode: String) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    Unit <- IO.spawn(Unit, Act.writer_go(Act.Writer{Some{Tr.Plain{sock}}, 1, Nil{}, Nil{}, 1, Out.budget_frames(frames), False{}}, evt, cmd, boot, False{}))
    _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Cont{lines(count)})
    # A second producer command fills the capacity-one queue while an
    # internal Pump is scheduled. Awaiting a self-send would deadlock here.
    _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Cont{"QUIT :queue-test" <> Nil{}})
    _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Pump{0})
    Unit <- queue_drop(String.eq(mode, "drop"), cmd)
    Unit <- queue_redial(String.eq(mode, "redial"), port, cmd)
    Unit <- IO.sleep(350)
    Unit <- IO.print("held")
    Unit <- IO.sleep(350)
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- wait_eof(evt)
    IO.print("closed")

def connected(r: Result<&1, &1, U32 & String, Socket>, port: U32, frames: U32, count: Nat, mode: String) -> IO(Unit):
  match r:
    case Fail{_}: IO.die(Unit, 1, "connect failed")
    case Done{sock}: run_socket(sock, port, frames, count, mode)

def parsed(p: Maybe<&2, U32>, f: Maybe<&2, U32>, n: Maybe<&2, U32>, +mode: String) -> IO(Unit):
  match p:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{+port}:
      match f:
        case None{}: IO.die(Unit, 1, "invalid frames")
        case Some{frames}:
          match n:
            case None{}: IO.die(Unit, 1, "invalid count")
            case Some{count}:
              do IO<Unit>:
                r : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("127.0.0.1", port, 1000)
                connected(r, port, frames, U32.to_nat(count), mode)

def boot_spawn(tls: Bool, +port: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Act.Boot)) -> IO(Unit):
  match tls:
    case False{}: IO.spawn(Unit, Act.actor_boot("127.0.0.1", port, "probe", 1, evt, cmd, boot, False{}, 0))
    case True{}: IO.spawn(Unit, Act.actor_boot_tls("127.0.0.1", port, "probe", 1, evt, cmd, boot, False{}, 0, True{}))

def run_close_spawn(first: Bool, tls: Bool, +port: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Act.Boot)) -> IO(Unit):
  match first:
    case True{}: boot_spawn(tls, port, evt, cmd, boot)
    case False{}:
      do IO<Unit>:
        Unit <- setup_spawn(tls, Act.Writer{None{}, 0, Nil{}, Nil{}, 1, Out.budget_frames(1), False{}}, evt, cmd, boot)
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", port, 1, "probe"})
        return Unit{}

def run_close(+port: U32, +first: Bool, +tls: Bool) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    Unit <- run_close_spawn(first, tls, port, evt, cmd, boot)
    Unit <- IO.sleep(100)
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- IO.print("held")
    Unit <- IO.sleep(500)
    Unit <- wait_eof(evt)
    IO.print("closed")

def run_boot(+port: U32, +drop: Bool, +tls: Bool) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    Unit <- boot_spawn(tls, port, evt, cmd, boot)
    Unit <- IO.sleep(100)
    Unit <- setup_drop(drop, cmd)
    Unit <- IO.print("held")
    Unit <- IO.sleep(500)
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- wait_eof(evt)
    IO.print("closed")

def after_finished(ready: Act.DialReady, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  match ready:
    case Act.DialReady{(sock, _, _), _}:
      do IO<Unit>:
        Unit <- Act.close_socket(sock)
        Unit <- Chan.close(Sess.NetCmd, cmd)
        Unit <- IO.print("held")
        IO.print("closed")

def after_queue(+mode: String, +target: U32, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  match mode:
    case "bootlsdrop":
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Drop{})
        return Unit{}
    case "bootlsclose": Chan.close(Sess.NetCmd, cmd)
    case "bootlskept":
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Cont{"PING :queued" <> Nil{}})
        return Unit{}
    case "afterdialdrop":
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", target, 2, "probe"})
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Drop{})
        return Unit{}
    case "afterdialclose":
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", target, 2, "probe"})
        Chan.close(Sess.NetCmd, cmd)
    case _: IO.pure(Unit, Unit{})

def run_after(sock: Socket, +target: U32, +mode: String) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 4)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    Unit <- after_queue(mode, target, cmd)
    Act.after_conn(Done{Tr.Plain{sock}}, "probe", 1, evt, boot, cmd, False{},
      Act.AuthScope{"127.0.0.1", 0, False{}},
      Act.AdmitAcc{None{}, Nil{}, Nil{}, False{}, False{}},
      pair => after_finished(pair, cmd),
      h2 => p2 => g2 => n2 => scope2 => carry2 => k2 =>
        Act.dial_begin.go(8n, h2, p2, False{}, n2, g2, evt, boot, cmd, False{}, scope2, carry2, k2))

def writer_after_queue(+mode: String, +target: U32, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  match mode:
    case "writerdialclose":
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", target, 2, "probe"})
        Chan.close(Sess.NetCmd, cmd)
    case _:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", target, 2, "probe"})
        Unit <- setup_drop(String.eq(mode, "writerdialdrop"), cmd)
        return Unit{}

def writer_after_finished(pair: Act.Writer & Act.AuthScope, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  match pair:
    case (Act.Writer{sock, _, _, _, _, _, _}, _):
      do IO<Unit>:
        Unit <- Act.close_socket(sock)
        Unit <- Chan.close(Sess.NetCmd, cmd)
        Unit <- IO.print("held")
        IO.print("closed")

# Exercise writer_admit's recursive winner, independently of dial_begin:
# Dial B followed by Drop or cmd-close must cancel before dialing B at all.
def run_writer_after(sock: Socket, +target: U32, +mode: String) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 4)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    Unit <- writer_after_queue(mode, target, cmd)
    Act.writer_admit_conn(Done{Tr.Plain{sock}}, "probe", 1, False{}, evt, boot, cmd,
      Act.AuthScope{"127.0.0.1", 0, False{}}, Out.budget_frames(1), 1,
      Act.AdmitAcc{None{}, Nil{}, Nil{}, False{}, False{}},
      pair => writer_after_finished(pair, cmd),
      h2 => p2 => g2 => n2 => scope2 => kept2 => closed2 => dropped2 => k2 =>
        Act.writer_admit_begin(h2, p2, False{}, n2, g2, evt, boot, cmd, scope2,
          Out.budget_frames(1), 1, kept2, closed2, dropped2, k2))

def after_connected(r: Result<&1, &1, U32 & String, Socket>, target: U32, mode: String) -> IO(Unit):
  match r:
    case Fail{_}: IO.die(Unit, 1, "connect failed")
    case Done{sock}: run_after(sock, target, mode)

def writer_after_connected(r: Result<&1, &1, U32 & String, Socket>, target: U32, mode: String) -> IO(Unit):
  match r:
    case Fail{_}: IO.die(Unit, 1, "connect failed")
    case Done{sock}: run_writer_after(sock, target, mode)

def after_port(p: Maybe<&2, U32>, target: Maybe<&2, U32>, +mode: String) -> IO(Unit):
  match p:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{port}:
      match target:
        case None{}: IO.die(Unit, 1, "invalid target port")
        case Some{other}:
          do IO<Unit>:
            r : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("127.0.0.1", port, 1000)
            after_connected(r, other, mode)

def writer_after_port(p: Maybe<&2, U32>, target: Maybe<&2, U32>, +mode: String) -> IO(Unit):
  match p:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{port}:
      match target:
        case None{}: IO.die(Unit, 1, "invalid target port")
        case Some{other}:
          do IO<Unit>:
            r : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("127.0.0.1", port, 1000)
            writer_after_connected(r, other, mode)

def auth_target(same: Bool, port: U32, other: U32) -> U32:
  match same:
    case True{}: port
    case False{}: other

def run_auth_scope(+port: U32, +other: U32, +same: Bool) -> IO(Unit):
  do IO<Unit>:
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    +cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    Unit <- IO.spawn(Unit, Act.actor_boot("127.0.0.1", port, "probe", 1, evt, cmd, boot, True{}, 0))
    Unit <- IO.sleep(100)
    _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Dial{"127.0.0.1", auth_target(same, port, other), 2, "probe"})
    Unit <- IO.print("held")
    Unit <- IO.sleep(700)
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- wait_eof(evt)
    IO.print("closed")

def auth_port(p: Maybe<&2, U32>, other: Maybe<&2, U32>, same: Bool) -> IO(Unit):
  match p:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{port}:
      match other:
        case None{}: IO.die(Unit, 1, "invalid target port")
        case Some{target}: run_auth_scope(port, target, same)

def setup_port(p: Maybe<&2, U32>, drop: Bool, tls: Bool) -> IO(Unit):
  match p:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{port}: run_setup(port, drop, tls)

def boot_port(p: Maybe<&2, U32>, drop: Bool, tls: Bool) -> IO(Unit):
  match p:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{port}: run_boot(port, drop, tls)

def close_port(p: Maybe<&2, U32>, first: Bool, tls: Bool) -> IO(Unit):
  match p:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{port}: run_close(port, first, tls)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{p, Con{_, Con{_, Con{"dropsetup", Nil{}}}}}}:
      setup_port(U32.read(p), True{}, False{})
    case Con{_, Con{p, Con{_, Con{_, Con{"droptls", Nil{}}}}}}:
      setup_port(U32.read(p), True{}, True{})
    case Con{_, Con{p, Con{_, Con{_, Con{"dialsetup", Nil{}}}}}}:
      setup_port(U32.read(p), False{}, False{})
    case Con{_, Con{p, Con{_, Con{_, Con{"bootdrop", Nil{}}}}}}:
      boot_port(U32.read(p), True{}, False{})
    case Con{_, Con{p, Con{_, Con{_, Con{"bootdial", Nil{}}}}}}:
      boot_port(U32.read(p), False{}, False{})
    case Con{_, Con{p, Con{_, Con{_, Con{"bootls", Nil{}}}}}}:
      boot_port(U32.read(p), True{}, True{})
    case Con{_, Con{p, Con{_, Con{_, Con{"closesetup", Nil{}}}}}}:
      close_port(U32.read(p), False{}, False{})
    case Con{_, Con{p, Con{_, Con{_, Con{"closels", Nil{}}}}}}:
      close_port(U32.read(p), False{}, True{})
    case Con{_, Con{p, Con{_, Con{_, Con{"bootclose", Nil{}}}}}}:
      close_port(U32.read(p), True{}, False{})
    case Con{_, Con{p, Con{_, Con{n, Con{"bootlsdrop", Nil{}}}}}}:
      after_port(U32.read(p), U32.read(n), "bootlsdrop")
    case Con{_, Con{p, Con{_, Con{n, Con{"bootlsclose", Nil{}}}}}}:
      after_port(U32.read(p), U32.read(n), "bootlsclose")
    case Con{_, Con{p, Con{_, Con{n, Con{"bootlsregister", Nil{}}}}}}:
      after_port(U32.read(p), U32.read(n), "bootlsregister")
    case Con{_, Con{p, Con{_, Con{n, Con{"bootlskept", Nil{}}}}}}:
      after_port(U32.read(p), U32.read(n), "bootlskept")
    case Con{_, Con{p, Con{_, Con{n, Con{"afterdialdrop", Nil{}}}}}}:
      after_port(U32.read(p), U32.read(n), "afterdialdrop")
    case Con{_, Con{p, Con{_, Con{n, Con{"afterdialclose", Nil{}}}}}}:
      after_port(U32.read(p), U32.read(n), "afterdialclose")
    case Con{_, Con{p, Con{_, Con{n, Con{"writerdialdrop", Nil{}}}}}}:
      writer_after_port(U32.read(p), U32.read(n), "writerdialdrop")
    case Con{_, Con{p, Con{_, Con{n, Con{"writerdialclose", Nil{}}}}}}:
      writer_after_port(U32.read(p), U32.read(n), "writerdialclose")
    case Con{_, Con{p, Con{_, Con{n, Con{"writerdialregister", Nil{}}}}}}:
      writer_after_port(U32.read(p), U32.read(n), "writerdialregister")
    case Con{_, Con{p, Con{_, Con{n, Con{"dialauthscope", Nil{}}}}}}:
      auth_port(U32.read(p), U32.read(n), False{})
    case Con{_, Con{p, Con{_, Con{n, Con{"dialauthsame", Nil{}}}}}}:
      auth_port(U32.read(p), U32.read(n), True{})
    case Con{_, Con{p, Con{f, Con{n, Con{+mode, Nil{}}}}}}: parsed(U32.read(p), U32.read(f), U32.read(n), mode)
    case _: IO.die(Unit, 1, "expected port frames count mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
