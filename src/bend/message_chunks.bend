# SPDX-License-Identifier: Apache-2.0
# Lossless UTF-8 byte chunks at the same common-cluster boundaries as TimUI.
# An indivisible cluster larger than the envelope rejects the entire message.
import Base
import ./irc.bend as Irc
import ./columns.bend as Columns

def finish(+head: String, +chunks: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  Some{List.reverse(&2, String,
    Bool.pick(List<&2, String>, String.is_empty(head) && Bool.not(List.is_empty(&2, String, chunks)),
      chunks, String.reverse(head) <> chunks))}

def piece.fits(fits: Bool, +cap: Nat, +used: Nat, +source: String, +text: String, tail: String, head: String, chunks: List<&2, String>, k: String -> Nat -> String -> List<&2, String> -> Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match fits:
    case True{}:
      k(tail, Nat.add(used, Irc.utf8_len(text)), String.reverse(text) ++ head, chunks)
    case False{}:
      k(source, 0n, "", String.reverse(head) <> chunks)

def piece.valid(valid: Bool, +cap: Nat, +used: Nat, source: String, +text: String, tail: String, head: String, chunks: List<&2, String>, k: String -> Nat -> String -> List<&2, String> -> Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match valid:
    case False{}: None{}
    case True{}:
      piece.fits(Nat.is_le(Nat.add(used, Irc.utf8_len(text)), cap), cap, used, source, text, tail, head, chunks, k)

def piece(+cap: Nat, used: Nat, source: String, cut: Columns.Cut, head: String, chunks: List<&2, String>, k: String -> Nat -> String -> List<&2, String> -> Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match cut:
    case Columns.Cut{+text, tail, _}:
      piece.valid(Nat.is_le(Irc.utf8_len(text), cap), cap, used, source, text, tail, head, chunks, k)

def split.go(fuel: Nat, s: String, +cap: Nat, used: Nat, head: String, chunks: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      match s:
        case SNil{}: finish(head, chunks)
        case SCon{+h, +t}:
          piece(cap, used, SCon{h, t}, Columns.cluster(SCon{h, t}), head, chunks,
            rest => bytes => acc => done => split.go(p, rest, cap, bytes, acc, done))

def split(+s: String, cap: Nat) -> Maybe<&2, List<&2, String>>:
  split.go(Nat.add(2n, Nat.mul(2n, String.length(s))), s, cap, 0n, "", Nil{})
