# Live A lookup of one.one.one.one. Not in make check.
import Base
import ./expect.bend as E
import ../../src/bend/dns.bend as Dns

def live_addr_ok(+ip: String) -> Bool:
  String.eq(ip, "1.1.1.1") || String.eq(ip, "1.0.0.1")

def live_fail_ok(+msg: String) -> Bool:
  String.eq(msg, "timeout") || String.eq(msg, "bind") || String.eq(msg, "send") || String.eq(msg, "recv") || String.eq(msg, "random") || String.eq(msg, "bad id") || String.eq(msg, "bad dns") || String.eq(msg, "no A") || String.eq(msg, "short") || String.eq(msg, "tc") || String.eq(msg, "rcode") || String.eq(msg, "ipv6") || String.eq(msg, "no nameserver")

def check_live(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{+ip}:
      do IO<Unit>:
        Unit <- E.must("live_addr", live_addr_ok(ip))
        IO.print("name=ok:" ++ ip)
    case Fail{e}:
      match e:
        case (_, +msg):
          do IO<Unit>:
            Unit <- E.must("live_fail:" ++ msg, live_fail_ok(msg))
            IO.print("name=fail:" ++ msg)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve("one.one.one.one")
    Unit <- check_live(r)
    IO.print("dns_live=ok")
