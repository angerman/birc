# Terminal columns follow the vendored timui_utf8_width contract. Bend uses
# these widths for layout; C only paints the prepared rows. Keep the ranges
# in step with TimUI (tests/columns_width.c compares every scalar value).
import Base

def between(+c: U32, lo: U32, hi: U32) -> Bool:
  U32.is_ge(c, lo) && U32.is_le(c, hi)

def zero(+c: U32) -> Bool:
  U32.is_lt(c, 32) || U32.is_eq(c, 127) || between(c, 128, 159)
    || between(c, 768, 879) || between(c, 6832, 6911)
    || between(c, 7616, 7679) || between(c, 8400, 8447)
    || between(c, 65056, 65071) || U32.is_eq(c, 8205)
    || between(c, 65024, 65039) || between(c, 917760, 917999)
    || between(c, 127995, 127999)

def wide(+c: U32) -> Bool:
  between(c, 4352, 4447) || between(c, 11904, 42191)
    || between(c, 44032, 55203) || between(c, 63744, 64255)
    || between(c, 65072, 65135) || between(c, 65280, 65376)
    || between(c, 65504, 65510) || between(c, 127744, 129791)

def width_visible(zero: Bool, +c: U32) -> U32:
  match zero:
    case True{}: 0
    case False{}: Bool.pick(U32, wide(c), 2, 1)

def width(+c: U32) -> U32:
  width_visible(zero(c), c)

def text_width(s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{h, t}: U32.add(width(Char.to_u32(h)), text_width(t))

type Cut is Data:
  Cut{head: String, tail: String, width: U32}

def regional(+c: U32) -> Bool:
  between(c, 127462, 127487)

def cluster_char(attached: Bool, +s: String, +h: Char, +t: String, +used: U32, +join: Bool, +ri: Bool, head: String, k: String -> U32 -> Bool -> Bool -> String -> Cut) -> Cut:
  match attached:
    case False{}: Cut{String.reverse(head), s, used}
    case True{}:
      +c = Char.to_u32(h)
      +w = width(c)
      k(t, U32.add(used, w), U32.is_eq(c, 8205) || (join && U32.is_zero(w)), ri && U32.is_zero(w), SCon{h, head})

# This matches the common cluster cases TimUI supports: trailing combining
# marks/modifiers, paired regional indicators, and zero-width-joiner runs.
# Width remains the sum of the codepoint widths that TimUI actually paints.
def cluster_go(fuel: Nat, s: String, +used: U32, +join: Bool, +ri: Bool, head: String) -> Cut:
  match fuel:
    case 0n: Cut{String.reverse(head), s, used}
    case 1n+p:
      match s:
        case SNil{}: Cut{String.reverse(head), "", used}
        case SCon{+h, +t}:
          cluster_char(U32.is_zero(width(Char.to_u32(h))) || join || (ri && regional(Char.to_u32(h))), SCon{h, t}, h, t, used, join, ri, head, rest => w => j => r => acc => cluster_go(p, rest, w, j, r, acc))

def cluster(s: String) -> Cut:
  match s:
    case SNil{}: Cut{"", "", 0}
    case SCon{+h, +t}:
      cluster_go(Nat.add(1n, String.length(t)), t, width(Char.to_u32(h)), U32.is_eq(Char.to_u32(h), 8205), regional(Char.to_u32(h)), SCon{h, ""})

def take_cluster(fits: Bool, +s: String, piece: Cut, +used: U32, head: String, k: String -> U32 -> String -> Cut) -> Cut:
  match fits:
    case False{}: Cut{String.reverse(head), s, used}
    case True{}:
      match piece:
        case Cut{+text, tail, width}: k(tail, U32.add(used, width), String.reverse(text) ++ head)

def take_piece(piece: Cut, +s: String, +cap: U32, +used: U32, head: String, k: String -> U32 -> String -> Cut) -> Cut:
  match piece:
    case Cut{+text, +tail, +width}:
      take_cluster(U32.is_le(U32.add(used, width), cap), s, Cut{text, tail, width}, used, head, k)

# Fit complete common grapheme clusters. The returned width is in columns,
# not code points or UTF-8 bytes.
def take_go(fuel: Nat, s: String, +cap: U32, +used: U32, head: String) -> Cut:
  match fuel:
    case 0n: Cut{String.reverse(head), s, used}
    case 1n+p:
      match s:
        case SNil{}: Cut{String.reverse(head), "", used}
        case SCon{+h, +t}:
          take_piece(cluster(SCon{h, t}), SCon{h, t}, cap, used, head, rest => w => acc => take_go(p, rest, cap, w, acc))

def take(+s: String, cap: U32) -> Cut:
  take_go(Nat.add(1n, String.length(s)), s, cap, 0, "")
