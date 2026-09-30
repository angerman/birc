# Pure IRC session: fold, JOIN-after-001, keys. No reconnect/backoff.
# No IO. net.bend owns Socket / Chan / TimUI.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./frame.bend as Fr
import ./submit.bend as Sub
import ./base64.bend as B64
import ./split.bend as Sp
import ./typing.bend as Ty

def register_lines(+nick: String) -> List<&2, String>:
  Irc.format_nick(nick) <> Irc.format_user(nick) <> Nil{}

def handshake_lines(+nick: String, has_sasl: Bool) -> List<&2, String>:
  match has_sasl:
    case True{}:
      "CAP LS 302" <> "CAP REQ :sasl" <> "CAP REQ :server-time" <> "CAP REQ :message-tags" <> Irc.format_nick(nick) <> Irc.format_user(nick) <> Nil{}
    case False{}:
      "CAP LS 302" <> "CAP REQ :server-time" <> "CAP REQ :message-tags" <> "CAP END" <> Irc.format_nick(nick) <> Irc.format_user(nick) <> Nil{}

type FoldAcc is Data:
  FoldAcc{cl: Cl.Client, pongs: List<&2, String>, now_ms: U32}

def fold_step.normal(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String) -> FoldAcc:
  +cl2 = Feed.feed(cl, h)
  FoldAcc{cl2, List.append(&2, String, Irc.nick433_for(h, Cl.nick_of(cl)), pongs), now_ms}

def fold_step.lag_rtt.on(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +sent: U32, ok: Bool) -> FoldAcc:
  match ok:
    case True{}:
      +rtt = U32.sub(now_ms, sent)
      +cl2 = Cl.client_set_lag(cl, rtt)
      FoldAcc{Feed.feed(cl2, h), pongs, now_ms}
    case False{}:
      FoldAcc{Feed.feed(cl, h), pongs, now_ms}

def fold_step.lag_rtt(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +sent: U32) -> FoldAcc:
  fold_step.lag_rtt.on(cl, pongs, now_ms, h, sent, U32.is_ge(now_ms, sent) && Bool.not(U32.is_zero(now_ms)))

def fold_step.lag_on(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, m: Maybe<&2, U32>) -> FoldAcc:
  match m:
    case None{}:
      fold_step.normal(cl, pongs, now_ms, h)
    case Some{sent}:
      fold_step.lag_rtt(cl, pongs, now_ms, h, sent)

def fold_step.lag(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String) -> FoldAcc:
  fold_step.lag_on(cl, pongs, now_ms, h, Irc.extract_pong_lag_line(h))

def fold_step.sasl_nak(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, is_nak: Bool) -> FoldAcc:
  match is_nak:
    case True{}:
      +c1 = Feed.feed(cl, h)
      +c2 = Cl.client_log(c1, 0n, Cl.Error{}, "SASL: capability rejected")
      FoldAcc{c2, "CAP END" <> pongs, now_ms}
    case False{}:
      fold_step.lag(cl, pongs, now_ms, h)

def fold_step.sasl_fail(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, is_fail: Bool) -> FoldAcc:
  match is_fail:
    case True{}:
      +c1 = Feed.feed(cl, h)
      +c2 = Cl.client_log(c1, 0n, Cl.Error{}, "SASL: authentication failed")
      FoldAcc{c2, "CAP END" <> pongs, now_ms}
    case False{}:
      fold_step.sasl_nak(cl, pongs, now_ms, h, Irc.is_cap_nak(h) && String.contains(h, "sasl"))

def fold_step.sasl_succ(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, is_succ: Bool) -> FoldAcc:
  match is_succ:
    case True{}:
      +c1 = Feed.feed(cl, h)
      +c2 = Cl.client_log(c1, 0n, Cl.System{}, "SASL: authentication successful")
      FoldAcc{c2, "CAP END" <> pongs, now_ms}
    case False{}:
      fold_step.sasl_fail(cl, pongs, now_ms, h, Irc.is_sasl_fail(h))

def fold_step.auth_plus(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, is_ap: Bool) -> FoldAcc:
  match is_ap:
    case True{}:
      +payload = B64.sasl_plain(Cl.client_sasl_user(cl), Cl.client_sasl_pass(cl))
      FoldAcc{cl, ("AUTHENTICATE " ++ payload) <> pongs, now_ms}
    case False{}:
      fold_step.sasl_succ(cl, pongs, now_ms, h, Irc.is_sasl_success(h))

def fold_step.cap_ack(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, is_ack: Bool) -> FoldAcc:
  match is_ack:
    case True{}:
      +c1 = Feed.feed(cl, h)
      +c2 = Cl.client_log(c1, 0n, Cl.System{}, "SASL: authenticating with PLAIN...")
      FoldAcc{c2, "AUTHENTICATE PLAIN" <> pongs, now_ms}
    case False{}:
      fold_step.auth_plus(cl, pongs, now_ms, h, Irc.is_authenticate_plus(h))

def fold_step.ping(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, ping: Bool) -> FoldAcc:
  match ping:
    case True{}:
      FoldAcc{cl, Irc.pong_for(h) <> pongs, now_ms}
    case False{}:
      fold_step.cap_ack(cl, pongs, now_ms, h, Irc.is_cap_ack_sasl(h))

def fold_step.got(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String) -> FoldAcc:
  fold_step.ping(cl, pongs, now_ms, h, Irc.is_ping_line(h))

def fold_step(st: FoldAcc, h: String) -> FoldAcc:
  match st:
    case FoldAcc{+cl, pongs, +now_ms}:
      fold_step.got(cl, pongs, now_ms, h)

def fold_fin(st: FoldAcc) -> Cl.Client & List<&2, String>:
  match st:
    case FoldAcc{+cl, pongs, _}:
      (cl, List.reverse(&2, String, pongs))

def fold_lines_ms(+cl: Cl.Client, +xs: List<&2, String>, +now_ms: U32) -> Cl.Client & List<&2, String>:
  fold_fin(List.foldl(~&2, ~String, ~FoldAcc, ~fold_step, xs, FoldAcc{cl, Nil{}, now_ms}))

def fold_lines(+cl: Cl.Client, +xs: List<&2, String>) -> Cl.Client & List<&2, String>:
  fold_lines_ms(cl, xs, 0)

def is_001_msg(+m: Irc.Message) -> Bool:
  match m:
    case Irc.Message{_, _, _, +num, _}:
      U32.is_eq(num, 1)

def is_001_on(m: Maybe<&2, Irc.Message>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{msg}:
      is_001_msg(msg)

def is_001_line(+line: String) -> Bool:
  is_001_on(Irc.parse(line))

def hit_step(hit: Bool, h: String) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      is_001_line(h)

def lines_have_001(+xs: List<&2, String>) -> Bool:
  List.foldl(~&2, ~String, ~Bool, ~hit_step, xs, False{})

def join_outs.on(+chan: String, +pongs: List<&2, String>, joined: Bool, welcome: Bool) -> List<&2, String> & Bool:
  match joined:
    case True{}:
      (pongs, True{})
    case False{}:
      match welcome:
        case True{}:
          (List.append(&2, String, pongs, Irc.format_join(chan) <> Nil{}), True{})
        case False{}:
          (pongs, False{})

def join_outs(+joined: Bool, +chan: String, +xs: List<&2, String>, +pongs: List<&2, String>) -> List<&2, String> & Bool:
  match joined:
    case True{}:
      (pongs, True{})
    case False{}:
      join_outs.on(chan, pongs, False{}, lines_have_001(xs))

def live_fuel(+frames: U32) -> Nat:
  U32.to_nat(frames)

def ticks_of(+frames: U32) -> Nat:
  live_fuel(frames)

def body_h_on(+rows: U32, ge: Bool) -> Nat:
  match ge:
    case True{}:
      U32.to_nat(U32.sub(rows, 5))
    case False{}:
      1n

def body_h(+rows: U32) -> Nat:
  body_h_on(rows, U32.is_ge(rows, 6))

# Body lines and PageUp/PageDown share this height. Bend applies it
# from the frame's row count (Sess.key_pol); C does not take a page.
def body_h_ok() -> Bool:
  Nat.is_eq(body_h(24), 19n) && Nat.is_eq(body_h(16), 11n) && Nat.is_eq(body_h(6), 1n) && Nat.is_eq(body_h(7), 2n)


def push_pure_join2(
  +cl2: Cl.Client,
  rem2: List<&2, U32>,
  drop2: Bool,
  pair: List<&2, String> & Bool
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  match pair:
    case (outs, joined2):
      (cl2, rem2, drop2, outs, joined2)

def push_pure_join(
  cl_pongs: Cl.Client & List<&2, String>,
  rem2: List<&2, U32>,
  drop2: Bool,
  +joined: Bool,
  +chan: String,
  +xs: List<&2, String>
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  match cl_pongs:
    case (cl2, pongs):
      push_pure_join2(cl2, rem2, drop2, join_outs(joined, chan, xs, pongs))

def push_pure_pair_ms(
  +cl: Cl.Client,
  got: List<&2, String> & List<&2, U32> & Bool,
  +joined: Bool,
  +chan: String,
  +now_ms: U32
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  match got:
    case (+lines, rem2, drop2):
      push_pure_join(fold_lines_ms(cl, lines, now_ms), rem2, drop2, joined, chan, lines)

def push_pure_pair(
  +cl: Cl.Client,
  got: List<&2, String> & List<&2, U32> & Bool,
  +joined: Bool,
  +chan: String
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  push_pure_pair_ms(cl, got, joined, chan, 0)

def push_pure_ms(
  +cl: Cl.Client,
  drop: Bool,
  rem: List<&2, U32>,
  chunk: List<&2, U32>,
  +joined: Bool,
  +chan: String,
  +now_ms: U32
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  push_pure_pair_ms(cl, Fr.push_ex(drop, rem, chunk), joined, chan, now_ms)

def push_pure(
  +cl: Cl.Client,
  drop: Bool,
  rem: List<&2, U32>,
  chunk: List<&2, U32>,
  +joined: Bool,
  +chan: String
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  push_pure_ms(cl, drop, rem, chunk, joined, chan, 0)

def step_chunk_ms(
  +cl: Cl.Client,
  drop: Bool,
  rem: List<&2, U32>,
  chunk: List<&2, U32>,
  +joined: Bool,
  +chan: String,
  +now_ms: U32
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  push_pure_ms(cl, drop, rem, chunk, joined, chan, now_ms)

def step_chunk(
  +cl: Cl.Client,
  drop: Bool,
  rem: List<&2, U32>,
  chunk: List<&2, U32>,
  +joined: Bool,
  +chan: String
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  step_chunk_ms(cl, drop, rem, chunk, joined, chan, 0)

type NetEvt is Data:
  Chunk{xs: List<&2, U32>}
  Eof{}
  Tick{}
  Up{fd: U32}
  NetFail{msg: String}

# gen is the connection the UI bumped on this Dial. Stale FromNet is dropped.
type NetCmd is Data:
  Cont{outs: List<&2, String>}
  Dial{host: String, port: U32, gen: U32}
  Drop{}
  Handoff{take: Bool}
  OpenUrl{url: String}

# One UI channel. FromNet is ignored unless gen is the UI's current one.
type UiMsg is Data:
  FromNet{gen: U32, e: NetEvt}
  UiKey{}
  Resize{}
  TypingTick{now_ms: U32}
  Reconnect{host: String, port: U32, gen: U32}

type NetState is Data:
  Demo{}
  Connecting{}
  Online{}
  Offline{}

def net_label(st: NetState) -> String:
  match st:
    case Demo{}:
      "demo"
    case Connecting{}:
      "connecting"
    case Online{}:
      "online"
    case Offline{}:
      "offline"

def net_label_lag.online(+lag: U32, is_zero: Bool) -> String:
  match is_zero:
    case True{}: "online"
    case False{}: "online · " ++ U32.show(lag) ++ "ms"

def net_label_lag(+st: NetState, +lag: U32) -> String:
  match st:
    case Online{}: net_label_lag.online(lag, U32.is_eq(lag, 0))
    case Demo{}: "demo"
    case Connecting{}: "connecting"
    case Offline{}: "offline"

def net_demo_ok() -> Bool:
  String.eq(net_label(Demo{}), "demo") && String.eq(net_label(Online{}), "online")

def show_netcmd(c: NetCmd) -> String:
  match c:
    case Cont{_}:
      "cont"
    case Dial{+host, port, _}:
      String.concat("dial:" <> host <> ":" <> U32.show(port) <> Nil{})
    case Drop{}:
      "drop"
    case Handoff{take}:
      String.concat("handoff:" <> Bool.show(take) <> Nil{})
    case OpenUrl{+url}:
      "open:" ++ url

def hold_cmd.outs(net: NetState, outs: List<&2, String>) -> NetCmd:
  match net:
    case Online{}:
      Cont{outs}
    case Connecting{}:
      Cont{Nil{}}
    case Demo{}:
      Cont{Nil{}}
    case Offline{}:
      Cont{Nil{}}

def hold_cmd(net: NetState, cmd: NetCmd) -> NetCmd:
  match cmd:
    case Dial{+host, port, gen}:
      Dial{host, port, gen}
    case Drop{}:
      Drop{}
    case Handoff{take}:
      Handoff{take}
    case Cont{outs}:
      hold_cmd.outs(net, outs)
    case OpenUrl{+url}:
      OpenUrl{url}

# Kept for the submit goldens. The UI does not call these.
def merge_cmd(+pending: List<&2, String>, cmd: NetCmd) -> NetCmd:
  match cmd:
    case Dial{+host, port, gen}:
      Dial{host, port, gen}
    case Drop{}:
      Drop{}
    case Handoff{take}:
      Handoff{take}
    case Cont{outs}:
      Cont{List.append(&2, String, pending, outs)}
    case OpenUrl{+url}:
      OpenUrl{url}

def wrap_outs(pair: Cl.Client & List<&2, String>) -> Cl.Client & String & NetCmd:
  match pair:
    case (cl2, outs):
      (cl2, "", Cont{outs})

def can_send(net: NetState) -> Bool:
  match net:
    case Online{}:
      True{}
    case Demo{}:
      True{}
    case Connecting{}:
      False{}
    case Offline{}:
      False{}

def submit_offline(+cl: Cl.Client, +draft: String, quit: Bool) -> Cl.Client & String & NetCmd:
  match quit:
    case True{}:
      wrap_outs(Sub.submit(cl, draft))
    case False{}:
      (Sub.echo_err_server(cl, "not connected"), "", Cont{Nil{}})

def submit_send(+cl: Cl.Client, net: NetState, +draft: String, ok: Bool) -> Cl.Client & String & NetCmd:
  match ok:
    case True{}:
      wrap_outs(Sub.submit(cl, draft))
    case False{}:
      submit_offline(cl, draft, Sub.submit_is_quit(draft))

def connect_apply.busy(+cl: Cl.Client, online: Bool) -> Cl.Client & String & NetCmd:
  match online:
    case True{}:
      (Sub.echo_err_server(cl, "already connected"), "", Cont{Nil{}})
    case False{}:
      (Sub.echo_err_server(cl, "already connecting"), "", Cont{Nil{}})

def connect_apply.st(+cl: Cl.Client, +host: String, +port: U32, net: NetState) -> Cl.Client & String & NetCmd:
  match net:
    case Connecting{}:
      connect_apply.busy(cl, False{})
    case _:
      (Sub.echo_sys(cl, "connecting to " ++ host ++ ":" ++ U32.show(port)), "", Dial{host, port, 0})

def connect_apply.recon_ok(ok: Bool, +cl: Cl.Client, net: NetState, +server: String, +port: U32) -> Cl.Client & String & NetCmd:
  match ok:
    case True{}:
      connect_apply.st(cl, server, port, net)
    case False{}:
      (Sub.echo_err(cl, "cannot reconnect: no server configured"), "", Cont{Nil{}})

def connect_apply.reconnect(+cl: Cl.Client, net: NetState, +server: String, +port: U32) -> Cl.Client & String & NetCmd:
  connect_apply.recon_ok(Bool.not(String.is_empty(server) || String.eq(server, "demo") || String.eq(server, "s")), cl, net, server, port)

def connect_apply(+cl: Cl.Client, net: NetState, +port: U32, c: Sub.Conn) -> Cl.Client & String & NetCmd:
  match c:
    case Sub.ConnBad{}:
      (Sub.echo_err(cl, "usage: /connect host [port]"), "", Cont{Nil{}})
    case Sub.ConnOk{+host, port}:
      connect_apply.st(cl, host, port, net)
    case Sub.ConnReconnect{}:
      connect_apply.reconnect(cl, net, Cl.server_of(cl), port)

def open_apply.got(+cl: Cl.Client, mb: Maybe<&2, String>) -> Cl.Client & String & NetCmd:
  match mb:
    case None{}:
      (Sub.echo_err(cl, "no link found"), "", Cont{Nil{}})
    case Some{+url}:
      (Sub.echo_info(cl, "opening " ++ url), "", OpenUrl{url})

def open_apply(+cl: Cl.Client, +draft: String) -> Cl.Client & String & NetCmd:
  +arg = Sub.open_arg_from_input(draft)
  open_apply.got(cl, Sub.open_resolve_target(cl, arg))

def submit_pair.enter.on(+cl: Cl.Client, +net: NetState, +draft: String, is_open: Bool) -> Cl.Client & String & NetCmd:
  match is_open:
    case True{}:
      open_apply(cl, draft)
    case False{}:
      submit_send(cl, net, draft, can_send(net))

def submit_pair.enter(+cl: Cl.Client, +net: NetState, +port: U32, +draft: String, conn: Bool) -> Cl.Client & String & NetCmd:
  match conn:
    case True{}:
      connect_apply(cl, net, port, Sub.connect_from_input(draft))
    case False{}:
      submit_pair.enter.on(cl, net, draft, Sub.submit_is_open(draft))

def submit_pair(+cl: Cl.Client, net: NetState, +port: U32, +draft: String, enter: Bool) -> Cl.Client & String & NetCmd:
  match enter:
    case False{}:
      (cl, draft, Cont{Nil{}})
    case True{}:
      submit_pair.enter(cl, net, port, draft, Sub.submit_is_connect(draft))

def apply_keys(+cl: Cl.Client, net: NetState, +port: U32, +draft: String, enter: Bool) -> Cl.Client & String & NetCmd:
  submit_pair(cl, net, port, draft, enter)

def cmd_connect.got(triple: Cl.Client & String & NetCmd) -> NetCmd:
  match triple:
    case (_, _, c):
      c

def cmd_connect(+net: NetState, +input: String) -> NetCmd:
  cmd_connect.got(connect_apply(Cl.init("me", "s"), net, 6667, Sub.connect_from_input(input)))

def cmd_connect_ok() -> Bool:
  String.eq(show_netcmd(cmd_connect(Demo{}, "/connect irc.example.net 6668")), "dial:irc.example.net:6668")
    && String.eq(show_netcmd(cmd_connect(Online{}, "/connect irc.example.net")), "dial:irc.example.net:6667")
    && String.eq(show_netcmd(cmd_connect(Connecting{}, "/connect irc.example.net")), "cont")
    && String.eq(show_netcmd(cmd_connect(Demo{}, "/connect")), "cont")

type Hist is Data:
  Hist{lines: List<&2, String>, pos: Nat}

def hist0() -> Hist:
  Hist{Nil{}, 0n}

def HIST_CAP() -> Nat:
  64n

def take_last_str(+xs: List<&2, String>, n: Nat) -> List<&2, String>:
  List.drop(&2, String, xs, Nat.sub(List.length(&2, String, xs), n))

def hist_len(h: Hist) -> Nat:
  match h:
    case Hist{+lines, _}:
      List.length(&2, String, lines)

def hist_push.on(+line: String, empty: Bool, h: Hist) -> Hist:
  match empty:
    case True{}:
      h
    case False{}:
      match h:
        case Hist{+lines, _}:
          +xs = take_last_str(List.append(&2, String, lines, line <> Nil{}), HIST_CAP())
          Hist{xs, List.length(&2, String, xs)}

def hist_push(+h: Hist, +line: String) -> Hist:
  hist_push.on(line, String.is_empty(line), h)

def str_get(+xs: List<&2, String>, +i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, i), "")

def hist_prev.on(+lines: List<&2, String>, +pos: Nat, z: Bool) -> Hist & String:
  match z:
    case True{}:
      (Hist{lines, pos}, str_get(lines, pos))
    case False{}:
      +p = Nat.sub(pos, 1n)
      (Hist{lines, p}, str_get(lines, p))

def hist_prev(h: Hist) -> Hist & String:
  match h:
    case Hist{+lines, +pos}:
      hist_prev.on(lines, pos, Nat.is_eq(pos, 0n))

def hist_next.at(+lines: List<&2, String>, +p: Nat, +n: Nat, last: Bool) -> Hist & String:
  match last:
    case True{}:
      (Hist{lines, n}, "")
    case False{}:
      (Hist{lines, p}, str_get(lines, p))

def hist_next.on(+lines: List<&2, String>, +pos: Nat, +n: Nat, last: Bool) -> Hist & String:
  match last:
    case True{}:
      (Hist{lines, n}, "")
    case False{}:
      +p = Nat.add(pos, 1n)
      hist_next.at(lines, p, n, Nat.is_eq(p, n))

def hist_next(h: Hist) -> Hist & String:
  match h:
    case Hist{+lines, +pos}:
      +n = List.length(&2, String, lines)
      hist_next.on(lines, pos, n, Nat.is_ge(pos, n))

type HistDir is Data:
  HistStay{}
  HistPrev{}
  HistNext{}

def hist_dir.on(+n: U32, prev: Bool, next: Bool) -> HistDir:
  match prev:
    case True{}:
      HistPrev{}
    case False{}:
      match next:
        case True{}:
          HistNext{}
        case False{}:
          HistStay{}

def hist_dir(+n: U32) -> HistDir:
  hist_dir.on(n, U32.is_eq(n, 1), U32.is_eq(n, 2))

def hist_move(+h: Hist, +draft: String, dir: HistDir) -> Hist & String:
  match dir:
    case HistStay{}:
      (h, draft)
    case HistPrev{}:
      hist_prev(h)
    case HistNext{}:
      hist_next(h)

def click_of.on(+n: U32, z: Bool) -> Maybe<&2, Nat>:
  match z:
    case True{}:
      None{}
    case False{}:
      Some{U32.to_nat(U32.sub(n, 1))}

def click_of(+n: U32) -> Maybe<&2, Nat>:
  click_of.on(n, U32.is_eq(n, 0))

type Keys is Data:
  Keys{
    typed: String,
    enter: Bool,
    tab: Cl.TabDir,
    click: Maybe<&2, Nat>,
    up: Nat,
    dn: Nat,
    hist: HistDir,
    comp: Bool,
    focus: U32
  }

def comp_on(+n: U32) -> Bool:
  Bool.not(U32.is_zero(n))

def keys_enter(+line: String) -> Keys:
  Keys{line, True{}, Cl.TabStay{}, None{}, 0n, 0n, HistStay{}, False{}, 0}

def keys_focus() -> Keys:
  Keys{"", False{}, Cl.TabStay{}, None{}, 0n, 0n, HistStay{}, False{}, 1}

# TimUI key numbers (TimuiKey). Bend maps them; C only reports the raw key.
def KEY_ESCAPE() -> U32:
  1

def KEY_TAB() -> U32:
  3

def key_comp.on(tab: Bool) -> U32:
  match tab:
    case True{}:
      1
    case False{}:
      0

def key_comp(+key: U32) -> U32:
  key_comp.on(U32.is_eq(key, KEY_TAB()))


def KEY_UP() -> U32:
  7

def KEY_DOWN() -> U32:
  8

def KEY_LEFT() -> U32:
  9

def KEY_RIGHT() -> U32:
  10

def KEY_PAGE_UP() -> U32:
  13

def KEY_PAGE_DOWN() -> U32:
  14

def KEY_F10() -> U32:
  24

def KEY_F6() -> U32:
  20

def MOD_SHIFT() -> U32:
  1

def MOD_CTRL() -> U32:
  4

def ctrl_on(+mods: U32) -> Bool:
  U32.is_eq(U32.and(mods, MOD_CTRL()), MOD_CTRL())

def key_focus.on(f6: Bool, ctrl_w: Bool) -> U32:
  match f6:
    case True{}: 1
    case False{}: Bool.pick(U32, ctrl_w, 1, 0)

def key_focus(+key: U32, +mods: U32, +codepoint: U32) -> U32:
  key_focus.on(U32.is_eq(key, KEY_F6()), ctrl_on(mods) && (U32.is_eq(codepoint, 119) || U32.is_eq(codepoint, 87)))

def WHEEL_SIGN() -> U32:
  2147483648

def shift_on(+mods: U32) -> Bool:
  U32.is_eq(U32.and(mods, MOD_SHIFT()), MOD_SHIFT())

def key_tab.on(shift: Bool, right: Bool, left: Bool) -> U32:
  match shift:
    case False{}:
      0
    case True{}:
      match right:
        case True{}:
          1
        case False{}:
          match left:
            case True{}:
              2
            case False{}:
              0

def key_tab(+key: U32, +mods: U32) -> U32:
  key_tab.on(shift_on(mods), U32.is_eq(key, KEY_RIGHT()), U32.is_eq(key, KEY_LEFT()))

def key_hist.on(shift: Bool, up: Bool, down: Bool) -> U32:
  match shift:
    case True{}:
      0
    case False{}:
      match up:
        case True{}:
          1
        case False{}:
          match down:
            case True{}:
              2
            case False{}:
              0

def key_hist(+key: U32, +mods: U32) -> U32:
  key_hist.on(shift_on(mods), U32.is_eq(key, KEY_UP()), U32.is_eq(key, KEY_DOWN()))

def key_quit.on(esc: Bool, f10: Bool) -> U32:
  match esc:
    case True{}:
      1
    case False{}:
      match f10:
        case True{}:
          1
        case False{}:
          0

def key_quit(+key: U32) -> U32:
  key_quit.on(U32.is_eq(key, KEY_ESCAPE()), U32.is_eq(key, KEY_F10()))

def wheel_neg(+w: U32) -> Bool:
  U32.is_ge(w, WHEEL_SIGN())

def wheel_up.on(+w: U32, neg: Bool) -> U32:
  match neg:
    case True{}:
      0
    case False{}:
      w

def wheel_up(+w: U32) -> U32:
  wheel_up.on(w, wheel_neg(w))

# A negative wheel is uint32 two's complement. Its magnitude is ~w+1.
# 2^32 does not fit in U32, so this is not a subtraction from 2^32.
def wheel_dn.on(+w: U32, neg: Bool) -> U32:
  match neg:
    case False{}:
      0
    case True{}:
      U32.add(U32.not(w), 1)

def wheel_dn(+w: U32) -> U32:
  wheel_dn.on(w, wheel_neg(w))

def page_amt(on: Bool, +page: Nat) -> U32:
  match on:
    case False{}:
      0
    case True{}:
      U32.from_nat(page)

def scroll_up(+key: U32, +wheel: U32, +page: Nat) -> U32:
  U32.add(wheel_up(wheel), page_amt(U32.is_eq(key, KEY_PAGE_UP()), page))

def scroll_dn(+key: U32, +wheel: U32, +page: Nat) -> U32:
  U32.add(wheel_dn(wheel), page_amt(U32.is_eq(key, KEY_PAGE_DOWN()), page))

type KeyPol is Data:
  KeyPol{tab: U32, up: U32, dn: U32, hist: U32, quit: U32, comp: U32, focus: U32}

def key_pol_raw(+key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +page: Nat) -> KeyPol:
  KeyPol{key_tab(key, mods), scroll_up(key, wheel, page), scroll_dn(key, wheel, page), key_hist(key, mods), key_quit(key), key_comp(key), key_focus(key, mods, codepoint)}

def key_pol(+key: U32, +mods: U32, +wheel: U32, +rows: U32) -> KeyPol:
  key_pol_raw(key, mods, 0, wheel, body_h(rows))

def pol_eq(p: KeyPol, +tab: U32, +up: U32, +dn: U32, +hist: U32, +quit: U32, +comp: U32, +focus: U32) -> Bool:
  match p:
    case KeyPol{t, u, d, h, q, c, f}:
      U32.is_eq(t, tab) && U32.is_eq(u, up) && U32.is_eq(d, dn) && U32.is_eq(h, hist) && U32.is_eq(q, quit) && U32.is_eq(c, comp) && U32.is_eq(f, focus)

def key_pol_ok() -> Bool:
  pol_eq(key_pol(KEY_RIGHT(), MOD_SHIFT(), 0, 24), 1, 0, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_LEFT(), MOD_SHIFT(), 0, 24), 2, 0, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_RIGHT(), 0, 0, 24), 0, 0, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_UP(), 0, 0, 24), 0, 0, 0, 1, 0, 0, 0)
    && pol_eq(key_pol(KEY_UP(), MOD_SHIFT(), 0, 24), 0, 0, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_DOWN(), 0, 0, 24), 0, 0, 0, 2, 0, 0, 0)
    && pol_eq(key_pol(KEY_ESCAPE(), 0, 0, 24), 0, 0, 0, 0, 1, 0, 0)
    && pol_eq(key_pol(KEY_F10(), 0, 0, 24), 0, 0, 0, 0, 1, 0, 0)
    && pol_eq(key_pol(KEY_PAGE_UP(), 0, 0, 24), 0, 19, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_PAGE_DOWN(), 0, 0, 24), 0, 0, 19, 0, 0, 0, 0)
    && pol_eq(key_pol(0, 0, 3, 24), 0, 3, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(0, 0, 4294967294, 24), 0, 0, 2, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_PAGE_UP(), 0, 2, 24), 0, 21, 0, 0, 0, 0, 0)
    && pol_eq(key_pol(KEY_TAB(), 0, 0, 24), 0, 0, 0, 0, 0, 1, 0)
    && pol_eq(key_pol_raw(KEY_F6(), 0, 0, 0, 9n), 0, 0, 0, 0, 0, 0, 1)
    && pol_eq(key_pol_raw(0, MOD_CTRL(), 119, 0, 9n), 0, 0, 0, 0, 0, 0, 1)

def keys_of(+typed: String, enter: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32, +comp: U32, +focus: U32) -> Keys:
  Keys{typed, enter, Cl.tab_dir(tab), click_of(click), U32.to_nat(up), U32.to_nat(dn), hist_dir(hist), comp_on(comp), focus}

def tab_hot(d: Cl.TabDir) -> Bool:
  match d:
    case Cl.TabStay{}:
      False{}
    case _:
      True{}

def hist_hot(d: HistDir) -> Bool:
  match d:
    case HistStay{}:
      False{}
    case _:
      True{}

def click_hot(c: Maybe<&2, Nat>) -> Bool:
  match c:
    case None{}:
      False{}
    case Some{_}:
      True{}

def nat_hot(+n: Nat) -> Bool:
  Bool.not(Nat.is_eq(n, 0n))

def keys_hot(+k: Keys) -> Bool:
  match k:
    case Keys{+typed, enter, tab, click, +up, +dn, hist, comp, focus}:
      Bool.or(Bool.not(String.is_empty(typed)), Bool.or(enter, Bool.or(tab_hot(tab), Bool.or(click_hot(click), Bool.or(nat_hot(up), Bool.or(nat_hot(dn), Bool.or(hist_hot(hist), Bool.or(comp, Bool.not(U32.is_zero(focus))))))))))


def hist_after_enter(+h: Hist, +line: String, enter: Bool) -> Hist:
  match enter:
    case True{}:
      hist_push(h, line)
    case False{}:
      h

def hist_cap_ok.go(n: Nat, h: Hist) -> Hist:
  match n:
    case 0n:
      h
    case 1n+p:
      hist_cap_ok.go(p, hist_push(h, "x"))

def hist_cap_ok() -> Bool:
  Nat.is_eq(hist_len(hist_cap_ok.go(70n, hist0())), 64n)

type Comp is Data:
  CompNone{}
  CompActive{pre: String, word: String, idx: Nat}

def comp0() -> Comp:
  CompNone{}

def is_all_spaces(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+h, t}:
      Bool.and(Irc.is_space(h), is_all_spaces(t))

def split_word.rev(pair: String & String) -> String & String:
  match pair:
    case (word_rev, pre_rev):
      (String.reverse(pre_rev), String.reverse(word_rev))

def split_word(+s: String) -> String & String:
  split_word.rev(Irc.take_until_space(String.reverse(s)))


def nick_match.ok(own: Bool, sw: Bool) -> Bool:
  match own:
    case True{}:
      False{}
    case False{}:
      sw

def nick_match(+cand: String, +my_nick: String, +word: String) -> Bool:
  nick_match.ok(Irc.ieq(cand, my_nick), String.starts_with(Irc.rfc1459(cand), Irc.rfc1459(word)))

def match_nicks.keep(+cand: String, rest: List<&2, String>, hit: Bool) -> List<&2, String>:
  match hit:
    case True{}:
      cand <> rest
    case False{}:
      rest

def match_nicks.go(xs: List<&2, String>, +my_nick: String, +word: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, +t}:
      +rest = match_nicks.go(t, my_nick, word)
      match_nicks.keep(h, rest, nick_match(h, my_nick, word))

def comp_next_idx.wrap(wrap: Bool, +p: Nat) -> Nat:
  match wrap:
    case True{}:
      0n
    case False{}:
      p

def comp_next_idx(+idx: Nat, +len: Nat) -> Nat:
  +p = Nat.add(idx, 1n)
  comp_next_idx.wrap(Nat.is_ge(p, len), p)

def comp_format.on(+pre: String, +nick: String, spaces: Bool) -> String:
  match spaces:
    case True{}:
      pre ++ nick ++ ": "
    case False{}:
      pre ++ nick ++ " "

def comp_format(+pre: String, +nick: String) -> String:
  comp_format.on(pre, nick, is_all_spaces(pre))

def slash_command_list() -> List<&2, String>:
  "/join" <> "/part" <> "/close" <> "/msg" <> "/query" <> "/nick" <> "/me"
    <> "/quit" <> "/settings" <> "/set" <> "/toggle" <> "/mute" <> "/unmute"
    <> "/mutes" <> "/connect" <> "/reconnect" <> "/open" <> "/links" <> "/search" <> "/preview"
    <> "/split" <> "/vsplit" <> "/split-off" <> "/unsplit" <> "/focus" <> Nil{}

def is_slash_word(+w: String) -> Bool:
  String.starts_with(w, "/")

def match_slash.keep(+cand: String, rest: List<&2, String>, hit: Bool) -> List<&2, String>:
  match hit:
    case True{}:
      cand <> rest
    case False{}:
      rest

def match_slash.go(xs: List<&2, String>, +word: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, +t}:
      +rest = match_slash.go(t, word)
      match_slash.keep(h, rest, String.starts_with(Irc.rfc1459(h), Irc.rfc1459(word)))

def comp_candidates.on(+cl: Cl.Client, +word: String, slash: Bool) -> List<&2, String>:
  match slash:
    case True{}:
      match_slash.go(slash_command_list(), word)
    case False{}:
      match_nicks.go(Cl.active_nicks(cl), Cl.nick_of(cl), word)

def comp_candidates(+cl: Cl.Client, +word: String) -> List<&2, String>:
  comp_candidates.on(cl, word, is_slash_word(word))

def comp_format.choice(+pre: String, +item: String, slash: Bool) -> String:
  match slash:
    case True{}:
      pre ++ item ++ " "
    case False{}:
      comp_format(pre, item)

def comp_format_cand(+pre: String, +word: String, +item: String) -> String:
  comp_format.choice(pre, item, is_slash_word(word))

def comp_pick.on(
  +matches: List<&2, String>,
  +pre: String,
  +word: String,
  +typed: String,
  +idx: Nat,
  empty: Bool
) -> Comp & String & U32:
  match empty:
    case True{}:
      (CompNone{}, typed, 0)
    case False{}:
      +item = str_get(matches, idx)
      (CompActive{pre, word, idx}, comp_format_cand(pre, word, item), 1)

def comp_step.active(+cl: Cl.Client, +pre: String, +word: String, +idx: Nat, +typed: String) -> Comp & String & U32:
  +matches = comp_candidates(cl, word)
  +len = List.length(&2, String, matches)
  comp_pick.on(matches, pre, word, typed, comp_next_idx(idx, len), Nat.is_eq(len, 0n))

def comp_step.fresh(+cl: Cl.Client, pair: String & String, +typed: String) -> Comp & String & U32:
  match pair:
    case (+pre, +word):
      +matches = comp_candidates(cl, word)
      comp_pick.on(matches, pre, word, typed, 0n, Nat.is_eq(List.length(&2, String, matches), 0n))

def comp_step(+cl: Cl.Client, comp: Comp, +typed: String) -> Comp & String & U32:
  match comp:
    case CompNone{}:
      comp_step.fresh(cl, split_word(typed), typed)
    case CompActive{+pre, +word, idx}:
      comp_step.active(cl, pre, word, idx, typed)

def comp_step_ok.check(c: Comp, +str: String, seed: U32) -> Bool:
  String.eq(str, "/join ") && U32.is_eq(seed, 1)

def comp_step_ok.got(trip: Comp & String & U32) -> Bool:
  match trip:
    case (c, str, seed):
      comp_step_ok.check(c, str, seed)

def comp_step_ok() -> Bool:
  comp_step_ok.got(comp_step(Cl.init("me", "s"), comp0(), "/j"))


type Size is Data:
  Size{rows: U32, cols: U32}

type Session is Data:
  Session{
    cl: Cl.Client,
    drop: Bool,
    rem: List<&2, U32>,
    draft: String,
    joined: Bool,
    chan: String,
    net: NetState,
    hist: Hist,
    size: Size,
    seed: U32,
    comp: Comp,
    split: Sp.State,
    typing: Ty.State,
    port: U32
  }

def SIZE0() -> Size:
  Size{24, 80}

def session_with_client_at(+cl: Cl.Client, +chan: String, +port: U32) -> Session:
  Session{cl, False{}, Nil{}, "", False{}, chan, Connecting{}, hist0(), SIZE0(), 0, comp0(), Sp.state0(), Ty.empty(), port}

def session_with_client(+cl: Cl.Client, +chan: String) -> Session:
  session_with_client_at(cl, chan, 6667)

def session0(+nick: String, +host: String, +chan: String) -> Session:
  session_with_client(Cl.init(nick, host), chan)

def session_demo(+cl: Cl.Client, +chan: String) -> Session:
  Session{cl, False{}, Nil{}, "", True{}, chan, Demo{}, hist0(), SIZE0(), 0, comp0(), Sp.state0(), Ty.empty(), 6667}

def session_online(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, +typing, port}:
      Session{cl, drop, rem, draft, joined, chan, Online{}, hist, size, seed, comp, split, typing, port}

def session_cl(+st: Session) -> Cl.Client:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      cl

def session_split(+st: Session) -> Sp.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, split, _, _}: split

def key_pol_for(+st: Session, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +rows: U32) -> KeyPol:
  key_pol_raw(key, mods, codepoint, wheel, Sp.page_height(rows, session_split(st)))

def split_key_ok() -> Bool:
  pol_eq(key_pol_raw(KEY_F6(), 0, 0, 0, 9n), 0, 0, 0, 0, 0, 0, 1)
    && pol_eq(key_pol_raw(0, MOD_CTRL(), 119, 0, 9n), 0, 0, 0, 0, 0, 0, 1)
    && pol_eq(key_pol_raw(0, MOD_CTRL(), 120, 0, 9n), 0, 0, 0, 0, 0, 0, 0)

def session_was_offline(+st: Session) -> Bool:
  match st:
    case Session{_, _, _, _, _, _, net, _, _, _, _, _, _, _}:
      match net:
        case Offline{}: True{}
        case _: False{}

def buf_has_lines(+b: Cl.Buffer) -> Bool:
  match b:
    case Cl.Buffer{_, _, _, lines, _, _}:
      match lines:
        case Nil{}: False{}
        case Con{_, _}: True{}

def add_recon_marker.has(has: Bool, +b: Cl.Buffer, +now: String) -> Cl.Buffer:
  match has:
    case False{}: b
    case True{}:
      Cl.buf_log_ts(b, Cl.System{}, "", "--- Reconnected: " ++ now ++ " ---")

def add_recon_marker(+b: Cl.Buffer, +now: String) -> Cl.Buffer:
  add_recon_marker.has(buf_has_lines(b), b, now)

def add_recon_bufs(bufs: List<&2, Cl.Buffer>, +now: String) -> List<&2, Cl.Buffer>:
  match bufs:
    case Nil{}: Nil{}
    case Con{+b, t}:
      add_recon_marker(b, now) <> add_recon_bufs(t, now)

def add_recon_cl(+cl: Cl.Client, +now: String) -> Cl.Client:
  match cl:
    case Cl.Client{+nick, +server, +bufs, +active, +now_old, +stg}:
      Cl.Client{nick, server, add_recon_bufs(bufs, now), active, now_old, stg}

def session_reconnected.on(was_off: Bool, +st: Session, +now: String) -> Session:
  match was_off:
    case False{}:
      session_online(st)
    case True{}:
      match st:
        case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, +typing, port}:
          Session{add_recon_cl(cl, now), drop, rem, draft, joined, chan, Online{}, hist, size, seed, comp, split, typing, port}

def session_reconnected(+st: Session, +now: String) -> Session:
  session_reconnected.on(session_was_offline(st), st, now)

def session_fail.got(+msg: String, +st: Session) -> Session:
  match st:
    case Session{+cl, _, _, +draft, joined, +chan, _, +hist, size, seed, +comp, split, _, port}:
      Session{Sub.echo_err_server(cl, msg), False{}, Nil{}, draft, joined, chan, Offline{}, hist, size, seed, comp, split, Ty.empty(), port}

def session_fail(+st: Session, +msg: String) -> Session:
  session_fail.got(msg, st)

def session_autoreconnect.st(
  +cl: Cl.Client,
  +draft: String,
  +chan: String,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +server: String,
  +port: U32
) -> Session:
  Session{Sub.echo_sys(cl, "reconnecting in 2s to " ++ server ++ ":" ++ U32.show(port) ++ "..."), False{}, Nil{}, draft, False{}, chan, Connecting{}, hist, size, seed, comp, split, Ty.empty(), port}

def session_autoreconnect.dial(ok: Bool, +st: Session, +server: String) -> Session & NetCmd:
  match ok:
    case False{}:
      (st, Drop{})
    case True{}:
      match st:
        case Session{+cl, drop, rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, _, port}:
          (session_autoreconnect.st(cl, draft, chan, hist, size, seed, comp, split, server, port), Dial{server, port, 0})

def session_autoreconnect.chk(auto: Bool, +st: Session, +server: String) -> Session & NetCmd:
  match auto:
    case False{}:
      (st, Drop{})
    case True{}:
      session_autoreconnect.dial(Bool.not(String.is_empty(server) || String.eq(server, "demo") || String.eq(server, "s")), st, server)

def session_autoreconnect(+st: Session) -> Session & NetCmd:
  +cl = session_cl(st)
  +stg = Cl.get_settings(cl)
  session_autoreconnect.chk(Cl.settings_autoreconn(stg), st, Cl.server_of(cl))

def session_autoreconnect_on(+st: Session) -> Bool:
  Cl.settings_autoreconn(Cl.get_settings(session_cl(st)))

def session_cancel_reconnect(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, +typing, port}:
      Session{cl, drop, rem, draft, joined, chan, Offline{}, hist, size, seed, comp, split, typing, port}

def session_set_now(+st: Session, +ts: String) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port}:
      Session{Cl.set_now(cl, ts), drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port}

def session_set_size(+st: Session, +rows: U32, +cols: U32) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, _, seed, +comp, split, +typing, port}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, Size{rows, cols}, seed, comp, split, typing, port}

def session_size(+st: Session) -> Size:
  match st:
    case Session{_, _, _, _, _, _, _, _, size, _, _, _, _, _}:
      size

def size_eq(a: Size, b: Size) -> Bool:
  match a:
    case Size{ar, ac}:
      match b:
        case Size{br, bc}:
          U32.is_eq(ar, br) && U32.is_eq(ac, bc)

def session_net(+st: Session) -> NetState:
  match st:
    case Session{_, _, _, _, _, _, net, _, _, _, _, _, _, _}:
      net

def session_nick(+st: Session) -> String:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Cl.nick_of(cl)

def session_after.dial(
  +cl: Cl.Client,
  +draft: String,
  +chan: String,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +host: String,
  +port: U32
) -> Session:
  Session{Cl.set_server(cl, host), False{}, Nil{}, draft, False{}, chan, Connecting{}, hist, size, seed, comp, split, Ty.empty(), port}

def session_after(
  +cl: Cl.Client,
  drop: Bool,
  rem: List<&2, U32>,
  +draft: String,
  joined: Bool,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +typing: Ty.State,
  +port: U32,
  cmd: NetCmd
) -> Session:
  match cmd:
    case Dial{+host, dial_port, _}:
      session_after.dial(cl, draft, chan, hist, size, seed, comp, split, host, dial_port)
    case Drop{}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port}
    case Handoff{_}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port}
    case Cont{_}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port}
    case OpenUrl{_}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port}

def apply_click(+cl: Cl.Client, c: Maybe<&2, Nat>) -> Cl.Client:
  match c:
    case None{}:
      cl
    case Some{i}:
      Cl.set_active_clamp(cl, i)

def snap_if(enter: Bool, +cl: Cl.Client) -> Cl.Client:
  match enter:
    case True{}:
      Cl.snap_active(cl)
    case False{}:
      cl

def halt_of(enter: Bool, +line: String) -> Bool:
  match enter:
    case True{}:
      Sub.submit_is_quit(line)
    case False{}:
      False{}

def seed_of(dir: HistDir) -> U32:
  match dir:
    case HistStay{}:
      0
    case HistPrev{}:
      1
    case HistNext{}:
      1

def session_seed(+st: Session) -> U32:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, seed, _, _, _, _}:
      seed

def session_draft(+st: Session) -> String:
  match st:
    case Session{_, _, _, draft, _, _, _, _, _, _, _, _, _, _}:
      draft

def split_apply.open.got(
  triple: Cl.Client & Sp.State & Bool,
  previous: Sp.State,
  axis: Sp.Axis,
  +target: String
) -> Cl.Client & String & NetCmd & Sp.State:
  match triple:
    case (cl2, split2, ok):
      match ok:
        case True{}:
          (Sub.echo_info(cl2, "split " ++ Sp.show_axis(axis)), "", Cont{Nil{}}, split2)
        case False{}:
          (Sub.echo_err(cl2, "split target must name another open buffer: " ++ target), "", Cont{Nil{}}, previous)

def split_apply.open(+cl: Cl.Client, previous: Sp.State, +axis: Sp.Axis, +target: String) -> Cl.Client & String & NetCmd & Sp.State:
  split_apply.open.got(Sp.activate(cl, axis, target), previous, axis, target)

def split_apply.focus.got(pair: Cl.Client & Sp.State) -> Cl.Client & String & NetCmd & Sp.State:
  match pair:
    case (cl2, split2):
      (Sub.echo_info(cl2, "split focus changed"), "", Cont{Nil{}}, split2)

def split_apply.focus.on(on: Bool, +cl: Cl.Client, split: Sp.State) -> Cl.Client & String & NetCmd & Sp.State:
  match on:
    case False{}:
      (Sub.echo_err(cl, "split view is not active"), "", Cont{Nil{}}, split)
    case True{}:
      split_apply.focus.got(Sp.toggle(cl, split))

def split_apply.focus(+cl: Cl.Client, +split: Sp.State) -> Cl.Client & String & NetCmd & Sp.State:
  split_apply.focus.on(Sp.is_on(split), cl, split)

def split_apply(+cl: Cl.Client, split: Sp.State, cmd: Sp.Command) -> Cl.Client & String & NetCmd & Sp.State:
  match cmd:
    case Sp.NotSplit{}:
      (cl, "", Cont{Nil{}}, split)
    case Sp.BadSplit{}:
      (Sub.echo_err(cl, "usage: /split [horizontal|vertical] [buffer]"), "", Cont{Nil{}}, split)
    case Sp.SplitOpen{axis, +target}:
      split_apply.open(cl, split, axis, target)
    case Sp.SplitClose{}:
      (Sub.echo_info(cl, "split view closed"), "", Cont{Nil{}}, Sp.Off{})
    case Sp.SplitFocus{}:
      split_apply.focus(cl, split)

def submit_follow.got(
  triple: Cl.Client & String & NetCmd,
  split: Sp.State
) -> Cl.Client & String & NetCmd & Sp.State:
  match triple:
    case (+cl2, draft2, cmd):
      (cl2, draft2, cmd, Sp.follow_active(cl2, split))

def submit_or_split.cmd(
  cmd: Sp.Command,
  +cl: Cl.Client,
  split: Sp.State,
  net: NetState,
  +port: U32,
  +typed: String
) -> Cl.Client & String & NetCmd & Sp.State:
  match cmd:
    case Sp.NotSplit{}:
      submit_follow.got(apply_keys(cl, net, port, typed, True{}), split)
    case _:
      split_apply(cl, split, cmd)

def submit_or_split.enter(
  enter: Bool,
  +cl: Cl.Client,
  split: Sp.State,
  net: NetState,
  +port: U32,
  +typed: String
) -> Cl.Client & String & NetCmd & Sp.State:
  match enter:
    case False{}:
      (cl, typed, Cont{Nil{}}, split)
    case True{}:
      submit_or_split.cmd(Sp.parse(typed), cl, split, net, port, typed)

def submit_or_split(+cl: Cl.Client, split: Sp.State, net: NetState, +port: U32, +typed: String, enter: Bool) -> Cl.Client & String & NetCmd & Sp.State:
  submit_or_split.enter(enter, cl, split, net, port, typed)

def session_typing(+st: Session) -> Ty.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, +typing, _}:
      typing

def session_typers(+st: Session) -> List<&2, String>:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, +typing, _}:
      Ty.names(typing, Cl.active_buf_name(cl))

def session_expire_typing.got(
  +cl: Cl.Client,
  drop: Bool,
  rem: List<&2, U32>,
  +draft: String,
  joined: Bool,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +port: U32,
  pair: Ty.State & Bool
) -> Session & Bool:
  match pair:
    case (typing, changed):
      (Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port}, changed)

def session_expire_typing(+st: Session, +now_ms: U32) -> Session & Bool:
  match st:
    case Session{+cl, drop, rem, +draft, joined, +chan, net, +hist, +size, +seed, +comp, split, +typing, port}:
      session_expire_typing.got(cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, port, Ty.expire_changed(typing, now_ms))

def finish_hist(
  drop: Bool,
  rem: List<&2, U32>,
  joined: Bool,
  +chan: String,
  net: NetState,
  +cl3: Cl.Client,
  +cmd: NetCmd,
  halt: Bool,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +typing: Ty.State,
  +port: U32,
  pair: Hist & String
) -> Session & NetCmd & Bool:
  match pair:
    case (h2, draft3):
      (session_after(cl3, drop, rem, draft3, joined, chan, net, h2, size, seed, comp, split, typing, port, cmd), cmd, halt)

def finish_comp(
  drop: Bool,
  rem: List<&2, U32>,
  joined: Bool,
  +chan: String,
  net: NetState,
  +cl3: Cl.Client,
  +cmd: NetCmd,
  +hist: Hist,
  +size: Size,
  split: Sp.State,
  +typing: Ty.State,
  +port: U32,
  trip: Comp & String & U32
) -> Session & NetCmd & Bool:
  match trip:
    case (comp2, draft3, seed):
      (session_after(cl3, drop, rem, draft3, joined, chan, net, hist, size, seed, comp2, split, typing, port, cmd), cmd, False{})

def finish_keys.comp(
  is_comp: Bool,
  drop: Bool,
  rem: List<&2, U32>,
  joined: Bool,
  +chan: String,
  net: NetState,
  +cl3: Cl.Client,
  +cmd: NetCmd,
  +hist: Hist,
  +size: Size,
  +comp: Comp,
  split: Sp.State,
  +typing: Ty.State,
  +port: U32,
  +typed: String,
  +draft2: String,
  +hdir: HistDir,
  +enter: Bool
) -> Session & NetCmd & Bool:

  match is_comp:
    case True{}:
      finish_comp(drop, rem, joined, chan, net, cl3, cmd, hist, size, split, typing, port, comp_step(cl3, comp, typed))
    case False{}:
      finish_hist(drop, rem, joined, chan, net, cl3, cmd, halt_of(enter, typed), size, seed_of(hdir), CompNone{}, split, typing, port, hist_move(hist, draft2, hdir))

def focus_after(on: Bool, +cl: Cl.Client, split: Sp.State) -> Cl.Client & Sp.State:
  match on:
    case True{}: Sp.toggle(cl, split)
    case False{}: (cl, split)

def nav_after(
  +cl: Cl.Client,
  split: Sp.State,
  enter: Bool,
  tab: Cl.TabDir,
  click: Maybe<&2, Nat>,
  +up: Nat,
  +dn: Nat,
  +focus: U32
) -> Cl.Client & Sp.State:
  +cl2 = snap_if(enter, Cl.apply_active_scroll(apply_click(Cl.cycle_tab(cl, tab), click), up, dn))
  +split2 = Sp.follow_active(cl2, split)
  focus_after(U32.is_eq(focus, 1), cl2, split2)

def finish_keys.nav(
  pair: Cl.Client & Sp.State,
  is_comp: Bool,
  drop: Bool,
  rem: List<&2, U32>,
  joined: Bool,
  +chan: String,
  net: NetState,
  +cmd: NetCmd,
  +hist: Hist,
  +size: Size,
  +comp: Comp,
  +typing: Ty.State,
  +port: U32,
  +typed: String,
  +draft2: String,
  +hdir: HistDir,
  +enter: Bool
) -> Session & NetCmd & Bool:
  match pair:
    case (cl3, split3):
      +h2 = hist_after_enter(hist, typed, enter)
      finish_keys.comp(is_comp, drop, rem, joined, chan, net, cl3, cmd, h2, size, comp, split3, typing, port, typed, draft2, hdir, enter)

def finish_keys(
  drop: Bool,
  rem: List<&2, U32>,
  joined: Bool,
  +chan: String,
  net: NetState,
  keys: Keys,
  +hist: Hist,
  +size: Size,
  +comp: Comp,
  +typing: Ty.State,
  +port: U32,
  quad: Cl.Client & String & NetCmd & Sp.State
) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, +enter, +tab, +click, +up, +dn, +hdir, is_comp, focus}:
      match quad:
        case (cl2, draft2, cmd, split2):
          finish_keys.nav(nav_after(cl2, split2, enter, tab, click, up, dn, focus), is_comp, drop, rem, joined, chan, net, cmd, hist, size, comp, typing, port, typed, draft2, hdir, enter)

def step_keys(+st: Session, +keys: Keys) -> Session & NetCmd & Bool:
  match st:
    case Session{+cl, drop, +rem, _, joined, +chan, net, +hist, size, _, +comp, split, +typing, port}:
      match keys:
        case Keys{+typed, enter, _, _, _, _, _, _, _}:
          finish_keys(drop, rem, joined, chan, net, keys, hist, size, comp, typing, port, submit_or_split(cl, split, net, port, typed, enter))

def step_enter(+st: Session, +line: String) -> Session & NetCmd & Bool:
  step_keys(st, keys_enter(line))

def step_chunk_got(
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +typing: Ty.State,
  +port: U32,
  got: Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool
) -> Session & List<&2, String>:
  match got:
    case (+cl2, rem2, drop2, outs, joined2):
      +typing2 = Ty.retain_client(typing, cl2)
      (Session{cl2, drop2, rem2, draft, joined2, chan, net, hist, size, seed, comp, Sp.normalize(cl2, split), typing2, port}, outs)

def step_on_chunk_pair(
  +cl: Cl.Client,
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +typing: Ty.State,
  +port: U32,
  +joined: Bool,
  +now_ms: U32,
  got: List<&2, String> & List<&2, U32> & Bool
) -> Session & List<&2, String>:
  match got:
    case (+lines, rem2, drop2):
      +typing2 = Ty.apply_lines(typing, lines, now_ms)
      step_chunk_got(
        draft, chan, net, hist, size, seed, comp, split, typing2, port,
        push_pure_join(fold_lines_ms(cl, lines, now_ms), rem2, drop2, joined, chan, lines)
      )

def step_on_chunk_ms(+st: Session, chunk: List<&2, U32>, +now_ms: U32) -> Session & List<&2, String>:
  match st:
    case Session{+cl, drop, rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port}:
      step_on_chunk_pair(cl, draft, chan, net, hist, size, seed, comp, split, typing, port, joined, now_ms, Fr.push_ex(drop, rem, chunk))

def step_on_chunk(+st: Session, chunk: List<&2, U32>) -> Session & List<&2, String>:
  step_on_chunk_ms(st, chunk, 0)

def sess_drop(+st: Session) -> Bool:
  match st:
    case Session{_, drop, _, _, _, _, _, _, _, _, _, _, _, _}:
      drop

def sess_rem_nil.of(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case _:
      False{}

def sess_rem_nil(+st: Session) -> Bool:
  match st:
    case Session{_, _, rem, _, _, _, _, _, _, _, _, _, _, _}:
      sess_rem_nil.of(rem)

def st_of_chunk(p: Session & List<&2, String>) -> Session:
  match p:
    case (+st, _):
      st

def st_of_keys(t: Session & NetCmd & Bool) -> Session:
  match t:
    case (+st, rest):
      match rest:
        case (_, _):
          st

def reconnect_endpoint.got(pair: Session & NetCmd) -> Bool:
  match pair:
    case (_, Dial{+host, port, _}):
      String.eq(host, "127.0.0.1") && U32.is_eq(port, 16668)
    case _:
      False{}

def reconnect_endpoint_ok() -> Bool:
  +cl0 = Cl.init("me", "old.example")
  +cl1 = Cl.set_settings(cl0, Cl.set_autoreconn(Cl.get_settings(cl0), True{}))
  +s0 = session_fail(session_with_client(cl1, "#t"), "initial")
  +s1 = st_of_keys(step_enter(s0, "/connect 127.0.0.1 16668"))
  +s2 = session_fail(session_online(s1), "lost")
  reconnect_endpoint.got(session_autoreconnect(s2))

def disconnect_drop.got(pair: Session & NetCmd) -> Bool:
  match pair:
    case (_, Drop{}): True{}
    case _: False{}

def disconnect_drop_ok() -> Bool:
  +st = session_fail(session_with_client(Cl.init("me", "irc.example"), "#t"), "lost")
  disconnect_drop.got(session_autoreconnect(st))
