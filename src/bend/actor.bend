# Net actor: Socket ownership, reader/idle loops, dial, send_line.
# UI lives in net.bend. Actor never calls UI (no mutual recursion).
import Base
import ./irc.bend as Irc
import ./session.bend as Sess
import ./timui.bend as T
import ./dns.bend as Dns

def evt_wake(+ok: Bool) -> IO(Unit):
  match ok:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      T.wake_poke()

def poke_then(+ok: Bool, k: Bool -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- evt_wake(ok)
    k(ok)

def send_go_r(s: Socket, r: Result<&1, &1, (U32 & String), Unit>) -> Socket & Bool:
  match r:
    case Done{_}:
      (s, True{})
    case Fail{_}:
      (s, False{})

def send_go(m: Socket & Result<&1, &1, (U32 & String), Unit>) -> Socket & Bool:
  match m:
    case (s, r):
      send_go_r(s, r)

def send_line(sock: Socket, +line: String) -> IO(Socket & Bool):
  do IO<Socket & Bool>:
    m : Socket & Result<&1, &1, (U32 & String), Unit> <- TCP.send(sock, Irc.clamp_line(Irc.strip_ctl(line)) ++ "\r\n")
    IO.pure(Socket & Bool, send_go(m))

def send_lines_go(xs: List<&2, String>, pair: Socket & Bool) -> IO(Socket & Bool):
  match xs:
    case Nil{}:
      match pair:
        case (sock, ok):
          IO.pure(Socket & Bool, (sock, ok))
    case Con{+h, t}:
      match pair:
        case (sock, ok):
          match ok:
            case False{}:
              IO.pure(Socket & Bool, (sock, False{}))
            case True{}:
              do IO<Socket & Bool>:
                nxt : Socket & Bool <- send_line(sock, h)
                send_lines_go(t, nxt)

def send_lines(sock: Socket, +xs: List<&2, String>) -> IO(Socket & Bool):
  send_lines_go(xs, (sock, True{}))

# JOIN is sent after 001 (live_go), not here.
def register(sock: Socket, +nick: String) -> IO(Socket & Bool):
  send_lines(sock, Sess.register_lines(nick))

def reader_die(sock: Socket, +evt: Chan(Sess.NetEvt)) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Eof{})
    Unit <- evt_wake(ok)
    Socket.close(sock)
def after_offer(
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  ok: Bool,
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match ok:
    case False{}:
      reader_die(sock, evt)
    case True{}:
      k(sock)

def xs_nil(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def after_hit(
  sock: Socket,
  xs: List<&2, U32>,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  empty: Bool,
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match empty:
    case True{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Eof{})
        Unit <- evt_wake(ok)
        reader_die(sock, evt)
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Chunk{xs})
        poke_then(ok, o => after_offer(sock, evt, cmd, o, k))

def after_hit.xs(
  sock: Socket,
  +xs: List<&2, U32>,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Socket -> IO(Unit)
) -> IO(Unit):
  after_hit(sock, xs, evt, cmd, xs_nil(xs), k)

def after_poll(
  trip: Socket & List<&2, U32> & Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match trip:
    case (sock, xs, hit):
      match hit:
        case False{}:
          do IO<Unit>:
            ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Tick{})
            after_offer(sock, evt, cmd, ok, k)
        case True{}:
          after_hit.xs(sock, xs, evt, cmd, k)

def take_oct.peer(
  sock: Socket,
  peer: String & (U32 & List<&2, U32>),
  k: (Socket & List<&2, U32> & Bool) -> IO(Unit)
) -> IO(Unit):
  match peer:
    case (_, rest):
      match rest:
        case (_, xs):
          k((sock, xs, True{}))

def take_oct.m(
  sock: Socket,
  got: Maybe<&1, String & (U32 & List<&2, U32>)>,
  k: (Socket & List<&2, U32> & Bool) -> IO(Unit)
) -> IO(Unit):
  match got:
    case None{}:
      k((sock, Nil{}, False{}))
    case Some{peer}:
      take_oct.peer(sock, peer, k)

def take_oct.r(
  sock: Socket,
  r: Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +evt: Chan(Sess.NetEvt),
  k: (Socket & List<&2, U32> & Bool) -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{_}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Eof{})
        Unit <- evt_wake(ok)
        # Close the socket only. Leave evt open so a wake-fd poll that
        # returns before Chan.recv still sees Eof (RST/POLLERR).
        Socket.close(sock)
    case Done{got}:
      take_oct.m(sock, got, k)

def take_oct(
  pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +evt: Chan(Sess.NetEvt),
  k: (Socket & List<&2, U32> & Bool) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (sock, r):
      take_oct.r(sock, r, evt, k)

def SEND_CAP() -> Nat:
  8n

def split_at.go(n: Nat, xs: List<&2, String>, acc: List<&2, String>) -> List<&2, String> & List<&2, String>:
  match n:
    case 0n:
      (List.reverse(&2, String, acc), xs)
    case 1n+p:
      match xs:
        case Nil{}:
          (List.reverse(&2, String, acc), Nil{})
        case Con{+h, t}:
          split_at.go(p, t, h <> acc)

def split_at(+xs: List<&2, String>, +n: Nat) -> List<&2, String> & List<&2, String>:
  split_at.go(n, xs, Nil{})

def after_send_ok(
  pair: Socket & Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (sock, ok):
      match ok:
        case False{}:
          reader_die(sock, evt)
        case True{}:
          do IO<Unit>:
            m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Dns.recv_octets(sock, 4096)
            take_oct(m, evt, trip => after_poll(trip, evt, cmd, k))

def on_cont(
  parts: List<&2, String> & List<&2, String>,
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Socket -> List<&2, String> -> IO(Unit)
) -> IO(Unit):
  match parts:
    case (+now, later):
      do IO<Unit>:
        sent : Socket & Bool <- send_lines(sock, now)
        after_send_ok(sent, evt, cmd, s => k(s, later))

def flush_die.sent(pair: Socket & Bool, +evt: Chan(Sess.NetEvt)) -> IO(Unit):
  match pair:
    case (sock, _):
      reader_die(sock, evt)

# Shutdown and fuel-0 must put leftover lines (including QUIT) on the wire.
def flush_die(sock: Socket, +evt: Chan(Sess.NetEvt), +pending: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    sent : Socket & Bool <- send_lines(sock, pending)
    flush_die.sent(sent, evt)

def on_cmd(
  g: Maybe<&1, Sess.NetCmd>,
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  pending: List<&2, String>,
  k: Socket -> List<&2, String> -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      flush_die(sock, evt, pending)
    case Some{c}:
      match c:
        case Sess.Dial{_, _}:
          do IO<Unit>:
            ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Tick{})
            after_offer(sock, evt, cmd, ok, s => k(s, pending))
        case Sess.Handoff{_}:
          do IO<Unit>:
            ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Tick{})
            after_offer(sock, evt, cmd, ok, s => k(s, pending))
        case Sess.Cont{+outs}:
          on_cont(split_at(List.append(&2, String, pending, outs), SEND_CAP()), sock, evt, cmd, k)

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed reader_go
def reader_go(
  fuel: Nat,
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  pending: List<&2, String>
) -> IO(Unit):
  match fuel:
    case 0n:
      flush_die(sock, evt, pending)
    case 1n+p:
      do IO<Unit>:
        next : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
        on_cmd(next, sock, evt, cmd, pending, s2 => rest => reader_go(p, s2, evt, cmd, rest))

@unsafe
def reader_idle(sock: Socket, +evt: Chan(Sess.NetEvt), +cmd: Chan(Sess.NetCmd), pending: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    next : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
    on_cmd(next, sock, evt, cmd, pending, s2 => rest => reader_idle(s2, evt, cmd, rest))

def reader_start.on(
  zero: Bool,
  +frames: U32,
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match zero:
    case True{}:
      reader_idle(sock, evt, cmd, Nil{})
    case False{}:
      reader_go(Sess.ticks_of(frames), sock, evt, cmd, Nil{})

def reader_start(
  +frames: U32,
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  reader_start.on(U32.is_eq(frames, 0), frames, sock, evt, cmd)

# Boot is Data (never a Socket). UI recvs one result then closes the Chan
# so the loser send returns False instead of waiting on a full channel.
def idle_die(+evt: Chan(Sess.NetEvt)) -> IO(Unit):
  Chan.close(Sess.NetEvt, evt)

def idle_again(
  ok: Bool,
  +evt: Chan(Sess.NetEvt),
  k: Unit -> IO(Unit)
) -> IO(Unit):
  match ok:
    case False{}:
      idle_die(evt)
    case True{}:
      k(Unit{})

def idle_fail(
  +evt: Chan(Sess.NetEvt),
  +msg: String,
  k: Unit -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Fail{msg})
    poke_then(ok, o => idle_again(o, evt, k))

def handoff_wait(ok: Bool, ack: Chan(Unit)) -> IO(Unit):
  match ok:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        g : Maybe<&1, Unit> <- Chan.recv(Unit, ack)
        return Unit{}

def handoff_done(+cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), take: Bool) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.Handoff{take})
    handoff_wait(ok, ack)

def idle_up.go(
  g: Maybe<&1, Unit>,
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match g:
    case None{}:
      reader_die(sock, evt)
    case Some{_}:
      reader_start(frames, sock, evt, cmd)

def idle_up.ack(
  ok: Bool,
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  match ok:
    case False{}:
      reader_die(sock, evt)
    case True{}:
      do IO<Unit>:
        g : Maybe<&1, Unit> <- Chan.recv(Unit, ack)
        idle_up.go(g, sock, frames, evt, cmd)

def idle_up.take(
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.Handoff{True{}})
    idle_up.ack(ok, sock, frames, evt, cmd, ack)

def idle_up(
  ok: Bool,
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  match ok:
    case False{}:
      reader_die(sock, evt)
    case True{}:
      idle_up.take(sock, frames, evt, cmd, ack)

def idle_reg.fail(
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  k: Unit -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    Unit <- Socket.close(sock)
    idle_fail(evt, "register send failed", k)

def idle_reg.up(
  pair: Socket & U32,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  match pair:
    case (s, fd):
      do IO<Unit>:
        up : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Up{fd})
        poke_then(up, o => idle_up(o, s, frames, evt, cmd, ack))

def idle_reg.ok(
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  do IO<Unit>:
    pair : Socket & U32 <- Dns.fd_hint(sock)
    idle_reg.up(pair, frames, evt, cmd, ack)

def idle_reg(
  pair: Socket & Bool,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  k: Unit -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (s, ok):
      match ok:
        case False{}:
          idle_reg.fail(s, evt, k)
        case True{}:
          idle_reg.ok(s, frames, evt, cmd, ack)

def idle_conn(
  r: Result<&1, &1, (U32 & String), Socket>,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  k: Unit -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{e}:
      match e:
        case (_, +msg):
          idle_fail(evt, msg, k)
    case Done{s}:
      do IO<Unit>:
        pair : Socket & Bool <- register(s, nick)
        idle_reg(pair, frames, evt, cmd, ack, k)

def idle_dns(
  r: Result<&1, &1, U32 & String, String>,
  +port: U32,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  k: Unit -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{e}:
      match e:
        case (_, +msg):
          idle_fail(evt, msg, k)
    case Done{+ip}:
      do IO<Unit>:
        cr : Result<&1, &1, (U32 & String), Socket> <- TCP.connect(ip, port)
        idle_conn(cr, nick, frames, evt, cmd, ack, k)

def idle_wait_take(take: Bool, +ack: Chan(Unit)) -> IO(Bool):
  do IO<Bool>:
    ok : Bool <- Chan.send(Unit, ack, Unit{})
    return take

def idle_wait_cmd(
  g: Maybe<&1, Sess.NetCmd>,
  +evt: Chan(Sess.NetEvt),
  +ack: Chan(Unit),
  k_wait: Unit -> IO(Bool)
) -> IO(Bool):
  match g:
    case None{}:
      do IO<Bool>:
        Unit <- Chan.close(Unit, ack)
        Unit <- idle_die(evt)
        return True{}
    case Some{c}:
      match c:
        case Sess.Handoff{take}:
          idle_wait_take(take, ack)
        case Sess.Cont{_}:
          k_wait(Unit{})
        case Sess.Dial{_, _}:
          k_wait(Unit{})

def idle_wait_after(
  ok: Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  k_wait: Unit -> IO(Bool)
) -> IO(Bool):
  match ok:
    case False{}:
      do IO<Bool>:
        Unit <- Chan.close(Unit, ack)
        Unit <- idle_die(evt)
        return True{}
    case True{}:
      do IO<Bool>:
        next : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
        idle_wait_cmd(next, evt, ack, k_wait)

@unsafe
def idle_wait(
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Bool):
  do IO<Bool>:
    Unit <- IO.sleep(16)
    ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Tick{})
    idle_wait_after(ok, evt, cmd, ack, u => idle_wait(nick, frames, evt, cmd, ack))

def dial_job(
  +host: String,
  +port: U32,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve(host)
    idle_dns(r, port, nick, frames, evt, cmd, ack, u => handoff_done(cmd, ack, False{}))

def idle_dial.done(take: Bool, k: Unit -> IO(Unit)) -> IO(Unit):
  match take:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      k(Unit{})

def idle_dial.go(
  +host: String,
  +port: U32,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Unit -> IO(Unit),
  ack0: Chan(Unit)
) -> IO(Unit):
  +ack = ack0
  do IO<Unit>:
    Unit <- IO.spawn(Unit, dial_job(host, port, nick, frames, evt, cmd, ack))
    take : Bool <- idle_wait(nick, frames, evt, cmd, ack)
    idle_dial.done(take, k)

def idle_dial(
  +host: String,
  +port: U32,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Unit -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ack0 : Chan(Unit) <- Chan.new(Unit, 1)
    idle_dial.go(host, port, nick, frames, evt, cmd, k, ack0)

def idle_on_cmd(
  g: Maybe<&1, Sess.NetCmd>,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Unit -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      idle_die(evt)
    case Some{c}:
      match c:
        case Sess.Cont{_}:
          k(Unit{})
        case Sess.Handoff{_}:
          k(Unit{})
        case Sess.Dial{+host, port}:
          idle_dial(host, port, nick, frames, evt, cmd, k)

def idle_after_tick(
  ok: Bool,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Unit -> IO(Unit)
) -> IO(Unit):
  match ok:
    case False{}:
      idle_die(evt)
    case True{}:
      do IO<Unit>:
        next : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
        idle_on_cmd(next, nick, frames, evt, cmd, k)

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed idle_go
def idle_go(
  fuel: Nat,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match fuel:
    case 0n:
      idle_die(evt)
    case 1n+p:
      do IO<Unit>:
        ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Tick{})
        idle_after_tick(ok, nick, frames, evt, cmd, u => idle_go(p, nick, frames, evt, cmd))

@unsafe
def idle_idle(
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Tick{})
    idle_after_tick(ok, nick, frames, evt, cmd, u => idle_idle(nick, frames, evt, cmd))

def idle_start.on(
  zero: Bool,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match zero:
    case True{}:
      idle_idle(nick, frames, evt, cmd)
    case False{}:
      idle_go(Sess.ticks_of(frames), nick, frames, evt, cmd)

def idle_start(
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  idle_start.on(U32.is_eq(frames, 0), nick, frames, evt, cmd)
type Boot is Data:
  Ready{}
  Down{msg: String}
  Timeout{}

def boot_fail(+boot: Chan(Boot), +msg: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Boot, boot, Down{msg})
    return Unit{}

def actor_up.sent(
  up: Bool,
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match up:
    case False{}:
      Socket.close(sock)
    case True{}:
      reader_start(frames, sock, evt, cmd)

def actor_up.on(
  pair: Socket & U32,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match pair:
    case (s, fd):
      do IO<Unit>:
        up : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Up{fd})
        poke_then(up, o => actor_up.sent(o, s, frames, evt, cmd))

def actor_ready_ok(
  ok: Bool,
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match ok:
    case False{}:
      Socket.close(sock)
    case True{}:
      do IO<Unit>:
        pair : Socket & U32 <- Dns.fd_hint(sock)
        actor_up.on(pair, frames, evt, cmd)

def actor_ready(
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot)
) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Boot, boot, Ready{})
    actor_ready_ok(ok, sock, frames, evt, cmd)

def actor_reg(
  pair: Socket & Bool,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot)
) -> IO(Unit):
  match pair:
    case (s, ok):
      match ok:
        case False{}:
          do IO<Unit>:
            Unit <- Socket.close(s)
            boot_fail(boot, "register send failed")
        case True{}:
          actor_ready(s, frames, evt, cmd, boot)

def actor_conn(
  r: Result<&1, &1, (U32 & String), Socket>,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot)
) -> IO(Unit):
  match r:
    case Fail{e}:
      match e:
        case (_, +msg):
          boot_fail(boot, msg)
    case Done{s}:
      do IO<Unit>:
        pair : Socket & Bool <- register(s, nick)
        actor_reg(pair, frames, evt, cmd, boot)

def actor_boot(
  +host: String,
  +port: U32,
  +nick: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot)
) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, (U32 & String), Socket> <- TCP.connect(host, port)
    actor_conn(r, nick, frames, evt, cmd, boot)
