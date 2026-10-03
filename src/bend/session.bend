# Pure IRC session: protocol fold, keys, and connection/reconnect transitions.
# No IO. net.bend owns Socket / Chan / TimUI.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./frame.bend as Fr
import ./submit.bend as Sub
import ./auth.bend as Auth
import ./split.bend as Sp
import ./typing.bend as Ty
import ./media.bend as M
import ./upload.bend as Up
import ./view.bend as View
import ./transport_policy.bend as Transport
import ./join_plan.bend as JoinPlan
import ./preferences.bend as Prefs
import ./irc_commands.bend as Commands

# The first welcome names the nickname actually assigned by the server. A
# requested nickname can differ because of server policy or length limits.
# Admit it before authentication, membership policy and the Client feed share
# that identity; malformed/peer/later-other welcomes must not poison the nick.
def registration_nick(+nick: String) -> Bool:
  Commands.word(nick) && Bool.not(Irc.starts_channel(nick)
    || String.contains(nick, "*") || String.contains(nick, ",")
    || String.contains(nick, "!") || String.contains(nick, "@")
    || String.contains(nick, ":"))

def registration_client.accept(allowed: Bool, cl: Cl.Client, nick: String) -> Maybe<&2, Cl.Client>:
  match allowed:
    case False{}: None{}
    case True{}: Some{Cl.set_nick(cl, nick)}

def registration_client.message(welcome: Bool, seen: Bool, +cl: Cl.Client, +line: String, +m: Irc.Message) -> Maybe<&2, Cl.Client>:
  match welcome:
    case False{}: Some{cl}
    case True{}:
      +nick = Irc.msg_param(m, 0n)
      registration_client.accept(Auth.server_source(Irc.source_prefix(line))
        && Nat.is_eq(List.length(&2, String, Irc.msg_params(m)), 2n)
        && registration_nick(nick) && Bool.not(String.is_empty(Irc.msg_param(m, 1n)))
        && (Bool.not(seen) || Irc.ieq(nick, Cl.nick_of(cl))), cl, nick)

def registration_client.parsed(parsed: Maybe<&2, Irc.Message>, seen: Bool, cl: Cl.Client, line: String) -> Maybe<&2, Cl.Client>:
  match parsed:
    case None{}: Some{cl}
    case Some{+m}: registration_client.message(U32.is_eq(Irc.msg_num(m), 1), seen, cl, line, m)

def registration_client(seen: Bool, cl: Cl.Client, +line: String) -> Maybe<&2, Cl.Client>:
  registration_client.parsed(Irc.parse(line), seen, cl, line)

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

def fold_step.normal_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  +cl2 = Feed.feed_at(cl, h, stamp)
  FoldAcc{cl2, List.append(&2, String, Irc.nick433_for(h, Cl.nick_of(cl)), pongs), now_ms}

def fold_step.lag_rtt.on_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +sent: U32, ok: Bool, +stamp: Maybe<&2, String>) -> FoldAcc:
  match ok:
    case True{}:
      +rtt = U32.sub(now_ms, sent)
      +cl2 = Cl.client_set_lag(cl, rtt)
      FoldAcc{Feed.feed_at(cl2, h, stamp), pongs, now_ms}
    case False{}:
      FoldAcc{Feed.feed_at(cl, h, stamp), pongs, now_ms}

def fold_step.lag_rtt_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +sent: U32, +stamp: Maybe<&2, String>) -> FoldAcc:
  fold_step.lag_rtt.on_at(cl, pongs, now_ms, h, sent, U32.is_ge(now_ms, sent) && Bool.not(U32.is_zero(now_ms)), stamp)

def fold_step.lag_on_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, m: Maybe<&2, U32>, +stamp: Maybe<&2, String>) -> FoldAcc:
  match m:
    case None{}:
      fold_step.normal_at(cl, pongs, now_ms, h, stamp)
    case Some{sent}:
      fold_step.lag_rtt_at(cl, pongs, now_ms, h, sent, stamp)

def fold_step.lag_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  fold_step.lag_on_at(cl, pongs, now_ms, h, Irc.extract_pong_lag_line(h), stamp)

def fold_step.auth.fed(fed: FoldAcc, phase: Cl.AuthPhase, outs: List<&2, String>, notice: Auth.Notice) -> FoldAcc:
  match fed:
    case FoldAcc{+cl, pongs, +now_ms}:
      FoldAcc{Auth.apply_reply(cl, phase, notice), List.append(&2, String, List.reverse(&2, String, outs), pongs), now_ms}

def fold_step.auth.feed_at(consumed: Bool, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  match consumed:
    case True{}: FoldAcc{cl, pongs, now_ms}
    case False{}: fold_step.lag_at(cl, pongs, now_ms, h, stamp)

def fold_step.auth_at(reply: Auth.Reply, +cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  match reply:
    case Auth.Reply{phase, outs, notice}:
      fold_step.auth.fed(fold_step.auth.feed_at(Auth.consume_line(cl, h) || Sub.credential_echo(cl, h), cl, pongs, now_ms, h, stamp), phase, outs, notice)

def fold_step.sasl_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  fold_step.auth_at(Auth.step_for(cl, h), cl, pongs, now_ms, h, stamp)

def fold_step.ping_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, ping: Bool, +stamp: Maybe<&2, String>) -> FoldAcc:
  match ping:
    case True{}:
      FoldAcc{cl, Irc.pong_for(h) <> pongs, now_ms}
    case False{}:
      fold_step.sasl_at(cl, pongs, now_ms, h, stamp)

def fold_step.got_at(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String, +stamp: Maybe<&2, String>) -> FoldAcc:
  fold_step.ping_at(cl, pongs, now_ms, h, Irc.is_ping_line(h), stamp)

def fold_step.got(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, +h: String) -> FoldAcc:
  fold_step.got_at(cl, pongs, now_ms, h, None{})

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

# Resolve each typing event against the Client at that wire position. A JOIN
# earlier in one chunk can establish an otherwise ambiguous +channel identity.
def fold_typing_step.fed(fed: FoldAcc, typing: Ty.State) -> FoldAcc & Ty.State:
  match fed:
    case FoldAcc{+cl, pongs, now_ms}:
      (FoldAcc{cl, pongs, now_ms}, Ty.retain_client(typing, cl))

def fold_typing_step.line(+cl: Cl.Client, pongs: List<&2, String>, +now_ms: U32, typing: Ty.State, +line: String) -> FoldAcc & Ty.State:
  fold_typing_step.fed(fold_step.got(cl, pongs, now_ms, line), Ty.apply_line_for(typing, cl, line, now_ms))

def fold_typing_step(st: FoldAcc & Ty.State, line: String) -> FoldAcc & Ty.State:
  match st:
    case (FoldAcc{+cl, pongs, +now_ms}, typing):
      fold_typing_step.line(cl, pongs, now_ms, typing, line)

def fold_lines_typing(+cl: Cl.Client, xs: List<&2, String>, +now_ms: U32, typing: Ty.State) -> FoldAcc & Ty.State:
  List.foldl(~&2, ~String, ~(FoldAcc & Ty.State), ~fold_typing_step, xs, (FoldAcc{cl, Nil{}, now_ms}, typing))

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

def body_h(+rows: U32) -> Nat:
  Sp.page_height(rows, Sp.Off{})

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

def push_pure_typing_join(folded: FoldAcc & Ty.State, rem: List<&2, U32>, drop: Bool, joined: Bool, chan: String, +lines: List<&2, String>) -> (Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool) & Ty.State:
  match folded:
    case (acc, typing): (push_pure_join(fold_fin(acc), rem, drop, joined, chan, lines), typing)

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
  WriterDone{}
  Up{}
  NetFail{msg: String}
  InitialFail{msg: String}

# gen is the connection the UI bumped on this Dial. Stale FromNet is dropped.
type NetCmd is Data:
  Cont{outs: List<&2, String>}
  Dial{host: String, port: U32, gen: U32, nick: String}
  Drop{}
  Pump{gen: U32}
  OpenUrl{url: String}
  Begin{gen: U32}

# One UI channel. FromNet is ignored unless gen is the UI's current one.
type UiMsg is Data:
  FromNet{gen: U32, e: NetEvt}
  UiKey{}
  UiContinue{}
  Resize{}
  UiError{msg: String}
  TypingTick{now_ms: U32}
  MediaFetched{generation: Nat, ticket: Nat, url: String, payload: String}
  UploadFetched{request: Up.Request, result: String, error: U32, http_status: U32}
  PreferencesLoaded{ticket: Nat, snapshot: Maybe<&2, Prefs.Preferences>, code: U32}
  PreferencesSaved{ticket: Nat, code: U32}
  PreferencesDeadline{ticket: Nat}
  Reconnect{host: String, port: U32, gen: U32}
  HistoryLoaded{ticket: Nat, gen: U32, endpoint: String, client: Cl.Client}

# All socket events, including an initial dial failure, share this guard.
def event_current(m: UiMsg, +gen: U32) -> Bool:
  match m:
    case FromNet{got, _}: U32.is_eq(got, gen)
    case _: True{}

# Only the socket owner can acknowledge completed shutdown. Reader EOF is
# independent of the writer's pending queue and must not release the UI.
def writer_done_current(m: UiMsg, +gen: U32) -> Bool:
  match m:
    case FromNet{got, WriterDone{}}: U32.is_eq(got, gen)
    case _: False{}

type NetState is Data:
  Demo{}
  Connecting{}
  Reconnecting{}
  Online{}
  Offline{}
  Stopping{wait: Bool}

def net_label(st: NetState) -> String:
  match st:
    case Demo{}:
      "demo"
    case Connecting{}:
      "connecting"
    case Reconnecting{}:
      "connecting"
    case Online{}:
      "online"
    case Offline{}:
      "offline"
    case Stopping{_}: "stopping"

def net_label_lag.online(+lag: U32, is_zero: Bool) -> String:
  match is_zero:
    case True{}: "online"
    case False{}: "online · " ++ U32.show(lag) ++ "ms"

def net_label_lag(+st: NetState, +lag: U32) -> String:
  match st:
    case Online{}: net_label_lag.online(lag, U32.is_eq(lag, 0))
    case Demo{}: "demo"
    case Connecting{}: "connecting"
    case Reconnecting{}: "connecting"
    case Offline{}: "offline"
    case Stopping{_}: "stopping"

def net_demo_ok() -> Bool:
  String.eq(net_label(Demo{}), "demo") && String.eq(net_label(Online{}), "online")

def show_netcmd(c: NetCmd) -> String:
  match c:
    case Cont{_}:
      "cont"
    case Dial{+host, port, _, _}:
      String.concat("dial:" <> host <> ":" <> U32.show(port) <> Nil{})
    case Drop{}:
      "drop"
    case Pump{_}:
      "pump"
    case OpenUrl{+url}:
      "open:" ++ url
    case Begin{gen}: "begin:" ++ U32.show(gen)

def hold_cmd.outs(net: NetState, outs: List<&2, String>) -> NetCmd:
  match net:
    case Online{}:
      Cont{outs}
    case Connecting{}:
      Cont{Nil{}}
    case Reconnecting{}:
      Cont{Nil{}}
    case Demo{}:
      Cont{Nil{}}
    case Offline{}:
      Cont{Nil{}}
    case Stopping{_}: Cont{Nil{}}

def hold_cmd(net: NetState, cmd: NetCmd) -> NetCmd:
  match cmd:
    case Dial{+host, port, gen, +nick}:
      Dial{host, port, gen, nick}
    case Drop{}:
      Drop{}
    case Pump{gen}:
      Pump{gen}
    case Cont{outs}:
      hold_cmd.outs(net, outs)
    case OpenUrl{+url}:
      OpenUrl{url}
    case Begin{gen}: Begin{gen}

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
    case Reconnecting{}:
      False{}
    case Offline{}:
      False{}
    case Stopping{_}: False{}

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
    case Reconnecting{}:
      connect_apply.busy(cl, False{})
    case _:
      (Sub.echo_sys(cl, "connecting to " ++ host ++ ":" ++ U32.show(port)), "", Dial{host, port, 0, Cl.nick_of(cl)})

def connect_apply.recon_ok(ok: Bool, +cl: Cl.Client, net: NetState, +server: String, +port: U32) -> Cl.Client & String & NetCmd:
  match ok:
    case True{}:
      connect_apply.st(cl, server, port, net)
    case False{}:
      (Sub.echo_err(cl, "cannot reconnect: no server configured"), "", Cont{Nil{}})

# Demo is a fixture state, not a hostname sentinel. A saved single-label
# endpoint (including "s" or "demo") is valid after an explicit connection.
def reconnect_configured(net: NetState, +server: String) -> Bool:
  match net:
    case Demo{}: False{}
    case _: Bool.not(String.is_empty(server))

def connect_apply.reconnect(+cl: Cl.Client, +net: NetState, +server: String, +port: U32) -> Cl.Client & String & NetCmd:
  connect_apply.recon_ok(reconnect_configured(net, server), cl, net, server, port)

def connect_apply(+cl: Cl.Client, net: NetState, +port: U32, c: Sub.Conn) -> Cl.Client & String & NetCmd:
  match c:
    case Sub.ConnBad{}:
      (Sub.echo_err(cl, "usage: /connect host[:port] [port]"), "", Cont{Nil{}})
    case Sub.ConnOk{+host, port}:
      connect_apply.st(cl, host, port, net)
    case Sub.ConnDefault{+host}:
      connect_apply.st(cl, host, port, net)
    case Sub.ConnReconnect{}:
      connect_apply.reconnect(cl, net, Cl.server_of(cl), port)

def open_apply.got(+cl: Cl.Client, mb: Maybe<&2, String>) -> Cl.Client & String & NetCmd:
  match mb:
    case None{}:
      (Sub.echo_err(cl, "no link found"), "", Cont{Nil{}})
    case Some{+url}:
      (Sub.echo_link_result(cl, "opening " ++ url), "", OpenUrl{url})

def wrap_local(pair: Cl.Client & List<&2, String>) -> Cl.Client & String & NetCmd:
  match pair:
    case (cl, _): (cl, "", Cont{Nil{}})

def submit_local(input: Sub.Input, +cl: Cl.Client) -> Cl.Client & String & NetCmd:
  match input:
    case Sub.CommandInput{Sub.Quit{}, +verb, +rest}:
      wrap_outs(Sub.submit_cmd.do(cl, verb, rest, Sub.Quit{}))
    case _:
      wrap_local(Sub.submit_parsed(cl, input))

def submit_offline.wire(+cl: Cl.Client, input: Sub.Input) -> Cl.Client & String & NetCmd:
  match input:
    # PART cancels desired membership even before registration or while offline.
    # Submission validates the target; this local path never emits its wire.
    case Sub.CommandInput{Sub.Part{}, verb, rest}: submit_local(Sub.CommandInput{Sub.Part{}, verb, rest}, cl)
    case _: (Sub.echo_err_server(cl, "not connected"), "", Cont{Nil{}})

def submit_offline(+cl: Cl.Client, +input: Sub.Input, needs_wire: Bool) -> Cl.Client & String & NetCmd:
  match needs_wire:
    case True{}: submit_offline.wire(cl, input)
    case False{}: submit_local(input, cl)

def submit_send(+cl: Cl.Client, +input: Sub.Input, online: Bool) -> Cl.Client & String & NetCmd:
  match online:
    case True{}: wrap_outs(Sub.submit_parsed(cl, input))
    case False{}: submit_offline(cl, input, Sub.needs_connection(input))

def submit_command(cmd: Sub.Slash, +cl: Cl.Client, +net: NetState, +verb: String, +rest: String) -> Cl.Client & String & NetCmd:
  match cmd:
    case Sub.OpenCmd{}: open_apply.got(cl, Sub.open_resolve_target(cl, rest))
    case _: submit_send(cl, Sub.CommandInput{cmd, verb, rest}, can_send(net))

def submit_command.connect(conn: Bool, +cl: Cl.Client, +net: NetState, +port: U32, cmd: Sub.Slash, +verb: String, +rest: String) -> Cl.Client & String & NetCmd:
  match conn:
    case True{}: connect_apply(cl, net, port, Sub.connect_from_input.verb(Irc.ieq(verb, "reconnect"), rest))
    case False{}: submit_command(cmd, cl, net, verb, rest)

def submit_input(input: Sub.Input, +cl: Cl.Client, +net: NetState, +port: U32) -> Cl.Client & String & NetCmd:
  match input:
    case Sub.CommandInput{cmd, +verb, +rest}:
      submit_command.connect(Irc.ieq(verb, "connect") || Irc.ieq(verb, "reconnect"), cl, net, port, cmd, verb, rest)
    case _:
      submit_send(cl, input, can_send(net))

def submit_pair(+cl: Cl.Client, net: NetState, +port: U32, +draft: String, enter: Bool) -> Cl.Client & String & NetCmd:
  match enter:
    case False{}:
      (cl, draft, Cont{Nil{}})
    case True{}:
      submit_input(Sub.parse_input(draft), cl, net, port)

def apply_keys(+cl: Cl.Client, net: NetState, +port: U32, +draft: String, enter: Bool) -> Cl.Client & String & NetCmd:
  submit_pair(cl, net, port, draft, enter)

def cmd_connect.got(triple: Cl.Client & String & NetCmd) -> NetCmd:
  match triple:
    case (_, _, c):
      c

def cmd_connect(+net: NetState, +input: String) -> NetCmd:
  cmd_connect.got(connect_apply(Cl.init("me", "s"), net, Transport.TLS_PORT(), Sub.connect_from_input(input)))

def cmd_connect_ok() -> Bool:
  String.eq(show_netcmd(cmd_connect(Demo{}, "/connect irc.example.net 6668")), "dial:irc.example.net:6668")
    && String.eq(show_netcmd(cmd_connect(Online{}, "/connect irc.example.net")), "dial:irc.example.net:6697")
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
  CompUpload{state: Up.State, completion: Maybe<&2, CompWord>, presented: Bool}

type CompWord is Data:
  CompWord{pre: String, word: String, idx: Nat}

def comp_from_word(word: Maybe<&2, CompWord>) -> Comp:
  match word:
    case None{}: CompNone{}
    case Some{CompWord{pre, word, idx}}: CompActive{pre, word, idx}

def comp_word(comp: Comp) -> Maybe<&2, CompWord>:
  match comp:
    case CompNone{}: None{}
    case CompActive{pre, word, idx}: Some{CompWord{pre, word, idx}}
    case CompUpload{_, completion, _}: completion

def comp_ordinary(comp: Comp) -> Comp:
  comp_from_word(comp_word(comp))

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

def slash_command_names(rows: List<&2, Sub.SlashRow>) -> List<&2, String>:
  match rows:
    case Nil{}: Nil{}
    case Con{Sub.SlashRow{name, _}, rest}: ("/" ++ name) <> slash_command_names(rest)

def slash_command_list() -> List<&2, String>:
  slash_command_names(Sub.slash_rows())

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

def comp_step.upload(word: Maybe<&2, CompWord>, +cl: Cl.Client, +typed: String) -> Comp & String & U32:
  match word:
    case None{}: comp_step.fresh(cl, split_word(typed), typed)
    case Some{CompWord{pre, word, idx}}: comp_step.active(cl, pre, word, idx, typed)

def comp_step(+cl: Cl.Client, comp: Comp, +typed: String) -> Comp & String & U32:
  match comp:
    case CompNone{}:
      comp_step.fresh(cl, split_word(typed), typed)
    case CompActive{+pre, +word, idx}:
      comp_step.active(cl, pre, word, idx, typed)
    case CompUpload{_, completion, _}:
      comp_step.upload(completion, cl, typed)

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
    port: U32,
    media: M.State,
    plan: JoinPlan.State,
    preference_edits: List<&2, String>
  }

def SIZE0() -> Size:
  Size{24, 80}

def session_with_client_at(+cl: Cl.Client, +chan: String, +port: U32) -> Session:
  +plan = JoinPlan.reset(JoinPlan.initial(chan), cl)
  Session{cl, False{}, Nil{}, "", JoinPlan.sent(plan), chan, Connecting{}, hist0(), SIZE0(), 0, comp0(), Sp.state0(), Ty.empty(), port, M.initial(True{}), plan, Nil{}}

def session_with_client(+cl: Cl.Client, +chan: String) -> Session:
  session_with_client_at(cl, chan, Transport.TLS_PORT())

def session0(+nick: String, +host: String, +chan: String) -> Session:
  session_with_client(Cl.init(nick, host), chan)

def session_demo_at(+cl: Cl.Client, +chan: String, port: U32) -> Session:
  +plan = JoinPlan.demo(chan)
  Session{cl, False{}, Nil{}, "", JoinPlan.sent(plan), chan, Demo{}, hist0(), SIZE0(), 0, comp0(), Sp.state0(), Ty.empty(), port, M.initial(True{}), plan, Nil{}}

def session_demo(+cl: Cl.Client, +chan: String) -> Session:
  session_demo_at(cl, chan, Transport.TLS_PORT())

def session_online(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, Online{}, hist, size, seed, comp, split, typing, port, media, plan, edits}

def session_cl(+st: Session) -> Cl.Client:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits}:
      cl

# Explicit accepted settings intent, not a value difference or a log-text guess.
# Only the nine canonical durable names are inserted by the submission hook.
def session_preference_edits(st: Session) -> List<&2, String>:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, edits}: edits

def session_preference_record.on(known: Bool, st: Session, name: String) -> Session:
  match known:
    case True{}: st
    case False{}:
      match st:
        case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}:
          Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, List.append(&2, String, edits, name <> Nil{})}

def session_preference_record(parsed: Maybe<&2, String>, +st: Session) -> Session:
  match parsed:
    case None{}: st
    case Some{+name}: session_preference_record.on(Prefs.has(session_preference_edits(st), name), st, name)

def session_net(+st: Session) -> NetState:
  match st:
    case Session{_, _, _, _, _, _, net, _, _, _, _, _, _, _, _, +plan, +edits}:
      net

def session_set_net(st: Session, net: NetState) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, _, hist, size, seed, comp, split, typing, port, media, plan, +edits}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}

def session_stopping.net(net: NetState) -> Maybe<&2, Bool>:
  match net:
    case Stopping{wait}: Some{wait}
    case _: None{}

def session_stopping(st: Session) -> Maybe<&2, Bool>:
  session_stopping.net(session_net(st))

def session_plan(st: Session) -> JoinPlan.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, plan, +edits}: plan

def session_set_plan(st: Session, +plan: JoinPlan.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, _, chan, net, hist, size, seed, comp, split, typing, port, media, _, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}

def session_channel_revision(st: Session) -> Nat:
  JoinPlan.revision(session_plan(st))

def session_desired_channels(st: Session) -> List<&2, String>:
  JoinPlan.desired_names(session_plan(st))

def session_seed_channels(+st: Session, names: List<&2, String>) -> Session:
  session_set_plan(st, JoinPlan.seed(session_plan(st), names))

def session_seed_channels_if.on(same: Bool, st: Session, names: List<&2, String>) -> Session:
  match same:
    case False{}: st
    case True{}: session_seed_channels(st, names)

def session_seed_channels_if(+st: Session, baseline: Nat, names: List<&2, String>) -> Session:
  session_seed_channels_if.on(Nat.is_eq(session_channel_revision(st), baseline), st, names)

def session_hold_joins(+st: Session) -> Session:
  session_set_plan(st, JoinPlan.set_held(session_plan(st), True{}))

# Install an IO-loaded client without changing connection or UI state.
def session_set_client(st: Session, +cl: Cl.Client) -> Session:
  match st:
    case Session{_, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, +media, +plan, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}

def join_notice(cl: Cl.Client, notice: JoinPlan.Notice) -> Cl.Client:
  match notice:
    case JoinPlan.Quiet{}: cl
    case JoinPlan.Held{}: Cl.diagnostic_notice(cl, Cl.System{}, "channel joins held: waiting for authentication")
    case JoinPlan.Failed{}: Cl.diagnostic_notice(cl, Cl.Error{}, "channel joins held: authentication failed; reconnect to retry")

def session_flush_joins.got(+st: Session, got: JoinPlan.Flush) -> Session & List<&2, String>:
  match got:
    case JoinPlan.Flush{plan, outs, notice}:
      (session_set_client(session_set_plan(st, plan), join_notice(session_cl(st), notice)), outs)

def session_flush_joins(+st: Session) -> Session & List<&2, String>:
  session_flush_joins.got(st, JoinPlan.flush(session_plan(st), session_cl(st)))

def session_resume_joins(+st: Session) -> Session & List<&2, String>:
  session_flush_joins(session_set_plan(st, JoinPlan.set_held(session_plan(st), False{})))

def session_split(+st: Session) -> Sp.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, split, _, _, _, +plan, +edits}: split

def key_pol_for(+st: Session, +key: U32, +mods: U32, +codepoint: U32, +wheel: U32, +rows: U32) -> KeyPol:
  key_pol_raw(key, mods, codepoint, wheel, Sp.page_height(rows, session_split(st)))

def split_key_ok() -> Bool:
  pol_eq(key_pol_raw(KEY_F6(), 0, 0, 0, 9n), 0, 0, 0, 0, 0, 0, 1)
    && pol_eq(key_pol_raw(0, MOD_CTRL(), 119, 0, 9n), 0, 0, 0, 0, 0, 0, 1)
    && pol_eq(key_pol_raw(0, MOD_CTRL(), 120, 0, 9n), 0, 0, 0, 0, 0, 0, 0)

def session_needs_reconnect_marker(+st: Session) -> Bool:
  match st:
    case Session{_, _, _, _, _, _, net, _, _, _, _, _, _, _, _, +plan, +edits}:
      match net:
        case Offline{}: True{}
        case Reconnecting{}: True{}
        case _: False{}

def session_reset_auth(st: Session) -> Session:
  match st:
    case Session{+cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, +media, +plan, +edits}:
      +fresh = Cl.reset_auth(cl)
      +next = JoinPlan.reset(plan, fresh)
      Session{fresh, drop, rem, draft, JoinPlan.sent(next), chan, net, hist, size, seed, comp, split, typing, port, media, next, edits}

def session_reconnected.on(was_off: Bool, +st: Session, +now: String) -> Session:
  match was_off:
    case False{}:
      session_online(st)
    case True{}:
      match st:
        case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits}:
          Session{Cl.reconnect_markers(cl, now), drop, rem, draft, JoinPlan.sent(plan), chan, Online{}, hist, size, seed, comp, split, typing, port, media, plan, edits}

def session_reconnected(+st: Session, +now: String) -> Session:
  +reset = session_reset_auth(st)
  +fresh = session_set_client(reset, Cl.reset_channel_state(session_cl(reset)))
  +online = session_reconnected.on(session_needs_reconnect_marker(st), fresh, now)
  session_set_client(online, Cl.diagnostic_notice(Cl.set_now(session_cl(online), now), Cl.System{}, "IRC connection established"))

def session_fail.got(+msg: String, +st: Session) -> Session:
  match st:
    case Session{+cl, _, _, +draft, joined, +chan, _, +hist, size, seed, +comp, split, _, port, +media, +plan, +edits}:
      Session{Sub.echo_err_server(cl, msg), False{}, Nil{}, draft, JoinPlan.sent(plan), chan, Offline{}, hist, size, seed, comp, split, Ty.empty(), port, media, plan, edits}

def session_fail(+st: Session, +msg: String) -> Session:
  session_fail.got(msg, st)

# A failed local helper does not change the connection or framer state.
def session_error(+st: Session, +msg: String) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits}:
      Session{Sub.echo_err(cl, msg), drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}

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
  +port: U32,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session:
  +cl2 = Sub.echo_sys(cl, "reconnecting in 2s to " ++ server ++ ":" ++ U32.show(port) ++ "...")
  +next = JoinPlan.reset(plan, cl2)
  Session{Cl.diagnostic_notice(cl2, Cl.System{}, "IRC reconnect scheduled in 2s"), False{}, Nil{}, draft, JoinPlan.sent(next), chan, Reconnecting{}, hist, size, seed, comp, split, Ty.empty(), port, M.reset(media), next, edits}

def session_autoreconnect.dial(ok: Bool, +st: Session, +server: String) -> Session & NetCmd:
  match ok:
    case False{}:
      (st, Drop{})
    case True{}:
      match st:
        case Session{+cl, drop, rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, _, port, +media, +plan, +edits}:
          (session_autoreconnect.st(cl, draft, chan, hist, size, seed, comp, split, server, port, media, plan, edits), Dial{server, port, 0, Cl.nick_of(cl)})

def session_autoreconnect.chk(auto: Bool, +st: Session, +server: String) -> Session & NetCmd:
  match auto:
    case False{}:
      (st, Drop{})
    case True{}:
      session_autoreconnect.dial(reconnect_configured(session_net(st), server), st, server)

def session_autoreconnect(+st: Session) -> Session & NetCmd:
  +cl = session_cl(st)
  +stg = Cl.get_settings(cl)
  session_autoreconnect.chk(Cl.settings_autoreconn(stg), st, Cl.server_of(cl))

def session_autoreconnect_on(+st: Session) -> Bool:
  Cl.settings_autoreconn(Cl.get_settings(session_cl(st)))

def session_cancel_reconnect(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, Offline{}, hist, size, seed, comp, split, typing, port, media, plan, edits}

def session_set_now(+st: Session, +ts: String) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits}:
      Session{Cl.set_now(cl, ts), drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}

def session_set_size(+st: Session, +rows: U32, +cols: U32) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, _, seed, +comp, split, +typing, port, +media, +plan, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, Size{rows, cols}, seed, comp, split, typing, port, media, plan, edits}

def session_size(+st: Session) -> Size:
  match st:
    case Session{_, _, _, _, _, _, _, _, size, _, _, _, _, _, _, +plan, +edits}:
      size

def size_eq(a: Size, b: Size) -> Bool:
  match a:
    case Size{ar, ac}:
      match b:
        case Size{br, bc}:
          U32.is_eq(ar, br) && U32.is_eq(ac, bc)

def session_nick(+st: Session) -> String:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits}:
      Cl.nick_of(cl)

def session_port(+st: Session) -> U32:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, port, _, +plan, +edits}: port

def endpoint_client.same(same: Bool, +cl: Cl.Client, +host: String) -> Cl.Client:
  match same:
    case True{}: Cl.set_server(cl, host)
    case False{}:
      match cl:
        case Cl.Client{+nick, _, _, _, +now, +stg, +auth, +seq}:
          +clean = Cl.set_unreads(stg, Nil{})
          Cl.client_set_lag(Cl.Client{nick, host, Cl.server_buf() <> Cl.log_buffers(cl), 0n, now, clean, auth, seq}, 0)

def endpoint_same(+cl: Cl.Client, host: String, old_port: U32, new_port: U32) -> Bool:
  String.eq(Cl.server_of(cl), host) && U32.is_eq(old_port, new_port)

def endpoint_client(+cl: Cl.Client, +host: String, +old_port: U32, +new_port: U32) -> Cl.Client:
  endpoint_client.same(endpoint_same(cl, host, old_port, new_port), Cl.scope_auth_endpoint(cl, host, new_port), host)

# A first connection and a changed endpoint have no reconnect boundary.
# Preserve the same-endpoint intent while the socket is being opened.
def dialing_state.prior(net: NetState) -> NetState:
  match net:
    case Online{}: Reconnecting{}
    case Offline{}: Reconnecting{}
    case Reconnecting{}: Reconnecting{}
    case _: Connecting{}

def dialing_state(same: Bool, net: NetState) -> NetState:
  match same:
    case True{}: dialing_state.prior(net)
    case False{}: Connecting{}

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
  +port: U32,
  +old_port: U32,
  net: NetState,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session:
  +same = endpoint_same(cl, host, old_port, port)
  +next_net = dialing_state(same, net)
  +cl2 = endpoint_client(cl, host, old_port, port)
  +next = JoinPlan.endpoint(same, plan, chan, cl2)
  Session{cl2, False{}, Nil{}, draft, JoinPlan.sent(next), chan, next_net, hist, size, seed, comp, Sp.normalize(cl2, split), Ty.empty(), port, M.reset(media), next, edits}

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
  cmd: NetCmd,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session:
  match cmd:
    case Dial{+host, dial_port, _, _}:
      session_after.dial(cl, draft, chan, hist, size, seed, comp, split, host, dial_port, port, net, media, plan, edits)
    case Drop{}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}
    case Pump{_}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}
    case Cont{_}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}
    case OpenUrl{_}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}
    case Begin{_}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}

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
    case Session{_, _, _, _, _, _, _, _, _, seed, _, _, _, _, _, +plan, +edits}:
      seed

def session_draft(+st: Session) -> String:
  match st:
    case Session{_, _, _, draft, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits}:
      draft

def comp_upload_state(comp: Comp) -> Up.State:
  match comp:
    case CompUpload{state, _, _}: state
    case _: Up.empty()

def session_upload(st: Session) -> Up.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, comp, _, _, _, _, +plan, +edits}: comp_upload_state(comp)

def session_upload_scope(st: Session) -> Up.Scope:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, _, port, _, +plan, +edits}:
      Up.Scope{Cl.server_of(cl), port, Cl.active_buf_name(cl)}

def session_upload_online.net(net: NetState) -> Bool:
  match net:
    case Online{}: True{}
    case _: False{}

def session_upload_online(st: Session) -> Bool:
  match st:
    case Session{+cl, _, _, _, _, _, net, _, _, _, _, _, _, _, _, +plan, +edits}:
      session_upload_online.net(net) && Bool.not(Nat.is_eq(Cl.active_of(cl), 0n) || Sub.active_is_synthetic(cl))

# Only an unchanged Confirm can cross the presentation barrier. In particular,
# Busy -> Confirm resets it even when two batch files have the same path.
def upload_confirmation_eq(before: Up.State, after: Up.State) -> Bool:
  match before:
    case Up.Confirm{request, _}:
      match after:
        case Up.Confirm{next, _}: Up.request_eq(request, next)
        case _: False{}
    case _: False{}

def comp_upload_presented(comp: Comp) -> Bool:
  match comp:
    case CompUpload{Up.Confirm{_, _}, _, presented}: presented
    case _: False{}

def session_upload_presented(st: Session) -> Bool:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, comp, _, _, _, _, +plan, +edits}: comp_upload_presented(comp)

def comp_set_upload(+state: Up.State, +comp: Comp) -> Comp:
  match state:
    case Up.Idle{}: comp_ordinary(comp)
    case _: CompUpload{state, comp_word(comp), comp_upload_presented(comp) && upload_confirmation_eq(comp_upload_state(comp), state)}

def session_set_upload(st: Session, state: Up.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, +plan, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp_set_upload(state, comp), split, typing, port, media, plan, edits}

def comp_upload_mark(comp: Comp, presented: Bool) -> Comp:
  match comp:
    case CompUpload{+state, completion, _}:
      CompUpload{state, completion, presented && upload_confirmation_eq(state, state)}
    case _: comp

def session_upload_mark(st: Session, presented: Bool) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, media, +plan, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp_upload_mark(comp, presented), split, typing, port, media, plan, edits}

def upload_presentation_reset_ok() -> Bool:
  +request: Up.Request = Up.Request{Up.Scope{"s", 6667, "#c"}, "/tmp/a"}
  +pending: Up.State = Up.Confirm{request, Nil{}}
  +painted: Comp = CompUpload{pending, None{}, True{}}
  Bool.not(comp_upload_presented(comp_set_upload(pending, CompNone{})))
    && comp_upload_presented(comp_set_upload(pending, painted))
    && Bool.not(comp_upload_presented(comp_set_upload(Up.Busy{request, Nil{}, True{}}, painted)))
    && Bool.not(comp_upload_presented(comp_set_upload(pending, CompUpload{Up.Busy{request, Nil{}, True{}}, None{}, False{}})))

def session_upload_draft(st: Session, draft: String, seed: U32) -> Session:
  match st:
    case Session{cl, drop, rem, _, joined, chan, net, hist, size, _, comp, split, typing, port, media, +plan, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}

def upload_basename(parts: List<&2, String>, previous: String) -> String:
  match parts:
    case Nil{}: previous
    case Con{part, rest}: upload_basename(rest, part)

def upload_hint(request: Up.Request, remaining: List<&2, String>) -> String:
  match request:
    case Up.Request{Up.Scope{_, _, target}, path}:
      "F8: upload publicly to 0x0.st; Esc: cancel | " ++ target ++ " | "
        ++ String.take(upload_basename(String.split(path, Chr{47}), "file"), 128n)
        ++ " (files=" ++ Nat.show(Nat.add(1n, List.length(&2, String, remaining))) ++ ")"

def session_upload_hint.state(state: Up.State) -> String:
  match state:
    case Up.Confirm{request, remaining}: upload_hint(request, remaining)
    case Up.Ready{request, remaining}: upload_hint(request, remaining)
    case _: ""

def session_upload_hint(+st: Session) -> String:
  session_upload_hint.state(session_upload(st))

# Every connection/focus transition must call this, not only completion. Busy
# retains physical ownership but cannot regain permission after leaving scope.
def session_upload_maintain(+st: Session) -> Session:
  session_set_upload(st, Up.retain(session_upload(st), session_upload_scope(st), session_upload_online(st)))

# Call after a frame and its keys are processed. A newly staged or completed
# request must first survive a later warning frame; this frame cannot arm it.
def session_upload_present(before: Session, +after: Session) -> Session:
  session_upload_mark(after, upload_confirmation_eq(session_upload(before), session_upload(after)))

def session_upload_key.confirm(confirm: Bool, +st: Session) -> Session & Bool:
  match confirm:
    case False{}: (st, False{})
    case True{}:
      (session_set_upload(st, Up.confirm(session_upload(st), session_upload_scope(st), session_upload_online(st))), True{})

def session_upload_key.cancel(cancel: Bool, confirm: Bool, +st: Session) -> Session & Bool:
  match cancel:
    case False{}: session_upload_key.confirm(confirm, st)
    case True{}:
      (session_set_upload(st, Up.cancel(session_upload(st))), True{})

def session_upload_key(+st: Session, +key: U32, mods: U32) -> Session & Bool:
  session_upload_key.cancel(U32.is_eq(key, KEY_ESCAPE()) && Up.active(session_upload(st)),
    U32.is_eq(key, 22) && U32.is_zero(mods) && Up.pending(session_upload(st)) && session_upload_presented(st), session_upload_maintain(st))

def session_upload_take.got(pair: Up.State & Maybe<&2, Up.Request>, st: Session) -> Session & Maybe<&2, Up.Request>:
  match pair:
    case (state, request): (session_set_upload(st, state), request)

def session_upload_take(+st: Session) -> Session & Maybe<&2, Up.Request>:
  +next = session_upload_maintain(st)
  session_upload_take.got(Up.take_job(session_upload(next)), next)

def session_upload_complete.got(pair: Up.State & Maybe<&2, String>, +st: Session) -> Session & Maybe<&2, String>:
  match pair:
    case (+state, result):
      (session_set_upload(st, state), result)

def session_upload_complete(+st: Session, request: Up.Request, result: String) -> Session & Maybe<&2, String>:
  session_upload_complete.got(Up.finish(session_upload(st), request, session_upload_scope(st), session_upload_online(st), result), st)

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
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, +typing, _, _, +plan, +edits}:
      typing

def session_typers(+st: Session) -> List<&2, String>:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _, _, _, +typing, _, _, +plan, +edits}:
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
  pair: Ty.State & Bool,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session & Bool:
  match pair:
    case (typing, changed):
      (Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}, changed)

def session_expire_typing(+st: Session, +now_ms: U32) -> Session & Bool:
  match st:
    case Session{+cl, drop, rem, +draft, joined, +chan, net, +hist, +size, +seed, +comp, split, +typing, port, +media, +plan, +edits}:
      session_expire_typing.got(cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, port, Ty.expire_changed(typing, now_ms), media, plan, edits)

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
  pair: Hist & String,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session & NetCmd & Bool:
  match pair:
    case (h2, draft3):
      (session_after(cl3, drop, rem, draft3, joined, chan, net, h2, size, seed, comp, split, typing, port, cmd, media, plan, edits), cmd, halt)

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
  trip: Comp & String & U32,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session & NetCmd & Bool:
  match trip:
    case (comp2, draft3, seed):
      (session_after(cl3, drop, rem, draft3, joined, chan, net, hist, size, seed, comp2, split, typing, port, cmd, media, plan, edits), cmd, False{})

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
  +enter: Bool,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session & NetCmd & Bool:

  match is_comp:
    case True{}:
      finish_comp(drop, rem, joined, chan, net, cl3, cmd, hist, size, split, typing, port, comp_step(cl3, comp, typed), media, plan, edits)
    case False{}:
      finish_hist(drop, rem, joined, chan, net, cl3, cmd, halt_of(enter, typed), size, seed_of(hdir), CompNone{}, split, typing, port, hist_move(hist, draft2, hdir), media, plan, edits)

def focus_after(on: Bool, +cl: Cl.Client, split: Sp.State) -> Cl.Client & Sp.State:
  match on:
    case True{}: Sp.toggle(cl, split)
    case False{}: (cl, split)

def nav_after(
  +cl: Cl.Client,
  split: Sp.State,
  size: Size,
  enter: Bool,
  tab: Cl.TabDir,
  click: Maybe<&2, Nat>,
  +up: Nat,
  +dn: Nat,
  +focus: U32,
  +media: M.State
) -> Cl.Client & Sp.State:
  match size:
    case Size{rows, cols}:
      +cl2 = apply_click(Cl.cycle_tab(cl, tab), click)
      +split2 = Sp.follow_active(cl2, split)
      +cl3 = snap_if(enter, View.scroll_active_media(cl2, rows, cols, split2, up, dn, media))
      focus_after(U32.is_eq(focus, 1), cl3, split2)

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
  +enter: Bool,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session & NetCmd & Bool:
  match pair:
    case (cl3, split3):
      finish_keys.comp(is_comp, drop, rem, joined, chan, net, cl3, cmd, hist, size, comp, split3, typing, port, typed, draft2, hdir, enter, media, plan, edits)

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
  quad: Cl.Client & String & NetCmd & Sp.State,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, +enter, +tab, +click, +up, +dn, +hdir, is_comp, focus}:
      match quad:
        case (cl2, draft2, cmd, split2):
          finish_keys.nav(nav_after(cl2, split2, size, enter, tab, click, up, dn, focus, media), is_comp, drop, rem, joined, chan, net, cmd, hist, size, comp, typing, port, typed, draft2, hdir, enter, media, plan, edits)

def step_keys.base(+st: Session, +keys: Keys) -> Session & NetCmd & Bool:
  match st:
    case Session{+cl, drop, +rem, _, joined, +chan, net, +hist, size, _, +comp, split, +typing, port, +media, +plan, +edits}:
      match keys:
        case Keys{+typed, enter, _, _, _, _, _, _, _}:
          +hist2 = hist_after_enter(hist, typed, enter && Bool.not(Sub.input_sensitive(cl, typed)))
          finish_keys(drop, rem, joined, chan, net, keys, hist2, size, comp, typing, port, submit_or_split(cl, split, net, port, typed, enter), media, plan, edits)

def session_media(st: Session) -> M.State:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, _, _, _, _, _, media, +plan, +edits}: media

def session_set_media(st: Session, media: M.State) -> Session:
  match st:
    case Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed, comp, split, typing, port, _, +plan, +edits}:
      Session{cl, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, split, typing, port, media, plan, edits}

def online_media(net: NetState) -> Bool:
  match net:
    case Online{}: True{}
    case _: False{}

def session_observe_media(+st: Session, after: Nat) -> Session:
  session_set_media(st, M.observe(session_media(st), session_cl(st), after, online_media(session_net(st))))

def images_intent.parsed(+st: Session, intent: Maybe<&2, Bool>) -> Session:
  match intent:
    case None{}: st
    case Some{on}: session_set_media(st, M.set_enabled(session_media(st), on))

def images_intent(+st: Session, +arg: String) -> Session:
  images_intent.parsed(st, Sub.images_arg(arg))

def media_intent.parsed(+st: Session, input: Sub.Input) -> Session:
  match input:
    case Sub.CommandInput{Sub.ImagesCmd{}, _, rest}: images_intent(st, Irc.drop_spaces(rest))
    case Sub.CommandInput{Sub.PreviewCmd{}, _, +rest}:
      +arg = Irc.drop_spaces(rest)
      +source = Bool.pick(String, Sub.is_http_pfx(arg), arg, Sub.preview_local_path(arg))
      +current = M.maintain(session_media(st), session_cl(st))
      +full = M.manual_saturated(current, source) && M.alive(session_cl(st), M.Manual{}, source)
      +media = M.enqueue(current, M.Manual{}, source)
      +next = session_set_media(st, M.maintain(media, session_cl(st)))
      Bool.pick(Session, full, session_error(next, "image preview queue is full; try again"), next)
    case _: st

def media_intent(enter: Bool, +st: Session, typed: String) -> Session:
  match enter:
    case False{}: st
    case True{}: media_intent.parsed(st, Sub.parse_input(typed))

def step_keys.intent(keys: Keys, +after: Nat, trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match keys:
    case Keys{typed, enter, _, _, _, _, _, _, _}:
      match trip:
        case (st, cmd, halt): (session_observe_media(media_intent(enter, st, typed), after), cmd, halt)

def step_keys.plan.got(pair: JoinPlan.State & List<&2, String>, st: Session, halt: Bool) -> Session & NetCmd & Bool:
  match pair:
    case (plan, outs): (session_set_plan(st, plan), Cont{outs}, halt)

# Only accepted submission outputs change desired membership. Recovery emits
# bypass this seam, so it cannot turn a reset into an explicit settings edit.
def local_plan.got(pair: JoinPlan.State & List<&2, String>, st: Session) -> Session:
  match pair:
    case (plan, _): session_set_plan(st, plan)

def local_plan.validated(pair: Cl.Client & List<&2, String>, +st: Session) -> Session:
  match pair:
    case (_, outs): local_plan.got(JoinPlan.outbound(session_plan(st), outs), st)

def local_plan.input(input: Sub.Input, cl: Cl.Client, st: Session) -> Session:
  match input:
    case Sub.CommandInput{Sub.Part{}, verb, rest}: local_plan.validated(Sub.submit_parsed(cl, Sub.CommandInput{Sub.Part{}, verb, rest}), st)
    case Sub.CommandInput{Sub.CloseCmd{}, verb, rest}: local_plan.validated(Sub.submit_parsed(cl, Sub.CommandInput{Sub.CloseCmd{}, verb, rest}), st)
    case _: st

# Local submission drops wire output. Reuse its validator against the prior
# client to recover only accepted PART/close intent, never a guessed target.
def local_plan.enter(local: Bool, +before: Session, st: Session, raw: String) -> Session:
  match local:
    case False{}: st
    case True{}: local_plan.input(Sub.parse_input(raw), session_cl(before), st)

def local_plan.keys(keys: Keys, +before: Session, st: Session) -> Session:
  match keys:
    case Keys{raw, enter, _, _, _, _, _, _, _}:
      local_plan.enter(enter && Bool.not(can_send(session_net(before))), before, st, raw)

def step_keys.plan.admit(allowed: Bool, +before: Session, +st: Session, outs: List<&2, String>, halt: Bool) -> Session & NetCmd & Bool:
  match allowed:
    case True{}: step_keys.plan.got(JoinPlan.outbound(session_plan(st), outs), st, halt)
    case False{}:
      # The rejected JOIN has no accepted membership. Discard its staged
      # tab/roster changes as well as the wire and runtime-only key update.
      (session_set_client(session_set_plan(st, session_plan(before)),
        Sub.echo_err_server(session_cl(before), "channel limit reached (14 desired channels)")), Cont{Nil{}}, halt)

def step_keys.plan(+before: Session, keys: Keys, trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match trip:
    case (+st, cmd, halt):
      match cmd:
        case Cont{+outs}:
          +next = local_plan.keys(keys, before, st)
          step_keys.plan.admit(JoinPlan.capacity_ok(outs, session_plan(next)), before, next, outs, halt)
        case _: (st, cmd, halt)

def preference_enter(enter: Bool, st: Session, typed: String) -> Session:
  match enter:
    case False{}: st
    case True{}: session_preference_record(Sub.preference_intent(Sub.parse_input(typed)), st)

def step_keys.preferences(keys: Keys, trip: Session & NetCmd & Bool) -> Session & NetCmd & Bool:
  match keys:
    case Keys{typed, enter, _, _, _, _, _, _, _}:
      match trip:
        case (st, cmd, halt): (preference_enter(enter, st, typed), cmd, halt)

def step_keys.normal(+st: Session, +keys: Keys) -> Session & NetCmd & Bool:
  step_keys.preferences(keys, step_keys.intent(keys, Cl.log_seq_of(session_cl(st)), step_keys.plan(st, keys, step_keys.base(st, keys))))

def step_keys.upload_restore(trip: Session & NetCmd & Bool, state: Up.State, presented: Bool) -> Session & NetCmd & Bool:
  match trip:
    case (st, cmd, halt): (session_upload_maintain(session_upload_mark(session_set_upload(st, state), presented)), cmd, halt)

# Completion and worker state have distinct nonrecursive payloads. Ordinary
# editing/history/completion can proceed while Busy without dropping its owner.
def step_keys.ordinary(+st: Session, keys: Keys) -> Session & NetCmd & Bool:
  step_keys.upload_restore(step_keys.normal(session_set_upload(st, Up.empty()), keys), session_upload(st), session_upload_presented(st))

def upload_modal_keys(keys: Keys) -> Keys:
  match keys:
    case Keys{typed, _, tab, click, up, dn, hist, comp, focus}:
      Keys{typed, False{}, tab, click, up, dn, hist, comp, focus}

def step_keys.upload_blocked(trip: Session & NetCmd & Bool, enter: Bool) -> Session & NetCmd & Bool:
  match trip:
    case (+st, cmd, halt):
      # Native Enter clears its editor; restore the same unsent draft once.
      (Bool.pick(Session, enter, session_upload_draft(st, session_draft(st), 1), st), cmd, halt)

type UploadInput is Data:
  NotUpload{}
  UploadPaths{paths: List<&2, String>}
  UploadBad{}

def upload_input.paths(got: Maybe<&2, List<&2, String>>, explicit: Bool, raw: String) -> UploadInput:
  match got:
    case None{}: Bool.pick(UploadInput, explicit || Up.looks_local_drop(raw), UploadBad{}, NotUpload{})
    case Some{paths}: UploadPaths{paths}

# Bare /name is a command, not an ambiguous root-level file. A second slash
# or literal path quoting/escaping in the verb marks a drop; later arguments
# cannot supply that intent. Explicit /upload remains the root-file escape hatch.
def upload_input.path_verb(+verb: String) -> Bool:
  Bool.not(String.contains(verb, "://"))
    && (String.contains(verb, "/") || String.contains(verb, "\\")
      || String.contains(verb, "'") || String.contains(verb, "\""))

def upload_input.unknown(command: Bool, +raw: String) -> UploadInput:
  match command:
    case True{}: NotUpload{}
    case False{}: upload_input.paths(Up.parse_paths(raw, True{}), False{}, raw)

def upload_input.parsed(input: Sub.Input, +raw: String) -> UploadInput:
  match input:
    case Sub.CommandInput{Sub.UploadCmd{}, _, rest}: upload_input.paths(Up.parse_paths(rest, False{}), True{}, raw)
    case Sub.CommandInput{Sub.Unknown{}, +verb, _}: upload_input.unknown(Sub.slash_known(verb) || Bool.not(upload_input.path_verb(verb)), raw)
    case Sub.PlainInput{_}: upload_input.paths(Up.parse_paths(raw, True{}), False{}, raw)
    case _: NotUpload{}

def upload_input(keys: Keys) -> UploadInput:
  match keys:
    case Keys{+typed, enter, _, _, _, _, _, _, _}:
      match enter:
        case False{}: NotUpload{}
        case True{}: upload_input.parsed(Sub.parse_input(typed), typed)

def step_keys.upload_offer.busy(busy: Bool, +st: Session, paths: List<&2, String>) -> Session & NetCmd & Bool:
  match busy:
    case True{}: (session_error(session_upload_draft(st, "", 1), "upload already in progress"), Cont{Nil{}}, False{})
    case False{}:
      +state = Up.offer(Up.empty(), session_upload_scope(st), session_upload_online(st), paths)
      +next = session_upload_draft(session_set_upload(st, state), "", 1)
      (Bool.pick(Session, Up.pending(state), next, session_error(next, "upload requires an online chat target")), Cont{Nil{}}, False{})

def step_keys.upload_input(input: UploadInput, +st: Session, keys: Keys) -> Session & NetCmd & Bool:
  match input:
    case NotUpload{}: step_keys.ordinary(st, keys)
    case UploadBad{}: (session_error(session_upload_draft(st, "", 1), "usage: /upload <local-path>"), Cont{Nil{}}, False{})
    case UploadPaths{paths}: step_keys.upload_offer.busy(Up.active(session_upload(st)), st, paths)

def step_keys.upload_modal(pending: Bool, +st: Session, +keys: Keys) -> Session & NetCmd & Bool:
  match pending:
    case True{}:
      match keys:
        case Keys{_, enter, _, _, _, _, _, _, _}:
          step_keys.upload_blocked(step_keys.ordinary(st, upload_modal_keys(keys)), enter)
    case False{}: step_keys.upload_input(upload_input(keys), st, keys)

def step_keys(+st: Session, keys: Keys) -> Session & NetCmd & Bool:
  +next = session_upload_maintain(st)
  step_keys.upload_modal(Up.pending(session_upload(next)), next, keys)

def step_enter(+st: Session, +line: String) -> Session & NetCmd & Bool:
  step_keys(st, keys_enter(line))

type StampedLine is Data:
  StampedLine{wire: String, stamp: Maybe<&2, String>}

def stamped_lines(lines: List<&2, String>, stamps: List<&2, Maybe<&2, String>>) -> List<&2, StampedLine>:
  match lines:
    case Nil{}: Nil{}
    case Con{line, rest}:
      match stamps:
        case Nil{}: StampedLine{line, None{}} <> stamped_lines(rest, Nil{})
        case Con{stamp, tail}: StampedLine{line, stamp} <> stamped_lines(rest, tail)

type LiveAcc is Data:
  LiveAcc{fold: FoldAcc, typing: Ty.State, plan: JoinPlan.State}

def live_step.flushed(fed: FoldAcc, typing: Ty.State, flushed: JoinPlan.Flush) -> LiveAcc:
  match fed:
    case FoldAcc{+cl, reversed, now_ms}:
      match flushed:
        case JoinPlan.Flush{plan, outs, notice}:
          LiveAcc{FoldAcc{join_notice(cl, notice), List.append(&2, String, List.reverse(&2, String, outs), reversed), now_ms}, Ty.retain_client(typing, cl), plan}

def live_step.fed(+fed: FoldAcc, typing: Ty.State, plan: JoinPlan.State) -> LiveAcc:
  match fed:
    case FoldAcc{+cl, _, _}: live_step.flushed(fed, typing, JoinPlan.flush(plan, cl))

# Keep the original wire text for protocol/authentication/membership policy.
# A local timestamp override affects only the display/history feed.
def live_step.registered(registered: Maybe<&2, Cl.Client>, acc: LiveAcc, +line: String, stamp: Maybe<&2, String>) -> LiveAcc:
  match registered:
    case None{}: acc
    case Some{+cl}:
      match acc:
        case LiveAcc{FoldAcc{_, reversed, +now_ms}, typing, plan}:
          live_step.fed(fold_step.got_at(cl, reversed, now_ms, line, stamp),
            Ty.apply_line_for(typing, cl, line, now_ms), JoinPlan.received(plan, cl, line))

def live_step(acc: LiveAcc, item: StampedLine) -> LiveAcc:
  match acc:
    case LiveAcc{FoldAcc{+cl, reversed, now_ms}, typing, +plan}:
      match item:
        case StampedLine{+line, stamp}:
          live_step.registered(registration_client(JoinPlan.welcomed(plan), cl, line),
            LiveAcc{FoldAcc{cl, reversed, now_ms}, typing, plan}, line, stamp)

def step_chunk_got(
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  +comp: Comp,
  split: Sp.State,
  +port: U32,
  rem: List<&2, U32>,
  drop: Bool,
  got: LiveAcc,
  +media: M.State,
  +edits: List<&2, String>
) -> Session & List<&2, String>:
  match got:
    case LiveAcc{FoldAcc{+cl2, reversed, _}, typing, +plan}:
      +typing2 = Ty.retain_client(typing, cl2)
      (Session{cl2, drop, rem, draft, JoinPlan.sent(plan), chan, net, hist, size, seed, comp, Sp.normalize(cl2, split), typing2, port, media, plan, edits}, List.reverse(&2, String, reversed))

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
  +now_ms: U32,
  got: List<&2, String> & List<&2, U32> & Bool,
  stamps: List<&2, Maybe<&2, String>>,
  +media: M.State,
  +plan: JoinPlan.State,
  +edits: List<&2, String>
) -> Session & List<&2, String>:
  match got:
    case (+lines, rem2, drop2):
      +split2 = Sp.rename_queries(split, lines)
      step_chunk_got(
        draft, chan, net, hist, size, seed, comp, split2, port, rem2, drop2,
        List.foldl(~&2, ~StampedLine, ~LiveAcc, ~live_step, stamped_lines(lines, stamps), LiveAcc{FoldAcc{cl, Nil{}, now_ms}, typing, plan}), media, edits)

def frame_chunk(st: Session, chunk: List<&2, U32>) -> List<&2, String> & List<&2, U32> & Bool:
  match st:
    case Session{_, drop, rem, _, _, _, _, _, _, _, _, _, _, _, _, _, +edits}: Fr.push_ex(drop, rem, chunk)

def step_on_framed_ms.base(+st: Session, framed: List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Session & List<&2, String>:
  match st:
    case Session{+cl, drop, rem, +draft, joined, +chan, net, +hist, size, seed, +comp, split, +typing, port, +media, +plan, +edits}:
      step_on_chunk_pair(cl, draft, chan, net, hist, size, seed, comp, split, typing, port, now_ms, framed, stamps, media, plan, edits)

def step_on_chunk_ms.observed(after: Nat, trip: Session & List<&2, String>) -> Session & List<&2, String>:
  match trip:
    case (st, outs): (session_observe_media(st, after), outs)

def step_on_framed_ms(+st: Session, framed: List<&2, String> & List<&2, U32> & Bool, stamps: List<&2, Maybe<&2, String>>, +now_ms: U32) -> Session & List<&2, String>:
  step_on_chunk_ms.observed(Cl.log_seq_of(session_cl(st)), step_on_framed_ms.base(st, framed, stamps, now_ms))

def step_on_chunk_ms(+st: Session, chunk: List<&2, U32>, +now_ms: U32) -> Session & List<&2, String>:
  step_on_framed_ms(st, frame_chunk(st, chunk), Nil{}, now_ms)

def step_on_chunk(+st: Session, chunk: List<&2, U32>) -> Session & List<&2, String>:
  step_on_chunk_ms(st, chunk, 0)

def sess_drop(+st: Session) -> Bool:
  match st:
    case Session{_, drop, _, _, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits}:
      drop

def sess_rem_nil.of(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case _:
      False{}

def sess_rem_nil(+st: Session) -> Bool:
  match st:
    case Session{_, _, rem, _, _, _, _, _, _, _, _, _, _, _, _, +plan, +edits}:
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
    case (_, Dial{+host, port, _, _}):
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
