# Bend TimUI FFI — thin open / frame / close; Bend owns the iteration.
# Timui.frame is one begin/draw/end and returns Ui beside UiKeys
# (Window.frame shape: handle & Data). C does not latch keys for a
# second IO.
import Base

# Opaque TimUI handle (same runtime shape as Base Window / Socket handles).
law Ui: Type

def Ui():
  Window

# Named Data so C packs CID_UIKEYS (not a `Keys` ctor, which collides
# with a `Timui.keys` law). Copyable; the Ui handle stays linear.
type UiKeys is Data:
  UiKeys{
    quit: Bool,
    enter: Bool,
    bs: Bool,
    typed: String,
    rows: U32,
    tab: U32,
    click: U32,
    up: U32,
    dn: U32,
    hist: U32
  }

def ROWS0() -> U32:
  24

def keys0() -> UiKeys:
  UiKeys{False{}, False{}, False{}, "", ROWS0(), 0, 0, 0, 0, 0}

def keys_quit(k: UiKeys) -> Bool:
  match k:
    case UiKeys{quit, _, _, _, _, _, _, _, _, _}:
      quit

def keys_rows(k: UiKeys) -> U32:
  match k:
    case UiKeys{_, _, _, _, rows, _, _, _, _, _}:
      rows

# Fail closed like Window.open / TCP.connect. Callers bind with IO.try.
law Timui.open:
  IO(Result<&1, &1, U32 & String, Ui>)

def Timui.open():
  import "../ffi/timui_ffi.c"

# One begin/draw/end. Returns the Ui beside this frame's keys (no Result:
# quit is UiKeys.quit, same as Window Close in the event list).
law Timui.frame:
  Ui -> String -> String -> String -> String -> String -> String -> IO(Ui & UiKeys)

def Timui.frame(ui, header, tabs, body, nicks, status, input):
  import "../ffi/timui_ffi.c"

law Timui.close:
  Ui -> IO(Unit)

def Timui.close(ui):
  import "../ffi/timui_ffi.c"
