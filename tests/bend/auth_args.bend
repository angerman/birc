# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/args.bend as A
import ../../src/bend/buffer.bend as Cl

def options(opts: A.AuthOptions) -> String:
  match opts:
    case A.AuthOptions{Cl.SaslOnly{}, prefix, success}: "sasl:" ++ prefix ++ ":" ++ success
    case A.AuthOptions{Cl.NickServOnly{}, prefix, success}: "nickserv:" ++ prefix ++ ":" ++ success
    case A.AuthOptions{Cl.SaslNickServ{}, prefix, success}: "fallback:" ++ prefix ++ ":" ++ success

def parsed(p: A.Parsed) -> String:
  match p:
    case A.Bad{_}: "bad"
    case A.Good{cfg}: options(A.auth_of(cfg))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("legacy defaults remain SASL", parsed(A.parse(Nil{})), "sasl::")
    Unit <- E.must_eq("explicit SASL mode", parsed(A.parse(["--auth", "sasl"])), "sasl::")
    Unit <- E.must_eq("NickServ requires identity", parsed(A.parse(["--auth", "nickserv"])), "bad")
    Unit <- E.must_eq("fallback requires success text", parsed(A.parse(["--auth", "sasl-nickserv", "--nickserv-prefix", "NickServ!service@services.test"])), "bad")
    Unit <- E.must_eq("invalid auth mode fails closed", parsed(A.parse(["--auth", "auto"])), "bad")
    Unit <- E.must_eq("missing auth mode fails closed", parsed(A.parse(["--auth"])), "bad")
    Unit <- E.must_eq("nickname alone is not a trusted service", parsed(A.parse(["--auth", "nickserv", "--nickserv-prefix", "NickServ", "--nickserv-success", "Confirmed"])), "bad")
    Unit <- E.must_eq("wildcard service is not trusted", parsed(A.parse(["--auth", "nickserv", "--nickserv-prefix", "NickServ!*@services.test", "--nickserv-success", "Confirmed"])), "bad")
    Unit <- E.must_eq("confirmation wire controls fail closed", parsed(A.parse(["--auth", "nickserv", "--nickserv-prefix", "NickServ!u@h", "--nickserv-success", "Confirmed\n"])), "bad")
    Unit <- E.must_eq("trusted NickServ flags preserve exact text", parsed(A.parse(["--auth", "nickserv", "--nickserv-prefix", "NickServ!service@services.test", "--nickserv-success", "Account confirmed"])), "nickserv:NickServ!service@services.test:Account confirmed")
    Unit <- E.must_eq("flag order preserves identity", parsed(A.parse(["--nickserv-success", "Confirmed", "--nickserv-prefix", "NickServ!u@h", "--auth", "sasl-nickserv"])), "fallback:NickServ!u@h:Confirmed")
    IO.print("auth_args=ok")
