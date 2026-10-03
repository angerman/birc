# SPDX-License-Identifier: Apache-2.0
# ACTION needs a positive body budget, even when CR/LF cleanup empties the body.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/irc.bend as Irc
import ../../src/bend/submit.bend as S

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def target(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "a" ++ target(p)

def named_query(name: String) -> Cl.Client:
  client(S.submit(Cl.init("me", "irc.example"), "/query " ++ name))

def query(n: Nat) -> Cl.Client:
  named_query(target(n))

def rejected(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, outs): List.is_empty(&2, String, outs)

def exact(pair: Cl.Client & List<&2, String>, want: String) -> Bool:
  match pair:
    case (_, +outs): S.out_all_ok(outs) && String.eq(String.join(outs, "|"), want)

def wire(n: Nat, body: String) -> String:
  Irc.format_privmsg(target(n), S.ctcp_action(body))

def zero_clean_rejected() -> Bool:
  rejected(S.submit(query(491n), "/me " ++ SCon{Chr{13}, SCon{Chr{10}, ""}}))

def zero_text_rejected() -> Bool:
  rejected(S.submit(query(491n), "/me x"))

def fitting_text_exact() -> Bool:
  exact(S.submit(query(490n), "/me x"), wire(490n, "x"))

def positive_clean_empty_exact() -> Bool:
  exact(S.submit(query(490n), "/me " ++ SCon{Chr{13}, SCon{Chr{10}, ""}}), wire(490n, ""))

def oversized_clean_rejected() -> Bool:
  rejected(S.submit(query(492n), "/me " ++ SCon{Chr{13}, ""}))

def ordinary_text_exact() -> Bool:
  exact(S.submit(named_query("alice"), "/me waves"), Irc.format_privmsg("alice", S.ctcp_action("waves")))

def original_empty_rejected() -> Bool:
  rejected(S.submit(named_query("alice"), "/me"))

def malformed_target_rejected() -> Bool:
  rejected(S.submit(named_query(":alice"), "/me waves"))

def malformed_plain_rejected() -> Bool:
  rejected(S.submit(named_query(":alice"), "waves"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("zero ACTION body budget rejects sanitized-empty body", zero_clean_rejected())
    Unit <- E.must("zero ACTION body budget rejects nonempty body", zero_text_rejected())
    Unit <- E.must("one-byte ACTION body budget retains fitting text", fitting_text_exact())
    Unit <- E.must("positive ACTION body budget preserves sanitized-empty behavior", positive_clean_empty_exact())
    Unit <- E.must("oversize ACTION target rejects sanitized-empty body", oversized_clean_rejected())
    Unit <- E.must("ordinary ACTION text remains exact", ordinary_text_exact())
    Unit <- E.must("empty original ACTION retains usage rejection", original_empty_rejected())
    Unit <- E.must("malformed ACTION target rejects without sending", malformed_target_rejected())
    Unit <- E.must("malformed plain target remains rejected", malformed_plain_rejected())
    IO.print("action_budget=ok\n")
