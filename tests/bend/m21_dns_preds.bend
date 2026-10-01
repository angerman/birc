# SPDX-License-Identifier: Apache-2.0
# Pure reply fixtures for label identity and error-response validation.
import Base
import ../../src/bend/dns_wire.bend as W

def response(+id: U32, +flags: U32, +rcode: U32, +questions: U32, +answers: U32, +question: List<&2, U32>, body: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [0, id, flags, rcode, 0, questions, 0, answers, 0, 0, 0, 0],
    List.append(&2, U32, question, body))

def question(name: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, name, [0, 1, 0, 1])

def dotted() -> List<&2, U32>:
  [1, 97, 1, 98, 0]

def label_dot() -> List<&2, U32>:
  [3, 97, 46, 98, 0]

def answer(owner: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, owner, [0, 1, 0, 1, 0, 0, 0, 1, 0, 4, 1, 2, 3, 4])

def complete(question_name: List<&2, U32>, owner: List<&2, U32>) -> List<&2, U32>:
  response(1, 129, 128, 1, 1, question(question_name), answer(owner))

def error(+id: U32, +flags: U32, +questions: U32, question_name: List<&2, U32>) -> List<&2, U32>:
  response(id, flags, 131, questions, 0, question(question_name), Nil{})

def cname(target: List<&2, U32>) -> List<&2, U32>:
  response(1, 129, 128, 1, 2, question(dotted()),
    List.append(&2, U32,
      List.append(&2, U32, [192, 12, 0, 5, 0, 1, 0, 0, 0, 1, 0, 5], target),
      answer([1, 99, 1, 100, 0])))

def parsed.got(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{ip}: "ok:" ++ ip
    case Fail{(_, msg)}: "fail:" ++ msg

def parsed(xs: List<&2, U32>) -> String:
  parsed.got(W.parse_q(1, "a.b", xs))

def taken.got(t: W.Take) -> String:
  match t:
    case W.Miss{}: "miss"
    case W.HitOk{ip}: "ok:" ++ ip
    case W.HitErr{msg}: "fail:" ++ msg

def taken(xs: List<&2, U32>) -> String:
  taken.got(W.take_pkt("127.0.0.1", 1, "a.b", "127.0.0.1", 53, xs))

def label_identity_ok() -> Bool:
  String.eq(parsed(complete(dotted(), [192, 12])), "ok:1.2.3.4")
    && String.eq(parsed(complete(label_dot(), [192, 12])), "fail:bad dns")
    && String.eq(parsed(complete(dotted(), label_dot())), "fail:bad dns")
    && String.eq(parsed(cname([1, 99, 1, 100, 0])), "ok:1.2.3.4")
    && String.eq(parsed(cname([3, 99, 46, 100, 0])), "fail:bad dns")

def error_identity_ok() -> Bool:
  String.eq(taken(error(1, 129, 1, dotted())), "fail:rcode")
    && String.eq(taken(error(1, 129, 1, [1, 99, 0])), "miss")
    && String.eq(taken(error(1, 137, 1, dotted())), "miss")
