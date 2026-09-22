# Bend TimUI FFI — thin open / frame / close; Bend owns the iteration.
# Timui.frame is one begin/draw/end and returns Ui beside UiKeys
# (Window.frame shape: handle & Data). C does not latch keys for a
# second IO.
import Base
import ./view.bend as V

# Opaque TimUI handle (same runtime shape as Base Window / Socket handles).
law Ui: Type

def Ui():
  Window

# Named Data so C packs CID_UIKEYS (not a `Keys` ctor, which collides
# with a `Timui.keys` law). Copyable; the Ui handle stays linear.
# Flags are U32 0/1 so C can pack them as unboxed words (Bool True/False
# is TAG_PAK; a 10-field Data ctor was not matching Enter).
type UiKeys is Data:
  UiKeys{
    quit: U32,
    enter: U32,
    typed: String,
    rows: U32,
    cols: U32,
    tab: U32,
    click: U32,
    up: U32,
    dn: U32,
    hist: U32
  }

def flag_on(+n: U32) -> Bool:
  U32.is_eq(n, 1)

# Fail closed like Window.open / TCP.connect. Callers bind with IO.try.
law Timui.open:
  IO(Result<&1, &1, U32 & String, Ui>)

def Timui.open():
  import "../ffi/timui_ffi.c"

# One begin/draw/end. C walks List<DrawOp> (no packed wire). seed != 0
# reseeds the composer from input, including "". page is Sess.body_h.
# wait_ms is the FFI poll timeout; wake_fd is a socket wake hint (0 = none).
law Timui.frame:
  Ui -> List<&2, V.DrawOp> -> String -> U32 -> U32 -> U32 -> U32 -> IO(Ui & UiKeys)

def Timui.frame(ui, ops, input, seed, page, wait_ms, wake_fd):
  import "../ffi/timui_ffi.c"

law Timui.close:
  Ui -> IO(Unit)

def Timui.close(ui):
  import "../ffi/timui_ffi.c"
