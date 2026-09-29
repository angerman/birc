# Wall-clock stamp. Pure fmt in clock_fmt; IO is local seconds-of-day (U32).
import Base
import ./clock_fmt.bend as Fmt

def pad2(+n: U32) -> String:
  Fmt.pad2(n)

def fmt_hms(+h: U32, +m: U32, +s: U32) -> String:
  Fmt.fmt_hms(h, m, s)

def fmt_sod(+n: U32) -> String:
  Fmt.fmt_sod(n)

def fmt_hms_ok() -> Bool:
  Fmt.fmt_hms_ok()

law local_secs:
  IO(U32)

def local_secs():
  import "../ffi/clock_ffi.c"

law millis:
  IO(U32)

def millis():
  import "../ffi/clock_ffi.c"

def hhmmss() -> IO(String):
  do IO<String>:
    n : U32 <- local_secs()
    return Fmt.fmt_sod(n)
