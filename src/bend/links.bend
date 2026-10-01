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

# URL identity is separate from style bits: bold+dim is attrs=3, never a link.
type Run is Data:
  Run{attrs: U32, text: String, url: Maybe<&2, String>}

type Alias is Data:
  Alias{text: String, rest: String}

type AliasEntry is Data:
  AliasEntry{name: String, text: String}

# Exact case-sensitive table from timui.h/examples/chat_text.h. Substitution is
# view-only: IRC/history retain shortcodes; cell selection copies their glyphs.
def aliases() -> List<&2, AliasEntry>:
  [AliasEntry{":eyes:", "👀"},
   AliasEntry{":wave:", "👋"},
   AliasEntry{":thumbsup:", "👍"},
   AliasEntry{":thumbs-up:", "👍"},
   AliasEntry{":+1:", "👍"},
   AliasEntry{":tada:", "🎉"},
   AliasEntry{":fire:", "🔥"},
   AliasEntry{":rocket:", "🚀"},
   AliasEntry{":heart:", "❤"},
   AliasEntry{":sparkles:", "✨"},
   AliasEntry{":bulb:", "💡"},
   AliasEntry{":clap:", "👏"},
   AliasEntry{":brain:", "🧠"},
   AliasEntry{":zap:", "⚡"},
   AliasEntry{":star:", "⭐"},
   AliasEntry{":joy:", "🤣"},
   AliasEntry{":raised_hands:", "🙌"},
   AliasEntry{":bow:", "🙇"},
   AliasEntry{":party:", "🥳"},
   AliasEntry{":bug:", "🐛"},
   AliasEntry{":globe:", "🌍"},
   AliasEntry{":boom:", "💥"}]

def alias.hit(found: Bool, +s: String, +name: String, text: String, other: Maybe<&2, Alias>) -> Maybe<&2, Alias>:
  match found:
    case True{}: Some{Alias{text, String.drop(s, String.length(name))}}
    case False{}: other

def alias.go(xs: List<&2, AliasEntry>, +s: String) -> Maybe<&2, Alias>:
  match xs:
    case Nil{}: None{}
    case Con{AliasEntry{+name, text}, t}:
      alias.hit(String.starts_with(s, name), s, name, text, alias.go(t, s))

def delimiter.double(double: Bool, s: String) -> String:
  match double:
    case True{}: "**"
    case False{}:
      match s:
        case SCon{Chr{42}, _}: "*"
        case SCon{Chr{95}, _}: "_"
        case SCon{Chr{96}, _}: "`"
        case _: ""

# Greedy ** before *. Longer runs have no special Markdown interpretation.
def delimiter(+s: String) -> String:
  delimiter.double(String.starts_with(s, "**"), s)

def escaped(s: String) -> Bool:
  match s:
    case SCon{Chr{92}, SCon{Chr{+n}, _}}:
      U32.is_eq(n, 42) || U32.is_eq(n, 95) || U32.is_eq(n, 96)
        || U32.is_eq(n, 92) || U32.is_eq(n, 58)
    case _: False{}

def ends_marker(+text: String, +mark: String) -> Bool:
  Bool.not(String.is_empty(mark)) && String.eq(delimiter(String.reverse(text)), mark)

def before_marker(+text: String, mark: String) -> String:
  String.take(text, Nat.sub(String.length(text), String.length(mark)))

type Scope is Data:
  Scope{attrs: U32, end: String}

def scope_end(scopes: List<&2, Scope>) -> String:
  match scopes:
    case Nil{}: ""
    case Con{Scope{_, end}, _}: end

type Search is Data:
  Seek{s: String, code: Bool, previous: String}
  Found{ok: Bool}

def paired.marker(+s: String, +wanted: String, +stop: String, +token: String) -> Search:
  +advance = Nat.max(1n, String.length(token))
  Bool.pick(Search, String.eq(token, wanted), Found{True{}},
    Bool.pick(Search, Bool.not(String.is_empty(stop)) && String.eq(token, stop),
      Found{False{}}, Seek{String.drop(s, advance), String.eq(token, "`"),
        String.reverse(String.take(s, advance))}))

# URL bytes are opaque even inside style delimiters. Active style closers
# may follow the URL at its end, before the existing trailing punctuation.
# Internal markers stay URL bytes: *https://x*next is literal + exact URL.
def take_marked.on(marked: Bool, +text: String, tail: String, +end: String) -> String & String:
  match marked:
    case True{}: (String.take(text, Nat.sub(String.length(text), String.length(end))), end ++ tail)
    case False{}: (text, tail)

def take_marked.pair(pair: String & String, +end: String, +outer: String) -> String & String:
  match pair:
    case (+text, tail):
      +both = ends_marker(text, outer) && ends_marker(before_marker(text, outer), end)
      take_marked.on(both || ends_marker(text, end), text, tail,
        Bool.pick(String, both, end ++ outer, end))

def take_marked(s: String, end: String, scopes: List<&2, Scope>) -> String & String:
  take_marked.pair(take(s), end, scope_end(scopes))

def paired.url(pair: String & String, +wanted: String, +stop: String) -> Search:
  match pair:
    case (+text, tail):
      Bool.pick(Search, ends_marker(text, wanted)
          || (ends_marker(text, stop) && ends_marker(before_marker(text, stop), wanted)), Found{True{}},
        Bool.pick(Search, ends_marker(text, stop),
          Found{False{}}, Seek{tail, False{}, ""}))

def paired.plain(url: Bool, +s: String, wanted: String, stop: String) -> Search:
  match url:
    case True{}: paired.url(take(s), wanted, stop)
    case False{}: paired.marker(s, wanted, stop, delimiter(s))

def paired.out(escape: Bool, +s: String, wanted: String, stop: String, previous: String) -> Search:
  match escape:
    case True{}: Seek{String.drop(s, 2n), False{}, String.reverse(String.take(s, 2n))}
    case False{}: paired.plain(is_url_prefix(s) && bound(previous), s, wanted, stop)

def paired.noncode(code: Bool, +s: String, wanted: String, stop: String, previous: String) -> Search:
  match code:
    case True{}: Seek{String.drop(s, 1n), Bool.not(String.starts_with(s, "`")), String.take(s, 1n)}
    case False{}: paired.out(escaped(s), s, wanted, stop, previous)

def paired.step(opaque: Bool, code: Bool, +s: String, wanted: String, stop: String, previous: String) -> Search:
  match opaque:
    case True{}:
      Bool.pick(Search, String.starts_with(s, "`"), Found{True{}},
        Seek{String.drop(s, 1n), False{}, ""})
    case False{}: paired.noncode(code, s, wanted, stop, previous)

def paired.go(fuel: Nat, j: Search, +wanted: String, +stop: String) -> Bool:
  match fuel:
    case 0n: False{}
    case 1n+p:
      match j:
        case Found{ok}: ok
        case Seek{+s, +code, previous}:
          Bool.pick(Bool, String.is_empty(s), False{},
            paired.go(p, paired.step(String.eq(wanted, "`"), code, s, wanted, stop, previous), wanted, stop))

def paired(+s: String, wanted: String, stop: String) -> Bool:
  paired.go(Nat.add(1n, String.length(s)), Seek{s, False{}, ""}, wanted, stop)

def marker_bit(+mark: String) -> U32:
  Bool.pick(U32, String.eq(mark, "_"), 4,
    Bool.pick(U32, String.eq(mark, "`"), 2, 1))

type Scan is Data:
  Scan{s: String, attrs: U32, end: String, scopes: List<&2, Scope>,
       text: String, previous: String, runs: List<&2, Run>}

# Different style bits can nest once each. Code is opaque, so this stack never
# grows beyond bold + italic + code; there is no general Markdown tree.
def flush(attrs: U32, text: String, runs: List<&2, Run>) -> List<&2, Run>:
  match text:
    case SNil{}: runs
    case SCon{h, t}: Run{attrs, String.reverse(SCon{h, t}), None{}} <> runs

def append(text: String, rest: String, previous: String, state: Scan) -> Scan:
  match state:
    case Scan{_, attrs, end, scopes, acc, _, runs}:
      Scan{rest, attrs, end, scopes, String.reverse(text) ++ acc, previous, runs}

def close.restore(rest: String, scopes: List<&2, Scope>, runs: List<&2, Run>) -> Scan:
  match scopes:
    case Nil{}: Scan{rest, 0, "", Nil{}, "", "", runs}
    case Con{Scope{attrs, end}, tail}: Scan{rest, attrs, end, tail, "", "", runs}

def close(state: Scan) -> Scan:
  match state:
    case Scan{+s, attrs, +end, scopes, text, _, runs}:
      close.restore(String.drop(s, String.length(end)), scopes, flush(attrs, text, runs))

def literal(+state: Scan) -> Scan:
  match state:
    case Scan{SCon{+h, t}, attrs, end, scopes, text, _, runs}:
      Scan{t, attrs, end, scopes, SCon{h, text}, SCon{h, ""}, runs}
    case _: state

def literal.token(empty: Bool, +mark: String, state: Scan) -> Scan:
  match empty:
    case True{}: literal(state)
    case False{}:
      match state:
        case Scan{+s, attrs, end, scopes, text, previous, runs}:
          append(mark, String.drop(s, String.length(mark)), String.reverse(mark),
            Scan{s, attrs, end, scopes, text, previous, runs})

def open.allowed(allowed: Bool, +mark: String, state: Scan) -> Scan:
  match allowed:
    case False{}: literal.token(String.is_empty(mark), mark, state)
    case True{}:
      match state:
        case Scan{+s, +attrs, +end, scopes, text, _, runs}:
          Scan{String.drop(s, String.length(mark)), U32.or(attrs, marker_bit(mark)), mark,
            Scope{attrs, end} <> scopes, "", "", flush(attrs, text, runs)}

def open(+mark: String, state: Scan) -> Scan:
  match state:
    case Scan{+s, +attrs, +end, +scopes, +text, +previous, +runs}:
      open.allowed(Bool.not(String.is_empty(mark))
          && U32.is_zero(U32.and(attrs, marker_bit(mark)))
          && paired(String.drop(s, String.length(mark)), mark, end),
        mark, Scan{s, attrs, end, scopes, text, previous, runs})

def substitute(alias: Maybe<&2, Alias>, state: Scan) -> Scan:
  match alias:
    case Some{Alias{text, rest}}: append(text, rest, ":", state)
    case None{}:
      match state:
        case Scan{+s, attrs, end, scopes, text, previous, runs}:
          open(delimiter(s), Scan{s, attrs, end, scopes, text, previous, runs})

def url(pair: String & String, state: Scan) -> Scan:
  match pair:
    case (+text, rest):
      match state:
        case Scan{_, +attrs, end, scopes, acc, _, runs}:
          Scan{rest, attrs, end, scopes, "", "",
            Run{attrs, text, Bool.pick(Maybe<&2, String>, U32.is_zero(attrs), Some{text}, None{})}
              <> flush(attrs, acc, runs)}

def outside.url(is_url: Bool, state: Scan) -> Scan:
  match is_url:
    case True{}:
      match state:
        case Scan{+s, attrs, +end, +scopes, text, previous, runs}:
          url(take_marked(s, end, scopes), Scan{s, attrs, end, scopes, text, previous, runs})
    case False{}:
      match state:
        case Scan{+s, attrs, end, scopes, text, previous, runs}:
          substitute(alias.go(aliases(), s), Scan{s, attrs, end, scopes, text, previous, runs})

def outside.escape(escape: Bool, state: Scan) -> Scan:
  match escape:
    case True{}:
      match state:
        case Scan{+s, attrs, end, scopes, text, previous, runs}:
          append(String.take(String.drop(s, 1n), 1n), String.drop(s, 2n),
            String.reverse(String.take(s, 2n)), Scan{s, attrs, end, scopes, text, previous, runs})
    case False{}:
      match state:
        case Scan{+s, attrs, end, scopes, text, +previous, runs}:
          outside.url(is_url_prefix(s) && bound(previous), Scan{s, attrs, end, scopes, text, previous, runs})

def next.closed(closed: Bool, state: Scan) -> Scan:
  match closed:
    case True{}: close(state)
    case False{}:
      match state:
        case Scan{+s, +attrs, +end, +scopes, +text, +previous, +runs}:
          Bool.pick(Scan, U32.is_ne(U32.and(attrs, 2), 0),
            literal(Scan{s, attrs, end, scopes, text, previous, runs}),
            outside.escape(escaped(s), Scan{s, attrs, end, scopes, text, previous, runs}))

def next(state: Scan) -> Scan:
  match state:
    case Scan{+s, attrs, +end, scopes, text, previous, runs}:
      next.closed(Bool.not(String.is_empty(end)) && String.eq(delimiter(s), end),
        Scan{s, attrs, end, scopes, text, previous, runs})

def finish(state: Scan) -> List<&2, Run>:
  match state:
    case Scan{_, attrs, _, _, text, _, runs}: List.reverse(&2, Run, flush(attrs, text, runs))

def render.go.on(empty: Bool, state: Scan, k: Scan -> List<&2, Run>) -> List<&2, Run>:
  match empty:
    case True{}: finish(state)
    case False{}: k(next(state))

def render.go(fuel: Nat, state: Scan) -> List<&2, Run>:
  match fuel:
    case 0n: finish(state)
    case 1n+p:
      match state:
        case Scan{+s, +attrs, +end, +scopes, +text, +previous, +runs}:
          render.go.on(String.is_empty(s), Scan{s, attrs, end, scopes, text, previous, runs},
            state => render.go(p, state))

# Every step consumes source; raw IRC/history/composer text is never rewritten.
def render(+s: String) -> List<&2, Run>:
  render.go(Nat.add(1n, String.length(s)), Scan{s, 0, "", Nil{}, "", "", Nil{}})

def extract_runs(xs: List<&2, Run>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case Con{Run{_, _, url}, t}:
      match url:
        case None{}: extract_runs(t)
        case Some{h}: h <> extract_runs(t)

def extract(+s: String) -> List<&2, String>:
  extract_runs(render(s))
