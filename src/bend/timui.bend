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
# Flags are U32 0/1 so C can pack them as unboxed words.
type UiKeys is Data:
  UiKeys{
    enter: U32,
    typed: String,
    rows: U32,
    cols: U32,
    click: U32,
    key: U32,
    mods: U32,
    codepoint: U32,
    wheel: U32,
    more: U32,
    url: String,
    clipboard: String
  }

def flag_on(+n: U32) -> Bool:
  U32.is_eq(n, 1)

# Fail closed like Window.open / TCP.connect. Callers bind with IO.try.
law Timui.open:
  IO(Result<&1, &1, U32 & String, Ui>)

def Timui.open():
  import "../ffi/timui_ffi.c"

# One begin/draw/end. C walks List<DrawOp> (no packed wire). seed != 0
# reseeds the composer from input, including "". Key policy is Bend's
# (Sess.key_pol). The UI does not poll. Watchers park; this frame does not wait.
law Timui.frame:
  Ui -> List<&2, V.DrawOp> -> String -> U32 -> IO(Ui & UiKeys)

def Timui.frame(ui, ops, input, seed):
  import "../ffi/timui_ffi.c"

# Read-only, nonblocking probe for a short frame whose output is writable again.
# The maintenance tick owns retry scheduling; pending input stays separate.
law Timui.redraw_ready:
  Ui -> IO(Ui & U32)

def Timui.redraw_ready(ui):
  import "../ffi/timui_ffi.c"

law Timui.close:
  Ui -> IO(Unit)

def Timui.close(ui):
  import "../ffi/timui_ffi.c"

# 1 if stdin is a tty. The headless --frames smoke is not.
law Timui.isatty:
  IO(U32)

def Timui.isatty():
  import "../ffi/timui_ffi.c"

# The Ui read fd. TimUI does not close it. Tty.close is a no-op so a
# watcher shutdown cannot close stdin. Do not F_SETFL this fd.
law Tty: Type

def Tty():
  Window

law Timui.tty:
  Ui -> IO(Ui & Result<&1, &1, U32 & String, Tty>)

def Timui.tty(ui):
  import "../ffi/timui_ffi.c"

law Tty.ready:
  Tty -> IO(Tty)

def Tty.ready(tty):
  import "../ffi/timui_ffi.c"

law Tty.close:
  Tty -> IO(Unit)

def Tty.close(tty):
  import "../ffi/timui_ffi.c"

law Winch: Type

def Winch():
  Window

law Winch.open:
  IO(Result<&1, &1, U32 & String, Winch>)

def Winch.open():
  import "../ffi/timui_ffi.c"

law Winch.ready:
  Winch -> IO(Winch)

def Winch.ready(w):
  import "../ffi/timui_ffi.c"

law Winch.close:
  Winch -> IO(Unit)

def Winch.close(w):
  import "../ffi/timui_ffi.c"

law Sys.open_program:
  IO(String)

def Sys.open_program():
  import "../ffi/timui_ffi.c"

law Sys.clipboard_program:
  IO(String)

def Sys.clipboard_program():
  import "../ffi/timui_ffi.c"

law Sys.exit_done:
  IO(Unit)

def Sys.exit_done():
  import "../ffi/timui_ffi.c"

law Sys.exit_fail:
  String -> IO(Unit)

def Sys.exit_fail(msg):
  import "../ffi/timui_ffi.c"

def Sys.copy_clipboard.on(+program: String, +text: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        result : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(program, Nil{}, text, 4096, 1000)
        return Unit{}

# Process.run waits/reaps on an IO helper thread; the caller spawns this work.
def Sys.copy_clipboard.program(+program: String, +text: String) -> IO(Unit):
  Sys.copy_clipboard.on(program, text, String.is_empty(program))

def Sys.copy_clipboard(+text: String) -> IO(Unit):
  do IO<Unit>:
    program : String <- Sys.clipboard_program()
    Sys.copy_clipboard.program(program, text)
