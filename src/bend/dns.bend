# DNS A lookup. Pure wire lives in dns_wire.bend.
# Live path: UDP.bind + send_octets + recv_octets (not UDP.send_to String).
# IPv4/A only: IPv6 literals fail with "ipv6". Resolver is the first IPv4
# nameserver in /etc/resolv.conf, else fails closed. Transaction ids are 16-bit.
import Base
import ./dns_wire.bend as Wire
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
  +q: List<&2, U32>,
  +n: Nat,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match resend:
    case False{}:
      wait_sleep(sock, n, k)
    case True{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- send_octets(sock, ns, DNS_PORT(), q)
        wait_sent(sent, n, k)

def wait_take(
  sock: Socket,
  +ns: String,
  +q: List<&2, U32>,
  +n: Nat,
  t: Wire.Take,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match t:
    case Wire.Miss{}:
      wait_idle(need_resend(n), sock, ns, q, n, k)
    case Wire.HitOk{+ip}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- Socket.close(sock)
        return Done{ip}
    case Wire.HitErr{+msg}:
      fail_close(sock, msg)

def wait_port(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +q: List<&2, U32>,
  +n: Nat,
  +phost: String,
  rest: U32 & List<&2, U32>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match rest:
    case (port, xs):
      wait_take(sock, ns, q, n, Wire.take_pkt(ns, id, qhost, phost, port, xs), k)

def wait_peer(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +q: List<&2, U32>,
  +n: Nat,
  p: String & (U32 & List<&2, U32>),
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match p:
    case (+phost, rest):
      wait_port(sock, id, qhost, ns, q, n, phost, rest, k)

def wait_got(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +q: List<&2, U32>,
  +n: Nat,
  got: Maybe<&1, String & (U32 & List<&2, U32>)>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match got:
    case None{}:
      wait_idle(need_resend(n), sock, ns, q, n, k)
    case Some{p}:
      wait_peer(sock, id, qhost, ns, q, n, p, k)

def wait_r(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +q: List<&2, U32>,
  +n: Nat,
  r: Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "recv")
    case Done{got}:
      wait_got(sock, id, qhost, ns, q, n, got, k)

def wait_poll(
  pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +id: U32,
  +qhost: String,
  +ns: String,
  +q: List<&2, U32>,
  +n: Nat,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      wait_r(sock, id, qhost, ns, q, n, r, k)

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed wait_ans
def wait_ans(
  fuel: Nat,
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +q: List<&2, U32>,
  +n: Nat
) -> IO(Result<&1, &1, U32 & String, String>):
  match fuel:
    case 0n:
      fail_close(sock, "timeout")
    case 1n+p:
      do IO<Result<&1, &1, U32 & String, String>>:
        m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- recv_nb(sock, 4096)
        wait_poll(m, id, qhost, ns, q, n, s2 => wait_ans(p, s2, id, qhost, ns, q, Nat.add(n, 1n)))

def after_send_r(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  +q: List<&2, U32>,
  r: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "send")
    case Done{_}:
      wait_ans(WAIT(), sock, id, qhost, ns, q, 0n)

def after_send(
  pair: Socket & Result<&1, &1, U32 & String, Unit>,
  +id: U32,
  +qhost: String,
  +ns: String,
  +q: List<&2, U32>
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      after_send_r(sock, id, qhost, ns, q, r)

def after_bind(
  r: Result<&1, &1, U32 & String, Socket>,
  +q: List<&2, U32>,
  +id: U32,
  +host: String,
  +ns: String
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("bind"))
    case Done{sock}:
      do IO<Result<&1, &1, U32 & String, String>>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- send_octets(sock, ns, DNS_PORT(), q)
        after_send(sent, id, host, ns, q)

def tcp_idle(sock: Socket, acc: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    Unit <- IO.sleep(10)
    k(sock, acc)

def tcp_frame(sock: Socket, +id: U32, +host: String, +acc: List<&2, U32>, frame: Wire.TcpFrame, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match frame:
    case Wire.TcpInvalid{}: fail_close(sock, "tcp length")
    case Wire.TcpMore{}: k(sock, acc)
    case Wire.TcpPayload{+xs}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- Socket.close(sock)
        return Wire.parse_q(id, host, xs)

def tcp_chunk(sock: Socket, +id: U32, +host: String, acc: List<&2, U32>, xs: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match xs:
    case Nil{}: fail_close(sock, "tcp eof")
    case Con{h, t}:
      +all = List.append(&2, U32, acc, h <> t)
      tcp_frame(sock, id, host, all, Wire.tcp_packet(all), k)

def tcp_poll(pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>, +id: U32, +host: String, acc: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}: fail_close(sock, "tcp recv")
        case Done{got}:
          match got:
            case None{}: tcp_idle(sock, acc, k)
            case Some{(_, (_, xs))}: tcp_chunk(sock, id, host, acc, xs, k)

def tcp_deadline(expired: Bool, sock: Socket, +id: U32, +host: String, acc: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Result<&1, &1, U32 & String, String>)) -> IO(Result<&1, &1, U32 & String, String>):
  match expired:
    case True{}: fail_close(sock, "tcp timeout")
    case False{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        got : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- recv_nb(sock, 4096)
        tcp_poll(got, id, host, acc, k)

# The monotonic deadline is shared by every chunk, so slow/trickling peers
# cannot extend it. Fuel is only a second, structural guardrail.
def tcp_wait(fuel: Nat, sock: Socket, +id: U32, +host: String, +start: U32, acc: List<&2, U32>) -> IO(Result<&1, &1, U32 & String, String>):
  match fuel:
    case 0n: fail_close(sock, "tcp timeout")
    case 1n+p:
      do IO<Result<&1, &1, U32 & String, String>>:
        now : U32 <- Clock.millis()
        tcp_deadline(U32.is_ge(U32.sub(now, start), TCP_TIMEOUT_MS()), sock, id, host, acc, s2 => buf => tcp_wait(p, s2, id, host, start, buf))

def lookup_tcp_sent(
  sock: Socket,
  +id: U32,
  +host: String,
  r: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "tcp send")
    case Done{_}:
      do IO<Result<&1, &1, U32 & String, String>>:
        start : U32 <- Clock.millis()
        tcp_wait(U32.to_nat(65538), sock, id, host, start, Nil{})

def lookup_tcp_send(
  pair: Socket & Result<&1, &1, U32 & String, Unit>,
  +id: U32,
  +host: String
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      lookup_tcp_sent(sock, id, host, r)

def lookup_tcp_sock(
  sock: Socket,
  +id: U32,
  +host: String,
  +q: List<&2, U32>
) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    sent : Socket & Result<&1, &1, U32 & String, Unit> <- send_octets(sock, "", 0, Wire.tcp_frame(q))
    lookup_tcp_send(sent, id, host)

def lookup_tcp_conn(
  cr: Result<&1, &1, U32 & String, Socket>,
  +id: U32,
  +host: String,
  +q: List<&2, U32>
) -> IO(Result<&1, &1, U32 & String, String>):
  match cr:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("tcp connect"))
    case Done{sock}:
      lookup_tcp_sock(sock, id, host, q)

def lookup_tcp(+host: String, +ns: String, +id: U32, +q: List<&2, U32>) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    cr : Result<&1, &1, U32 & String, Socket> <- TCP.connect_for(ns, DNS_PORT(), TCP_TIMEOUT_MS())
    lookup_tcp_conn(cr, id, host, q)

def lookup_fallback(
  +host: String,
  +ns: String,
  +id: U32,
  +q: List<&2, U32>,
  r: Result<&1, &1, U32 & String, String>,
  is_tc: Bool
) -> IO(Result<&1, &1, U32 & String, String>):
  match is_tc:
    case True{}:
      lookup_tcp(host, ns, id, q)
    case False{}:
      IO.pure(Result<&1, &1, U32 & String, String>, r)

def lookup_res(
  +host: String,
  +ns: String,
  +id: U32,
  +q: List<&2, U32>,
  r: Result<&1, &1, U32 & String, String>
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Done{+ip}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{ip})
    case Fail{e}:
      match e:
        case (_, +msg):
          lookup_fallback(host, ns, id, q, Fail{e}, String.eq(msg, "tc"))

def lookup_q(
  enc: Result<&1, &1, U32 & String, List<&2, U32>>,
  +id: U32,
  +host: String,
  +ns: String
) -> IO(Result<&1, &1, U32 & String, String>):
  match enc:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case Done{+q}:
      do IO<Result<&1, &1, U32 & String, String>>:
        br : Result<&1, &1, U32 & String, Socket> <- UDP.bind("0.0.0.0", 0)
        r : Result<&1, &1, U32 & String, String> <- after_bind(br, q, id, host, ns)
        lookup_res(host, ns, id, q, r)

def lookup_n(+host: String, +ns: String, +n: U32) -> IO(Result<&1, &1, U32 & String, String>):
  +id = Wire.txid_of(n)
  lookup_q(Wire.encode_edns_id(id, host), id, host, ns)

def lookup_rnd(+host: String, +ns: String, rnd: Result<&1, &1, U32 & String, U32>) -> IO(Result<&1, &1, U32 & String, String>):
  match rnd:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("random"))
    case Done{n}:
      lookup_n(host, ns, n)

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
        lookup_rnd(host, ns, rnd)

def lookup_a(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    rns : Result<&1, &1, U32 & String, String> <- load_ns()
    lookup_ns(rns, host)

def resolve_v6(+host: String, v6: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match v6:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Wire.err("ipv6"))
    case False{}:
      lookup_a(host)

def resolve_pick(+host: String, ip: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match ip:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{host})
    case False{}:
      resolve_v6(host, Wire.is_ipv6(host))

def resolve(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  resolve_pick(host, Wire.is_ipv4(host))
