# Reader-owned PONG purity: exact replies per completed line, split-chunk
# reassembly through the shadow framer, and overlong-drop silence.
import Base
import ./expect.bend as E
import ../../src/bend/actor.bend as Act
import ../../src/bend/frame.bend as Fr

def show(+xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+h, t}:
      h ++ "|" ++ show(t)

def show_pongs(+xs: List<&2, String>) -> String:
  show(Act.reader_pongs(xs))

# A PING split across two pushes answers exactly once, on completion.
def split_push2(second: List<&2, String> & List<&2, U32> & Bool, +pongs1: List<&2, String>) -> List<&2, String>:
  match second:
    case (lines2, _, _):
      List.append(&2, String, pongs1, Act.reader_pongs(lines2))

def split_push1(first: List<&2, String> & List<&2, U32> & Bool) -> List<&2, String>:
  match first:
    case (lines1, rem1, drop1):
      +pongs1 = Act.reader_pongs(lines1)
      split_push2(Fr.push_ex(drop1, rem1, Fr.string_to_octets("lit-gen\r\n")), pongs1)

def split_pongs() -> List<&2, String>:
  split_push1(Fr.push_ex(False{}, Nil{}, Fr.string_to_octets("PING :sp")))

# An overlong PING never completes a line, so it is never answered.
def overlong_ping() -> List<&2, U32>:
  List.append(&2, U32, Fr.string_to_octets("PING :"), Fr.a_line(520n))

def drop_push(got: List<&2, String> & List<&2, U32> & Bool) -> List<&2, String>:
  match got:
    case (lines, _, _):
      Act.reader_pongs(lines)

def drop_pongs() -> List<&2, String>:
  drop_push(Fr.push_ex(False{}, Nil{}, overlong_ping()))

# Complete the rejected line: without a newline, silence alone cannot show
# that the framer rejected an overlong line. Then carry Drop across pushes
# and require exactly one reply for the valid PING after the rejected line.
def drop_complete_pongs() -> List<&2, String>:
  drop_push(Fr.push_ex(False{}, Nil{}, List.append(&2, U32, overlong_ping(), Fr.string_to_octets("\r\n"))))

def drop_recovery_push(first: List<&2, String> & List<&2, U32> & Bool) -> List<&2, String>:
  match first:
    case (lines, rem, drop):
      split_push2(Fr.push_ex(drop, rem, Fr.string_to_octets("\r\nPING :after-drop\r\n")), Act.reader_pongs(lines))

def drop_recovery_pongs() -> List<&2, String>:
  drop_recovery_push(Fr.push_ex(False{}, Nil{}, overlong_ping()))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("exact_one", show_pongs("PING :abc" <> Nil{}), "PONG :abc|")
    Unit <- E.must_eq("empty", show_pongs(Nil{}), "")
    Unit <- E.must_eq("non_ping", show_pongs(":a!u@h PRIVMSG #t :hi" <> Nil{}), "")
    Unit <- E.must_eq("order", show_pongs("PING :a" <> ":a!u@h NOTICE #t :n" <> "PING :b" <> Nil{}), "PONG :a|PONG :b|")
    Unit <- E.must_eq("pong_never", show_pongs("PONG :x" <> Nil{}), "")
    Unit <- E.must_eq("split_once", show(split_pongs()), "PONG :split-gen|")
    Unit <- E.must_eq("overlong_silent", show(drop_pongs()), "")
    Unit <- E.must_eq("overlong_completed_silent", show(drop_complete_pongs()), "")
    Unit <- E.must_eq("overlong_split_recovers_once", show(drop_recovery_pongs()), "PONG :after-drop|")
    IO.print("reader_pongs=ok")
