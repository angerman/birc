# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess

def command(triple: Sess.Session & Sess.NetCmd & Bool) -> String:
  match triple:
    case (_, cmd, _): Sess.show_netcmd(cmd)

def demo(input: String) -> String:
  command(Sess.step_enter(Sess.session_demo(Cl.init("me", "demo"), "#t"), input))

def at(port: U32, input: String) -> String:
  command(Sess.step_enter(Sess.session_online(Sess.session_with_client_at(Cl.init("me", "old.example"), "#t", port)), input))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("inline port is split from the host", demo("/connect irc.example.net:7000"), "dial:irc.example.net:7000")
    Unit <- E.must_eq("IPv4 inline port is split", demo("/connect 127.0.0.1:7000"), "dial:127.0.0.1:7000")
    Unit <- E.must_eq("matching separate port is accepted", demo("/connect irc.example.net:7000 7000"), "dial:irc.example.net:7000")
    Unit <- E.must_eq("different separate port is refused", demo("/connect irc.example.net:7000 7001"), "cont")
    Unit <- E.must_eq("default session chooses secure port", demo("/connect irc.example.net"), "dial:irc.example.net:6697")
    Unit <- E.must_eq("current explicit port is inherited", at(7000, "/connect next.example"), "dial:next.example:7000")
    Unit <- E.must_eq("current plaintext port is inherited", at(6667, "/connect next.example"), "dial:next.example:6667")
    Unit <- E.must_eq("separate port overrides inherited port", at(7000, "/connect next.example 7001"), "dial:next.example:7001")
    Unit <- E.must_eq("reconnect preserves exact saved endpoint", at(7000, "/reconnect"), "dial:old.example:7000")
    Unit <- E.must_eq("empty host is refused", demo("/connect :7000"), "cont")
    Unit <- E.must_eq("missing inline port is refused", demo("/connect irc.example.net:"), "cont")
    Unit <- E.must_eq("zero inline port is refused", demo("/connect irc.example.net:0"), "cont")
    Unit <- E.must_eq("oversized inline port is refused", demo("/connect irc.example.net:65536"), "cont")
    Unit <- E.must_eq("multiple colon syntax is refused", demo("/connect irc.example.net:7000:7001"), "cont")
    Unit <- E.must_eq("extra port token is refused", demo("/connect irc.example.net 7000 extra"), "cont")
    Unit <- E.must_eq("unsupported IPv6 stays refused", demo("/connect [::1]:7000"), "cont")
    IO.print("connect_endpoint=ok")
