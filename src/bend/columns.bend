# Terminal columns follow TimUI's scalar and common-grapheme contracts. Bend
# lays out whole clusters; C paints those same clusters. Scalar parity is
# exhaustive; tests/ui_review_columns.py checks native cluster boundaries and
# widths, including ZWJ, VS16, regional indicators, and control boundaries.
import Base

def between(+c: U32, lo: U32, hi: U32) -> Bool:
  U32.is_ge(c, lo) && U32.is_le(c, hi)

def extend(+c: U32) -> Bool:
  between(c, 768, 879) || between(c, 6832, 6911)
    || between(c, 7616, 7679) || between(c, 8400, 8447)
    || between(c, 65056, 65071)
    || between(c, 65024, 65039) || between(c, 917760, 917999)
    || between(c, 127995, 127999)

def zero(+c: U32) -> Bool:
  U32.is_lt(c, 32) || U32.is_eq(c, 127) || between(c, 128, 159)
    || extend(c) || U32.is_eq(c, 8205)

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

type Cut is Data:
  Cut{head: String, tail: String, width: U32}

def regional(+c: U32) -> Bool:
  between(c, 127462, 127487)

def emoji_base(+c: U32) -> Bool:
  between(c, 126976, 129791) || between(c, 9728, 10175)
    || between(c, 8960, 9215) || U32.is_eq(c, 169) || U32.is_eq(c, 174)

# timui_grapheme_width: maximum base width, not a scalar sum. Regional
# indicators are two columns; emoji ZWJ/VS16 presentation is two columns.
def cluster_width_go(s: String, +w: U32, +presentation: Bool, +emoji: Bool, +ri: Bool) -> U32:
  match s:
    case SNil{}: Bool.pick(U32, ri || (presentation && emoji), 2, w)
    case SCon{h, t}:
      +c = Char.to_u32(h)
      +ext = extend(c)
      +zwj = U32.is_eq(c, 8205)
      +reg = regional(c)
      +cw = Bool.pick(U32, ext || zwj || reg, 0, width(c))
      cluster_width_go(t, Bool.pick(U32, U32.is_ge(w, cw), w, cw), presentation || zwj || U32.is_eq(c, 65039), emoji || (Bool.not(ext || zwj) && (reg || emoji_base(c))), ri || reg)

def cluster_cut(head: String, tail: String) -> Cut:
  +text = String.reverse(head)
  Cut{text, tail, cluster_width_go(text, 0, False{}, False{}, False{})}

def cluster_join(s: String, head: String, k: String -> String -> Cut) -> Cut:
  match s:
    case SNil{}: cluster_cut(head, "")
    case SCon{h, t}: k(t, SCon{h, head})

def cluster_char(attached: Bool, zwj: Bool, +s: String, +h: Char, +t: String, +ri: Bool, head: String, k: String -> Bool -> String -> Cut) -> Cut:
  match attached:
    case True{}: k(t, ri && Bool.not(regional(Char.to_u32(h))), SCon{h, head})
    case False{}:
      match zwj:
        case True{}: cluster_join(t, SCon{h, head}, rest => acc => k(rest, ri, acc))
        case False{}: cluster_cut(head, s)

# Match timui_grapheme_next exactly within its documented common classes:
# extensions, a second regional indicator, and ZWJ plus its following scalar.
def cluster_go(fuel: Nat, s: String, +ri: Bool, head: String) -> Cut:
  match fuel:
    case 0n: cluster_cut(head, s)
    case 1n+p:
      match s:
        case SNil{}: cluster_cut(head, "")
        case SCon{+h, +t}:
          +c = Char.to_u32(h)
          cluster_char(extend(c) || (ri && regional(c)), U32.is_eq(c, 8205), SCon{h, t}, h, t, ri, head, rest => r => acc => cluster_go(p, rest, r, acc))

def cluster_crlf(s: String, +h: Char) -> Cut:
  match s:
    case SNil{}: Cut{SCon{h, ""}, "", 0}
    case SCon{+next, +rest}:
      Bool.pick(Cut, U32.is_eq(Char.to_u32(next), 10), Cut{SCon{h, SCon{next, ""}}, rest, 0}, Cut{SCon{h, ""}, SCon{next, rest}, 0})

def cluster_start(cr: Bool, lf: Bool, +h: Char, t: String) -> Cut:
  match cr:
    case True{}: cluster_crlf(t, h)
    case False{}:
      match lf:
        case True{}: Cut{SCon{h, ""}, t, 0}
        case False{}:
          +rest = t
          cluster_go(Nat.add(1n, String.length(rest)), rest, regional(Char.to_u32(h)), SCon{h, ""})

def cluster(s: String) -> Cut:
  match s:
    case SNil{}: Cut{"", "", 0}
    case SCon{+h, +t}:
      cluster_start(U32.is_eq(Char.to_u32(h), 13), U32.is_eq(Char.to_u32(h), 10), h, t)

def text_width_piece(piece: Cut, k: String -> U32) -> U32:
  match piece:
    case Cut{_, tail, w}: U32.add(w, k(tail))

def text_width_go(fuel: Nat, s: String) -> U32:
  match fuel:
    case 0n: 0
    case 1n+p:
      match s:
        case SNil{}: 0
        case SCon{h, t}: text_width_piece(cluster(SCon{h, t}), rest => text_width_go(p, rest))

def text_width(+s: String) -> U32:
  text_width_go(Nat.add(1n, String.length(s)), s)

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
