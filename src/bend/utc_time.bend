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

# History day-carry. A bare HH:MM:SS borrows the previous civil day and rolls
# exactly one day when the clock goes backwards. Weekday names match
# clock.bend (Sunday = 0). That module is IO, so history imports this copy.
# The same rule is in src/ffi/history_ffi.c. A stamp that already contains
# '|' is left unchanged. Skipped whole days stay merged.
type Ymd is Data:
  Ymd{year: U32, month: U32, day: U32}

def pad4.under10(small: Bool, +n: U32) -> String:
  match small:
    case True{}: "000" ++ U32.show(n)
    case False{}: "00" ++ U32.show(n)

def pad4.under100(small: Bool, +n: U32) -> String:
  match small:
    case True{}: pad4.under10(U32.is_lt(n, 10), n)
    case False{}: "0" ++ U32.show(n)

def pad4.under1000(small: Bool, +n: U32) -> String:
  match small:
    case True{}: pad4.under100(U32.is_lt(n, 100), n)
    case False{}: U32.show(n)

def pad4(+n: U32) -> String:
  pad4.under1000(U32.is_lt(n, 1000), n)

def sakamoto.t(month: U32) -> U32:
  match month:
    case 1: 0
    case 2: 3
    case 3: 2
    case 4: 5
    case 5: 0
    case 6: 3
    case 7: 5
    case 8: 1
    case 9: 4
    case 10: 6
    case 11: 2
    case _: 4

def sakamoto.year(early: Bool, +year: U32) -> U32:
  match early:
    case True{}: U32.sub(year, 1)
    case False{}: year

def civil_wday.sum(+year: U32, +t: U32, +day: U32) -> U32:
  +with_leap = U32.add(year, U32.div(year, 4))
  +century = U32.sub(with_leap, U32.div(year, 100))
  +gregorian = U32.add(century, U32.div(year, 400))
  U32.mod(U32.add(U32.add(gregorian, t), day), 7)

def civil_wday(+year: U32, +month: U32, +day: U32) -> U32:
  civil_wday.sum(sakamoto.year(U32.is_lt(month, 3), year), sakamoto.t(month), day)

def civil_weekday.sat(sat: Bool) -> String:
  match sat:
    case True{}: "Saturday"
    case False{}: "Sunday"

def civil_weekday.fri(fri: Bool, +w: U32) -> String:
  match fri:
    case True{}: "Friday"
    case False{}: civil_weekday.sat(U32.is_eq(w, 6))

def civil_weekday.thu(thu: Bool, +w: U32) -> String:
  match thu:
    case True{}: "Thursday"
    case False{}: civil_weekday.fri(U32.is_eq(w, 5), w)

def civil_weekday.wed(wed: Bool, +w: U32) -> String:
  match wed:
    case True{}: "Wednesday"
    case False{}: civil_weekday.thu(U32.is_eq(w, 4), w)

def civil_weekday.tue(tue: Bool, +w: U32) -> String:
  match tue:
    case True{}: "Tuesday"
    case False{}: civil_weekday.wed(U32.is_eq(w, 3), w)

def civil_weekday.mon(mon: Bool, +w: U32) -> String:
  match mon:
    case True{}: "Monday"
    case False{}: civil_weekday.tue(U32.is_eq(w, 2), w)

def civil_weekday.sun(sun: Bool, +w: U32) -> String:
  match sun:
    case True{}: "Sunday"
    case False{}: civil_weekday.mon(U32.is_eq(w, 1), w)

def civil_weekday(+w: U32) -> String:
  civil_weekday.sun(U32.is_eq(w, 0), w)

def next_ymd.month(room: Bool, +year: U32, +month: U32) -> Ymd:
  match room:
    case True{}: Ymd{year, U32.add(month, 1), 1}
    case False{}: Ymd{U32.add(year, 1), 1, 1}

def next_ymd.day(room: Bool, +year: U32, +month: U32, +day: U32) -> Ymd:
  match room:
    case True{}: Ymd{year, month, U32.add(day, 1)}
    case False{}: next_ymd.month(U32.is_lt(month, 12), year, month)

def next_ymd.open(+ymd: Ymd) -> Ymd:
  match ymd:
    case Ymd{+year, +month, +day}:
      next_ymd.day(U32.is_lt(day, month_days(year, month)), year, month, day)

def next_ymd.ended(+ymd: Ymd) -> Bool:
  match ymd:
    case Ymd{+year, +month, +day}:
      U32.is_eq(year, 9999) && U32.is_eq(month, 12) && U32.is_eq(day, 31)

def next_ymd.at(end: Bool, +ymd: Ymd) -> Ymd:
  match end:
    case True{}: ymd
    case False{}: next_ymd.open(ymd)

def next_ymd(+ymd: Ymd) -> Ymd:
  next_ymd.at(next_ymd.ended(ymd), ymd)

def suffix_bar(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{124}, +t}: t
    case SCon{_, +t}: suffix_bar(t)

def hms_digits(+s: String) -> Bool:
  Nat.is_eq(String.length(s), 8n)
    && String.eq(String.take(String.drop(s, 2n), 1n), ":")
    && String.eq(String.take(String.drop(s, 5n), 1n), ":")
    && digits(s, 0n, 2n) && digits(s, 3n, 2n) && digits(s, 6n, 2n)

def hms_bounds(+hour: U32, +minute: U32, +second: U32) -> Bool:
  U32.is_lt(hour, 24) && U32.is_lt(minute, 60) && U32.is_le(second, 60)

def hms_ok.digits(ok: Bool, +s: String) -> Bool:
  match ok:
    case False{}: False{}
    case True{}: hms_bounds(number(s, 0n, 2n), number(s, 3n, 2n), number(s, 6n, 2n))

def hms_ok(+s: String) -> Bool:
  hms_ok.digits(hms_digits(s), s)

def hms_to_sod(+hour: U32, +minute: U32, +second: U32) -> U32:
  U32.add(U32.add(U32.mul(hour, 3600), U32.mul(minute, 60)), second)

def hms_sod.ok(ok: Bool, +s: String) -> Maybe<&2, U32>:
  match ok:
    case False{}: None{}
    case True{}: Some{hms_to_sod(number(s, 0n, 2n), number(s, 3n, 2n), number(s, 6n, 2n))}

def hms_sod(+s: String) -> Maybe<&2, U32>:
  hms_sod.ok(hms_ok(s), s)

def ymd_shape(+s: String) -> Bool:
  Nat.is_ge(String.length(s), 10n)
    && String.eq(String.take(String.drop(s, 4n), 1n), "-")
    && String.eq(String.take(String.drop(s, 7n), 1n), "-")
    && digits(s, 0n, 4n) && digits(s, 5n, 2n) && digits(s, 8n, 2n)

def ymd_of(+s: String) -> Ymd:
  Ymd{number(s, 0n, 4n), number(s, 5n, 2n), number(s, 8n, 2n)}

def ymd_in_range(+ymd: Ymd) -> Bool:
  match ymd:
    case Ymd{+year, +month, +day}:
      U32.is_ge(year, 1) && U32.is_le(year, 9999)
        && U32.is_ge(month, 1) && U32.is_le(month, 12)
        && U32.is_ge(day, 1) && U32.is_le(day, month_days(year, month))

def ymd_ok.shape(ok: Bool, +s: String) -> Bool:
  match ok:
    case False{}: False{}
    case True{}: ymd_in_range(ymd_of(s))

def ymd_ok(+s: String) -> Bool:
  ymd_ok.shape(ymd_shape(s), s)

def day_of.ok(ok: Bool, +s: String) -> Maybe<&2, Ymd>:
  match ok:
    case False{}: None{}
    case True{}: Some{ymd_of(s)}

def day_of.has(has: Bool, +s: String) -> Maybe<&2, Ymd>:
  match has:
    case False{}: None{}
    case True{}: day_of.ok(ymd_ok(s), s)

def day_of(+s: String) -> Maybe<&2, Ymd>:
  day_of.has(String.contains(s, "|"), s)

def sod_of(+prev: String) -> Maybe<&2, U32>:
  hms_sod(suffix_bar(prev))

def show_dated(+year: U32, +month: U32, +day: U32, +hms: String) -> String:
  pad4(year) ++ "-" ++ Fmt.pad2(month) ++ "-" ++ Fmt.pad2(day)
    ++ " (" ++ civil_weekday(civil_wday(year, month, day)) ++ ")|" ++ hms

def carry.use(back: Bool, +ymd: Ymd) -> Ymd:
  match back:
    case True{}: next_ymd(ymd)
    case False{}: ymd

def carry.roll(prev: Maybe<&2, U32>, +sod: U32, +ymd: Ymd) -> Ymd:
  match prev:
    case None{}: ymd
    case Some{+old}: carry.use(U32.is_lt(sod, old), ymd)

def carry.wrote(+ymd: Ymd, +hms: String) -> String:
  match ymd:
    case Ymd{+year, +month, +day}: show_dated(year, month, day, hms)

def carry.attach(+ymd: Ymd, prev: Maybe<&2, U32>, +sod: U32, +hms: String) -> String:
  carry.wrote(carry.roll(prev, sod, ymd), hms)

def carry.known(+ymd: Ymd, prev: Maybe<&2, U32>, got: Maybe<&2, U32>, +hms: String) -> String:
  match got:
    case None{}: hms
    case Some{+sod}: carry.attach(ymd, prev, sod, hms)

def carry.from(got: Maybe<&2, Ymd>, +prev: String, +hms: String) -> String:
  match got:
    case None{}: hms
    case Some{+ymd}: carry.known(ymd, sod_of(prev), hms_sod(hms), hms)

def carry.plain(+ts: String) -> Bool:
  String.contains(ts, "|") || String.is_empty(ts) || Bool.not(hms_ok(ts))

def carry.keep(keep: Bool, +prev: String, +ts: String) -> String:
  match keep:
    case True{}: ts
    case False{}: carry.from(day_of(prev), prev, ts)

def carry(+prev: String, +ts: String) -> String:
  carry.keep(carry.plain(ts), prev, ts)
