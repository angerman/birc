# SPDX-License-Identifier: Apache-2.0
# Shared names-only launch admission and standalone JOIN envelope policy.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./auth.bend as Auth

def MAX_CHANNELS() -> Nat:
  Nat.sub(Cl.MAX_BUFFERS(), 2n)

def line(+name: String, +key: String) -> String:
  "JOIN " ++ name ++ Bool.pick(String, String.is_empty(key), "",
    " " ++ Bool.pick(String, String.starts_with(key, ":"), ":", "") ++ key)

def valid(+name: String, +key: String) -> Bool:
  Irc.starts_channel(name) && Nat.is_gt(String.length(name), 1n)
    && Auth.word_clean(name) && Auth.word_clean(key)
    && Bool.not(String.contains(name, ",") || String.contains(key, ","))
    && String.eq(name, Cl.target_name(name)) && Irc.line_ok(line(name, key))

def launch_names.allowed(allowed: Bool, next: Unit -> Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match allowed:
    case False{}: None{}
    case True{}: next(Unit{})

def launch_names.go(parts: List<&2, String>, +count: Nat, reversed: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match parts:
    case Nil{}: Some{List.reverse(&2, String, reversed)}
    case Con{+name, rest}:
      launch_names.allowed(Nat.is_lt(count, MAX_CHANNELS()) && valid(name, ""),
        _ => launch_names.go(rest, 1n+count, name <> reversed))

def launch_names.empty(empty: Bool, text: String) -> Maybe<&2, List<&2, String>>:
  match empty:
    case True{}: Some{Nil{}}
    case False{}: launch_names.go(String.split(text, Chr{44}), 0n, Nil{})

# Fail the whole list on any invalid/empty member or a fifteenth entry.
# Launch metadata never supplies joining keys.
def launch_names(+text: String) -> Maybe<&2, List<&2, String>>:
  launch_names.empty(String.is_empty(text), text)
