# SPDX-License-Identifier: Apache-2.0
# Bounded desktop-notification delivery through an explicit helper program.
# Unconfigured (no BIRC_NOTIFY_HELPER) sends nothing and reports nothing:
# notifications are opt-in until a default helper is provisioned. Unknown
# helper names fail closed without spawning. Helper output is never copied
# into diagnostics; only the safe stage label and numeric code are kept.
import Base
import ./notify.bend as Notify
import ./diagnostic.bend as Diagnostic

def program.env(got: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match got:
    case Fail{_}: None{}
    case Done{+value}: Bool.pick(Maybe<&2, String>, String.is_empty(value), None{}, Some{value})

def program() -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    got : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_NOTIFY_HELPER")
    return program.env(got)

def ends_with(+s: String, +suffix: String) -> Bool:
  String.starts_with(String.reverse(s), String.reverse(suffix))

# AppleScript string escaping: backslash and double quote only.
def esc.go(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{92}, t}: SCon{Chr{92}, SCon{Chr{92}, esc.go(t)}}
    case SCon{Chr{34}, t}: SCon{Chr{92}, SCon{Chr{34}, esc.go(t)}}
    case SCon{h, t}: SCon{h, esc.go(t)}

def quote(+s: String) -> String:
  SCon{Chr{34}, ""} ++ s ++ SCon{Chr{34}, ""}

def script(+title: String, +body: String) -> String:
  "display notification " ++ quote(esc.go(body)) ++ " with title " ++ quote(esc.go(title))

def args_for.kind(+req: Notify.Req, send: Bool, osa: Bool) -> List<&1, String>:
  match send:
    case True{}: Notify.req_title(req) <> Notify.req_body(req) <> Nil{}
    case False{}:
      match osa:
        case True{}: "-e" <> script(Notify.req_title(req), Notify.req_body(req)) <> Nil{}
        case False{}: Nil{}

def args_for(+program: String, +req: Notify.Req) -> List<&1, String>:
  args_for.kind(req, ends_with(program, "notify-send"), ends_with(program, "osascript"))

def send_result(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Maybe<&2, String>:
  Diagnostic.process_result("notify", got)

def send.run(+program: String, args: List<&1, String>) -> IO(Maybe<&2, String>):
  match args:
    case Nil{}: IO.pure(Maybe<&2, String>, Some{"notify failed (unknown helper)"})
    case Con{h, t}:
      do IO<Maybe<&2, String>>:
        got : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(program, h <> t, "", 512, 2000)
        return send_result(got)

def send.with(+program: Maybe<&2, String>, +req: Notify.Req) -> IO(Maybe<&2, String>):
  match program:
    case None{}: IO.pure(Maybe<&2, String>, None{})
    case Some{+helper}: send.run(helper, args_for(helper, req))

def send(+req: Notify.Req) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    helper : Maybe<&2, String> <- program()
    send.with(helper, req)
