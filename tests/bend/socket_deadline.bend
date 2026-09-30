# Socket effect regression driver. All peers are local and owned by the test.
import Base
import ../../src/bend/dns.bend as Dns

def large_text(n: Nat, +s: String) -> String:
  match n:
    case 0n: s
    case 1n+p: large_text(p, s ++ s)

def sent(r: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match r:
    case Done{_}: IO.print("send:ok")
    case Fail{_}: IO.print("send:fail")

def close_sent(pair: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match pair:
    case (sock, r):
      do IO<Unit>:
        Unit <- Socket.close(sock)
        sent(r)

def connected(r: Result<&1, &1, U32 & String, Socket>, stall: Bool) -> IO(Unit):
  match r:
    case Fail{_}: IO.print("connect:fail")
    case Done{sock}:
      match stall:
        case False{}:
          do IO<Unit>:
            pair : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, "hello", 200)
            close_sent(pair)
        case True{}:
          do IO<Unit>:
            pair : Socket & Result<&1, &1, U32 & String, Unit> <- Dns.TCP.send_for(sock, large_text(19n, "0123456789abcdef"), 200)
            close_sent(pair)

def run(port: Maybe<&2, U32>, +mode: String) -> IO(Unit):
  match port:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{p}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("127.0.0.1", p, 1000)
        connected(r, String.eq(mode, "stall") || String.eq(mode, "large"))

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{port, Con{+mode, Nil{}}}}: run(U32.read(port), mode)
    case _: IO.die(Unit, 1, "expected port and mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
