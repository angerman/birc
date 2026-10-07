# birc IRC protocol core (pure). RFC 1459 §2.3.1 / RFC 2812 §2.3.1.
# Parse, classify, format. No IO here — the TimUI client and the
# headless harness drive this through fixtures and the wire.
import Base

def LINE_MAX() -> Nat:
  510n  # 512 including CRLF

type TypingStatus is Data:
  TypingActive{}
  TypingPaused{}
  TypingDone{}

type TypingEvent is Data:
  TypingSet{nick: String, target: String, status: TypingStatus}
  TypingClear{nick: String, target: String}
  TypingClearAll{nick: String}

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
  Cap{}
  Tagmsg{}
  Numeric{code: U32}

type Message is Data:
  Message{
    time: String,
    nick: String,
    command: String,
    numeric: U32,
    params: List<&2, String>
  }

def msg_time(+m: Message) -> String:
  match m:
    case Message{+time, _, _, _, _}:
      time

def msg_nick(+m: Message) -> String:
  match m:
    case Message{_, +nick, _, _, _}:
      nick

def msg_command(+m: Message) -> String:
  match m:
    case Message{_, _, +cmd, _, _}:
      cmd

def msg_num(+m: Message) -> U32:
  match m:
    case Message{_, _, _, +num, _}:
      num

def msg_params(+m: Message) -> List<&2, String>:
  match m:
    case Message{_, _, _, _, +ps}:
      ps


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

def take_until_space.cons(+h: Char, r: String & String) -> String & String:
  match r:
    case (tok, rest):
      (SCon{h, tok}, rest)

def take_until_space.fin(+h: Char, +t: String, r: String & String, space: Bool) -> String & String:
  match space:
    case True{}:
      ("", SCon{h, t})
    case False{}:
      take_until_space.cons(h, r)

def take_until_space(s: String) -> String & String:
  match s:
    case SNil{}:
      ("", "")
    case SCon{+h, +t}:
      take_until_space.fin(h, t, take_until_space(t), is_space(h))

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

def nick_of_prefix.keep(+h: Char, r: String, cut: Bool) -> String:
  match cut:
    case True{}:
      ""
    case False{}:
      SCon{h, r}

def nick_of_prefix(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+h, t}:
      nick_of_prefix.keep(h, nick_of_prefix(t), is_bang_or_at(h))

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

def starts_digit(s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{h, _}: Char.is_digit(h)

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
    case SCon{+h, +t}:
      skip_mirc_com(h, t, code_is(h, 44) && starts_digit(t))

def skip_mirc_d2.on(+h: Char, +t: String, dig: Bool) -> String:
  match dig:
    case True{}:
      skip_mirc_comma(t)
    case False{}:
      skip_mirc_com(h, t, code_is(h, 44) && starts_digit(t))

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

# 0x03 then optional 1–2 fg digits; comma belongs to the color code only
# when a foreground digit was eaten and a background digit follows it.
def skip_mirc(+s: String) -> String:
  skip_mirc_d1(s)

type SanPh is Data:
  SanStr{}
  SanHit{h: Char, color: Bool, drop: Bool}

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed sanitize_in
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

def proto_soh.keep(+h: Char, r: String, soh: Bool) -> String:
  match soh:
    case True{}:
      r
    case False{}:
      SCon{h, r}

def proto_soh(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      proto_soh.keep(h, proto_soh(t), code_is(h, 1))

# Canonical protocol atom for identity and policy comparisons: nicknames,
# channels, mode flags, verbs, and credential words. Framed lines keep
# their style bytes, so every comparison site normalizes through this one
# seam: sanitize exactly like inbound, then drop SOH as well. Bodies and
# history keep their own bytes; this equals the supported-style visible
# text on every input.
def proto_atom(+s: String) -> String:
  proto_soh(sanitize_in(s))

# Style-bearing inbound bytes: SOH (CTCP framing) plus the mIRC formatting
# set (toggles, color introducer, reset, monospace). The color introducer
# keeps its parameter bytes so the view decoder consumes exactly what
# skip_mirc would. Every other C0/DEL byte is dropped, including TAB/CR/LF,
# so BIRC2 fields and stored lines stay intact while chat styles survive.
def is_style_keep(+c: Char) -> Bool:
  +n = code_of(c)
  U32.is_eq(n, 1) || U32.is_eq(n, 2) || U32.is_eq(n, 3) || U32.is_eq(n, 15)
    || U32.is_eq(n, 17) || U32.is_eq(n, 22) || U32.is_eq(n, 29) || U32.is_eq(n, 30) || U32.is_eq(n, 31)

type KeepPh is Data:
  KeepStr{}
  KeepHit{h: Char, drop: Bool}

def sanitize_keep_style_go(fuel: Nat, ph: KeepPh, +s: String) -> String:
  match fuel:
    case 0n:
      SNil{}
    case 1n+p:
      match ph:
        case KeepStr{}:
          match s:
            case SNil{}:
              SNil{}
            case SCon{+hd, t}:
              sanitize_keep_style_go(p, KeepHit{hd, is_c0_drop(hd) && Bool.not(is_style_keep(hd))}, t)
        case KeepHit{h, drop}:
          match drop:
            case True{}:
              sanitize_keep_style_go(p, KeepStr{}, s)
            case False{}:
              SCon{h, sanitize_keep_style_go(p, KeepStr{}, s)}

def sanitize_keep_style(+s: String) -> String:
  sanitize_keep_style_go(Nat.add(1n, Nat.mul(4n, String.length(s))), KeepStr{}, s)

# ---- parse --------------------------------------------------------------

def push_param(ps: List<&2, String>, p: String) -> List<&2, String>:
  p <> ps

def params_done(ps: List<&2, String>) -> List<&2, String>:
  List.reverse(&2, String, ps)

type ParPhase is Data:
  ParFuel{}
  ParRest{}
  ParColon{}
  ParMid{}

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed parse_params.go
def parse_params.go(fuel: Nat, phase: ParPhase, s: String, ps: List<&2, String>, +h: Char, t: String, +rest: String, colon: Bool, pair: String & String) -> List<&2, String>:
  match fuel:
    case 0n:
      params_done(ps)
    case 1n+p:
      match phase:
        case ParFuel{}:
          parse_params.go(p, ParRest{}, drop_spaces(s), ps, h, t, rest, colon, pair)
        case ParRest{}:
          match s:
            case SNil{}:
              params_done(ps)
            case SCon{+hd, +tl}:
              parse_params.go(p, ParColon{}, "", ps, hd, tl, SCon{hd, tl}, is_colon(hd), pair)
        case ParColon{}:
          match colon:
            case True{}:
              params_done(push_param(ps, t))
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

def take_8_exact.on(+sub: String, is8: Bool) -> String:
  match is8:
    case True{}:
      sub
    case False{}:
      ""

def take_8_exact(+s: String) -> String:
  +sub = String.take(s, 8n)
  take_8_exact.on(sub, Nat.is_eq(String.length(sub), 8n))

def take_8_hhmmss.pick(is_t: Bool, +t: String, +rest: String) -> String:
  match is_t:
    case True{}:
      take_8_exact(t)
    case False{}:
      rest

def take_8_hhmmss.go(fuel: Nat, s: String) -> String:
  match fuel:
    case 0n:
      ""
    case 1n+p:
      match s:
        case SNil{}:
          ""
        case SCon{+h, +t}:
          take_8_hhmmss.pick(code_is(h, 84), t, take_8_hhmmss.go(p, t))

def extract_time_val(+val: String) -> String:
  take_8_hhmmss.go(Nat.add(1n, String.length(val)), val)

def parse_server_time.is_time(+tag: String, is_tm: Bool) -> String:
  match is_tm:
    case True{}:
      extract_time_val(String.drop(tag, 5n))
    case False{}:
      ""

def parse_server_time.on_tag(+tag: String, acc: String) -> String:
  match acc:
    case SNil{}:
      parse_server_time.is_time(tag, String.starts_with(tag, "time="))
    case SCon{+h, +t}:
      SCon{h, t}

def parse_server_time.step(acc: String, tag: String) -> String:
  parse_server_time.on_tag(tag, acc)

def parse_server_time(+tags: String) -> String:
  List.foldl(~&2, ~String, ~String, ~parse_server_time.step, String.split(tags, Chr{59}), "")

def parse_after_prefix.empty(empty: Bool, +time: String, +cmd: String, +more: String, +nick: String) -> Maybe<&2, Message>:
  match empty:
    case True{}:
      None{}
    case False{}:
      # Protocol verbs are never styled: normalize control bytes so framed
      # style-bearing lines dispatch exactly like stripped ones. Bodies keep
      # their bytes; identity params re-sanitize at their own use sites.
      +verb = proto_atom(cmd)
      +num = Bool.pick(U32, is_numeric3(verb), parse_numeric3(verb), 0)
      Some{Message{time, nick, verb, num, parse_params(more)}}

def parse_after_prefix.cmd2(+time: String, +cmd: String, more: String, +nick: String) -> Maybe<&2, Message>:
  parse_after_prefix.empty(String.is_empty(cmd), time, cmd, more, nick)

def parse_after_prefix.cmd(+time: String, pair: String & String, +nick: String) -> Maybe<&2, Message>:
  (cmd, more) = pair
  parse_after_prefix.cmd2(time, cmd, more, nick)

def parse_after_prefix.on_rest(+time: String, rest: String, nick: String) -> Maybe<&2, Message>:
  match rest:
    case SNil{}:
      None{}
    case _:
      parse_after_prefix.cmd(time, take_until_space(rest), nick)

def parse_after_prefix(+time: String, s: String, nick: String) -> Maybe<&2, Message>:
  parse_after_prefix.on_rest(time, drop_spaces(s), nick)

def parse_body.with_pfx(+time: String, pair: String & String) -> Maybe<&2, Message>:
  (pfx, more) = pair
  parse_after_prefix(time, more, nick_of_prefix(pfx))

def parse_body.colon(+time: String, colon: Bool, +h: Char, +t: String, +rest: String) -> Maybe<&2, Message>:
  match colon:
    case True{}:
      parse_body.with_pfx(time, take_until_space(t))
    case False{}:
      parse_after_prefix(time, rest, "")

def parse_body.tagged_on(+time: String, rest: String) -> Maybe<&2, Message>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+h, +t}:
      parse_body.colon(time, is_colon(h), h, t, SCon{h, t})

def parse_body.tagged(+time: String, s: String) -> Maybe<&2, Message>:
  parse_body.tagged_on(time, drop_spaces(s))

def parse_body.tags_pair(pair: String & String) -> Maybe<&2, Message>:
  match pair:
    case (tags, more):
      parse_body.tagged(parse_server_time(tags), more)

def parse_body.at(at: Bool, +h: Char, +t: String, +rest: String) -> Maybe<&2, Message>:
  match at:
    case True{}:
      parse_body.tags_pair(take_until_space(t))
    case False{}:
      parse_body.colon("", is_colon(h), h, t, rest)

def parse_body.on_rest(rest: String) -> Maybe<&2, Message>:
  match rest:
    case SNil{}:
      None{}
    case SCon{+h, +t}:
      parse_body.at(code_is(h, 64), h, t, SCon{h, t})

def parse_body(s: String) -> Maybe<&2, Message>:
  parse_body.on_rest(drop_spaces(s))

# Source inspection keeps the user/host markers that Message.nick omits.
# A bare nickname is ambiguous: only a server-shaped or configured source
# is a server here. Explicit nick!user@host sources always remain users.
def source_prefix.word(pair: String & String) -> String:
  match pair:
    case (prefix, _): prefix

def source_prefix.body(s: String) -> String:
  match s:
    case SCon{Chr{58}, t}: source_prefix.word(take_until_space(t))
    case _: ""

def source_prefix.tagged(pair: String & String) -> String:
  match pair:
    case (_, rest): source_prefix.body(drop_spaces(rest))

def source_prefix.on(tagged: Bool, +s: String) -> String:
  match tagged:
    case True{}: source_prefix.tagged(take_until_space(s))
    case False{}: source_prefix.body(s)

def source_prefix(+line: String) -> String:
  +body = drop_spaces(line)
  source_prefix.on(String.starts_with(body, "@"), body)

def source_is_server(+prefix: String, +server: String) -> Bool:
  Bool.not(String.is_empty(prefix) || String.contains(prefix, "!") || String.contains(prefix, "@"))
    && (String.contains(prefix, ".") || ieq(prefix, server))

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
def is_crlf(+c: Char) -> Bool:
  code_is(c, 13) || code_is(c, 10)

def has_crlf(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+h, t}:
      Bool.or(is_crlf(h), has_crlf(t))

def strip_ctl.keep(+h: Char, r: String, drop: Bool) -> String:
  match drop:
    case True{}:
      r
    case False{}:
      SCon{h, r}

def strip_ctl(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      strip_ctl.keep(h, strip_ctl(t), is_crlf(h))

def parse(line: String) -> Maybe<&2, Message>:
  parse_body(strip_cr(line))

# ---- IRCv3 client-only +typing tag -------------------------------------

def typing_status.done(+value: String, done: Bool) -> Maybe<&2, TypingStatus>:
  match done:
    case True{}:
      Some{TypingDone{}}
    case False{}:
      None{}

def typing_status.paused(+value: String, paused: Bool) -> Maybe<&2, TypingStatus>:
  match paused:
    case True{}:
      Some{TypingPaused{}}
    case False{}:
      typing_status.done(value, String.eq(value, "done"))

def typing_status.active(+value: String, active: Bool) -> Maybe<&2, TypingStatus>:
  match active:
    case True{}:
      Some{TypingActive{}}
    case False{}:
      typing_status.paused(value, String.eq(value, "paused"))

def typing_status(+value: String) -> Maybe<&2, TypingStatus>:
  typing_status.active(value, String.eq(value, "active"))

def typing_tag.one(+tag: String, hit: Bool) -> Maybe<&2, TypingStatus>:
  match hit:
    case True{}:
      typing_status(String.drop(tag, 8n))
    case False{}:
      None{}

def typing_tags.go(xs: List<&2, String>, found: Maybe<&2, TypingStatus>) -> Maybe<&2, TypingStatus>:
  match xs found:
    case _ Some{status}:
      Some{status}
    case Nil{} None{}:
      None{}
    case Con{+tag, rest} None{}:
      typing_tags.go(rest, typing_tag.one(tag, String.starts_with(tag, "+typing=")))

def typing_tag(+tags: String) -> Maybe<&2, TypingStatus>:
  typing_tags.go(String.split(tags, Chr{59}), None{})

def raw_tags.pair(pair: String & String) -> String:
  match pair:
    case (tags, _):
      tags

def raw_tags.at(+tail: String, at: Bool) -> String:
  match at:
    case True{}:
      raw_tags.pair(take_until_space(tail))
    case False{}:
      ""

def raw_tags.clean(+line: String) -> String:
  match line:
    case SNil{}:
      ""
    case SCon{+h, +tail}:
      raw_tags.at(tail, code_is(h, 64))

def raw_tags(+line: String) -> String:
  raw_tags.clean(strip_cr(line))

# ---- classify -----------------------------------------------------------

type ClsRow is Data:
  ClsRow{name: String, cmd: Cmd}

def cls_rows() -> List<&2, ClsRow>:
  ClsRow{"PING", Ping{}} <> ClsRow{"PONG", Pong{}} <> ClsRow{"JOIN", Join{}} <> ClsRow{"PART", Part{}} <> ClsRow{"KICK", Kick{}} <> ClsRow{"QUIT", Quit{}} <> ClsRow{"PRIVMSG", Privmsg{}} <> ClsRow{"NOTICE", Notice{}} <> ClsRow{"NICK", Nick{}} <> ClsRow{"TOPIC", Topic{}} <> ClsRow{"MODE", Mode{}} <> ClsRow{"NAMES", Names{}} <> ClsRow{"ERROR", Error{}} <> ClsRow{"CAP", Cap{}} <> ClsRow{"TAGMSG", Tagmsg{}} <> Nil{}

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
    case Message{_, _, +cmd, +num, _}:
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
    case Message{_, _, _, _, +ps}:
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
    case Message{_, _, _, _, ps}:
      msg_last_xs(ps)

# Typing events are separate from normal client feed. This lets Session clear
# typing state even when a message is muted and omitted from scrollback.
def typing_target.pick(+nick: String, +target: String, channel: Bool) -> String:
  match channel:
    case True{}:
      chan_target(target)
    case False{}:
      nick

def typing_target(+nick: String, +target: String) -> String:
  typing_target.pick(nick, target, starts_channel(target))

def typing_set_event(+nick: String, +target: String, status: TypingStatus) -> TypingEvent:
  match status:
    case TypingDone{}:
      TypingClear{nick, typing_target(nick, target)}
    case TypingActive{}:
      TypingSet{nick, typing_target(nick, target), TypingActive{}}
    case TypingPaused{}:
      TypingSet{nick, typing_target(nick, target), TypingPaused{}}

def typing_tagmsg(+m: Message, status: TypingStatus) -> TypingEvent:
  typing_set_event(msg_nick(m), msg_param(m, 0n), status)

def typing_from_tagmsg(+m: Message, status: Maybe<&2, TypingStatus>) -> Maybe<&2, TypingEvent>:
  match status:
    case Some{st}:
      Some{typing_tagmsg(m, st)}
    case None{}:
      None{}

def typing_from_kick(+m: Message) -> TypingEvent:
  TypingClear{msg_param(m, 1n), chan_target(msg_param(m, 0n))}

def typing_from_message(+m: Message) -> TypingEvent:
  typing_set_event(msg_nick(m), msg_param(m, 0n), TypingDone{})

def typing_event_cmd(+m: Message, status: Maybe<&2, TypingStatus>, c: Cmd) -> Maybe<&2, TypingEvent>:
  match c:
    case Tagmsg{}:
      typing_from_tagmsg(m, status)
    case Privmsg{}:
      Some{typing_from_message(m)}
    case Notice{}:
      Some{typing_from_message(m)}
    case Part{}:
      Some{TypingClear{msg_nick(m), chan_target(msg_param(m, 0n))}}
    case Kick{}:
      Some{typing_from_kick(m)}
    case Quit{}:
      Some{TypingClearAll{msg_nick(m)}}
    case Nick{}:
      Some{TypingClearAll{msg_nick(m)}}
    case _:
      None{}

def typing_event_msg(+m: Message, status: Maybe<&2, TypingStatus>) -> Maybe<&2, TypingEvent>:
  typing_event_cmd(m, status, classify(m))

def typing_event_parsed(m: Maybe<&2, Message>, status: Maybe<&2, TypingStatus>) -> Maybe<&2, TypingEvent>:
  match m:
    case None{}:
      None{}
    case Some{msg}:
      typing_event_msg(msg, status)

def typing_event(+line: String) -> Maybe<&2, TypingEvent>:
  +clean = strip_cr(line)
  typing_event_parsed(parse(clean), typing_tag(raw_tags(clean)))

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

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed clamp_line.go
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
  U32.is_eq(num, 433) || U32.is_eq(num, 437)

def is_433_msg(+m: Message) -> Bool:
  match m:
    case Message{_, _, _, +num, _}:
      is_433_num(num)

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

def format_cap_req(+caps: String) -> String:
  "CAP REQ :" ++ caps

def format_cap_end() -> String:
  "CAP END"

def format_authenticate(+payload: String) -> String:
  "AUTHENTICATE " ++ payload

type SaslEvent is Data:
  SaslAck{}
  SaslNak{}
  SaslPlus{}
  SaslSuccess{}
  SaslFailure{}
  SaslRegistered{}
  SaslOther{}

def has_sasl_cap(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{+h, t}:
      ieq(h, "sasl") || String.starts_with(h, "sasl=") || has_sasl_cap(t)

def sasl_event.cap(+m: Message) -> SaslEvent:
  Bool.pick(SaslEvent, has_sasl_cap(String.split(msg_param(m, 2n), Chr{32})),
    Bool.pick(SaslEvent, ieq(msg_param(m, 1n), "ACK"), SaslAck{},
      Bool.pick(SaslEvent, ieq(msg_param(m, 1n), "NAK"), SaslNak{}, SaslOther{})), SaslOther{})

def sasl_event(+m: Message) -> SaslEvent:
  Bool.pick(SaslEvent, ieq(msg_command(m), "CAP"), sasl_event.cap(m),
    Bool.pick(SaslEvent, ieq(msg_command(m), "AUTHENTICATE") && String.eq(msg_param(m, 0n), "+") && Nat.is_eq(List.length(&2, String, msg_params(m)), 1n), SaslPlus{},
      Bool.pick(SaslEvent, U32.is_eq(msg_num(m), 903), SaslSuccess{},
        Bool.pick(SaslEvent, U32.is_eq(msg_num(m), 902) || (U32.is_ge(msg_num(m), 904) && U32.is_le(msg_num(m), 907)), SaslFailure{},
          Bool.pick(SaslEvent, U32.is_eq(msg_num(m), 1), SaslRegistered{}, SaslOther{})))))

def sasl_event.line(m: Maybe<&2, Message>) -> SaslEvent:
  match m:
    case None{}: SaslOther{}
    case Some{msg}: sasl_event(msg)

def is_cap_ack_sasl.event(e: SaslEvent) -> Bool:
  match e:
    case SaslAck{}: True{}
    case _: False{}

def is_cap_ack_sasl(+line: String) -> Bool:
  is_cap_ack_sasl.event(sasl_event.line(parse(line)))

def is_authenticate_plus.event(e: SaslEvent) -> Bool:
  match e:
    case SaslPlus{}: True{}
    case _: False{}

def is_authenticate_plus(+line: String) -> Bool:
  is_authenticate_plus.event(sasl_event.line(parse(line)))

def is_sasl_success.event(e: SaslEvent) -> Bool:
  match e:
    case SaslSuccess{}: True{}
    case _: False{}

def is_sasl_success(+line: String) -> Bool:
  is_sasl_success.event(sasl_event.line(parse(line)))

def is_sasl_fail.event(e: SaslEvent) -> Bool:
  match e:
    case SaslFailure{}: True{}
    case _: False{}

def is_sasl_fail(+line: String) -> Bool:
  is_sasl_fail.event(sasl_event.line(parse(line)))

def is_cap_nak.event(e: SaslEvent) -> Bool:
  match e:
    case SaslNak{}: True{}
    case _: False{}

def is_cap_nak(+line: String) -> Bool:
  is_cap_nak.event(sasl_event.line(parse(line)))

def parse_u32_read.on(m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case None{}: None{}
    case Some{n}: Some{n}

def parse_u32_read(+s: String) -> Maybe<&2, U32>:
  parse_u32_read.on(U32.read(s))

def extract_lag_token.on(+tok: String, is_birc: Bool) -> Maybe<&2, U32>:
  match is_birc:
    case True{}:
      parse_u32_read(String.drop(tok, 5n))
    case False{}:
      None{}

def extract_lag_token(+tok: String) -> Maybe<&2, U32>:
  extract_lag_token.on(tok, String.starts_with(tok, "birc_"))

def extract_pong_lag.on(cand: Maybe<&2, U32>, cont: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match cand:
    case Some{n}: Some{n}
    case None{}: cont

def extract_pong_lag.ps(ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Nil{}:
      None{}
    case Con{+h, t}:
      extract_pong_lag.on(extract_lag_token(h), extract_pong_lag.ps(t))

def extract_pong_lag.is_pong(+ps: List<&2, String>, is_p: Bool) -> Maybe<&2, U32>:
  match is_p:
    case True{}: extract_pong_lag.ps(ps)
    case False{}: None{}

def extract_pong_lag(+m: Message) -> Maybe<&2, U32>:
  match m:
    case Message{_, _, +cmd, _, +ps}:
      extract_pong_lag.is_pong(ps, ieq(cmd, "PONG"))

def extract_pong_lag_line.on(m: Maybe<&2, Message>) -> Maybe<&2, U32>:
  match m:
    case None{}: None{}
    case Some{msg}: extract_pong_lag(msg)

def extract_pong_lag_line(+line: String) -> Maybe<&2, U32>:
  extract_pong_lag_line.on(parse(line))

def server_time_sample_ok() -> Bool:
  String.eq(parse_server_time("time=2026-09-28T17:40:27.123Z"), "17:40:27")
    && String.eq(parse_server_time("account=u;time=2023-01-02T03:04:05Z;foo=1"), "03:04:05")
