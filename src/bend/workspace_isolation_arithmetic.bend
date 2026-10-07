# SPDX-License-Identifier: Apache-2.0
# Proof-only Nat lemmas used by Workspace isolation.
import Base

law prefix_lt:
  for prefix: Nat
  for -a: Nat
  for -b: Nat
  {Nat.is_lt(Nat.add(prefix, a), Nat.add(prefix, b)) == Nat.is_lt(a, b) : Bool}

def prefix_lt(prefix, a, b):
  match prefix:
    case 0n:
      {==}
    case 1n+p:
      prefix_lt(p, a, b)

def add_zero(prefix: Nat) -> {Nat.add(prefix, 0n) == prefix : Nat}:
  match prefix:
    case 0n:
      {==}
    case 1n+p:
      %add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

def below_positive(+prefix: Nat, -tail: Nat) -> {Nat.is_lt(prefix, Nat.add(prefix, 1n+tail)) == True{} : Bool}:
  %add_zero(prefix) : {Nat.is_lt(_, Nat.add(prefix, 1n+tail)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_lt(Nat.add(prefix, 0n), Nat.add(prefix, 1n+tail)), Nat.is_lt(0n, 1n+tail), prefix_lt(prefix, 0n, 1n+tail)) : {_ == True{} : Bool}
  {==}

def below_overflow(+prefix: Nat, -tail: Nat) -> {Bool.not(Nat.is_lt(prefix, Nat.add(prefix, 1n+tail))) == False{} : Bool}:
  %Equal.sym(Bool, Nat.is_lt(prefix, Nat.add(prefix, 1n+tail)), True{}, below_positive(prefix, tail)) : {Bool.not(_) == False{} : Bool}
  {==}

# Accepted INPUT: strict upper bound admits the sequence below it.
law small_below:
  {Bool.not(Nat.is_lt(2n, 4n)) == False{} : Bool}

def small_below():
  below_overflow(2n, 1n)

# Rejected INPUT, with a correct proof goal (not a deliberately invalid proof).
law small_boundary:
  {Bool.not(Nat.is_lt(4n, 4n)) == True{} : Bool}

def small_boundary():
  {==}
