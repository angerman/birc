# SPDX-License-Identifier: Apache-2.0
# Affine connection ownership shared by the IRC reader and writer. TLS is
# verified before the actor can register or send authentication commands.
import Base
import ./dns.bend as Dns
import ./tls.bend as Tls
import ./transport_policy.bend as Policy

type Conn is Type:
  Plain{socket: Socket}
  Secure{handle: Tls.Handle}

def tls_result(r: Result<&1, &1, U32 & String, Tls.Handle>) -> Result<&1, &1, U32 & String, Conn>:
  match r:
    case Fail{e}: Fail{e}
    case Done{h}: Done{Secure{h}}

def upgrade(sock: Socket, +host: String, secure: Bool) -> IO(Result<&1, &1, U32 & String, Conn>):
  match secure:
    case False{}: IO.pure(Result<&1, &1, U32 & String, Conn>, Done{Plain{sock}})
    case True{}:
      do IO<Result<&1, &1, U32 & String, Conn>>:
        r : Result<&1, &1, U32 & String, Tls.Handle> <- Tls.open_for(sock, host, 5000)
        return tls_result(r)

def connected(r: Result<&1, &1, U32 & String, Socket>, +host: String, secure: Bool) -> IO(Result<&1, &1, U32 & String, Conn>):
  match r:
    case Fail{e}: IO.pure(Result<&1, &1, U32 & String, Conn>, Fail{e})
    case Done{sock}: upgrade(sock, host, secure)

# DNS may resolve a different address. Verification always uses the requested
# hostname, not the address chosen for TCP. There is no plaintext retry.
def connect_for(+ip: String, +port: U32, +host: String, force_tls: Bool) -> IO(Result<&1, &1, U32 & String, Conn>):
  do IO<Result<&1, &1, U32 & String, Conn>>:
    r : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for(ip, port, 1000)
    connected(r, host, Policy.enabled(force_tls, port))

def send_plain(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> Conn & Result<&1, &1, U32 & String, Unit>:
  match pair:
    case (sock, r): (Plain{sock}, r)

def send_secure(pair: Tls.Handle & Result<&1, &1, U32 & String, Unit>) -> Conn & Result<&1, &1, U32 & String, Unit>:
  match pair:
    case (h, r): (Secure{h}, r)

def send_for(conn: Conn, +text: String, timeout_ms: U32) -> IO(Conn & Result<&1, &1, U32 & String, Unit>):
  match conn:
    case Plain{sock}:
      do IO<Conn & Result<&1, &1, U32 & String, Unit>>:
        pair : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, text, timeout_ms)
        return send_plain(pair)
    case Secure{h}:
      do IO<Conn & Result<&1, &1, U32 & String, Unit>>:
        pair : Tls.Handle & Result<&1, &1, U32 & String, Unit> <- Tls.send_for(h, text, timeout_ms)
        return send_secure(pair)

def recv_plain(pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>) -> Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>:
  match pair:
    case (sock, r): (Plain{sock}, r)

def recv_secure(pair: Tls.Handle & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>) -> Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>:
  match pair:
    case (h, r): (Secure{h}, r)

def recv_octets(conn: Conn, max: U32) -> IO(Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>):
  match conn:
    case Plain{sock}:
      do IO<Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>>:
        pair : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Dns.recv_octets(sock, max)
        return recv_plain(pair)
    case Secure{h}:
      do IO<Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>>:
        pair : Tls.Handle & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Tls.recv_octets(h, max)
        return recv_secure(pair)

def dup_plain(pair: Socket & Result<&1, &1, U32 & String, Socket>) -> Conn & Result<&1, &1, U32 & String, Conn>:
  match pair:
    case (sock, r):
      match r:
        case Fail{e}: (Plain{sock}, Fail{e})
        case Done{copy}: (Plain{sock}, Done{Plain{copy}})

def dup_secure(pair: Tls.Handle & Result<&1, &1, U32 & String, Tls.Handle>) -> Conn & Result<&1, &1, U32 & String, Conn>:
  match pair:
    case (h, r): (Secure{h}, tls_result(r))

def dup(conn: Conn) -> IO(Conn & Result<&1, &1, U32 & String, Conn>):
  match conn:
    case Plain{sock}:
      do IO<Conn & Result<&1, &1, U32 & String, Conn>>:
        pair : Socket & Result<&1, &1, U32 & String, Socket> <- Dns.Socket.dup(sock)
        return dup_plain(pair)
    case Secure{h}:
      do IO<Conn & Result<&1, &1, U32 & String, Conn>>:
        pair : Tls.Handle & Result<&1, &1, U32 & String, Tls.Handle> <- Tls.dup(h)
        return dup_secure(pair)

def shutdown(conn: Conn) -> IO(Conn & Result<&1, &1, U32 & String, Unit>):
  match conn:
    case Plain{sock}:
      do IO<Conn & Result<&1, &1, U32 & String, Unit>>:
        pair : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.Socket.shutdown(sock)
        return send_plain(pair)
    case Secure{h}:
      do IO<Conn & Result<&1, &1, U32 & String, Unit>>:
        pair : Tls.Handle & Result<&1, &1, U32 & String, Unit> <- Tls.shutdown(h)
        return send_secure(pair)

def close(conn: Conn) -> IO(Unit):
  match conn:
    case Plain{sock}: Socket.close(sock)
    case Secure{h}: Tls.close(h)
