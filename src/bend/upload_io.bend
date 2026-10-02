# SPDX-License-Identifier: Apache-2.0
# One bounded helper call. Consent, scope and URL validation stay in Upload.
import Base

def program.env(result: Result<&1, &1, U32 & String, String>) -> String:
  match result:
    case Fail{_}: "birc-upload"
    case Done{+value}: Bool.pick(String, String.is_empty(value), "birc-upload", value)

def program() -> IO(String):
  do IO<String>:
    result : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_UPLOAD_HELPER")
    return program.env(result)

def result.exit(code: U32, output: String) -> String & U32:
  match code:
    case 0: (output, 0)
    case _: ("", code)

# Never forward helper stderr or OS diagnostic text to the UI.
def result(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String & U32:
  match got:
    case Fail{(+code, _)}: ("", Bool.pick(U32, U32.is_zero(code), 1, code))
    case Done{(code, (out, _))}: result.exit(code, out)

def run(path: String) -> IO(String & U32):
  do IO<String & U32>:
    helper : String <- program()
    got : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(helper, ["--local", path], "", 2048, 35000)
    return result(got)
