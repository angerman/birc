# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/upload.bend as U

def paths(got: Maybe<&2, List<&2, String>>) -> String:
  match got:
    case None{}: "none"
    case Some{xs}: String.join(xs, "|")

def text(got: Maybe<&2, String>) -> String:
  match got:
    case None{}: "none"
    case Some{s}: s

def scope() -> U.Scope:
  U.Scope{"irc.example", 6667, "+#room"}

def req() -> U.Request:
  U.Request{scope(), "/tmp/a.txt"}

def offered() -> U.State:
  U.offer(U.empty(), scope(), True{}, ["/tmp/a.txt", "/tmp/b.png"])

def state_of(pair: U.State & Maybe<&2, U.Request>) -> U.State:
  match pair:
    case (state, _): state

def started() -> U.State:
  state_of(U.take_job(U.confirm(offered(), scope(), True{})))

def job(pair: U.State & Maybe<&2, U.Request>) -> String:
  match pair:
    case (_, None{}): "none"
    case (_, Some{U.Request{_, path}}): path

def result(pair: U.State & Maybe<&2, String>) -> String:
  match pair:
    case (_, got): text(got)

def completed(pair: U.State & Maybe<&2, String>) -> U.State:
  match pair:
    case (state, _): state

def phase(state: U.State) -> String:
  match state:
    case U.Idle{}: "idle"
    case U.Confirm{U.Request{_, path}, _}: "confirm:" ++ path
    case U.Ready{U.Request{_, path}, _}: "ready:" ++ path
    case U.Busy{_, _, allowed}: "busy:" ++ Bool.show(allowed)

def repeated(n: Nat, +part: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: part ++ repeated(p, part)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("quoted interruption retains malformed URI intent", U.looks_local_drop("fi''le:///tmp/private%FF.jpg"))
    Unit <- E.must("escaped interruption retains malformed URI intent", U.looks_local_drop("fi\\le:///tmp/private%FF.jpg"))
    Unit <- E.must("unclosed quote retains decoded firstword URI intent", U.looks_local_drop("fi'le:///tmp/private%FF.jpg"))
    Unit <- E.must("uppercase malformed URI remains local intent", U.looks_local_drop("FILE:///tmp/private%FF.jpg"))
    Unit <- E.must("empty quoted prefixes cannot hide path intent", U.looks_local_drop("'' /tmp/private\\"))
    Unit <- E.must("empty quoted prefix does not scan later prose path", Bool.not(U.looks_local_drop("'' ordinary /tmp/private")))
    Unit <- E.must_eq("quoted interruption valid URI is accepted", paths(U.parse_paths("fi''le:///tmp/%C3%A9.txt", True{})), "/tmp/é.txt")
    Unit <- E.must_eq("escaped interruption valid URI is accepted", paths(U.parse_paths("fi\\le:///tmp/%C3%A9.txt", True{})), "/tmp/é.txt")
    Unit <- E.must_eq("uppercase URI stays unsupported rather than decoded", paths(U.parse_paths("FILE:///tmp/a.txt", True{})), "none")
    Unit <- E.must("quoted ordinary firstword does not scan later path", Bool.not(U.looks_local_drop("or''dinary /tmp/private")))
    Unit <- E.must("malformed file URI keeps local-drop intent", U.looks_local_drop("file:///tmp/private%FF.jpg"))
    Unit <- E.must("absolute batch keeps local-drop intent", U.looks_local_drop("'/tmp/a' '/tmp/b'"))
    Unit <- E.must("unclosed absolute quote keeps local-drop intent", U.looks_local_drop("'/tmp/private"))
    Unit <- E.must("leading spaces and quoted URI keep local intent", U.looks_local_drop("  \"file:///tmp/%GG"))
    Unit <- E.must("escaped absolute prefix keeps local-drop intent", U.looks_local_drop("\\/tmp/private\\"))
    Unit <- E.must("concatenated empty quotes keep local-drop intent", U.looks_local_drop("''file:///tmp/private%FF"))
    Unit <- E.must("escaped URI prefix keeps local-drop intent", U.looks_local_drop("\\file:///tmp/private%FF"))
    Unit <- E.must("remote file authority still has file-drop intent", U.looks_local_drop("file://remote/tmp/private"))
    Unit <- E.must("later prose path is not drop intent", Bool.not(U.looks_local_drop("please read /tmp/private")))
    Unit <- E.must("HTTP URL is not drop intent", Bool.not(U.looks_local_drop("https://example.test/tmp/private")))
    Unit <- E.must("quoted prose is not drop intent", Bool.not(U.looks_local_drop("'ordinary text'")))
    Unit <- E.must_eq("prose is not a drop", paths(U.parse_paths("ordinary message", True{})), "none")
    Unit <- E.must_eq("exact absolute file drop", paths(U.parse_paths("/tmp/a.txt", True{})), "/tmp/a.txt")
    Unit <- E.must_eq("quoted Unicode and escaped spaces", paths(U.parse_paths("'/tmp/é a.png' /tmp/b\\ c.txt", True{})), "/tmp/é a.png|/tmp/b c.txt")
    Unit <- E.must_eq("double quotes and quote concatenation", paths(U.parse_paths("\"/tmp/a b\" '/tmp/a'\\''b'", True{})), "/tmp/a b|/tmp/a'b")
    Unit <- E.must_eq("double quoted ordinary backslash retained", paths(U.parse_paths("\"/tmp/a\\q\"", True{})), "/tmp/a\\q")
    Unit <- E.must_eq("empty quoted path rejected", paths(U.parse_paths("/tmp/a ''", True{})), "none")
    Unit <- E.must_eq("expansions stay literal", paths(U.parse_paths("'/tmp/$name;`cmd`'", True{})), "/tmp/$name;`cmd`")
    Unit <- E.must_eq("local percent UTF8 URL", paths(U.parse_paths("file:///tmp/%C3%A9%20a.png", True{})), "/tmp/é a.png")
    Unit <- E.must_eq("explicit relative file", paths(U.parse_paths("./a.txt", False{})), "./a.txt")
    Unit <- E.must_eq("implicit relative prose rejected", paths(U.parse_paths("./a.txt", True{})), "none")
    Unit <- E.must_eq("public URL is not a local drop", paths(U.parse_paths("https://0x0.st/a.png", False{})), "none")
    Unit <- E.must_eq("remote file authority rejected", paths(U.parse_paths("file://other/tmp/a", True{})), "none")
    Unit <- E.must_eq("localhost file authority rejected", paths(U.parse_paths("file://localhost/tmp/a", True{})), "none")
    Unit <- E.must_eq("file URL query rejected", paths(U.parse_paths("file:///tmp/a?x", True{})), "none")
    Unit <- E.must_eq("malformed percent rejected", paths(U.parse_paths("file:///tmp/%GG", True{})), "none")
    Unit <- E.must_eq("invalid UTF8 rejected", paths(U.parse_paths("file:///tmp/%C0%AF", True{})), "none")
    Unit <- E.must_eq("decoded control rejected", paths(U.parse_paths("file:///tmp/a%0Ab", True{})), "none")
    Unit <- E.must_eq("decoded NUL rejected", paths(U.parse_paths("file:///tmp/a%00b", True{})), "none")
    Unit <- E.must_eq("decoded C1 control rejected", paths(U.parse_paths("file:///tmp/a%C2%9Bb", True{})), "none")
    Unit <- E.must_eq("multiline prose untouched", paths(U.parse_paths("hello\nworld", True{})), "none")
    Unit <- E.must_eq("unclosed quote rejected", paths(U.parse_paths("'/tmp/a", True{})), "none")
    Unit <- E.must_eq("trailing escape rejected", paths(U.parse_paths("/tmp/a\\", True{})), "none")
    Unit <- E.must_eq("mixed path and prose rejected", paths(U.parse_paths("/tmp/a ordinary", True{})), "none")
    Unit <- E.must_eq("eight paths accepted", paths(U.parse_paths(repeated(8n, "/a "), True{})), "/a|/a|/a|/a|/a|/a|/a|/a")
    Unit <- E.must_eq("ninth path rejects entire drop", paths(U.parse_paths(repeated(9n, "/a "), True{})), "none")
    Unit <- E.must_eq("oversize path rejected", paths(U.parse_paths("/" ++ repeated(1024n, "a"), True{})), "none")
    Unit <- E.must("exact byte bound accepted", String.eq(paths(U.parse_paths("/" ++ repeated(1023n, "a"), True{})), "/" ++ repeated(1023n, "a")))
    Unit <- E.must("Unicode byte bound accepted", String.eq(paths(U.parse_paths("/" ++ repeated(511n, "é") ++ "a", True{})), "/" ++ repeated(511n, "é") ++ "a"))
    Unit <- E.must_eq("Unicode byte bound exceeded", paths(U.parse_paths("/" ++ repeated(512n, "é"), True{})), "none")
    Unit <- E.must_eq("offer stages confirmation", phase(offered()), "confirm:/tmp/a.txt")
    Unit <- E.must_eq("paste alone cannot start", job(U.take_job(offered())), "none")
    Unit <- E.must_eq("offline refusal", phase(U.offer(U.empty(), scope(), False{}, ["/tmp/a.txt"])), "idle")
    Unit <- E.must_eq("empty target refusal", phase(U.offer(U.empty(), U.Scope{"irc.example", 6667, ""}, True{}, ["/tmp/a.txt"])), "idle")
    Unit <- E.must_eq("synthetic target refusal", phase(U.offer(U.empty(), U.Scope{"irc.example", 6667, "*log*"}, True{}, ["/tmp/a.txt"])), "idle")
    Unit <- E.must_eq("explicit confirmation releases one job", job(U.take_job(U.confirm(offered(), scope(), True{}))), "/tmp/a.txt")
    Unit <- E.must_eq("one worker only", job(U.take_job(started())), "none")
    Unit <- E.must_eq("new offer cannot replace worker", phase(U.offer(started(), scope(), True{}, ["/tmp/c"])), "busy:True")
    Unit <- E.must_eq("cancel before confirmation", phase(U.cancel(offered())), "idle")
    Unit <- E.must_eq("cancel after confirmation before spawn", job(U.take_job(U.cancel(U.confirm(offered(), scope(), True{})))), "none")
    Unit <- E.must_eq("cancel retains physical worker", phase(U.cancel(started())), "busy:False")
    Unit <- E.must_eq("cancelled completion never sends", result(U.finish(U.cancel(started()), req(), scope(), True{}, "https://0x0.st/a.txt\n")), "none")
    Unit <- E.must_eq("cancelled completion releases worker", phase(completed(U.finish(U.cancel(started()), req(), scope(), True{}, "https://0x0.st/a.txt\n"))), "idle")
    Unit <- E.must_eq("valid completion sends URL only", result(U.finish(started(), req(), scope(), True{}, "https://0x0.st/a.txt\n")), "https://0x0.st/a.txt")
    Unit <- E.must_eq("second file requires its own confirmation", phase(completed(U.finish(started(), req(), scope(), True{}, "https://0x0.st/a.txt\n"))), "confirm:/tmp/b.png")
    Unit <- E.must_eq("wrong completion keeps ownership", phase(completed(U.finish(started(), U.Request{scope(), "/tmp/other"}, scope(), True{}, "https://0x0.st/a.txt\n"))), "busy:True")
    Unit <- E.must_eq("failed helper releases worker", phase(completed(U.finish(started(), req(), scope(), True{}, ""))), "confirm:/tmp/b.png")
    Unit <- E.must_eq("changed endpoint never sends", result(U.finish(started(), req(), U.Scope{"other", 6667, "+#room"}, True{}, "https://0x0.st/a.txt\n")), "none")
    Unit <- E.must_eq("changed port never sends", result(U.finish(started(), req(), U.Scope{"irc.example", 6697, "+#room"}, True{}, "https://0x0.st/a.txt\n")), "none")
    Unit <- E.must_eq("changed target never sends", result(U.finish(started(), req(), U.Scope{"irc.example", 6667, "#room"}, True{}, "https://0x0.st/a.txt\n")), "none")
    Unit <- E.must_eq("offline completion never sends", result(U.finish(started(), req(), scope(), False{}, "https://0x0.st/a.txt\n")), "none")
    Unit <- E.must_eq("changed-away-and-back stays invalid", result(U.finish(U.retain(U.retain(started(), U.Scope{"other", 6667, "+#room"}, True{}), scope(), True{}), req(), scope(), True{}, "https://0x0.st/a.txt\n")), "none")
    Unit <- E.must_eq("changed scope clears pending consent", phase(U.retain(offered(), U.Scope{"other", 6667, "+#room"}, True{})), "idle")
    Unit <- E.must_eq("scope change invalidates even wrong completion", phase(completed(U.finish(started(), U.Request{scope(), "/tmp/wrong"}, U.Scope{"other", 6667, "+#room"}, True{}, "https://0x0.st/a.txt\n"))), "busy:False")
    Unit <- E.must_eq("safe helper response", text(U.response("https://0x0.st/u/a._~-1.txt\n")), "https://0x0.st/u/a._~-1.txt")
    Unit <- E.must_eq("unterminated helper output rejected", text(U.response("https://0x0.st/a.txt")), "none")
    Unit <- E.must_eq("extra helper output rejected", text(U.response("https://0x0.st/a.txt\nnoise\n")), "none")
    Unit <- E.must_eq("other host rejected", text(U.response("https://0x0.st.evil/a\n")), "none")
    Unit <- E.must_eq("dot segment rejected", text(U.response("https://0x0.st/../a\n")), "none")
    Unit <- E.must_eq("empty URL segment rejected", text(U.response("https://0x0.st//a\n")), "none")
    Unit <- E.must_eq("query rejected", text(U.response("https://0x0.st/a?x\n")), "none")
    Unit <- E.must_eq("CRLF helper output rejected", text(U.response("https://0x0.st/a\r\n")), "none")
    Unit <- E.must("exact URL bound accepted", String.eq(text(U.response("https://0x0.st/" ++ repeated(1009n, "a") ++ "\n")), "https://0x0.st/" ++ repeated(1009n, "a")))
    Unit <- E.must_eq("one byte URL overflow rejected", text(U.response("https://0x0.st/" ++ repeated(1010n, "a") ++ "\n")), "none")
    Unit <- E.must("exact IRC wire bound fits without clamping", U.wire_fits(req(), "https://0x0.st/" ++ repeated(479n, "a")))
    Unit <- E.must("IRC wire one-byte overflow refused", Bool.not(U.wire_fits(req(), "https://0x0.st/" ++ repeated(480n, "a"))))
    Unit <- E.must("long target refused before submission", Bool.not(U.wire_fits(U.Request{U.Scope{"irc.example", 6667, repeated(500n, "x")}, "/tmp/a"}, "https://0x0.st/a")))
    Unit <- E.must("wire fit still requires validated URL", Bool.not(U.wire_fits(req(), "https://other.example/a")))
    Unit <- E.must("consent inspector", U.consent_ok())
    Unit <- E.must("one-shot inspector", U.one_shot_ok())
    Unit <- E.must("cancel inspector", U.cancel_ok())
    Unit <- E.must_eq("oversize response rejected", text(U.response("https://0x0.st/" ++ repeated(1024n, "a") ++ "\n")), "none")
    IO.print("upload_demo=ok")
