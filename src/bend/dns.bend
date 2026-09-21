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

def octets(+s: String) -> List<&2, U32>:
  Wire.octets(s)

def parse_id(+want: U32, xs: List<&2, U32>) -> Result<&1, &1, U32 & String, String>:
  Wire.parse_id(want, xs)

def NS() -> String:
  "1.1.1.1"

def DNS_PORT() -> U32:
  53

def WAIT() -> Nat:
  40n

# Octet recv. Base UDP.recv_from is a String; A rdata 0x80–0xC1 is FFFD.
law recv_octets:
  Socket -> U32 -> IO(Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>)

def recv_octets(sock, max):
  import "../ffi/dns_ffi.c"

def fail_close(sock: Socket, +msg: String) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    Unit <- Socket.close(sock)
    return err(msg)

def wait_some(
  sock: Socket,
  +id: U32,
  xs: List<&2, U32>
) -> IO(Result<&1, &1, U32 & String, String>):
  do IO<Result<&1, &1, U32 & String, String>>:
    Unit <- Socket.close(sock)
    return parse_id(id, xs)

def wait_got(
  sock: Socket,
  +id: U32,
  got: Maybe<&1, List<&2, U32>>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match got:
    case None{}:
      do IO<Result<&1, &1, U32 & String, String>>:
        Unit <- IO.sleep(50)
        k(sock)
    case Some{xs}:
      wait_some(sock, id, xs)

def wait_r(
  sock: Socket,
  +id: U32,
  r: Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "recv")
    case Done{got}:
      wait_got(sock, id, got, k)

def wait_poll(
  pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>>,
  +id: U32,
  k: Socket -> IO(Result<&1, &1, U32 & String, String>)
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      wait_r(sock, id, r, k)

def wait_ans(fuel: Nat, sock: Socket, +id: U32) -> IO(Result<&1, &1, U32 & String, String>):
  match fuel:
    case 0n:
      fail_close(sock, "timeout")
    case 1n+p:
      do IO<Result<&1, &1, U32 & String, String>>:
        m : Socket & Result<&1, &1, U32 & String, Maybe<&1, List<&2, U32>>> <- recv_octets(sock, 512)
        wait_poll(m, id, s2 => wait_ans(p, s2, id))

def after_send_r(
  sock: Socket,
  +id: U32,
  r: Result<&1, &1, U32 & String, Unit>
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      fail_close(sock, "send")
    case Done{_}:
      wait_ans(WAIT(), sock, id)

def after_send(
  pair: Socket & Result<&1, &1, U32 & String, Unit>,
  +id: U32
) -> IO(Result<&1, &1, U32 & String, String>):
  match pair:
    case (sock, r):
      after_send_r(sock, id, r)

def after_bind(
  r: Result<&1, &1, U32 & String, Socket>,
  +q: String,
  +id: U32
) -> IO(Result<&1, &1, U32 & String, String>):
  match r:
    case Fail{_}:
      IO.pure(Result<&1, &1, U32 & String, String>, err("bind"))
    case Done{sock}:
      do IO<Result<&1, &1, U32 & String, String>>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- UDP.send_to(sock, NS(), DNS_PORT(), q)
        after_send(sent, id)

def lookup_q(enc: Result<&1, &1, U32 & String, String>, +id: U32) -> IO(Result<&1, &1, U32 & String, String>):
  match enc:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, String>, Fail{e})
    case Done{+q}:
      do IO<Result<&1, &1, U32 & String, String>>:
        br : Result<&1, &1, U32 & String, Socket> <- UDP.bind(0)
        after_bind(br, q, id)

def lookup_n(+host: String, +n: U32) -> IO(Result<&1, &1, U32 & String, String>):
  +id = txid_of(n)
  lookup_q(encode_id(id, host), id)

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
