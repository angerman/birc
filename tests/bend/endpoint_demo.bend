# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/endpoint.bend as Ep

def optional(n: Maybe<&2, U32>) -> String:
  match n:
    case None{}: "none"
    case Some{n}: U32.show(n)

def parsed(got: Result<&2, &2, String, Ep.Endpoint>) -> String:
  match got:
    case Fail{msg}: "bad:" ++ msg
    case Done{Ep.Endpoint{host, p}}: host ++ ":" ++ optional(p)

def resolved(got: Maybe<&1, String & U32>) -> String:
  match got:
    case None{}: "conflict"
    case Some{(host, p)}: host ++ ":" ++ U32.show(p)

def repeated(n: Nat, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p: repeated(p, "a" ++ acc)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("DNS without port retains absence", parsed(Ep.parse("irc.example")), "irc.example:none")
    Unit <- E.must_eq("IPv4 shorthand", parsed(Ep.parse("127.0.0.1:7000")), "127.0.0.1:7000")
    Unit <- E.must_eq("root dot and case remain identity", parsed(Ep.parse("IRC.Example.:6697")), "IRC.Example.:6697")
    Unit <- E.must_eq("minimum inline port", parsed(Ep.parse("h:1")), "h:1")
    Unit <- E.must_eq("maximum inline port", parsed(Ep.parse("h:65535")), "h:65535")
    Unit <- E.must_eq("leading-zero spelling", parsed(Ep.parse("h:00007000")), "h:7000")
    Unit <- E.must_eq("empty endpoint", parsed(Ep.parse("")), "bad:bad endpoint")
    Unit <- E.must_eq("missing host", parsed(Ep.parse(":6697")), "bad:bad endpoint")
    Unit <- E.must_eq("missing inline port", parsed(Ep.parse("h:")), "bad:bad port")
    Unit <- E.must_eq("zero inline port", parsed(Ep.parse("h:0")), "bad:bad port")
    Unit <- E.must_eq("oversized inline port", parsed(Ep.parse("h:65536")), "bad:bad port")
    Unit <- E.must_eq("U32 overflow", parsed(Ep.parse("h:4294967296")), "bad:bad port")
    Unit <- E.must_eq("nondecimal inline port", parsed(Ep.parse("h:+6697")), "bad:bad endpoint")
    Unit <- E.must_eq("port letters", parsed(Ep.parse("h:tls")), "bad:bad port")
    Unit <- E.must_eq("multiple colons", parsed(Ep.parse("h:6697:7000")), "bad:bad endpoint")
    Unit <- E.must_eq("IPv6 brackets unsupported", parsed(Ep.parse("[::1]:6697")), "bad:bad endpoint")
    Unit <- E.must_eq("bare IPv6 unsupported", parsed(Ep.parse("::1")), "bad:bad endpoint")
    Unit <- E.must_eq("URL is not endpoint", parsed(Ep.parse("https://irc.example")), "bad:bad endpoint")
    Unit <- E.must_eq("prose is not endpoint", parsed(Ep.parse("irc.example extra")), "bad:bad endpoint")
    Unit <- E.must_eq("control is not endpoint", parsed(Ep.parse("irc.example\n")), "bad:bad endpoint")
    Unit <- E.must_eq("nonASCII DNS unsupported", parsed(Ep.parse("서울.example")), "bad:bad endpoint")
    Unit <- E.must_eq("empty interior label", parsed(Ep.parse("irc..example")), "bad:bad endpoint")
    Unit <- E.must_eq("double terminal dot", parsed(Ep.parse("irc.example..")), "bad:bad endpoint")
    Unit <- E.must_eq("root is not host", parsed(Ep.parse(".")), "bad:bad endpoint")
    Unit <- E.must("63-byte label accepted", Ep.host_ok(repeated(63n, "")))
    Unit <- E.must("64-byte label denied", Bool.not(Ep.host_ok(repeated(64n, ""))))
    +maximum : String = repeated(63n, "") ++ "." ++ repeated(63n, "") ++ "." ++ repeated(63n, "") ++ "." ++ repeated(61n, "")
    Unit <- E.must("253-byte relative name accepted", Ep.host_ok(maximum))
    Unit <- E.must("254-byte root-dotted name accepted", Ep.host_ok(maximum ++ "."))
    Unit <- E.must_eq("260-byte shorthand accepted", parsed(Ep.parse(maximum ++ ".:65535")), maximum ++ ".:65535")
    Unit <- E.must_eq("261-byte shorthand denied", parsed(Ep.parse(maximum ++ ".:065535")), "bad:bad endpoint")
    Unit <- E.must("254-byte relative name denied", Bool.not(Ep.host_ok(maximum ++ "a")))
    Unit <- E.must_eq("port1", optional(Ep.port("1")), "1")
    Unit <- E.must_eq("port65535", optional(Ep.port("65535")), "65535")
    Unit <- E.must_eq("port0 refused", optional(Ep.port("0")), "none")
    Unit <- E.must_eq("port whitespace refused", optional(Ep.port(" 1")), "none")
    Unit <- E.must_eq("port sign refused", optional(Ep.port("+1")), "none")
    Unit <- E.must_eq("same numeric ports accepted", optional(Ep.select_port(Some{7000}, Ep.port("07000"), 6697)), "7000")
    Unit <- E.must_eq("conflicting ports denied", optional(Ep.select_port(Some{7000}, Some{7001}, 6697)), "none")
    Unit <- E.must_eq("absent uses selected fallback", resolved(Ep.resolve(Ep.Endpoint{"h", None{}}, None{}, 6667)), "h:6667")
    Unit <- E.must_eq("inline overrides fallback", resolved(Ep.resolve(Ep.Endpoint{"h", Some{7000}}, None{}, 6697)), "h:7000")
    Unit <- E.must_eq("separate overrides fallback", resolved(Ep.resolve(Ep.Endpoint{"h", None{}}, Some{7000}, 6697)), "h:7000")
    Unit <- E.must_eq("conflict never resolves", resolved(Ep.resolve(Ep.Endpoint{"h", Some{7000}}, Some{7001}, 6697)), "conflict")
    IO.print("endpoint_demo=ok")
