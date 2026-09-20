# birc IRC protocol core (pure). RFC 1459 §2.3.1 / RFC 2812 §2.3.1.
# Parse, classify, format. No IO here — the TimUI client and the
# headless harness drive this through fixtures and the wire.
import Base

def LINE_MAX() -> Nat:
  510n  # 512 including CRLF

type Cmd is Data:
  Unknown{}
  Ping{}
  Pong{}
  Join{}
  Part{}
  Kick{}
  Quit{}
  Privmsg{}
  Notice{}
  Nick{}
  Topic{}
  Mode{}
  Names{}
  Error{}
  Numeric{code: U32}

type Message is Data:
  Message{
    nick: String,
    command: String,
    numeric: U32,
    params: List<&2, String>
  }

# ---- character helpers --------------------------------------------------

def code_of(+c: Char) -> U32:
  match c:
    case Chr{code}:
      code

def code_is(+c: Char, +k: U32) -> Bool:
  U32.is_eq(code_of(c), k)

def is_space(+c: Char) -> Bool:
  code_is(c, 32)

def is_colon(+c: Char) -> Bool:
  code_is(c, 58)

def is_bang_or_at(+c: Char) -> Bool:
  code_is(c, 33) || code_is(c, 64)

def is_digit(+c: Char) -> Bool:
  Char.is_digit(c)

# ---- string helpers -----------------------------------------------------

type SpacePhase is Data:
  SpRead{}
  SpDecide{}

# Fuel-bounded space skip: each char costs Read+Decide ≤ 2 calls.
def drop_spaces.go(fuel: Nat, phase: SpacePhase, s: String, +h: Char, space: Bool) -> String:
  match fuel:
    case 0n:
      s
    case 1n+p:
      match phase:
        case SpRead{}:
          match s:
            case SNil{}:
              SNil{}
            case SCon{+hd, t}:
              drop_spaces.go(p, SpDecide{}, t, hd, is_space(hd))
        case SpDecide{}:
          match space:
            case True{}:
              drop_spaces.go(p, SpRead{}, s, h, False{})
            case False{}:
              SCon{h, s}

def drop_spaces(+s: String) -> String:
  drop_spaces.go(Nat.add(1n, Nat.mul(2n, String.length(s))), SpRead{}, s, Chr{0}, False{})

type TakePhase is Data:
  TkRead{}
  TkDecide{}

def take_until_space.go(fuel: Nat, phase: TakePhase, s: String, acc: String, +h: Char, space: Bool) -> String & String:
  match fuel:
    case 0n:
      (String.reverse(acc), s)
    case 1n+p:
      match phase:
        case TkRead{}:
          match s:
            case SNil{}:
              (String.reverse(acc), SNil{})
            case SCon{+hd, t}:
              take_until_space.go(p, TkDecide{}, t, acc, hd, is_space(hd))
        case TkDecide{}:
          match space:
            case True{}:
              (String.reverse(acc), SCon{h, s})
            case False{}:
              take_until_space.go(p, TkRead{}, s, SCon{h, acc}, h, False{})

def take_until_space(+s: String) -> String & String:
  take_until_space.go(Nat.add(1n, Nat.mul(2n, String.length(s))), TkRead{}, s, SNil{}, Chr{0}, False{})

def ieq(+a: String, +b: String) -> Bool:
  String.eq(String.to_upper(a), String.to_upper(b))

def is_chan_type(+c: Char) -> Bool:
  code_is(c, 35) || code_is(c, 38) || code_is(c, 43) || code_is(c, 33)  # # & + !

def is_status_prefix(+c: Char) -> Bool:
  code_is(c, 64) || code_is(c, 43)  # @ +

def starts_channel.rest(+t: String) -> Bool:
  match t:
    case SNil{}:
      False{}
    case SCon{+h, _}:
      is_chan_type(h)

def starts_channel.status(pref: Bool, +t: String) -> Bool:
  match pref:
    case False{}:
      False{}
    case True{}:
      starts_channel.rest(t)

def starts_channel.head(+h: Char, +t: String) -> Bool:
  is_chan_type(h) || starts_channel.status(is_status_prefix(h), t)

def starts_channel(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+h, t}:
      starts_channel.head(h, t)

# STATUSMSG: @#chan / +#chan → #chan. +chan (CHANTYPE) is left intact.
def chan_target.pick(+h: Char, +t: String, +s: String, strip: Bool) -> String:
  match strip:
    case True{}:
      t
    case False{}:
      s

def chan_target.head(+h: Char, +t: String, +s: String) -> String:
  chan_target.pick(h, t, s, is_status_prefix(h) && starts_channel.rest(t))

def chan_target(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      chan_target.head(h, t, s)

def is_numeric3(+s: String) -> Bool:
  match s:
    case SCon{+a, SCon{+b, SCon{+c, SNil{}}}}:
      is_digit(a) && is_digit(b) && is_digit(c)
    case _:
      False{}

def digit_val(+c: Char) -> U32:
  U32.sub(code_of(c), 48)

def parse_numeric3(+s: String) -> U32:
  match s:
    case SCon{+a, SCon{+b, SCon{+c, SNil{}}}}:
      U32.add(U32.add(U32.mul(digit_val(a), 100), U32.mul(digit_val(b), 10)), digit_val(c))
    case _:
      0

type NickPhase is Data:
  NkRead{}
  NkDecide{}

def nick_of_prefix.go(fuel: Nat, phase: NickPhase, s: String, acc: String, +h: Char, cut: Bool) -> String:
  match fuel:
    case 0n:
      String.reverse(acc)
    case 1n+p:
      match phase:
        case NkRead{}:
          match s:
            case SNil{}:
              String.reverse(acc)
            case SCon{+hd, t}:
              nick_of_prefix.go(p, NkDecide{}, t, acc, hd, is_bang_or_at(hd))
        case NkDecide{}:
          match cut:
            case True{}:
              String.reverse(acc)
            case False{}:
              nick_of_prefix.go(p, NkRead{}, s, SCon{h, acc}, h, False{})

def nick_of_prefix(+pfx: String) -> String:
  nick_of_prefix.go(Nat.add(1n, Nat.mul(2n, String.length(pfx))), NkRead{}, pfx, SNil{}, Chr{0}, False{})

# ---- parse --------------------------------------------------------------

def push_param(ps: List<&2, String>, p: String) -> List<&2, String>:
  List.append(&2, String, ps, p <> Nil{})

type ParPhase is Data:
  ParFuel{}
  ParRest{}
  ParColon{}
  ParMid{}

def parse_params.go(fuel: Nat, phase: ParPhase, s: String, ps: List<&2, String>, +h: Char, t: String, +rest: String, colon: Bool, pair: String & String) -> List<&2, String>:
  match fuel:
    case 0n:
      ps
    case 1n+p:
      match phase:
        case ParFuel{}:
          parse_params.go(p, ParRest{}, drop_spaces(s), ps, h, t, rest, colon, pair)
        case ParRest{}:
          match s:
            case SNil{}:
              ps
            case SCon{+hd, +tl}:
              parse_params.go(p, ParColon{}, "", ps, hd, tl, SCon{hd, tl}, is_colon(hd), pair)
        case ParColon{}:
          match colon:
            case True{}:
              push_param(ps, t)
            case False{}:
              parse_params.go(p, ParMid{}, s, ps, h, t, rest, False{}, take_until_space(rest))
        case ParMid{}:
          (tok, more) = pair
          parse_params.go(p, ParFuel{}, more, push_param(ps, tok), h, t, rest, False{}, ("", ""))

def parse_params(s: String) -> List<&2, String>:
  parse_params.go(64n, ParFuel{}, s, Nil{}, Chr{0}, "", "", False{}, ("", ""))

def parse_after_prefix.empty(empty: Bool, +cmd: String, +more: String, +nick: String) -> Maybe<&2, Message>:
  match empty:
    case True{}:
      None{}
    case False{}:
      +num = Bool.pick(U32, is_numeric3(cmd), parse_numeric3(cmd), 0)
      Some{Message{nick, cmd, num, parse_params(more)}}

def parse_after_prefix.cmd2(+cmd: String, more: String, +nick: String) -> Maybe<&2, Message>:
  parse_after_prefix.empty(String.is_empty(cmd), cmd, more, nick)

def parse_after_prefix.cmd(pair: String & String, +nick: String) -> Maybe<&2, Message>:
  (cmd, more) = pair
  parse_after_prefix.cmd2(cmd, more, nick)

def parse_after_prefix.on_rest(rest: String, nick: String) -> Maybe<&2, Message>:
  match rest:
    case SNil{}:
      None{}
    case _:
      parse_after_prefix.cmd(take_until_space(rest), nick)

def parse_after_prefix(s: String, nick: String) -> Maybe<&2, Message>:
  parse_after_prefix.on_rest(drop_spaces(s), nick)

def parse_body.with_pfx(pair: String & String) -> Maybe<&2, Message>:
  (pfx, more) = pair
  parse_after_prefix(more, nick_of_prefix(pfx))

def parse_body.colon(colon: Bool, +h: Char, +t: String, +rest: String) -> Maybe<&2, Message>:
  match colon:
    case True{}:
      parse_body.with_pfx(take_until_space(t))
    case False{}:
      parse_after_prefix(rest, "")

def parse_body.on_rest(rest: String) -> Maybe<&2, Message>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+h, +t}:
      parse_body.colon(is_colon(h), h, t, SCon{h, t})

def parse_body(s: String) -> Maybe<&2, Message>:
  parse_body.on_rest(drop_spaces(s))

def strip_cr.fin(cr: Bool, +s: String, +t: String) -> String:
  match cr:
    case True{}:
      String.reverse(t)
    case False{}:
      s

def strip_cr.go(rev: String, +s: String) -> String:
  match rev:
    case SCon{+h, t}:
      strip_cr.fin(code_is(h, 13), s, t)
    case SNil{}:
      SNil{}

def strip_cr(+s: String) -> String:
  strip_cr.go(String.reverse(s), s)

# F13 — drop CR/LF so outbound cannot inject extra IRC lines.
type CtlPhase is Data:
  CtlRead{}
  CtlDecide{}

def is_crlf(+c: Char) -> Bool:
  code_is(c, 13) || code_is(c, 10)

def strip_ctl.go(fuel: Nat, phase: CtlPhase, s: String, acc: String, +h: Char, drop: Bool) -> String:
  match fuel:
    case 0n:
      String.reverse(acc)
    case 1n+p:
      match phase:
        case CtlRead{}:
          match s:
            case SNil{}:
              String.reverse(acc)
            case SCon{+hd, t}:
              strip_ctl.go(p, CtlDecide{}, t, acc, hd, is_crlf(hd))
        case CtlDecide{}:
          match drop:
            case True{}:
              strip_ctl.go(p, CtlRead{}, s, acc, h, False{})
            case False{}:
              strip_ctl.go(p, CtlRead{}, s, SCon{h, acc}, h, False{})

def strip_ctl(+s: String) -> String:
  strip_ctl.go(Nat.add(1n, Nat.mul(2n, String.length(s))), CtlRead{}, s, SNil{}, Chr{0}, False{})

def parse(line: String) -> Maybe<&2, Message>:
  parse_body(strip_cr(line))

# ---- classify -----------------------------------------------------------

# Nested ieq helpers: match only on Bool parameters (first binder).
def cls_err(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Error{}
    case False{}:
      Unknown{}

def cls_names(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Names{}
    case False{}:
      cls_err(ieq(cmd, "ERROR"), cmd)

def cls_mode(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Mode{}
    case False{}:
      cls_names(ieq(cmd, "NAMES"), cmd)

def cls_topic(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Topic{}
    case False{}:
      cls_mode(ieq(cmd, "MODE"), cmd)

def cls_nick(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Nick{}
    case False{}:
      cls_topic(ieq(cmd, "TOPIC"), cmd)

def cls_notice(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Notice{}
    case False{}:
      cls_nick(ieq(cmd, "NICK"), cmd)

def cls_privmsg(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Privmsg{}
    case False{}:
      cls_notice(ieq(cmd, "NOTICE"), cmd)

def cls_quit(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Quit{}
    case False{}:
      cls_privmsg(ieq(cmd, "PRIVMSG"), cmd)

def cls_kick(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Kick{}
    case False{}:
      cls_quit(ieq(cmd, "QUIT"), cmd)

def cls_part(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Part{}
    case False{}:
      cls_kick(ieq(cmd, "KICK"), cmd)

def cls_join(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Join{}
    case False{}:
      cls_part(ieq(cmd, "PART"), cmd)

def cls_pong(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Pong{}
    case False{}:
      cls_join(ieq(cmd, "JOIN"), cmd)

def cls_ping(hit: Bool, +cmd: String) -> Cmd:
  match hit:
    case True{}:
      Ping{}
    case False{}:
      cls_pong(ieq(cmd, "PONG"), cmd)

def cls_verb(num: Bool, +cmd: String, +code: U32) -> Cmd:
  match num:
    case True{}:
      Numeric{code}
    case False{}:
      cls_ping(ieq(cmd, "PING"), cmd)

def classify(+m: Message) -> Cmd:
  match m:
    case Message{_, +cmd, +num, _}:
      cls_verb(U32.is_gt(num, 0), cmd, num)

def param_at(ps: List<&2, String>, i: Nat) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{+h, +t}:
      match i:
        case 0n:
          h
        case 1n+p:
          param_at(t, p)

def msg_param(+m: Message, i: Nat) -> String:
  match m:
    case Message{_, _, _, +ps}:
      param_at(ps, i)

# ---- format -------------------------------------------------------------

def format_pong.empty(empty: Bool, +token: String) -> String:
  match empty:
    case True{}:
      "PONG"
    case False{}:
      "PONG :" ++ token

def format_pong(+token: String) -> String:
  format_pong.empty(String.is_empty(token), token)

def format_nick(+nick: String) -> String:
  "NICK " ++ nick

def format_user(+nick: String) -> String:
  "USER " ++ nick ++ " 0 * :" ++ nick

def format_join(+chan: String) -> String:
  "JOIN " ++ chan

def format_part(+chan: String) -> String:
  "PART " ++ chan

def format_privmsg(+target: String, +body: String) -> String:
  "PRIVMSG " ++ target ++ " :" ++ body

def format_quit.empty(empty: Bool, +reason: String) -> String:
  match empty:
    case True{}:
      "QUIT :birc"
    case False{}:
      "QUIT :" ++ reason

def format_quit(+reason: String) -> String:
  format_quit.empty(String.is_empty(reason), reason)

law clamp_line.go:
  for n: Nat
  for s: String
  for acc: String
  String

def clamp_line.go(n, s, acc):
  match n:
    case 0n:
      String.reverse(acc)
    case 1n+p:
      match s:
        case SNil{}:
          String.reverse(acc)
        case SCon{+h, t}:
          clamp_line.go(p, t, SCon{h, acc})

def clamp_line(s: String) -> String:
  clamp_line.go(LINE_MAX(), s, SNil{})

def line_ok(s: String) -> Bool:
  Nat.is_le(String.length(s), LINE_MAX())

def is_ping_cmd(c: Cmd) -> Bool:
  match c:
    case Ping{}:
      True{}
    case _:
      False{}

def is_ping_line.fin(ok: Bool) -> Bool:
  match ok:
    case True{}:
      True{}
    case False{}:
      False{}

def is_ping_line.on(m: Maybe<&2, Message>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{+msg}:
      is_ping_line.fin(is_ping_cmd(classify(msg)))

def is_ping_line(line: String) -> Bool:
  is_ping_line.on(parse(line))

def pong_for.fin(ping: Bool, +m: Message) -> String:
  match ping:
    case True{}:
      format_pong(msg_param(m, 0n))
    case False{}:
      ""

def pong_for.on(m: Maybe<&2, Message>) -> String:
  match m:
    case None{}:
      ""
    case Some{+msg}:
      pong_for.fin(is_ping_cmd(classify(msg)), msg)

def pong_for(line: String) -> String:
  pong_for.on(parse(line))

# Tag a Maybe<Message> for the harness.
def show_cmd(c: Cmd) -> String:
  match c:
    case Unknown{}:
      "UNK"
    case Ping{}:
      "PING"
    case Pong{}:
      "PONG"
    case Join{}:
      "JOIN"
    case Part{}:
      "PART"
    case Kick{}:
      "KICK"
    case Quit{}:
      "QUIT"
    case Privmsg{}:
      "PRIVMSG"
    case Notice{}:
      "NOTICE"
    case Nick{}:
      "NICK"
    case Topic{}:
      "TOPIC"
    case Mode{}:
      "MODE"
    case Names{}:
      "NAMES"
    case Error{}:
      "ERROR"
    case Numeric{+code}:
      "NUM" ++ U32.show(code)

def show_params.go(+ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{+h, +t}:
      "|" ++ h ++ show_params.go(t)

def show_msg(+m: Message) -> String:
  match m:
    case Message{+nick, +cmd, +num, +ps}:
      nick ++ "!" ++ cmd ++ "#" ++ U32.show(num) ++ show_params.go(ps)

def show_parse.on(m: Maybe<&2, Message>) -> String:
  match m:
    case None{}:
      "NONE"
    case Some{+msg}:
      show_cmd(classify(msg)) ++ ":" ++ show_msg(msg)

def show_parse(line: String) -> String:
  show_parse.on(parse(line))
