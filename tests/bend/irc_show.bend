# Test-only IRC tags and sanitize samples. Not cited by LAWS.bend.
import Base
import ../../src/bend/irc.bend as Irc

def show_cmd(c: Irc.Cmd) -> String:
  match c:
    case Irc.Unknown{}:
      "UNK"
    case Irc.Ping{}:
      "PING"
    case Irc.Pong{}:
      "PONG"
    case Irc.Join{}:
      "JOIN"
    case Irc.Part{}:
      "PART"
    case Irc.Kick{}:
      "KICK"
    case Irc.Quit{}:
      "QUIT"
    case Irc.Privmsg{}:
      "PRIVMSG"
    case Irc.Notice{}:
      "NOTICE"
    case Irc.Nick{}:
      "NICK"
    case Irc.Topic{}:
      "TOPIC"
    case Irc.Mode{}:
      "MODE"
    case Irc.Names{}:
      "NAMES"
    case Irc.Error{}:
      "ERROR"
    case Irc.Numeric{+code}:
      "NUM" ++ U32.show(code)

def show_params.chunks(+ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      ("|" ++ h) <> show_params.chunks(t)

def show_params(+ps: List<&2, String>) -> String:
  String.concat(show_params.chunks(ps))

def show_msg(+m: Irc.Message) -> String:
  match m:
    case Irc.Message{+nick, +cmd, +num, +ps}:
      nick ++ "!" ++ cmd ++ "#" ++ U32.show(num) ++ show_params(ps)

def show_parse.on(m: Maybe<&2, Irc.Message>) -> String:
  match m:
    case None{}:
      "NONE"
    case Some{+msg}:
      show_cmd(Irc.classify(msg)) ++ ":" ++ show_msg(msg)

def show_parse(line: String) -> String:
  show_parse.on(Irc.parse(line))

def sanitize_in_ok() -> Bool:
  String.eq(Irc.sanitize_in("ab" ++ SCon{Chr{31}, "cd"}), "abcd")
    && String.eq(Irc.sanitize_in("x" ++ SCon{Chr{3}, "04y"}), "xy")
    && String.eq(Irc.sanitize_in(SCon{Chr{1}, "ACTION"}), SCon{Chr{1}, "ACTION"})
    && String.eq(Irc.sanitize_in(SCon{Chr{3}, ",hello"}), ",hello")
    && String.eq(Irc.sanitize_in(SCon{Chr{3}, "4,hello"}), "hello")
    && String.eq(Irc.sanitize_in(SCon{Chr{3}, "04,02hello"}), "hello")
