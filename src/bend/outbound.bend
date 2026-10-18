# Pure outbound queue and credit rules. Actor IO consumes these batches.
import Base

def SEND_CAP() -> Nat:
  8n

def split_at.go(n: Nat, xs: List<&2, String>, acc: List<&2, String>) -> List<&2, String> & List<&2, String>:
  match n:
    case 0n:
      (List.reverse(&2, String, acc), xs)
    case 1n+p:
      match xs:
        case Nil{}:
          (List.reverse(&2, String, acc), Nil{})
        case Con{+h, t}:
          split_at.go(p, t, h <> acc)

def split_at(+xs: List<&2, String>, +n: Nat) -> List<&2, String> & List<&2, String>:
  split_at.go(n, xs, Nil{})

# Credits avoid U32 multiplication and a huge unary Nat frame budget.
# Each refill grants eight lines. Zero frames means unlimited.
type Budget is Data:
  Unlimited{}
  Limited{turns: U32, credit: U32}

type Batch is Data:
  Batch{now: List<&2, String>, later: List<&2, String>, budget: Budget}

def budget_frames.pick(unlimited: Bool, +frames: U32) -> Budget:
  match unlimited:
    case True{}: Unlimited{}
    case False{}: Limited{frames, 0}

def budget_frames(+frames: U32) -> Budget:
  budget_frames.pick(U32.is_zero(frames), frames)

def budget_refill(refill: Bool, +turns: U32, +credit: U32) -> Budget:
  match refill:
    case True{}: Limited{U32.sub(turns, 1), U32.from_nat(SEND_CAP())}
    case False{}: Limited{turns, credit}

def budget_ready(b: Budget) -> Budget:
  match b:
    case Unlimited{}: Unlimited{}
    case Limited{+turns, +credit}: budget_refill(U32.is_zero(credit) && Bool.not(U32.is_zero(turns)), turns, credit)

def budget_cap(b: Budget) -> Nat:
  match b:
    case Unlimited{}: SEND_CAP()
    case Limited{_, +credit}: Bool.pick(Nat, U32.is_gt(credit, U32.from_nat(SEND_CAP())), SEND_CAP(), U32.to_nat(credit))

def budget_after(b: Budget, used: Nat) -> Budget:
  match b:
    case Unlimited{}: Unlimited{}
    case Limited{turns, credit}: Limited{turns, U32.sub(credit, U32.from_nat(used))}

def budget_open(b: Budget) -> Bool:
  match b:
    case Unlimited{}: True{}
    case Limited{+turns, +credit}: Bool.not(U32.is_zero(turns) && U32.is_zero(credit))

def batch_parts(parts: List<&2, String> & List<&2, String>, b: Budget) -> Batch:
  match parts:
    case (+now, later): Batch{now, later, budget_after(b, List.length(&2, String, now))}

def batch_ready(+b: Budget, xs: List<&2, String>) -> Batch:
  batch_parts(split_at(xs, budget_cap(b)), b)

def batch(xs: List<&2, String>, b: Budget) -> Batch:
  batch_ready(budget_ready(b), xs)

# Transaction IDs for trace correlation. Cont batches use a fresh low-space
# txn per batch (Writer.next_txn, in [1, 2^31-1]); PONG requests use a
# carried high-space request ID minted by the reader (one per PING-carrying
# read) and shared by the reply (stage 6), the Chunk post/dequeue (stages
# 1/2), and the writer receive/send (stages 4/5), so every PONG hop matches
# by numeric identity, never by order. Pending carries each line's txn
# through FIFO so stage-5 sends match their stage-4 receive by ID. Txn 0
# means unidentified (non-PING chunks, stage 3, bare registration sends);
# it never matches a real request. PONG_TXN must equal the PONG-space base
# in tests/pty/net_trace.py exactly.
def pong_txn() -> U32:
  2147483648
# Request identity spaces (Gates 1+2, L1-src6 GATE4). Each generation owns
# one 2^20 range of PONG space starting at pong_first(gen), so repeated
# PINGs never alias across generations and a stale-gen reply can never
# match a new-gen receive. The Cont counter wraps below the PONG base and
# the PONG counter is pinned above it: the spaces are disjoint by
# construction, not by assertion. Bounds: 2048 generations x 2^20
# PING-carrying reads per connection; past either bound IDs FAIL CLOSED to
# 0 (unidentified, never PONG-space, never aliasing another gen) and the
# resolver refuses. No wrap, no overflow, no unbounded tracking.
def pong_stride() -> U32:
  1048576
def pong_gens() -> U32:
  2048
def pong_first.on(oor: Bool, +gen: U32) -> U32:
  match oor:
    case True{}: 0
    case False{}: U32.add(pong_txn(), U32.mul(gen, pong_stride()))
def pong_first(+gen: U32) -> U32:
  pong_first.on(U32.is_ge(gen, pong_gens()), gen)
def pong_last.on(oor: Bool, +gen: U32) -> U32:
  match oor:
    case True{}: 0
    case False{}: U32.add(pong_first(gen), U32.sub(pong_stride(), 1))
def pong_last(+gen: U32) -> U32:
  pong_last.on(U32.is_ge(gen, pong_gens()), gen)
def next_pong_gen(+cur: U32) -> U32:
  U32.div(U32.sub(cur, pong_txn()), pong_stride())
def next_pong_is_top(+cur: U32) -> Bool:
  U32.is_eq(cur, pong_last(next_pong_gen(cur)))
def next_pong_guarded.step(at_top: Bool, +cur: U32) -> U32:
  match at_top:
    case True{}: 0
    case False{}: U32.add(cur, 1)
def next_pong_guarded(exhausted: Bool, +cur: U32) -> U32:
  match exhausted:
    case True{}: 0
    case False{}: next_pong_guarded.step(next_pong_is_top(cur), cur)
def next_pong_txn(+cur: U32) -> U32:
  next_pong_guarded(U32.is_zero(cur) || U32.is_lt(cur, pong_txn()), cur)
def repeat_txn.go(n: Nat, +txn: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      List.reverse(&2, U32, acc)
    case 1n+p:
      repeat_txn.go(p, txn, txn <> acc)

def repeat_txn(+txn: U32, +n: Nat) -> List<&2, U32>:
  repeat_txn.go(n, txn, Nil{})

def split_at_u32.go(n: Nat, xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match n:
    case 0n:
      (List.reverse(&2, U32, acc), xs)
    case 1n+p:
      match xs:
        case Nil{}:
          (List.reverse(&2, U32, acc), Nil{})
        case Con{+h, t}:
          split_at_u32.go(p, t, h <> acc)

def split_at_u32(+xs: List<&2, U32>, +n: Nat) -> List<&2, U32> & List<&2, U32>:
  split_at_u32.go(n, xs, Nil{})

def next_batch_txn(+cur: U32) -> U32:
  +nxt = U32.add(cur, 1)
  Bool.pick(U32, U32.is_zero(nxt) || U32.is_ge(nxt, pong_txn()), 1, nxt)
