# Wall-clock stamp. Pure fmt; IO is local seconds-of-day (U32).
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

def fmt_sod(+n: U32) -> String:
  +h = U32.div(n, 3600)
  +rem = U32.mod(n, 3600)
  fmt_hms(h, U32.div(rem, 60), U32.mod(rem, 60))

def fmt_hms_ok() -> Bool:
  String.eq(fmt_hms(12, 5, 9), "12:05:09")
    && String.eq(fmt_hms(0, 0, 0), "00:00:00")
    && String.eq(fmt_sod(43509), "12:05:09")
    && String.eq(fmt_sod(0), "00:00:00")

law local_secs:
  IO(U32)

def local_secs():
  import "../ffi/clock_ffi.c"

def hhmmss() -> IO(String):
  do IO<String>:
    n : U32 <- local_secs()
    return fmt_sod(n)
