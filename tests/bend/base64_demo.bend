import Base
import ./expect.bend as E
import ../../src/bend/base64.bend as B64
import ../../src/bend/submit.bend as Sub

def repeat(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "a" ++ repeat(p)

def chunks399(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+h, Nil{}}:
      String.eq(h, "AUTHENTICATE " ++ repeat(399n))
    case _: False{}

def chunks400(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+h, Con{+end, Nil{}}}:
      String.eq(h, "AUTHENTICATE " ++ repeat(400n)) && String.eq(end, "AUTHENTICATE +")
    case _: False{}

def chunks401(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+h, Con{+end, Nil{}}}:
      String.eq(h, "AUTHENTICATE " ++ repeat(400n)) && String.eq(end, "AUTHENTICATE a")
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("sasl_user_pass", String.eq(B64.sasl_plain("user", "pass"), "AHVzZXIAcGFzcw=="))
    Unit <- E.must("sasl_alice_secret", String.eq(B64.sasl_plain("alice", "secret"), "AGFsaWNlAHNlY3JldA=="))
    Unit <- E.must("sasl_empty", String.eq(B64.sasl_plain("", ""), "AAA="))
    Unit <- E.must("sasl_utf8", String.eq(B64.sasl_plain("user", "é"), "AHVzZXIAw6k="))
    Unit <- E.must("chunks399", chunks399(B64.authenticate_chunks(repeat(399n))))
    Unit <- E.must("chunks400", chunks400(B64.authenticate_chunks(repeat(400n))))
    Unit <- E.must("chunks401", chunks401(B64.authenticate_chunks(repeat(401n))))
    Unit <- E.must("chunk_line_limits", Sub.out_all_ok(B64.authenticate_chunks(repeat(1200n))))
    Unit <- E.must("sasl_ok_fn", B64.sasl_plain_ok())
    IO.print("base64_demo=ok")
