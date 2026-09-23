# Net actor: Socket ownership, reader/idle loops, dial, send_line.
# UI lives in net.bend. Actor never calls UI (no mutual recursion).
import Base
import ./irc.bend as Irc
import ./session.bend as Sess
import ./dns.bend as Dns

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

def SEND_CAP() -> Nat:
  8n

def xs_nil(+xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def oct_nil(+xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

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

def post(+evt: Chan(Sess.UiMsg), +gen: U32, e: Sess.NetEvt) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.UiMsg, evt, Sess.FromNet{gen, e})
    return Unit{}

def reader_stop(dup: Socket, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- post(evt, gen, Sess.Eof{})
    Socket.close(dup)

def reader_xs.on(
  dup: Socket,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  +xs: List<&2, U32>,
  empty: Bool,
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match empty:
    case True{}:
      reader_stop(dup, evt, gen)
    case False{}:
      do IO<Unit>:
        Unit <- post(evt, gen, Sess.Chunk{xs})
        k(dup)

def reader_xs(
  dup: Socket,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  +xs: List<&2, U32>,
  k: Socket -> IO(Unit)
) -> IO(Unit):
  reader_xs.on(dup, evt, gen, xs, oct_nil(xs), k)

def reader_peer(
  dup: Socket,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  p: String & (U32 & List<&2, U32>),
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match p:
    case (_, rest):
      match rest:
        case (_, xs):
          reader_xs(dup, evt, gen, xs, k)

def reader_got(
  dup: Socket,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  got: Maybe<&1, String & (U32 & List<&2, U32>)>,
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match got:
    case None{}:
      k(dup)
    case Some{p}:
      reader_peer(dup, evt, gen, p, k)

def reader_r(
  dup: Socket,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  r: Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{_}:
      reader_stop(dup, evt, gen)
    case Done{got}:
      reader_got(dup, evt, gen, got, k)

def reader_pair(
  pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +evt: Chan(Sess.UiMsg),
  +gen: U32,
  k: Socket -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (dup, r):
      reader_r(dup, evt, gen, r, k)

@unsafe
def reader_run(dup: Socket, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Dns.recv_octets(dup, 4096)
    reader_pair(m, evt, gen, d => reader_run(d, evt, gen))

def flush_next(
  pair: Socket & Bool,
  +later: List<&2, String>,
  k: (Socket & List<&2, String>) -> IO(Socket & List<&2, String> & Bool)
) -> IO(Socket & List<&2, String> & Bool):
  match pair:
    case (sock, ok):
      match ok:
        case False{}:
          IO.pure(Socket & List<&2, String> & Bool, (sock, later, False{}))
        case True{}:
          k((sock, later))

def flush_some(
  sock: Socket,
  parts: List<&2, String> & List<&2, String>,
  k: (Socket & List<&2, String>) -> IO(Socket & List<&2, String> & Bool)
) -> IO(Socket & List<&2, String> & Bool):
  match parts:
    case (+now, later):
      do IO<Socket & List<&2, String> & Bool>:
        sent : Socket & Bool <- send_lines(sock, now)
        flush_next(sent, later, k)

def flush_on(
  sock: Socket,
  +xs: List<&2, String>,
  empty: Bool,
  k: (Socket & List<&2, String>) -> IO(Socket & List<&2, String> & Bool)
) -> IO(Socket & List<&2, String> & Bool):
  match empty:
    case True{}:
      IO.pure(Socket & List<&2, String> & Bool, (sock, xs, True{}))
    case False{}:
      flush_some(sock, split_at(xs, SEND_CAP()), k)

@unsafe
def flush(pack: Socket & List<&2, String>) -> IO(Socket & List<&2, String> & Bool):
  match pack:
    case (sock, +xs):
      flush_on(sock, xs, xs_nil(xs), p => flush(p))

def flush_xs(sock: Socket, +xs: List<&2, String>) -> IO(Socket & List<&2, String> & Bool):
  flush((sock, xs))

def writer_drop.r(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, _):
      Socket.close(sock)

def writer_drop(sock: Socket) -> IO(Unit):
  do IO<Unit>:
    pair : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.Socket.shutdown(sock)
    writer_drop.r(pair)

def writer_fail(+evt: Chan(Sess.UiMsg), +gen: U32, +msg: String) -> IO(Unit):
  post(evt, gen, Sess.Fail{msg})

type Boot is Data:
  Ready{}
  Down{msg: String}
  Timeout{}

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
  +nick: String,
  +boot: Chan(Boot),
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +gen: U32,
  +msg: String,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match live:
    case True{}:
      boot_down(boot, msg)
    case False{}:
      do IO<Unit>:
        Unit <- writer_fail(evt, gen, msg)
        k((None{}, gen, Nil{}))

def arm_ok(
  sock: Socket,
  dup: Socket,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.spawn(Unit, reader_run(dup, evt, gen))
    Unit <- arm_ready(live, boot)
    Unit <- post(evt, gen, Sess.Up{0})
    k((Some{sock}, gen, Nil{}))

def arm_dup(
  pair: Socket & Result<&1, &1, U32 & String, Socket>,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{e}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            arm_fail(live, nick, boot, evt, cmd, gen, err_msg(e), k)
        case Done{dup}:
          arm_ok(sock, dup, nick, gen, evt, cmd, boot, live, k)

def after_reg(
  pair: Socket & Bool,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (sock, ok):
      match ok:
        case False{}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            arm_fail(live, nick, boot, evt, cmd, gen, "register send failed", k)
        case True{}:
          do IO<Unit>:
            d : Socket & Result<&1, &1, U32 & String, Socket> <- Dns.Socket.dup(sock)
            arm_dup(d, nick, gen, evt, cmd, boot, live, k)

def after_conn(
  r: Result<&1, &1, (U32 & String), Socket>,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{e}:
      arm_fail(live, nick, boot, evt, cmd, gen, err_msg(e), k)
    case Done{sock}:
      do IO<Unit>:
        pair : Socket & Bool <- register(sock, nick)
        after_reg(pair, nick, gen, evt, cmd, boot, live, k)

def after_dns(
  r: Result<&1, &1, U32 & String, String>,
  +port: U32,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match r:
    case Fail{e}:
      arm_fail(live, nick, boot, evt, cmd, gen, err_msg(e), k)
    case Done{+ip}:
      do IO<Unit>:
        cr : Result<&1, &1, (U32 & String), Socket> <- TCP.connect(ip, port)
        after_conn(cr, nick, gen, evt, cmd, boot, live, k)

def dial_begin(
  +host: String,
  +port: U32,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  live: Bool,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve(host)
    after_dns(r, port, nick, gen, evt, cmd, boot, live, k)

def writer_end_go(
  trip: Socket & List<&2, String> & Bool,
  +evt: Chan(Sess.UiMsg),
  +gen: U32
) -> IO(Unit):
  match trip:
    case (sock, _, _):
      do IO<Unit>:
        Unit <- writer_drop(sock)
        post(evt, gen, Sess.Eof{})

# cmd closed: put leftover lines (QUIT) on the wire, then wake the reader.
def writer_end(
  sock: Socket,
  +pending: List<&2, String>,
  +evt: Chan(Sess.UiMsg),
  +gen: U32
) -> IO(Unit):
  do IO<Unit>:
    trip : Socket & List<&2, String> & Bool <- flush_xs(sock, pending)
    writer_end_go(trip, evt, gen)

def writer_flushed(
  trip: Socket & List<&2, String> & Bool,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match trip:
    case (sock, _, ok):
      match ok:
        case False{}:
          do IO<Unit>:
            Unit <- writer_drop(sock)
            Unit <- writer_fail(evt, gen, "send failed")
            k((None{}, gen, Nil{}))
        case True{}:
          k((Some{sock}, gen, Nil{}))

def writer_cont(
  sock: Socket,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +pending: List<&2, String>,
  +outs: List<&2, String>,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    trip : Socket & List<&2, String> & Bool <- flush_xs(sock, List.append(&2, String, pending, outs))
    writer_flushed(trip, gen, evt, k)

def writer_cmd(
  g: Maybe<&1, Sess.NetCmd>,
  sock: Socket,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +pending: List<&2, String>,
  +boot: Chan(Boot),
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      writer_end(sock, pending, evt, gen)
    case Some{c}:
      match c:
        case Sess.Cont{outs}:
          writer_cont(sock, gen, evt, pending, outs, k)
        case Sess.Dial{+host, port, dgen}:
          do IO<Unit>:
            Unit <- writer_drop(sock)
            dial_begin(host, port, nick, dgen, evt, cmd, boot, False{}, k)
        case Sess.Handoff{_}:
          k((Some{sock}, gen, pending))

def wait_cmd(
  g: Maybe<&1, Sess.NetCmd>,
  +nick: String,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  +gen: U32,
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      post(evt, gen, Sess.Eof{})
    case Some{c}:
      match c:
        case Sess.Dial{+host, port, dgen}:
          dial_begin(host, port, nick, dgen, evt, cmd, boot, False{}, k)
        case Sess.Cont{_}:
          k((None{}, gen, Nil{}))
        case Sess.Handoff{_}:
          k((None{}, gen, Nil{}))

def writer_go_s(
  s: Maybe<&1, Socket>,
  +gen: U32,
  +pending: List<&2, String>,
  +nick: String,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match s:
    case None{}:
      do IO<Unit>:
        g : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
        wait_cmd(g, nick, evt, cmd, boot, gen, k)
    case Some{sock}:
      do IO<Unit>:
        g : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, cmd)
        writer_cmd(g, sock, nick, gen, evt, cmd, pending, boot, k)

def writer_go_rest(
  rest: U32 & List<&2, String>,
  s: Maybe<&1, Socket>,
  +nick: String,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match rest:
    case (gen, +pending):
      writer_go_s(s, gen, pending, nick, evt, cmd, boot, k)

def writer_go_st(
  st: Maybe<&1, Socket> & U32 & List<&2, String>,
  +nick: String,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot),
  k: (Maybe<&1, Socket> & U32 & List<&2, String>) -> IO(Unit)
) -> IO(Unit):
  match st:
    case (s, rest):
      writer_go_rest(rest, s, nick, evt, cmd, boot, k)

@unsafe
def writer_go(
  st: Maybe<&1, Socket> & U32 & List<&2, String>,
  +nick: String,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot)
) -> IO(Unit):
  writer_go_st(st, nick, evt, cmd, boot, p => writer_go(p, nick, evt, cmd, boot))

def actor_boot(
  +host: String,
  +port: U32,
  +nick: String,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Boot)
) -> IO(Unit):
  dial_begin(host, port, nick, gen, evt, cmd, boot, True{}, st => writer_go(st, nick, evt, cmd, boot))

def idle_start(+nick: String, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  do IO<Unit>:
    boot : Chan(Boot) <- Chan.new(Boot, 1)
    writer_go((None{}, 0, Nil{}), nick, evt, cmd, boot)
