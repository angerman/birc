# Bend TimUI FFI — thin open / frame / close; Bend owns the iteration.
import Base

# Opaque TimUI handle (same runtime shape as Base Window / Socket handles).
law Ui: Type

def Ui():
  Window

# Fail closed like Window.open / TCP.connect. Callers bind with IO.try.
law Timui.open:
  IO(Result<&1, &1, U32 & String, Ui>)

def Timui.open():
  import "../ffi/timui_ffi.c"

# One begin/draw/end; returns Ui. Quit latched for Timui.did_quit / Timui.events.
# Strings: header, tabs, body, nicks, status, input (composer on its own row).
law Timui.frame:
  Ui -> String -> String -> String -> String -> String -> String -> IO(Ui)

def Timui.frame(ui, header, tabs, body, nicks, status, input):
  import "../ffi/timui_ffi.c"

law Timui.did_quit:
  IO(Bool)

def Timui.did_quit():
  import "../ffi/timui_ffi.c"

# Latched from the last Timui.frame (timui_root.h, min 4). Default 24.
law Timui.rows:
  IO(U32)

def Timui.rows():
  import "../ffi/timui_ffi.c"

# Latched during the last Timui.frame (text / Enter / Backspace).
law Timui.typed:
  IO(String)

def Timui.typed():
  import "../ffi/timui_ffi.c"

law Timui.enter:
  IO(Bool)

def Timui.enter():
  import "../ffi/timui_ffi.c"

law Timui.backspace:
  IO(Bool)

def Timui.backspace():
  import "../ffi/timui_ffi.c"

# Latched keys from the last Timui.frame, packed in one IO.
# Data constructor `Keys` would mangle to CID_TIMUI_KEYS and collide with
# this law, so the product is a right-nested tuple (same as UDP.recv_from).
# quit, enter, bs, typed, rows, tab (0 none / 1 next / 2 prev)
law Timui.keys:
  IO(Bool & Bool & Bool & String & U32 & U32)

def Timui.keys():
  import "../ffi/timui_ffi.c"

# M5.5 — minimal Quit event list (full Key/UiEvent fold deferred; IO handle bind).
type UiEvent is Data:
  Quit{}

# Built in Bend from the keys product (avoids packing List in C FFI).
def events_of(q: Bool) -> List<&2, UiEvent>:
  match q:
    case True{}:
      Quit{} <> Nil{}
    case False{}:
      Nil{}

def quit_of(k: Bool & Bool & Bool & String & U32 & U32) -> Bool:
  match k:
    case (q, _):
      q

law Timui.events:
  IO(List<&2, UiEvent>)

def Timui.events():
  do IO<List<&2, UiEvent>>:
    k : Bool & Bool & Bool & String & U32 & U32 <- Timui.keys()
    return events_of(quit_of(k))

# Non-empty event list means Quit (only constructor today).
def has_quit(+xs: List<&2, UiEvent>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{_, _}:
      True{}

law Timui.close:
  Ui -> IO(Unit)

def Timui.close(ui):
  import "../ffi/timui_ffi.c"
