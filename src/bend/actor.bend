# Net actor: Connection ownership, reader/idle loops, dial, send_line.
# UI lives in net.bend. Actor never calls UI (no mutual recursion).
import Base
import ./irc.bend as Irc
import ./frame.bend as Fr
import ./session.bend as Sess
import ./dns.bend as Dns
import ./outbound.bend as Out
import ./transport.bend as Tr
import ./clock.bend as Clock

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

def send_line.traced(pair: Tr.Conn & Bool, +txn: U32) -> IO(Tr.Conn & Bool):
  match pair:
    case (sock, +ok):
      do IO<Tr.Conn & Bool>:
        Unit <- Clock.net_trace(5, txn, Bool.to_u32(ok))
        return (sock, ok)

def send_line(sock: Tr.Conn, +line: String, +txn: U32) -> IO(Tr.Conn & Bool):
  do IO<Tr.Conn & Bool>:
    m : Tr.Conn & Result<&1, &1, (U32 & String), Unit> <- Tr.send_for(sock, Irc.clamp_line(Irc.strip_ctl(line)) ++ "\r\n", 250)
    send_line.traced(send_go(m), txn)

type Sent is Data:
  Sent{count: Nat, ok: Bool}

def send_batch_go(xs: List<&2, String>, txns: List<&2, U32>, pair: Tr.Conn & Bool, +count: Nat) -> IO(Tr.Conn & Sent):
  match xs:
    case Nil{}:
      match pair:
        case (sock, ok):
          IO.pure(Tr.Conn & Sent, (sock, Sent{count, ok}))
    case Con{+h, t}:
      match txns:
        case Nil{}:
          match pair:
            case (sock, ok):
              match ok:
                case False{}:
                  IO.pure(Tr.Conn & Sent, (sock, Sent{count, False{}}))
                case True{}:
                  do IO<Tr.Conn & Sent>:
                    nxt : Tr.Conn & Bool <- send_line(sock, h, 0)
                    send_batch_go(t, Nil{}, nxt, Nat.add(count, 1n))
        case Con{+th, tt}:
          match pair:
            case (sock, ok):
              match ok:
                case False{}:
                  IO.pure(Tr.Conn & Sent, (sock, Sent{count, False{}}))
                case True{}:
                  do IO<Tr.Conn & Sent>:
                    nxt : Tr.Conn & Bool <- send_line(sock, h, th)
                    send_batch_go(t, tt, nxt, Nat.add(count, 1n))

# Count attempted lines. On failure the last attempt may have written only
# part of its line, so neither that line nor the remainder may be replayed.
def send_batch(sock: Tr.Conn, +xs: List<&2, String>, +txns: List<&2, U32>) -> IO(Tr.Conn & Sent):
  send_batch_go(xs, txns, (sock, True{}), 0n)

def sent_ok(pair: Tr.Conn & Sent) -> Tr.Conn & Bool:
  match pair:
    case (sock, Sent{_, ok}): (sock, ok)

# Bare sends (registration handshake): no batch txn, so stage 5 carries 0
# and never matches a real writer batch.
def send_lines(sock: Tr.Conn, +xs: List<&2, String>) -> IO(Tr.Conn & Bool):
  do IO<Tr.Conn & Bool>:
    pair : Tr.Conn & Sent <- send_batch(sock, xs, Out.repeat_txn(0, List.length(&2, String, xs)))
    return sent_ok(pair)

# JOIN is sent after 001 (live_go), not here.
def register(sock: Tr.Conn, +nick: String, has_sasl: Bool) -> IO(Tr.Conn & Bool):
  send_lines(sock, Sess.handshake_lines(nick, has_sasl))

def post(+evt: Chan(Sess.UiMsg), +gen: U32, e: Sess.NetEvt) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, Sess.UiMsg, Unit> <- Chan.send(Sess.UiMsg, evt, Sess.FromNet{gen, e})
    return Unit{}

# The reader shadows the UI framer over the same verbatim bytes and owns the
# single live wire PONG: it answers completed PINGs ahead of UI paints (and
# ahead of its own Chunk post, so a full evt queue cannot delay the reply).
# The UI still frames, feeds, and paints every line, but never answers PING.
# Each reply carries its read generation; the writer drops a Pong whose gen
# mismatches Writer.gen, exactly like a stale Pump.
def pong_cons.on(+pong: String, +acc: List<&2, String>, empty: Bool) -> List<&2, String>:
  match empty:
    case True{}: acc
    case False{}: pong <> acc

def pong_cons(+pong: String, +acc: List<&2, String>) -> List<&2, String>:
  pong_cons.on(pong, acc, String.is_empty(pong))

def reader_pongs.go(fuel: Nat, +lines: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+f:
      match lines:
        case Nil{}:
          List.reverse(&2, String, acc)
        case Con{h, t}:
          reader_pongs.go(f, t, pong_cons(Irc.pong_for(h), acc))

def reader_pongs(+lines: List<&2, String>) -> List<&2, String>:
  reader_pongs.go(List.length(&2, String, lines), lines, Nil{})

# The reply carries this read's request ID (when the read holds PINGs) and
# the Chunk carries the same ID, so the reply, post, dequeue, receive, and
# send match by numeric identity. A read without PINGs posts an
# unidentified chunk (req 0), which never joins a PONG branch. The reply
# still goes out ahead of the Chunk post. An exhausted reply (req 0: range
# or gen2048 exhaustion) still sends its PONG bytes but emits NO stage-6
# identity mark and posts an unidentified chunk, so no correlatable
# 6/1/2/4/5 req0 chain exists for any resolver to accept (L1-src7 GATE Z).
def reader_answered.pong(exhausted: Bool, +pongs: List<&2, String>, +xs: List<&2, U32>, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +gen: U32, +req: U32, rem2: List<&2, U32>, drop2: Bool, dup: Tr.Conn, k: Tr.Conn -> ReadFr -> IO(Unit)) -> IO(Unit):
  match exhausted:
    case True{}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Pong{gen, pongs, 0})
        Unit <- post(evt, gen, Sess.Chunk{xs, 0})
        Unit <- Clock.net_trace(1, 0, 0)
        k(dup)(ReadFr{drop2, rem2, 0})
    case False{}:
      do IO<Unit>:
        _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Pong{gen, pongs, req})
        Unit <- Clock.net_trace(6, req, 0)
        Unit <- post(evt, gen, Sess.Chunk{xs, req})
        Unit <- Clock.net_trace(1, req, 0)
        k(dup)(ReadFr{drop2, rem2, Out.next_pong_txn(req)})

def reader_answered.go(+pongs: List<&2, String>, +xs: List<&2, U32>, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +gen: U32, +req: U32, rem2: List<&2, U32>, drop2: Bool, dup: Tr.Conn, empty: Bool, k: Tr.Conn -> ReadFr -> IO(Unit)) -> IO(Unit):
  match empty:
    case True{}:
      do IO<Unit>:
        Unit <- post(evt, gen, Sess.Chunk{xs, 0})
        Unit <- Clock.net_trace(1, 0, 0)
        k(dup)(ReadFr{drop2, rem2, req})
    case False{}:
      reader_answered.pong(U32.is_zero(req), pongs, xs, evt, cmd, gen, req, rem2, drop2, dup, k)

type ReadFr is Data:
  ReadFr{drop: Bool, rem: List<&2, U32>, req: U32}

def reader_answered(framed: List<&2, String> & List<&2, U32> & Bool, +xs: List<&2, U32>, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +gen: U32, +req: U32, dup: Tr.Conn, k: Tr.Conn -> ReadFr -> IO(Unit)) -> IO(Unit):
  match framed:
    case (lines, rem2, drop2):
      +pongs = reader_pongs(lines)
      reader_answered.go(pongs, xs, evt, cmd, gen, req, rem2, drop2, dup, List.is_empty(&2, String, pongs), k)

def reader_frame_answer(+fr: ReadFr, +xs: List<&2, U32>, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +gen: U32, dup: Tr.Conn, k: Tr.Conn -> ReadFr -> IO(Unit)) -> IO(Unit):
  match fr:
    case ReadFr{drop, rem, req}:
      framed = Fr.push_ex(drop, rem, xs)
      reader_answered(framed, xs, evt, cmd, gen, req, dup, k)

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
  +cmd: Chan(Sess.NetCmd),
  +fr: ReadFr,
  k: Tr.Conn -> ReadFr -> IO(Unit)
) -> IO(Unit):
  match empty:
    case True{}:
      reader_stop(dup, evt, gen)
    case False{}:
      reader_frame_answer(fr, xs, evt, cmd, gen, dup, k)

def reader_xs(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  +xs: List<&2, U32>,
  +cmd: Chan(Sess.NetCmd),
  +fr: ReadFr,
  k: Tr.Conn -> ReadFr -> IO(Unit)
) -> IO(Unit):
  reader_xs.on(dup, evt, gen, xs, List.is_empty(&2, U32, xs), cmd, fr, k)

def reader_peer(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  p: String & (U32 & List<&2, U32>),
  +cmd: Chan(Sess.NetCmd),
  +fr: ReadFr,
  k: Tr.Conn -> ReadFr -> IO(Unit)
) -> IO(Unit):
  match p:
    case (_, rest):
      match rest:
        case (_, xs):
          reader_xs(dup, evt, gen, xs, cmd, fr, k)

def reader_got(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  got: Maybe<&1, String & (U32 & List<&2, U32>)>,
  +cmd: Chan(Sess.NetCmd),
  +fr: ReadFr,
  k: Tr.Conn -> ReadFr -> IO(Unit)
) -> IO(Unit):
  match got:
    case None{}:
      k(dup)(fr)
    case Some{p}:
      reader_peer(dup, evt, gen, p, cmd, fr, k)

def reader_r(
  dup: Tr.Conn,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  r: Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +cmd: Chan(Sess.NetCmd),
  +fr: ReadFr,
  k: Tr.Conn -> ReadFr -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{(code, _)}:
      do IO<Unit>:
        Unit <- post(evt, gen, Sess.NetFail{"receive failed (OS " ++ U32.show(code) ++ ")"})
        Tr.close(dup)
    case Done{got}:
      reader_got(dup, evt, gen, got, cmd, fr, k)

def reader_pair(
  pair: Tr.Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  +cmd: Chan(Sess.NetCmd),
  +fr: ReadFr,
  k: Tr.Conn -> ReadFr -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (dup, r):
      reader_r(dup, evt, gen, r, cmd, fr, k)

@unsafe
def reader_run(dup: Tr.Conn, +evt: Chan(Sess.UiMsg), +gen: U32, +cmd: Chan(Sess.NetCmd), +fr: ReadFr) -> IO(Unit):
  do IO<Unit>:
    m : Tr.Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Tr.recv_octets(dup, 65536)
    reader_pair(m, evt, gen, cmd, fr, d => fr2 => reader_run(d, evt, gen, cmd, fr2))

# Announce Up before any data or EOF. This reader task may park on evt;
# the socket-owning writer must remain free to consume cmd and shut down.
def reader_start(dup: Tr.Conn, +evt: Chan(Sess.UiMsg), +gen: U32, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  do IO<Unit>:
    Unit <- post(evt, gen, Sess.Up{})
    reader_run(dup, evt, gen, cmd, ReadFr{False{}, Nil{}, Out.pong_first(gen)})

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
  Booted{}
  Down{msg: String}

def boot_down(+boot: Chan(Boot), +msg: String) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, Boot, Unit> <- Chan.send(Boot, boot, Down{msg})
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
        _ : Result<&1, &1, Boot, Unit> <- Chan.send(Boot, boot, Booted{})
        return Unit{}

type AuthScope is Data:
  AuthScope{host: String, port: U32, enabled: Bool}

type DialReady is Type:
  DialReady{state: Maybe<&1, Tr.Conn> & U32 & List<&2, String>, scope: AuthScope}

def arm_fail(
  live: Bool,
  +boot: Chan(Boot),
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  +msg: String,
  +scope: AuthScope,
  k: DialReady -> IO(Unit)
) -> IO(Unit):
  match live:
    case True{}:
      do IO<Unit>:
        Unit <- boot_down(boot, msg)
        k(DialReady{(None{}, gen, Nil{}), scope})
    case False{}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, writer_fail(evt, gen, msg))
        k(DialReady{(None{}, gen, Nil{}), scope})

def dial_replay_failed(sock: Tr.Conn, +evt: Chan(Sess.UiMsg), +gen: U32, next: Maybe<&1, Tr.Conn> -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- writer_drop(sock)
    Unit <- IO.spawn(Unit, writer_fail(evt, gen, "send timed out or failed during dial admission replay"))
    next(None{})

def dial_replay_sent(pair: Tr.Conn & Bool, +gen: U32, +evt: Chan(Sess.UiMsg), next: Maybe<&1, Tr.Conn> -> IO(Unit)) -> IO(Unit):
  match pair:
    case (sock, ok):
      match ok:
        case False{}: dial_replay_failed(sock, evt, gen, next)
        case True{}: next(Some{sock})

def dial_replay_pong(same: Bool, sock: Tr.Conn, +pongs: List<&2, String>, +gen: U32, +evt: Chan(Sess.UiMsg), next: Maybe<&1, Tr.Conn> -> IO(Unit)) -> IO(Unit):
  match same:
    case False{}: next(Some{sock})
    case True{}:
      do IO<Unit>:
        pair : Tr.Conn & Bool <- send_lines(sock, pongs)
        dial_replay_sent(pair, gen, evt, next)

def dial_replay_step(c: Sess.NetCmd, sock: Tr.Conn, +gen: U32, +evt: Chan(Sess.UiMsg), next: Maybe<&1, Tr.Conn> -> IO(Unit)) -> IO(Unit):
  match c:
    case Sess.Cont{+outs}:
      do IO<Unit>:
        pair : Tr.Conn & Bool <- send_lines(sock, outs)
        dial_replay_sent(pair, gen, evt, next)
    case Sess.Pong{pgen, +pongs, _}:
      dial_replay_pong(U32.is_eq(pgen, gen), sock, pongs, gen, evt, next)
    case _:
      next(Some{sock})

def dial_replay_run(fuel: Nat, current: Maybe<&1, Tr.Conn>, +kept: List<&2, Sess.NetCmd>, +gen: U32, +evt: Chan(Sess.UiMsg), k: Maybe<&1, Tr.Conn> -> IO(Unit)) -> IO(Unit):
  match fuel:
    case 0n: k(current)
    case 1n+p:
      match current:
        case None{}: k(None{})
        case Some{sock}:
          match kept:
            case Nil{}: k(Some{sock})
            case Con{c, t}: dial_replay_step(c, sock, gen, evt, next => dial_replay_run(p, next, t, gen, evt, k))

def dial_replay(+kept: List<&2, Sess.NetCmd>, sock: Tr.Conn, +gen: U32, +evt: Chan(Sess.UiMsg), k: Maybe<&1, Tr.Conn> -> IO(Unit)) -> IO(Unit):
  dial_replay_run(List.length(&2, Sess.NetCmd, kept), Some{sock}, List.reverse(&2, Sess.NetCmd, kept), gen, evt, k)

def arm_ok(
  sock: Tr.Conn,
  dup: Tr.Conn,
  +kept: List<&2, Sess.NetCmd>,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  +cmd: Chan(Sess.NetCmd),
  live: Bool,
  +scope: AuthScope,
  k: DialReady -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    Unit <- arm_ready(live, boot)
    Unit <- IO.spawn(Unit, reader_start(dup, evt, gen, cmd))
    dial_replay(kept, sock, gen, evt, final => k(DialReady{(final, gen, Nil{}), scope}))

def arm_dup(
  pair: Tr.Conn & Result<&1, &1, U32 & String, Tr.Conn>,
  +kept: List<&2, Sess.NetCmd>,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  +cmd: Chan(Sess.NetCmd),
  live: Bool,
  +scope: AuthScope,
  k: DialReady -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{e}:
          do IO<Unit>:
            Unit <- Tr.close(sock)
            arm_fail(live, boot, evt, gen, err_msg(e), scope, k)
        case Done{dup}:
          arm_ok(sock, dup, kept, gen, evt, boot, cmd, live, scope, k)

def after_reg(
  pair: Tr.Conn & Bool,
  +kept: List<&2, Sess.NetCmd>,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  +cmd: Chan(Sess.NetCmd),
  live: Bool,
  +scope: AuthScope,
  k: DialReady -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (sock, ok):
      match ok:
        case False{}:
          do IO<Unit>:
            Unit <- Tr.close(sock)
            arm_fail(live, boot, evt, gen, "register send failed", scope, k)
        case True{}:
          do IO<Unit>:
            d : Tr.Conn & Result<&1, &1, U32 & String, Tr.Conn> <- Tr.dup(sock)
            arm_dup(d, kept, gen, evt, boot, cmd, live, scope, k)

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
  Writer{socket: Maybe<&1, Tr.Conn>, gen: U32, pending: List<&2, String>, pending_txn: List<&2, U32>, next_txn: U32, budget: Out.Budget, scheduled: Bool}

def writer_adopt(st: Maybe<&1, Tr.Conn> & U32 & List<&2, String>, budget: Out.Budget, +next_txn: U32) -> Writer:
  match st:
    case (sock, (gen, pending)): Writer{sock, gen, pending, Nil{}, next_txn, budget, False{}}

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
    case Writer{sock, +gen, +pending, +pending_txn, _, _, _}:
      match sock:
        case None{}: writer_done(evt, gen)
        case Some{s}:
          do IO<Unit>:
            pair : Tr.Conn & Sent <- send_batch(s, pending, pending_txn)
            finish_sent(pair, evt, gen)

def pump_send(+cmd: Chan(Sess.NetCmd), gen: U32) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, Sess.NetCmd, Unit> <- Chan.send(Sess.NetCmd, cmd, Sess.Pump{gen})
    return Unit{}

# Never await a self-send on the socket-owning task: cmd may already be full.
# One scheduled flag permits at most one outstanding pump for this generation.
def writer_schedule(need: Bool, st: Writer, +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match need:
    case False{}: k(st)
    case True{}:
      match st:
        case Writer{sock, +gen, +pending, +pending_txn, +next_txn, budget, _}:
          do IO<Unit>:
            Unit <- IO.spawn(Unit, pump_send(cmd, gen))
            k(Writer{sock, gen, pending, pending_txn, next_txn, budget, True{}})

def writer_sent(pair: Tr.Conn & Sent, +gen: U32, +later: List<&2, String>, +later_txn: List<&2, U32>, +budget: Out.Budget, +scheduled: Bool, +total: Nat, +next_txn: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match pair:
    case (sock, Sent{+count, ok}):
      match ok:
        case False{}:
          do IO<Unit>:
            Unit <- writer_drop(sock)
            Unit <- IO.spawn(Unit, writer_fail(evt, gen, "send timed out or failed; " ++ Nat.show(Nat.add(1n, Nat.sub(total, count))) ++ " queued/uncertain lines were discarded without retry"))
            k(Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}})
        case True{}:
          writer_schedule(Bool.not(scheduled) && Bool.not(List.is_empty(&2, String, later)) && Out.budget_open(budget), Writer{Some{sock}, gen, later, later_txn, next_txn, budget, scheduled}, cmd, k)

def writer_batch(sock: Tr.Conn, +gen: U32, +now: List<&2, String>, +now_txn: List<&2, U32>, +later: List<&2, String>, +later_txn: List<&2, U32>, +budget: Out.Budget, +scheduled: Bool, +total: Nat, +next_txn: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    pair : Tr.Conn & Sent <- send_batch(sock, now, now_txn)
    writer_sent(pair, gen, later, later_txn, budget, scheduled, total, next_txn, evt, cmd, k)

def writer_split(plan: Out.Batch, +all_txn: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match plan:
    case Out.Batch{+now, _, _}:
      Out.split_at_u32(all_txn, List.length(&2, String, now))

def writer_split_go(split: List<&2, U32> & List<&2, U32>, sock: Tr.Conn, +gen: U32, +now: List<&2, String>, +later: List<&2, String>, +budget: Out.Budget, +scheduled: Bool, +total: Nat, +next_txn: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match split:
    case (+now_txn, +later_txn):
      writer_batch(sock, gen, now, now_txn, later, later_txn, budget, scheduled, total, next_txn, evt, cmd, k)

def writer_queued(sock: Tr.Conn, +gen: U32, +plan: Out.Batch, +all_txn: List<&2, U32>, +scheduled: Bool, +total: Nat, +next_txn: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match plan:
    case Out.Batch{+now, +later, +budget}:
      split = writer_split(plan, all_txn)
      writer_split_go(split, sock, gen, now, later, budget, scheduled, total, next_txn, evt, cmd, k)

def writer_queue(st: Writer, +outs: List<&2, String>, +txn: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match st:
    case Writer{sock, +gen, +pending, +pending_txn, +next_txn, budget, +scheduled}:
      match sock:
        case None{}: k(Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}})
        case Some{s}:
          +all = List.append(&2, String, pending, outs)
          +all_txn = List.append(&2, U32, pending_txn, Out.repeat_txn(txn, List.length(&2, String, outs)))
          +plan = Out.batch(all, budget)
          # The Cont/Pong mark txn (txn) may be a PONG-space request ID; the
          # low batch counter always advances from next_txn so PONG marks
          # never corrupt Cont batch IDs. For Cont, txn equals next_txn.
          +advanced = Out.next_batch_txn(next_txn)
          +has_new = Bool.not(List.is_empty(&2, String, outs))
          +next = Bool.pick(U32, has_new, advanced, next_txn)
          writer_queued(s, gen, plan, all_txn, scheduled, List.length(&2, String, all), next, evt, cmd, k)

def writer_pump(same: Bool, st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match same:
    case False{}: k(st)
    case True{}:
      match st:
        case Writer{sock, gen, +pending, +pending_txn, +next_txn, budget, _}:
          writer_queue(Writer{sock, gen, pending, pending_txn, next_txn, budget, False{}}, Nil{}, 0, evt, cmd, k)

# A stale reader reply is dropped exactly like a stale Pump: only the
# writer-receive mark fires for an accepted same-generation Pong. PONG marks
# carry the Pong's request ID shared with its stage-6 reply (identity, not
# order); the low Cont counter in st is preserved by writer_queue. An
# unidentified Pong (txn 0: reader exhaustion) still queues its bytes but
# emits NO stage-4 mark, so its bare send can never complete a PONG branch
# (L1-src7 GATE Z).
def writer_pong.traced(unidentified: Bool, st: Writer, +pongs: List<&2, String>, +txn: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match unidentified:
    case True{}:
      writer_queue(st, pongs, txn, evt, cmd, k)
    case False{}:
      do IO<Unit>:
        Unit <- Clock.net_trace(4, txn, 0)
        writer_queue(st, pongs, txn, evt, cmd, k)

def writer_pong(same: Bool, st: Writer, +pongs: List<&2, String>, +txn: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: Writer -> IO(Unit)) -> IO(Unit):
  match same:
    case False{}: k(st)
    case True{}:
      writer_pong.traced(U32.is_zero(txn), st, pongs, txn, evt, cmd, k)

# In-flight Dial admission (L1-src5 GATE 1, L1-src6 GATE 2): after the async
# setup (TCP dial + TLS upgrade) completes but BEFORE any registration, the
# writer drains cmd for a queued newer Dial. A drain hit abandons the
# just-established socket unregistered (the old peer sees EOF with zero
# bytes) and dials the winner instead; only drained commands AFTER the last
# Dial replay on the winner in order (pre-Dial Cont stays with its abandoned
# setup, never migrates). The winner setup re-enters the same drain, so a
# third Dial queued during a held winner setup abandons the winner before it
# registers (last gen wins). A Drop kept with no newer Dial also abandons
# before register (zero peer bytes); post-winner Drop is honored the same
# way after adopt (closes, later Cont unsent). The drain ends at a self-sent
# Pump{setup_gen} sentinel (the writer's own pump idiom; live Pumps always
# carry an adopted gen, so only the sentinel matches) or at cmd close
# (shutdown still finishes) or at fuel exhaustion (falls back to the
# sequential path). No Socket/Conn crosses a channel; the only spawn is the
# one-shot sentinel send. Pure steps are JS-pinned.
type QueuedDial is Data:
  QueuedDial{host: String, port: U32, gen: U32, nick: String}

type AdmitAcc is Data:
  AdmitAcc{latest: Maybe<&2, QueuedDial>, dials: List<&2, QueuedDial>, kept: List<&2, Sess.NetCmd>, closed: Bool, dropped: Bool}

type DialCarry is Data:
  DialCarry{kept: List<&2, Sess.NetCmd>, closed: Bool, dropped: Bool}

def admit_keep(+c: Sess.NetCmd, +acc: AdmitAcc) -> AdmitAcc & Bool:
  match acc:
    case AdmitAcc{+latest, +dials, +kept, +closed, +dropped}:
      (AdmitAcc{latest, dials, c <> kept, closed, dropped}, False{})

def admit_drop(+acc: AdmitAcc) -> AdmitAcc & Bool:
  match acc:
    case AdmitAcc{+latest, +dials, +kept, +closed, _}:
      (AdmitAcc{latest, dials, Sess.Drop{} <> kept, closed, True{}}, False{})

def admit_dial(+host: String, +port: U32, +gen: U32, +nick: String, +acc: AdmitAcc) -> AdmitAcc & Bool:
  match acc:
    case AdmitAcc{_, +dials, _, +closed, _}:
      +qd: QueuedDial = QueuedDial{host, port, gen, nick}
      +grown = List.append(&2, QueuedDial, dials, qd <> Nil{})
      # Newer Dial clears kept and any prior Drop; winner path abandons this sock.
      (AdmitAcc{Some{qd}, grown, Nil{}, closed, False{}}, False{})

def admit_pump(stop: Bool, +acc: AdmitAcc) -> AdmitAcc & Bool:
  match stop:
    case True{}: (acc, True{})
    case False{}: (acc, False{})

def admit_consider(c: Sess.NetCmd, +setup_gen: U32, +acc: AdmitAcc) -> AdmitAcc & Bool:
  match c:
    case Sess.Cont{+outs}:
      admit_keep(Sess.Cont{outs}, acc)
    case Sess.Pong{+pgen, +pongs, +req}:
      admit_keep(Sess.Pong{pgen, pongs, req}, acc)
    case Sess.Dial{+host, +port, +gen, +nick}:
      admit_dial(host, port, gen, nick, acc)
    case Sess.Drop{}:
      admit_drop(acc)
    case Sess.Pump{+pgen}:
      admit_pump(U32.is_eq(pgen, setup_gen), acc)
    case Sess.OpenUrl{_}:
      (acc, False{})
    case Sess.Begin{_}:
      (acc, False{})
    case Sess.Search{_, _, _, _, _, _, _, _, _}:
      (acc, False{})

def writer_drain_next(stop: Bool, +acc: AdmitAcc, k: AdmitAcc -> IO(AdmitAcc)) -> IO(AdmitAcc):
  match stop:
    case True{}:
      IO.pure(AdmitAcc, acc)
    case False{}:
      k(acc)

def writer_drain_decided(pair: AdmitAcc & Bool, k: AdmitAcc -> IO(AdmitAcc)) -> IO(AdmitAcc):
  match pair:
    case (acc, stop):
      writer_drain_next(stop, acc, k)

def writer_drain_got(got: Maybe<&1, Sess.NetCmd>, +setup_gen: U32, +acc: AdmitAcc, k: AdmitAcc -> IO(AdmitAcc)) -> IO(AdmitAcc):
  match got:
    case None{}:
      match acc:
        case AdmitAcc{+latest, +dials, +kept, _, +dropped}:
          IO.pure(AdmitAcc, AdmitAcc{latest, dials, kept, True{}, dropped})
    case Some{c}:
      writer_drain_decided(admit_consider(c, setup_gen, acc), k)

def writer_drain(fuel: Nat, +cmd: Chan(Sess.NetCmd), +setup_gen: U32, +acc: AdmitAcc) -> IO(AdmitAcc):
  match fuel:
    case 0n:
      IO.pure(AdmitAcc, acc)
    case 1n+p:
      do IO<AdmitAcc>:
        got : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
        writer_drain_got(got, setup_gen, acc, next => writer_drain(p, cmd, setup_gen, next))

def writer_admit_scope(fuel: Nat, +dials: List<&2, QueuedDial>, +scope: AuthScope) -> AuthScope:
  match fuel:
    case 0n:
      scope
    case 1n+p:
      match dials:
        case Nil{}:
          scope
        case Con{QueuedDial{+host, +port, _, _}, t}:
          writer_admit_scope(p, t, auth_scope_dial(scope, host, port))

def writer_kept_drop(honor: Bool, st: Writer, k: Writer -> IO(Unit)) -> IO(Unit):
  match honor:
    case False{}:
      k(st)
    case True{}:
      match st:
        case Writer{sock, gen, _, _, +next_txn, budget, _}:
          do IO<Unit>:
            Unit <- close_socket(sock)
            k(Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}})

def writer_kept_step(c: Sess.NetCmd, st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), honor_drop: Bool, k: Writer -> IO(Unit)) -> IO(Unit):
  match c:
    case Sess.Cont{+outs}:
      match st:
        case Writer{sock, +gen, +pending, +pending_txn, +next_txn, budget, +scheduled}:
          do IO<Unit>:
            Unit <- Clock.net_trace(4, next_txn, 0)
            writer_queue(Writer{sock, gen, pending, pending_txn, next_txn, budget, scheduled}, outs, next_txn, evt, cmd, k)
    case Sess.Pong{pgen, +pongs, +req}:
      match st:
        case Writer{sock, +gen, +pending, +pending_txn, +next_txn, budget, +scheduled}:
          writer_pong(U32.is_eq(pgen, gen), Writer{sock, gen, pending, pending_txn, next_txn, budget, scheduled}, pongs, req, evt, cmd, k)
    case Sess.OpenUrl{_}: k(st)
    case Sess.Begin{_}: k(st)
    case Sess.Pump{pgen}:
      match st:
        case Writer{sock, +gen, +pending, +pending_txn, +next_txn, budget, +scheduled}:
          writer_pump(U32.is_eq(pgen, gen), Writer{sock, gen, pending, pending_txn, next_txn, budget, scheduled}, evt, cmd, k)
    case Sess.Drop{}:
      writer_kept_drop(honor_drop, st, k)
    case Sess.Dial{_, _, _, _}: k(st)
    case Sess.Search{_, _, _, _, _, _, _, _, _}: k(st)

def writer_kept(fuel: Nat, +kept: List<&2, Sess.NetCmd>, st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +honor_drop: Bool, k: Writer -> IO(Unit)) -> IO(Unit):
  match fuel:
    case 0n:
      k(st)
    case 1n+p:
      match kept:
        case Nil{}: k(st)
        case Con{c, t}:
          writer_kept_step(c, st, evt, cmd, honor_drop, next => writer_kept(p, t, next, evt, cmd, honor_drop, k))

def writer_admit_done(+closed: Bool, st: Writer, +scope: AuthScope, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match closed:
    case True{}:
      writer_finish(st, evt)
    case False{}:
      writer_pump(True{}, st, evt, cmd, next => k((next, scope)))

def writer_admit_failed(e: U32 & String, +gen: U32, +evt: Chan(Sess.UiMsg), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.spawn(Unit, writer_fail(evt, gen, err_msg(e)))
    k((Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}}, scope))

def writer_admit_dup_r(r: Result<&1, &1, U32 & String, Tr.Conn>, sock: Tr.Conn, +kept: List<&2, Sess.NetCmd>, +closed: Bool, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match r:
    case Fail{e}:
      do IO<Unit>:
        Unit <- Tr.close(sock)
        Unit <- IO.spawn(Unit, writer_fail(evt, gen, err_msg(e)))
        writer_kept(List.length(&2, Sess.NetCmd, kept), List.reverse(&2, Sess.NetCmd, kept), Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}}, evt, cmd, True{}, final => writer_admit_done(closed, final, scope, evt, cmd, k))
    case Done{dup}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, reader_start(dup, evt, gen, cmd))
        writer_kept(List.length(&2, Sess.NetCmd, kept), List.reverse(&2, Sess.NetCmd, kept), writer_adopt((Some{sock}, gen, Nil{}), budget, next_txn), evt, cmd, True{}, final => writer_admit_done(closed, final, scope, evt, cmd, k))

def writer_admit_dup(d: Tr.Conn & Result<&1, &1, U32 & String, Tr.Conn>, +kept: List<&2, Sess.NetCmd>, +closed: Bool, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match d:
    case (sock, r):
      writer_admit_dup_r(r, sock, kept, closed, gen, evt, cmd, scope, budget, next_txn, k)

def writer_admit_reg_ok(ok: Bool, sock: Tr.Conn, +kept: List<&2, Sess.NetCmd>, +closed: Bool, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match ok:
    case False{}:
      do IO<Unit>:
        Unit <- Tr.close(sock)
        Unit <- IO.spawn(Unit, writer_fail(evt, gen, "register send failed"))
        writer_kept(List.length(&2, Sess.NetCmd, kept), List.reverse(&2, Sess.NetCmd, kept), Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}}, evt, cmd, True{}, final => writer_admit_done(closed, final, scope, evt, cmd, k))
    case True{}:
      do IO<Unit>:
        d : Tr.Conn & Result<&1, &1, U32 & String, Tr.Conn> <- Tr.dup(sock)
        writer_admit_dup(d, kept, closed, gen, evt, boot, cmd, scope, budget, next_txn, k)

def writer_admit_reg(pair: Tr.Conn & Bool, +kept: List<&2, Sess.NetCmd>, +closed: Bool, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (sock, ok):
      writer_admit_reg_ok(ok, sock, kept, closed, gen, evt, boot, cmd, scope, budget, next_txn, k)

# Drop during setup sets AdmitAcc.dropped (and stays in kept). A newer Dial
# clears both. Before register with no winning Dial: close with zero peer
# bytes, then replay kept on None so later Cont stays unsent.
def writer_admit_dropped(+kept: List<&2, Sess.NetCmd>, +closed: Bool, sock: Tr.Conn, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Tr.close(sock)
    writer_kept(List.length(&2, Sess.NetCmd, kept), List.reverse(&2, Sess.NetCmd, kept), Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}}, evt, cmd, True{}, final => writer_admit_done(closed, final, scope, evt, cmd, k))

def writer_admit_register(+kept: List<&2, Sess.NetCmd>, +closed: Bool, sock: Tr.Conn, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    pair : Tr.Conn & Bool <- register(sock, nick, auth_scope_enabled(scope))
    writer_admit_reg(pair, kept, closed, gen, evt, boot, cmd, scope, budget, next_txn, k)

def writer_admit_single_open(closed: Bool, +kept: List<&2, Sess.NetCmd>, sock: Tr.Conn, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match closed:
    case True{}:
      writer_admit_dropped(kept, True{}, sock, gen, evt, cmd, scope, budget, next_txn, k)
    case False{}:
      writer_admit_register(kept, False{}, sock, nick, gen, evt, boot, cmd, scope, budget, next_txn, k)

def writer_admit_single_go(drop: Bool, +kept: List<&2, Sess.NetCmd>, +closed: Bool, sock: Tr.Conn, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match drop:
    case True{}:
      writer_admit_dropped(kept, closed, sock, gen, evt, cmd, scope, budget, next_txn, k)
    case False{}:
      writer_admit_single_open(closed, kept, sock, nick, gen, evt, boot, cmd, scope, budget, next_txn, k)

def writer_admit_single(+kept: List<&2, Sess.NetCmd>, +closed: Bool, dropped: Bool, sock: Tr.Conn, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  writer_admit_single_go(dropped, kept, closed, sock, nick, gen, evt, boot, cmd, scope, budget, next_txn, k)

# Winner replay honors Drop (L1-src6 GATE 2a): a queued Drop after the winner
# closes the adopted socket and a later Cont finds None (unsent). The live
# recursive winner re-enters the drain via retry and replays via single
# (also honor True); this entry stays pinned with honor True.
def writer_admit_won(pair: Maybe<&1, Tr.Conn> & U32 & List<&2, String>, +kept: List<&2, Sess.NetCmd>, +closed: Bool, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  writer_kept(List.length(&2, Sess.NetCmd, kept), List.reverse(&2, Sess.NetCmd, kept), writer_adopt(pair, budget, next_txn), evt, cmd, True{}, final => writer_admit_done(closed, final, scope, evt, cmd, k))

def writer_admit_winner(+h2: String, +p2: U32, +g2: U32, +n2: String, +scope: AuthScope, +kept: List<&2, Sess.NetCmd>, +closed: Bool, sock: Tr.Conn, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Tr.close(sock)
    retry(h2, p2, g2, n2, scope, kept, closed, k)

def writer_admit_latest(+latest: Maybe<&2, QueuedDial>, +dials: List<&2, QueuedDial>, +kept: List<&2, Sess.NetCmd>, +closed: Bool, dropped: Bool, sock: Tr.Conn, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match latest:
    case None{}:
      writer_admit_single(kept, closed, dropped, sock, nick, gen, evt, boot, cmd, scope, budget, next_txn, k)
    case Some{QueuedDial{+h2, +p2, +g2, +n2}}:
      writer_admit_winner(h2, p2, g2, n2, writer_admit_scope(List.length(&2, QueuedDial, dials), dials, scope), kept, closed, sock, k, retry)

def writer_admit_decide(+acc: AdmitAcc, sock: Tr.Conn, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match acc:
    case AdmitAcc{+latest, +dials, +kept, +closed, +dropped}:
      writer_admit_latest(latest, dials, kept, closed, dropped, sock, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, k, retry)

def writer_peek.cont(pair: AdmitAcc & Bool, k: AdmitAcc -> IO(AdmitAcc)) -> IO(AdmitAcc):
  match pair:
    case (+acc, +stop):
      match stop:
        case True{}: IO.pure(AdmitAcc, acc)
        case False{}: k(acc)

def writer_peek.closed(+acc: AdmitAcc) -> IO(AdmitAcc & Bool):
  match acc:
    case AdmitAcc{+latest, +dials, +kept, _, +dropped}:
      IO.pure(AdmitAcc & Bool, (AdmitAcc{latest, dials, kept, True{}, dropped}, True{}))

def writer_peek.ready(got: Maybe<&1, Sess.NetCmd>, +setup_gen: U32, +acc: AdmitAcc) -> IO(AdmitAcc & Bool):
  match got:
    case None{}: writer_peek.closed(acc)
    case Some{+c}: IO.pure(AdmitAcc & Bool, admit_consider(c, setup_gen, acc))

def writer_peek.polled(p: Poll<&1, &1, Maybe<&1, Sess.NetCmd>, Unit>, +setup_gen: U32, +acc: AdmitAcc) -> IO(AdmitAcc & Bool):
  match p:
    case Wait{_}: IO.pure(AdmitAcc & Bool, (acc, True{}))
    case Ready{got}: writer_peek.ready(got, setup_gen, acc)

# Non-blocking. A blocking recv here would park the writer when Dial is the
# only queued command. Drop already waiting is visible before TLS starts.
def writer_peek(+fuel: Nat, +cmd: Chan(Sess.NetCmd), +setup_gen: U32, +acc: AdmitAcc) -> IO(AdmitAcc):
  match fuel:
    case 0n: IO.pure(AdmitAcc, acc)
    case 1n+p:
      do IO<AdmitAcc>:
        pol : Poll<&1, &1, Maybe<&1, Sess.NetCmd>, Unit> <- Chan.try_recv(Sess.NetCmd, cmd, 0)
        pair : AdmitAcc & Bool <- writer_peek.polled(pol, setup_gen, acc)
        writer_peek.cont(pair, next => writer_peek(p, cmd, setup_gen, next))

def dial_cancel(live: Bool, +boot: Chan(Boot), sock: Socket, +gen: U32, +scope: AuthScope, k: DialReady -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Socket.close(sock)
    Unit <- arm_ready(live, boot)
    k(DialReady{(None{}, gen, Nil{}), scope})

def dial_conn_cancel(live: Bool, +boot: Chan(Boot), sock: Tr.Conn, +gen: U32, +scope: AuthScope, k: DialReady -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Tr.close(sock)
    Unit <- arm_ready(live, boot)
    k(DialReady{(None{}, gen, Nil{}), scope})

def after_conn_open(closed: Bool, dropped: Bool, +kept: List<&2, Sess.NetCmd>, sock: Tr.Conn, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, k: DialReady -> IO(Unit)) -> IO(Unit):
  match closed:
    case True{}:
      dial_conn_cancel(live, boot, sock, gen, scope, k)
    case False{}:
      match dropped:
        case True{}:
          dial_conn_cancel(live, boot, sock, gen, scope, k)
        case False{}:
          do IO<Unit>:
            pair : Tr.Conn & Bool <- register(sock, nick, auth_scope_enabled(scope))
            after_reg(pair, kept, gen, evt, boot, cmd, live, scope, k)

def after_conn_latest.open(+latest: Maybe<&2, QueuedDial>, +dials: List<&2, QueuedDial>, +kept: List<&2, Sess.NetCmd>, dropped: Bool, sock: Tr.Conn, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match latest:
    case Some{QueuedDial{+h2, +p2, +g2, +n2}}:
      do IO<Unit>:
        Unit <- Tr.close(sock)
        retry(h2, p2, g2, n2, writer_admit_scope(List.length(&2, QueuedDial, dials), dials, scope),
          DialCarry{kept, False{}, dropped}, k)
    case None{}:
      after_conn_open(False{}, dropped, kept, sock, nick, gen, evt, boot, cmd, live, scope, k)

def after_conn_latest(+latest: Maybe<&2, QueuedDial>, +dials: List<&2, QueuedDial>, +kept: List<&2, Sess.NetCmd>, +closed: Bool, dropped: Bool, sock: Tr.Conn, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match closed:
    case True{}:
      after_conn_open(True{}, dropped, kept, sock, nick, gen, evt, boot, cmd, live, scope, k)
    case False{}:
      after_conn_latest.open(latest, dials, kept, dropped, sock, nick, gen, evt, boot, cmd, live, scope, k, retry)

def after_conn_decide(+acc: AdmitAcc, sock: Tr.Conn, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match acc:
    case AdmitAcc{+latest, +dials, +kept, +closed, +dropped}:
      after_conn_latest(latest, dials, kept, closed, dropped, sock, nick, gen, evt, boot, cmd, live, scope, k, retry)

# Tr.upgrade has succeeded, but registration is still not admitted. Drain to
# the same sentinel used by writer_admit so Drop, cmd-close, or a newer Dial
# wins before CAP/NICK/USER can reach this connection.
def after_conn(r: Result<&1, &1, (U32 & String), Tr.Conn>, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, +acc0: AdmitAcc, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match r:
    case Fail{e}:
      arm_fail(live, boot, evt, gen, err_msg(e), scope, k)
    case Done{sock}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, pump_send(cmd, gen))
        acc : AdmitAcc <- writer_drain(65n, cmd, gen, acc0)
        after_conn_decide(acc, sock, nick, gen, evt, boot, cmd, live, scope, k, retry)

def dial_after_open(closed: Bool, sock: Socket, +host: String, +port: U32, force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, +acc0: AdmitAcc, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match closed:
    case True{}: dial_cancel(live, boot, sock, gen, scope, k)
    case False{}:
      do IO<Unit>:
        cr : Result<&1, &1, (U32 & String), Tr.Conn> <- Tr.upgrade(sock, host, force_tls)
        after_conn(cr, nick, gen, evt, boot, cmd, live, scope, acc0, k, retry)

def dial_after_plain(dropped: Bool, +closed: Bool, sock: Socket, +host: String, +port: U32, force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, +acc0: AdmitAcc, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match dropped:
    case True{}: dial_cancel(live, boot, sock, gen, scope, k)
    case False{}: dial_after_open(closed, sock, host, port, force_tls, nick, gen, evt, boot, cmd, live, scope, acc0, k, retry)

def dial_after_latest.open(latest: Maybe<&2, QueuedDial>, +dials: List<&2, QueuedDial>, +kept: List<&2, Sess.NetCmd>, dropped: Bool, sock: Socket, +host: String, +port: U32, force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, +acc0: AdmitAcc, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match latest:
    case Some{QueuedDial{+h2, +p2, +g2, +n2}}:
      do IO<Unit>:
        Unit <- Socket.close(sock)
        retry(h2, p2, g2, n2, writer_admit_scope(List.length(&2, QueuedDial, dials), dials, scope),
          DialCarry{kept, False{}, dropped}, k)
    case None{}:
      dial_after_plain(dropped, False{}, sock, host, port, force_tls, nick, gen, evt, boot, cmd, live, scope, acc0, k, retry)

def dial_after_latest(latest: Maybe<&2, QueuedDial>, +dials: List<&2, QueuedDial>, +kept: List<&2, Sess.NetCmd>, dropped: Bool, +closed: Bool, sock: Socket, +host: String, +port: U32, force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, +acc0: AdmitAcc, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match closed:
    case True{}: dial_cancel(live, boot, sock, gen, scope, k)
    case False{}:
      dial_after_latest.open(latest, dials, kept, dropped, sock, host, port, force_tls, nick, gen, evt, boot, cmd, live, scope, acc0, k, retry)

def dial_after_acc(+acc: AdmitAcc, sock: Socket, +host: String, +port: U32, force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match acc:
    case AdmitAcc{+latest, +dials, +kept, +closed, +dropped}:
      dial_after_latest(latest, dials, kept, dropped, closed, sock, host, port, force_tls, nick, gen, evt, boot, cmd, live, scope, acc, k, retry)

def dial_after_sock(pair: Socket & String, +host: String, +port: U32, force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, +carry: DialCarry, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (sock, _):
      match carry:
        case DialCarry{+kept, +closed, +dropped}:
          do IO<Unit>:
            acc : AdmitAcc <- writer_peek(65n, cmd, gen, AdmitAcc{None{}, Nil{}, kept, closed, dropped})
            dial_after_acc(acc, sock, host, port, force_tls, nick, gen, evt, boot, cmd, live, scope, k, retry)

def dial_after_dual(r: Result<&1, &1, U32 & String, Socket & String>, +host: String, +port: U32, force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, +carry: DialCarry, k: DialReady -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> DialCarry -> (DialReady -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match r:
    case Fail{e}:
      arm_fail(live, boot, evt, gen, err_msg(e), scope, k)
    case Done{pair}:
      dial_after_sock(pair, host, port, force_tls, nick, gen, evt, boot, cmd, live, scope, carry, k, retry)

def dial_begin.go(+fuel: Nat, +host: String, +port: U32, +force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +live: Bool, +scope: AuthScope, +carry: DialCarry, k: DialReady -> IO(Unit)) -> IO(Unit):
  match fuel:
    case 0n: arm_fail(live, boot, evt, gen, "dial", scope, k)
    case 1n+p:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, Socket & String> <- Dns.dial_dual(host, port, 1000)
        dial_after_dual(r, host, port, force_tls, nick, gen, evt, boot, cmd, live, scope, carry, k,
          h2 => p2 => g2 => n2 => scope2 => carry2 => k2 =>
            dial_begin.go(p, h2, p2, force_tls, n2, g2, evt, boot, cmd, live, scope2, carry2, k2))

def dial_begin(+host: String, +port: U32, force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), live: Bool, +scope: AuthScope, k: DialReady -> IO(Unit)) -> IO(Unit):
  dial_begin.go(8n, host, port, force_tls, nick, gen, evt, boot, cmd, live, scope,
    DialCarry{Nil{}, False{}, False{}}, k)

def writer_admit_conn(r: Result<&1, &1, (U32 & String), Tr.Conn>, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, +acc0: AdmitAcc, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match r:
    case Fail{e}:
      writer_admit_failed(e, gen, evt, scope, budget, next_txn, k)
    case Done{sock}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, pump_send(cmd, gen))
        acc : AdmitAcc <- writer_drain(65n, cmd, gen, acc0)
        writer_admit_decide(acc, sock, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, k, retry)

def writer_admit_raw_drop(+kept: List<&2, Sess.NetCmd>, +closed: Bool, sock: Socket, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Socket.close(sock)
    writer_kept(List.length(&2, Sess.NetCmd, kept), List.reverse(&2, Sess.NetCmd, kept), Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}}, evt, cmd, True{}, final => writer_admit_done(closed, final, scope, evt, cmd, k))

def writer_admit_raw_winner(+h2: String, +p2: U32, +g2: U32, +n2: String, +scope: AuthScope, +kept: List<&2, Sess.NetCmd>, +closed: Bool, sock: Socket, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Socket.close(sock)
    retry(h2, p2, g2, n2, scope, kept, closed, k)

def writer_admit_sock.open(closed: Bool, sock: Socket, +host: String, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, +kept: List<&2, Sess.NetCmd>, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match closed:
    case True{}: writer_admit_raw_drop(kept, True{}, sock, gen, evt, cmd, scope, budget, next_txn, k)
    case False{}:
      do IO<Unit>:
        cr : Result<&1, &1, (U32 & String), Tr.Conn> <- Tr.upgrade(sock, host, force_tls)
        writer_admit_conn(cr, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, AdmitAcc{None{}, Nil{}, kept, False{}, False{}}, k, retry)

def writer_admit_sock.plain(dropped: Bool, sock: Socket, +host: String, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, +kept: List<&2, Sess.NetCmd>, +closed: Bool, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match dropped:
    case True{}: writer_admit_raw_drop(kept, closed, sock, gen, evt, cmd, scope, budget, next_txn, k)
    case False{}: writer_admit_sock.open(closed, sock, host, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, kept, k, retry)

def writer_admit_sock.latest(latest: Maybe<&2, QueuedDial>, dropped: Bool, +dials: List<&2, QueuedDial>, sock: Socket, +host: String, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, +kept: List<&2, Sess.NetCmd>, +closed: Bool, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match latest:
    case Some{QueuedDial{+h2, +p2, +g2, +n2}}:
      writer_admit_raw_winner(h2, p2, g2, n2, writer_admit_scope(List.length(&2, QueuedDial, dials), dials, scope), kept, closed, sock, k, retry)
    case None{}:
      writer_admit_sock.plain(dropped, sock, host, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, kept, closed, k, retry)

def writer_admit_sock.acc(+acc: AdmitAcc, sock: Socket, +host: String, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match acc:
    case AdmitAcc{+latest, +dials, +kept, +closed, +dropped}:
      writer_admit_sock.latest(latest, dropped, dials, sock, host, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, kept, closed, k, retry)

def writer_admit_sock(pair: Socket & String, +host: String, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, +kept0: List<&2, Sess.NetCmd>, +closed0: Bool, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (sock, _):
      do IO<Unit>:
        acc : AdmitAcc <- writer_peek(65n, cmd, gen, AdmitAcc{None{}, Nil{}, kept0, closed0, False{}})
        writer_admit_sock.acc(acc, sock, host, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, k, retry)

def writer_admit_dual(r: Result<&1, &1, U32 & String, Socket & String>, +host: String, +nick: String, +gen: U32, +force_tls: Bool, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, budget: Out.Budget, +next_txn: U32, +kept0: List<&2, Sess.NetCmd>, +closed0: Bool, k: (Writer & AuthScope) -> IO(Unit), retry: String -> U32 -> U32 -> String -> AuthScope -> List<&2, Sess.NetCmd> -> Bool -> ((Writer & AuthScope) -> IO(Unit)) -> IO(Unit)) -> IO(Unit):
  match r:
    case Fail{e}:
      writer_admit_failed(e, gen, evt, scope, budget, next_txn, k)
    case Done{pair}:
      writer_admit_sock(pair, host, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, kept0, closed0, k, retry)

# The winner re-enters through the retry continuation (leaves-up: Bend
# forbids the winner forward-calling begin). Begin passes itself as that
# continuation, so nth-Dial admission stays truly recursive; each re-entry
# abandons one setup for a strictly newer queued Dial and terminates when
# the drain finds no newer Dial (data-dependent, hence @unsafe like the
# other actor loops).
@unsafe
def writer_admit_begin(+host: String, +port: U32, +force_tls: Bool, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +boot: Chan(Boot), +cmd: Chan(Sess.NetCmd), +scope: AuthScope, +budget: Out.Budget, +next_txn: U32, +kept0: List<&2, Sess.NetCmd>, +closed0: Bool, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Socket & String> <- Dns.dial_dual(host, port, 1000)
    writer_admit_dual(r, host, nick, gen, force_tls, evt, boot, cmd, scope, budget, next_txn, kept0, closed0, k, h2 => p2 => g2 => n2 => scope2 => kept2 => closed2 => k2 => writer_admit_begin(h2, p2, force_tls, n2, g2, evt, boot, cmd, scope2, budget, next_txn, kept2, closed2, k2))

# Pre-setup supersede guard (L1-src3 GATE 2, kept): a Dial for the generation
# the writer is already on is superseded by the live connection while
# connected (drop: the writer keeps its exact state, no teardown, no re-dial
# flap). Strictly-newer Dials always execute; anything else executes
# fail-open (unreachable via the monotonic UI, and equality-only so
# generation wrap still dials). Queued-newer admission after setup is owned
# by the L1-src5 drain above, not this predicate. Pure; JS-pinned.
def dial_superseded(+dial_gen: U32, +writer_gen: U32, connected: Bool) -> Bool:
  connected && U32.is_eq(dial_gen, writer_gen)

# Dial replaces the live socket. Flush the healthy pending FIFO first (same
# send_batch contract as writer_finish) without posting WriterDone; admit
# begins with an empty queue for the new generation.
def writer_dial_flush_drop(pair: Tr.Conn & Sent) -> IO(Unit):
  match pair:
    case (sock, _): writer_drop(sock)

def writer_dial_flushed(
  pair: Tr.Conn & Sent,
  +host: String,
  +port: U32,
  +force_tls: Bool,
  +nick: String,
  +dial_gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  +cmd: Chan(Sess.NetCmd),
  +scope: AuthScope,
  +budget: Out.Budget,
  +next_txn: U32,
  k: (Writer & AuthScope) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    Unit <- writer_dial_flush_drop(pair)
    writer_admit_begin(host, port, force_tls, nick, dial_gen, evt, boot, cmd, scope, budget, next_txn, Nil{}, False{}, k)

def writer_dial_flush(
  sock: Maybe<&1, Tr.Conn>,
  +pending: List<&2, String>,
  +pending_txn: List<&2, U32>,
  +host: String,
  +port: U32,
  +force_tls: Bool,
  +nick: String,
  +dial_gen: U32,
  +evt: Chan(Sess.UiMsg),
  +boot: Chan(Boot),
  +cmd: Chan(Sess.NetCmd),
  +scope: AuthScope,
  +budget: Out.Budget,
  +next_txn: U32,
  k: (Writer & AuthScope) -> IO(Unit)
) -> IO(Unit):
  match sock:
    case None{}:
      writer_admit_begin(host, port, force_tls, nick, dial_gen, evt, boot, cmd, scope, budget, next_txn, Nil{}, False{}, k)
    case Some{s}:
      do IO<Unit>:
        pair : Tr.Conn & Sent <- send_batch(s, pending, pending_txn)
        writer_dial_flushed(pair, host, port, force_tls, nick, dial_gen, evt, boot, cmd, scope, budget, next_txn, k)

def writer_dial_some(
  redundant: Bool,
  w: Writer,
  +host: String,
  +port: U32,
  +dial_gen: U32,
  +nick: String,
  +scope: AuthScope,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  force_tls: Bool,
  k: (Writer & AuthScope) -> IO(Unit)
) -> IO(Unit):
  match redundant:
    case True{}: k((w, scope))
    case False{}:
      match w:
        case Writer{sock, _, +pending, +pending_txn, +next_txn, budget, _}:
          +next_scope = auth_scope_dial(scope, host, port)
          writer_dial_flush(sock, pending, pending_txn, host, port, force_tls, nick, dial_gen, evt, boot, cmd, next_scope, budget, next_txn, k)

def writer_command(c: Sess.NetCmd, st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +scope: AuthScope, force_tls: Bool, k: (Writer & AuthScope) -> IO(Unit)) -> IO(Unit):
  match c:
    case Sess.Cont{+outs}:
      match st:
        case Writer{sock, +gen, +pending, +pending_txn, +next_txn, budget, +scheduled}:
          do IO<Unit>:
            Unit <- Clock.net_trace(4, next_txn, 0)
            writer_queue(Writer{sock, gen, pending, pending_txn, next_txn, budget, scheduled}, outs, next_txn, evt, cmd, next => k((next, scope)))
    case Sess.Pong{pgen, +pongs, +req}:
      match st:
        case Writer{sock, +gen, +pending, +pending_txn, +next_txn, budget, +scheduled}:
          writer_pong(U32.is_eq(pgen, gen), Writer{sock, gen, pending, pending_txn, next_txn, budget, scheduled}, pongs, req, evt, cmd, next => k((next, scope)))
    case Sess.OpenUrl{_}: k((st, scope))
    case Sess.Begin{_}: k((st, scope))
    case Sess.Search{_, _, _, _, _, _, _, _, _}: k((st, scope))
    case Sess.Pump{pgen}:
      match st:
        case Writer{sock, +gen, +pending, +pending_txn, +next_txn, budget, +scheduled}:
          writer_pump(U32.is_eq(pgen, gen), Writer{sock, gen, pending, pending_txn, next_txn, budget, scheduled}, evt, cmd, next => k((next, scope)))
    case Sess.Drop{}:
      match st:
        case Writer{sock, gen, _, _, +next_txn, budget, _}:
          do IO<Unit>:
            Unit <- close_socket(sock)
            k((Writer{None{}, gen, Nil{}, Nil{}, next_txn, budget, False{}}, scope))
    case Sess.Dial{+host, +port, +gen, +nick}:
      match st:
        case Writer{sock, +writer_gen, +pending, +pending_txn, +next_txn, budget, +scheduled}:
          match sock:
            case None{}:
              writer_dial_some(dial_superseded(gen, writer_gen, False{}), Writer{None{}, writer_gen, pending, pending_txn, next_txn, budget, scheduled}, host, port, gen, nick, scope, evt, cmd, boot, force_tls, k)
            case Some{s}:
              writer_dial_some(dial_superseded(gen, writer_gen, True{}), Writer{Some{s}, writer_gen, pending, pending_txn, next_txn, budget, scheduled}, host, port, gen, nick, scope, evt, cmd, boot, force_tls, k)

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

# Same fixture seam with the TLS upgrade the live writer uses. A Drop already
# queued when TCP connect returns must close the raw socket before this runs.
def writer_go_tls(st: Writer, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), has_sasl: Bool) -> IO(Unit):
  writer_loop((st, AuthScope{"", 0, has_sasl}), evt, cmd, boot, True{})

def actor_boot_adopt(ready: DialReady, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), frames: U32, force_tls: Bool) -> IO(Unit):
  match ready:
    case DialReady{st, scope}:
      writer_loop((writer_adopt(st, Out.budget_frames(frames), 1), scope), evt, cmd, boot, force_tls)

def actor_boot_tls(+host: String, +port: U32, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +has_sasl: Bool, frames: U32, +force_tls: Bool) -> IO(Unit):
  dial_begin(host, port, force_tls, nick, gen, evt, boot, cmd, True{}, AuthScope{host, port, has_sasl},
    pair => actor_boot_adopt(pair, evt, cmd, boot, frames, force_tls))

# The startup fixture keeps its explicit plaintext entry point.
def actor_boot(+host: String, +port: U32, +nick: String, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +has_sasl: Bool, frames: U32) -> IO(Unit):
  actor_boot_tls(host, port, nick, gen, evt, cmd, boot, has_sasl, frames, False{})

def idle_start_tls(+evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), frames: U32, force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    boot : Chan(Boot) <- Chan.new(Boot, 1)
    writer_loop((Writer{None{}, 0, Nil{}, Nil{}, 1, Out.budget_frames(frames), False{}}, AuthScope{"", 0, False{}}), evt, cmd, boot, force_tls)

def deferred_started(ready: DialReady, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), budget: Out.Budget, force_tls: Bool) -> IO(Unit):
  match ready:
    case DialReady{got, scope}:
      writer_loop((writer_adopt(got, budget, 1), scope), evt, cmd, boot, force_tls)

def deferred_adopt(step: DeferredStep, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Boot), +budget: Out.Budget, +force_tls: Bool, next: Deferred -> IO(Unit)) -> IO(Unit):
  match step:
    case Waiting{state}: next(state)
    case Released{gen, scope}:
      writer_loop((Writer{None{}, gen, Nil{}, Nil{}, 1, budget, False{}}, scope), evt, cmd, boot, force_tls)
    case Starting{PendingDial{host, port, nick}, gen, +scope, initial}:
      dial_begin(host, port, force_tls, nick, gen, evt, boot, cmd, initial, scope,
        pair => deferred_started(pair, evt, cmd, boot, budget, force_tls))

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
