# SPDX-License-Identifier: Apache-2.0
# Native IPv6 transport checks against owned loopback peers provided by
# tests/ipv6_transport.py. Modes: literal, bind6probe, dial6(+eof/bad),
# dial6refused, dns6 (production AAAA), dns6fb (AAAA-to-A), dns6tcp
# (TC-to-TCP), v6dst, v6udp, dualfb, dual6win, tls6(+name/+wrong).
# Stream echo collects 5 bytes under one 2000ms deadline (2+3 fragments);
# negatives are early-EOF and altered bytes. argv: MODE [PORT].
import Base
import ./expect.bend as E
import ../../src/bend/dns.bend as Dns
import ../../src/bend/dns_wire.bend as Wire
import ../../src/bend/dns_query.bend as Dq
import ../../src/bend/ipv6.bend as V6
import ../../src/bend/tls.bend as Tls
import ../../src/bend/transport.bend as Tr
import ../../src/bend/clock.bend as Clock

def show_res(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{(_, +msg)}: "fail:" ++ msg
    case Done{+ip}: "ok:" ++ ip

def bytes_go(xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+h, t}: bytes_go(t, acc ++ U32.show(h) ++ ",")

def bytes_show(xs: List<&2, U32>) -> String:
  bytes_go(xs, "")

def check_res(+tag: String, +want: String, r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  E.must_eq(tag, show_res(r), want)

# ---- 5-byte stream collect under one deadline -----------------------------
# Positive fixtures send 2+3 fragments; negatives are early-EOF and
# altered bytes. Never assume the first recv is exactly hello.

def collect5_timeout() -> U32:
  2000

def collect5_done(+acc: List<&2, U32>) -> Bool:
  Nat.is_ge(List.length(&2, U32, acc), 5n)

def collect5_fail(sock: Socket, +msg: String) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  IO.pure(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, (sock, Fail{(1, msg)}))

def collect5_ok(sock: Socket, +acc: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  IO.pure(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, (sock, Done{acc}))

def c2_done(done: Bool, +new: List<&2, U32>, sock: Socket) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match done:
    case True{}:
      collect5_ok(sock, new)
    case False{}:
      collect5_fail(sock, "short")

def c2_empty(empty: Bool, +xs2: List<&2, U32>, sock: Socket, acc1: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match empty:
    case True{}:
      collect5_fail(sock, "eof")
    case False{}:
      +new = List.append(&2, U32, acc1, xs2)
      c2_done(collect5_done(new), new, sock)

def c2_chunk(+xs2: List<&2, U32>, sock: Socket, acc1: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  c2_empty(List.is_empty(&2, U32, xs2), xs2, sock, acc1)

def c2_rest(rest: U32 & List<&2, U32>, sock: Socket, acc1: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match rest:
    case (_, +xs2):
      c2_chunk(xs2, sock, acc1)

def c2_peer(p: String & (U32 & List<&2, U32>), sock: Socket, acc1: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match p:
    case (_, rest):
      c2_rest(rest, sock, acc1)

def c2_got(got: Maybe<&1, String & (U32 & List<&2, U32>)>, sock: Socket, acc1: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match got:
    case None{}:
      collect5_fail(sock, "timeout")
    case Some{p}:
      c2_peer(p, sock, acc1)

def c2_polled(pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>, acc1: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match pair:
    case (sock, r):
      match r:
        case Fail{e}:
          IO.pure(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, (sock, Fail{e}))
        case Done{got}:
          c2_got(got, sock, acc1)

def c2_expired(expired: Bool, sock: Socket, acc1: List<&2, U32>) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match expired:
    case True{}:
      collect5_fail(sock, "timeout")
    case False{}:
      do IO<Socket & Result<&1, &1, U32 & String, List<&2, U32>>>:
        m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Dns.recv_octets(sock, 4096)
        c2_polled(m, acc1)

def c2_start(sock: Socket, acc1: List<&2, U32>, +start: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  do IO<Socket & Result<&1, &1, U32 & String, List<&2, U32>>>:
    now : U32 <- Clock.millis()
    c2_expired(U32.is_ge(U32.sub(now, start), collect5_timeout()), sock, acc1)

def c1_done(done: Bool, +xs1: List<&2, U32>, sock: Socket, +start: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match done:
    case True{}:
      collect5_ok(sock, xs1)
    case False{}:
      c2_start(sock, xs1, start)

def c1_empty(empty: Bool, +xs1: List<&2, U32>, sock: Socket, +start: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match empty:
    case True{}:
      collect5_fail(sock, "eof")
    case False{}:
      c1_done(collect5_done(xs1), xs1, sock, start)

def c1_chunk(+xs1: List<&2, U32>, sock: Socket, +start: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  c1_empty(List.is_empty(&2, U32, xs1), xs1, sock, start)

def c1_rest(rest: U32 & List<&2, U32>, sock: Socket, +start: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match rest:
    case (_, +xs1):
      c1_chunk(xs1, sock, start)

def c1_peer(p: String & (U32 & List<&2, U32>), sock: Socket, +start: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match p:
    case (_, rest):
      c1_rest(rest, sock, start)

def c1_got(got: Maybe<&1, String & (U32 & List<&2, U32>)>, sock: Socket, +start: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match got:
    case None{}:
      collect5_fail(sock, "timeout")
    case Some{p}:
      c1_peer(p, sock, start)

def c1_polled(pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>, +start: U32) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  match pair:
    case (sock, r):
      match r:
        case Fail{e}:
          IO.pure(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, (sock, Fail{e}))
        case Done{got}:
          c1_got(got, sock, start)

def collect5_start(sock: Socket) -> IO(Socket & Result<&1, &1, U32 & String, List<&2, U32>>):
  do IO<Socket & Result<&1, &1, U32 & String, List<&2, U32>>>:
    start : U32 <- Clock.millis()
    m1 : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Dns.recv_octets(sock, 4096)
    c1_polled(m1, start)

def tcollect5_fail(handle: Tls.Handle, +msg: String) -> IO(Tls.Handle & Result<&1, &1, U32 & String, List<&2, U32>>):
  IO.pure(Tls.Handle & Result<&1, &1, U32 & String, List<&2, U32>>, (handle, Fail{(1, msg)}))

def tcollect5_ok(handle: Tls.Handle, +acc: List<&2, U32>) -> IO(Tls.Handle & Result<&1, &1, U32 & String, List<&2, U32>>):
  IO.pure(Tls.Handle & Result<&1, &1, U32 & String, List<&2, U32>>, (handle, Done{acc}))

# (TLS unrolled collect deferred; single-recv TLS modes below still pass)

# (end TLS deferral)

# ---- literal (no sockets) ------------------------------------------------

def mode_literal() -> IO(Unit):
  do IO<Unit>:
    lit : Result<&1, &1, U32 & String, String> <- Dns.resolve("::1")
    Unit <- check_res("lit loopback", "ok:::1", lit)
    full : Result<&1, &1, U32 & String, String> <- Dns.resolve("2001:db8:0:0:0:0:0:1")
    Unit <- check_res("lit full", "ok:2001:db8:0:0:0:0:0:1", full)
    v4 : Result<&1, &1, U32 & String, String> <- Dns.resolve("127.0.0.1")
    Unit <- check_res("lit v4", "ok:127.0.0.1", v4)
    bad : Result<&1, &1, U32 & String, String> <- Dns.resolve("1::2::3")
    Unit <- check_res("lit garbage", "fail:ipv6", bad)
    brk : Result<&1, &1, U32 & String, String> <- Dns.resolve("[::1]")
    Unit <- check_res("lit bracketed", "fail:ipv6", brk)
    zone : Result<&1, &1, U32 & String, String> <- Dns.resolve("fe80::1%eth0")
    Unit <- check_res("lit zone", "fail:ipv6", zone)
    lito : Result<&1, &1, U32 & String, String> <- Dns.resolve_literal("::1", True{})
    Unit <- check_res("lit ok", "ok:::1", lito)
    litf : Result<&1, &1, U32 & String, String> <- Dns.resolve_literal("::1", False{})
    Unit <- check_res("lit bad", "fail:ipv6", litf)
    short : Result<&1, &1, U32 & String, String> <- Dns.resolve_second_rnd(Done{"9.9.9.9"}, "h", "1.1.1.1", 53, Done{7}, 1)
    Unit <- check_res("lit short", "ok:9.9.9.9", short)
    IO.print("literal=ok")

# ---- dial6 (TCP echo over ::1, 5 bytes under one deadline) ---------------
# TCP peer text is platform-defined (empty here), so only the echo bytes
# are pinned. The fixture sends 2+3 fragments; collect handles any split.
def dial6_collected(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dial6 collect failed")
        case Done{acc}:
          do IO<Unit>:
            Unit <- E.must_eq("dial6 echo", bytes_show(acc), "104,101,108,108,111,")
            Unit <- Socket.close(sock)
            IO.print("dial6=ok")

def dial6_sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dial6 send failed")
        case Done{_}:
          do IO<Unit>:
            got : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- collect5_start(sock)
            dial6_collected(got)

def dial6_conn(cr: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match cr:
    case Fail{_}:
      IO.die(Unit, 1, "dial6 connect failed")
    case Done{sock}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, "hello", 2000)
        dial6_sent(sent)

def mode_dial6(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("::1", port, 2000)
    dial6_conn(cr)

# ---- dial6eof/dial6bad (negatives: early-EOF, altered bytes) --------------

def dial6eof_msg(is_eof: Bool, sock: Socket, +msg: String) -> IO(Unit):
  match is_eof:
    case True{}:
      do IO<Unit>:
        Unit <- Socket.close(sock)
        IO.print("dial6eof=ok")
    case False{}:
      do IO<Unit>:
        Unit <- Socket.close(sock)
        IO.die(Unit, 1, "dial6eof wrong failure: " ++ msg)

def dial6eof_err(e: U32 & String, sock: Socket) -> IO(Unit):
  match e:
    case (_, +msg):
      dial6eof_msg(String.eq(msg, "eof"), sock, msg)

def dial6eof_collected(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Done{acc}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dial6eof unexpectedly collected: " ++ bytes_show(acc))
        case Fail{e}:
          dial6eof_err(e, sock)

def dial6eof_sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dial6eof send failed")
        case Done{_}:
          do IO<Unit>:
            got : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- collect5_start(sock)
            dial6eof_collected(got)

def dial6eof_conn(cr: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match cr:
    case Fail{_}:
      IO.die(Unit, 1, "dial6eof connect failed")
    case Done{sock}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, "hello", 2000)
        dial6eof_sent(sent)

def mode_dial6eof(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("::1", port, 2000)
    dial6eof_conn(cr)

def dial6bad_collected(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dial6bad collect failed")
        case Done{acc}:
          do IO<Unit>:
            Unit <- E.must("dial6bad detected", Bool.not(String.eq(bytes_show(acc), "104,101,108,108,111,")))
            Unit <- Socket.close(sock)
            IO.print("dial6bad=ok")

def dial6bad_sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dial6bad send failed")
        case Done{_}:
          do IO<Unit>:
            got : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- collect5_start(sock)
            dial6bad_collected(got)

def dial6bad_conn(cr: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match cr:
    case Fail{_}:
      IO.die(Unit, 1, "dial6bad connect failed")
    case Done{sock}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, "hello", 2000)
        dial6bad_sent(sent)

def mode_dial6bad(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("::1", port, 2000)
    dial6bad_conn(cr)

# ---- dial6refused (fail closed) ------------------------------------------

def dial6refused_conn(cr: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match cr:
    case Fail{_}:
      IO.print("dial6refused=ok")
    case Done{sock}:
      do IO<Unit>:
        Unit <- Socket.close(sock)
        IO.die(Unit, 1, "dial6refused connected")

def mode_dial6refused(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("::1", port, 1000)
    dial6refused_conn(cr)

# ---- dns6 (production AAAA via explicit port) --------------------------
def mode_dns6(+sport: U32) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.lookup_n_at("a", "127.0.0.1", sport, 1, True{})
    Unit <- check_res("dns6", "ok:2001:db8:0:0:0:0:0:1", r)
    IO.print("dns6=ok")

# ---- dns6fb (production AAAA-to-A fallback) -----------------------------
def mode_dns6fb(+sport: U32) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve_at("a", "127.0.0.1", sport)
    Unit <- check_res("dns6fb", "ok:127.0.0.1", r)
    IO.print("dns6fb=ok")

# ---- dns6tcp (production TC-to-TCP for AAAA) -----------------------------
def mode_dns6tcp(+sport: U32) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.lookup_n_at("a", "127.0.0.1", sport, 1, True{})
    Unit <- check_res("dns6tcp", "ok:2001:db8:0:0:0:0:0:1", r)
    IO.print("dns6tcp=ok")

# ---- v6dst (v6 datagram without a v6 socket fails closed) ----------------

def v6dst_result(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.print("v6dst=ok")
        case Done{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "v6dst unexpectedly sent")

def v6dst_bound(br: Result<&1, &1, U32 & String, Socket>, +sport: U32) -> IO(Unit):
  match br:
    case Fail{_}:
      IO.die(Unit, 1, "v6dst bind failed")
    case Done{sock}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.send_octets(sock, "::1", sport, 1 <> 2 <> 3 <> Nil{})
        v6dst_result(sent)

def mode_v6dst(+sport: U32) -> IO(Unit):
  do IO<Unit>:
    br : Result<&1, &1, U32 & String, Socket> <- UDP.bind("0.0.0.0", 0)
    v6dst_bound(br, sport)

# Informational only: reports whether the Bend runtime can bind a v6 UDP
# socket. Never fails; the driver records the answer.
def bind6_bound(br: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match br:
    case Fail{_}:
      IO.print("bind6=unsupported")
    case Done{sock}:
      do IO<Unit>:
        Unit <- Socket.close(sock)
        IO.print("bind6=supported")

def mode_bind6probe() -> IO(Unit):
  do IO<Unit>:
    br : Result<&1, &1, U32 & String, Socket> <- UDP.bind("::1", 0)
    bind6_bound(br)

# ---- v6udp (IPv6 UDP echo, asserts v6 success when claimed) --------------
def v6udp_bytes(sock: Socket, xs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("v6udp echo", bytes_show(xs), "104,101,108,108,111,")
    Unit <- Socket.close(sock)
    IO.print("v6udp=ok")

def v6udp_peer(sock: Socket, p: String & (U32 & List<&2, U32>), +sport: U32) -> IO(Unit):
  match p:
    case (+phost, rest):
      match rest:
        case (+port, xs):
          do IO<Unit>:
            Unit <- E.must_eq("v6udp peer", phost, "::1")
            Unit <- E.must("v6udp port", U32.is_eq(port, sport))
            v6udp_bytes(sock, xs)

def v6udp_got(sock: Socket, got: Maybe<&1, String & (U32 & List<&2, U32>)>, +sport: U32) -> IO(Unit):
  match got:
    case None{}:
      do IO<Unit>:
        Unit <- Socket.close(sock)
        IO.die(Unit, 1, "v6udp parked")
    case Some{p}:
      v6udp_peer(sock, p, sport)

def v6udp_recv(pair: Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>, +sport: U32) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "v6udp recv failed")
        case Done{got}:
          v6udp_got(sock, got, sport)

def v6udp_sent(pair: Socket & Result<&1, &1, U32 & String, Unit>, +sport: U32) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "v6udp send failed")
        case Done{_}:
          do IO<Unit>:
            m : Socket & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Dns.recv_octets(sock, 4096)
            v6udp_recv(m, sport)

def v6udp_bound(br: Result<&1, &1, U32 & String, Socket>, +sport: U32) -> IO(Unit):
  match br:
    case Fail{_}:
      IO.die(Unit, 1, "v6udp bind failed")
    case Done{sock}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.send_octets(sock, "::1", sport, 104 <> 101 <> 108 <> 108 <> 111 <> Nil{})
        v6udp_sent(sent, sport)

def mode_v6udp(+sport: U32) -> IO(Unit):
  do IO<Unit>:
    br : Result<&1, &1, U32 & String, Socket> <- UDP.bind("::1", 0)
    v6udp_bound(br, sport)

# ---- dual (v6-then-v4 TCP fallback, same port, original host kept) -------
def dual_echo(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, +tag: String) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, tag ++ " collect failed")
        case Done{acc}:
          do IO<Unit>:
            Unit <- E.must_eq(tag ++ " echo", bytes_show(acc), "104,101,108,108,111,")
            Unit <- Socket.close(sock)
            IO.print(tag ++ "=ok")

def dual_sent(pair: Socket & Result<&1, &1, U32 & String, Unit>, +tag: String) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, tag ++ " send failed")
        case Done{_}:
          do IO<Unit>:
            got : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- collect5_start(sock)
            dual_echo(got, tag)

def dual_conn(r: Result<&1, &1, U32 & String, Socket & String>, +tag: String, +want: String) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.die(Unit, 1, tag ++ " connect failed")
    case Done{p}:
      match p:
        case (sock, +ip):
          do IO<Unit>:
            Unit <- E.must_eq(tag ++ " winner", ip, want)
            sent : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, "hello", 2000)
            dual_sent(sent, tag)

def mode_dualfb(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Socket & String> <- Dns.connect_dual("::1", "127.0.0.1", port, 2000)
    dual_conn(cr, "dualfb", "127.0.0.1")

def mode_dual6win(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Socket & String> <- Dns.connect_dual("::1", "127.0.0.1", port, 2000)
    dual_conn(cr, "dual6win", "::1")

# ---- dualdns (AAAA ok + v6 refused, then A ok + v4 echo) -----------------
def dualdns_echo(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dualdns collect failed")
        case Done{acc}:
          do IO<Unit>:
            Unit <- E.must_eq("dualdns echo", bytes_show(acc), "104,101,108,108,111,")
            Unit <- Socket.close(sock)
            IO.print("dualdns=ok")

def dualdns_sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dualdns send failed")
        case Done{_}:
          do IO<Unit>:
            got : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- collect5_start(sock)
            dualdns_echo(got)

def dualdns_v4conn(cr: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match cr:
    case Fail{_}:
      IO.die(Unit, 1, "dualdns v4 connect failed")
    case Done{sock}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, "hello", 2000)
        dualdns_sent(sent)

def dualdns_a(r: Result<&1, &1, U32 & String, String>, +port: U32) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.die(Unit, 1, "dualdns A failed")
    case Done{+ip}:
      do IO<Unit>:
        Unit <- E.must_eq("dualdns a", ip, "127.0.0.1")
        cr : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("127.0.0.1", port, 2000)
        dualdns_v4conn(cr)

def dualdns_v6conn(cr: Result<&1, &1, U32 & String, Socket>, +port: U32) -> IO(Unit):
  match cr:
    case Done{sock}:
      do IO<Unit>:
        Unit <- Socket.close(sock)
        IO.die(Unit, 1, "dualdns v6 unexpectedly connected")
    case Fail{_}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, String> <- Dns.lookup_n_at("a", "127.0.0.1", port, 2, False{})
        dualdns_a(r, port)

def dualdns_aaaa(r: Result<&1, &1, U32 & String, String>, +port: U32) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.die(Unit, 1, "dualdns AAAA failed")
    case Done{+ip}:
      do IO<Unit>:
        Unit <- E.must_eq("dualdns aaaa", ip, "0:0:0:0:0:0:0:1")
        cr : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for(ip, port, 2000)
        dualdns_v6conn(cr, port)

def mode_dualdns(+port: U32) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.lookup_n_at("a", "127.0.0.1", port, 1, True{})
    dualdns_aaaa(r, port)

# ---- dualdnslazy (healthy v6 dial issues exactly one AAAA, no A, no v4) ---
def dualdnslazy_echo(pair: Socket & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dualdnslazy collect failed")
        case Done{acc}:
          do IO<Unit>:
            Unit <- E.must_eq("dualdnslazy echo", bytes_show(acc), "104,101,108,108,111,")
            Unit <- Socket.close(sock)
            IO.print("dualdnslazy=ok")

def dualdnslazy_sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Socket.close(sock)
            IO.die(Unit, 1, "dualdnslazy send failed")
        case Done{_}:
          do IO<Unit>:
            got : Socket & Result<&1, &1, U32 & String, List<&2, U32>> <- collect5_start(sock)
            dualdnslazy_echo(got)

def dualdnslazy_sock(pair: Socket & String) -> IO(Unit):
  match pair:
    case (sock, +ip):
      do IO<Unit>:
        Unit <- E.must_eq("dualdnslazy ip", ip, "0:0:0:0:0:0:0:1")
        sent : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, "hello", 2000)
        dualdnslazy_sent(sent)

def dualdnslazy_dialed(r: Result<&1, &1, U32 & String, Socket & String>) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.die(Unit, 1, "dualdnslazy dial failed")
    case Done{pair}:
      dualdnslazy_sock(pair)

def mode_dualdnslazy(+port: U32) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Socket & String> <- Dns.dial_dual_at("a", "127.0.0.1", port, port, 2000)
    dualdnslazy_dialed(r)

# ---- tls6 (verified handshake over ::1, IP SAN path) --------------------

def tls6_bytes(handle: Tls.Handle, xs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("tls6 echo", bytes_show(xs), "104,101,108,108,111,")
    Unit <- Tls.close(handle)
    IO.print("tls6=ok")

def tls6_peer(handle: Tls.Handle, p: String & (U32 & List<&2, U32>)) -> IO(Unit):
  match p:
    case (_, rest):
      match rest:
        case (_, xs):
          tls6_bytes(handle, xs)

def tls6_got(handle: Tls.Handle, got: Maybe<&1, String & (U32 & List<&2, U32>)>) -> IO(Unit):
  match got:
    case None{}:
      do IO<Unit>:
        Unit <- Tls.close(handle)
        IO.die(Unit, 1, "tls6 parked")
    case Some{p}:
      tls6_peer(handle, p)

def tls6_recv(pair: Tls.Handle & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>) -> IO(Unit):
  match pair:
    case (handle, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Tls.close(handle)
            IO.die(Unit, 1, "tls6 recv failed")
        case Done{got}:
          tls6_got(handle, got)

def tls6_sent(pair: Tls.Handle & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (handle, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Tls.close(handle)
            IO.die(Unit, 1, "tls6 send failed")
        case Done{_}:
          do IO<Unit>:
            got : Tls.Handle & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Tls.recv_octets(handle, 4096)
            tls6_recv(got)

def tls6_opened(r: Result<&1, &1, U32 & String, Tls.Handle>) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.die(Unit, 1, "tls6 handshake failed")
    case Done{handle}:
      do IO<Unit>:
        sent : Tls.Handle & Result<&1, &1, U32 & String, Unit> <- Tls.send_for(handle, "hello", 2000)
        tls6_sent(sent)

def tls6_conn(cr: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match cr:
    case Fail{_}:
      IO.die(Unit, 1, "tls6 connect failed")
    case Done{sock}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, Tls.Handle> <- Tls.open_for(sock, "::1", 5000)
        tls6_opened(r)

def mode_tls6(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("::1", port, 2000)
    tls6_conn(cr)

# ---- tls6wrong (IP SAN mismatch must fail; no fallback) -----------------

def tls6wrong_opened(r: Result<&1, &1, U32 & String, Tls.Handle>) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.print("tls6wrong=ok")
    case Done{handle}:
      do IO<Unit>:
        Unit <- Tls.close(handle)
        IO.die(Unit, 1, "tls6wrong unexpectedly verified")

def tls6wrong_conn(+host: String, cr: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match cr:
    case Fail{_}:
      IO.die(Unit, 1, "tls6wrong connect failed")
    case Done{sock}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, Tls.Handle> <- Tls.open_for(sock, host, 5000)
        tls6wrong_opened(r)

def mode_tls6wrong(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("::1", port, 2000)
    tls6wrong_conn("127.0.0.1", cr)

# ---- tls6name (DNS SAN + SNI present, production transport path) ----------
def tls6name_bytes(conn: Tr.Conn, xs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("tls6name echo", bytes_show(xs), "104,101,108,108,111,")
    Unit <- Tr.close(conn)
    IO.print("tls6name=ok")

def tls6name_peer(conn: Tr.Conn, p: String & (U32 & List<&2, U32>)) -> IO(Unit):
  match p:
    case (_, rest):
      match rest:
        case (_, xs):
          tls6name_bytes(conn, xs)

def tls6name_got(conn: Tr.Conn, got: Maybe<&1, String & (U32 & List<&2, U32>)>) -> IO(Unit):
  match got:
    case None{}:
      do IO<Unit>:
        Unit <- Tr.close(conn)
        IO.die(Unit, 1, "tls6name parked")
    case Some{p}:
      tls6name_peer(conn, p)

def tls6name_recv(pair: Tr.Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>>) -> IO(Unit):
  match pair:
    case (conn, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Tr.close(conn)
            IO.die(Unit, 1, "tls6name recv failed")
        case Done{got}:
          tls6name_got(conn, got)

def tls6name_sent(pair: Tr.Conn & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (conn, r):
      match r:
        case Fail{_}:
          do IO<Unit>:
            Unit <- Tr.close(conn)
            IO.die(Unit, 1, "tls6name send failed")
        case Done{_}:
          do IO<Unit>:
            m : Tr.Conn & Result<&1, &1, U32 & String, Maybe<&1, String & (U32 & List<&2, U32>)>> <- Tr.recv_octets(conn, 4096)
            tls6name_recv(m)

def tls6name_conn(cr: Result<&1, &1, U32 & String, Tr.Conn>) -> IO(Unit):
  match cr:
    case Fail{_}:
      IO.die(Unit, 1, "tls6name connect failed")
    case Done{conn}:
      do IO<Unit>:
        sent : Tr.Conn & Result<&1, &1, U32 & String, Unit> <- Tr.send_for(conn, "hello", 2000)
        tls6name_sent(sent)

def mode_tls6name(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Tr.Conn> <- Tr.connect_for("::1", port, "birc.test", True{})
    tls6name_conn(cr)

# ---- tls6namewrong (DNS mismatch must fail, no fallback/downgrade) -------
def tls6namewrong_conn(cr: Result<&1, &1, U32 & String, Tr.Conn>) -> IO(Unit):
  match cr:
    case Done{conn}:
      do IO<Unit>:
        Unit <- Tr.close(conn)
        IO.die(Unit, 1, "tls6namewrong unexpectedly verified")
    case Fail{_}:
      IO.print("tls6namewrong=ok")

def mode_tls6namewrong(+port: U32) -> IO(Unit):
  do IO<Unit>:
    cr : Result<&1, &1, U32 & String, Tr.Conn> <- Tr.connect_for("::1", port, "wrong.test", True{})
    tls6namewrong_conn(cr)

# ---- dispatch ------------------------------------------------------------

def run_tlsnamewrong(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_tls6namewrong(port)
    case False{}:
      IO.die(Unit, 1, "unknown mode: " ++ mode)

def run_tlsname(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_tls6name(port)
    case False{}:
      run_tlsnamewrong(mode, port, String.eq(mode, "tls6namewrong"))

def run_dualdns(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_dualdns(port)
    case False{}:
      run_tlsname(mode, port, String.eq(mode, "tls6name"))

def run_dualdnslazy(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_dualdnslazy(port)
    case False{}:
      run_dualdns(mode, port, String.eq(mode, "dualdns"))

def run_dualwin(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_dual6win(port)
    case False{}:
      run_dualdnslazy(mode, port, String.eq(mode, "dualdnslazy"))

def run_dualfb(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_dualfb(port)
    case False{}:
      run_dualwin(mode, port, String.eq(mode, "dual6win"))

def run_dnstcp(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_dns6tcp(port)
    case False{}:
      run_dualfb(mode, port, String.eq(mode, "dualfb"))

def run_dnsfb(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_dns6fb(port)
    case False{}:
      run_dnstcp(mode, port, String.eq(mode, "dns6tcp"))

def run_v6udp(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_v6udp(port)
    case False{}:
      run_dnsfb(mode, port, String.eq(mode, "dns6fb"))

def run_bad(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_dial6bad(port)
    case False{}:
      run_v6udp(mode, port, String.eq(mode, "v6udp"))

def run_eof(+mode: String, +port: U32, is_x: Bool) -> IO(Unit):
  match is_x:
    case True{}:
      mode_dial6eof(port)
    case False{}:
      run_bad(mode, port, String.eq(mode, "dial6bad"))

def run_tls6wrong(+mode: String, +port: U32, is_wrong: Bool) -> IO(Unit):
  match is_wrong:
    case True{}:
      mode_tls6wrong(port)
    case False{}:
      run_eof(mode, port, String.eq(mode, "dial6eof"))

def run_tls6(+mode: String, +port: U32, is_tls: Bool) -> IO(Unit):
  match is_tls:
    case True{}:
      mode_tls6(port)
    case False{}:
      run_tls6wrong(mode, port, String.eq(mode, "tls6wrong"))

def run_v6dst(+mode: String, +port: U32, is_v6dst: Bool) -> IO(Unit):
  match is_v6dst:
    case True{}:
      mode_v6dst(port)
    case False{}:
      run_tls6(mode, port, String.eq(mode, "tls6"))

def run_dns6(+mode: String, +port: U32, is_dns: Bool) -> IO(Unit):
  match is_dns:
    case True{}:
      mode_dns6(port)
    case False{}:
      run_v6dst(mode, port, String.eq(mode, "v6dst"))

def run_refused(+mode: String, +port: U32, is_refused: Bool) -> IO(Unit):
  match is_refused:
    case True{}:
      mode_dial6refused(port)
    case False{}:
      run_dns6(mode, port, String.eq(mode, "dns6"))

def run_dial(+mode: String, +port: U32, is_dial: Bool) -> IO(Unit):
  match is_dial:
    case True{}:
      mode_dial6(port)
    case False{}:
      run_refused(mode, port, String.eq(mode, "dial6refused"))

def run_mode(+mode: String, +port: U32) -> IO(Unit):
  run_dial(mode, port, String.eq(mode, "dial6"))

def port_read(+mode: String, got: Maybe<&2, U32>) -> IO(Unit):
  match got:
    case None{}:
      IO.die(Unit, 1, "invalid port")
    case Some{+port}:
      run_mode(mode, port)

def args_probe(+mode: String, is_probe: Bool) -> IO(Unit):
  match is_probe:
    case True{}:
      mode_bind6probe()
    case False{}:
      IO.die(Unit, 1, "expected port")

def args_bare(+mode: String, is_literal: Bool) -> IO(Unit):
  match is_literal:
    case True{}:
      mode_literal()
    case False{}:
      args_probe(mode, String.eq(mode, "bind6probe"))

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+mode, rest}}:
      match rest:
        case Nil{}:
          args_bare(mode, String.eq(mode, "literal"))
        case Con{port, Nil{}}:
          port_read(mode, U32.read(port))
        case _:
          IO.die(Unit, 1, "expected MODE [PORT]")
    case _:
      IO.die(Unit, 1, "expected MODE [PORT]")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
