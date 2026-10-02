# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/args.bend as A
import ../../src/bend/transport_policy.bend as Policy

def port(got: A.Parsed) -> String:
  match got:
    case A.Bad{msg}: "bad:" ++ msg
    case A.Good{A.Cfg{_, _, _, p, _, _, _, _, _, _, _, _, _}}: U32.show(p)

def secure(got: A.Parsed) -> String:
  match got:
    case A.Bad{msg}: "bad:" ++ msg
    case A.Good{A.Cfg{_, _, _, p, _, _, _, _, _, _, _, tls, _}}:
      Bool.show(Policy.enabled(tls, p))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("TLS chooses secure default", port(A.parse(["--connect", "irc.example", "--tls"])), "6697")
    Unit <- E.must_eq("TLS before host chooses secure default", port(A.parse(["--tls", "--connect", "irc.example"])), "6697")
    Unit <- E.must_eq("explicit port before TLS remains", port(A.parse(["--port", "7000", "--tls", "--connect", "irc.example"])), "7000")
    Unit <- E.must_eq("explicit port after TLS remains", port(A.parse(["--tls", "--port", "7000", "--connect", "irc.example"])), "7000")
    Unit <- E.must_eq("explicit plaintext-number port not replaced", port(A.parse(["--port", "6667", "--tls"])), "6667")
    Unit <- E.must_eq("legacy plain default unchanged", port(A.parse(["--connect", "irc.example"])), "6667")
    Unit <- E.must_eq("known TLS port accepted", port(A.parse(["--port", "6697", "--connect", "irc.example"])), "6697")
    Unit <- E.must_eq("TLS port enables verification without flag", secure(A.parse(["--port", "6697"])), "True")
    Unit <- E.must_eq("TLS flag enables verification on alternate port", secure(A.parse(["--tls", "--port", "7000"])), "True")
    Unit <- E.must_eq("legacy port stays plaintext", secure(A.parse(["--port", "6667"])), "False")
    Unit <- E.must_eq("explicit 6667 with TLS stays secure", secure(A.parse(["--tls", "--port", "6667"])), "True")
    Unit <- E.must_eq("invalid port still refused", port(A.parse(["--tls", "--port", "0"])), "bad:birc: --port out of range")
    Unit <- E.must_eq("missing port still refused", port(A.parse(["--tls", "--port"])), "bad:birc: missing value")
    IO.print("tls_args=ok")
