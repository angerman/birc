# Wall-clock stamp. Pure fmt in clock_fmt; IO is local seconds-of-day (U32).
import Base
import ./clock_fmt.bend as Fmt
import ./utc_time.bend as Utc

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

# Default-off numeric PONG-path trace. Stages: 1 reader post, 2 UI chunk,
# 3 UI enqueue, 4 writer receive, 5 line sent, 6 reader reply. The reader
# reply stage opens its own branch, so a late QUIT can never join the PONG
# chain; PONG stages 6/1/2/4/5 share the read's carried request ID so every
# hop matches by numeric identity, never by order; Cont 4/5 carry the low
# batch txn so FIFO sends match their receive by ID. Txn 0 is unidentified
# (non-PING chunks, stage 3, bare sends). Counts stay numeric; only stage 5
# carries the send result. Silent unless BIRC_NET_TRACE is set.
law net_trace:
  U32 -> U32 -> U32 -> IO(Unit)

def net_trace(stage, txn, count):
  import "../ffi/clock_ffi.c"

def hhmmss() -> IO(String):
  do IO<String>:
    n : U32 <- local_secs()
    return Fmt.fmt_sod(n)

# Local calendar day for channel dividers. ymd is year*10000+month*100+day.
# wday is libc tm_wday: 0 = Sunday.
law local_civil:
  IO(U32 & U32)

def local_civil():
  import "../ffi/clock_ffi.c"

# One localtime snapshot: ymd, wday, seconds-of-day. stamp() must use this so
# midnight cannot tear day and HMS across two FFI reads.
law local_now:
  IO(U32 & U32 & U32)

def local_now():
  import "../ffi/clock_ffi.c"

def weekday.sat(sat: Bool) -> String:
  match sat:
    case True{}: "Saturday"
    case False{}: "Sunday"

def weekday.fri(fri: Bool, +w: U32) -> String:
  match fri:
    case True{}: "Friday"
    case False{}: weekday.sat(U32.is_eq(w, 6))

def weekday.thu(thu: Bool, +w: U32) -> String:
  match thu:
    case True{}: "Thursday"
    case False{}: weekday.fri(U32.is_eq(w, 5), w)

def weekday.wed(wed: Bool, +w: U32) -> String:
  match wed:
    case True{}: "Wednesday"
    case False{}: weekday.thu(U32.is_eq(w, 4), w)

def weekday.tue(tue: Bool, +w: U32) -> String:
  match tue:
    case True{}: "Tuesday"
    case False{}: weekday.wed(U32.is_eq(w, 3), w)

def weekday.mon(mon: Bool, +w: U32) -> String:
  match mon:
    case True{}: "Monday"
    case False{}: weekday.tue(U32.is_eq(w, 2), w)

def weekday.sun(sun: Bool, +w: U32) -> String:
  match sun:
    case True{}: "Sunday"
    case False{}: weekday.mon(U32.is_eq(w, 1), w)

def weekday(+w: U32) -> String:
  weekday.sun(U32.is_eq(w, 0), w)

def day_label.parts(+ymd: U32, +w: U32) -> String:
  +year = U32.div(ymd, 10000)
  +md = U32.mod(ymd, 10000)
  U32.show(year) ++ "-" ++ Fmt.pad2(U32.div(md, 100)) ++ "-" ++ Fmt.pad2(U32.mod(md, 100)) ++ " (" ++ weekday(w) ++ ")"

def day_label(parts: U32 & U32) -> String:
  match parts:
    case (+ymd, +w): day_label.parts(ymd, w)

# Join one civil+sod snapshot. ymd 0 means localtime failed — empty stamp.
def stamp_join.civil(zero: Bool, +ymd: U32, +w: U32, +sod: U32) -> String:
  match zero:
    case True{}: ""
    case False{}: day_label.parts(ymd, w) ++ "|" ++ Fmt.fmt_sod(sod)

def stamp_join(+ymd: U32, +w: U32, +sod: U32) -> String:
  stamp_join.civil(U32.is_zero(ymd), ymd, w, sod)

def stamp_join.parts(parts: U32 & U32 & U32) -> String:
  match parts:
    case (+ymd, w, s): stamp_join(ymd, w, s)

# Live clock: day label, '|', HH:MM:SS. Paint shows the time half; '|' survives
# Irc.sanitize_in and history's single-line records.
def stamp() -> IO(String):
  do IO<String>:
    parts : U32 & U32 & U32 <- local_now()
    return stamp_join.parts(parts)

law utc_local_parts:
  U32 -> U32 -> U32 -> U32 -> U32 -> U32 -> IO(U32 & U32 & U32)

def utc_local_parts(y, m, d, h, n, s):
  import "../ffi/clock_ffi.c"

def local_stamp.parts(parts: U32 & U32 & U32) -> Maybe<&2, String>:
  match parts:
    case (+h, m, s):
      Some{Bool.pick(String, U32.is_lt(h, 24), Fmt.fmt_hms(h, m, s), "")}

def local_stamp(utc: Utc.Utc) -> IO(Maybe<&2, String>):
  match utc:
    case Utc.Utc{year, month, day, hour, minute, second}:
      do IO<Maybe<&2, String>>:
        parts : U32 & U32 & U32 <- utc_local_parts(year, month, day, hour, minute, second)
        return local_stamp.parts(parts)

def line_stamp.parsed(tag: Utc.Stamp) -> IO(Maybe<&2, String>):
  match tag:
    case Utc.Missing{}: IO.pure(Maybe<&2, String>, None{})
    case Utc.Invalid{}: IO.pure(Maybe<&2, String>, Some{""})
    case Utc.Valid{utc}: local_stamp(utc)

def line_stamp(line: String) -> IO(Maybe<&2, String>):
  line_stamp.parsed(Utc.line_stamp(line))

def line_stamps.go(fuel: Nat, lines: List<&2, String>) -> IO(List<&2, Maybe<&2, String>>):
  match fuel:
    case 0n: IO.pure(List<&2, Maybe<&2, String>>, Nil{})
    case 1n+p:
      match lines:
        case Nil{}: IO.pure(List<&2, Maybe<&2, String>>, Nil{})
        case Con{line, rest}:
          do IO<List<&2, Maybe<&2, String>>>:
            stamp : Maybe<&2, String> <- line_stamp(line)
            stamps : List<&2, Maybe<&2, String>> <- line_stamps.go(p, rest)
            return stamp <> stamps

def line_stamps(+lines: List<&2, String>) -> IO(List<&2, Maybe<&2, String>>):
  line_stamps.go(List.length(&2, String, lines), lines)
