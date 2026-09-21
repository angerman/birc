# M4 net goldens — loopback TCP + fold_lines PONG/001. Assert.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/frame.bend as Fr
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/session.bend as Sess
import ./session_preds.bend as SP
import ../../src/bend/net.bend as IoNet

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
        && Nat.is_eq(CL.nbuf(cl), 1n)
        && Nat.is_eq(CL.buf_nlines(cl, 0n), 1n)

def fold_ok() -> Bool:
  fold_ok.on(Sess.fold_lines(Cl.init("me", "s"), "PING :abc" <> ":irc.example.net 001 me :Welcome" <> Nil{}))

def show_outs(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+h, t}:
      h ++ "|" ++ show_outs(t)

def nick433_fold_reject.on(got: Cl.Client & List<&2, String>) -> Bool:
  match got:
    case (+cl, +outs):
      String.eq(Cl.nick_of(cl), "me") && String.eq(show_outs(outs), "")

def nick433_fold_reject() -> Bool:
  nick433_fold_reject.on(
    Sess.fold_lines(
      Cl.init("me", "s"),
      ":irc.example.net 433 me newnick :Nickname is already in use" <> Nil{}
    )
  )

def nick433_fold_retry.on(+want: String, got: Cl.Client & List<&2, String>) -> Bool:
  match got:
    case (+cl, +outs):
      String.eq(Cl.nick_of(cl), "me_") && String.eq(show_outs(outs), want)

def nick433_fold_star() -> Bool:
  nick433_fold_retry.on(
    "NICK me_|",
    Sess.fold_lines(
      Cl.init("me", "s"),
      ":irc.example.net 433 * me :Nickname is already in use" <> Nil{}
    )
  )

# A2: 433 retry keys on Client.nick. Demo used to init("me") while
# registration used --nick, so 433 * bob never retried.
def nick433_demo_mismatch() -> Bool:
  nick433_fold_reject.on(
    Sess.fold_lines(
      Cl.init("me", "s"),
      ":irc.example.net 433 * bob :Nickname is already in use" <> Nil{}
    )
  )

def nick433_demo_nick.on(got: Cl.Client & List<&2, String>) -> Bool:
  match got:
    case (+cl, +outs):
      String.eq(Cl.nick_of(cl), "bob_") && String.eq(show_outs(outs), "NICK bob_|")

def nick433_demo_nick() -> Bool:
  nick433_demo_nick.on(
    Sess.fold_lines(
      Cl.init("bob", "s"),
      ":irc.example.net 433 * bob :Nickname is already in use" <> Nil{}
    )
  )

def nick433_fold_same() -> Bool:
  nick433_fold_retry.on(
    "NICK me_|",
    Sess.fold_lines(
      Cl.init("me", "s"),
      ":irc.example.net 433 me me :Nickname is already in use" <> Nil{}
    )
  )

def welcome_octets() -> List<&2, U32>:
  Fr.string_to_octets(":irc.example.net 001 probe :Welcome\r\nPING :xyz\r\n")

def chunk_join_pong.on(got: Sess.Session & List<&2, String>) -> Bool:
  match got:
    case (_, outs):
      String.eq(show_outs(outs), "PONG :xyz|JOIN #t|")

def chunk_join_pong() -> Bool:
  chunk_join_pong.on(
    Sess.step_on_chunk(Sess.session_online(Sess.session0("probe", "h", "#t")), welcome_octets())
  )

def finish_report(+lines: List<&2, String>, client2: Socket, server2: Socket) -> IO(Unit):
  do IO<Unit>:
    Unit <- Socket.close(client2)
    Unit <- Socket.close(server2)
    Unit <- E.must_eq("reg", show_reg_pair(Sess.register_lines("bob")), "NICK bob|USER bob 0 * :bob")
    Unit <- E.must_eq("pong", Irc.pong_for("PING :x"), "PONG :x")
    Unit <- E.must_eq("line", first_line(lines), "PING :loopback")
    Unit <- E.must("rt", Fr.str_eq(first_line(lines), "PING :loopback"))
    Unit <- E.must("fold", fold_ok())
    Unit <- E.must("chunk_join_pong", chunk_join_pong())
    Unit <- E.must("nick433_reject", nick433_fold_reject())
    Unit <- E.must("nick433_star", nick433_fold_star())
    Unit <- E.must("nick433_same", nick433_fold_same())
    Unit <- E.must("nick433_demo_mismatch", nick433_demo_mismatch())
    Unit <- E.must("nick433_demo_nick", nick433_demo_nick())
    Unit <- E.must("rem_cleared", SP.rem_cleared_ok())
    Unit <- E.must("drop_cleared", SP.drop_cleared_ok())
    Unit <- E.must("fuel3", Nat.is_eq(Sess.live_fuel(3), 3n))
    Unit <- E.must("fuel70000", Nat.is_eq(Sess.live_fuel(70000), 70000n))
    IO.print("net_demo=ok")

def finish_push(got: List<&2, String> & List<&2, U32>, client2: Socket, server2: Socket) -> IO(Unit):
  match got:
    case (+lines, _):
      finish_report(lines, client2, server2)

def finish_drop(
  pair: Socket & Bool,
  +chunk: String,
  server2: Socket
) -> IO(Unit):
  match pair:
    case (client3, ok):
      do IO<Unit>:
        Unit <- E.must("send_fuel0", Bool.not(ok))
        finish_push(Fr.push(Nil{}, Fr.string_to_octets(chunk)), client3, server2)

def finish_recv(sl: Socket & String, client2: Socket) -> IO(Unit):
  match sl:
    case (server2, chunk):
      do IO<Unit>:
        dropped : Socket & Bool <- IoNet.send_lines(0n, client2, "PING :drop" <> Nil{})
        finish_drop(dropped, chunk, server2)

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
