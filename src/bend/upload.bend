# SPDX-License-Identifier: Apache-2.0
# Public-upload consent and worker ownership. No filesystem, shell, or IO.
import Base
import ./irc.bend as Irc
import ./frame.bend as Fr

type Scope is Data:
  Scope{host: String, port: U32, target: String}

type Request is Data:
  Request{scope: Scope, path: String}

type State is Data:
  Idle{}
  Confirm{request: Request, remaining: List<&2, String>}
  Ready{request: Request, remaining: List<&2, String>}
  Busy{request: Request, remaining: List<&2, String>, allowed: Bool}

def empty() -> State:
  Idle{}

def active(state: State) -> Bool:
  match state:
    case Idle{}: False{}
    case _: True{}

def pending(state: State) -> Bool:
  match state:
    case Confirm{_, _}: True{}
    case Ready{_, _}: True{}
    case _: False{}

def CAP() -> Nat:
  8n

def PATH_BYTES() -> Nat:
  1024n

def printable(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}:
      U32.is_ge(Char.to_u32(h), 32) && Bool.not(U32.is_ge(Char.to_u32(h), 127) && U32.is_le(Char.to_u32(h), 159)) && printable(t)

def push_word(present: Bool, word: String, words: List<&2, String>) -> List<&2, String>:
  match present:
    case False{}: words
    case True{}: String.reverse(word) <> words

type Lex is Data:
  Lex{rest: String, quote: U32, escape: Bool, word: String, words: List<&2, String>, present: Bool}

def lex_quote.open(open: Bool, +same: Bool, h: Char, rest: String, quote: U32, mark: U32, +word: String, words: List<&2, String>) -> Lex:
  match open:
    case True{}: Lex{rest, mark, False{}, word, words, True{}}
    case False{}: Lex{rest, Bool.pick(U32, same, 0, quote), False{}, Bool.pick(String, same, word, SCon{h, word}), words, True{}}

def lex_quote(+quote: U32, +mark: U32, h: Char, rest: String, word: String, words: List<&2, String>) -> Lex:
  lex_quote.open(U32.is_zero(quote), U32.is_eq(quote, mark), h, rest, quote, mark, word, words)

def lex_space(quote: U32, rest: String, +word: String, +words: List<&2, String>, present: Bool) -> Lex:
  match quote:
    case 0: Lex{rest, 0, False{}, "", push_word(present, word, words), False{}}
    case _: Lex{rest, quote, False{}, SCon{Chr{32}, word}, words, True{}}

def lex_backslash(quote: U32, rest: String, word: String, words: List<&2, String>) -> Lex:
  match quote:
    case 39: Lex{rest, quote, False{}, SCon{Chr{92}, word}, words, True{}}
    case _: Lex{rest, quote, True{}, word, words, True{}}

# Quotes and backslashes decode literal terminal path text only. There is no
# glob, variable, tilde, command substitution, or shell execution.
def lex_plain(h: Char, rest: String, quote: U32, word: String, words: List<&2, String>, present: Bool) -> Lex:
  match h:
    case Chr{32}: lex_space(quote, rest, word, words, present)
    case Chr{39}: lex_quote(quote, 39, Chr{39}, rest, word, words)
    case Chr{34}: lex_quote(quote, 34, Chr{34}, rest, word, words)
    case Chr{92}: lex_backslash(quote, rest, word, words)
    case _: Lex{rest, quote, False{}, SCon{h, word}, words, True{}}

def lex_escaped(+h: Char, rest: String, +quote: U32, +word: String, words: List<&2, String>) -> Lex:
  +n = Char.to_u32(h)
  +keep = U32.is_eq(quote, 34) && Bool.not(U32.is_eq(n, 34) || U32.is_eq(n, 92) || U32.is_eq(n, 36) || U32.is_eq(n, 96))
  Lex{rest, quote, False{}, SCon{h, Bool.pick(String, keep, SCon{Chr{92}, word}, word)}, words, True{}}

def lex_char(escape: Bool, h: Char, rest: String, quote: U32, word: String, words: List<&2, String>, present: Bool) -> Lex:
  match escape:
    case True{}: lex_escaped(h, rest, quote, word, words)
    case False{}: lex_plain(h, rest, quote, word, words, present)

def lex_end(valid: Bool, word: String, words: List<&2, String>, present: Bool) -> Maybe<&2, List<&2, String>>:
  match valid:
    case False{}: None{}
    case True{}: Some{List.reverse(&2, String, push_word(present, word, words))}

def lex_go(fuel: Nat, st: Lex) -> Maybe<&2, List<&2, String>>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      match st:
        case Lex{rest, +quote, escape, word, words, present}:
          match rest:
            case SNil{}: lex_end(U32.is_zero(quote) && Bool.not(escape), word, words, present)
            case SCon{h, t}: lex_go(p, lex_char(escape, h, t, quote, word, words, present))

def hex.low(+n: U32, lower: Bool) -> Maybe<&2, U32>:
  match lower:
    case True{}: Some{U32.sub(n, 87)}
    case False{}: None{}

def hex.upper(+n: U32, upper: Bool) -> Maybe<&2, U32>:
  match upper:
    case True{}: Some{U32.sub(n, 55)}
    case False{}: hex.low(n, U32.is_ge(n, 97) && U32.is_le(n, 102))

def hex.digit(+n: U32, digit: Bool) -> Maybe<&2, U32>:
  match digit:
    case True{}: Some{U32.sub(n, 48)}
    case False{}: hex.upper(n, U32.is_ge(n, 65) && U32.is_le(n, 70))

def hex(+h: Char) -> Maybe<&2, U32>:
  +n = Char.to_u32(h)
  hex.digit(n, U32.is_ge(n, 48) && U32.is_le(n, 57))

def percent_pair(a: Char, b: Char) -> Maybe<&2, U32>:
  do Maybe<&2, U32>:
    x : U32 <- hex(a)
    y : U32 <- hex(b)
    return U32.add(U32.mul(x, 16), y)

def percent_go(fuel: Nat, raw: String) -> Maybe<&2, List<&2, U32>>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      match raw:
        case SNil{}: Some{Nil{}}
        case SCon{Chr{37}, SCon{a, SCon{b, t}}}:
          do Maybe<&2, List<&2, U32>>:
            byte : U32 <- percent_pair(a, b)
            rest : List<&2, U32> <- percent_go(p, t)
            return byte <> rest
        case SCon{Chr{37}, _}: None{}
        case SCon{+h, t}:
          do Maybe<&2, List<&2, U32>>:
            rest : List<&2, U32> <- percent_go(p, t)
            return Fr.utf8_encode_scalar(Char.to_u32(h), rest)

def local_path.valid(valid: Bool, path: String) -> Maybe<&2, String>:
  match valid:
    case False{}: None{}
    case True{}: Some{path}

def path_valid(+path: String, absolute: Bool) -> Bool:
  Bool.not(String.is_empty(path)) && printable(path) && Nat.is_le(Irc.utf8_len(path), PATH_BYTES())
    && (Bool.not(absolute) || String.starts_with(path, "/"))
    && Bool.not(String.contains(path, "://"))

def local_path.decoded(got: Maybe<&2, String>) -> Maybe<&2, String>:
  match got:
    case None{}: None{}
    case Some{+path}: local_path.valid(path_valid(path, True{}), path)

def local_path.uri(valid: Bool, +raw: String) -> Maybe<&2, String>:
  match valid:
    case False{}: None{}
    case True{}:
      do Maybe<&2, String>:
        bytes : List<&2, U32> <- percent_go(Nat.add(1n, String.length(raw)), raw)
        local_path.decoded(Fr.utf8_decode(bytes))

def local_path(+word: String, absolute: Bool) -> Maybe<&2, String>:
  match word:
    case SCon{Chr{102}, SCon{Chr{105}, SCon{Chr{108}, SCon{Chr{101}, SCon{Chr{58}, SCon{Chr{47}, SCon{Chr{47}, +raw}}}}}}}:
      local_path.uri(String.starts_with(raw, "/") && Bool.not(String.contains(raw, "?") || String.contains(raw, "#")), raw)
    case _: local_path.valid(path_valid(word, absolute), word)

def decode_paths(words: List<&2, String>, +absolute: Bool) -> Maybe<&2, List<&2, String>>:
  match words:
    case Nil{}: Some{Nil{}}
    case Con{word, t}:
      do Maybe<&2, List<&2, String>>:
        path : String <- local_path(word, absolute)
        rest : List<&2, String> <- decode_paths(t, absolute)
        return path <> rest

def parse_paths.words(got: Maybe<&2, List<&2, String>>, absolute: Bool) -> Maybe<&2, List<&2, String>>:
  match got:
    case None{}: None{}
    case Some{+words}:
      +local = Nat.is_gt(List.length(&2, String, words), 0n) && Nat.is_le(List.length(&2, String, words), CAP())
      Maybe.bind(&2, Unit, List<&2, String>, Bool.pick(Maybe<&2, Unit>, local, Some{Unit{}}, None{}), _ => decode_paths(words, absolute))

def parse_paths.bounded(valid: Bool, +raw: String, absolute: Bool) -> Maybe<&2, List<&2, String>>:
  match valid:
    case False{}: None{}
    case True{}: parse_paths.words(lex_go(Nat.add(1n, String.length(raw)), Lex{raw, 0, False{}, "", Nil{}, False{}}), absolute)

def parse_paths(+raw: String, absolute: Bool) -> Maybe<&2, List<&2, String>>:
  parse_paths.bounded(printable(raw) && Nat.is_le(Irc.utf8_len(raw), Nat.mul(4n, Nat.mul(CAP(), PATH_BYTES()))), raw, absolute)

def looks_local_drop.word(+word: String) -> Bool:
  String.starts_with(word, "/") || Irc.ieq(String.take(word, 7n), "file://")

def looks_local_drop.first(words: List<&2, String>, next: Unit -> Bool) -> Bool:
  match words:
    case Con{SCon{h, t}, _}: looks_local_drop.word(SCon{h, t})
    case _: next(Unit{})

# Reuse literal path lexing so failed URI decoding cannot hide behind quotes
# or escapes. Inspect only the first nonempty word, including malformed EOF;
# empty quoted prefixes are not prose. Never expand text or scan later prose.
def looks_local_drop.go(fuel: Nat, st: Lex) -> Bool:
  match fuel:
    case 0n: False{}
    case 1n+p:
      match st:
        case Lex{rest, quote, escape, word, words, present}:
          match rest:
            case SNil{}: looks_local_drop.first(words, _ => looks_local_drop.word(String.reverse(word)))
            case SCon{h, t}: looks_local_drop.first(words, _ => looks_local_drop.go(p, lex_char(escape, h, t, quote, word, Nil{}, present)))

def looks_local_drop(+raw: String) -> Bool:
  looks_local_drop.go(Nat.add(1n, String.length(raw)), Lex{raw, 0, False{}, "", Nil{}, False{}})

def scope_eq(a: Scope, b: Scope) -> Bool:
  match a:
    case Scope{host, port, target}:
      match b:
        case Scope{h, p, t}: String.eq(host, h) && U32.is_eq(port, p) && String.eq(target, t)

def scope_valid(scope: Scope) -> Bool:
  match scope:
    case Scope{+host, +port, +target}:
      Bool.not(String.is_empty(host) || String.is_empty(target) || String.starts_with(target, "*"))
        && printable(host) && printable(target) && Bool.not(String.contains(target, " ") || String.contains(target, ",") || String.starts_with(target, ":"))
        && U32.is_gt(port, 0) && U32.is_le(port, 65535)

def request_eq(a: Request, b: Request) -> Bool:
  match a:
    case Request{scope, path}:
      match b:
        case Request{s, p}: scope_eq(scope, s) && String.eq(path, p)

def request_scope(request: Request) -> Scope:
  match request:
    case Request{scope, _}: scope

def request_path(request: Request) -> String:
  match request:
    case Request{_, path}: path

def paths_valid(paths: List<&2, String>) -> Bool:
  match paths:
    case Nil{}: True{}
    case Con{+path, t}: path_valid(path, False{}) && paths_valid(t)

def offer.valid(valid: Bool, scope: Scope, paths: List<&2, String>) -> State:
  match valid:
    case False{}: Idle{}
    case True{}:
      match paths:
        case Nil{}: Idle{}
        case Con{path, remaining}: Confirm{Request{scope, path}, remaining}

def offer(state: State, +scope: Scope, online: Bool, +paths: List<&2, String>) -> State:
  match state:
    case Idle{}: offer.valid(online && scope_valid(scope) && paths_valid(paths) && Nat.is_le(List.length(&2, String, paths), CAP()), scope, paths)
    case _: state

def retain.valid(valid: Bool, state: State) -> State:
  match valid:
    case True{}: state
    case False{}:
      match state:
        case Busy{request, _, _}: Busy{request, Nil{}, False{}}
        case _: Idle{}

# Invalidating a running request never drops physical worker ownership. The
# flag is monotonic, so leaving and later returning to a scope cannot send.
def retain(+state: State, +scope: Scope, +online: Bool) -> State:
  match state:
    case Idle{}: Idle{}
    case Confirm{+request, _}: retain.valid(online && scope_eq(request_scope(request), scope), state)
    case Ready{+request, _}: retain.valid(online && scope_eq(request_scope(request), scope), state)
    case Busy{+request, _, _}: retain.valid(online && scope_eq(request_scope(request), scope), state)

def confirm.retained(state: State) -> State:
  match state:
    case Confirm{request, remaining}: Ready{request, remaining}
    case _: state

# The caller supplies a dedicated physical-key action, never pasted text.
def confirm(state: State, scope: Scope, online: Bool) -> State:
  confirm.retained(retain(state, scope, online))

def cancel(state: State) -> State:
  match state:
    case Busy{request, _, _}: Busy{request, Nil{}, False{}}
    case _: Idle{}

def take_job(state: State) -> State & Maybe<&2, Request>:
  match state:
    case Ready{+request, remaining}: (Busy{request, remaining, True{}}, Some{request})
    case _: (state, None{})

def ascii_path(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{+h, t}:
      +n = Char.to_u32(h)
      ((U32.is_ge(n, 48) && U32.is_le(n, 57)) || (U32.is_ge(n, 65) && U32.is_le(n, 90))
        || (U32.is_ge(n, 97) && U32.is_le(n, 122)) || U32.is_eq(n, 46) || U32.is_eq(n, 95)
        || U32.is_eq(n, 126) || U32.is_eq(n, 47) || U32.is_eq(n, 45)) && ascii_path(t)

def segments_valid(parts: List<&2, String>) -> Bool:
  match parts:
    case Nil{}: True{}
    case Con{+part, t}: Bool.not(String.is_empty(part) || String.eq(part, ".") || String.eq(part, "..")) && segments_valid(t)

def response_url(+url: String) -> Bool:
  +path = String.drop(url, 15n)
  String.starts_with(url, "https://0x0.st/") && Nat.is_le(String.length(url), 1024n)
    && Bool.not(String.is_empty(path)) && ascii_path(path) && segments_valid(String.split(path, Chr{47}))

def response.valid(valid: Bool, url: String) -> Maybe<&2, String>:
  match valid:
    case False{}: None{}
    case True{}: Some{url}

def response(+output: String) -> Maybe<&2, String>:
  +url = String.take(output, Nat.sub(String.length(output), 1n))
  response.valid(String.eq(output, url ++ "\n") && response_url(url), url)

def wire_fits(request: Request, +url: String) -> Bool:
  match request:
    case Request{+scope, _}:
      match scope:
        case Scope{_, _, target}:
          scope_valid(scope) && response_url(url) && Irc.line_ok(Irc.format_privmsg(target, url))

def eligible(state: State, +request: Request, +scope: Scope, online: Bool) -> Bool:
  match state:
    case Busy{active, _, allowed}: allowed && online && request_eq(active, request) && scope_eq(request_scope(request), scope)
    case _: False{}

def next(allowed: Bool, scope: Scope, remaining: List<&2, String>) -> State:
  match allowed:
    case False{}: Idle{}
    case True{}:
      match remaining:
        case Nil{}: Idle{}
        case Con{path, tail}: Confirm{Request{scope, path}, tail}

def finish.hit(hit: Bool, +allowed: Bool, state: State, scope: Scope, remaining: List<&2, String>, output: String) -> State & Maybe<&2, String>:
  match hit:
    case False{}: (state, None{})
    case True{}: (next(allowed, scope, remaining), Bool.pick(Maybe<&2, String>, allowed, response(output), None{}))

def finish.retained(+state: State, +request: Request, +scope: Scope, online: Bool, output: String) -> State & Maybe<&2, String>:
  match state:
    case Busy{active, remaining, _}:
      finish.hit(request_eq(active, request), eligible(state, request, scope, online), state, scope, remaining, output)
    case _: (state, None{})

def finish(state: State, request: Request, +scope: Scope, +online: Bool, output: String) -> State & Maybe<&2, String>:
  finish.retained(retain(state, scope, online), request, scope, online, output)

# Small pure inspectors keep consent/ownership contracts available to LAWS.
def has_job(pair: State & Maybe<&2, Request>) -> Bool:
  match pair:
    case (_, None{}): False{}
    case (_, Some{_}): True{}

def job_state(pair: State & Maybe<&2, Request>) -> State:
  match pair:
    case (state, _): state

def result_absent(pair: State & Maybe<&2, String>) -> Bool:
  match pair:
    case (_, None{}): True{}
    case (_, Some{_}): False{}

def finished_state(pair: State & Maybe<&2, String>) -> State:
  match pair:
    case (state, _): state

def sample_scope() -> Scope:
  Scope{"irc.example", 6667, "+#room"}

def sample_request() -> Request:
  Request{sample_scope(), "/fixture/file.txt"}

def sample_pending() -> State:
  offer(empty(), sample_scope(), True{}, ["/fixture/file.txt"])

def sample_busy() -> State:
  job_state(take_job(confirm(sample_pending(), sample_scope(), True{})))

def consent_ok() -> Bool:
  Bool.not(has_job(take_job(sample_pending())))
    && has_job(take_job(confirm(sample_pending(), sample_scope(), True{})))
    && Bool.not(has_job(take_job(confirm(sample_pending(), sample_scope(), False{}))))

def one_shot_ok() -> Bool:
  Bool.not(has_job(take_job(sample_busy())))
    && Bool.not(has_job(take_job(confirm(sample_busy(), sample_scope(), True{}))))

def cancel_ok() -> Bool:
  +stopped = cancel(sample_busy())
  Bool.not(has_job(take_job(cancel(sample_pending())))) && active(stopped)
    && result_absent(finish(stopped, sample_request(), sample_scope(), True{}, "https://0x0.st/file.txt\n"))
    && Bool.not(active(finished_state(finish(stopped, sample_request(), sample_scope(), True{}, "https://0x0.st/file.txt\n"))))
