# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/upload_io.bend as U

def shown(pair: String & U32 & U32) -> String:
  match pair:
    case (out, code, http): U32.show(code) ++ ":" ++ U32.show(http) ++ ":" ++ out

def envelope(+status: String) -> String:
  "birc-upload: failed (code:5, http:" ++ status ++ ")\n"

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("numeric HTTP rejection preserves code and drops both outputs", shown(U.result_detail(Done{(5, ("private stdout", envelope("403")))})), "5:403:")
    Unit <- E.must_eq("success ignores status-looking stderr", shown(U.result_detail(Done{(0, ("https://0x0.st/file.html\n", envelope("403")))})), "0:0:https://0x0.st/file.html\n")
    Unit <- E.must_eq("another error ignores status-looking stderr", shown(U.result_detail(Done{(4, ("private stdout", envelope("403")))})), "4:0:")
    Unit <- E.must_eq("OS failures never carry HTTP status", shown(U.result_detail(Fail{(5, envelope("403"))})), "5:0:")
    Unit <- E.must_eq("unknown status is discarded", shown(U.result_detail(Done{(5, ("", envelope("999")))})), "5:0:")
    Unit <- E.must_eq("successful status is not a rejection diagnostic", shown(U.result_detail(Done{(5, ("", envelope("200")))})), "5:0:")
    Unit <- E.must_eq("private suffix cannot cross the status channel", shown(U.result_detail(Done{(5, ("", envelope("403") ++ "private path body"))})), "5:0:")
    Unit <- E.must_eq("control bytes cannot cross the status channel", shown(U.result_detail(Done{(5, ("", envelope("403") ++ "\u{1b}[31m"))})), "5:0:")
    Unit <- E.must_eq("leading zero/noncanonical status is discarded", shown(U.result_detail(Done{(5, ("", envelope("0403")))})), "5:0:")
    Unit <- E.must_eq("leading private text is discarded", shown(U.result_detail(Done{(5, ("", "private body" ++ envelope("403")))})), "5:0:")
    Unit <- E.must_eq("valid HTTP status has fixed numeric display", U.error_text(5, 418), "upload failed (HTTP 418; code: 5)")
    Unit <- E.must_eq("unknown reply error stays generic", U.error_text(5, 0), "upload failed (code: 5)")
    Unit <- E.must_eq("wrong error cannot display HTTP metadata", U.error_text(4, 418), "upload failed (code: 4)")
    Unit <- E.must_eq("invalid success URL keeps established diagnostic", U.error_text(0, 403), "upload returned an invalid URL")
    IO.print("upload_diagnostics=ok")
