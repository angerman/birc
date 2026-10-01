# SPDX-License-Identifier: Apache-2.0
# Both credential fields keep CLI precedence and identical environment policy.
import Base
import ./expect.bend as E
import ../../src/bend/app.bend as A

def main() -> IO(Unit):
  do IO<Unit>:
    user : String <- A.resolve_sasl_user("cli-user")
    pass : String <- A.resolve_sasl_pass("cli-pass")
    fallback_user : String <- A.resolve_sasl_user("")
    fallback_pass : String <- A.resolve_sasl_pass("")
    expected_user : String <- IO.try(String, IO.get_env("BIRC_M21_EXPECT_USER"))
    expected_pass : String <- IO.try(String, IO.get_env("BIRC_M21_EXPECT_PASS"))
    Unit <- E.must_eq("user CLI override", user, "cli-user")
    Unit <- E.must_eq("pass CLI override", pass, "cli-pass")
    Unit <- E.must_eq("user fallback", fallback_user, expected_user)
    Unit <- E.must_eq("pass fallback", fallback_pass, expected_pass)
    IO.print("m21_sasl_env=ok")
