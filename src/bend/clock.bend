# Wall-clock stamp. Pure fmt; IO only at Clock.hhmmss (localtime FFI).
import Base

def pad2.on(+n: U32, lt: Bool) -> String:
  match lt:
    case True{}:
      "0" ++ U32.show(n)
    case False{}:
      U32.show(n)

def pad2(+n: U32) -> String:
  pad2.on(n, U32.is_lt(n, 10))

def fmt_hms(+h: U32, +m: U32, +s: U32) -> String:
  pad2(h) ++ ":" ++ pad2(m) ++ ":" ++ pad2(s)

def fmt_hms_ok() -> Bool:
  String.eq(fmt_hms(12, 5, 9), "12:05:09") && String.eq(fmt_hms(0, 0, 0), "00:00:00")

law hhmmss:
  IO(String)

def hhmmss():
  import "../ffi/clock_ffi.c"
