# SPDX-License-Identifier: Apache-2.0
# One bounded helper call. Consent, scope and URL validation stay in Upload.
import Base
import ./helper_io.bend as H

def spec() -> H.Spec:
  H.Spec{"BIRC_UPLOAD_HELPER", "birc-upload", 2048, 35000}

def program.env(result: Result<&1, &1, U32 & String, String>) -> String:
  H.name_got(result, "birc-upload")

def program() -> IO(String):
  H.name(spec())

def result.exit(code: U32, output: String) -> String & U32:
  match code:
    case 0: (output, 0)
    case _: ("", code)

def HTTP_PREFIX() -> String:
  "birc-upload: failed (code:5, http:"

def http_rejection(+status: U32) -> Bool:
  U32.is_ge(status, 100) && U32.is_le(status, 599) && Bool.not(U32.is_eq(status, 200))

def http_status.read(got: Maybe<&2, U32>, +code: U32, +stderr: String) -> U32:
  match got:
    case None{}: 0
    case Some{+status}:
      Bool.pick(U32, U32.is_eq(code, 5) && http_rejection(status)
        && String.eq(stderr, HTTP_PREFIX() ++ U32.show(status) ++ ")\n"), status, 0)

# Admit only the exact canonical three-digit envelope. No body, reason phrase,
# path, escape sequence, suffix, or OS error can enter this numeric channel.
def http_status(+code: U32, +stderr: String) -> U32:
  http_status.read(U32.read(String.take(String.drop(stderr, String.length(HTTP_PREFIX())), 3n)), code, stderr)

def result_detail.exit(+code: U32, output: String, stderr: String) -> String & U32 & U32:
  match code:
    case 0: (output, 0, 0)
    case _: ("", code, http_status(code, stderr))

def result_detail(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String & U32 & U32:
  match got:
    case Fail{(+code, _)}: ("", H.spawn_code(code), 0)
    case Done{(code, (out, stderr))}: result_detail.exit(code, out, stderr)

def result.compat(got: String & U32 & U32) -> String & U32:
  match got:
    case (output, code, _): (output, code)

# Legacy callers retain the output/code API and never receive helper stderr.
def result(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String & U32:
  result.compat(result_detail(got))

def error_text.http(known: Bool, code: U32, status: U32) -> String:
  match known:
    case False{}: "upload failed (code: " ++ U32.show(code) ++ ")"
    case True{}: "upload failed (HTTP " ++ U32.show(status) ++ "; code: " ++ U32.show(code) ++ ")"

def error_text(+code: U32, +status: U32) -> String:
  match code:
    case 0: "upload returned an invalid URL"
    case _: error_text.http(U32.is_eq(code, 5) && http_rejection(status), code, status)

def run_detail(path: String) -> IO(String & U32 & U32):
  do IO<String & U32 & U32>:
    got : Result<&1, &1, U32 & String, U32 & (String & String)> <- H.run(spec(), ["--local", path], "")
    return result_detail(got)

def run(path: String) -> IO(String & U32):
  do IO<String & U32>:
    got : String & U32 & U32 <- run_detail(path)
    return result.compat(got)
