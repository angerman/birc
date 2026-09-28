import Base
import ./expect.bend as E
import ../../src/bend/base64.bend as B64

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("sasl_user_pass", String.eq(B64.sasl_plain("user", "pass"), "AHVzZXIAcGFzcw=="))
    Unit <- E.must("sasl_alice_secret", String.eq(B64.sasl_plain("alice", "secret"), "AGFsaWNlAHNlY3JldA=="))
    Unit <- E.must("sasl_empty", String.eq(B64.sasl_plain("", ""), "AAA="))
    Unit <- E.must("sasl_ok_fn", B64.sasl_plain_ok())
    IO.print("base64_demo=ok")
