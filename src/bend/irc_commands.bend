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

def who.default(+active: String, empty: Bool, args: String) -> Maybe<&2, String>:
  match empty:
    case True{}: word_command("WHO", Bool.pick(String, channel(active), active, "*"), 1n, 1n)
    case False{}: word_command("WHO", args, 1n, 2n)

def who(+active: String, +args: String) -> Maybe<&2, String>:
  who.default(active, String.is_empty(args), args)

def list(args: String) -> Maybe<&2, String>:
  word_command("LIST", args, 0n, 2n)

def names.default(+active: String, empty: Bool, args: String) -> Maybe<&2, String>:
  match empty:
    case True{}: word_command("NAMES", Bool.pick(String, channel(active), active, ""), 0n, 1n)
    case False{}: word_command("NAMES", args, 1n, 2n)

def names(+active: String, +args: String) -> Maybe<&2, String>:
  names.default(active, String.is_empty(args), args)

def trailing(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{58}, t}: t
    case SCon{h, t}: SCon{h, t}

def topic.line(+target: String, +text: String, has_text: Bool) -> Maybe<&2, String>:
  checked(channel(target), "TOPIC " ++ target ++ Bool.pick(String, has_text, " :" ++ trailing(text), ""))

def topic.named(named: Bool, +active: String, +first: String, +rest: String, +args: String) -> Maybe<&2, String>:
  match named:
    case True{}: topic.line(first, Irc.drop_spaces(rest), Bool.not(String.is_empty(Irc.drop_spaces(rest))))
    case False{}: topic.line(active, args, Bool.not(String.is_empty(args)))

def topic.words(+active: String, +args: String, pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (+first, +rest): topic.named(channel(first), active, first, rest, args)

def topic(+active: String, +args: String) -> Maybe<&2, String>:
  topic.words(active, args, Irc.take_until_space(args))

def mode.target(+active: String, nick: String) -> String:
  Bool.pick(String, channel(active), active, nick)

def mode.sign(+args: String) -> Bool:
  String.starts_with(args, "+") || String.starts_with(args, "-")

def mode.explicit(pair: String & String) -> Bool:
  match pair:
    case (+first, rest):
      String.starts_with(first, "+#") || (channel(first) && mode.sign(Irc.drop_spaces(rest)))

def mode.flags(+active: String, +nick: String, +args: String, flags: Bool) -> Maybe<&2, String>:
  match flags:
    case True{}: word_command("MODE", mode.target(active, nick) ++ " " ++ args, 1n, 14n)
    case False{}: word_command("MODE", args, 1n, 14n)

def mode.empty(+active: String, +nick: String, +args: String, empty: Bool) -> Maybe<&2, String>:
  match empty:
    case True{}: word_command("MODE", mode.target(active, nick), 1n, 1n)
    case False{}: mode.flags(active, nick, args, mode.sign(args) && Bool.not(mode.explicit(Irc.take_until_space(args))))

def mode(+active: String, +nick: String, +args: String) -> Maybe<&2, String>:
  mode.empty(active, nick, args, String.is_empty(args))

def mode.flag_chars(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, rest}:
      (U32.is_eq(c, 43) || U32.is_eq(c, 45)
        || (U32.is_ge(c, 65) && U32.is_le(c, 90))
        || (U32.is_ge(c, 97) && U32.is_le(c, 122))) && mode.flag_chars(rest)

# Key arguments never enter logs or history. Match the MODE parameter, not
# an arbitrary substring of its target or message text; uppercase K differs.
# Framed atoms normalize before this shared predicate, so styled flags and
# channels redact exactly like their visible text.
def mode_has_key(+m: Irc.Message) -> Bool:
  +chan = Irc.proto_atom(Irc.msg_param(m, 0n))
  +flags = Irc.proto_atom(Irc.msg_param(m, 1n))
  Irc.ieq(Irc.msg_command(m), "MODE") && channel(chan)
    && mode.sign(flags) && mode.flag_chars(flags) && String.contains(flags, "k")
    && Nat.is_ge(List.length(&2, String, Irc.msg_params(m)), 3n)

def mode_has_key.parsed(m: Maybe<&2, Irc.Message>) -> Bool:
  match m:
    case None{}: False{}
    case Some{msg}: mode_has_key(msg)

def mode_has_key.line(wire: String) -> Bool:
  mode_has_key.parsed(Irc.parse(wire))

def kick.line(+target: String, +victim: String, +reason: String) -> Maybe<&2, String>:
  checked(channel(target) && word(victim) && Bool.not(Irc.starts_channel(victim)),
    "KICK " ++ target ++ " " ++ victim ++ Bool.pick(String, String.is_empty(reason), "", " :" ++ trailing(reason)))

def kick.victim(+target: String, pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (victim, reason): kick.line(target, victim, Irc.drop_spaces(reason))

def kick.named(named: Bool, +active: String, +first: String, +rest: String) -> Maybe<&2, String>:
  match named:
    case True{}: kick.victim(first, Irc.take_until_space(Irc.drop_spaces(rest)))
    case False{}: kick.line(active, first, Irc.drop_spaces(rest))

def kick.words(+active: String, pair: String & String) -> Maybe<&2, String>:
  match pair:
    case (+first, rest): kick.named(channel(first), active, first, rest)

def kick(active: String, args: String) -> Maybe<&2, String>:
  kick.words(active, Irc.take_until_space(args))

def invite.words(+active: String, xs: List<&2, String>) -> Maybe<&2, String>:
  match xs:
    case Con{+nick, Nil{}}:
      checked(word(nick) && channel(active) && Bool.not(Irc.starts_channel(nick)), "INVITE " ++ nick ++ " " ++ active)
    case Con{+nick, Con{+target, Nil{}}}:
      checked(word(nick) && channel(target) && Bool.not(Irc.starts_channel(nick)), "INVITE " ++ nick ++ " " ++ target)
    case _: None{}

def invite(active: String, args: String) -> Maybe<&2, String>:
  invite.words(active, words(args))

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
