# Private launch pipes. Protocol success is decided by Bend, not UI text.
import Base

law setup:
  IO(U32 & String)

def setup():
  import "../ffi/auth_bridge_ffi.c"

law notify:
  IO(U32)

def notify():
  import "../ffi/auth_bridge_ffi.c"

def observed(changed: Bool) -> IO(U32):
  match changed:
    case False{}: IO.pure(U32, 0)
    case True{}: notify()
