# Bounded, private copies for the internal diagnostic buffer. No IO or state.
import Base
import ./irc.bend as Irc
import ./links.bend as Links

def name() -> String:
  "*log*"

def ROW_CAP() -> Nat:
  128n

def TEXT_CAP() -> Nat:
  512n

def secret_length.hit(hit: Bool, secret: String) -> Nat:
  match hit:
    case False{}: 0n
    case True{}: String.length(secret)

def secret_length(+s: String, +secret: String) -> Nat:
  secret_length.hit(Bool.not(String.is_empty(secret)) && String.starts_with(s, secret), secret)

# Longest first: a user name can be a prefix of the password. Empty configured
# values must not match every cursor position.
def secret_skip(+s: String, user: String, pass: String) -> Nat:
  Nat.max(secret_length(s, user), secret_length(s, pass))

def token.char(s: String) -> String & String:
  match s:
    case SNil{}: ("", "")
    case SCon{h, t}: (SCon{h, ""}, t)

def token.secret(s: String, skip: Nat) -> String & String:
  match skip:
    case 0n: token.char(s)
    case 1n+p: ("[redacted]", String.drop(s, 1n+p))

def token.url(pair: String & String) -> String & String:
  match pair:
    case (_, tail): ("[url]", tail)

# Use the shared URL prefix/token rules, not clickable extraction: even opaque
# code and styled URLs are private here. Only the bounded prefix is tokenized;
# text farther beyond a long URL is deliberately omitted from its diagnostic.
def token.pick(url: Bool, +s: String, user: String, pass: String) -> String & String:
  match url:
    case True{}: token.url(Links.take(String.take(s, TEXT_CAP())))
    case False{}: token.secret(s, secret_skip(s, user, pass))

def token(+s: String, user: String, pass: String) -> String & String:
  token.pick(Links.is_url_prefix(String.to_lower(String.take(s, 8n))), s, user, pass)

def text.step(pair: String & String, next: String -> String) -> String:
  match pair:
    case (part, rest): part ++ next(rest)

def text.go(fuel: Nat, s: String, +user: String, +pass: String) -> String:
  match fuel:
    case 0n: ""
    case 1n+p:
      match s:
        case SNil{}: ""
        case SCon{h, t}:
          text.step(token(SCon{h, t}, user, pass), rest => text.go(p, rest, user, pass))

def text(msg: String, user: String, pass: String) -> String:
  String.take(text.go(TEXT_CAP(), Irc.sanitize_in(msg), Irc.sanitize_in(user), Irc.sanitize_in(pass)), TEXT_CAP())

def process_result.exit(ok: Bool, label: String, code: U32) -> Maybe<&2, String>:
  match ok:
    case True{}: None{}
    case False{}: Some{label ++ " failed (exit " ++ U32.show(code) ++ ")"}

# Never copy child output, stderr, or host error text: they can contain pasted
# text, private URLs, or credentials. Labels are caller-owned stage names.
def process_result(+label: String, result: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Maybe<&2, String>:
  match result:
    case Fail{(code, _)}: Some{label ++ " failed (OS " ++ U32.show(code) ++ ")"}
    case Done{(+code, _)}: process_result.exit(U32.is_eq(code, 0), label, code)
