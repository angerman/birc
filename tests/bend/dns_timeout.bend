# K3: a nameserver that never answers must hit the fuel timeout.
# 127.0.0.2 drops UDP. wait_ans uses recv_nb, sleeps, and resends.
# A parked recv_octets would not return; the recipe kills it at 15 s.
import Base
import ./expect.bend as E
import ../../src/bend/dns.bend as Dns

def check_to(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{+ip}:
      E.must("timeout_done:" ++ ip, False{})
    case Fail{e}:
      match e:
        case (_, +msg):
          do IO<Unit>:
            Unit <- E.must_eq("timeout_msg", msg, "timeout")
            IO.print("dns_timeout=ok")

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.lookup_n("example.test", "127.0.0.2", 1)
    check_to(r)
