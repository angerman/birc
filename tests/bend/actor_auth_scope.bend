# SPDX-License-Identifier: Apache-2.0
# The writer cannot reuse a launch's SASL negotiation on another endpoint.
import Base
import ./expect.bend as E
import ../../src/bend/actor.bend as A
import ../../src/bend/session.bend as S

def enabled(scope: A.AuthScope) -> Bool:
  A.auth_scope_enabled(scope)

def handshake(scope: A.AuthScope) -> Bool:
  String.contains(String.join(S.handshake_lines("me", enabled(scope)), "|"), "CAP REQ :sasl")

def positive() -> Bool:
  +scope : A.AuthScope = A.AuthScope{"irc.example", 6667, True{}}
  enabled(A.auth_scope_dial(scope, "irc.example", 6667))
    && handshake(A.auth_scope_dial(scope, "irc.example", 6667))
    && Bool.not(enabled(A.auth_scope_dial(A.AuthScope{"irc.example", 6667, False{}}, "irc.example", 6667)))

def negative() -> Bool:
  +scope : A.AuthScope = A.AuthScope{"irc.example", 6667, True{}}
  +host = A.auth_scope_dial(scope, "other.example", 6667)
  +port = A.auth_scope_dial(scope, "irc.example", 6668)
  Bool.not(enabled(host) || enabled(port) || handshake(host) || handshake(port))
    && Bool.not(enabled(A.auth_scope_dial(host, "irc.example", 6667)))
    && Bool.not(enabled(A.auth_scope_dial(port, "irc.example", 6667)))
    && Bool.not(enabled(A.auth_scope_dial(scope, "IRC.example", 6667)))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("same endpoint preserves initial enabled/disabled scope", positive())
    Unit <- E.must("any endpoint mismatch permanently disables SASL negotiation", negative())
    IO.print("actor_auth_scope=ok")
