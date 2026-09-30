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
