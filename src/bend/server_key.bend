# SPDX-License-Identifier: Apache-2.0
# Canonical multiserver identity. Leaf module: no project imports, so pure
# policies (drafts, history, preferences) and Session above can all share
# one ServerId type without an import cycle. Routing wrappers that need
# Session live in server_id.bend; Workspace adapters own integration.
import Base

# At most four simultaneous servers bound actor/channel fan-out. A next id at
# the bound is invalid; callers check valid, never wrap around.
def MAX_SERVERS() -> Nat:
  4n

type ServerId is Data:
  ServerId{id: Nat}

def first() -> ServerId:
  ServerId{0n}

def valid(+id: ServerId) -> Bool:
  match id:
    case ServerId{+n}: Nat.is_lt(n, MAX_SERVERS())

def slot(+id: ServerId) -> U32:
  match id:
    case ServerId{+n}: U32.from_nat(n)

# Identity comparison never narrows: Nat equality, so out-of-range ids
# cannot collide with valid slots through U32 wrapping.
def eq(+a: ServerId, +b: ServerId) -> Bool:
  match a:
    case ServerId{+x}:
      match b:
        case ServerId{+y}: Nat.is_eq(x, y)

def next(+id: ServerId) -> ServerId:
  match id:
    case ServerId{+n}: ServerId{Nat.add(n, 1n)}
