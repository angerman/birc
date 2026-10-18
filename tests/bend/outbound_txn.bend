# Txn helpers for trace correlation: repeat/split/next with wrap-skip.
# Pure only, so the JS backend runs this without sockets.
import Base
import ./expect.bend as E
import ../../src/bend/outbound.bend as Out

def show_u32s(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, t}: U32.show(h) ++ "," ++ show_u32s(t)

def show_split(p: List<&2, U32> & List<&2, U32>) -> String:
  match p:
    case (+a, +b):
      show_u32s(a) ++ "|" ++ show_u32s(b)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("repeat3", show_u32s(Out.repeat_txn(7, 3n)), "7,7,7,")
    Unit <- E.must_eq("repeat0", show_u32s(Out.repeat_txn(7, 0n)), "")
    Unit <- E.must_eq("repeat1", show_u32s(Out.repeat_txn(0, 1n)), "0,")
    Unit <- E.must_eq("split0", show_split(Out.split_at_u32(1 <> 2 <> Nil{}, 0n)), "|1,2,")
    Unit <- E.must_eq("split2", show_split(Out.split_at_u32(1 <> 2 <> 3 <> Nil{}, 2n)), "1,2,|3,")
    Unit <- E.must_eq("split-over", show_split(Out.split_at_u32(1 <> Nil{}, 5n)), "1,|")
    Unit <- E.must_eq("split-empty", show_split(Out.split_at_u32(Nil{}, 3n)), "|")
    Unit <- E.must_eq("next1", U32.show(Out.next_batch_txn(1)), "2")
    Unit <- E.must_eq("next-wrap", U32.show(Out.next_batch_txn(4294967295)), "1")
    Unit <- E.must_eq("next-zero", U32.show(Out.next_batch_txn(0)), "1")
    Unit <- E.must_eq("next-high", U32.show(Out.next_batch_txn(2147483647)), "1")
    Unit <- E.must_eq("next-heal", U32.show(Out.next_batch_txn(2147483648)), "1")
    Unit <- E.must_eq("pong-first0", U32.show(Out.pong_first(0)), "2147483648")
    Unit <- E.must_eq("pong-first1", U32.show(Out.pong_first(1)), "2148532224")
    Unit <- E.must_eq("pong-first2", U32.show(Out.pong_first(2)), "2149580800")
    Unit <- E.must_eq("pong-next", U32.show(Out.next_pong_txn(2147483648)), "2147483649")
    # L1-src6 GATE4: exhausted PONG space FAILS CLOSED to 0 (unidentified,
    # never aliasing another gen), not wrap/overflow. The old pong-wrap
    # pinned wrap-to-P (aliasing gen0); the documented 2^20 ranges forbid
    # aliasing, so the wrap pin moves to 0 with top+wrap guards below.
    # Ordinary increment (pong-next) and gen0->1 (pong-first0/1) stay pinned.
    Unit <- E.must_eq("pong-wrap-closed", U32.show(Out.next_pong_txn(4294967295)), "0")
    Unit <- E.must_eq("pong-top0-closed", U32.show(Out.next_pong_txn(2148532223)), "0")
    Unit <- E.must_eq("pong-exhausted-stays", U32.show(Out.next_pong_txn(0)), "0")
    Unit <- E.must_eq("pong-first2048-closed", U32.show(Out.pong_first(2048)), "0")
    Unit <- E.must_eq("pong-last2048-closed", U32.show(Out.pong_last(2048)), "0")
    Unit <- E.must_eq("pong-last0", U32.show(Out.pong_last(0)), "2148532223")
    Unit <- E.must_eq("pong-last2047", U32.show(Out.pong_last(2047)), "4294967295")
    IO.print("outbound_txn=ok")
