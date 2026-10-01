# SPDX-License-Identifier: Apache-2.0
# DNS reply identity must be checked before answer parsing or TCP fallback.
import Base
import ../../src/bend/dns_wire.bend as W

def response(+flags: U32, +rcode: U32, +questions: U32, +answers: U32, +name: U32, body: List<&2, U32>) -> List<&2, U32>:
  0 <> 1 <> flags <> rcode <> 0 <> questions <> 0 <> answers <> 0 <> 0 <> 0 <> 0
    <> 1 <> name <> 0 <> 0 <> 1 <> 0 <> 1 <> body

def answer() -> List<&2, U32>:
  192 <> 12 <> 0 <> 1 <> 0 <> 1 <> 0 <> 0 <> 0 <> 1 <> 0 <> 4 <> 1 <> 2 <> 3 <> 4 <> Nil{}

def complete(flags: U32) -> List<&2, U32>:
  response(flags, 128, 1, 1, 97, answer())

def truncated(flags: U32, rcode: U32, questions: U32, name: U32) -> List<&2, U32>:
  response(flags, rcode, questions, 0, name, Nil{})

def parsed.got(got: Result<&1, &1, U32 & String, String>) -> String:
  match got:
    case Done{+ip}: "ok:" ++ ip
    case Fail{(_, +msg)}: "fail:" ++ msg

def parsed(xs: List<&2, U32>) -> String:
  parsed.got(W.parse_q(1, "a", xs))

def taken.got(got: W.Take) -> String:
  match got:
    case W.Miss{}: "miss"
    case W.HitOk{+ip}: "ok:" ++ ip
    case W.HitErr{+msg}: "fail:" ++ msg

def taken(xs: List<&2, U32>) -> String:
  taken.got(W.take_pkt("1.1.1.1", 1, "a", "1.1.1.1", 53, xs))

def opcode_ok() -> Bool:
  String.eq(parsed(complete(129)), "ok:1.2.3.4")
    && String.eq(parsed(complete(137)), "fail:bad dns")
    && String.eq(taken(complete(137)), "miss")

def truncated_validation_ok() -> Bool:
  String.eq(parsed(truncated(131, 128, 1, 97)), "fail:tc")
    && String.eq(parsed(truncated(131, 128, 1, 98)), "fail:bad dns")
    && String.eq(parsed(truncated(131, 128, 0, 97)), "fail:bad dns")
    && String.eq(parsed(truncated(131, 129, 1, 97)), "fail:rcode")
    && String.eq(parsed(complete(131)), "ok:1.2.3.4")
