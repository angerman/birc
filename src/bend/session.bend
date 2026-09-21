# Pure IRC session: fold, JOIN-after-001, keys. No reconnect/backoff.
# No IO. net.bend owns Socket / Chan / TimUI.
import Base
import ./irc.bend as Irc
import ./client.bend as Cl
import ./frame.bend as Fr
import ./submit.bend as Sub

def register_lines(+nick: String) -> List<&2, String>:
  Irc.format_nick(nick) <> Irc.format_user(nick) <> Nil{}

type FoldAcc is Data:
  FoldAcc{cl: Cl.Client, pongs: List<&2, String>}

def fold_step.ping(+cl: Cl.Client, pongs: List<&2, String>, +h: String, ping: Bool) -> FoldAcc:
  match ping:
    case True{}:
      FoldAcc{cl, Irc.pong_for(h) <> pongs}
    case False{}:
      +cl2 = Cl.feed(cl, h)
      FoldAcc{cl2, List.append(&2, String, Irc.nick433_for(h, Cl.nick_of(cl)), pongs)}

def fold_step.got(+cl: Cl.Client, pongs: List<&2, String>, +h: String) -> FoldAcc:
  fold_step.ping(cl, pongs, h, Irc.is_ping_line(h))

def fold_step(st: FoldAcc, h: String) -> FoldAcc:
  match st:
    case FoldAcc{+cl, pongs}:
      fold_step.got(cl, pongs, h)

def fold_fin(st: FoldAcc) -> Cl.Client & List<&2, String>:
  match st:
    case FoldAcc{+cl, pongs}:
      (cl, List.reverse(&2, String, pongs))

def fold_lines(+cl: Cl.Client, +xs: List<&2, String>) -> Cl.Client & List<&2, String>:
  fold_fin(List.foldl(~&2, ~String, ~FoldAcc, ~fold_step, xs, FoldAcc{cl, Nil{}}))

def is_001_msg(+m: Irc.Message) -> Bool:
  match m:
    case Irc.Message{_, _, +num, _}:
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
      U32.to_nat(U32.sub(rows, 6))
    case False{}:
      1n

def body_h(+rows: U32) -> Nat:
  body_h_on(rows, U32.is_ge(rows, 7))

# Packed body lines must not exceed C's drawable rows (root.h-6).
def body_h_ok() -> Bool:
  Nat.is_eq(body_h(24), 18n) && Nat.is_eq(body_h(16), 10n) && Nat.is_eq(body_h(6), 1n)

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

def push_pure_pair(
  +cl: Cl.Client,
  got: List<&2, String> & List<&2, U32> & Bool,
  +joined: Bool,
  +chan: String
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  match got:
    case (+lines, rem2, drop2):
      push_pure_join(fold_lines(cl, lines), rem2, drop2, joined, chan, lines)

def push_pure(
  +cl: Cl.Client,
  drop: Bool,
  rem: List<&2, U32>,
  chunk: List<&2, U32>,
  +joined: Bool,
  +chan: String
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  push_pure_pair(cl, Fr.push_ex(drop, rem, chunk), joined, chan)

def step_chunk(
  +cl: Cl.Client,
  drop: Bool,
  rem: List<&2, U32>,
  chunk: List<&2, U32>,
  +joined: Bool,
  +chan: String
) -> Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool:
  push_pure(cl, drop, rem, chunk, joined, chan)

type NetEvt is Data:
  Chunk{xs: List<&2, U32>}
  Eof{}
  Tick{}
  Up{}
  Fail{msg: String}

type NetCmd is Data:
  Cont{outs: List<&2, String>}
  Dial{host: String, port: U32}
  Handoff{take: Bool}

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

def net_demo_ok() -> Bool:
  String.eq(net_label(Demo{}), "demo") && String.eq(net_label(Online{}), "online")

def show_netcmd(c: NetCmd) -> String:
  match c:
    case Cont{_}:
      "cont"
    case Dial{+host, port}:
      "dial:" ++ host ++ ":" ++ U32.show(port)
    case Handoff{take}:
      "handoff:" ++ Bool.show(take)

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
    case Dial{+host, port}:
      Dial{host, port}
    case Handoff{take}:
      Handoff{take}
    case Cont{outs}:
      hold_cmd.outs(net, outs)

# One NetCmd per NetEvt: chunk PONG/JOIN outs ride with the UI cmd.
def merge_cmd(+pending: List<&2, String>, cmd: NetCmd) -> NetCmd:
  match cmd:
    case Dial{+host, port}:
      Dial{host, port}
    case Handoff{take}:
      Handoff{take}
    case Cont{outs}:
      Cont{List.append(&2, String, pending, outs)}

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
    case Online{}:
      connect_apply.busy(cl, True{})
    case Connecting{}:
      connect_apply.busy(cl, False{})
    case Demo{}:
      (Sub.echo_sys(cl, "connecting to " ++ host ++ ":" ++ U32.show(port)), "", Dial{host, port})
    case Offline{}:
      (Sub.echo_sys(cl, "connecting to " ++ host ++ ":" ++ U32.show(port)), "", Dial{host, port})

def connect_apply(+cl: Cl.Client, net: NetState, c: Sub.Conn) -> Cl.Client & String & NetCmd:
  match c:
    case Sub.ConnBad{}:
      (Sub.echo_err(cl, "usage: /connect host [port]"), "", Cont{Nil{}})
    case Sub.ConnOk{+host, port}:
      connect_apply.st(cl, host, port, net)

def submit_pair.enter(+cl: Cl.Client, +net: NetState, +draft: String, conn: Bool) -> Cl.Client & String & NetCmd:
  match conn:
    case True{}:
      connect_apply(cl, net, Sub.connect_from_input(draft))
    case False{}:
      submit_send(cl, net, draft, can_send(net))

def submit_pair(+cl: Cl.Client, net: NetState, +draft: String, enter: Bool) -> Cl.Client & String & NetCmd:
  match enter:
    case False{}:
      (cl, draft, Cont{Nil{}})
    case True{}:
      submit_pair.enter(cl, net, draft, Sub.submit_is_connect(draft))

def apply_keys(+cl: Cl.Client, net: NetState, +draft: String, enter: Bool) -> Cl.Client & String & NetCmd:
  submit_pair(cl, net, draft, enter)

def cmd_connect.got(triple: Cl.Client & String & NetCmd) -> NetCmd:
  match triple:
    case (_, _, c):
      c

def cmd_connect(+net: NetState, +input: String) -> NetCmd:
  cmd_connect.got(connect_apply(Cl.init("me", "s"), net, Sub.connect_from_input(input)))

def cmd_connect_ok() -> Bool:
  String.eq(show_netcmd(cmd_connect(Demo{}, "/connect irc.example.net 6668")), "dial:irc.example.net:6668")
    && String.eq(show_netcmd(cmd_connect(Online{}, "/connect irc.example.net")), "cont")
    && String.eq(show_netcmd(cmd_connect(Connecting{}, "/connect irc.example.net")), "cont")
    && String.eq(show_netcmd(cmd_connect(Demo{}, "/connect")), "cont")

type Hist is Data:
  Hist{lines: List<&2, String>, pos: Nat}

def hist0() -> Hist:
  Hist{Nil{}, 0n}

def HIST_CAP() -> Nat:
  64n

def take_last_str.go(+xs: List<&2, String>, n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      acc
    case Con{+h, t}:
      match n:
        case 0n:
          acc
        case 1n+p:
          take_last_str.go(t, p, h <> acc)

def take_last_str(+xs: List<&2, String>, n: Nat) -> List<&2, String>:
  take_last_str.go(List.reverse(&2, String, xs), n, Nil{})

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

def str_get.on(got: Maybe<&2, String>) -> String:
  match got:
    case None{}:
      ""
    case Some{+s}:
      s

def str_get(+xs: List<&2, String>, +i: Nat) -> String:
  str_get.on(List.get(&2, String, xs, i))

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

def hist_move.on(h: Hist, +draft: String, prev: Bool, next: Bool) -> Hist & String:
  match prev:
    case True{}:
      hist_prev(h)
    case False{}:
      match next:
        case True{}:
          hist_next(h)
        case False{}:
          (h, draft)

def hist_move(+h: Hist, +draft: String, +cmd: U32) -> Hist & String:
  hist_move.on(h, draft, U32.is_eq(cmd, 1), U32.is_eq(cmd, 2))

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
    rows: U32,
    seed: U32
  }

def ROWS0() -> U32:
  24

def session0(+nick: String, +host: String, +chan: String) -> Session:
  Session{Cl.init(nick, host), False{}, Nil{}, "", False{}, chan, Connecting{}, hist0(), ROWS0(), 0}

def session_demo(+cl: Cl.Client, +chan: String) -> Session:
  Session{cl, False{}, Nil{}, "", True{}, chan, Demo{}, hist0(), ROWS0(), 0}

def session_online(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, rows, seed}:
      Session{cl, drop, rem, draft, joined, chan, Online{}, hist, rows, seed}

def session_fail.got(+msg: String, +st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, rows, seed}:
      Session{Sub.echo_err_server(cl, msg), drop, rem, draft, joined, chan, Offline{}, hist, rows, seed}

def session_fail(+st: Session, +msg: String) -> Session:
  session_fail.got(msg, st)

def session_set_now(+st: Session, +ts: String) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, rows, seed}:
      Session{Cl.set_now(cl, ts), drop, rem, draft, joined, chan, net, hist, rows, seed}

def session_set_rows(+st: Session, +rows: U32) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, _, seed}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, rows, seed}

def session_net(+st: Session) -> NetState:
  match st:
    case Session{_, _, _, _, _, _, net, _, _, _}:
      net

def session_nick(+st: Session) -> String:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _}:
      Cl.nick_of(cl)

def session_after.dial(+cl: Cl.Client, drop: Bool, rem: List<&2, U32>, +draft: String, +chan: String, +hist: Hist, +rows: U32, +seed: U32, +host: String) -> Session:
  Session{Cl.set_server(cl, host), drop, rem, draft, False{}, chan, Connecting{}, hist, rows, seed}

def session_after(+cl: Cl.Client, drop: Bool, rem: List<&2, U32>, +draft: String, joined: Bool, +chan: String, net: NetState, +hist: Hist, +rows: U32, +seed: U32, cmd: NetCmd) -> Session:
  match cmd:
    case Dial{+host, _}:
      session_after.dial(cl, drop, rem, draft, chan, hist, rows, seed, host)
    case Handoff{_}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, rows, seed}
    case Cont{_}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, rows, seed}

def apply_click.on(+cl: Cl.Client, +click: U32, z: Bool) -> Cl.Client:
  match z:
    case True{}:
      cl
    case False{}:
      Cl.set_active_clamp(cl, U32.to_nat(U32.sub(click, 1)))

def apply_click(+cl: Cl.Client, +click: U32) -> Cl.Client:
  apply_click.on(cl, click, U32.is_eq(click, 0))

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

def seed_bit(z: Bool) -> U32:
  match z:
    case True{}:
      0
    case False{}:
      1

def seed_of(+hcmd: U32) -> U32:
  seed_bit(U32.is_zero(hcmd))

def session_seed(+st: Session) -> U32:
  match st:
    case Session{_, _, _, _, _, _, _, _, _, seed}:
      seed

def session_draft(+st: Session) -> String:
  match st:
    case Session{_, _, _, draft, _, _, _, _, _, _}:
      draft

def finish_hist(
  drop: Bool,
  rem: List<&2, U32>,
  joined: Bool,
  +chan: String,
  net: NetState,
  +cl3: Cl.Client,
  +cmd: NetCmd,
  halt: Bool,
  +rows: U32,
  +seed: U32,
  pair: Hist & String
) -> Session & NetCmd & Bool:
  match pair:
    case (h2, draft3):
      (session_after(cl3, drop, rem, draft3, joined, chan, net, h2, rows, seed, cmd), cmd, halt)

def finish_keys(
  drop: Bool,
  rem: List<&2, U32>,
  joined: Bool,
  +chan: String,
  net: NetState,
  +enter: Bool,
  +tab: U32,
  +click: U32,
  +up: U32,
  +dn: U32,
  +hcmd: U32,
  +hist: Hist,
  +line: String,
  +rows: U32,
  triple: Cl.Client & String & NetCmd
) -> Session & NetCmd & Bool:
  match triple:
    case (cl2, draft2, cmd):
      +cl3 = snap_if(enter, Cl.apply_active_scroll(apply_click(Cl.cycle_tab(cl2, tab), click), U32.to_nat(up), U32.to_nat(dn)))
      +h2 = hist_after_enter(hist, line, enter)
      finish_hist(drop, rem, joined, chan, net, cl3, cmd, halt_of(enter, line), rows, seed_of(hcmd), hist_move(h2, draft2, hcmd))

def step_keys(+st: Session, +typed: String, +enter: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hcmd: U32) -> Session & NetCmd & Bool:
  match st:
    case Session{+cl, drop, +rem, _, joined, +chan, net, +hist, rows, _}:
      +line = typed
      finish_keys(drop, rem, joined, chan, net, enter, tab, click, up, dn, hcmd, hist, line, rows, apply_keys(cl, net, line, enter))

def step_enter(+st: Session, +line: String) -> Session & NetCmd & Bool:
  step_keys(st, line, True{}, 0, 0, 0, 0, 0)

def step_chunk_got(
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +rows: U32,
  +seed: U32,
  got: Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool
) -> Session & List<&2, String>:
  match got:
    case (cl2, rem2, drop2, outs, joined2):
      (Session{cl2, drop2, rem2, draft, joined2, chan, net, hist, rows, seed}, outs)

def step_on_chunk(+st: Session, chunk: List<&2, U32>) -> Session & List<&2, String>:
  match st:
    case Session{+cl, drop, rem, +draft, joined, +chan, net, +hist, rows, seed}:
      step_chunk_got(draft, chan, net, hist, rows, seed, step_chunk(cl, drop, rem, chunk, joined, chan))


