# SPDX-License-Identifier: Apache-2.0
# Strict UTC server-time input. Calendar conversion belongs to libc, not the
# IRC parser; this module only validates and retains the complete event date.
# valid is the sole calendar gate. clock_ffi converts a Valid date and does
# not repeat these bounds.
import Base
import ./clock_fmt.bend as Fmt
import ./endpoint.bend as Ep
import ./irc.bend as Irc

type Utc is Data:
  Utc{year: U32, month: U32, day: U32, hour: U32, minute: U32, second: U32}

type Stamp is Data:
  Missing{}
  Invalid{}
  Valid{utc: Utc}

def leap(+year: U32) -> Bool:
  U32.is_zero(U32.mod(year, 4))
    && (Bool.not(U32.is_zero(U32.mod(year, 100))) || U32.is_zero(U32.mod(year, 400)))

def month_days(+year: U32, month: U32) -> U32:
  match month:
    case 2: Bool.pick(U32, leap(year), 29, 28)
    case 4: 30
    case 6: 30
    case 9: 30
    case 11: 30
    case _: 31

def valid(+utc: Utc) -> Bool:
  match utc:
    case Utc{+year, +month, +day, +hour, +minute, +second}:
      U32.is_ge(year, 1) && U32.is_le(year, 9999)
        && U32.is_ge(month, 1) && U32.is_le(month, 12)
        && U32.is_ge(day, 1) && U32.is_le(day, month_days(year, month))
        && U32.is_lt(hour, 24) && U32.is_lt(minute, 60) && U32.is_le(second, 60)
        && (U32.is_lt(second, 60) || (U32.is_eq(hour, 23) && U32.is_eq(minute, 59)
          && U32.is_eq(day, month_days(year, month))))

def number(+s: String, offset: Nat, width: Nat) -> U32:
  Maybe.default(&2, U32, U32.read(String.take(String.drop(s, offset), width)), 0)

def digits(+s: String, offset: Nat, width: Nat) -> Bool:
  Ep.decimal(String.take(String.drop(s, offset), width))

def fraction(tail: String) -> Bool:
  match tail:
    case SCon{Chr{46}, +rest}:
      Nat.is_ge(String.length(rest), 2n) && Nat.is_le(String.length(rest), 10n)
        && String.ends_with(rest, "Z")
        && Ep.decimal(String.take(rest, Nat.sub(String.length(rest), 1n)))
    case _: False{}

def syntax(+s: String) -> Bool:
  Nat.is_ge(String.length(s), 20n) && Nat.is_le(String.length(s), 30n)
    && String.eq(String.take(String.drop(s, 4n), 1n), "-")
    && String.eq(String.take(String.drop(s, 7n), 1n), "-")
    && String.eq(String.take(String.drop(s, 10n), 1n), "T")
    && String.eq(String.take(String.drop(s, 13n), 1n), ":")
    && String.eq(String.take(String.drop(s, 16n), 1n), ":")
    && digits(s, 0n, 4n) && digits(s, 5n, 2n) && digits(s, 8n, 2n)
    && digits(s, 11n, 2n) && digits(s, 14n, 2n) && digits(s, 17n, 2n)
    && (String.eq(String.drop(s, 19n), "Z") || fraction(String.drop(s, 19n)))

def parse.valid(+utc: Utc, ok: Bool) -> Maybe<&2, Utc>:
  match ok:
    case False{}: None{}
    case True{}: Some{utc}

def parse.syntax(+s: String, ok: Bool) -> Maybe<&2, Utc>:
  match ok:
    case False{}: None{}
    case True{}:
      +utc : Utc = Utc{number(s, 0n, 4n), number(s, 5n, 2n), number(s, 8n, 2n), number(s, 11n, 2n), number(s, 14n, 2n), number(s, 17n, 2n)}
      parse.valid(utc, valid(utc))

def parse(+s: String) -> Maybe<&2, Utc>:
  parse.syntax(s, syntax(s))

def show(utc: Utc) -> String:
  match utc:
    case Utc{year, month, day, hour, minute, second}:
      U32.show(year) ++ "-" ++ U32.show(month) ++ "-" ++ U32.show(day)
        ++ " " ++ Fmt.fmt_hms(hour, minute, second)

def tag.parsed(got: Maybe<&2, Utc>) -> Stamp:
  match got:
    case None{}: Invalid{}
    case Some{utc}: Valid{utc}

def tag.found(previous: Stamp, text: String) -> Stamp:
  match previous:
    case Missing{}: tag.parsed(parse(text))
    case _: Invalid{}

def tag.is_time(is_time: Bool, previous: Stamp, text: String) -> Stamp:
  match is_time:
    case False{}: previous
    case True{}: tag.found(previous, String.drop(text, 5n))

def tag(previous: Stamp, +text: String) -> Stamp:
  tag.is_time(String.starts_with(text, "time="), previous, text)

def tag.step(previous: Stamp, text: String) -> Stamp:
  tag(previous, text)

def line_stamp.words(words: List<&2, String>) -> Stamp:
  match words:
    case Con{SCon{Chr{64}, tags}, _}:
      List.foldl(~&2, ~String, ~Stamp, ~tag.step, String.split(tags, Chr{59}), Missing{})
    case _: Missing{}

def line_stamp(line: String) -> Stamp:
  line_stamp.words(String.split(Irc.drop_spaces(line), Chr{32}))
