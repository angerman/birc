# Coarse TimUI paint: one ViewModel → one Timui.frame.
import Base
import ./view.bend as V
import ./timui.bend as T

def paint(ui: T.Ui, +vm: V.ViewModel) -> IO(T.Ui):
  match vm:
    case V.ViewModel{+h, +tabs, +b, +n, +s, +inp}:
      T.Timui.frame(ui, h, tabs, b, n, s, inp)
