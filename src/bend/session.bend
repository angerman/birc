# Pure IRC session: fold, JOIN-after-001, keys. No reconnect/backoff.
# No IO. net.bend owns Socket / Chan / TimUI.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./client.bend as Feed
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
      +cl2 = Feed.feed(cl, h)
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

# Body lines and PageUp/PageDown share this height (passed into Timui.frame).
def body_h_ok() -> Bool:
  Nat.is_eq(body_h(24), 18n) && Nat.is_eq(body_h(16), 10n) && Nat.is_eq(body_h(6), 1n) && Nat.is_eq(body_h(7), 1n)

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
    hist: HistDir
  }

def keys_enter(+line: String) -> Keys:
  Keys{line, True{}, Cl.TabStay{}, None{}, 0n, 0n, HistStay{}}

def keys_of(+typed: String, enter: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32) -> Keys:
  Keys{typed, enter, Cl.tab_dir(tab), click_of(click), U32.to_nat(up), U32.to_nat(dn), hist_dir(hist)}

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
    seed: U32
  }

def SIZE0() -> Size:
  Size{24, 80}

def session0(+nick: String, +host: String, +chan: String) -> Session:
  Session{Cl.init(nick, host), False{}, Nil{}, "", False{}, chan, Connecting{}, hist0(), SIZE0(), 0}

def session_demo(+cl: Cl.Client, +chan: String) -> Session:
  Session{cl, False{}, Nil{}, "", True{}, chan, Demo{}, hist0(), SIZE0(), 0}

def session_online(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist, size, seed}:
      Session{cl, drop, rem, draft, joined, chan, Online{}, hist, size, seed}

def session_fail.got(+msg: String, +st: Session) -> Session:
  match st:
    case Session{+cl, _, _, +draft, joined, +chan, _, +hist, size, seed}:
      Session{Sub.echo_err_server(cl, msg), False{}, Nil{}, draft, joined, chan, Offline{}, hist, size, seed}

def session_fail(+st: Session, +msg: String) -> Session:
  session_fail.got(msg, st)

def session_set_now(+st: Session, +ts: String) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, size, seed}:
      Session{Cl.set_now(cl, ts), drop, rem, draft, joined, chan, net, hist, size, seed}

def session_set_size(+st: Session, +rows: U32, +cols: U32) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist, _, seed}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, Size{rows, cols}, seed}

def session_net(+st: Session) -> NetState:
  match st:
    case Session{_, _, _, _, _, _, net, _, _, _}:
      net

def session_nick(+st: Session) -> String:
  match st:
    case Session{+cl, _, _, _, _, _, _, _, _, _}:
      Cl.nick_of(cl)

def session_after.dial(+cl: Cl.Client, +draft: String, +chan: String, +hist: Hist, +size: Size, +seed: U32, +host: String) -> Session:
  Session{Cl.set_server(cl, host), False{}, Nil{}, draft, False{}, chan, Connecting{}, hist, size, seed}

def session_after(+cl: Cl.Client, drop: Bool, rem: List<&2, U32>, +draft: String, joined: Bool, +chan: String, net: NetState, +hist: Hist, +size: Size, +seed: U32, cmd: NetCmd) -> Session:
  match cmd:
    case Dial{+host, _}:
      session_after.dial(cl, draft, chan, hist, size, seed, host)
    case Handoff{_}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed}
    case Cont{_}:
      Session{cl, drop, rem, draft, joined, chan, net, hist, size, seed}

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

def seed_bit(z: Bool) -> U32:
  match z:
    case True{}:
      0
    case False{}:
      1

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
  +size: Size,
  +seed: U32,
  pair: Hist & String
) -> Session & NetCmd & Bool:
  match pair:
    case (h2, draft3):
      (session_after(cl3, drop, rem, draft3, joined, chan, net, h2, size, seed, cmd), cmd, halt)

def finish_keys(
  drop: Bool,
  rem: List<&2, U32>,
  joined: Bool,
  +chan: String,
  net: NetState,
  keys: Keys,
  +hist: Hist,
  +size: Size,
  triple: Cl.Client & String & NetCmd
) -> Session & NetCmd & Bool:
  match keys:
    case Keys{+typed, +enter, tab, click, +up, +dn, +hdir}:
      match triple:
        case (cl2, draft2, cmd):
          +cl3 = snap_if(enter, Cl.apply_active_scroll(apply_click(Cl.cycle_tab(cl2, tab), click), up, dn))
          +h2 = hist_after_enter(hist, typed, enter)
          finish_hist(drop, rem, joined, chan, net, cl3, cmd, halt_of(enter, typed), size, seed_of(hdir), hist_move(h2, draft2, hdir))

def step_keys(+st: Session, +keys: Keys) -> Session & NetCmd & Bool:
  match st:
    case Session{+cl, drop, +rem, _, joined, +chan, net, +hist, size, _}:
      match keys:
        case Keys{+typed, enter, _, _, _, _, _}:
          finish_keys(drop, rem, joined, chan, net, keys, hist, size, apply_keys(cl, net, typed, enter))

def step_enter(+st: Session, +line: String) -> Session & NetCmd & Bool:
  step_keys(st, keys_enter(line))

def step_chunk_got(
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  +size: Size,
  +seed: U32,
  got: Cl.Client & List<&2, U32> & Bool & List<&2, String> & Bool
) -> Session & List<&2, String>:
  match got:
    case (cl2, rem2, drop2, outs, joined2):
      (Session{cl2, drop2, rem2, draft, joined2, chan, net, hist, size, seed}, outs)

def step_on_chunk(+st: Session, chunk: List<&2, U32>) -> Session & List<&2, String>:
  match st:
    case Session{+cl, drop, rem, +draft, joined, +chan, net, +hist, size, seed}:
      step_chunk_got(draft, chan, net, hist, size, seed, step_chunk(cl, drop, rem, chunk, joined, chan))

def sess_drop(+st: Session) -> Bool:
  match st:
    case Session{_, drop, _, _, _, _, _, _, _, _}:
      drop

def sess_rem_nil.of(xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case _:
      False{}

def sess_rem_nil(+st: Session) -> Bool:
  match st:
    case Session{_, _, rem, _, _, _, _, _, _, _}:
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


