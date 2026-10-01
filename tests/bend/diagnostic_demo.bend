# Pure diagnostic privacy and helper-result guards.
import Base
import ./expect.bend as E
import ../../src/bend/diagnostic.bend as D

def shown(r: Maybe<&2, String>) -> String:
  match r:
    case None{}: ""
    case Some{s}: s

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("plain", D.text("connected", "", ""), "connected")
    Unit <- E.must_eq("credentials", D.text("user=alice pass=secret", "alice", "secret"), "user=[redacted] pass=[redacted]")
    Unit <- E.must_eq("overlap", D.text("abc abc", "a", "abc"), "[redacted] [redacted]")
    Unit <- E.must_eq("url", D.text("failed (https://example.invalid/private?q=secret), retry", "", ""), "failed ([url]), retry")
    Unit <- E.must_eq("mixed_scheme", D.text("HTTPS://example.invalid/private", "", ""), "[url]")
    Unit <- E.must("styled_url", Bool.not(String.contains(D.text("_https://example.invalid/private_", "", ""), "example.invalid")))
    Unit <- E.must("code_url", Bool.not(String.contains(D.text("`https://example.invalid/private`", "", ""), "example.invalid")))
    Unit <- E.must_eq("code_secret", D.text("`secret`", "", "secret"), "`[redacted]`")
    Unit <- E.must("bounded", Nat.is_eq(String.length(D.text(String.repeat("x", 513n), "", "")), D.TEXT_CAP()))
    Unit <- E.must("secret_crosses_cap", Bool.not(String.contains(D.text(String.repeat("x", 510n) ++ "secret", "", "secret"), "secret")))
    Unit <- E.must_eq("helper_success", shown(D.process_result("opener", Done{(0, ("private", "secret"))})), "")
    Unit <- E.must_eq("helper_exit", shown(D.process_result("opener", Done{(3, ("private", "secret"))})), "opener failed (exit 3)")
    Unit <- E.must_eq("helper_os", shown(D.process_result("clipboard", Fail{(2, "private secret")})), "clipboard failed (OS 2)")
    IO.print("diagnostic_demo=ok\n")
