# SPDX-License-Identifier: Apache-2.0
# Slash commands win over ambiguous root files; clear dropped paths need consent.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/session.bend as Sess
import ../../src/bend/upload.bend as Up

def online() -> Sess.Session:
  +cl = Feed.feed(Cl.init("me", "irc.example"), ":me!u@h JOIN :#t")
  Sess.session_online(Sess.session_with_client_at(Cl.set_active(cl, 1n), "#t", 6667))

def phase(state: Up.State) -> String:
  match state:
    case Up.Idle{}: "idle"
    case Up.Confirm{Up.Request{_, path}, _}: "confirm:" ++ path
    case _: "other"

def wire(cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Cont{outs}: String.join(outs, "|")
    case _: "other"

def history(st: Sess.Session) -> String:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, Sess.Hist{lines, _}, _, _, _, _, _, _, _}: String.join(lines, "|")

def texts(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, _, text, _, _}, rest}: text ++ "|" ++ texts(rest)

def stored(bufs: List<&2, Cl.Buffer>) -> String:
  match bufs:
    case Nil{}: ""
    case Con{Cl.Buffer{_, _, _, lines, _, _}, rest}: texts(lines) ++ stored(rest)

def unknown.got(trip: Sess.Session & Sess.NetCmd & Bool, raw: String, verb: String) -> Bool:
  match trip:
    case (+st, cmd, _):
      +text = stored(Cl.client_bufs(Sess.session_cl(st)))
      String.eq(phase(Sess.session_upload(st)), "idle") && String.is_empty(wire(cmd))
        && String.contains(text, "unknown command: /" ++ verb)
        && Bool.not(String.contains(text, "usage: /upload")) && String.eq(history(st), raw)

def unknown(+raw: String, verb: String) -> Bool:
  unknown.got(Sess.step_enter(online(), raw), raw, verb)

def offered.got(trip: Sess.Session & Sess.NetCmd & Bool, path: String) -> Bool:
  match trip:
    case (+st, cmd, _):
      String.eq(phase(Sess.session_upload(st)), "confirm:" ++ path)
        && String.is_empty(wire(cmd)) && String.is_empty(history(st))

def offered(raw: String, path: String) -> Bool:
  offered.got(Sess.step_enter(online(), raw), path)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("bare unknown slash verb remains a command", unknown("/RECREATED-ONLY", "RECREATED-ONLY"))
    Unit <- E.must("unknown slash verb with arguments remains a command", unknown("/bogus argument", "bogus"))
    Unit <- E.must("quoted command arguments cannot turn its verb into a path", unknown("/bogus 'argument'", "bogus"))
    Unit <- E.must("escaped command arguments cannot turn its verb into a path", unknown("/bogus extra\\ argument", "bogus"))
    Unit <- E.must("remote text in unknown slash verb stays a command", unknown("/plain-user-pass-https://log.invalid/pass", "plain-user-pass-https://log.invalid/pass"))
    Unit <- E.must("styled remote text in unknown slash verb stays a command", unknown("/styled-_https://log.invalid/pass_", "styled-_https://log.invalid/pass_"))
    Unit <- E.must("code remote text in unknown slash verb stays a command", unknown("/code-`https://log.invalid/user`-pass", "code-`https://log.invalid/user`-pass"))
    Unit <- E.must("unquoted absolute path still stages consent", offered("/tmp/private.txt", "/tmp/private.txt"))
    Unit <- E.must("quoted absolute path still stages consent", offered("'/tmp/private file.txt'", "/tmp/private file.txt"))
    Unit <- E.must("escaped absolute path still stages consent", offered("/tmp/private\\ file.txt", "/tmp/private file.txt"))
    Unit <- E.must("escaped root-level path still stages consent", offered("/root\\ file.png", "/root file.png"))
    Unit <- E.must("quoted root-level path still stages consent", offered("'/root file.png'", "/root file.png"))
    Unit <- E.must("concatenated quote marks root-level path intent", offered("/root' file.png'", "/root file.png"))
    Unit <- E.must("file URI still stages consent", offered("file:///tmp/private%20file.txt", "/tmp/private file.txt"))
    Unit <- E.must("explicit upload supports ambiguous root files", offered("/upload /root-file", "/root-file"))
    Unit <- E.must("explicit upload still supports ordinary paths", offered("/upload /tmp/private.txt", "/tmp/private.txt"))
    IO.print("upload_dispatch=ok")
