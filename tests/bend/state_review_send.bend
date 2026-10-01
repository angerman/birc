# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ./diagnostic_wire.bend as W
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/irc.bend as Irc
import ../../src/bend/submit.bend as S
import ../../src/bend/history.bend as H

def repeated(n: Nat, +c: Char) -> String:
  match n:
    case 0n: ""
    case 1n+p: SCon{c, repeated(p, c)}

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def body(parsed: Maybe<&2, Irc.Message>) -> String:
  match parsed:
    case None{}: ""
    case Some{m}: Irc.msg_param(m, 1n)

def agreement(+label: String, pair: Cl.Client & List<&2, String>, +expected: String) -> IO(Unit):
  match pair:
    case (+cl, Con{+wire, Nil{}}):
      +sent = body(Irc.parse(wire))
      do IO<Unit>:
        Unit <- E.must_eq(label ++ " fitted body", sent, expected)
        Unit <- E.must(label ++ " line bound", Irc.line_ok(wire))
        Unit <- E.must_eq(label ++ " echo equals sent body", W.last_text(Cl.active_buf_lines(cl)), Feed.fmt_msg("me", expected))
        Unit <- E.must(label ++ " history uses fitted echo", String.contains(H.extract_new_history_for("s:6667", Cl.init("me", "s"), cl), Feed.fmt_msg("me", expected) ++ "\n"))
        IO.pure(Unit, Unit{})
    case _: E.must(label ++ " needs exactly one wire line", False{})

def rejected(+label: String, pair: Cl.Client & List<&2, String>) -> IO(Unit):
  match pair:
    case (+cl, Nil{}): E.must(label ++ " no self echo", Bool.not(String.contains(W.lines_signature(Cl.active_buf_lines(cl)), "SELF|")))
    case _: E.must(label ++ " must not send truncated target", False{})

def ascii_guards() -> IO(Unit):
  +base = Cl.init("me", "s")
  +channel = client(S.submit(base, "/join #r"))
  +long = repeated(600n, 'x')
  do IO<Unit>:
    agreement("plain long", S.submit(channel, long), repeated(498n, 'x'))
    agreement("msg long", S.submit(base, "/msg alice " ++ long), repeated(495n, 'x'))
    agreement("query long", S.submit(base, "/query alice " ++ long), repeated(495n, 'x'))
    agreement("exact boundary", S.submit(channel, repeated(498n, 'x')), repeated(498n, 'x'))
    agreement("one over boundary", S.submit(channel, repeated(499n, 'x')), repeated(498n, 'x'))
    agreement("short control", S.submit(channel, "hello"), "hello")
    agreement("CRLF removed before body fit and echo", S.submit(channel, "a" ++ SCon{Chr{13}, "b" ++ SCon{Chr{10}, "c"}}), "abc")
    IO.pure(Unit, Unit{})

def unicode_guards() -> IO(Unit):
  +base = Cl.init("me", "s")
  +channel = client(S.submit(base, "/join #r"))
  do IO<Unit>:
    agreement("plain unicode", S.submit(channel, repeated(200n, '界')), repeated(166n, '界'))
    agreement("msg unicode", S.submit(base, "/msg alice " ++ repeated(200n, '😀')), repeated(123n, '😀'))
    agreement("query unicode", S.submit(base, "/query alice " ++ repeated(200n, '界')), repeated(165n, '界'))
    rejected("msg oversized envelope", S.submit(base, "/msg " ++ repeated(510n, 'x') ++ " hi"))
    rejected("query oversized envelope", S.submit(base, "/query " ++ repeated(510n, 'x') ++ " hi"))
    rejected("plain oversized envelope", S.submit(client(S.submit(base, "/query " ++ repeated(510n, 'x'))), "hi"))
    agreement("exact envelope boundary", S.submit(base, "/msg " ++ repeated(500n, 'x') ++ " hi"), "")
    rejected("one-byte oversized envelope", S.submit(base, "/msg " ++ repeated(501n, 'x') ++ " hi"))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    ascii_guards()
    unicode_guards()
    IO.print("state_review_send=ok")
