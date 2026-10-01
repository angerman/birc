# SPDX-License-Identifier: Apache-2.0
# Positive replies and negative identity mutations use the production parser.
import Base
import ./expect.bend as E
import ./dns_validation_preds.bend as P

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("valid_complete", P.parsed(P.complete(129)), "ok:1.2.3.4")
    Unit <- E.must_eq("valid_truncated", P.parsed(P.truncated(131, 128, 1, 97)), "fail:tc")
    Unit <- E.must_eq("complete_a_with_tc", P.parsed(P.complete(131)), "ok:1.2.3.4")
    Unit <- E.must_eq("unsupported_opcode", P.parsed(P.complete(137)), "fail:bad dns")
    Unit <- E.must_eq("unsupported_truncated_opcode", P.parsed(P.truncated(139, 128, 1, 97)), "fail:bad dns")
    Unit <- E.must_eq("truncated_wrong_question", P.parsed(P.truncated(131, 128, 1, 98)), "fail:bad dns")
    Unit <- E.must_eq("truncated_zero_questions", P.parsed(P.truncated(131, 128, 0, 97)), "fail:bad dns")
    Unit <- E.must_eq("truncated_error_rcode", P.parsed(P.truncated(131, 129, 1, 97)), "fail:rcode")
    Unit <- E.must_eq("take_valid_complete", P.taken(P.complete(129)), "ok:1.2.3.4")
    Unit <- E.must_eq("take_valid_truncated", P.taken(P.truncated(131, 128, 1, 97)), "fail:tc")
    Unit <- E.must_eq("take_unsupported_opcode", P.taken(P.complete(137)), "miss")
    Unit <- E.must_eq("take_wrong_truncated_question", P.taken(P.truncated(131, 128, 1, 98)), "miss")
    Unit <- E.must_eq("take_truncated_zero_questions", P.taken(P.truncated(131, 128, 0, 97)), "miss")
    Unit <- E.must_eq("take_truncated_error_rcode", P.taken(P.truncated(131, 129, 1, 97)), "fail:rcode")
    Unit <- E.must("opcode_guard", P.opcode_ok())
    Unit <- E.must("truncated_validation_guard", P.truncated_validation_ok())
    IO.print("dns_validation=ok")
