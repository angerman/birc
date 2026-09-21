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
  Char.to_u32(c)

def code_is(+c: Char, +k: U32) -> Bool:
  U32.is_eq(code_of(c), k)

def is_space(+c: Char) -> Bool:
  code_is(c, 32)

def is_colon(+c: Char) -> Bool:
  code_is(c, 58)

def is_bang_or_at(+c: Char) -> Bool:
  code_is(c, 33) || code_is(c, 64)



# ---- string helpers -----------------------------------------------------

def drop_spaces(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, +t}:
      Bool.pick(String, is_space(h), drop_spaces(t), SCon{h, t})

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

# RFC 1459 casemap: ASCII upper, then []\~ ↔ {}|^.
def rfc1459_code.tilde(+n: U32, hit: Bool) -> U32:
  match hit:
    case True{}:
      94
    case False{}:
      n

def rfc1459_code.rb(+n: U32, hit: Bool) -> U32:
  match hit:
    case True{}:
      125
    case False{}:
      rfc1459_code.tilde(n, U32.is_eq(n, 126))

def rfc1459_code.bs(+n: U32, hit: Bool) -> U32:
  match hit:
    case True{}:
      124
    case False{}:
      rfc1459_code.rb(n, U32.is_eq(n, 93))

def rfc1459_code.lb(+n: U32, hit: Bool) -> U32:
  match hit:
    case True{}:
      123
    case False{}:
      rfc1459_code.bs(n, U32.is_eq(n, 92))

def rfc1459_code(+n: U32) -> U32:
  rfc1459_code.lb(n, U32.is_eq(n, 91))

def rfc1459_char(+c: Char) -> Char:
  match c:
    case Chr{n}:
      Chr{rfc1459_code(n)}

def rfc1459.go(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      SCon{rfc1459_char(h), rfc1459.go(t)}

def rfc1459(+s: String) -> String:
  rfc1459.go(String.to_upper(s))

def ieq(+a: String, +b: String) -> Bool:
  String.eq(rfc1459(a), rfc1459(b))

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
      Char.is_digit(a) && Char.is_digit(b) && Char.is_digit(c)
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

def parse_params(+s: String) -> List<&2, String>:
  parse_params.go(
    Nat.add(1n, Nat.mul(4n, String.length(s))),
    ParFuel{},
    s,
    Nil{},
    Chr{0},
    "",
    "",
    False{},
    ("", "")
  )

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

# Drop CR/LF so outbound cannot inject extra IRC lines.
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

# Inbound: drop C0 except SOH (CTCP), drop DEL, strip mIRC colour (0x03+digits).
def is_c0_drop(+c: Char) -> Bool:
  +n = code_of(c)
  (U32.is_lt(n, 32) && Bool.not(U32.is_eq(n, 1))) || U32.is_eq(n, 127)

def skip_one_digit_on(+h: Char, t: String, dig: Bool) -> String:
  match dig:
    case True{}:
      t
    case False{}:
      SCon{h, t}

def skip_one_digit(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      skip_one_digit_on(h, t, Char.is_digit(h))

def skip_mirc_com(+h: Char, t: String, comma: Bool) -> String:
  match comma:
    case True{}:
      skip_one_digit(skip_one_digit(t))
    case False{}:
      SCon{h, t}

def skip_mirc_comma(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      skip_mirc_com(h, t, code_is(h, 44))

def skip_mirc_d2.on(+h: Char, t: String, dig: Bool) -> String:
  match dig:
    case True{}:
      skip_mirc_comma(t)
    case False{}:
      skip_mirc_com(h, t, code_is(h, 44))

def skip_mirc_d2(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      skip_mirc_d2.on(h, t, Char.is_digit(h))

def skip_mirc_d1.on(+h: Char, t: String, dig: Bool) -> String:
  match dig:
    case True{}:
      skip_mirc_d2(t)
    case False{}:
      SCon{h, t}

def skip_mirc_d1(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      skip_mirc_d1.on(h, t, Char.is_digit(h))

# 0x03 then optional 1–2 fg digits, then comma+bg only if a digit was eaten.
def skip_mirc(+s: String) -> String:
  skip_mirc_d1(s)

type SanPh is Data:
  SanStr{}
  SanHit{h: Char, color: Bool, drop: Bool}

def sanitize_in_go(fuel: Nat, ph: SanPh, +s: String) -> String:
  match fuel:
    case 0n:
      SNil{}
    case 1n+p:
      match ph:
        case SanStr{}:
          match s:
            case SNil{}:
              SNil{}
            case SCon{+hd, t}:
              sanitize_in_go(p, SanHit{hd, code_is(hd, 3), is_c0_drop(hd)}, t)
        case SanHit{h, color, drop}:
          match color:
            case True{}:
              sanitize_in_go(p, SanStr{}, skip_mirc(s))
            case False{}:
              match drop:
                case True{}:
                  sanitize_in_go(p, SanStr{}, s)
                case False{}:
                  SCon{h, sanitize_in_go(p, SanStr{}, s)}

def sanitize_in(+s: String) -> String:
  sanitize_in_go(Nat.add(1n, Nat.mul(4n, String.length(s))), SanStr{}, s)

def sanitize_in_ok() -> Bool:
  String.eq(sanitize_in("ab" ++ SCon{Chr{31}, "cd"}), "abcd")
    && String.eq(sanitize_in("x" ++ SCon{Chr{3}, "04y"}), "xy")
    && String.eq(sanitize_in(SCon{Chr{1}, "ACTION"}), SCon{Chr{1}, "ACTION"})
    && String.eq(sanitize_in(SCon{Chr{3}, ",hello"}), ",hello")
    && String.eq(sanitize_in(SCon{Chr{3}, "4,hello"}), "hello")
    && String.eq(sanitize_in(SCon{Chr{3}, "04,02hello"}), "hello")

def parse(line: String) -> Maybe<&2, Message>:
  parse_body(strip_cr(line))

# ---- classify -----------------------------------------------------------

type ClsRow is Data:
  ClsRow{name: String, cmd: Cmd}

def cls_rows() -> List<&2, ClsRow>:
  ClsRow{"PING", Ping{}} <> ClsRow{"PONG", Pong{}} <> ClsRow{"JOIN", Join{}} <> ClsRow{"PART", Part{}} <> ClsRow{"KICK", Kick{}} <> ClsRow{"QUIT", Quit{}} <> ClsRow{"PRIVMSG", Privmsg{}} <> ClsRow{"NOTICE", Notice{}} <> ClsRow{"NICK", Nick{}} <> ClsRow{"TOPIC", Topic{}} <> ClsRow{"MODE", Mode{}} <> ClsRow{"NAMES", Names{}} <> ClsRow{"ERROR", Error{}} <> Nil{}

def cls_lookup(xs: List<&2, ClsRow>, +cmd: String) -> Cmd:
  match xs:
    case Nil{}:
      Unknown{}
    case Con{row, t}:
      match row:
        case ClsRow{+name, +c}:
          Bool.pick(Cmd, ieq(name, cmd), c, cls_lookup(t, cmd))

def cls_verb(num: Bool, +cmd: String, +code: U32) -> Cmd:
  match num:
    case True{}:
      Numeric{code}
    case False{}:
      cls_lookup(cls_rows(), cmd)

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

def msg_last_xs(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+h, t}:
      match t:
        case Nil{}:
          h
        case Con{_, _}:
          msg_last_xs(t)

def msg_last(+m: Message) -> String:
  match m:
    case Message{_, _, _, ps}:
      msg_last_xs(ps)

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

def utf8_w4(+n: U32, hi: Bool) -> Nat:
  match hi:
    case True{}:
      4n
    case False{}:
      3n

def utf8_w2(+n: U32, two: Bool) -> Nat:
  match two:
    case True{}:
      2n
    case False{}:
      utf8_w4(n, U32.is_ge(n, 65536))

def utf8_w1(+n: U32, one: Bool) -> Nat:
  match one:
    case True{}:
      1n
    case False{}:
      utf8_w2(n, U32.is_lt(n, 2048))

def utf8_w(+c: Char) -> Nat:
  +n = code_of(c)
  utf8_w1(n, U32.is_lt(n, 128))

def utf8_len.go(+s: String, acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{+h, t}:
      utf8_len.go(t, Nat.add(acc, utf8_w(h)))

def utf8_len(+s: String) -> Nat:
  utf8_len.go(s, 0n)

type ClPh is Data:
  ClStr{}
  ClFit{h: Char, w: Nat, too: Bool}

def clamp_line.go(fuel: Nat, ph: ClPh, +n: Nat, s: String, acc: String) -> String:
  match fuel:
    case 0n:
      String.reverse(acc)
    case 1n+p:
      match ph:
        case ClStr{}:
          match s:
            case SNil{}:
              String.reverse(acc)
            case SCon{+h, t}:
              +w = utf8_w(h)
              clamp_line.go(p, ClFit{h, w, Nat.is_lt(n, w)}, n, t, acc)
        case ClFit{h, w, too}:
          match too:
            case True{}:
              String.reverse(acc)
            case False{}:
              clamp_line.go(p, ClStr{}, Nat.sub(n, w), s, SCon{h, acc})

def clamp_line(+s: String) -> String:
  clamp_line.go(Nat.add(1n, Nat.mul(2n, String.length(s))), ClStr{}, LINE_MAX(), s, SNil{})

def line_ok(s: String) -> Bool:
  Nat.is_le(utf8_len(s), LINE_MAX())

def stars.go(n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      "x" ++ stars.go(p)

def clamp_samples_ok() -> Bool:
  line_ok(clamp_line(""))
    && line_ok(clamp_line("hi"))
    && line_ok(clamp_line(stars.go(80n)))
    && line_ok(clamp_line(stars.go(600n)))

def strip_ctl_nocr_ok() -> Bool:
  String.eq(strip_ctl("a" ++ SCon{Chr{13}, "b" ++ SCon{Chr{10}, "c"}}), "abc")

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

def is_433_num(+num: U32) -> Bool:
  U32.is_eq(num, 433)

def is_433_msg(+m: Message) -> Bool:
  match m:
    case Message{_, _, +num, _}:
      is_433_num(num)

def is_433_on(m: Maybe<&2, Message>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{+msg}:
      is_433_msg(msg)

def is_433_line(line: String) -> Bool:
  is_433_on(parse(line))

def nick433_retry(+m: Message, +nick: String) -> Bool:
  is_433_msg(m) && ieq(msg_param(m, 1n), nick)

def nick433_for.hit(+nick: String, hit: Bool) -> List<&2, String>:
  match hit:
    case False{}:
      Nil{}
    case True{}:
      format_nick(nick ++ "_") <> Nil{}

def nick433_for.got(m: Maybe<&2, Message>, +nick: String) -> List<&2, String>:
  match m:
    case None{}:
      Nil{}
    case Some{+msg}:
      nick433_for.hit(nick, nick433_retry(msg, nick))

def nick433_for(+line: String, +nick: String) -> List<&2, String>:
  nick433_for.got(parse(line), nick)

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
