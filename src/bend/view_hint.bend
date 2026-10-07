# SPDX-License-Identifier: Apache-2.0
# A transient status-row hint never replaces input or enters chat history.
import Base
import ./buffer.bend as Cl
import ./theme.bend as Theme
import ./view.bend as V

def spaces(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: SCon{Chr{32}, spaces(p)}

def status.on(empty: Bool, vm: V.ViewModel, rows: U32, +cols: U32, hint: String) -> V.ViewModel:
  match empty:
    case True{}: vm
    case False{}:
      match vm:
        case V.ViewModel{ops, input}:
          # Padding overwrites the old status, including its trailing text.
          # Bound allocation independently of terminal-reported dimensions.
          V.ViewModel{List.append(&2, V.DrawOp, ops,
            [V.OpText{0, V.status_y(rows), cols, V.FG_TEXT(), 1,
              hint ++ spaces(Cl.clamp_nat(U32.to_nat(cols), 1024n))}]), input}

def status(vm: V.ViewModel, rows: U32, cols: U32, +hint: String) -> V.ViewModel:
  status.on(String.is_empty(hint), vm, rows, cols, hint)

def status_themed.on(empty: Bool, vm: V.ViewModel, rows: U32, +cols: U32, hint: String, +th: Theme.Id) -> V.ViewModel:
  match empty:
    case True{}: vm
    case False{}:
      match vm:
        case V.ViewModel{ops, input}:
          V.ViewModel{List.append(&2, V.DrawOp, ops,
            [V.OpText{0, V.status_y(rows), cols, V.FG_TEXT_themed(th), 1,
              hint ++ spaces(Cl.clamp_nat(U32.to_nat(cols), 1024n))}]), input}

def status_themed(vm: V.ViewModel, rows: U32, cols: U32, +hint: String, +th: Theme.Id) -> V.ViewModel:
  status_themed.on(String.is_empty(hint), vm, rows, cols, hint, th)
