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

# Match timui_grapheme_next exactly within its documented common classes:
# extensions, a second regional indicator, and ZWJ plus its following scalar.
# One self-recursive walk in two phases: helpers cannot call back (no mutual
# recursion) and matches cannot scrutinize computed values, so Decide selects
# a phase value and each act arm matches parameters only. Decide spends fuel;
# act arms keep fuel and shrink the string.
type ClusterPhase is Data:
  Decide{}
  DoAttached{}
  DoZwj{}
  DoZwjAbsorb{}
  DoCut{}

def cluster_go(fuel: Nat, s: String, +ri: Bool, head: String, phase: ClusterPhase) -> Cut:
  match fuel:
    case 0n: cluster_cut(head, s)
    case 1n+p:
      match s:
        case SNil{}: cluster_cut(head, "")
        case SCon{+h, +t}:
          match phase:
            case Decide{}:
              +c = Char.to_u32(h)
              +at = extend(c) || (ri && regional(c))
              +zw = U32.is_eq(c, 8205)
              cluster_go(p, SCon{h, t}, ri, head, Bool.pick(ClusterPhase, at, DoAttached{}, Bool.pick(ClusterPhase, zw, DoZwj{}, DoCut{})))
            case DoAttached{}:
              cluster_go(fuel, t, ri && Bool.not(regional(Char.to_u32(h))), SCon{h, head}, Decide{})
            case DoZwj{}:
              cluster_go(fuel, t, ri, SCon{h, head}, DoZwjAbsorb{})
            case DoZwjAbsorb{}:
              cluster_go(fuel, t, ri, SCon{h, head}, Decide{})
            case DoCut{}:
              cluster_cut(head, SCon{h, t})

def cluster_crlf_cut(nl: Bool, +h: Char, +next: Char, +rest: String) -> Cut:
  match nl:
    case True{}: Cut{SCon{h, SCon{next, ""}}, rest, 0}
    case False{}: Cut{SCon{h, ""}, SCon{next, rest}, 0}

def cluster_crlf(s: String, +h: Char) -> Cut:
  match s:
    case SNil{}: Cut{SCon{h, ""}, "", 0}
    case SCon{+next, +rest}:
      cluster_crlf_cut(U32.is_eq(Char.to_u32(next), 10), h, next, rest)

# `fuel` is the caller's remaining bound for this string. It must be at least
# one more than the number of scalars after the first: Decide spends one per
# scalar it inspects, and a cluster looks one scalar past its end. Callers
# that walk cluster by cluster pass their own decreasing fuel instead of
# scanning the tail with String.length on every cluster.
def cluster_start(fuel: Nat, cr: Bool, lf: Bool, +h: Char, t: String) -> Cut:
  match cr:
    case True{}: cluster_crlf(t, h)
    case False{}:
      match lf:
        case True{}: Cut{SCon{h, ""}, t, 0}
        case False{}:
          cluster_go(fuel, t, regional(Char.to_u32(h)), SCon{h, ""}, Decide{})

def cluster_bounded(s: String, fuel: Nat) -> Cut:
  match s:
    case SNil{}: Cut{"", "", 0}
    case SCon{+h, +t}:
      cluster_start(fuel, U32.is_eq(Char.to_u32(h), 13), U32.is_eq(Char.to_u32(h), 10), h, t)

def cluster(s: String) -> Cut:
  match s:
    case SNil{}: Cut{"", "", 0}
    case SCon{_, +t}:
      cluster_bounded(s, Nat.add(1n, String.length(t)))

def cut_text(piece: Cut) -> String:
  match piece:
    case Cut{text, _, _}: text

def cut_tail(piece: Cut) -> String:
  match piece:
    case Cut{_, tail, _}: tail

def cut_width(piece: Cut) -> U32:
  match piece:
    case Cut{_, _, w}: w

# `bound` is a copyable cluster-walk limit (2*len+2). The match binder `p`
# stays the decreasing first argument and is not also handed to cluster_bounded.
def text_width_go(fuel: Nat, s: String, +bound: Nat) -> U32:
  match fuel:
    case 0n:
      match s:
        case SNil{}: Bool.pick(U32, Nat.is_eq(bound, 0n), 0, 0)
        case SCon{_, _}: Bool.pick(U32, Nat.is_eq(bound, 0n), 0, 0)
    case 1n+p:
      match s:
        case SNil{}: Bool.pick(U32, Nat.is_eq(Nat.add(p, bound), 0n), 0, 0)
        case SCon{_, _}:
          +cut = cluster_bounded(s, bound)
          U32.add(cut_width(cut), text_width_go(p, cut_tail(cut), bound))

def text_width(+s: String) -> U32:
  +n = String.length(s)
  +fuel = Nat.add(2n, Nat.add(n, n))
  text_width_go(fuel, s, fuel)

# Fit complete common grapheme clusters. The returned width is in columns,
# not code points or UTF-8 bytes. The fit fields ride in the phase value;
# both hops shrink fuel, so the entry fuel covers two spends per cluster.
type TakePhase is Data:
  TakeDecide{}
  TakeFit{tail: String, text: String, uw: U32}
  TakeNoFit{}

def take_end(done: Bool, head: String, s: String, +used: U32) -> Cut:
  match done:
    case True{}: Cut{String.reverse(head), s, used}
    case False{}: Cut{String.reverse(head), s, used}

def take_go(fuel: Nat, s: String, +cap: U32, +used: U32, head: String, phase: TakePhase, +bound: Nat) -> Cut:
  match fuel:
    case 0n: take_end(Nat.is_eq(bound, 0n), head, s, used)
    case 1n+p:
      match s:
        case SNil{}: take_end(Nat.is_eq(Nat.add(p, bound), 0n), head, "", used)
        case SCon{+h, +t}:
          match phase:
            case TakeDecide{}:
              +cut = cluster_bounded(SCon{h, t}, bound)
              +text = cut_text(cut)
              +tail = cut_tail(cut)
              +uw = U32.add(used, cut_width(cut))
              +fits = U32.is_le(uw, cap)
              take_go(p, SCon{h, t}, cap, used, head, Bool.pick(TakePhase, fits, TakeFit{tail, text, uw}, TakeNoFit{}), bound)
            case TakeFit{tail, text, uw}:
              take_go(p, tail, cap, uw, String.reverse(text) ++ head, TakeDecide{}, bound)
            case TakeNoFit{}:
              take_end(Nat.is_eq(Nat.add(p, bound), 0n), head, SCon{h, t}, used)

def take(+s: String, cap: U32) -> Cut:
  +n = String.length(s)
  +fuel = Nat.add(2n, Nat.add(n, n))
  take_go(fuel, s, cap, 0, "", TakeDecide{}, fuel)
