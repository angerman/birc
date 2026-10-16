# SPDX-License-Identifier: Apache-2.0
# Pure IPv4/DNS HOST[:PORT] syntax shared by CLI and /connect. IPv6 is not
# supported. Keep host spelling/root dot for endpoint and credential identity.
import Base
import ./dns_wire.bend as Wire

type Endpoint is Data:
  Endpoint{host: String, port: Maybe<&2, U32>}

def MAX_INPUT() -> Nat:
  260n

def ascii_word(+c: U32) -> Bool:
  (U32.is_ge(c, 65) && U32.is_le(c, 90))
    || (U32.is_ge(c, 97) && U32.is_le(c, 122))
    || (U32.is_ge(c, 48) && U32.is_le(c, 57)) || U32.is_eq(c, 45)

def chars(s: String, +endpoint: Bool) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, t}:
      (ascii_word(c) || (endpoint && (U32.is_eq(c, 46) || U32.is_eq(c, 58)))) && chars(t, endpoint)

def labels(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{+h, t}:
      Nat.is_ge(String.length(h), 1n) && Nat.is_le(String.length(h), 63n)
        && chars(h, False{}) && labels(t)

def host_ok(+host: String) -> Bool:
  +clean = Wire.without_root_dot(host)
  Nat.is_ge(String.length(clean), 1n) && Nat.is_le(String.length(clean), 253n)
    && labels(String.split(clean, Chr{46}))

# ASCII digits only. Shared by endpoint ports and ISUPPORT numeric tokens.
def decimal(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, t}:
      U32.is_ge(c, 48) && U32.is_le(c, 57) && decimal(t)

def port.range(n: U32, valid: Bool) -> Maybe<&2, U32>:
  match valid:
    case True{}: Some{n}
    case False{}: None{}

def port.read(got: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match got:
    case None{}: None{}
    case Some{+n}: port.range(n, U32.is_ge(n, 1) && U32.is_le(n, 65535))

def port.valid(+text: String, valid: Bool) -> Maybe<&2, U32>:
  match valid:
    case False{}: None{}
    case True{}: port.read(U32.read(text))

# Leading zeros remain valid, as with the existing numeric CLI flags.
def port(+text: String) -> Maybe<&2, U32>:
  port.valid(text, decimal(text))

def parse.host(valid: Bool, host: String, port: Maybe<&2, U32>) -> Result<&2, &2, String, Endpoint>:
  match valid:
    case False{}: Fail{"bad endpoint"}
    case True{}: Done{Endpoint{host, port}}

def parse.port(got: Maybe<&2, U32>, +host: String) -> Result<&2, &2, String, Endpoint>:
  match got:
    case None{}: Fail{"bad port"}
    case Some{n}: parse.host(host_ok(host), host, Some{n})

def parse.parts(parts: List<&2, String>) -> Result<&2, &2, String, Endpoint>:
  match parts:
    case Con{+host, Nil{}}: parse.host(host_ok(host), host, None{})
    case Con{+host, Con{text, Nil{}}}: parse.port(port(text), host)
    case _: Fail{"bad endpoint"}

def parse.valid(+text: String, valid: Bool) -> Result<&2, &2, String, Endpoint>:
  match valid:
    case False{}: Fail{"bad endpoint"}
    case True{}: parse.parts(String.split(text, Chr{58}))

# The shorthand cap covers 254 host bytes, ':', and five canonical port digits.
# Shorter hosts may use extra leading zeros within the same bound.
def parse(+text: String) -> Result<&2, &2, String, Endpoint>:
  parse.valid(text, Nat.is_le(String.length(text), MAX_INPUT()) && chars(text, True{}))

def select_port.same(same: Bool, port: U32) -> Maybe<&2, U32>:
  match same:
    case False{}: None{}
    case True{}: Some{port}

def select_port(inline: Maybe<&2, U32>, separate: Maybe<&2, U32>, fallback: U32) -> Maybe<&2, U32>:
  match inline:
    case None{}:
      match separate:
        case None{}: Some{fallback}
        case Some{n}: Some{n}
    case Some{+n}:
      match separate:
        case None{}: Some{n}
        case Some{m}: select_port.same(U32.is_eq(n, m), n)

def resolve.selected(selected: Maybe<&2, U32>, host: String) -> Maybe<&1, String & U32>:
  match selected:
    case None{}: None{}
    case Some{n}: Some{(host, n)}

def resolve(endpoint: Endpoint, separate: Maybe<&2, U32>, fallback: U32) -> Maybe<&1, String & U32>:
  match endpoint:
    case Endpoint{host, port}: resolve.selected(select_port(port, separate, fallback), host)

# History records and credentials both scope on this string. Keep host
# spelling and a terminal DNS root dot byte-for-byte: no case folding, no
# dot stripping. SNI normalization is a different step.
def endpoint(+host: String, +port: U32) -> String:
  host ++ ":" ++ U32.show(port)
