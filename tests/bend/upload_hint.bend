# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/view.bend as V
import ../../src/bend/view_hint.bend as H

def input(vm: V.ViewModel) -> String:
  match vm:
    case V.ViewModel{_, input}: input

def ops(vm: V.ViewModel) -> Nat:
  match vm:
    case V.ViewModel{ops, _}: List.length(&2, V.DrawOp, ops)

def hint_ok(vm: V.ViewModel) -> Bool:
  match vm:
    case V.ViewModel{Con{V.OpText{1, 7, 10, _, 1, text}, Nil{}}, input}:
      String.eq(input, "unsent draft") && String.eq(text, "F8: upload")
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("no hint adds no drawing", Nat.show(ops(H.status(V.ViewModel{Nil{}, "unsent draft"}, 10, 12, ""))), "0")
    Unit <- E.must_eq("no hint preserves draft", input(H.status(V.ViewModel{Nil{}, "unsent draft"}, 10, 12, "")), "unsent draft")
    Unit <- E.must("hint targets the panel row and preserves draft", hint_ok(H.status(V.ViewModel{Nil{}, "unsent draft"}, 10, 12, "F8: upload")))
    Unit <- E.must_eq("dimension padding has a finite cap", Nat.show(String.length(H.spaces(1024n))), "1024")
    IO.print("upload_hint=ok\n")
