# SPDX-License-Identifier: Apache-2.0
# Pure durable preferences. No credentials, log state, or channel keys belong here.
import Base
import ./buffer.bend as Cl
import ./irc.bend as Irc
import ./theme.bend as Theme

type Preferences is Data:
  Preferences{joins: Bool, ts: Bool, motd: Bool, history: Bool, hist_cap: U32, autoreconn: Bool, bell: Bool, images: Bool, mutes: List<&2, String>, channels: List<&2, String>, known_channels: Bool, theme: Theme.Id}

def MAX_WIRE() -> U32:
  40960

def images(prefs: Preferences) -> Bool:
  match prefs:
    case Preferences{_, _, _, _, _, _, _, images, _, _, _, _}: images

def channels(prefs: Preferences) -> List<&2, String>:
  match prefs:
    case Preferences{_, _, _, _, _, _, _, _, _, channels, _, _}: channels

def known_channels(prefs: Preferences) -> Bool:
  match prefs:
    case Preferences{_, _, _, _, _, _, _, _, _, _, known, _}: known

def theme(prefs: Preferences) -> Theme.Id:
  match prefs:
    case Preferences{_, _, _, _, _, _, _, _, _, _, _, +th}: th

def capture_themed(+cl: Cl.Client, images: Bool, channels: List<&2, String>, +th: Theme.Id) -> Preferences:
  +stg = Cl.get_settings(cl)
  Preferences{Cl.settings_joins(stg), Cl.settings_ts(stg), Cl.settings_motd(stg), Cl.settings_history(stg), Cl.settings_hist_cap(stg), Cl.settings_autoreconn(stg), Cl.settings_bell(stg), images, Cl.settings_mutes(stg), channels, True{}, th}

def capture(+cl: Cl.Client, images: Bool, channels: List<&2, String>) -> Preferences:
  capture_themed(cl, images, channels, Theme.Dark{})

# Update only durable fields; authentication, unreads, lag and bell sequence survive.
def apply(+cl: Cl.Client, prefs: Preferences) -> Cl.Client:
  match prefs:
    case Preferences{joins, ts, motd, history, cap, auto, bell, _, mutes, _, _, _}:
      +s0 = Cl.get_settings(cl)
      +s1 = Cl.set_joins(s0, joins)
      +s2 = Cl.set_ts(s1, ts)
      +s3 = Cl.set_motd(s2, motd)
      +s4 = Cl.set_history(s3, history)
      +s5 = Cl.set_hist_cap(s4, cap)
      +s6 = Cl.set_autoreconn(s5, auto)
      Cl.set_settings(cl, Cl.set_mutes(Cl.set_bell(s6, bell), mutes))

def bit(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def records_text(xs: List<&2, String>, +kind: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: kind ++ "\t" ++ h ++ "\n" ++ records_text(t, kind)

def show_theme.record(+th: Theme.Id) -> String:
  match th:
    case Theme.Dark{}: ""
    case Theme.Light{}: "theme\tlight\n"
    case Theme.Mono{}: "theme\tmono\n"

def show(prefs: Preferences) -> String:
  match prefs:
    case Preferences{joins, ts, motd, history, cap, auto, bell, images, mutes, channels, known, theme}:
      "BIRC_PREFS1\nsettings\t" ++ bit(joins) ++ "\t" ++ bit(ts) ++ "\t" ++ bit(motd)
        ++ "\t" ++ bit(history) ++ "\t" ++ U32.show(cap) ++ "\t" ++ bit(auto)
        ++ "\t" ++ bit(bell) ++ "\t" ++ bit(images) ++ "\n"
        ++ show_theme.record(theme)
        ++ records_text(mutes, "mute") ++ records_text(channels, "channel")
        ++ Bool.pick(String, known, "", "scope\t0\n")

def text_chars(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, t}:
      U32.is_ge(c, 33) && Bool.not(U32.is_eq(c, 127)) && text_chars(t)

def text_ok(+s: String, bound: U32) -> Bool:
  Bool.not(String.is_empty(s)) && Nat.is_le(Irc.utf8_len(s), U32.to_nat(bound)) && text_chars(s)

def channel_chars(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, t}:
      Bool.not(U32.is_eq(c, 44)) && channel_chars(t)

def channel_ok(+s: String) -> Bool:
  Nat.is_gt(String.length(s), 1n) && text_ok(s, 505) && Irc.starts_channel(s) && channel_chars(s)

def exact_eq(a: String, b: String) -> Bool:
  String.eq(a, b)

def has(+xs: List<&2, String>, value: String) -> Bool:
  List.contains(~String, ~exact_eq, xs, value)

def list_ok(xs: List<&2, String>, +channel: Bool) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, +t}:
      Bool.pick(Bool, channel, channel_ok(h), text_ok(h, 512))
        && Bool.not(has(t, h)) && list_ok(t, channel)

def valid(prefs: Preferences) -> Bool:
  match prefs:
    case Preferences{_, _, _, _, _, _, _, _, +mutes, +channels, known, _}:
      Nat.is_le(List.length(&2, String, mutes), 64n) && Nat.is_le(List.length(&2, String, channels), 14n)
        && list_ok(mutes, False{}) && list_ok(channels, True{})
        && (known || List.is_empty(&2, String, channels))

def serialize.valid(ok: Bool, prefs: Preferences) -> Maybe<&2, String>:
  match ok:
    case False{}: None{}
    case True{}: Some{show(prefs)}

def serialize(+prefs: Preferences) -> Maybe<&2, String>:
  serialize.valid(valid(prefs), prefs)

def parse_bit(s: String) -> Maybe<&2, Bool>:
  match s:
    case "0": Some{False{}}
    case "1": Some{True{}}
    case _: None{}

def decimal(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, t}:
      U32.is_ge(c, 48) && U32.is_le(c, 57) && decimal(t)

def parse_cap.valid(ok: Bool, s: String) -> Maybe<&2, U32>:
  match ok:
    case True{}: U32.read(s)
    case False{}: None{}

def parse_cap(+s: String) -> Maybe<&2, U32>:
  parse_cap.valid(Bool.not(String.is_empty(s)) && Nat.is_le(String.length(s), 10n) && decimal(s), s)

def parse_settings.fields(fields: List<&2, String>) -> Maybe<&2, Preferences>:
  match fields:
    case "settings" <> j <> t <> m <> h <> cap <> a <> b <> i <> Nil{}:
      do Maybe<&2, Preferences>:
        joins : Bool <- parse_bit(j)
        ts : Bool <- parse_bit(t)
        motd : Bool <- parse_bit(m)
        history : Bool <- parse_bit(h)
        hist_cap : U32 <- parse_cap(cap)
        auto : Bool <- parse_bit(a)
        bell : Bool <- parse_bit(b)
        images : Bool <- parse_bit(i)
        return Preferences{joins, ts, motd, history, hist_cap, auto, bell, images, Nil{}, Nil{}, True{}, Theme.Dark{}}
    case _: None{}

def parse_record.mute(ok: Bool, prefs: Preferences, value: String) -> Maybe<&2, Preferences>:
  match ok:
    case False{}: None{}
    case True{}:
      match prefs:
        case Preferences{j, t, m, h, cap, a, b, i, mutes, channels, known, +th}:
          Some{Preferences{j, t, m, h, cap, a, b, i, List.append(&2, String, mutes, value <> Nil{}), channels, known, th}}

def parse_record.channel(ok: Bool, prefs: Preferences, value: String) -> Maybe<&2, Preferences>:
  match ok:
    case False{}: None{}
    case True{}:
      match prefs:
        case Preferences{j, t, m, h, cap, a, b, i, mutes, channels, known, +th}:
          Some{Preferences{j, t, m, h, cap, a, b, i, mutes, List.append(&2, String, channels, value <> Nil{}), known, th}}

def parse_record.scope(ok: Bool, prefs: Preferences) -> Maybe<&2, Preferences>:
  match ok:
    case False{}: None{}
    case True{}:
      match prefs:
        case Preferences{j, t, m, h, cap, a, b, i, mutes, channels, _, +th}:
          Some{Preferences{j, t, m, h, cap, a, b, i, mutes, channels, False{}, th}}

def parse_record.theme(got: Maybe<&2, Theme.Id>, prefs: Preferences) -> Maybe<&2, Preferences>:
  match got:
    case None{}: None{}
    case Some{+th}:
      match prefs:
        case Preferences{j, t, m, h, cap, a, b, i, mutes, channels, known, _}:
          Some{Preferences{j, t, m, h, cap, a, b, i, mutes, channels, known, th}}

def parse_record.fields(fields: List<&2, String>, +prefs: Preferences) -> Maybe<&2, Preferences>:
  match fields:
    case "mute" <> +value <> Nil{}:
      match prefs:
        case Preferences{j, t, m, h, cap, a, b, i, +mutes, channels, known, +th}:
          parse_record.mute(text_ok(value, 512) && Nat.is_lt(List.length(&2, String, mutes), 64n) && Bool.not(has(mutes, value)), Preferences{j, t, m, h, cap, a, b, i, mutes, channels, known, th}, value)
    case "channel" <> +value <> Nil{}:
      match prefs:
        case Preferences{j, t, m, h, cap, a, b, i, mutes, +channels, +known, +th}:
          parse_record.channel(known && channel_ok(value) && Nat.is_lt(List.length(&2, String, channels), 14n) && Bool.not(has(channels, value)), Preferences{j, t, m, h, cap, a, b, i, mutes, channels, known, th}, value)
    case "theme" <> +value <> Nil{}:
      parse_record.theme(Theme.parse(value), prefs)
    case "scope" <> "0" <> Nil{}:
      parse_record.scope(known_channels(prefs) && List.is_empty(&2, String, channels(prefs)), prefs)
    case _: None{}

def parse_records(lines: List<&2, String>, prefs: Preferences) -> Maybe<&2, Preferences>:
  match lines:
    case "" <> Nil{}: Some{prefs}
    case Con{line, tail}:
      do Maybe<&2, Preferences>:
        next : Preferences <- parse_record.fields(String.split(line, Chr{9}), prefs)
        parse_records(tail, next)
    case Nil{}: None{}

def parse_lines(lines: List<&2, String>) -> Maybe<&2, Preferences>:
  match lines:
    case "BIRC_PREFS1" <> header <> rest:
      do Maybe<&2, Preferences>:
        prefs : Preferences <- parse_settings.fields(String.split(header, Chr{9}))
        parse_records(rest, prefs)
    case _: None{}

def parse.valid(ok: Bool, text: String) -> Maybe<&2, Preferences>:
  match ok:
    case False{}: None{}
    case True{}: parse_lines(String.split(text, Chr{10}))

def parse(+text: String) -> Maybe<&2, Preferences>:
  parse.valid(Nat.is_le(Irc.utf8_len(text), U32.to_nat(MAX_WIRE())), text)
