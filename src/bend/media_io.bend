# SPDX-License-Identifier: Apache-2.0
# Image helper IO. Decode and fetch are the native FFI; a helper process
# remains only when BIRC_MEDIA_HELPER names one.
import Base
import ./helper_io.bend as H
import ./links.bend as Links

def spec() -> H.Spec:
  H.Spec{"BIRC_MEDIA_HELPER", "native", 2800000, 11000}

def args.pick(remote: Bool, source: String) -> List<&1, String>:
  match remote:
    case True{}: [source]
    case False{}: ["--local", source]

def args(+source: String) -> List<&1, String>:
  args.pick(Links.is_url_prefix(source), source)

law media_load:
  U32 -> String -> IO(U32 & String)

def media_load(local, source):
  import "../ffi/media_fetch_ffi.c"
  import "../ffi/media_fetch_ffi.js"

law cards_load:
  U32 -> String -> IO(U32 & String)

def cards_load(local, source):
  import "../ffi/media_fetch_ffi.c"
  import "../ffi/media_fetch_ffi.js"

def payload_exit(code: U32, +out: String) -> String:
  Bool.pick(String, U32.is_zero(code), out, "")

def payload_pair(pair: U32 & String) -> String:
  match pair:
    case (+code, +out): payload_exit(code, out)

def payload(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Fail{_}: ""
    case Done{(code, (out, _))}: payload_exit(code, out)

def run.native.local(remote: Bool, +source: String) -> IO(String):
  match remote:
    case True{}:
      do IO<String>:
        pair : U32 & String <- media_load(0, source)
        return payload_pair(pair)
    case False{}:
      do IO<String>:
        pair : U32 & String <- media_load(1, source)
        return payload_pair(pair)

def run.native(+source: String) -> IO(String):
  run.native.local(Links.is_url_prefix(source), source)

def run.helper(+source: String) -> IO(String):
  do IO<String>:
    result : Result<&1, &1, U32 & String, U32 & (String & String)> <- H.run(spec(), args(source), "")
    return payload(result)

def run.choose(native: Bool, +source: String) -> IO(String):
  match native:
    case True{}: run.native(source)
    case False{}: run.helper(source)

def run(+source: String) -> IO(String):
  do IO<String>:
    helper : String <- H.name(spec())
    run.choose(String.eq(helper, "native"), source)
