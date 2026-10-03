# DNS A/AAAA lookup. Pure wire lives in dns_wire.bend (A) and ipv6.bend (AAAA).
# Live path: UDP.bind + send_octets + recv_octets (not UDP.send_to String).
# Names try AAAA before A (V6.query_order); each attempt keeps the existing
# per-query bounds, timeouts, resends, and TCP fallback. Valid inner IPv6
# literals resolve directly; colon garbage still fails with "ipv6".
# Brackets stay at parse_any: resolve takes inner text or DNS names only.
# Resolver is the first IPv4 nameserver in /etc/resolv.conf, else fails closed.
# Transaction ids are 16-bit.
# Owned fixtures use explicit nameserver ports via the _at entry points
# (same wait/TCP chains, same bounds; production passes DNS_PORT 53 and
# still requires exact ns+port peer equality). Dual dial (v6 then v4) is
# TCP-connect fallback only, preserving the original hostname for TLS;
# integrator wires actor dial_begin to it (see dns_query.bend header).
import Base
import ./dns_wire.bend as Wire
import ./dns_query.bend as Dq
import ./ipv6.bend as V6
import ./clock.bend as Clock

def DNS_PORT() -> U32:
  53

def WAIT() -> Nat:
  80n

def TCP_TIMEOUT_MS() -> U32:
  3000

def tick_ms_on(fast: Bool) -> U32:
  match fast:
    case True{}:
      10
    case False{}:
      50

def tick_ms(+n: Nat) -> U32:
  tick_ms_on(Nat.is_lt(n, 8n))

def need_resend(+n: Nat) -> Bool:
  Nat.is_eq(n, 16n) || Nat.is_eq(n, 32n) || Nat.is_eq(n, 48n) || Nat.is_eq(n, 64n)

# TCP reader. Parks until the socket is readable (IO_READ). n = 0 is EOF
# (Some of an empty list). EAGAIN parks again.
law recv_octets:
  Socket -> U32 -> IO(Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>)

def recv_octets(sock, max):
  import "../ffi/dns_ffi.c"

# DNS only. Same bytes as recv_octets, but EAGAIN is None so wait_ans
# can sleep, resend, and hit its fuel timeout.
law recv_nb:
  Socket -> U32 -> IO(Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>)

def recv_nb(sock, max):
  import "../ffi/dns_ffi.c"

# dup the fd. The result Socket is a different descriptor. Close it once.
law Socket.dup:
  Socket -> IO(Socket & Result<&1, &1, U32 & String, Socket>)

def Socket.dup(sock):
  import "../ffi/dns_ffi.c"

# SHUT_RDWR on this descriptor. Does not close it. Wakes a reader parked
# on a dup of the same open file description.
law Socket.shutdown:
  Socket -> IO(Socket & Result<&1, &1, U32 & String, Unit>)

def Socket.shutdown(sock):
  import "../ffi/dns_ffi.c"

# Bounded native operations own the wait and its deadline. IO.within alone
# cannot cancel a parked connect/write and would leave its Socket alive.
law TCP.connect_for:
  String -> U32 -> U32 -> IO(Result<&1, &1, U32 & String, Socket>)

def TCP.connect_for(host, port, timeout_ms):
  import "../ffi/dns_ffi.c"

law TCP.send_for:
  Socket -> String -> U32 -> IO(Socket & Result<&1, &1, U32 & String, Unit>)

def TCP.send_for(sock, text, timeout_ms):
  import "../ffi/dns_ffi.c"

law send_octets_for:
  Socket -> String -> U32 -> List<&2, U32> -> U32 -> IO(Socket & Result<&1, &1, U32 & String, Unit>)

def send_octets_for(sock, host, port, xs, timeout_ms):
  import "../ffi/dns_ffi.c"

# UDP and TCP share the same checked, deadline-owned byte sender.
def send_octets(sock: Socket, +host: String, port: U32, xs: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, Unit>):
  send_octets_for(sock, host, port, xs, TCP_TIMEOUT_MS())

def fail_close(sock: Socket, +msg: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    Unit <- Socket.close(sock)
    return Wire.err(msg)

def wait_sleep(
  sock: Socket,
  +n: Nat,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    Unit <- IO.sleep(tick_ms(n))
    k(sock)

def wait_sent(
  pair: Socket & Result<&1, &1, U32 & String, Unit>,
  +n: Nat,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          fail_close(sock, "send")
        case Done{_}:
          wait_sleep(sock, n, k)

def wait_idle(
  resend: Bool,
  sock: Socket,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +n: Nat,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match resend:
    case False{}:
      wait_sleep(sock, n, k)
    case True{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- send_octets(sock, ns, dport, q)
        wait_sent(sent, n, k)

def wait_take(
  sock: Socket,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +n: Nat,
  t: Wire.Take,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match t:
    case Wire.Miss{}:
      wait_idle(need_resend(n), sock, ns, dport, q, n, k)
    case Wire.HitOk{+ip}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- Socket.close(sock)
        return Done{ip}
    case Wire.HitErr{+msg}:
      fail_close(sock, msg)

# Query-type dispatch lives in dns_query.bend (pure, JS-pinned); the
# wait/TCP chains below only thread the selector and nameserver port.
def wait_port(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +n: Nat,
  +aaaa: Bool,
  +phost: String,
  rest: U32 & List<&2, U32>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match rest:
    case (port, xs):
      wait_take(sock, ns, dport, q, n, Dq.take_for_at(aaaa, ns, dport, id, qhost, phost, port, xs), k)

def wait_peer(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +n: Nat,
  +aaaa: Bool,
  p: String & (U32 & List<&2, U32>),
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match p:
    case (+phost, rest):
      wait_port(sock, id, qhost, ns, dport, q, n, aaaa, phost, rest, k)

def wait_got(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +n: Nat,
  +aaaa: Bool,
  got: Maybe<&1, String & (U32 & List<&2, U32>)>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match got:
    case None{}:
      wait_idle(need_resend(n), sock, ns, dport, q, n, k)
    case Some{p}:
      wait_peer(sock, id, qhost, ns, dport, q, n, aaaa, p, k)

def wait_r(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +n: Nat,
  +aaaa: Bool,
  r: Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "recv")
    case Done{got}:
      wait_got(sock, id, qhost, ns, dport, q, n, aaaa, got, k)

def wait_poll(
  pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +id: U32,
  +qhost: String,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +n: Nat,
  +aaaa: Bool,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      wait_r(sock, id, qhost, ns, dport, q, n, aaaa, r, k)

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed wait_ans
def wait_ans(
  fuel: Nat,
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +n: Nat,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match fuel:
    case 0n:
      fail_close(sock, "timeout")
    case 1n+p:
      do IO<Result<&1, &1, U32 & String, String>>:
        m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- recv_nb(sock, 4096)
        wait_poll(m, id, qhost, ns, dport, q, n, aaaa, s2 => wait_ans(p, s2, id, qhost, ns, dport, q, Nat.add(n, 1n), aaaa))

def after_send_r(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +aaaa: Bool,
  r: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "send")
    case Done{_}:
      wait_ans(WAIT(), sock, id, qhost, ns, dport, q, 0n, aaaa)

def after_send(
  pair: Socket & Result<&1, &1, U32 & String, Unit>,
  +id: U32,
  +qhost: String,
  +ns: String,
  +dport: U32,
  +q: List<&2, U32>,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      after_send_r(sock, id, qhost, ns, dport, q, aaaa, r)

def after_bind(
  r: Result<&1, &1, U32 & String, Socket>,
  +q: List<&2, U32>,
  +id: U32,
  +host: String,
  +ns: String,
  +dport: U32,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("bind"))
    case Done{sock}:
      do IO<Result<&1, &1, U32 & String, String>>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- send_octets(sock, ns, dport, q)
        after_send(sent, id, host, ns, dport, q, aaaa)

def tcp_idle(sock: Socket, acc: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    Unit <- IO.sleep(10)
    k(sock, acc)

def tcp_frame(sock: Socket, +id: U32, +host: String, +acc: List<&2, U32>, +aaaa: Bool, frame: Wire.TcpFrame, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match frame:
    case Wire.TcpInvalid{}: fail_close(sock, "tcp length")
    case Wire.TcpMore{}: k(sock, acc)
    case Wire.TcpPayload{+xs}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- Socket.close(sock)
        return Dq.tcp_parse(aaaa, id, host, xs)

def tcp_chunk(sock: Socket, +id: U32, +host: String, acc: List<&2, U32>, +aaaa: Bool, xs: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match xs:
    case Nil{}: fail_close(sock, "tcp eof")
    case Con{h, t}:
      +all = List.append(&2, U32, acc, h <> t)
      tcp_frame(sock, id, host, all, aaaa, Wire.tcp_packet(all), k)

def tcp_poll(pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>, +id: U32, +host: String, acc: List<&2, U32>, +aaaa: Bool, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}: fail_close(sock, "tcp recv")
        case Done{got}:
          match got:
            case None{}: tcp_idle(sock, acc, k)
            case Some{(_, (_, xs))}: tcp_chunk(sock, id, host, acc, aaaa, xs, k)

def tcp_deadline(expired: Bool, sock: Socket, +id: U32, +host: String, acc: List<&2, U32>, +aaaa: Bool, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match expired:
    case True{}: fail_close(sock, "tcp timeout")
    case False{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        got : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- recv_nb(sock, 4096)
        tcp_poll(got, id, host, acc, aaaa, k)

# The monotonic deadline is shared by every chunk, so slow/trickling peers
# cannot extend it. Fuel is only a second, structural guardrail.
def tcp_wait(fuel: Nat, sock: Socket, +id: U32, +host: String, +start: U32, acc: List<&2, U32>, +aaaa: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match fuel:
    case 0n: fail_close(sock, "tcp timeout")
    case 1n+p:
      do IO<Result<&1, &1, U32 & String, String>>:
        now : U32 <- Clock.millis()
        tcp_deadline(U32.is_ge(U32.sub(now, start), TCP_TIMEOUT_MS()), sock, id, host, acc, aaaa, s2 => buf => tcp_wait(p, s2, id, host, start, buf, aaaa))

def lookup_tcp_sent(
  sock: Socket,
  +id: U32,
  +host: String,
  +aaaa: Bool,
  r: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "tcp send")
    case Done{_}:
      do IO<Result<&1, &1, U32 & String, String>>:
        start : U32 <- Clock.millis()
        tcp_wait(U32.to_nat(65538), sock, id, host, start, Nil{}, aaaa)

def lookup_tcp_send(
  pair: Socket & Result<&1, &1, U32 & String, Unit>,
  +id: U32,
  +host: String,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      lookup_tcp_sent(sock, id, host, aaaa, r)

def lookup_tcp_sock(
  sock: Socket,
  +id: U32,
  +host: String,
  +q: List<&2, U32>,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    sent : Socket & Result<&1, &1, U32 & String, Unit> <- send_octets(sock, "", 0, Wire.tcp_frame(q))
    lookup_tcp_send(sent, id, host, aaaa)

def lookup_tcp_conn(
  cr: Result<&1, &1, U32 & String, Socket>,
  +id: U32,
  +host: String,
  +q: List<&2, U32>,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match cr:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("tcp connect"))
    case Done{sock}:
      lookup_tcp_sock(sock, id, host, q, aaaa)

def lookup_tcp(+host: String, +ns: String, +dport: U32, +id: U32, +q: List<&2, U32>, +aaaa: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    cr : Result<&1, &1, U32 & String, Socket> <- TCP.connect_for(ns, dport, TCP_TIMEOUT_MS())
    lookup_tcp_conn(cr, id, host, q, aaaa)

def lookup_fallback(
  +host: String,
  +ns: String,
  +dport: U32,
  +id: U32,
  +q: List<&2, U32>,
  r: Result<&1, &1, U32 & String, String>,
  is_tc: Bool,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match is_tc:
    case True{}:
      lookup_tcp(host, ns, dport, id, q, aaaa)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, String>, r)

def lookup_res(
  +host: String,
  +ns: String,
  +dport: U32,
  +id: U32,
  +q: List<&2, U32>,
  r: Result<&1, &1, U32 & String, String>,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Done{+ip}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{ip})
    case Fail{e}:
      match e:
        case (_, +msg):
          lookup_fallback(host, ns, dport, id, q, Fail{e}, String.eq(msg, "tc"), aaaa)

def lookup_q(
  enc: Result<&1, &1, U32 & String, List<&2, U32>>,
  +id: U32,
  +host: String,
  +ns: String,
  +dport: U32,
  +aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match enc:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case Done{+q}:
      do IO<Result<&1, &1, U32 & String, String>>:
        br : Result<&1, &1, U32 & String, Socket> <- UDP.bind("0.0.0.0", 0)
        r : Result<&1, &1, U32 & String, String> <- after_bind(br, q, id, host, ns, dport, aaaa)
        lookup_res(host, ns, dport, id, q, r, aaaa)

def lookup_n(+host: String, +ns: String, +dport: U32, +n: U32, +aaaa: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  +id = Wire.txid_of(n)
  lookup_q(Dq.encode_for(aaaa, id, host), id, host, ns, dport, aaaa)

def lookup_rnd(+host: String, +ns: String, +dport: U32, rnd: Result<&1, &1, U32 & String, U32>, +aaaa: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match rnd:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("random"))
    case Done{n}:
      lookup_n(host, ns, dport, n, aaaa)

def load_ns_text(r: Result<&1, &1, U32 & String, String>, f: File) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{e}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- File.close(f)
        return Fail{e}
    case Done{+text}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- File.close(f)
        return Wire.nameserver_of(text)

def load_ns_read(pair: File & Result<&1, &1, U32 & String, String>) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (f, r):
      load_ns_text(r, f)

def load_ns_open(r: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("no nameserver"))
    case Done{f}:
      do IO<Result<&1, &1, U32 & String, String>>:
        pair : File & Result<&1, &1, U32 & String, String> <- File.read(f, 4096)
        load_ns_read(pair)

def load_ns() -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    r : Result<&1, &1, U32 & String, File> <- File.open("/etc/resolv.conf", "r")
    load_ns_open(r)

def lookup_ns(rns: Result<&1, &1, U32 & String, String>, +host: String) -> IO(Result<&1, &1, U32 & String, String>):
  match rns:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case Done{+ns}:
      do IO<Result<&1, &1, U32 & String, String>>:
        rnd : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
        lookup_rnd(host, ns, DNS_PORT(), rnd, False{})

def lookup_ns_aaaa(rns: Result<&1, &1, U32 & String, String>, +host: String) -> IO(Result<&1, &1, U32 & String, String>):
  match rns:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case Done{+ns}:
      do IO<Result<&1, &1, U32 & String, String>>:
        rnd : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
        lookup_rnd(host, ns, DNS_PORT(), rnd, True{})

def lookup_aaaa(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    rns : Result<&1, &1, U32 & String, String> <- load_ns()
    lookup_ns_aaaa(rns, host)

def lookup_a(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    rns : Result<&1, &1, U32 & String, String> <- load_ns()
    lookup_ns(rns, host)

# Query-order dispatch. The pure V6.query_order policy owns the attempt
# sequence; each attempt draws a fresh txid and keeps the existing bounds.
def lookup_rnd_typed(
  +host: String,
  +ns: String,
  +dport: U32,
  rnd: Result<&1, &1, U32 & String, U32>,
  is_aaaa: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match is_aaaa:
    case True{}:
      lookup_rnd(host, ns, dport, rnd, True{})
    case False{}:
      lookup_rnd(host, ns, dport, rnd, False{})

def resolve_second_rnd(
  r_first: Result<&1, &1, U32 & String, String>,
  +host: String,
  +ns: String,
  +dport: U32,
  rnd: Result<&1, &1, U32 & String, U32>,
  second: U32
) -> IO(Result<&1, &1, U32 & String, String>):
  match r_first:
    case Done{+ip}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{ip})
    case Fail{_}:
      lookup_rnd_typed(host, ns, dport, rnd, U32.is_eq(second, V6.AAAA_QTYPE()))

def resolve_ns_go(
  rns: Result<&1, &1, U32 & String, String>,
  +host: String,
  +dport: U32,
  +order: V6.QueryOrder
) -> IO(Result<&1, &1, U32 & String, String>):
  match rns:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case Done{+ns}:
      match order:
        case V6.QueryOrder{+first, +second}:
          do IO<Result<&1, &1, U32 & String, String>>:
            rnd : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
            first_r : Result<&1, &1, U32 & String, String> <- lookup_rnd_typed(host, ns, dport, rnd, U32.is_eq(first, V6.AAAA_QTYPE()))
            rnd2 : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
            resolve_second_rnd(first_r, host, ns, dport, rnd2, second)

def resolve_ns(rns: Result<&1, &1, U32 & String, String>, +host: String) -> IO(Result<&1, &1, U32 & String, String>):
  resolve_ns_go(rns, host, DNS_PORT(), V6.query_order())

def resolve_ns_at(rns: Result<&1, &1, U32 & String, String>, +host: String, +dport: U32) -> IO(Result<&1, &1, U32 & String, String>):
  resolve_ns_go(rns, host, dport, V6.query_order())

def resolve_at(+host: String, +ns: String, +dport: U32) -> IO(Result<&1, &1, U32 & String, String>):
  resolve_ns_at(Done{ns}, host, dport)

def lookup_n_at(+host: String, +ns: String, +dport: U32, +n: U32, +aaaa: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  lookup_n(host, ns, dport, n, aaaa)

def resolve_name(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    rns : Result<&1, &1, U32 & String, String> <- load_ns()
    resolve_ns(rns, host)

def resolve_literal(+host: String, valid: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match valid:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{host})
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("ipv6"))

def resolve_v6(+host: String, v6: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match v6:
    case True{}:
      resolve_literal(host, V6.valid_inner(host))
    case False{}:
      resolve_name(host)

def resolve_pick(+host: String, ip: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match ip:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{host})
    case False{}:
      resolve_v6(host, Wire.is_ipv6(host))

def resolve(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  resolve_pick(host, Wire.is_ipv4(host))

# Dual TCP dial: try first, fall back to second only when the first
# connect fails. No TLS here; callers upgrade with the original hostname
# (never the winning IP) and never downgrade or accept failed verification.
# Integrator (actor dial_begin): replace single resolve+connect with
# resolve AAAA, dial v6, on TCP failure resolve A and dial v4, threading
# the Dial generation so a stale fallback cannot win after a newer Dial.
def dial_second_done(
  cr2: Result<&1, &1, U32 & String, Socket>,
  +second_ip: String
) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  match cr2:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Socket & String>, Fail{e})
    case Done{sock2}:
      IO.pure(Result<&1, &1, U32 & String, Socket & String>, Done{(sock2, second_ip)})

def dial_second(
  cr1: Result<&1, &1, U32 & String, Socket>,
  +first_ip: String,
  +second_ip: String,
  +port: U32,
  +timeout: U32
) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  match cr1:
    case Done{sock1}:
      IO.pure(Result<&1, &1, U32 & String, Socket & String>, Done{(sock1, first_ip)})
    case Fail{_}:
      do IO<Result<&1, &1, U32 & String, Socket & String>>:
        cr2 : Result<&1, &1, U32 & String, Socket> <- TCP.connect_for(second_ip, port, timeout)
        dial_second_done(cr2, second_ip)

def connect_pair(+first_ip: String, +second_ip: String, +port: U32, +timeout: U32) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  do IO<Result<&1, &1, U32 & String, Socket & String>>:
    cr1 : Result<&1, &1, U32 & String, Socket> <- TCP.connect_for(first_ip, port, timeout)
    dial_second(cr1, first_ip, second_ip, port, timeout)

def connect_dual(+v6: String, +v4: String, +port: U32, +timeout: U32) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  connect_pair(v6, v4, port, timeout)

def dial_dual.one(+ip: String, +port: U32, +timeout: U32) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  do IO<Result<&1, &1, U32 & String, Socket & String>>:
    cr : Result<&1, &1, U32 & String, Socket> <- TCP.connect_for(ip, port, timeout)
    dial_second_done(cr, ip)

def dial_dual.has_v6(
  +ip6: String,
  r4: Result<&1, &1, U32 & String, String>,
  +port: U32,
  +timeout: U32
) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  match r4:
    case Done{+ip4}:
      connect_dual(ip6, ip4, port, timeout)
    case Fail{_}:
      dial_dual.one(ip6, port, timeout)

def dial_dual.no_v6(
  r4: Result<&1, &1, U32 & String, String>,
  +port: U32,
  +timeout: U32
) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  match r4:
    case Done{+ip4}:
      dial_dual.one(ip4, port, timeout)
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Socket & String>, Fail{e})

# Actuation mirrors Dq.dial_plan arm-for-arm (Results are linear, so the
# decision table cannot be shared by value): dual, v6-only, v4-only, none.
# Both-failed DNS reports the A error, mirroring the ordered resolver's
# second-failure convention.
def dial_dual.names(
  r6: Result<&1, &1, U32 & String, String>,
  r4: Result<&1, &1, U32 & String, String>,
  +port: U32,
  +timeout: U32
) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  match r6:
    case Done{+ip6}:
      dial_dual.has_v6(ip6, r4, port, timeout)
    case Fail{_}:
      dial_dual.no_v6(r4, port, timeout)

def dial_dual.gathered(
  r6: Result<&1, &1, U32 & String, String>,
  +host: String,
  +port: U32,
  +timeout: U32
) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  do IO<Result<&1, &1, U32 & String, Socket & String>>:
    r4 : Result<&1, &1, U32 & String, String> <- lookup_a(host)
    dial_dual.names(r6, r4, port, timeout)

def dial_dual.host(+host: String, +port: U32, +timeout: U32) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  do IO<Result<&1, &1, U32 & String, Socket & String>>:
    r6 : Result<&1, &1, U32 & String, String> <- lookup_aaaa(host)
    dial_dual.gathered(r6, host, port, timeout)

def dial_dual.validated(+host: String, +port: U32, +timeout: U32, valid: Bool) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  match valid:
    case True{}:
      dial_dual.one(host, port, timeout)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, Socket & String>, Fail{(1, "ipv6")})

def dial_dual.v6lit(+host: String, +port: U32, +timeout: U32, v6: Bool) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  match v6:
    case True{}:
      dial_dual.validated(host, port, timeout, V6.valid_inner(host))
    case False{}:
      dial_dual.host(host, port, timeout)

# Production dial entry: literals dial directly (v4 as-is, v6 validated);
# names gather AAAA+A, dial the dual pair (v6 first, TCP-failure fallback),
# and return the winning socket with its IP. TCP only: callers upgrade with
# the original hostname, never the winning IP; no TLS-failure fallback and
# no plaintext downgrade. Both-failed DNS reports the A error, mirroring
# the ordered resolver's second-failure convention.
def dial_dual.v4lit(+host: String, +port: U32, +timeout: U32, v4: Bool) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  match v4:
    case True{}:
      dial_dual.one(host, port, timeout)
    case False{}:
      dial_dual.v6lit(host, port, timeout, Wire.is_ipv6(host))

def dial_dual(+host: String, +port: U32, +timeout: U32) -> IO(Result<&1, &1, U32 & String, Socket & String>):
  dial_dual.v4lit(host, port, timeout, Wire.is_ipv4(host))
