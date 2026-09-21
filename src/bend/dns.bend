# DNS A lookup. Pure wire lives in dns_wire.bend.
# Live path: UDP.bind + UDP.send_to + recv_octets (not UDP.recv String).
import Base
import ./dns_wire.bend as Wire

def err(+msg: String) -> Result<&1, &1, U32 & String, String>:
  Wire.err(msg)

def is_ipv4(+host: String) -> Bool:
  Wire.is_ipv4(host)

def txid_of(+n: U32) -> U32:
  Wire.txid_of(n)

def encode_id(+id: U32, +host: String) -> Result<&1, &1, U32 & String, String>:
  Wire.encode_id(id, host)

def encode(+host: String) -> Result<&1, &1, U32 & String, String>:
  Wire.encode(host)

def parse_id(+want: U32, xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  Wire.parse_id(want, xs)

def parse_q(+want: U32, +host: String, xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  Wire.parse_q(want, host, xs)

def NS() -> String:
  "1.1.1.1"

def DNS_PORT() -> U32:
  53

def WAIT() -> Nat:
  40n

# Octet recv. Peer is host & (port & octets). None is EAGAIN/EINTR.
law recv_octets:
  Socket -> U32 -> IO(Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>)

def recv_octets(sock, max):
  import "../ffi/dns_ffi.c"

def fail_close(sock: Socket, +msg: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    Unit <- Socket.close(sock)
    return err(msg)

def wait_take(
  sock: Socket,
  t: Wire.Take,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match t:
    case Wire.Miss{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- IO.sleep(50)
        k(sock)
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
  +phost: String,
  rest: U32 & List<&2, U32>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match rest:
    case (port, xs):
      wait_take(sock, Wire.take_pkt(ns, id, qhost, phost, port, xs), k)

def wait_peer(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  p: String & (U32 & List<&2, U32>),
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match p:
    case (+phost, rest):
      wait_port(sock, id, qhost, ns, phost, rest, k)

def wait_got(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  got: Maybe<&1, String & (U32 & List<&2, U32>)>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match got:
    case None{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- IO.sleep(50)
        k(sock)
    case Some{p}:
      wait_peer(sock, id, qhost, ns, p, k)

def wait_r(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  r: Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "recv")
    case Done{got}:
      wait_got(sock, id, qhost, ns, got, k)

def wait_poll(
  pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>,
  +id: U32,
  +qhost: String,
  +ns: String,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      wait_r(sock, id, qhost, ns, r, k)

def wait_ans(fuel: Nat, sock: Socket, +id: U32, +qhost: String, +ns: String) -> IO(Result<&1, &1, U32 & String, String>):
  match fuel:
    case 0n:
      fail_close(sock, "timeout")
    case 1n+p:
      do IO<Result<&1, &1, U32 & String, String>>:
        m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- recv_octets(sock, 512)
        wait_poll(m, id, qhost, ns, s2 => wait_ans(p, s2, id, qhost, ns))

def after_send_r(
  sock: Socket,
  +id: U32,
  +qhost: String,
  +ns: String,
  r: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "send")
    case Done{_}:
      wait_ans(WAIT(), sock, id, qhost, ns)

def after_send(
  pair: Socket & Result<&1, &1, U32 & String, Unit>,
  +id: U32,
  +qhost: String,
  +ns: String
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      after_send_r(sock, id, qhost, ns, r)

def after_bind(
  r: Result<&1, &1, U32 & String, Socket>,
  +q: String,
  +id: U32,
  +host: String,
  +ns: String
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, err("bind"))
    case Done{sock}:
      do IO<Result<&1, &1, U32 & String, String>>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- UDP.send_to(sock, ns, DNS_PORT(), q)
        after_send(sent, id, host, ns)

def lookup_q(enc: Result<&1, &1, U32 & String, String>, +id: U32, +host: String) -> IO(Result<&1, &1, U32 & String, String>):
  match enc:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case Done{+q}:
      do IO<Result<&1, &1, U32 & String, String>>:
        br : Result<&1, &1, U32 & String, Socket> <- UDP.bind(0)
        after_bind(br, q, id, host, NS())

def lookup_n(+host: String, +n: U32) -> IO(Result<&1, &1, U32 & String, String>):
  +id = txid_of(n)
  lookup_q(encode_id(id, host), id, host)

def lookup_rnd(+host: String, rnd: Result<&1, &1, U32 & String, U32>) -> IO(Result<&1, &1, U32 & String, String>):
  match rnd:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, err("random"))
    case Done{n}:
      lookup_n(host, n)

def lookup_a(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    rnd : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
    lookup_rnd(host, rnd)

def resolve_pick(+host: String, ip: Bool) -> IO(Result<&1, &1, U32 & String, String>):
  match ip:
    case True{}:
      IO.pure(Result<&1, &1, U32 & String, String>, Done{host})
    case False{}:
      lookup_a(host)

def resolve(+host: String) -> IO(Result<&1, &1, U32 & String, String>):
  resolve_pick(host, is_ipv4(host))
