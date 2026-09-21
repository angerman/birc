# Nat fuel helpers. Pure. No IO.
import Base

def u32_to_nat.step(fuel: Nat, +x: U32, +acc: Nat, zero: Bool) -> Nat:
  match fuel:
    case 0n:
      acc
    case 1n+p:
      match zero:
        case True{}:
          acc
        case False{}:
          +y = U32.sub(x, 1)
          u32_to_nat.step(p, y, Nat.add(acc, 1n), U32.is_eq(y, 0))

def u32_to_nat(+x: U32) -> Nat:
  u32_to_nat.step(65536n, x, 0n, U32.is_eq(x, 0))

# One live_go / reader_go tick per --frames unit. frames=0 is 0n; the live
# path uses @unsafe idle loops instead of a fake terminator.
def live_fuel(+frames: U32) -> Nat:
  u32_to_nat(frames)

def ticks_of(+frames: U32) -> Nat:
  live_fuel(frames)

def body_h_on(+rows: U32, ge: Bool) -> Nat:
  match ge:
    case True{}:
      u32_to_nat(U32.sub(rows, 4))
    case False{}:
      4n

def body_h(+rows: U32) -> Nat:
  body_h_on(rows, U32.is_ge(rows, 8))
