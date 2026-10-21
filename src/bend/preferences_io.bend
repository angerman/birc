# SPDX-License-Identifier: Apache-2.0
# Literal bounded preference IO. File admission is the native FFI; a helper
# process remains only when BIRC_PREFS_HELPER names one. Never copy helper
# or OS diagnostics into a buffer.
import Base
import ./preferences.bend as P
import ./helper_io.bend as H

def spec(+out_cap: U32) -> H.Spec:
  H.Spec{"BIRC_PREFS_HELPER", "native", out_cap, 5000}

def program.env(got: Result<&1, &1, U32 & String, String>) -> String:
  H.name_got(got, "native")

def program() -> IO(String):
  H.name(spec(P.MAX_WIRE()))

def resolve_prefs_path.home(home: Result<&1, &1, U32 & String, String>) -> String:
  match home:
    case Done{+h}: h ++ "/.config/birc/preferences.toml"
    case Fail{_}: ".config/birc/preferences.toml"

def resolve_prefs_path.xdg_empty(empty: Bool, +value: String, home: Result<&1, &1, U32 & String, String>) -> String:
  match empty:
    case True{}: resolve_prefs_path.home(home)
    case False{}: value ++ "/birc/preferences.toml"

def resolve_prefs_path.default(xdg: Result<&1, &1, U32 & String, String>, home: Result<&1, &1, U32 & String, String>) -> String:
  match xdg:
    case Done{+value}: resolve_prefs_path.xdg_empty(String.is_empty(value), value, home)
    case Fail{_}: resolve_prefs_path.home(home)

def resolve_prefs_path.env(b: Result<&1, &1, U32 & String, String>, xdg: Result<&1, &1, U32 & String, String>, home: Result<&1, &1, U32 & String, String>) -> String:
  match b:
    case Done{+val}:
      Bool.pick(String, String.eq(val, "none") || String.is_empty(val), "", val)
    case Fail{_}: resolve_prefs_path.default(xdg, home)

def resolve_prefs_path() -> IO(String):
  do IO<String>:
    b : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_PREFERENCES")
    xdg : Result<&1, &1, U32 & String, String> <- IO.get_env("XDG_CONFIG_HOME")
    home : Result<&1, &1, U32 & String, String> <- IO.get_env("HOME")
    return resolve_prefs_path.env(b, xdg, home)

law prefs_load:
  String -> String -> U32 -> IO(U32 & String)

def prefs_load(path, host, port):
  import "../ffi/preferences_ffi.c"
  import "../ffi/preferences_ffi.js"

law prefs_save:
  String -> String -> U32 -> String -> IO(U32)

def prefs_save(path, host, port, body):
  import "../ffi/preferences_ffi.c"
  import "../ffi/preferences_ffi.js"

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

def load_result.pair(pair: U32 & String) -> Maybe<&2, P.Preferences> & U32:
  match pair:
    case (+code, +out): load_result.exit(code, out)

def load.native.empty(empty: Bool, +path: String, +host: String, +port: U32) -> IO(Maybe<&2, P.Preferences> & U32):
  match empty:
    case True{}: IO.pure(Maybe<&2, P.Preferences> & U32, (None{}, 0))
    case False{}:
      do IO<Maybe<&2, P.Preferences> & U32>:
        pair : U32 & String <- prefs_load(path, host, port)
        return load_result.pair(pair)

def load.native.got(+path: String, +host: String, +port: U32) -> IO(Maybe<&2, P.Preferences> & U32):
  load.native.empty(String.is_empty(path), path, host, port)

def load.native(+host: String, +port: U32) -> IO(Maybe<&2, P.Preferences> & U32):
  do IO<Maybe<&2, P.Preferences> & U32>:
    path : String <- resolve_prefs_path()
    load.native.got(path, host, port)

def load.helper(+host: String, +port: U32) -> IO(Maybe<&2, P.Preferences> & U32):
  do IO<Maybe<&2, P.Preferences> & U32>:
    got : Result<&1, &1, U32 & String, U32 & (String & String)> <- H.run(spec(P.MAX_WIRE()), ["read", host, U32.show(port)], "")
    return load_result(got)

def load.choose(native: Bool, +host: String, +port: U32) -> IO(Maybe<&2, P.Preferences> & U32):
  match native:
    case True{}: load.native(host, port)
    case False{}: load.helper(host, port)

def load(host: String, port: U32) -> IO(Maybe<&2, P.Preferences> & U32):
  do IO<Maybe<&2, P.Preferences> & U32>:
    helper : String <- program()
    load.choose(String.eq(helper, "native"), host, port)

def save_result.exit(code: U32, out: String, err: String) -> U32:
  match code:
    case 0: Bool.pick(U32, String.is_empty(out) && String.is_empty(err), 0, 2)
    case _: code

def save_result(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> U32:
  match got:
    case Fail{(+code, _)}: H.spawn_code(code)
    case Done{(code, (out, err))}: save_result.exit(code, out, err)

def save.native.empty(empty: Bool, +path: String, +host: String, +port: U32, +body: String) -> IO(U32):
  match empty:
    case True{}: IO.pure(U32, 0)
    case False{}: prefs_save(path, host, port, body)

def save.native.got(+path: String, +host: String, +port: U32, +body: String) -> IO(U32):
  save.native.empty(String.is_empty(path), path, host, port, body)

def save.native(+host: String, +port: U32, +body: String) -> IO(U32):
  do IO<U32>:
    path : String <- resolve_prefs_path()
    save.native.got(path, host, port, body)

def save.helper(+host: String, +port: U32, +body: String) -> IO(U32):
  do IO<U32>:
    result : Result<&1, &1, U32 & String, U32 & (String & String)> <- H.run(spec(4096), ["write", host, U32.show(port)], body)
    return save_result(result)

def save.choose(native: Bool, +host: String, +port: U32, +body: String) -> IO(U32):
  match native:
    case True{}: save.native(host, port, body)
    case False{}: save.helper(host, port, body)

def save.serialized(host: String, port: U32, got: Maybe<&2, String>) -> IO(U32):
  match got:
    case None{}: IO.pure(U32, 2)
    case Some{body}:
      do IO<U32>:
        helper : String <- program()
        save.choose(String.eq(helper, "native"), host, port, body)

def save(host: String, port: U32, prefs: P.Preferences) -> IO(U32):
  save.serialized(host, port, P.serialize(prefs))
