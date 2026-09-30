# Framed DNS lookup against the loopback peer provided by tests/dns/tcp.py.
import Base
import ../../src/bend/dns.bend as Dns
import ../../src/bend/dns_wire.bend as Wire

def show(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{+ip}: IO.print("ok:" ++ ip)
    case Fail{(_, +msg)}: IO.print("fail:" ++ msg)

def connected(r: Result<&1, &1, U32 & String, Socket>, q: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  match r:
    case Fail{_}: IO.die(Unit, 1, "local connect failed")
    case Done{sock}:
      match q:
        case Fail{_}: IO.die(Unit, 1, "query encode failed")
        case Done{+xs}:
          do IO<Unit>:
            answer : Result<&1, &1, U32 & String, String> <- Dns.lookup_tcp_sock(sock, 1, "a", xs)
            show(answer)

def port_read(got: Maybe<&2, U32>) -> IO(Unit):
  match got:
    case None{}: IO.die(Unit, 1, "invalid port")
    case Some{port}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, Socket> <- Dns.TCP.connect_for("127.0.0.1", port, 1000)
        connected(r, Wire.encode_id(1, "a"))

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{port, Nil{}}}: port_read(U32.read(port))
    case _: IO.die(Unit, 1, "expected port")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
