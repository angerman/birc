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

def message_valid(parsed: Maybe<&2, Irc.Message>, +target: String) -> Bool:
  match parsed:
    case None{}: False{}
    case Some{+m}:
      Irc.ieq(Irc.msg_command(m), "PRIVMSG") && String.eq(Irc.msg_param(m, 0n), target)
        && Nat.is_eq(List.length(&2, String, Irc.msg_params(m)), 2n)
        && Bool.not(String.is_empty(Irc.msg_param(m, 1n)))

def messages_valid(xs: List<&2, String>, +target: String) -> Bool:
  match xs:
    case Nil{}: True{}
    case Con{h, t}: message_valid(Irc.parse(h), target) && messages_valid(t, target)

def complete_body(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: body(Irc.parse(h)) ++ complete_body(t)

def echoes_ok(lines: List<&2, Cl.Line>, wires: List<&2, String>) -> Bool:
  match lines wires:
    case Nil{} Nil{}: True{}
    case Con{Cl.Line{Cl.Self{}, _, text, author, _}, rest} Con{wire, tail}:
      String.eq(text, Feed.fmt_msg("me", body(Irc.parse(wire))))
        && String.eq(author, "me") && echoes_ok(rest, tail)
    case _ _: False{}

def client_now(cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, _, _, now, _, _, _}: now

def history_wires(xs: List<&2, String>, +target: String, +now: String) -> String:
  match xs:
    case Nil{}: ""
    case Con{wire, rest}:
      H.serialize_line_for("s:6667", target,
        Cl.Line{Cl.Self{}, now, Feed.fmt_msg("me", body(Irc.parse(wire))), "me", 0n})
        ++ history_wires(rest, target, now)

def complete_agreement(+label: String, pair: Cl.Client & List<&2, String>, +expected: String) -> IO(Unit):
  match pair:
    case (_, Nil{}): E.must(label ++ " needs wire output", False{})
    case (+cl, +outs):
      +target = Cl.active_buf_name(cl)
      do IO<Unit>:
        Unit <- E.must_eq(label ++ " complete body", complete_body(outs), expected)
        Unit <- E.must(label ++ " every line bound", S.out_all_ok(outs))
        Unit <- E.must(label ++ " exact target and nonempty bodies", messages_valid(outs, target))
        Unit <- E.must(label ++ " echoes equal every sent body", echoes_ok(Cl.active_buf_lines(cl), outs))
        Unit <- E.must_eq(label ++ " history contains every echo in order",
          H.extract_new_history_for("s:6667", Cl.init("me", "s"), cl), history_wires(outs, target, client_now(cl)))
        IO.pure(Unit, Unit{})

def rejected(+label: String, pair: Cl.Client & List<&2, String>) -> IO(Unit):
  match pair:
    case (+cl, Nil{}): E.must(label ++ " no self echo", Bool.not(String.contains(W.lines_signature(Cl.active_buf_lines(cl)), "SELF|")))
    case _: E.must(label ++ " must not send truncated target", False{})

def ascii_guards() -> IO(Unit):
  +base = Cl.init("me", "s")
  +channel = client(S.submit(base, "/join #r"))
  +long = repeated(600n, 'x')
  do IO<Unit>:
    complete_agreement("plain long", S.submit(channel, long), long)
    complete_agreement("msg long", S.submit(base, "/msg alice " ++ long), long)
    complete_agreement("query long", S.submit(base, "/query alice " ++ long), long)
    agreement("exact boundary", S.submit(channel, repeated(498n, 'x')), repeated(498n, 'x'))
    complete_agreement("one over boundary", S.submit(channel, repeated(499n, 'x')), repeated(499n, 'x'))
    agreement("short control", S.submit(channel, "hello"), "hello")
    agreement("CRLF removed before body fit and echo", S.submit(channel, "a" ++ SCon{Chr{13}, "b" ++ SCon{Chr{10}, "c"}}), "abc")
    IO.pure(Unit, Unit{})

def unicode_guards() -> IO(Unit):
  +base = Cl.init("me", "s")
  +channel = client(S.submit(base, "/join #r"))
  do IO<Unit>:
    complete_agreement("plain unicode", S.submit(channel, repeated(200n, '界')), repeated(200n, '界'))
    complete_agreement("msg unicode", S.submit(base, "/msg alice " ++ repeated(200n, '😀')), repeated(200n, '😀'))
    complete_agreement("query unicode", S.submit(base, "/query alice " ++ repeated(200n, '界')), repeated(200n, '界'))
    rejected("msg oversized envelope", S.submit(base, "/msg " ++ repeated(510n, 'x') ++ " hi"))
    rejected("query oversized envelope", S.submit(base, "/query " ++ repeated(510n, 'x') ++ " hi"))
    rejected("plain oversized envelope", S.submit(client(S.submit(base, "/query " ++ repeated(510n, 'x'))), "hi"))
    complete_agreement("fitting envelope with one-byte body budget", S.submit(base, "/msg " ++ repeated(499n, 'x') ++ " hi"), "hi")
    rejected("zero body budget", S.submit(base, "/msg " ++ repeated(500n, 'x') ++ " hi"))
    rejected("one-byte oversized envelope", S.submit(base, "/msg " ++ repeated(501n, 'x') ++ " hi"))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    ascii_guards()
    unicode_guards()
    IO.print("state_review_send=ok")
