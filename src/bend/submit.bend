# Composer submit (M2). Pure: Client -> input -> (Client & List<&2, String>) outbound.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./args.bend as Args

def empty_out() -> List<&2, String>:
  Nil{}

def one_out(+s: String) -> List<&2, String>:
  Irc.clamp_line(Irc.strip_ctl(s)) <> Nil{}

# ---- take_verb / take_word (phase+fuel; no match on computed) -----------

type VerbPhase is Data:
  VbRead{}
  VbDecide{}

def take_verb.go(fuel: Nat, phase: VerbPhase, +s: String, +acc: String, +h: Char, space: Bool) -> String & String:
  match fuel:
    case 0n:
      (String.reverse(acc), s)
    case 1n+p:
      match phase:
        case VbRead{}:
          match s:
            case SNil{}:
              (String.reverse(acc), SNil{})
            case SCon{+hd, t}:
              take_verb.go(p, VbDecide{}, t, acc, hd, Irc.is_space(hd))
        case VbDecide{}:
          match space:
            case True{}:
              (String.reverse(acc), s)
            case False{}:
              take_verb.go(p, VbRead{}, s, SCon{h, acc}, h, False{})

def take_verb(+s: String) -> String & String:
  take_verb.go(Nat.add(1n, Nat.mul(2n, String.length(s))), VbRead{}, s, "", Chr{0}, False{})

def skip_slash.on(+h: Char, +t: String, slash: Bool) -> String:
  match slash:
    case True{}:
      t
    case False{}:
      SCon{h, t}

def skip_slash(+s: String) -> String:
  match s:
    case SCon{+h, t}:
      skip_slash.on(h, t, Irc.code_is(h, 47))
    case SNil{}:
      SNil{}

def active_idx(+cl: Cl.Client) -> Nat:
  match cl:
    case Cl.Client{_, _, _, +active, _}:
      active

def active_name.on(+got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}:
      "server"
    case Some{b}:
      match b:
        case Cl.Buffer{+name, _, _, _, _, _}:
          name

def active_name(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, +active, _}:
      active_name.on(Cl.nth_buf(bufs, active))

def echo_self(+cl: Cl.Client, +bi: Nat, +body: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, _, _, _, _}:
      Cl.client_log(cl, bi, Cl.Self{}, Feed.fmt_msg(nick, body))

def echo_action(+cl: Cl.Client, +bi: Nat, +body: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, _, _, _, _}:
      Cl.client_log(cl, bi, Cl.Action{}, Feed.fmt_action(nick, body))

def echo_err(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, active_idx(cl), Cl.Error{}, msg)

def echo_sys(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, 0n, Cl.System{}, msg)

def echo_err_server(+cl: Cl.Client, +msg: String) -> Cl.Client:
  Cl.client_log(cl, 0n, Cl.Error{}, msg)

# ---- /join --------------------------------------------------------------

def submit_join.got.on(+cl2: Cl.Client, +bi: Nat, +rest: String, +nick: String) -> Cl.Client & List<&2, String>:
  (Cl.set_active(Cl.nick_add_idx(cl2, bi, nick), bi), one_out(Irc.format_join(rest)))

def submit_join.got.cl(+cl2: Cl.Client, +bi: Nat, +rest: String) -> Cl.Client & List<&2, String>:
  match cl2:
    case Cl.Client{+nick, _, _, _, _}:
      submit_join.got.on(cl2, bi, rest, nick)

def submit_join.got(pair: Cl.Client & Maybe<&2, Nat>, +rest: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      submit_join.got.cl(cl2, bi, rest)

def submit_join.on(+cl: Cl.Client, +rest: String, chan: Bool) -> Cl.Client & List<&2, String>:
  match chan:
    case False{}:
      (echo_err(cl, "usage: /join #chan"), empty_out())
    case True{}:
      submit_join.got(Cl.buf_get(cl, rest, True{}, True{}), rest)

def submit_join(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_join.on(cl, rest, Irc.starts_channel(rest))

# ---- /part --------------------------------------------------------------

def submit_part.chan(+cl: Cl.Client, +rest: String, empty: Bool) -> String:
  match empty:
    case True{}:
      active_name(cl)
    case False{}:
      rest

def submit_part.drop.fin(+nick: String, +server: String, +bufs: List<&2, Cl.Buffer>, +active: Nat, +now: String, +chan: String, +bi: Nat) -> Cl.Client & List<&2, String>:
  (Cl.drop_buf(Cl.Client{nick, server, bufs, active, now}, bi), one_out(Irc.format_part(chan)))

def submit_part.drop.pick(+nick: String, +server: String, +bufs: List<&2, Cl.Buffer>, +active: Nat, +now: String, +chan: String, +bi: Nat, is_server: Bool) -> Cl.Client & List<&2, String>:
  match is_server:
    case True{}:
      (Cl.Client{nick, server, bufs, active, now}, one_out(Irc.format_part(chan)))
    case False{}:
      submit_part.drop.fin(nick, server, bufs, active, now, chan, bi)

def submit_part.drop.body(+cl: Cl.Client, +chan: String, +bi: Nat, is_server: Bool) -> Cl.Client & List<&2, String>:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now}:
      submit_part.drop.pick(nick, server, bufs, active, now, chan, bi, is_server)

def submit_part.drop(+cl: Cl.Client, +chan: String, +bi: Nat) -> Cl.Client & List<&2, String>:
  submit_part.drop.body(cl, chan, bi, Nat.is_eq(bi, 0n))

def submit_part.on(+cl: Cl.Client, +chan: String, found: Maybe<&2, Nat>) -> Cl.Client & List<&2, String>:
  match found:
    case None{}:
      (cl, one_out(Irc.format_part(chan)))
    case Some{+bi}:
      submit_part.drop(cl, chan, bi)

def submit_part.with(+cl: Cl.Client, +chan: String) -> Cl.Client & List<&2, String>:
  submit_part.on(cl, chan, Cl.buf_find(cl, chan))

def submit_part.empty.on(+cl: Cl.Client, +rest: String, server: Bool) -> Cl.Client & List<&2, String>:
  match server:
    case True{}:
      (echo_err(cl, "usage: /part #chan"), empty_out())
    case False{}:
      submit_part.with(cl, active_name(cl))

def submit_part.empty(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      submit_part.empty.on(cl, rest, Nat.is_eq(active_idx(cl), 0n))
    case False{}:
      submit_part.with(cl, rest)

def submit_part(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_part.empty(cl, rest, String.is_empty(rest))

# ---- /msg ---------------------------------------------------------------

type WordPhase is Data:
  WdRead{}
  WdDecide{}

def take_word.go(fuel: Nat, phase: WordPhase, +s: String, +acc: String, +h: Char, space: Bool) -> String & String:
  match fuel:
    case 0n:
      (String.reverse(acc), s)
    case 1n+p:
      match phase:
        case WdRead{}:
          match s:
            case SNil{}:
              (String.reverse(acc), SNil{})
            case SCon{+hd, t}:
              take_word.go(p, WdDecide{}, t, acc, hd, Irc.is_space(hd))
        case WdDecide{}:
          match space:
            case True{}:
              (String.reverse(acc), Irc.drop_spaces(s))
            case False{}:
              take_word.go(p, WdRead{}, s, SCon{h, acc}, h, False{})

def take_word(+s: String) -> String & String:
  take_word.go(Nat.add(1n, Nat.mul(2n, String.length(s))), WdRead{}, s, "", Chr{0}, False{})

def submit_msg.got(pair: Cl.Client & Maybe<&2, Nat>, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match pair:
    case (cl2, None{}):
      (cl2, empty_out())
    case (cl2, Some{+bi}):
      +cl3 = Cl.set_active(echo_self(cl2, bi, body), bi)
      (cl3, one_out(Irc.format_privmsg(who, body)))

def submit_msg.bad(+cl: Cl.Client, bad: Bool, +who: String, +body: String) -> Cl.Client & List<&2, String>:
  match bad:
    case True{}:
      (echo_err(cl, "usage: /msg nick text"), empty_out())
    case False{}:
      submit_msg.got(Cl.buf_get(cl, who, False{}, True{}), who, body)

def submit_msg.words(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (+who, +body):
      submit_msg.bad(cl, String.is_empty(who) || String.is_empty(body), who, body)

def submit_msg(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_msg.words(cl, take_word(rest))

# ---- /nick /me /quit /unknown -------------------------------------------

def submit_nick.on(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /nick name"), empty_out())
    case False{}:
      (cl, one_out(Irc.format_nick(rest)))

def submit_nick(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_nick.on(cl, rest, String.is_empty(rest))

def ctcp_action(+rest: String) -> String:
  SCon{Chr{1}, "ACTION " ++ rest ++ SCon{Chr{1}, SNil{}}}

def submit_me.chan(+cl: Cl.Client, +rest: String, on_server: Bool) -> Cl.Client & List<&2, String>:
  match on_server:
    case True{}:
      (echo_err(cl, "not in a channel — /join #chan first"), empty_out())
    case False{}:
      +tgt = active_name(cl)
      +bi = active_idx(cl)
      (echo_action(cl, bi, rest), one_out(Irc.format_privmsg(tgt, ctcp_action(rest))))

def submit_me.on(+cl: Cl.Client, +rest: String, empty: Bool) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (echo_err(cl, "usage: /me action"), empty_out())
    case False{}:
      submit_me.chan(cl, rest, Nat.is_eq(active_idx(cl), 0n))

def submit_me(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  submit_me.on(cl, rest, String.is_empty(rest))

def submit_quit.reason(+rest: String, empty: Bool) -> String:
  match empty:
    case True{}:
      "birc"
    case False{}:
      rest

def submit_quit(+cl: Cl.Client, +rest: String) -> Cl.Client & List<&2, String>:
  (cl, one_out(Irc.format_quit(submit_quit.reason(rest, String.is_empty(rest)))))

def submit_unknown(+cl: Cl.Client, +verb: String) -> Cl.Client & List<&2, String>:
  (echo_err(cl, "unknown command: /" ++ verb), empty_out())

# /connect is not a submit arm. Session intercepts via submit_is_connect
# and connect_apply (Dial). connect_parse stays for that path.

type Conn is Data:
  ConnBad{}
  ConnOk{host: String, port: U32}

def connect_port.range(+host: String, +p: U32, bad: Bool) -> Conn:
  match bad:
    case True{}:
      ConnBad{}
    case False{}:
      ConnOk{host, p}

def connect_port.num(+host: String, got: Maybe<&2, U32>) -> Conn:
  match got:
    case None{}:
      ConnBad{}
    case Some{+p}:
      connect_port.range(host, p, U32.is_eq(p, 0) || U32.is_gt(p, Args.PORT_MAX()))

def connect_port.on(+host: String, +more: String, empty: Bool) -> Conn:
  match empty:
    case True{}:
      ConnOk{host, 6667}
    case False{}:
      connect_port.num(host, U32.read(more))

def connect_parse.host(+host: String, +more: String, empty: Bool) -> Conn:
  match empty:
    case True{}:
      ConnBad{}
    case False{}:
      connect_port.on(host, more, String.is_empty(more))

def connect_parse.words(pair: String & String) -> Conn:
  match pair:
    case (+host, +more):
      connect_parse.host(host, more, String.is_empty(host))

def connect_parse(+rest: String) -> Conn:
  connect_parse.words(take_word(Irc.drop_spaces(rest)))

type Slash is Data:
  Join{}
  Part{}
  Msg{}
  Nick{}
  Me{}
  Quit{}
  Unknown{}

type SlashRow is Data:
  SlashRow{name: String, cmd: Slash}

def slash_rows() -> List<&2, SlashRow>:
  SlashRow{"join", Join{}} <> SlashRow{"part", Part{}} <> SlashRow{"msg", Msg{}} <> SlashRow{"nick", Nick{}} <> SlashRow{"me", Me{}} <> SlashRow{"quit", Quit{}} <> Nil{}

def slash_lookup(xs: List<&2, SlashRow>, +verb: String) -> Slash:
  match xs:
    case Nil{}:
      Unknown{}
    case Con{row, t}:
      match row:
        case SlashRow{+name, +c}:
          Bool.pick(Slash, Irc.ieq(name, verb), c, slash_lookup(t, verb))

def slash_of(+verb: String) -> Slash:
  slash_lookup(slash_rows(), verb)

def submit_cmd.do(+cl: Cl.Client, +verb: String, +rest: String, cmd: Slash) -> Cl.Client & List<&2, String>:
  match cmd:
    case Join{}:
      submit_join(cl, rest)
    case Part{}:
      submit_part(cl, rest)
    case Msg{}:
      submit_msg(cl, rest)
    case Nick{}:
      submit_nick(cl, rest)
    case Me{}:
      submit_me(cl, rest)
    case Quit{}:
      submit_quit(cl, rest)
    case Unknown{}:
      submit_unknown(cl, verb)

def submit_cmd(+cl: Cl.Client, +verb: String, +rest: String) -> Cl.Client & List<&2, String>:
  submit_cmd.do(cl, verb, rest, slash_of(verb))

def submit_plain.on(+cl: Cl.Client, +input: String, on_server: Bool) -> Cl.Client & List<&2, String>:
  match on_server:
    case True{}:
      (echo_err(cl, "not in a channel — /join #chan first"), empty_out())
    case False{}:
      +tgt = active_name(cl)
      +bi = active_idx(cl)
      (echo_self(cl, bi, input), one_out(Irc.format_privmsg(tgt, input)))

def submit_plain(+cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  submit_plain.on(cl, input, Nat.is_eq(active_idx(cl), 0n))

def submit.verb(+cl: Cl.Client, pair: String & String) -> Cl.Client & List<&2, String>:
  match pair:
    case (verb, rest):
      submit_cmd(cl, verb, Irc.drop_spaces(rest))

def submit.slash(+cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  submit.verb(cl, take_verb(skip_slash(input)))

def submit.is_slash.on(+h: Char) -> Bool:
  Irc.code_is(h, 47)

def submit.is_slash(+s: String) -> Bool:
  match s:
    case SCon{+h, _}:
      submit.is_slash.on(h)
    case SNil{}:
      False{}

def submit.on(+cl: Cl.Client, +input: String, slash: Bool) -> Cl.Client & List<&2, String>:
  match slash:
    case True{}:
      submit.slash(cl, input)
    case False{}:
      submit_plain(cl, input)

def submit.empty(+cl: Cl.Client, empty: Bool, +input: String) -> Cl.Client & List<&2, String>:
  match empty:
    case True{}:
      (cl, empty_out())
    case False{}:
      submit.on(cl, input, submit.is_slash(input))

def submit(+cl: Cl.Client, +input: String) -> Cl.Client & List<&2, String>:
  submit.empty(cl, String.is_empty(input), input)

# Fuel 0 fails closed. Nil is True only after a fuel tick (out_all_ok).
def out_all_ok.go(fuel: Nat, +xs: List<&2, String>, ok: Bool) -> Bool:
  match fuel:
    case 0n:
      False{}
    case 1n+p:
      match xs:
        case Nil{}:
          ok
        case Con{+h, t}:
          match ok:
            case False{}:
              False{}
            case True{}:
              out_all_ok.go(p, t, Irc.line_ok(h))

def out_all_ok(+xs: List<&2, String>) -> Bool:
  out_all_ok.go(Nat.add(1n, List.length(&2, String, xs)), xs, True{})

def submit_ok.fin(outs: List<&2, String>) -> Bool:
  out_all_ok(outs)

def submit_ok.pair(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, outs):
      submit_ok.fin(outs)

def submit_ok(+cl: Cl.Client, +input: String) -> Bool:
  submit_ok.pair(submit(cl, input))

def quit_verb.on(hit: Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      False{}

def quit_verb(pair: String & String) -> Bool:
  match pair:
    case (+verb, _):
      quit_verb.on(Irc.ieq(verb, "quit"))

def submit_is_quit.on(+input: String, slash: Bool) -> Bool:
  match slash:
    case True{}:
      quit_verb(take_verb(skip_slash(input)))
    case False{}:
      False{}

def submit_is_quit(+input: String) -> Bool:
  submit_is_quit.on(input, submit.is_slash(input))

def submit_halt_ok() -> Bool:
  submit_is_quit("/quit") && submit_is_quit("/quit bye") && Bool.not(submit_is_quit("hello")) && Bool.not(submit_is_quit("/join #x"))

def connect_verb.on(hit: Bool) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      False{}

def connect_verb(pair: String & String) -> Bool:
  match pair:
    case (+verb, _):
      connect_verb.on(Irc.ieq(verb, "connect"))

def submit_is_connect.on(+input: String, slash: Bool) -> Bool:
  match slash:
    case True{}:
      connect_verb(take_verb(skip_slash(input)))
    case False{}:
      False{}

def submit_is_connect(+input: String) -> Bool:
  submit_is_connect.on(input, submit.is_slash(input))

def connect_from_input.on(pair: String & String) -> Conn:
  match pair:
    case (_, +rest):
      connect_parse(Irc.drop_spaces(rest))

def connect_from_input.slash(+input: String, slash: Bool) -> Conn:
  match slash:
    case True{}:
      connect_from_input.on(take_verb(skip_slash(input)))
    case False{}:
      ConnBad{}

def connect_from_input(+input: String) -> Conn:
  connect_from_input.slash(input, submit.is_slash(input))

def connect_parse_ok.on(c: Conn) -> Bool:
  match c:
    case ConnOk{+host, port}:
      String.eq(host, "irc.example.net") && U32.is_eq(port, 6668)
    case ConnBad{}:
      False{}

def connect_default_ok.on(c: Conn) -> Bool:
  match c:
    case ConnOk{_, p}:
      U32.is_eq(p, 6667)
    case ConnBad{}:
      False{}

def connect_bad.on(c: Conn) -> Bool:
  match c:
    case ConnBad{}:
      True{}
    case ConnOk{_, _}:
      False{}

def connect_port_range_ok() -> Bool:
  connect_bad.on(connect_parse("h 0"))
    && connect_bad.on(connect_parse("h 99999"))
    && connect_bad.on(connect_parse("h 4294967295"))
    && connect_parse_ok.on(connect_parse("irc.example.net 6668"))

def connect_parse_ok() -> Bool:
  connect_parse_ok.on(connect_parse("irc.example.net 6668"))
    && connect_default_ok.on(connect_parse("irc.example.net"))
    && connect_port_range_ok()
