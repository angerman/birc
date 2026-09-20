# M0.5 — TimUI foreign-effect smoke (native only).
# Opens TimUI, draws one label, quits after max_frames (or Escape if 0).
import Base

law Timui.hello:
  U32 -> IO(Unit)

def Timui.hello(max_frames):
  import "./timui_hello.c"

def main() -> IO(Unit):
  do IO<Unit>:
    Timui.hello(3)
    IO.print("timui_hello=ok")
