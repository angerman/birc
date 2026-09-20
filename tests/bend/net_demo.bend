# M4 net goldens — loopback TCP + fold_lines PONG/001. Assert.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/frame.bend as Fr
import ../../src/bend/client.bend as Cl
import ../../src/bend/session.bend as Net

def send_go(m: Socket & Result<&1, &1, (U32 & String), Unit>) -> IO(Socket):
  match m:
    case (s, r):
      do IO<Socket>:
        Unit <- IO.pass(Unit, r)
        return s

def recv_go(m: Socket & Result<&1, &1, (U32 & String), String>) -> IO(Socket & String):
  match m:
    case (s, r):
      do IO<Socket & String>:
        text : String <- IO.pass(String, r)
        return (s, text)

def tcp_retry(port: U32, r: Result<&1, &1, (U32 & String), Listener>, rest: IO(Listener & U32)) -> IO(Listener & U32):
  match r:
    case Done{l}:
      IO.pure(Listener & U32, (l, port))
    case Fail{_}:
      rest

def tcp_listen_any(tries: Nat, +port: U32) -> IO(Listener & U32):
  match tries:
    case 0n:
      IO.die(Listener & U32, 1, "no free tcp port")
    case 1n+t:
      rest = tcp_listen_any(t, U32.add(port, 1))
      do IO<Listener & U32>:
        r : Result<&1, &1, (U32 & String), Listener> <- TCP.listen(port)
        tcp_retry(port, r, rest)

def first_line(+xs: List<&2, String>) -> String:
  match xs:
    case Con{+h, _}:
      h
    case Nil{}:
      ""

def show_reg_pair(xs: List<&2, String>) -> String:
  match xs:
    case Con{+a, Con{+b, _}}:
      a ++ "|" ++ b
    case _:
      "reg=bad"

def fold_ok.on(got: Cl.Client & List<&2, String>) -> Bool:
  match got:
    case (+cl, +pongs):
      String.eq(first_line(pongs), "PONG :abc")
        && Nat.is_eq(Cl.nbuf(cl), 1n)
        && Nat.is_eq(Cl.buf_nlines(cl, 0n), 1n)

def fold_ok() -> Bool:
  fold_ok.on(Net.fold_lines(Cl.init("me", "s"), "PING :abc" <> ":irc.example.net 001 me :Welcome" <> Nil{}))

def finish_report(+lines: List<&2, String>, client2: Socket, server2: Socket) -> IO(Unit):
  do IO<Unit>:
    Unit <- Socket.close(client2)
    Unit <- Socket.close(server2)
    Unit <- E.must_eq("reg", show_reg_pair(Net.register_lines("bob")), "NICK bob|USER bob 0 * :bob")
    Unit <- E.must_eq("pong", Irc.pong_for("PING :x"), "PONG :x")
    Unit <- E.must_eq("line", first_line(lines), "PING :loopback")
    Unit <- E.must("rt", Fr.str_eq(first_line(lines), "PING :loopback"))
    Unit <- E.must("fold", fold_ok())
    Unit <- E.must("fuel_alias", Nat.is_eq(Net.live_fuel(3), Net.ticks_of(3)))
    Unit <- E.must("fuel3", Nat.is_eq(Net.live_fuel(3), 3n))
    IO.print("net_demo=ok")

def finish_push(got: List<&2, String> & String, client2: Socket, server2: Socket) -> IO(Unit):
  match got:
    case (+lines, _):
      finish_report(lines, client2, server2)

def finish_recv(sl: Socket & String, client2: Socket) -> IO(Unit):
  match sl:
    case (server2, chunk):
      finish_push(Fr.push_text("", chunk), client2, server2)

def after_accept(
  listener2: Listener,
  ar: Result<&1, &1, (U32 & String), Socket>,
  client: Socket
) -> IO(Unit):
  do IO<Unit>:
    server : Socket <- IO.pass(Socket, ar)
    Unit <- Listener.close(listener2)
    sm : Socket & Result<&1, &1, (U32 & String), Unit> <- TCP.send(client, "PING :loopback\r\n")
    client2 : Socket <- send_go(sm)
    rm : Socket & Result<&1, &1, (U32 & String), String> <- TCP.recv(server, 1024)
    sl : Socket & String <- recv_go(rm)
    finish_recv(sl, client2)

def after_accept_pair(ap: Listener & Result<&1, &1, (U32 & String), Socket>, client: Socket) -> IO(Unit):
  match ap:
    case (listener2, ar):
      after_accept(listener2, ar, client)

def after_listen(lp: Listener & U32) -> IO(Unit):
  match lp:
    case (listener, port):
      do IO<Unit>:
        client : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", port))
        ap : Listener & Result<&1, &1, (U32 & String), Socket> <- TCP.accept(listener)
        after_accept_pair(ap, client)

def main() -> IO(Unit):
  do IO<Unit>:
    lp : Listener & U32 <- tcp_listen_any(32n, 19000)
    after_listen(lp)
