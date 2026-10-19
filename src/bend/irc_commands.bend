# SPDX-License-Identifier: Apache-2.0
# Small pure formatters for explicit IRC commands. Reject, never truncate.
import Base
import ./irc.bend as Irc

def framing(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}:
      Bool.not(Irc.code_is(h, 0) || Irc.code_is(h, 10) || Irc.code_is(h, 13)) && framing(t)

def word_chars(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}:
      +c = Char.to_u32(h)
      U32.is_gt(c, 32) && Bool.not(U32.is_ge(c, 127) && U32.is_le(c, 159)) && word_chars(t)

def word(+s: String) -> Bool:
  Bool.not(String.is_empty(s) || String.starts_with(s, ":")) && word_chars(s)

def channel(+s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{h, +t}: Irc.is_chan_type(h) && Bool.not(String.is_empty(t)) && word(s)

def not_empty(s: String) -> Bool:
  Bool.not(String.is_empty(s))

def words(+s: String) -> List<&2, String>:
  List.filter(~String, ~not_empty, String.split(s, Chr{32}))

def all_words(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, t}: word(h) && all_words(t)

def checked(ok: Bool, +line: String) -> Maybe<&2, String>:
  match ok:
    case False{}: None{}
    case True{}:
      Bool.pick(Maybe<&2, String>, framing(line) && Irc.line_ok(line), Some{line}, None{})

def with_words(+verb: String, +args: List<&2, String>) -> String:
  verb ++ Bool.pick(String, List.is_empty(&2, String, args), "", " " ++ String.join(args, " "))

def word_command(+verb: String, +args: String, lo: Nat, hi: Nat) -> Maybe<&2, String>:
  +xs = words(args)
  +count = List.length(&2, String, xs)
  checked(all_words(xs) && Nat.is_ge(count, lo) && Nat.is_le(count, hi), with_words(verb, xs))

def whois(args: String) -> Maybe<&2, String>:
  word_command("WHOIS", args, 1n, 2n)

def who.default_as(+active: String, active_chan: Bool, empty: Bool, args: String) -> Maybe<&2, String>:
  match empty:
    case True{}: word_command("WHO", Bool.pick(String, active_chan, active, "*"), 1n, 1n)
    case False{}: word_command("WHO", args, 1n, 2n)

def who_as(+active: String, +args: String, active_chan: Bool) -> Maybe<&2, String>:
  who.default_as(active, active_chan, String.is_empty(args), args)

def who(+active: String, +args: String) -> Maybe<&2, String>:
  who_as(active, args, channel(active))

def list(args: String) -> Maybe<&2, String>:
  word_command("LIST", args, 0n, 2n)

def names.default_as(+active: String, active_chan: Bool, empty: Bool, args: String) -> Maybe<&2, String>:
  match empty:
    case True{}: word_command("NAMES", Bool.pick(String, active_chan, active, ""), 0n, 1n)
    case False{}: word_command("NAMES", args, 1n, 2n)

def names_as(+active: String, +args: String, active_chan: Bool) -> Maybe<&2, String>:
  names.default_as(active, active_chan, String.is_empty(args), args)

def names(+active: String, +args: String) -> Maybe<&2, String>:
  names_as(active, args, channel(active))

def trailing(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{58}, t}: t
    case SCon{h, t}: SCon{h, t}

def topic.line_as(+target: String, +text: String, has_text: Bool, target_chan: Bool) -> Maybe<&2, String>:
  checked(target_chan, "TOPIC " ++ target ++ Bool.pick(String, has_text, " :" ++ trailing(text), ""))

def topic.named_as(named: Bool, +active: String, +first: String, +rest: String, +args: String, active_chan: Bool) -> Maybe<&2, String>:
  match named:
    case True{}: topic.line_as(first, Irc.drop_spaces(rest), Bool.not(String.is_empty(Irc.drop_spaces(rest))), True{})
    case False{}: topic.line_as(active, args, Bool.not(String.is_empty(args)), active_chan)

def topic.words_as(+active: String, +args: String, pair: String & String, active_chan: Bool, first_chan: Bool) -> Maybe<&2, String>:
  match pair:
    case (+first, +rest): topic.named_as(first_chan, active, first, rest, args, active_chan)

def topic_as(+active: String, +args: String, active_chan: Bool, first_chan: Bool) -> Maybe<&2, String>:
  topic.words_as(active, args, Irc.take_until_space(args), active_chan, first_chan)

def topic.fixed(+active: String, +args: String, pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (+first, +rest): topic.named_as(channel(first), active, first, rest, args, channel(active))

def topic(+active: String, +args: String) -> Maybe<&2, String>:
  topic.fixed(active, args, Irc.take_until_space(args))

def mode.target_as(+active: String, nick: String, active_chan: Bool) -> String:
  Bool.pick(String, active_chan, active, nick)

def mode.target(+active: String, nick: String) -> String:
  mode.target_as(active, nick, channel(active))

def mode.sign(+args: String) -> Bool:
  String.starts_with(args, "+") || String.starts_with(args, "-")

# The "+#" carve-out is intentional, not gap-B duplication: a bare "+#room"
# names a modeless channel / STATUSMSG audience, never implicit flags,
# while a bare flag-shaped "+else" stays implicit. Pinned by the contrast
# pair "mode plus-prefixed channel query" (explicit "MODE +#other") and
# "mode single unseen plus word stays implicit flags" ("MODE #room +else").
def mode.explicit_as(pair: String & String, first_chan: Bool) -> Bool:
  match pair:
    case (+first, rest):
      String.starts_with(first, "+#") || (first_chan && mode.sign(Irc.drop_spaces(rest)))

def mode.explicit(pair: String & String) -> Bool:
  match pair:
    case (+first, rest):
      mode.explicit_as((first, rest), channel(first))

def mode.flags_as(+active: String, +nick: String, +args: String, active_chan: Bool, flags: Bool) -> Maybe<&2, String>:
  match flags:
    case True{}: word_command("MODE", mode.target_as(active, nick, active_chan) ++ " " ++ args, 1n, 14n)
    case False{}: word_command("MODE", args, 1n, 14n)

def mode.empty_as(+active: String, +nick: String, +args: String, active_chan: Bool, first_chan: Bool, empty: Bool) -> Maybe<&2, String>:
  match empty:
    case True{}: word_command("MODE", mode.target_as(active, nick, active_chan), 1n, 1n)
    case False{}: mode.flags_as(active, nick, args, active_chan, mode.sign(args) && Bool.not(mode.explicit_as(Irc.take_until_space(args), first_chan)))

def mode_as(+active: String, +nick: String, +args: String, active_chan: Bool, first_chan: Bool) -> Maybe<&2, String>:
  mode.empty_as(active, nick, args, active_chan, first_chan, String.is_empty(args))

def mode_first_channel.pair(pair: String & String) -> Bool:
  match pair:
    case (+first, _): channel(first)

def mode_first_channel(+args: String) -> Bool:
  mode_first_channel.pair(Irc.take_until_space(args))

def mode(+active: String, +nick: String, +args: String) -> Maybe<&2, String>:
  mode_as(active, nick, args, channel(active), mode_first_channel(args))

def mode.flag_chars(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, rest}:
      (U32.is_eq(c, 43) || U32.is_eq(c, 45)
        || (U32.is_ge(c, 65) && U32.is_le(c, 90))
        || (U32.is_ge(c, 97) && U32.is_le(c, 122))) && mode.flag_chars(rest)

# Conservative key detector shared by Commands/I2/Submit: a channel MODE tail
# mentioning 'k' with an argument slot is key-bearing when signed (even if
# flag-malformed like "+k!") or a bare short unsigned token like "k". Longer
# unsigned words ("monkey") are not mode attempts. Uppercase K differs.
# A 'k'-mentioning tail the wire itself rejects (styled/control-polluted
# flags like bold-wrapped "+k") is plausibly a key attempt whose secret
# must not become recallable: fail closed via the exact wire predicate
# word_chars, not a second lexer. Plain words are unaffected, so "monkey"
# still rejects and ordinary modes stay recallable.
# Fail closed: ambiguous tails redact. Match the MODE parameter, not an
# arbitrary substring of its target or message text.
#
# The key-target certainty has ONE owner: mode_chan_target. A STATUSMSG
# audience (@#room) is channel-shaped even though channel() rejects its
# leading sigil, so the fixed predicate is starts_channel, not channel.
# Negotiated-only types ($room under CHANTYPES=$) additionally need live
# 005 state; Isupport ORs its negotiated is_channel into
# mode_maybe_key_target via the one shared target owner
# Isupport.sensitive_target. Every key-bearing call site (mode_has_key,
# Submit.input_sensitive, Submit.input_sensitive_iso, Isupport.suspicious)
# routes through this pair.
def mode_maybe_short(+flags: String) -> Bool:
  Nat.is_le(String.length(flags), 2n)

def mode_maybe_signed(+flags: String) -> Bool:
  mode.sign(flags) || mode_maybe_short(flags)

# Formatting strip for sensitivity classification ONLY (I2-dynamic2 F5):
# drop C0 controls (bold/color/etc.) and DEL/C1 so a styled flag word like
# bold-wrapped "+k" is still recognized as flags-shaped when deciding
# whether a signed target (e.g. +#room) carries a key attempt. Never used
# for outbound wire construction, which keeps rejecting such input.
def strip_format.keep(+h: Char, r: String, keep: Bool) -> String:
  match keep:
    case True{}: SCon{h, r}
    case False{}: r

def strip_format.go(+s: String) -> String:
  match s:
    case SNil{}: SNil{}
    case SCon{+h, +t}:
      +c = Char.to_u32(h)
      strip_format.keep(h, strip_format.go(t), U32.is_ge(c, 32) && Bool.not(U32.is_ge(c, 127) && U32.is_le(c, 159)))

def strip_format(+s: String) -> String:
  strip_format.go(s)

def mode_maybe_signed_norm(+flags: String) -> Bool:
  mode_maybe_signed(strip_format(flags))

def mode_chan_target(+target: String) -> Bool:
  # Sensitivity follows the same normalized identity as Client lookup.
  # This does not admit styled atoms into strict outbound wire construction.
  Irc.starts_channel(Irc.proto_atom(target))

def mode_key_tail(+flags: String, has_arg: Bool) -> Bool:
  String.contains(flags, "k") && has_arg && (mode_maybe_signed(flags) || Bool.not(word_chars(flags)))

def mode_maybe_key_target(+target_ok: Bool, +flags: String, has_arg: Bool) -> Bool:
  target_ok && mode_key_tail(flags, has_arg)

def mode_maybe_key(+target: String, +flags: String, has_arg: Bool) -> Bool:
  mode_maybe_key_target(mode_chan_target(target), flags, has_arg)

# Key arguments never enter logs or history.
def mode_has_key(+m: Irc.Message) -> Bool:
  Irc.ieq(Irc.msg_command(m), "MODE")
    && mode_maybe_key(Irc.msg_param(m, 0n), Irc.msg_param(m, 1n), Nat.is_ge(List.length(&2, String, Irc.msg_params(m)), 3n))

def mode_has_key.parsed(m: Maybe<&2, Irc.Message>) -> Bool:
  match m:
    case None{}: False{}
    case Some{msg}: mode_has_key(msg)

def mode_has_key.line(wire: String) -> Bool:
  mode_has_key.parsed(Irc.parse(wire))

def kick.line_as(+target: String, +victim: String, +reason: String, target_chan: Bool) -> Maybe<&2, String>:
  checked(target_chan && word(victim) && Bool.not(Irc.starts_channel(victim)),
    "KICK " ++ target ++ " " ++ victim ++ Bool.pick(String, String.is_empty(reason), "", " :" ++ trailing(reason)))

def kick.victim_as(+target: String, pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (victim, reason): kick.line_as(target, victim, Irc.drop_spaces(reason), True{})

def kick.named_as(named: Bool, +active: String, +first: String, +rest: String, active_chan: Bool) -> Maybe<&2, String>:
  match named:
    case True{}: kick.victim_as(first, Irc.take_until_space(Irc.drop_spaces(rest)))
    case False{}: kick.line_as(active, first, Irc.drop_spaces(rest), active_chan)

def kick.words_as(+active: String, pair: String & String, active_chan: Bool, first_chan: Bool) -> Maybe<&2, String>:
  match pair:
    case (+first, rest): kick.named_as(first_chan, active, first, rest, active_chan)

def kick_as(+active: String, +args: String, active_chan: Bool, first_chan: Bool) -> Maybe<&2, String>:
  kick.words_as(active, Irc.take_until_space(args), active_chan, first_chan)

def kick.fixed(+active: String, pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (+first, rest): kick.named_as(channel(first), active, first, rest, channel(active))

def kick(active: String, args: String) -> Maybe<&2, String>:
  kick.fixed(active, Irc.take_until_space(args))

def invite.words_as(+active: String, xs: List<&2, String>, active_chan: Bool, target_chan: Bool) -> Maybe<&2, String>:
  match xs:
    case Con{+nick, Nil{}}:
      checked(word(nick) && active_chan && Bool.not(Irc.starts_channel(nick)), "INVITE " ++ nick ++ " " ++ active)
    case Con{+nick, Con{+target, Nil{}}}:
      checked(word(nick) && target_chan && Bool.not(Irc.starts_channel(nick)), "INVITE " ++ nick ++ " " ++ target)
    case _: None{}

def invite_target_channel(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{_, Con{+target, Nil{}}}: channel(target)
    case _: False{}

def invite_as(+active: String, +args: String, active_chan: Bool, target_chan: Bool) -> Maybe<&2, String>:
  invite.words_as(active, words(args), active_chan, target_chan)

def invite(+active: String, +args: String) -> Maybe<&2, String>:
  invite_as(active, args, channel(active), invite_target_channel(words(args)))

def away(+args: String) -> Maybe<&2, String>:
  checked(True{}, "AWAY" ++ Bool.pick(String, String.is_empty(args), "", " :" ++ trailing(args)))

def command_chars(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}:
      +c = Char.to_u32(h)
      ((U32.is_ge(c, 65) && U32.is_le(c, 90)) || (U32.is_ge(c, 97) && U32.is_le(c, 122))) && command_chars(t)

def raw.param(trailing: Bool, +token: String, rest: String, +count: Nat, k: String -> Nat -> Bool) -> Bool:
  match trailing:
    case True{}: Nat.is_lt(count, 15n)
    case False{}: word(token) && Nat.is_lt(count, 15n) && k(Irc.drop_spaces(rest), Nat.add(count, 1n))

def raw.param_pair(pair: String & String, count: Nat, k: String -> Nat -> Bool) -> Bool:
  match pair:
    case (+token, rest): raw.param(String.starts_with(token, ":"), token, rest, count, k)

def raw.params(fuel: Nat, s: String, count: Nat) -> Bool:
  match fuel:
    case 0n: False{}
    case 1n+p:
      match s:
        case SNil{}: True{}
        case SCon{h, t}:
          raw.param_pair(Irc.take_until_space(SCon{h, t}), count, rest => n => raw.params(p, rest, n))

def raw.words(+line: String, pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (+verb, +rest):
      checked(Bool.not(String.is_empty(verb)) && command_chars(verb)
        && raw.params(Nat.add(1n, String.length(rest)), Irc.drop_spaces(rest), 0n), line)

def raw(+line: String) -> Maybe<&2, String>:
  raw.words(line, Irc.take_until_space(line))
