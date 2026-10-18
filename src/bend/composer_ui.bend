# Slash ghost suffix, command menu, and /help lines. Pure. Nothing here is sent.
import Base
import ./emoji.bend as Emoji
import ./irc.bend as Irc
import ./submit.bend as Sub

def usage(+name: String) -> String:
  match name:
    case "help": "/help [command]"
    case "join": "/join <#channel>"
    case "part": "/part [#channel] [reason]"
    case "close": "/close [buffer]"
    case "msg": "/msg <nick> <text>"
    case "query": "/query <nick>"
    case "nick": "/nick <name>"
    case "me": "/me <action>"
    case "quit": "/quit [reason]"
    case "settings": "/settings"
    case "set": "/set <key> <value>"
    case "toggle": "/toggle <key>"
    case "mute": "/mute <nick>"
    case "unmute": "/unmute <nick>"
    case "mutes": "/mutes"
    case "connect": "/connect <host[:port]> [port]"
    case "reconnect": "/reconnect"
    case "open": "/open <url>"
    case "links": "/links"
    case "search": "/search <text>"
    case "history": "/history [target]"
    case "preview": "/preview <path>"
    case "images": "/images [on|off]"
    case "theme": "/theme [name]"
    case "log": "/log"
    case "split": "/split [buffer]"
    case "vsplit": "/vsplit [buffer]"
    case "split-off": "/split-off"
    case "unsplit": "/unsplit"
    case "focus": "/focus"
    case "upload": "/upload <local-path>"
    case "whois": "/whois <nick>"
    case "who": "/who [mask]"
    case "list": "/list"
    case "names": "/names"
    case "topic": "/topic [text]"
    case "mode": "/mode [flags]"
    case "kick": "/kick <nick> [reason]"
    case "invite": "/invite <nick>"
    case "away": "/away [reason]"
    case "notice": "/notice <target> <text>"
    case "raw": "/raw <line>"
    case "quote": "/quote <line>"
    case _: ""

def blurb(+name: String) -> String:
  match name:
    case "help": "Show commands"
    case "join": "Join a channel"
    case "part": "Leave a channel"
    case "close": "Close a buffer"
    case "msg": "Send a private message"
    case "query": "Open a private buffer"
    case "nick": "Change nickname"
    case "me": "Send an action"
    case "quit": "Disconnect"
    case "settings": "Open settings"
    case "set": "Set a preference"
    case "toggle": "Toggle a preference"
    case "mute": "Hide a nick"
    case "unmute": "Show a nick"
    case "mutes": "List muted nicks"
    case "connect": "Connect to a server"
    case "reconnect": "Reconnect"
    case "open": "Open a URL"
    case "links": "List links"
    case "search": "Search history"
    case "history": "Load older history"
    case "preview": "Preview a local image"
    case "images": "Toggle image previews"
    case "theme": "Choose a theme"
    case "log": "Open the log buffer"
    case "split": "Split the window"
    case "vsplit": "Split vertically"
    case "split-off": "Close the split"
    case "unsplit": "Close the split"
    case "focus": "Switch pane"
    case "upload": "Upload a file"
    case "whois": "Look up a nick"
    case "who": "List matching nicks"
    case "list": "List channels"
    case "names": "List names"
    case "topic": "Show or set the topic"
    case "mode": "Show or set modes"
    case "kick": "Kick a nick"
    case "invite": "Invite a nick"
    case "away": "Set away"
    case "notice": "Send a notice"
    case "raw": "Send a raw line"
    case "quote": "Send a raw line"
    case _: ""

def menu_spaces(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: " " ++ menu_spaces(p)

def menu_fit.on(fits: Bool, +s: String, +n: Nat) -> String:
  match fits:
    case True{}: s
    case False{}: s ++ menu_spaces(Nat.sub(n, String.length(s)))

def menu_fit(+s: String) -> String:
  menu_fit.on(Nat.is_ge(String.length(s), 30n), s, 30n)

def menu_mark(first: Bool) -> String:
  match first:
    case True{}: "→ "
    case False{}: "  "

def menu_row(first: Bool, +name: String) -> String:
  menu_mark(first) ++ menu_fit(usage(name)) ++ "  " ++ blurb(name)

def row_name(row: Sub.SlashRow) -> String:
  match row:
    case Sub.SlashRow{+name, _}: name

def names_keep(ok: Bool, +name: String, rest: List<&2, String>) -> List<&2, String>:
  match ok:
    case True{}: name <> rest
    case False{}: rest

def names_pref(fuel: Nat, xs: List<&2, Sub.SlashRow>, +pre: String) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+h, t}: names_keep(String.starts_with(row_name(h), pre), row_name(h), names_pref(p, t, pre))

def command_names(+pre: String) -> List<&2, String>:
  names_pref(Sub.slash_fuel(), Sub.slash_rows(), pre)

def command_word.space(spaced: Bool, +rest: String) -> Maybe<&2, String>:
  match spaced:
    case True{}: None{}
    case False{}: Some{rest}

def command_word.slash(slash: Bool, +typed: String) -> Maybe<&2, String>:
  match slash:
    case False{}: None{}
    case True{}:
      +rest = String.drop(typed, 1n)
      command_word.space(String.contains(rest, " "), rest)

# A slash token with no argument. None once the user has typed a space.
def command_word(+typed: String) -> Maybe<&2, String>:
  command_word.slash(String.starts_with(typed, "/"), typed)

def shared.take(eq: Bool, +a: String, +rest: String) -> String:
  match eq:
    case False{}: ""
    case True{}: String.take(a, 1n) ++ rest

def shared.go(fuel: Nat, +a: String, +b: String) -> String:
  match fuel:
    case 0n: ""
    case 1n+p:
      shared.take(
        Bool.and(Bool.not(String.is_empty(a)), Bool.and(Bool.not(String.is_empty(b)), String.eq(String.take(a, 1n), String.take(b, 1n)))),
        a,
        shared.go(p, String.drop(a, 1n), String.drop(b, 1n)))

def shared(+a: String, +b: String) -> String:
  shared.go(64n, a, b)

def common_fold(fuel: Nat, xs: List<&2, String>, +acc: String) -> String:
  match fuel:
    case 0n: acc
    case 1n+p:
      match xs:
        case Nil{}: acc
        case Con{+h, t}: common_fold(p, t, shared(acc, h))

def ghost_one.on(same: Bool, +word: String, +name: String) -> String:
  match same:
    case True{}: " "
    case False{}: String.drop(name, String.length(word))

def ghost_one(+word: String, +name: String) -> String:
  ghost_one.on(String.eq(word, name), word, name)

def ghost_of(+word: String, xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, t}:
      match t:
        case Nil{}: ghost_one(word, h)
        case _: String.drop(common_fold(Sub.slash_fuel(), t, h), String.length(word))

def ghost_word(word: Maybe<&2, String>) -> String:
  match word:
    case None{}: ""
    case Some{+w}: ghost_of(w, command_names(w))

def ghost_suffix(+typed: String) -> String:
  ghost_word(command_word(typed))

def slash_name(+name: String) -> String:
  "/" ++ name

def take_rows(fuel: Nat, xs: List<&2, String>, +at: Nat, +selected: Nat) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+h, t}: menu_row(Nat.is_eq(at, selected), h) <> take_rows(p, t, Nat.add(at, 1n), selected)

def menu_more(more: Bool, rows: List<&2, String>) -> List<&2, String>:
  match more:
    case False{}: rows
    case True{}: List.append(&2, String, rows, "  ↓ more below" <> Nil{})

def page_start.go(fuel: Nat, here: Bool, +idx: Nat) -> Nat:
  match fuel:
    case 0n: 0n
    case 1n+p:
      match here:
        case True{}: 0n
        case False{}: Nat.add(8n, page_start.go(p, Nat.is_lt(Nat.sub(idx, 8n), 8n), Nat.sub(idx, 8n)))

def page_start(+idx: Nat) -> Nat:
  page_start.go(8n, Nat.is_lt(idx, 8n), idx)

def pick_clamp.on(over: Bool, +idx: Nat, +n: Nat) -> Nat:
  match over:
    case True{}: Nat.sub(n, 1n)
    case False{}: idx

def pick_clamp(+idx: Nat, +n: Nat) -> Nat:
  pick_clamp.on(Bool.and(Nat.is_gt(n, 0n), Bool.not(Nat.is_lt(idx, n))), idx, n)

def pick_up(zero: Bool, +idx: Nat) -> Nat:
  match zero:
    case True{}: 0n
    case False{}: Nat.sub(idx, 1n)

def pick_down(last: Bool, +idx: Nat) -> Nat:
  match last:
    case True{}: idx
    case False{}: Nat.add(idx, 1n)

def pick_move(down: Bool, +idx: Nat, +n: Nat) -> Nat:
  match down:
    case False{}: pick_up(Nat.is_eq(idx, 0n), idx)
    case True{}: pick_down(Bool.not(Nat.is_lt(Nat.add(idx, 1n), n)), idx)

def menu_page(+n: Nat, xs: List<&2, String>, +idx: Nat) -> List<&2, String>:
  +at = pick_clamp(idx, n)
  +start = page_start(at)
  menu_more(Nat.is_gt(n, Nat.add(start, 8n)), take_rows(8n, List.drop(&2, String, xs, start), start, at))

def menu_of(n: Nat, xs: List<&2, String>, +idx: Nat) -> List<&2, String>:
  match n:
    case 0n: Nil{}
    case 1n: Nil{}
    case _: menu_page(n, xs, idx)

def menu_word(word: Maybe<&2, String>, +idx: Nat) -> List<&2, String>:
  match word:
    case None{}: Nil{}
    case Some{+w}:
      +names = command_names(w)
      menu_of(List.length(&2, String, names), names, idx)

def menu_lines_at(+typed: String, +idx: Nat) -> List<&2, String>:
  menu_word(command_word(typed), idx)

def menu_lines(+typed: String) -> List<&2, String>:
  menu_lines_at(typed, 0n)

def menu_len_word(word: Maybe<&2, String>) -> Nat:
  match word:
    case None{}: 0n
    case Some{+w}: List.length(&2, String, command_names(w))

def menu_len(+typed: String) -> Nat:
  menu_len_word(command_word(typed))

# Trailing :shortcode picker. A finished :name: becomes its glyph in the draft.
# The chat view still expands shortcodes that arrive on the wire.
type Colon is Data:
  Colon{seen: Bool, before: String, after: String}

def one(+h: Char) -> String:
  SCon{h, SNil{}}

def split_colon.go(s: String, colon: Bool, +held: Char, +before: String, +after: String, seen: Bool) -> Colon:
  match s:
    case SNil{}:
      match colon:
        case True{}: Colon{True{}, before ++ after ++ ":", ""}
        case False{}: Colon{seen, before, after ++ one(held)}
    case SCon{+n, t}:
      match colon:
        case True{}: split_colon.go(t, U32.is_eq(Char.to_u32(n), 58), n, before ++ after ++ ":", "", True{})
        case False{}: split_colon.go(t, U32.is_eq(Char.to_u32(n), 58), n, before, after ++ one(held), seen)

def split_colon(s: String) -> Colon:
  match s:
    case SNil{}: Colon{False{}, "", ""}
    case SCon{+h, t}: split_colon.go(t, U32.is_eq(Char.to_u32(h), 58), h, "", "", False{})

def name_char(+n: U32) -> Bool:
  (U32.is_ge(n, 48) && U32.is_le(n, 57))
    || (U32.is_ge(n, 65) && U32.is_le(n, 90))
    || (U32.is_ge(n, 97) && U32.is_le(n, 122))
    || U32.is_eq(n, 95) || U32.is_eq(n, 45) || U32.is_eq(n, 43)

def name_chars(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}: name_char(Char.to_u32(h)) && name_chars(t)

def last_u32.rev(s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{+h, _}: Char.to_u32(h)

def last_u32(+s: String) -> U32:
  last_u32.rev(String.reverse(s))

def at_boundary.empty(empty: Bool, +stem: String) -> Bool:
  match empty:
    case True{}: True{}
    case False{}: Bool.not(name_char(last_u32(stem)))

def at_boundary(+pre: String) -> Bool:
  at_boundary.empty(String.is_empty(String.take(pre, Nat.sub(String.length(pre), 1n))), String.take(pre, Nat.sub(String.length(pre), 1n)))

def emoji_keep(eq: Bool, +text: String, +rest: String) -> String:
  match eq:
    case True{}: text
    case False{}: rest

def emoji_find(fuel: Nat, xs: List<&2, Emoji.Entry>, +code: String) -> String:
  match fuel:
    case 0n: ""
    case 1n+p:
      match xs:
        case Nil{}: ""
        case Con{Emoji.Entry{+name, +text}, t}: emoji_keep(String.eq(name, code), text, emoji_find(p, t, code))

def emoji_commit.hit(empty: Bool, +glyph: String, +pre: String, +s: String) -> String:
  match empty:
    case True{}: s
    case False{}: String.take(pre, Nat.sub(String.length(pre), 1n)) ++ glyph

def emoji_commit.name(ok: Bool, +pre: String, +name: String, +s: String) -> String:
  match ok:
    case False{}: s
    case True{}:
      +glyph = emoji_find(80n, Emoji.aliases(), ":" ++ name ++ ":")
      emoji_commit.hit(String.is_empty(glyph), glyph, pre, s)

def emoji_commit.closed(c: Colon, +s: String) -> String:
  match c:
    case Colon{seen, +pre, +name}:
      emoji_commit.name(Bool.and(seen, Bool.and(name_chars(name), at_boundary(pre))), pre, name, s)

def emoji_commit.on(closed: Bool, +before: String, +s: String) -> String:
  match closed:
    case False{}: s
    case True{}: emoji_commit.closed(split_colon(String.take(before, Nat.sub(String.length(before), 1n))), s)

def emoji_commit.got(c: Colon, +s: String) -> String:
  match c:
    case Colon{seen, +before, +after}: emoji_commit.on(Bool.and(seen, String.is_empty(after)), before, s)

def emoji_commit(+s: String) -> String:
  emoji_commit.got(split_colon(s), s)

def emoji_prefix.on(ok: Bool, +after: String) -> Maybe<&2, String>:
  match ok:
    case False{}: None{}
    case True{}: Some{after}

def emoji_prefix.got(c: Colon) -> Maybe<&2, String>:
  match c:
    case Colon{seen, +before, +after}:
      emoji_prefix.on(Bool.and(seen, Bool.and(name_chars(after), at_boundary(before))), after)

def emoji_prefix(+s: String) -> Maybe<&2, String>:
  emoji_prefix.got(split_colon(s))

def emoji_name(e: Emoji.Entry) -> String:
  match e:
    case Emoji.Entry{+name, _}: name

def emoji_text(e: Emoji.Entry) -> String:
  match e:
    case Emoji.Entry{_, +text}: text

def emoji_cons(ok: Bool, +e: Emoji.Entry, rest: List<&2, Emoji.Entry>) -> List<&2, Emoji.Entry>:
  match ok:
    case True{}: e <> rest
    case False{}: rest

def emoji_matches(fuel: Nat, xs: List<&2, Emoji.Entry>, +pre: String) -> List<&2, Emoji.Entry>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+h, t}: emoji_cons(String.starts_with(emoji_name(h), ":" ++ pre), h, emoji_matches(p, t, pre))

def emoji_len.pre(word: Maybe<&2, String>) -> Nat:
  match word:
    case None{}: 0n
    case Some{+pre}: List.length(&2, Emoji.Entry, emoji_matches(80n, Emoji.aliases(), pre))

def emoji_len(+s: String) -> Nat:
  emoji_len.pre(emoji_prefix(s))

def emoji_pick(here: Bool, +h: Emoji.Entry, +rest: Emoji.Entry) -> Emoji.Entry:
  match here:
    case True{}: h
    case False{}: rest

def emoji_nth(fuel: Nat, here: Bool, +h: Emoji.Entry, xs: List<&2, Emoji.Entry>, +idx: Nat) -> Emoji.Entry:
  match fuel:
    case 0n: Emoji.Entry{"", ""}
    case 1n+p:
      match here:
        case True{}: h
        case False{}:
          match xs:
            case Nil{}: Emoji.Entry{"", ""}
            case Con{+n, t}: emoji_nth(p, Nat.is_eq(idx, 1n), n, t, Nat.sub(idx, 1n))

def emoji_at(xs: List<&2, Emoji.Entry>, +idx: Nat) -> Emoji.Entry:
  match xs:
    case Nil{}: Emoji.Entry{"", ""}
    case Con{+h, t}: emoji_nth(80n, Nat.is_eq(idx, 0n), h, t, idx)

# Shared match-list readers: ghost / glyph / lines / accept bind +ms once.
def emoji_glyph.of(+ms: List<&2, Emoji.Entry>, +idx: Nat) -> String:
  emoji_text(emoji_at(ms, pick_clamp(idx, List.length(&2, Emoji.Entry, ms))))

def emoji_glyph(+pre: String, +idx: Nat) -> String:
  emoji_glyph.of(emoji_matches(80n, Emoji.aliases(), pre), idx)

def emoji_row(first: Bool, +e: Emoji.Entry) -> String:
  menu_mark(first) ++ emoji_text(e) ++ "  " ++ emoji_name(e)

def emoji_take(fuel: Nat, xs: List<&2, Emoji.Entry>, +at: Nat, +selected: Nat) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+h, t}: emoji_row(Nat.is_eq(at, selected), h) <> emoji_take(p, t, Nat.add(at, 1n), selected)

def emoji_page(+n: Nat, xs: List<&2, Emoji.Entry>, +idx: Nat) -> List<&2, String>:
  +at = pick_clamp(idx, n)
  +start = page_start(at)
  menu_more(Nat.is_gt(n, Nat.add(start, 8n)), emoji_take(8n, List.drop(&2, Emoji.Entry, xs, start), start, at))

def emoji_lines.ms(+ms: List<&2, Emoji.Entry>, +idx: Nat) -> List<&2, String>:
  emoji_page(List.length(&2, Emoji.Entry, ms), ms, idx)

def emoji_lines.pre(word: Maybe<&2, String>, +idx: Nat) -> List<&2, String>:
  match word:
    case None{}: Nil{}
    case Some{+pre}: emoji_lines.ms(emoji_matches(80n, Emoji.aliases(), pre), idx)

def emoji_lines(+s: String, +idx: Nat) -> List<&2, String>:
  emoji_lines.pre(emoji_prefix(s), idx)

# Match on the emoji list (a parameter) so menu_lines_at runs only when empty.
# Call with draft/idx — do not pre-evaluate both menus (Bool.pick / dual args are eager).
def emoji_or.pick(emoji: List<&2, String>, +draft: String, +idx: Nat) -> List<&2, String>:
  match emoji:
    case Nil{}: menu_lines_at(draft, idx)
    case _: emoji

def emoji_or(+draft: String, +idx: Nat) -> List<&2, String>:
  emoji_or.pick(emoji_lines(draft, idx), draft, idx)

def emoji_ghost.drop(empty: Bool, +name: String, +pre: String) -> String:
  match empty:
    case True{}: ""
    case False{}: String.drop(name, String.length(":" ++ pre))

def emoji_ghost.ms(+ms: List<&2, Emoji.Entry>, +pre: String, +idx: Nat) -> String:
  +n = List.length(&2, Emoji.Entry, ms)
  # Empty probe keeps the unclamped idx (out-of-range → no ghost); the
  # suffix still reads the clamped selection when the probe hits.
  emoji_ghost.drop(
    String.is_empty(emoji_name(emoji_at(ms, idx))),
    emoji_name(emoji_at(ms, pick_clamp(idx, n))),
    pre)

def emoji_ghost.pre(word: Maybe<&2, String>, +idx: Nat) -> String:
  match word:
    case None{}: ""
    case Some{+pre}: emoji_ghost.ms(emoji_matches(80n, Emoji.aliases(), pre), pre, idx)

def emoji_ghost(+s: String, +idx: Nat) -> String:
  emoji_ghost.pre(emoji_prefix(s), idx)

def emoji_insert(+draft: String, +pre: String, +glyph: String) -> String:
  +tok = ":" ++ pre
  String.take(draft, Nat.sub(String.length(draft), String.length(tok))) ++ glyph

def compose_accept.hit(empty: Bool, +glyph: String, +typed: String, +pre: String) -> String:
  match empty:
    case True{}: typed
    case False{}: emoji_insert(typed, pre, glyph)

def compose_accept.ms(+ms: List<&2, Emoji.Entry>, +typed: String, +pre: String, +idx: Nat) -> String:
  +glyph = emoji_glyph.of(ms, idx)
  compose_accept.hit(String.is_empty(glyph), glyph, typed, pre)

# Multi-match slash menus accept the selected verb (trailing space, like Tab
# CompActive). A unique match keeps the ghost finish (no forced space).
def slash_name_at(+xs: List<&2, String>, +idx: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, idx), "")

def slash_accept.many(+names: List<&2, String>, +idx: Nat) -> String:
  +n = List.length(&2, String, names)
  slash_name(slash_name_at(names, pick_clamp(idx, n))) ++ " "

def slash_accept.got(+typed: String, +word: String, +names: List<&2, String>, +idx: Nat, +n: Nat) -> String:
  match n:
    case 0n: typed
    case 1n: typed ++ ghost_one(word, slash_name_at(names, 0n))
    case _: slash_accept.many(names, idx)

def slash_accept(+typed: String, +word: String, +idx: Nat) -> String:
  +names = command_names(word)
  slash_accept.got(typed, word, names, idx, List.length(&2, String, names))

def compose_accept.slash(word: Maybe<&2, String>, +typed: String, +idx: Nat) -> String:
  match word:
    case None{}: typed
    case Some{+w}: slash_accept(typed, w, idx)

def compose_accept.pre(word: Maybe<&2, String>, +typed: String, +idx: Nat) -> String:
  match word:
    case None{}: compose_accept.slash(command_word(typed), typed, idx)
    case Some{+pre}: compose_accept.ms(emoji_matches(80n, Emoji.aliases(), pre), typed, pre, idx)

def compose_accept(+typed: String, +idx: Nat) -> String:
  compose_accept.pre(emoji_prefix(typed), typed, idx)

def ghost_at.on(empty: Bool, +slash: String, +typed: String, +idx: Nat) -> String:
  match empty:
    case True{}: emoji_ghost(typed, idx)
    case False{}: slash

def ghost_at(+typed: String, +idx: Nat) -> String:
  +slash = ghost_suffix(typed)
  ghost_at.on(String.is_empty(slash), slash, typed, idx)

# Tab accepts when a picker/ghost is ready; nick CompActive keeps cycling.
def tab_accept_ok(+typed: String, +idx: Nat) -> Bool:
  Bool.or(
    Nat.is_gt(emoji_len(typed), 0n),
    Bool.or(
      Nat.is_gt(menu_len(typed), 1n),
      Bool.not(String.is_empty(ghost_at(typed, idx)))))

def is_help.on(exact: Bool, +typed: String) -> Bool:
  match exact:
    case True{}: True{}
    case False{}: String.starts_with(typed, "/help ")

def is_help(+typed: String) -> Bool:
  is_help.on(String.eq(typed, "/help"), typed)

def help_arg.on(exact: Bool, +typed: String) -> String:
  match exact:
    case True{}: ""
    case False{}: Irc.drop_spaces(String.drop(typed, 6n))

def help_arg(+typed: String) -> String:
  help_arg.on(String.eq(typed, "/help"), typed)

def usage_line(+name: String) -> String:
  "/" ++ name ++ "  " ++ usage(name)

def catalog_lines(fuel: Nat, xs: List<&2, Sub.SlashRow>) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+h, t}: usage_line(row_name(h)) <> catalog_lines(p, t)

def take_lines(fuel: Nat, xs: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: Nil{}
    case 1n+p:
      match xs:
        case Nil{}: Nil{}
        case Con{+h, t}: h <> take_lines(p, t)

def help_pick(hit: Bool, +name: String, +fallback: String) -> String:
  match hit:
    case True{}: usage_line(name)
    case False{}: fallback

def help_exact(fuel: Nat, xs: List<&2, Sub.SlashRow>, +topic: String) -> String:
  match fuel:
    case 0n: ""
    case 1n+p:
      match xs:
        case Nil{}: ""
        case Con{+h, t}: help_pick(Irc.ieq(row_name(h), topic), row_name(h), help_exact(p, t, topic))

def help_topic_lines.miss(empty: Bool, +line: String) -> List<&2, String>:
  match empty:
    case True{}: "no such command" <> Nil{}
    case False{}: line <> Nil{}

def help_topic_lines.on(empty: Bool, +topic: String, +limit: Nat) -> List<&2, String>:
  match empty:
    case True{}: take_lines(limit, catalog_lines(Sub.slash_fuel(), Sub.slash_rows()))
    case False{}: help_topic_lines.miss(String.is_empty(help_exact(Sub.slash_fuel(), Sub.slash_rows(), topic)), help_exact(Sub.slash_fuel(), Sub.slash_rows(), topic))

def help_topic_lines(+topic: String, +limit: Nat) -> List<&2, String>:
  help_topic_lines.on(String.is_empty(topic), topic, limit)

def help_lines(+topic: String, +limit: Nat) -> List<&2, String>:
  help_topic_lines(topic, limit)

def ghost_ok() -> Bool:
  String.eq(ghost_suffix("/j"), "oin")
    && String.eq(ghost_suffix("/me"), " ")
    && String.eq(ghost_suffix("/m"), "")
    && String.eq(ghost_suffix("/mu"), "te")
    && String.eq(ghost_suffix("/"), "")
    && String.eq(ghost_suffix("hello"), "")
    && String.eq(ghost_suffix("/join #a"), "")

def menu_second_ok(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+h, _}: String.starts_with(h, "  /join <#channel>") && String.contains(h, "Join a channel")
    case Nil{}: False{}

def menu_head_ok.go(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+h, t}:
      String.starts_with(h, "→ /help [command]") && String.contains(h, "Show commands") && menu_second_ok(t)
    case Nil{}: False{}

def menu_more_ok.go(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}:
      match t:
        case Nil{}: String.eq(h, "  ↓ more below")
        case _: menu_more_ok.go(t)

def menu_head_ok() -> Bool:
  menu_head_ok.go(menu_lines("/"))

def menu_unique_ok.go(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: True{}
    case _: False{}

def menu_unique_ok() -> Bool:
  menu_unique_ok.go(menu_lines("/j"))

def menu_many_ok.go(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{_, _}: True{}
    case Nil{}: False{}

def menu_many_ok() -> Bool:
  menu_many_ok.go(menu_lines("/m"))

def menu_sel_second(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, _}: String.starts_with(h, "→ /join <#channel>")

def menu_sel_ok.go(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}: Bool.not(String.starts_with(h, "→")) && menu_sel_second(t)

def menu_sel_ok() -> Bool:
  menu_sel_ok.go(menu_lines_at("/", 1n))

def emoji_line0(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, _}: h

def emoji_line1(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{_, t}:
      match t:
        case Nil{}: ""
        case Con{+h, _}: h

def emoji_head(xs: List<&2, String>) -> Bool:
  String.eq(emoji_line0(xs), "→ 🤣  :rofl:")

def emoji_second(xs: List<&2, String>) -> Bool:
  String.eq(emoji_line1(xs), "→ ⭐  :star:")

def emoji_ok() -> Bool:
  String.eq(emoji_commit(":rofl:"), "🤣")
    && String.eq(emoji_commit(":rolling-on-the-floor-laughing:"), "🤣")
    && String.eq(emoji_commit("hi :joy:"), "hi 🤣")
    && String.eq(emoji_commit(":rof"), ":rof")
    && String.eq(emoji_commit("http://x"), "http://x")
    && String.eq(ghost_at(":rof", 0n), "l:")
    && String.eq(compose_accept(":rof", 0n), "🤣")
    && String.eq(compose_accept(":s", 1n), "⭐")
    && tab_accept_ok(":rof", 0n)
    && emoji_head(emoji_lines(":rof", 0n))
    && emoji_second(emoji_lines(":s", 1n))

def menu_ok() -> Bool:
  menu_head_ok()
    && menu_unique_ok()
    && menu_many_ok()
    && menu_more_ok.go(menu_lines("/"))
    && menu_sel_ok()
    && String.eq(compose_accept("/j", 0n), "/join")
    && String.eq(compose_accept("/", 1n), "/join ")
    && tab_accept_ok("/j", 0n)
    && tab_accept_ok("/", 1n)
    && Bool.not(tab_accept_ok("hello", 0n))

def help_one_ok.go(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+h, Nil{}}: String.eq(h, "/join  /join <#channel>")
    case _: False{}

def help_one_ok() -> Bool:
  help_one_ok.go(help_lines("join", 4n))

def help_miss_ok.go(xs: List<&2, String>) -> Bool:
  match xs:
    case Con{+h, Nil{}}: String.eq(h, "no such command")
    case _: False{}

def help_miss_ok() -> Bool:
  help_miss_ok.go(help_lines("nope", 4n))

def help_ok() -> Bool:
  is_help("/help")
    && is_help("/help join")
    && Bool.not(is_help("/helpjoin"))
    && String.eq(help_arg("/help join"), "join")
    && help_one_ok()
    && help_miss_ok()
