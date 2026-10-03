# Net actor: Connection ownership, reader/idle loops, dial, send_line.
# UI lives in net.bend. Actor never calls UI (no mutual recursion).
import Base
import ./irc.bend as Irc
import ./session.bend as Sess
import ./dns.bend as Dns
import ./outbound.bend as Out
import ./transport.bend as Tr

def send_go_r(s: Tr.Conn, r: Result<&1, &1, (U32 & String), Unit>) -> Tr.Conn & Bool:
  match r:
    case Done{_}:
      (s, True{})
    case Fail{_}:
      (s, False{})

def send_go(m: Tr.Conn & Result<&1, &1, (U32 & String), Unit>) -> Tr.Conn & Bool:
  match m:
    case (s, r):
      send_go_r(s, r)

def send_line(sock: Tr.Conn, +line: String) -> IO(Tr.Conn & Bool):
  do IO<Tr.Conn & Bool>:
    m : Tr.Conn & Result<&1, &1, (U32 & String), Unit> <- Tr.send_for(sock, Irc.clamp_line(Irc.strip_ctl(line)) ++ "\r\n", 250)
    IO.pure(Tr.Conn & Bool, send_go(m))

type Sent is Data:
  Sent{count: Nat, ok: Bool}

def send_batch_go(xs: List<&2, String>, pair: Tr.Conn & Bool, +count: Nat) -> IO(Tr.Conn & Sent):
  match xs:
    case Nil{}:
      match pair:
        case (sock, ok):
          IO.pure(Tr.Conn & Sent, (sock, Sent{count, ok}))
    case Con{+h, t}:
      match pair:
        case (sock, ok):
          match ok:
            case False{}:
              IO.pure(Tr.Conn & Sent, (sock, Sent{count, False{}}))
            case True{}:
              do IO<Tr.Conn & Sent>:
                nxt : Tr.Conn & Bool <- send_line(sock, h)
                send_batch_go(t, nxt, Nat.add(count, 1n))

# Count attempted lines. On failure the last attempt may have written only
# part of its line, so neither that line nor the remainder may be replayed.
def send_batch(sock: Tr.Conn, +xs: List<&2, String>) -> IO(Tr.Conn & Sent):
  send_batch_go(xs, (sock, True{}), 0n)

def sent_ok(pair: Tr.Conn & Sent) -> Tr.Conn & Bool:
  match pair:
    case (sock, Sent{_, ok}): (sock, ok)

def send_lines(sock: Tr.Conn, +xs: List<&2, String>) -> IO(Tr.Conn & Bool):
  do IO<Tr.Conn & Bool>:
    pair : Tr.Conn & Sent <- send_batch(sock, xs)
    return sent_ok(pair)

# JOIN is sent after 001 (live_go), not here.
def register(sock: Tr.Conn, +nick: String, has_sasl: Bool) -> IO(Tr.Conn & Bool):
  send_lines(sock, Sess.handshake_lines(nick, has_sasl))

def post(+evt: Chan(Sess.UiMsg), +gen: U32, e: Sess.NetEvt) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.UiMsg, evt, Sess.FromNet{gen, e})
    return Unit{}

def reader_stop(dup: Tr.Conn, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- post(evt, gen, Sess.Eof{})
    Tr.close(dup)

def reader_xs.on(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  +xs: List<&2, U32>,
  empty: Bool,
  k: Tr.Conn -> IO(Unit)
) -> IO(Unit):
  match empty:
    case True{}:
      reader_stop(dup, evt, gen)
    case False{}:
      do IO<Unit>:
        Unit <- post(evt, gen, Sess.Chunk{xs})
        k(dup)

def reader_xs(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  +xs: List<&2, U32>,
  k: Tr.Conn -> IO(Unit)
) -> IO(Unit):
  reader_xs.on(dup, evt, gen, xs, List.is_empty(&2, U32, xs), k)

def reader_peer(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  p: String & (U32 & List<&2, U32>),
  k: Tr.Conn -> IO(Unit)
) -> IO(Unit):
  match p:
    case (_, rest):
      match rest:
        case (_, xs):
          reader_xs(dup, evt, gen, xs, k)

def reader_got(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  got: Maybe<&1, String & (U32 & List<&2, U32>)>,
  k: Tr.Conn -> IO(Unit)
) -> IO(Unit):
  match got:
    case None{}:
      k(dup)
    case Some{p}:
      reader_peer(dup, evt, gen, p, k)

def reader_r(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  r: Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  k: Tr.Conn -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{(code, _)}:
      do IO<Unit>:
        Unit <- post(evt, gen, Sess.NetFail{"receive failed (OS " ++ U32.show(code) ++ ")"})
        Tr.close(dup)
    case Done{got}:
      reader_got(dup, evt, gen, got, k)

def reader_pair(
  pair: Tr.Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  k: Tr.Conn -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (dup, r):
      reader_r(dup, evt, gen, r, k)

@unsafe
def reader_run(dup: Tr.Conn, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    m : Tr.Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Tr.recv_octets(dup, 4096)
    reader_pair(m, evt, gen, d => reader_run(d, evt, gen))

# Announce Up before any data or EOF. This reader task may park on evt;
# the socket-owning writer must remain free to consume cmd and shut down.
def reader_start(dup: Tr.Conn, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- post(evt, gen, Sess.Up{})
    reader_run(dup, evt, gen)

def writer_drop.r(pair: Tr.Conn & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, _):
      Tr.close(sock)

def writer_drop(sock: Tr.Conn) -> IO(Unit):
  do IO<Unit>:
    pair : Tr.Conn & Result<&1, &1, U32 & String, Unit> <- Tr.shutdown(sock)
    writer_drop.r(pair)

def writer_fail(+evt: Chan(Sess.UiMsg), +gen: U32, +msg: String) -> IO(Unit):
  post(evt, gen, Sess.NetFail{msg})

type Boot is Data:
  Ready{}
  Down{msg: String}

def boot_down(+boot: Chan(Boot), +msg: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Boot, boot, Down{msg})
    return Unit{}

def err_msg(e: U32 & String) -> String:
  match e:
    case (_, +msg):
      msg

def arm_ready(live: Bool, +boot: Chan(Boot)) -> IO(Unit):
  match live:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Boot, boot, Ready{})
        return Unit{}

def arm_fail(
  live: Bool,
  +boot: Chan(Boot),
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  +msg: String,
  k: (Maybe<&1, Tr.Conn> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match live:
    case True{}:
      do IO<Unit>:
        Unit <- boot_down(boot, msg)
        k((None{}, gen, Nil{}))
    case False{}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, writer_fail(evt, gen, msg))
        k((None{}, gen, Nil{}))

def arm_ok(
  sock: Tr.Conn,
  dup: Tr.Conn,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Tr.Conn> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    Unit <- arm_ready(live, boot)
    Unit <- IO.spawn(Unit, reader_start(dup, evt, gen))
    k((Some{sock}, gen, Nil{}))

def arm_dup(
  pair: Tr.Conn & Result<&1, &1, U32 & String, Tr.Conn>,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Tr.Conn> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{e}:
          do IO<Unit>:
            Unit <- Tr.close(sock)
            arm_fail(live, boot, evt, gen, err_msg(e), k)
        case Done{dup}:
          arm_ok(sock, dup, gen, evt, boot, live, k)

def after_reg(
  pair: Tr.Conn & Bool,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Tr.Conn> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (sock, ok):
      match ok:
        case False{}:
          do IO<Unit>:
            Unit <- Tr.close(sock)
            arm_fail(live, boot, evt, gen, "register send failed", k)
        case True{}:
          do IO<Unit>:
            d : Tr.Conn & Result<&1, &1, U32 & String, Tr.Conn> <- Tr.dup(sock)
            arm_dup(d, gen, evt, boot, live, k)

def after_conn(
  r: Result<&1, &1, (U32 & String), Tr.Conn>,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  live: Bool,
  has_sasl: Bool,
  k: (Maybe<&1, Tr.Conn> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{e}:
      arm_fail(live, boot, evt, gen, err_msg(e), k)
    case Done{sock}:
      do IO<Unit>:
        pair : Tr.Conn & Bool <- register(sock, nick, has_sasl)
        after_reg(pair, gen, evt, boot, live, k)

def after_dns(
  r: Result<&1, &1, U32 & String, String>,
  +host: String,
  +port: U32,
  force_tls: Bool,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  live: Bool,
  has_sasl: Bool,
  k: (Maybe<&1, Tr.Conn> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{e}:
      arm_fail(live, boot, evt, gen, err_msg(e), k)
    case Done{+ip}:
      do IO<Unit>:
        cr : Result<&1, &1, (U32 & String), Tr.Conn> <- Tr.connect_for(ip, port, host, force_tls)
        after_conn(cr, nick, gen, evt, boot, live, has_sasl, k)

def dial_begin(
  +host: String,
  +port: U32,
  force_tls: Bool,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  live: Bool,
  has_sasl: Bool,
  k: (Maybe<&1, Tr.Conn> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve(host)
    after_dns(r, host, port, force_tls, nick, gen, evt, boot, live, has_sasl, k)

type AuthScope is Data:
  AuthScope{host: String, port: U32, enabled: Bool}

def auth_scope_enabled(scope: AuthScope) -> Bool:
  match scope:
    case AuthScope{_, _, enabled}: enabled

# The launch enables negotiation for one exact endpoint. Once a Dial leaves
# it, returning later cannot restore credentials that Session already dropped.
def auth_scope_dial(scope: AuthScope, +host: String, +port: U32) -> AuthScope:
  match scope:
    case AuthScope{+initial_host, +initial_port, enabled}:
      AuthScope{initial_host, initial_port,
        enabled && String.eq(initial_host, host) && U32.is_eq(initial_port, port)}

type PendingDial is Data:
  PendingDial{host: String, port: U32, nick: String}

type Deferred is Data:
  Deferred{pending: Maybe<&2, PendingDial>, gen: U32, scope: AuthScope}

type DeferredStep is Data:
  Waiting{state: Deferred}
  Starting{dial: PendingDial, gen: U32, scope: AuthScope, initial: Bool}
  Released{gen: U32, scope: AuthScope}

def deferred_initial(+host: String, +port: U32, nick: String, has_sasl: Bool) -> Deferred:
  Deferred{Some{PendingDial{host, port, nick}}, 1, AuthScope{host, port, has_sasl}}

def deferred_begin.pending(pending: Maybe<&2, PendingDial>, +gen: U32, scope: AuthScope) -> DeferredStep:
  match pending:
    case None{}: Released{gen, scope}
    case Some{dial}: Starting{dial, gen, scope, U32.is_eq(gen, 1)}

def deferred_begin(ok: Bool, st: Deferred) -> DeferredStep:
  match ok:
    case False{}: Waiting{st}
    case True{}:
      match st:
        case Deferred{pending, gen, scope}: deferred_begin.pending(pending, gen, scope)

# Until Begin, Cont cannot leak registration/chat bytes and Dial only changes
# the pending endpoint. Leaving the credential scope is permanent even here.
def deferred_command(cmd: Sess.NetCmd, st: Deferred) -> DeferredStep:
  match cmd:
    case Sess.Dial{+host, +port, gen, nick}:
      match st:
        case Deferred{_, _, scope}:
          Waiting{Deferred{Some{PendingDial{host, port, nick}}, gen, auth_scope_dial(scope, host, port)}}
    case Sess.Drop{}:
      match st:
        case Deferred{_, gen, scope}: Waiting{Deferred{None{}, gen, scope}}
    case Sess.Begin{+wanted}:
      match st:
        case Deferred{pending, +gen, scope}: deferred_begin(U32.is_eq(wanted, gen), Deferred{pending, gen, scope})
    case _: Waiting{st}

type Writer is Type:
  Writer{socket: Maybe<&1, Tr.Conn>, gen: U32, pending: List<&2, String>, budget: Out.Budget, scheduled: Bool}

def writer_adopt(st: Maybe<&1, Tr.Conn> & U32 & List<&2, String>, budget: Out.Budget) -> Writer:
  match st:
    case (sock, (gen, pending)): Writer{sock, gen, pending, budget, False{}}

def close_socket(sock: Maybe<&1, Tr.Conn>) -> IO(Unit):
  match sock:
    case None{}: IO.pure(Unit, Unit{})
    case Some{s}: writer_drop(s)

# Preserve the ordinary EOF notification, then acknowledge writer completion
# separately. A reader's EOF cannot stand in for this socket-owner event.
def writer_done(+evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- post(evt, gen, Sess.Eof{})
    post(evt, gen, Sess.WriterDone{})

def finish_sent(pair: Tr.Conn & Sent, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  match pair:
    case (sock, _):
      do IO<Unit>:
        Unit <- writer_drop(sock)
        writer_done(evt, gen)

# Closing cmd (including UI fuel exhaustion) flushes the healthy FIFO outside
# the loop budget. A failed/partial write stops this flush without replay.
def writer_finish(st: Writer, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match st:
    case Writer{sock, +gen, pending, _, _}:
      match sock:
        case None{}: writer_done(evt, gen)
        case Some{s}:
          do IO<Unit>:
            pair : Tr.Conn & Sent <- send_batch(s, pending)
            finish_sent(pair, evt, gen)

def pump_send(+cmd: Chan(Sess.NetCmd), gen: U32) -> IO(Unit):
  do IO<Unit>:
    _ : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.Pump{gen})
    return Unit{}

# Never await a self-send on the socket-owning task: cmd may already be full.
# One scheduled flag permits at most one outstanding pump for this generation.
def writer_schedule(need: Bool, st: Writer, +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match need:
    case False{}: k(st)
    case True{}:
      match st:
        case Writer{sock, +gen, pending, budget, _}:
          do IO<Unit>:
            Unit <- IO.spawn(Unit, pump_send(cmd, gen))
            k(Writer{sock, gen, pending, budget, True{}})

def writer_sent(pair: Tr.Conn & Sent, +gen: U32, +later: List<&2, String>, +budget: Out.Budget, +scheduled: Bool, +total: Nat, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match pair:
    case (sock, Sent{+count, ok}):
      match ok:
        case False{}:
          do IO<Unit>:
            Unit <- writer_drop(sock)
            Unit <- IO.spawn(Unit, writer_fail(evt, gen, "send timed out or failed; " ++ Nat.show(Nat.add(1n, Nat.sub(total, count))) ++ " queued/uncertain lines were discarded without retry"))
            k(Writer{None{}, gen, Nil{}, budget, False{}})
        case True{}:
          writer_schedule(Bool.not(scheduled) && Bool.not(List.is_empty(&2, String, later)) && Out.budget_open(budget), Writer{Some{sock}, gen, later, budget, scheduled}, cmd, k)

def writer_batch(sock: Tr.Conn, +gen: U32, plan: Out.Batch, +scheduled: Bool, +total: Nat, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match plan:
    case Out.Batch{now, later, budget}:
      do IO<Unit>:
        pair : Tr.Conn & Sent <- send_batch(sock, now)
        writer_sent(pair, gen, later, budget, scheduled, total, evt, cmd, k)

def writer_queue(st: Writer, outs: List<&2, String>, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match st:
    case Writer{sock, +gen, pending, budget, +scheduled}:
      match sock:
        case None{}: k(Writer{None{}, gen, Nil{}, budget, False{}})
        case Some{s}:
          +all = List.append(&2, String, pending, outs)
          writer_batch(s, gen, Out.batch(all, budget), scheduled, List.length(&2, String, all), evt, cmd, k)

def writer_pump(same: Bool, st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match same:
    case False{}: k(st)
    case True{}:
      match st:
        case Writer{sock, gen, pending, budget, _}:
          writer_queue(Writer{sock, gen, pending, budget, False{}}, Nil{}, evt, cmd, k)

def writer_command(c: Sess.NetCmd, st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +scope: AuthScope, force_tls: Bool, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match c:
    case Sess.Cont{outs}: writer_queue(st, outs, evt, cmd, next => k((next, scope)))
    case Sess.OpenUrl{_}: k((st, scope))
    case Sess.Begin{_}: k((st, scope))
    case Sess.Pump{pgen}:
      match st:
        case Writer{sock, +gen, pending, budget, scheduled}:
          writer_pump(U32.is_eq(pgen, gen), Writer{sock, gen, pending, budget, scheduled}, evt, cmd, next => k((next, scope)))
    case Sess.Drop{}:
      match st:
        case Writer{sock, gen, _, budget, _}:
          do IO<Unit>:
            Unit <- close_socket(sock)
            k((Writer{None{}, gen, Nil{}, budget, False{}}, scope))
    case Sess.Dial{+host, +port, gen, +nick}:
      match st:
        case Writer{sock, _, _, budget, _}:
          +next_scope = auth_scope_dial(scope, host, port)
          do IO<Unit>:
            Unit <- close_socket(sock)
            dial_begin(host, port, force_tls, nick, gen, evt, boot, False{}, auth_scope_enabled(next_scope),
              pair => k((writer_adopt(pair, budget), next_scope)))

def writer_received(g: Maybe<&1, Sess.NetCmd>, st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), scope: AuthScope, force_tls: Bool, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}: writer_finish(st, evt)
    case Some{c}: writer_command(c, st, evt, cmd, boot, scope, force_tls, k)

@unsafe
def writer_loop(state: Writer & AuthScope, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +force_tls: Bool) -> IO(Unit):
  match state:
    case (st, scope):
      do IO<Unit>:
        g : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
        writer_received(g, st, evt, cmd, boot, scope, force_tls, next => writer_loop(next, evt, cmd, boot, force_tls))

# Direct writer fixtures have no launch endpoint. Preserve their seam, but an
# unidentified writer cannot enable SASL on a later Dial.
def writer_go(st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), has_sasl: Bool) -> IO(Unit):
  writer_loop((st, AuthScope{"", 0, has_sasl}), evt, cmd, boot, False{})

def actor_boot_tls(+host: String, +port: U32, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +has_sasl: Bool, frames: U32, +force_tls: Bool) -> IO(Unit):
  dial_begin(host, port, force_tls, nick, gen, evt, boot, True{}, has_sasl,
    st => writer_loop((writer_adopt(st, Out.budget_frames(frames)), AuthScope{host, port, has_sasl}), evt, cmd, boot, force_tls))

# The startup fixture keeps its explicit plaintext entry point.
def actor_boot(+host: String, +port: U32, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +has_sasl: Bool, frames: U32) -> IO(Unit):
  actor_boot_tls(host, port, nick, gen, evt, cmd, boot, has_sasl, frames, False{})

def idle_start_tls(+evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), frames: U32, force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    boot : Chan(Boot) <- Chan.new(Boot, 1)
    writer_loop((Writer{None{}, 0, Nil{}, Out.budget_frames(frames), False{}}, AuthScope{"", 0, False{}}), evt, cmd, boot, force_tls)

def deferred_adopt(step: DeferredStep, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +budget: Out.Budget, +force_tls: Bool, next: Deferred -> IO(Unit)) -> IO(Unit):
  match step:
    case Waiting{state}: next(state)
    case Released{gen, scope}:
      writer_loop((Writer{None{}, gen, Nil{}, budget, False{}}, scope), evt, cmd, boot, force_tls)
    case Starting{PendingDial{host, port, nick}, gen, +scope, initial}:
      dial_begin(host, port, force_tls, nick, gen, evt, boot, initial, auth_scope_enabled(scope),
        got => writer_loop((writer_adopt(got, budget), scope), evt, cmd, boot, force_tls))

def deferred_received(got: Maybe<&1, Sess.NetCmd>, st: Deferred, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), boot: Chan(Boot), budget: Out.Budget, force_tls: Bool, next: Deferred -> IO(Unit)) -> IO(Unit):
  match got:
    case None{}:
      match st:
        case Deferred{_, gen, _}: writer_done(evt, gen)
    case Some{command}: deferred_adopt(deferred_command(command, st), evt, cmd, boot, budget, force_tls, next)

@unsafe
def deferred_loop(st: Deferred, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +budget: Out.Budget, +force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    got : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
    deferred_received(got, st, evt, cmd, boot, budget, force_tls,
      next => deferred_loop(next, evt, cmd, boot, budget, force_tls))

# Only the pref-enabled startup uses this permission gate. The existing direct
# launch and demo idle paths keep their registration and Boot behavior.
def deferred_start_tls(host: String, port: U32, nick: String, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), boot: Chan(Boot), has_sasl: Bool, frames: U32, force_tls: Bool) -> IO(Unit):
  deferred_loop(deferred_initial(host, port, nick, has_sasl), evt, cmd, boot, Out.budget_frames(frames), force_tls)
