# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/args.bend as A

def port(got: A.Parsed) -> String:
  match got:
    case A.Bad{msg}: "bad:" ++ msg
    case A.Good{A.Cfg{_, _, _, p, _, _, _, _, _, _, _, _, _}}: U32.show(p)

def secure(got: A.Parsed) -> String:
  match got:
    case A.Bad{msg}: "bad:" ++ msg
    case A.Good{A.Cfg{_, _, _, _, _, _, _, _, _, _, _, tls, _}}:
      Bool.show(tls)

def endpoint(got: A.Parsed) -> String:
  match got:
    case A.Bad{msg}: "bad:" ++ msg
    case A.Good{A.Cfg{_, _, host, p, _, _, _, _, _, _, _, tls, _}}:
      host ++ ":" ++ U32.show(p) ++ ":" ++ Bool.show(tls)

def many_mode(n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n: acc
    case 1n+p: many_mode(p, "--plain" <> acc)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("TLS chooses secure default", port(A.parse(["--connect", "irc.example", "--tls"])), "6697")
    Unit <- E.must_eq("TLS before host chooses secure default", port(A.parse(["--tls", "--connect", "irc.example"])), "6697")
    Unit <- E.must_eq("explicit port before TLS remains", port(A.parse(["--port", "7000", "--tls", "--connect", "irc.example"])), "7000")
    Unit <- E.must_eq("explicit port after TLS remains", port(A.parse(["--tls", "--port", "7000", "--connect", "irc.example"])), "7000")
    Unit <- E.must_eq("explicit plaintext-number port not replaced", port(A.parse(["--port", "6667", "--tls"])), "6667")
    Unit <- E.must_eq("default verified transport chooses secure port", port(A.parse(["--connect", "irc.example"])), "6697")
    Unit <- E.must_eq("offline default is secure", endpoint(A.parse(Nil{})), ":6697:True")
    Unit <- E.must_eq("plain opts out and chooses legacy port", endpoint(A.parse(["--plain", "--connect", "irc.example"])), "irc.example:6667:False")
    Unit <- E.must_eq("plain after host has same default", endpoint(A.parse(["--connect", "irc.example", "--plain"])), "irc.example:6667:False")
    Unit <- E.must_eq("known TLS port accepted", port(A.parse(["--port", "6697", "--connect", "irc.example"])), "6697")
    Unit <- E.must_eq("default verifies on secure-number port", secure(A.parse(["--port", "6697"])), "True")
    Unit <- E.must_eq("TLS flag enables verification on alternate port", secure(A.parse(["--tls", "--port", "7000"])), "True")
    Unit <- E.must_eq("port does not disable default TLS", secure(A.parse(["--port", "6667"])), "True")
    Unit <- E.must_eq("custom port does not disable TLS", secure(A.parse(["--port", "7000"])), "True")
    Unit <- E.must_eq("plain remains plain on TLS-number port", endpoint(A.parse(["--plain", "--port", "6697"])), ":6697:False")
    Unit <- E.must_eq("port before plain stays exact", endpoint(A.parse(["--port", "7000", "--plain"])), ":7000:False")
    Unit <- E.must_eq("plain before port stays exact", endpoint(A.parse(["--plain", "--port", "7000"])), ":7000:False")
    Unit <- E.must_eq("explicit 6667 with TLS stays secure", secure(A.parse(["--tls", "--port", "6667"])), "True")
    Unit <- E.must_eq("invalid port still refused", port(A.parse(["--tls", "--port", "0"])), "bad:birc: --port out of range")
    Unit <- E.must_eq("missing port still refused", port(A.parse(["--tls", "--port"])), "bad:birc: missing value")
    Unit <- E.must_eq("tls then plain conflict", port(A.parse(["--tls", "--plain"])), "bad:birc: --tls and --plain conflict")
    Unit <- E.must_eq("plain then tls conflict", port(A.parse(["--plain", "--tls"])), "bad:birc: --tls and --plain conflict")
    Unit <- E.must_eq("duplicate same mode allowed", endpoint(A.parse(["--plain", "--plain"])), ":6667:False")
    Unit <- E.must_eq("mode flags retain ordinary fuel bound", port(A.parse(many_mode(32n, Nil{}))), "6667")
    Unit <- E.must_eq("a flag-shaped value is not a mode selector", endpoint(A.parse(["--nick", "--plain"])), ":6697:True")
    Unit <- E.must_eq("inline endpoint keeps exact host", endpoint(A.parse(["--connect", "IRC.Example.:7000"])), "IRC.Example.:7000:True")
    Unit <- E.must_eq("IPv4 shorthand plain", endpoint(A.parse(["--plain", "--connect", "127.0.0.1:7000"])), "127.0.0.1:7000:False")
    Unit <- E.must_eq("same separate port after inline allowed", endpoint(A.parse(["--connect", "h:7000", "--port", "7000"])), "h:7000:True")
    Unit <- E.must_eq("same separate port before inline allowed", endpoint(A.parse(["--port", "7000", "--connect", "h:7000"])), "h:7000:True")
    Unit <- E.must_eq("differing separate port after inline refused", endpoint(A.parse(["--connect", "h:7000", "--port", "7001"])), "bad:birc: conflicting port values")
    Unit <- E.must_eq("differing separate port before inline refused", endpoint(A.parse(["--port", "7001", "--connect", "h:7000"])), "bad:birc: conflicting port values")
    Unit <- E.must_eq("differing repeated explicit ports refused", port(A.parse(["--port", "7000", "--port", "7001"])), "bad:birc: conflicting port values")
    Unit <- E.must_eq("same repeated explicit ports accepted", port(A.parse(["--port", "7000", "--port", "7000"])), "7000")
    Unit <- E.must_eq("empty inline port refused", endpoint(A.parse(["--connect", "h:"])), "bad:birc: --connect bad port")
    Unit <- E.must_eq("IPv6 endpoint refused", endpoint(A.parse(["--connect", "[::1]:6697"])), "bad:birc: --connect bad endpoint")
    Unit <- E.must_eq("URL endpoint refused", endpoint(A.parse(["--connect", "https://h"])), "bad:birc: --connect bad endpoint")
    IO.print("tls_args=ok")
