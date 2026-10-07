# SPDX-License-Identifier: Apache-2.0
# Native IRC wire formatting (mIRC control codes) for the view. Pure.
#
# Policy:
# - Formatting bytes become display styles; they never reach the terminal.
# - Visible text matches Irc.sanitize_in on SOH-free input, so history and
#   URL extraction keep exact bytes. SOH is CTCP framing: sanitize keeps it
#   for parsing, the view drops it at a seg boundary so it cannot forge
#   links or paint bytes.
# - 0x02 bold, 0x1D italic, 0x1F underline, 0x16 reverse, 0x1E strike toggle.
#   0x11 monospace is consumed without a style (no terminal monospace attr).
#   0x0F resets attrs and color. A bare 0x03 resets the color only.
# - 0x03 consumes exactly the bytes Irc.skip_mirc consumes: 1-2 fg digits,
#   then comma plus 1-2 bg digits only after fg digits when a bg digit
#   follows. Bg digits are consumed and ignored (SpanOp has no bg slot).
#   Numbers above 15 reset the color (fail closed).
# - Markdown, aliases, and URLs lex each style run separately: wire codes are
#   opaque boundaries for local styles. A URL keeps its link only when it
#   would linkify in the glued visible text (non-alnum before, space or end
#   after); otherwise it stays exact literal text, never a forged link.
#   Dropped bytes (SOH, monospace, other controls) are also seg boundaries:
#   no invisible byte can glue link bytes together. The boundary only splits
#   spans; painted text is unchanged.
# - Styles never leak across lines: every parse starts unstyled, and an
#   unclosed toggle simply ends with its line.
import Base
import ./irc.bend as Irc
import ./links.bend as Links

# Standard mIRC palette (hex in comments).
def fg_of(+n: U32) -> U32:
  match n:
    case 0: 16777215 # FFFFFF white
    case 1: 0 # 000000 black
    case 2: 127 # 00007F blue
    case 3: 37632 # 009300 green
    case 4: 16711680 # FF0000 red
    case 5: 8323072 # 7F0000 brown
    case 6: 10223772 # 9C009C purple
    case 7: 16547584 # FC7F00 orange
    case 8: 16776960 # FFFF00 yellow
    case 9: 64512 # 00FC00 light green
    case 10: 37779 # 009393 teal
    case 11: 65535 # 00FFFF light cyan
    case 12: 252 # 0000FC light blue
    case 13: 16711935 # FF00FF pink
    case 14: 8355711 # 7F7F7F grey
    case _: 13816530 # D2D2D2 light grey (15; callers check fg_valid)

def fg_valid(+n: U32) -> Bool:
  U32.is_le(n, 15)

# One style run over visible text. Bg digits never reach this type.
type Seg is Data:
  Seg{attrs: U32, fg: U32, has_fg: Bool, text: String}

# One markdown run with its wire style. Links keep their exact URL; like the
# existing renderer, styles on links are dropped at the SpanOp edge.
type SRun is Data:
  SRun{attrs: U32, fg: U32, has_fg: Bool, text: String, url: Maybe<&2, String>}

type CSpec is Data:
  CSpec{fg: U32, has_fg: Bool, rest: String}

def digit_val(+h: Char) -> U32:
  U32.sub(Char.to_u32(h), 48)

def color_bg.second(dig: Bool, +h: Char, +t: String) -> String:
  match dig:
    case True{}: t
    case False{}: SCon{h, t}

def color_bg.more(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+h, +t}: color_bg.second(Char.is_digit(h), h, t)

def color_bg.first(dig: Bool, +h: Char, +t: String) -> String:
  match dig:
    case True{}: color_bg.more(t)
    case False{}: SCon{h, t}

def color_bg(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+h, +t}: color_bg.first(Char.is_digit(h), h, t)

def color_comma.at(comma: Bool, +h: Char, +t: String) -> String:
  match comma:
    case True{}: color_bg(t)
    case False{}: SCon{h, t}

def color_comma(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{+h, +t}: color_comma.at(Irc.code_is(h, 44) && Irc.starts_digit(t), h, t)

def color_after_fg.valid(valid: Bool, +v: U32, +s: String) -> CSpec:
  match valid:
    case True{}: CSpec{fg_of(v), True{}, color_comma(s)}
    case False{}: CSpec{0, False{}, color_comma(s)}

def color_after_fg(+v: U32, +s: String) -> CSpec:
  color_after_fg.valid(fg_valid(v), v, s)

def color_d2.second(dig: Bool, +v1: U32, +h: Char, +t: String) -> CSpec:
  match dig:
    case True{}: color_after_fg(U32.add(U32.mul(v1, 10), digit_val(h)), t)
    case False{}: color_after_fg(v1, SCon{h, t})

def color_d2(+v1: U32, +s: String) -> CSpec:
  match s:
    case SNil{}: color_after_fg(v1, "")
    case SCon{+h, +t}: color_d2.second(Char.is_digit(h), v1, h, t)

def color.first(dig: Bool, +h: Char, +t: String) -> CSpec:
  match dig:
    case True{}: color_d2(digit_val(h), t)
    case False{}: CSpec{0, False{}, SCon{h, t}}

# s follows the 0x03 byte. A bare 0x03 resets the color only.
def color(+s: String) -> CSpec:
  match s:
    case SNil{}: CSpec{0, False{}, ""}
    case SCon{+h, +t}: color.first(Char.is_digit(h), h, t)

def flush(+attrs: U32, +fg: U32, +has_fg: Bool, +acc: String, segs: List<&2, Seg>) -> List<&2, Seg>:
  match acc:
    case SNil{}: segs
    case SCon{_, _}: Seg{attrs, fg, has_fg, String.reverse(acc)} <> segs

def toggle.off(off: Bool, +attrs: U32, +bit: U32) -> U32:
  match off:
    case True{}: U32.add(attrs, bit)
    case False{}: U32.sub(attrs, bit)

def toggle(+attrs: U32, +bit: U32) -> U32:
  toggle.off(U32.is_zero(U32.and(attrs, bit)), attrs, bit)

def wire_drop(+h: Char) -> Bool:
  +n = Char.to_u32(h)
  U32.is_lt(n, 32) || U32.is_eq(n, 127)

# Destructures one color parse for the scan loop below. This helper never
# names parse_go: the loop passes its own continuation (no mutual recursion).
def parse_color.apply(spec: CSpec, k: U32 -> Bool -> String -> List<&2, Seg>) -> List<&2, Seg>:
  match spec:
    case CSpec{+fg, +has_fg, +rest}: k(fg, has_fg, rest)

def parse_done(+attrs: U32, +fg: U32, +has_fg: Bool, +acc: String, segs: List<&2, Seg>) -> List<&2, Seg>:
  List.reverse(&2, Seg, flush(attrs, fg, has_fg, acc, segs))

# Every step consumes at least one source byte (0x03 consumes itself plus
# whatever color() eats), so fuel 1+length always suffices.
def parse_go(fuel: Nat, +s: String, +attrs: U32, +fg: U32, +has_fg: Bool, +acc: String, +segs: List<&2, Seg>) -> List<&2, Seg>:
  match fuel:
    case 0n: parse_done(attrs, fg, has_fg, acc, segs)
    case 1n+p:
      match s:
        case SNil{}: parse_done(attrs, fg, has_fg, acc, segs)
        case SCon{Chr{2}, t}: parse_go(p, t, toggle(attrs, 1), fg, has_fg, "", flush(attrs, fg, has_fg, acc, segs))
        case SCon{Chr{29}, t}: parse_go(p, t, toggle(attrs, 4), fg, has_fg, "", flush(attrs, fg, has_fg, acc, segs))
        case SCon{Chr{31}, t}: parse_go(p, t, toggle(attrs, 8), fg, has_fg, "", flush(attrs, fg, has_fg, acc, segs))
        case SCon{Chr{22}, t}: parse_go(p, t, toggle(attrs, 16), fg, has_fg, "", flush(attrs, fg, has_fg, acc, segs))
        case SCon{Chr{30}, t}: parse_go(p, t, toggle(attrs, 64), fg, has_fg, "", flush(attrs, fg, has_fg, acc, segs))
        case SCon{Chr{17}, t}: parse_go(p, t, attrs, fg, has_fg, "", flush(attrs, fg, has_fg, acc, segs))
        case SCon{Chr{15}, t}: parse_go(p, t, 0, 0, False{}, "", flush(attrs, fg, has_fg, acc, segs))
        case SCon{Chr{1}, t}: parse_go(p, t, attrs, fg, has_fg, "", flush(attrs, fg, has_fg, acc, segs))
        case SCon{Chr{3}, t}: parse_color.apply(color(t), nfg => nhas => nrest => parse_go(p, nrest, attrs, nfg, nhas, "", flush(attrs, fg, has_fg, acc, segs)))
        case SCon{+h, +t}:
          +drop = wire_drop(h)
          parse_go(p, t, attrs, fg, has_fg, Bool.pick(String, drop, "", SCon{h, acc}), Bool.pick(List<&2, Seg>, drop, flush(attrs, fg, has_fg, acc, segs), segs))

def parse(+s: String) -> List<&2, Seg>:
  parse_go(Nat.add(1n, String.length(s)), s, 0, 0, False{}, "", Nil{})

def visible(+xs: List<&2, Seg>) -> String:
  match xs:
    case Nil{}: ""
    case Con{Seg{_, _, _, +text}, t}: text ++ visible(t)

def last_alnum.go(+s: String, +acc: Bool) -> Bool:
  match s:
    case SNil{}: acc
    case SCon{+h, t}: last_alnum.go(t, Links.alnum(h))

def seg_last_alnum(seg: Seg) -> Bool:
  match seg:
    case Seg{_, _, _, +text}: last_alnum.go(text, False{})

def seg_first_space(+s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, _}: Irc.code_is(h, 32)

def rest_ok(+rest: List<&2, Seg>) -> Bool:
  match rest:
    case Nil{}: True{}
    case Con{Seg{_, _, _, +text}, _}: seg_first_space(text)

def stylize.degraded(degraded: Bool, +attrs: U32, +fg: U32, +has_fg: Bool, +text: String, +url: Maybe<&2, String>) -> SRun:
  match degraded:
    case True{}: SRun{attrs, fg, has_fg, text, None{}}
    case False{}: SRun{attrs, fg, has_fg, text, url}

def stylize(run: Links.Run, +wattrs: U32, +wfg: U32, +whas: Bool, degrade: Bool) -> SRun:
  match run:
    case Links.Run{+attrs, +text, +url}: stylize.degraded(degrade, U32.or(attrs, wattrs), wfg, whas, text, url)

# Spaces survive markdown lexing one-to-one, so a run whose later runs hold no
# space sits in the seg's last token: glued text continues past the boundary
# and any link there would differ from (or vanish under) glued lexing.
def run_has_space(+s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{+h, t}: Irc.code_is(h, 32) || run_has_space(t)

def later_has_space(+runs: List<&2, Links.Run>) -> Bool:
  match runs:
    case Nil{}: False{}
    case Con{Links.Run{_, +text, _}, +t}: run_has_space(text) || later_has_space(t)

def render_runs.go(+runs: List<&2, Links.Run>, +wattrs: U32, +wfg: U32, +whas: Bool, +prev_alnum: Bool, +next_ok: Bool, +i: Nat) -> List<&2, SRun>:
  match runs:
    case Nil{}: Nil{}
    case Con{+run, +t}:
      +bad = (Nat.is_eq(i, 0n) && prev_alnum) || (Bool.not(next_ok) && Bool.not(later_has_space(t)))
      stylize(run, wattrs, wfg, whas, bad) <> render_runs.go(t, wattrs, wfg, whas, prev_alnum, next_ok, Nat.add(i, 1n))

def render_seg(seg: Seg, +prev_alnum: Bool, +next_ok: Bool) -> List<&2, SRun>:
  match seg:
    case Seg{+attrs, +fg, +has_fg, +text}:
      render_runs.go(Links.render(text), attrs, fg, has_fg, prev_alnum, next_ok, 0n)

def render_segs.go(+xs: List<&2, Seg>, +prev_alnum: Bool) -> List<&2, SRun>:
  match xs:
    case Nil{}: Nil{}
    case Con{+seg, +rest}: List.append(&2, SRun, render_seg(seg, prev_alnum, rest_ok(rest)), render_segs.go(rest, seg_last_alnum(seg)))

def render_segs(+xs: List<&2, Seg>) -> List<&2, SRun>:
  render_segs.go(xs, False{})

def render(+s: String) -> List<&2, SRun>:
  render_segs(parse(s))

# Shared boundary-aware URL-runs seam for View, /open, Media, and Cards.
# Every consumer reads these same runs: wire style controls are segment
# boundaries, so there is no SOH-scheme glue and no style-infixed match.
# Consumers filter these runs for their own exclusions; they never
# flatten/relex the text or run a second lexer.
def url_runs(+s: String) -> List<&2, SRun>:
  render(s)

def rendered_text(+xs: List<&2, SRun>) -> String:
  match xs:
    case Nil{}: ""
    case Con{SRun{_, _, _, +text, _}, t}: text ++ rendered_text(t)

# Styled link collection for /open and /links: exactly the links the view
# paints (boundary-degraded runs stay literal), with exact URL bytes.
def extract_runs(+xs: List<&2, SRun>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{SRun{_, _, _, _, url}, t}:
      match url:
        case None{}: extract_runs(t)
        case Some{h}: h <> extract_runs(t)

def extract(+s: String) -> List<&2, String>:
  extract_runs(render(s))
