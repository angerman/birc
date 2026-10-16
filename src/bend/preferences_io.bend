# SPDX-License-Identifier: Apache-2.0
# Literal bounded preference IO. Never copy helper/OS diagnostics into a buffer.
import Base
import ./preferences.bend as P
import ./helper_io.bend as H

def spec(+out_cap: U32) -> H.Spec:
  H.Spec{"BIRC_PREFS_HELPER", "birc-preferences", out_cap, 5000}

def program.env(got: Result<&1, &1, U32 & String, String>) -> String:
  H.name_got(got, "birc-preferences")

def program() -> IO(String):
  H.name(spec(P.MAX_WIRE()))

def load_result.parsed(got: Maybe<&2, P.Preferences>) -> Maybe<&2, P.Preferences> & U32:
  match got:
    case None{}: (None{}, 2)
    case Some{prefs}: (Some{prefs}, 0)

def load_result.output(empty: Bool, output: String) -> Maybe<&2, P.Preferences> & U32:
  match empty:
    case True{}: (None{}, 0)
    case False{}: load_result.parsed(P.parse(output))

def load_result.exit(code: U32, +output: String) -> Maybe<&2, P.Preferences> & U32:
  match code:
    case 0: load_result.output(String.is_empty(output), output)
    case _: (None{}, code)

def load_result(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Maybe<&2, P.Preferences> & U32:
  match got:
    case Fail{(+code, _)}: (None{}, H.spawn_code(code))
    case Done{(code, (out, _))}: load_result.exit(code, out)

def load(host: String, port: U32) -> IO(Maybe<&2, P.Preferences> & U32):
  do IO<Maybe<&2, P.Preferences> & U32>:
    got : Result<&1, &1, U32 & String, U32 & (String & String)> <- H.run(spec(P.MAX_WIRE()), ["read", host, U32.show(port)], "")
    return load_result(got)

def save_result.exit(code: U32, out: String, err: String) -> U32:
  match code:
    case 0: Bool.pick(U32, String.is_empty(out) && String.is_empty(err), 0, 2)
    case _: code

def save_result(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> U32:
  match got:
    case Fail{(+code, _)}: H.spawn_code(code)
    case Done{(code, (out, err))}: save_result.exit(code, out, err)

def save.serialized(host: String, port: U32, got: Maybe<&2, String>) -> IO(U32):
  match got:
    case None{}: IO.pure(U32, 2)
    case Some{body}:
      do IO<U32>:
        result : Result<&1, &1, U32 & String, U32 & (String & String)> <- H.run(spec(4096), ["write", host, U32.show(port)], body)
        return save_result(result)

def save(host: String, port: U32, prefs: P.Preferences) -> IO(U32):
  save.serialized(host, port, P.serialize(prefs))
