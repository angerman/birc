# Outbound CTCP ACTION keeps its closing SOH and echoes the transmitted text.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def channel(+target: String) -> Cl.Client:
  client(Sub.submit(Cl.init("me", "irc.example"), "/join " ++ target))

def repeat(n: Nat, +c: Char) -> String:
  match n:
    case 0n: ""
    case 1n+p: SCon{c, repeat(p, c)}

def action_result(pair: Cl.Client & List<&2, String>, +target: String, +want: String) -> Bool:
  match pair:
    case (+cl, outs):
      match outs:
        case Con{+wire, Nil{}}:
          String.eq(wire, Irc.format_privmsg(target, Sub.ctcp_action(want)))
            && Irc.line_ok(wire)
            && String.eq(CL.buf_texts(cl, 1n), "* me " ++ want ++ "|")
        case _: False{}

def action(+body: String, +want: String) -> Bool:
  action_result(Sub.submit(channel("#room"), "/me " ++ body), "#room", want)

def oversize_result(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (+cl, outs):
      Nat.is_eq(List.length(&2, String, outs), 0n)
        && String.eq(CL.buf_texts(cl, 1n), "action target exceeds IRC line limit|")

def oversize_target() -> Bool:
  oversize_result(Sub.submit(channel("#" ++ Irc.stars.go(491n)), "/me waves"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("short_action", action("waves", "waves"))
    Unit <- E.must("exact_ascii_action", action(Irc.stars.go(486n), Irc.stars.go(486n)))
    Unit <- E.must("long_ascii_action", action(Irc.stars.go(507n), Irc.stars.go(486n)))
    Unit <- E.must("exact_utf8_action", action(repeat(162n, Chr{28450}), repeat(162n, Chr{28450})))
    Unit <- E.must("long_utf8_action", action(repeat(163n, Chr{28450}), repeat(162n, Chr{28450})))
    Unit <- E.must("partial_utf8_action", action(Irc.stars.go(485n) ++ "é", Irc.stars.go(485n)))
    Unit <- E.must("four_byte_action", action(repeat(123n, Chr{128512}), repeat(121n, Chr{128512})))
    Unit <- E.must("line_injection_action", action("hi" ++ SCon{Chr{13}, SCon{Chr{10}, "there"}}, "hithere"))
    Unit <- E.must("oversize_target", oversize_target())
    IO.print("action_budget_demo=ok")
