# IRC networking IO (M4). Pure fold/fuel live in session.bend.
# IO.spawn net actor owns Socket; UI ↔ actor via Chan(Sess.NetEvt)/Chan(Sess.NetCmd).
# D3: TCP.send String; inbound octets via recv_octets, framed by Fr.push.
# Empty octet list is EOF. Completed lines are UTF-8, Latin-1 if invalid.
# Shutdown: actor Socket.close then Timui.close (drain evt after Chan.close(cmd)).
# Dial: actor owns the fd (never Chan(Socket)). Demo/Connecting Cont is
# held (empty outs) so queued JOIN/PRIVMSG cannot flush after Dial.
# frames=0 uses @unsafe idle; --frames N is fuel.
# Eof: UI spawns a fresh idle actor on new channels and keeps painting.
# Actor code never calls UI code (no mutual recursion).
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./view.bend as V
import ./timui.bend as T
import ./session.bend as Sess

import ./clock.bend as Clock
import ./dns.bend as Dns

def send_go_r(s: Socket, r: Result<&1, &1, (U32 & String), Unit>) -> IO(Socket & Bool):
  match r:
    case Done{_}:
      IO.pure(Socket & Bool, (s, True{}))
    case Fail{_}:
      IO.pure(Socket & Bool, (s, False{}))

def send_go(m: Socket & Result<&1, &1, (U32 & String), Unit>) -> IO(Socket & Bool):
  match m:
    case (s, r):
      send_go_r(s, r)

def send_line(sock: Socket, +line: String) -> IO(Socket & Bool):
  do IO<Socket & Bool>:
    m : Socket & Result<&1, &1, (U32 & String), Unit> <- TCP.send(sock, Irc.clamp_line(Irc.strip_ctl(line)) ++ "\r\n")
    send_go(m)

type SLPh is Data:
  SLList{}
  SLOk{}

def send_lines_go(
  fuel: Nat,
  phase: SLPh,
  +xs: List<&2, String>,
  pair: Socket & Bool,
  +t: List<&2, String>
) -> IO(Socket & Bool):
  match fuel:
    case 0n:
      match pair:
        case (sock, _):
          IO.pure(Socket & Bool, (sock, False{}))
    case 1n+p:
      match phase:
        case SLList{}:
          match xs:
            case Nil{}:
              IO.pure(Socket & Bool, pair)
            case Con{+h, tl}:
              match pair:
                case (sock, _):
                  do IO<Socket & Bool>:
                    nxt : Socket & Bool <- send_line(sock, h)
                    send_lines_go(p, SLOk{}, tl, nxt, tl)
        case SLOk{}:
          match pair:
            case (sock, ok0):
              match ok0:
                case False{}:
                  IO.pure(Socket & Bool, (sock, False{}))
                case True{}:
                  send_lines_go(p, SLList{}, t, (sock, True{}), t)

def send_lines(fuel: Nat, sock: Socket, +xs: List<&2, String>) -> IO(Socket & Bool):
  send_lines_go(fuel, SLList{}, xs, (sock, True{}), Nil{})

# JOIN is sent after 001 (live_go), not here.
def register(sock: Socket, +nick: String) -> IO(Socket & Bool):
  send_lines(8n, sock, Sess.register_lines(nick))

def reader_die(sock: Socket, +evt: Chan(Sess.NetEvt)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Socket.close(sock)
    Chan.close(Sess.NetEvt, evt)

def wait_dead_g(fuel: Nat, ui: T.Ui, +evt: Chan(Sess.NetEvt), g: Maybe<&1, Sess.NetEvt>) -> IO(Unit):
  match fuel:
    case 0n:
      T.Timui.close(ui)
    case 1n+p:
      match g:
        case None{}:
          T.Timui.close(ui)
        case Some{_}:
          do IO<Unit>:
            g2 : Maybe<&1, Sess.NetEvt> <- Chan.recv(Sess.NetEvt, evt)
            wait_dead_g(p, ui, evt, g2)

# Close cmd (actor Socket.close + Chan.close(evt)), drain evt to None, then Timui.close.
# Halt so a parked TCP.connect / sleep cannot keep io_loop alive (H4, H6).
def shutdown(ui: T.Ui, +evt: Chan(Sess.NetEvt), +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    g0 : Maybe<&1, Sess.NetEvt> <- Chan.recv(Sess.NetEvt, evt)
    Unit <- wait_dead_g(256n, ui, evt, g0)
    Unit <- IO.print("birc=ok")
    IO.die(Unit, 0, "")

def paint_vm(ui: T.Ui, +vm: V.ViewModel, +seed: U32) -> IO(T.Ui & T.UiKeys):
  match vm:
    case V.ViewModel{+ops, +inp}:
      T.Timui.frame(ui, ops, inp, seed)

def paint_session.size(
  ui: T.Ui,
  +cl: Cl.Client,
  +draft: String,
  net: Sess.NetState,
  +seed: U32,
  size: Sess.Size
) -> IO(T.Ui & T.UiKeys):
  match size:
    case Sess.Size{rows, cols}:
      paint_vm(ui, V.view_draft(cl, rows, cols, draft, Sess.net_label(net)), seed)

def paint_session(ui: T.Ui, +st: Sess.Session) -> IO(T.Ui & T.UiKeys):
  match st:
    case Sess.Session{+cl, _, _, +draft, _, _, net, _, size, seed}:
      paint_session.size(ui, cl, draft, net, seed, size)

def after_ui_send(
  ok: Bool,
  ui: T.Ui,
  +st2: Sess.Session,
  quit: Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match ok:
    case False{}:
      shutdown(ui, evt, cmd)
    case True{}:
      k((ui, st2, evt, cmd, quit))

def send_pair(
  ui: T.Ui,
  quit: Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  pair: Sess.Session & Sess.NetCmd & Bool,
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (+st2, rest):
      match rest:
        case (+ncmd, halt):
          do IO<Unit>:
            ok : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.hold_cmd(Sess.session_net(st2), Sess.merge_cmd(pending, ncmd)))
            after_ui_send(ok, ui, st2, Bool.or(quit, halt), evt, cmd, k)

def step_size(
  triple: Sess.Session & Sess.NetCmd & Bool,
  +rows: U32,
  +cols: U32
) -> Sess.Session & Sess.NetCmd & Bool:
  match triple:
    case (+st, rest):
      match rest:
        case (+cmd, halt):
          (Sess.session_set_size(st, rows, cols), cmd, halt)

def with_keys.go(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +typed: String,
  +rows: U32,
  +cols: U32,
  +tab: U32,
  +click: U32,
  +up: U32,
  +dn: U32,
  +hist: U32,
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit),
  quit: Bool,
  enter: Bool
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    send_pair(ui, quit, evt, cmd, step_size(Sess.step_keys(Sess.session_set_now(st, ts), typed, enter, tab, click, up, dn, hist), rows, cols), pending, k)

def with_keys(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  keys: T.UiKeys,
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match keys:
    case T.UiKeys{quit, enter, +typed, rows, cols, tab, click, up, dn, hist}:
      with_keys.go(ui, st, evt, cmd, typed, rows, cols, tab, click, up, dn, hist, pending, k, T.flag_on(quit), T.flag_on(enter))

def with_tick.got(
  got: T.Ui & T.UiKeys,
  +st2: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match got:
    case (ui2, keys):
      with_keys(ui2, st2, evt, cmd, keys, pending, k)

def with_tick_pend(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st)
    with_tick.got(got, st, evt, cmd, pending, k)

def with_tick(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  with_tick_pend(ui, st, evt, cmd, Nil{}, k)

def with_chunk_pair(
  ui: T.Ui,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  pair: Sess.Session & List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (+st2, +outs):
      with_tick_pend(ui, st2, evt, cmd, outs, k)

def with_chunk.ts(
  ui: T.Ui,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ts: String,
  +st: Sess.Session,
  xs: List<&2, U32>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  with_chunk_pair(ui, evt, cmd, Sess.step_on_chunk(Sess.session_set_now(st, ts), xs), k)

def with_chunk(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  xs: List<&2, U32>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    with_chunk.ts(ui, evt, cmd, ts, st, xs, k)

def with_fail(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +msg: String,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    with_tick(ui, Sess.session_fail(Sess.session_set_now(st, ts), msg), evt, cmd, k)

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
        reader_die(sock, evt)
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Chunk{xs})
        after_offer(sock, evt, cmd, ok, k)

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
      reader_die(sock, evt)
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

def on_cmd(
  g: Maybe<&1, Sess.NetCmd>,
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      reader_die(sock, evt)
    case Some{c}:
      match c:
        case Sess.Dial{_, _}:
          do IO<Unit>:
            ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Tick{})
            after_offer(sock, evt, cmd, ok, k)
        case Sess.Handoff{_}:
          do IO<Unit>:
            ok : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Tick{})
            after_offer(sock, evt, cmd, ok, k)
        case Sess.Cont{+outs}:
          do IO<Unit>:
            sent : Socket & Bool <- send_lines(Nat.add(1n, Nat.mul(2n, List.length(&2, String, outs))), sock, outs)
            after_send_ok(sent, evt, cmd, k)

# One fuel tick = one cmd/poll cycle.
def reader_go(
  fuel: Nat,
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match fuel:
    case 0n:
      reader_die(sock, evt)
    case 1n+p:
      do IO<Unit>:
        next : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
        on_cmd(next, sock, evt, cmd, s2 => reader_go(p, s2, evt, cmd))

@unsafe
def reader_idle(sock: Socket, +evt: Chan(Sess.NetEvt), +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  do IO<Unit>:
    next : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
    on_cmd(next, sock, evt, cmd, s2 => reader_idle(s2, evt, cmd))

def reader_start.on(
  zero: Bool,
  +frames: U32,
  sock: Socket,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match zero:
    case True{}:
      reader_idle(sock, evt, cmd)
    case False{}:
      reader_go(Sess.ticks_of(frames), sock, evt, cmd)

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
    idle_again(ok, evt, k)

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

def idle_reg.ok(
  sock: Socket,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  do IO<Unit>:
    up : Bool <- Chan.send(Sess.NetEvt, evt, Sess.Up{})
    idle_up(up, sock, frames, evt, cmd, ack)

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

def with_eof.go(
  ui: T.Ui,
  +st: Sess.Session,
  +cmd: Chan(Sess.NetCmd),
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit),
  evt0: Chan(Sess.NetEvt),
  cmd0: Chan(Sess.NetCmd)
) -> IO(Unit):
  +evt2 = evt0
  +cmd2 = cmd0
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    Unit <- IO.spawn(Unit, idle_start(Sess.session_nick(st), frames, evt2, cmd2))
    Unit <- Chan.close(Sess.NetCmd, cmd)
    with_tick(ui, Sess.session_fail(Sess.session_set_now(st, ts), "disconnected"), evt2, cmd2, k)

def with_eof(
  ui: T.Ui,
  +st: Sess.Session,
  +cmd: Chan(Sess.NetCmd),
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    evt0 : Chan(Sess.NetEvt) <- Chan.new(Sess.NetEvt, 64)
    cmd0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    with_eof.go(ui, st, cmd, frames, k, evt0, cmd0)

def on_evt_some(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  e: Sess.NetEvt,
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match e:
    case Sess.Eof{}:
      with_eof(ui, st, cmd, frames, k)
    case Sess.Tick{}:
      with_tick(ui, st, evt, cmd, k)
    case Sess.Chunk{xs}:
      with_chunk(ui, st, evt, cmd, xs, k)
    case Sess.Up{}:
      with_tick(ui, Sess.session_online(st), evt, cmd, k)
    case Sess.Fail{+msg}:
      with_fail(ui, st, evt, cmd, msg, k)

def on_evt(
  g: Maybe<&1, Sess.NetEvt>,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      shutdown(ui, evt, cmd)
    case Some{e}:
      on_evt_some(ui, st, evt, cmd, e, frames, k)

def live_step(
  quit: Bool,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match quit:
    case True{}:
      shutdown(ui, evt, cmd)
    case False{}:
      do IO<Unit>:
        got : Maybe<&1, Sess.NetEvt> <- Chan.recv(Sess.NetEvt, evt)
        on_evt(got, ui, st, evt, cmd, frames, k)

# One fuel tick = one net event (Tick/Chunk) plus paint/keys/send.
def live_go(
  fuel: Nat,
  acc: T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool,
  +frames: U32
) -> IO(Unit):
  match fuel:
    case 0n:
      match acc:
        case (ui, _, evt, cmd, _):
          shutdown(ui, evt, cmd)
    case 1n+p:
      match acc:
        case (ui, +st, evt, cmd, quit):
          live_step(quit, ui, st, evt, cmd, frames, nxt => live_go(p, nxt, frames))

@unsafe
def live_idle(
  acc: T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool,
  +frames: U32
) -> IO(Unit):
  match acc:
    case (ui, +st, evt, cmd, quit):
      live_step(quit, ui, st, evt, cmd, frames, nxt => live_idle(nxt, frames))

type Boot is Data:
  Ready{}
  Down{msg: String}
  Timeout{}

def boot_fail(+boot: Chan(Boot), +msg: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Boot, boot, Down{msg})
    return Unit{}

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
      reader_start(frames, sock, evt, cmd)

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

def boot_clock.step(n: Nat, ok: Bool, +boot: Chan(Boot), +stop: Chan(Unit)) -> IO(Unit):
  match n:
    case 0n:
      match ok:
        case False{}:
          IO.pure(Unit, Unit{})
        case True{}:
          do IO<Unit>:
            t : Bool <- Chan.send(Boot, boot, Timeout{})
            return Unit{}
    case 1n+p:
      match ok:
        case False{}:
          IO.pure(Unit, Unit{})
        case True{}:
          do IO<Unit>:
            Unit <- IO.sleep(100)
            nxt : Bool <- Chan.send(Unit, stop, Unit{})
            boot_clock.step(p, nxt, boot, stop)

def boot_clock(+boot: Chan(Boot), +stop: Chan(Unit)) -> IO(Unit):
  boot_clock.step(80n, True{}, boot, stop)

def live_boot.acc(
  zero: Bool,
  +frames: U32,
  acc: T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool
) -> IO(Unit):
  match zero:
    case True{}:
      live_idle(acc, frames)
    case False{}:
      live_go(Sess.ticks_of(frames), acc, frames)

def live_boot.on(
  zero: Bool,
  +frames: U32,
  trip: T.Ui & Sess.Session & Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match trip:
    case (ui, +st, quit):
      live_boot.acc(zero, frames, (ui, st, evt, cmd, quit))

def start_ui(
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +chan: String
) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.Cont{Nil{}})
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    live_boot.on(U32.is_eq(frames, 0), frames, (ui, Sess.session_online(Sess.session0(nick, host, chan)), False{}), evt, cmd)

def boot_die(+cmd: Chan(Sess.NetCmd), +msg: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    IO.die(Unit, 1, msg)

def boot_ui_on(
  e: Boot,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +chan: String
) -> IO(Unit):
  match e:
    case Timeout{}:
      boot_die(cmd, "connect timeout")
    case Down{+msg}:
      boot_die(cmd, msg)
    case Ready{}:
      start_ui(frames, evt, cmd, nick, host, chan)

def boot_ui(
  g: Maybe<&1, Boot>,
  +boot: Chan(Boot),
  +stop: Chan(Unit),
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +chan: String
) -> IO(Unit):
  match g:
    case None{}:
      boot_die(cmd, "connect failed")
    case Some{e}:
      do IO<Unit>:
        Unit <- Chan.close(Boot, boot)
        Unit <- Chan.close(Unit, stop)
        boot_ui_on(e, frames, evt, cmd, nick, host, chan)

def run_live_on(
  +frames: U32,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  evt0: Chan(Sess.NetEvt),
  cmd0: Chan(Sess.NetCmd),
  boot0: Chan(Boot),
  stop0: Chan(Unit)
) -> IO(Unit):
  +evt = evt0
  +cmd = cmd0
  +boot = boot0
  +stop = stop0
  do IO<Unit>:
    Unit <- IO.spawn(Unit, actor_boot(host, port, nick, frames, evt, cmd, boot))
    Unit <- IO.spawn(Unit, boot_clock(boot, stop))
    g : Maybe<&1, Boot> <- Chan.recv(Boot, boot)
    boot_ui(g, boot, stop, frames, evt, cmd, nick, host, chan)

def run_live(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String) -> IO(Unit):
  do IO<Unit>:
    evt0 : Chan(Sess.NetEvt) <- Chan.new(Sess.NetEvt, 64)
    cmd0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    boot0 : Chan(Boot) <- Chan.new(Boot, 1)
    stop0 : Chan(Unit) <- Chan.new(Unit, 80)
    run_live_on(frames, host, port, nick, chan, evt0, cmd0, boot0, stop0)

def boot_demo(
  ui: T.Ui,
  +cl: Cl.Client,
  +chan: String,
  +ts: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  live_boot.on(U32.is_eq(frames, 0), frames, (ui, Sess.session_set_now(Sess.session_demo(cl, chan), ts), False{}), evt, cmd)

def run_offline_on(
  +frames: U32,
  +cl: Cl.Client,
  +nick: String,
  +chan: String,
  evt0: Chan(Sess.NetEvt),
  cmd0: Chan(Sess.NetCmd)
) -> IO(Unit):
  +evt = evt0
  +cmd = cmd0
  do IO<Unit>:
    Unit <- IO.spawn(Unit, idle_start(nick, frames, evt, cmd))
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    ts : String <- Clock.hhmmss()
    boot_demo(ui, cl, chan, ts, frames, evt, cmd)

def run_offline(+frames: U32, +cl: Cl.Client, +nick: String, +chan: String) -> IO(Unit):
  do IO<Unit>:
    evt0 : Chan(Sess.NetEvt) <- Chan.new(Sess.NetEvt, 64)
    cmd0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    run_offline_on(frames, cl, nick, chan, evt0, cmd0)
