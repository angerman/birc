# One lexical rule for displayed chat links and /links /open collection.
import Base

def alnum(h: Char) -> Bool:
  match h:
    case Chr{+n}:
      (U32.is_ge(n, 48) && U32.is_le(n, 57))
        || (U32.is_ge(n, 65) && U32.is_le(n, 90))
        || (U32.is_ge(n, 97) && U32.is_le(n, 122))

# The argument is a reversed plain-text accumulator, as used by View.
def bound(acc: String) -> Bool:
  match acc:
    case SNil{}: True{}
    case SCon{h, _}: Bool.not(alnum(h))

def is_url_prefix(+s: String) -> Bool:
  String.starts_with(s, "http://") || String.starts_with(s, "https://")

def trailing(+c: U32) -> Bool:
  U32.is_eq(c, 41) || U32.is_eq(c, 46) || U32.is_eq(c, 44) || U32.is_eq(c, 34)
    || U32.is_eq(c, 93) || U32.is_eq(c, 59)

def trim_keep(drop: Bool, +h: Char, +t: String, rest: String) -> String:
  match drop:
    case True{}: rest
    case False{}: String.reverse(SCon{h, t})

def trim_rev(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+h, +t}: trim_keep(trailing(Char.to_u32(h)), h, t, trim_rev(t))

def trim(s: String) -> String:
  trim_rev(String.reverse(s))

def take_char(stop: Bool, +h: Char, +t: String, more: String & String) -> String & String:
  match stop:
    case True{}: ("", SCon{h, t})
    case False{}:
      match more:
        case (head, tail): (SCon{h, head}, tail)

def take_raw(s: String) -> String & String:
  match s:
    case SNil{}: ("", "")
    case SCon{+h, +t}:
      take_char(U32.is_le(Char.to_u32(h), 32), h, t, take_raw(t))

def take_trim(pair: String & String) -> String & String:
  match pair:
    case (+raw, +tail):
      +url = trim(raw)
      (url, String.drop(raw, String.length(url)) ++ tail)

def take(s: String) -> String & String:
  take_trim(take_raw(s))

type Step is Data:
  Step{rest: String, mode: U32, previous: String, url: Maybe<&2, String>}

def after_url(pair: String & String) -> Step:
  match pair:
    case (+url, rest): Step{rest, 0, "", Some{url}}

def mark(+c: U32) -> Bool:
  U32.is_eq(c, 42) || U32.is_eq(c, 95) || U32.is_eq(c, 96)

def plain_mark(marked: Bool, +h: Char, t: String) -> Step:
  match marked:
    case True{}: Step{t, Char.to_u32(h), "", None{}}
    case False{}: Step{t, 0, SCon{h, ""}, None{}}

def outside(link: Bool, +s: String, +h: Char, +t: String) -> Step:
  match link:
    case True{}: after_url(take(s))
    case False{}: plain_mark(mark(Char.to_u32(h)), h, t)

def next(out: Bool, +s: String, +h: Char, +t: String, +mode: U32, previous: String) -> Step:
  match out:
    case True{}: outside(is_url_prefix(s) && bound(previous), s, h, t)
    case False{}:
      Step{t, Bool.pick(U32, U32.is_eq(Char.to_u32(h), mode), 0, mode), "", None{}}

def extract_step(step: Step, k: String -> U32 -> String -> List<&2, String>) -> List<&2, String>:
  match step:
    case Step{rest, mode, previous, url}:
      match url:
        case None{}: k(rest, mode, previous)
        case Some{h}: h <> k(rest, mode, previous)

def extract_go(fuel: Nat, s: String, +mode: U32, previous: String) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match s:
        case SNil{}: Nil{}
        case SCon{+h, +t}:
          extract_step(next(U32.is_zero(mode), SCon{h, t}, h, t, mode, previous), rest => m => prev => extract_go(p, rest, m, prev))

def extract(+s: String) -> List<&2, String>:
  extract_go(Nat.add(1n, String.length(s)), s, 0, "")
