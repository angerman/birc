# Pure IRC session: fold, JOIN-after-001, keys, backoff.
# Fuel helpers live in natutil.bend. No IO. net.bend owns Socket / Chan / TimUI.
import Base
import ./irc.bend as Irc
import ./client.bend as Cl
import ./frame.bend as Fr
import ./submit.bend as Sub
import ./natutil.bend as NatU

def register_lines(+nick: String) -> List<&2, String>:
  Irc.format_nick(nick) <> Irc.format_user(nick) <> Nil{}

type FoldAcc is Data:
  FoldAcc{cl: Cl.Client, pongs: List<&2, String>}

def fold_step.ping(+cl: Cl.Client, pongs: List<&2, String>, +h: String, ping: Bool) -> FoldAcc:
  match ping:
    case True{}:
      FoldAcc{cl, Irc.pong_for(h) <> pongs}
    case False{}:
      FoldAcc{Cl.feed(cl, h), pongs}

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
  NatU.live_fuel(frames)

def ticks_of(+frames: U32) -> Nat:
  NatU.ticks_of(frames)

def body_h(+rows: U32) -> Nat:
  NatU.body_h(rows)

def push_pure_join2(
  +cl2: Cl.Client,
  +rem2: String,
  drop2: Bool,
  pair: List<&2, String> & Bool
) -> Cl.Client & String & Bool & List<&2, String> & Bool:
  match pair:
    case (outs, joined2):
      (cl2, rem2, drop2, outs, joined2)

def push_pure_join(
  cl_pongs: Cl.Client & List<&2, String>,
  +rem2: String,
  drop2: Bool,
  +joined: Bool,
  +chan: String,
  +xs: List<&2, String>
) -> Cl.Client & String & Bool & List<&2, String> & Bool:
  match cl_pongs:
    case (cl2, pongs):
      push_pure_join2(cl2, rem2, drop2, join_outs(joined, chan, xs, pongs))

def push_pure_pair(
  +cl: Cl.Client,
  got: List<&2, String> & String & Bool,
  +joined: Bool,
  +chan: String
) -> Cl.Client & String & Bool & List<&2, String> & Bool:
  match got:
    case (+lines, rem2, drop2):
      push_pure_join(fold_lines(cl, lines), rem2, drop2, joined, chan, lines)

def push_pure(
  +cl: Cl.Client,
  drop: Bool,
  +rem: String,
  +chunk: String,
  +joined: Bool,
  +chan: String
) -> Cl.Client & String & Bool & List<&2, String> & Bool:
  push_pure_pair(cl, Fr.push_text_ex(drop, rem, chunk), joined, chan)

def step_chunk(
  +cl: Cl.Client,
  drop: Bool,
  +rem: String,
  +chunk: String,
  +joined: Bool,
  +chan: String
) -> Cl.Client & String & Bool & List<&2, String> & Bool:
  push_pure(cl, drop, rem, chunk, joined, chan)

type NetEvt is Data:
  Chunk{text: String}
  Eof{}
  Tick{}

type NetCmd is Data:
  Cont{outs: List<&2, String>}
  Stop{}
  Dial{host: String, port: U32}

def draft_bs.len(+s: String, n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      String.take(s, p)

def draft_bs(+s: String, bs: Bool) -> String:
  match bs:
    case False{}:
      s
    case True{}:
      draft_bs.len(s, String.length(s))

def draft_typed(+s: String, +text: String) -> String:
  s ++ text

def submit_enter(pair: Cl.Client & List<&2, String>) -> Cl.Client & String & List<&2, String>:
  match pair:
    case (cl2, outs):
      (cl2, "", outs)

def submit_pair(+cl: Cl.Client, +draft: String, enter: Bool) -> Cl.Client & String & List<&2, String>:
  match enter:
    case False{}:
      (cl, draft, Nil{})
    case True{}:
      submit_enter(Sub.submit(cl, draft))

def apply_keys(+cl: Cl.Client, +draft: String, +typed: String, enter: Bool, bs: Bool) -> Cl.Client & String & List<&2, String>:
  submit_pair(cl, draft_typed(draft_bs(draft, bs), typed), enter)

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
    rem: String,
    draft: String,
    joined: Bool,
    chan: String,
    net: NetState,
    hist: Hist
  }

def session0(+nick: String, +host: String, +chan: String) -> Session:
  Session{Cl.init(nick, host), False{}, "", "", False{}, chan, Connecting{}, hist0()}

def session_online(+st: Session) -> Session:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, _, +hist}:
      Session{cl, drop, rem, draft, joined, chan, Online{}, hist}

def apply_click.on(+cl: Cl.Client, +click: U32, z: Bool) -> Cl.Client:
  match z:
    case True{}:
      cl
    case False{}:
      Cl.set_active_clamp(cl, NatU.u32_to_nat(U32.sub(click, 1)))

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

def finish_hist(
  drop: Bool,
  +rem: String,
  joined: Bool,
  +chan: String,
  net: NetState,
  +cl3: Cl.Client,
  +outs: List<&2, String>,
  halt: Bool,
  pair: Hist & String
) -> Session & List<&2, String> & Bool:
  match pair:
    case (h2, draft3):
      (Session{cl3, drop, rem, draft3, joined, chan, net, h2}, outs, halt)

def finish_keys(
  drop: Bool,
  +rem: String,
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
  triple: Cl.Client & String & List<&2, String>
) -> Session & List<&2, String> & Bool:
  match triple:
    case (cl2, draft2, outs):
      +cl3 = snap_if(enter, Cl.apply_active_scroll(apply_click(Cl.cycle_tab(cl2, tab), click), NatU.u32_to_nat(up), NatU.u32_to_nat(dn)))
      +h2 = hist_after_enter(hist, line, enter)
      finish_hist(drop, rem, joined, chan, net, cl3, outs, halt_of(enter, line), hist_move(h2, draft2, hcmd))

def step_keys(+st: Session, +typed: String, +enter: Bool, bs: Bool, +tab: U32, +click: U32, +up: U32, +dn: U32, +hcmd: U32) -> Session & List<&2, String> & Bool:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist}:
      +line = draft_typed(draft_bs(draft, bs), typed)
      finish_keys(drop, rem, joined, chan, net, enter, tab, click, up, dn, hcmd, hist, line, apply_keys(cl, line, "", enter, False{}))

def step_chunk_got(
  +draft: String,
  +chan: String,
  net: NetState,
  +hist: Hist,
  got: Cl.Client & String & Bool & List<&2, String> & Bool
) -> Session & List<&2, String>:
  match got:
    case (cl2, rem2, drop2, outs, joined2):
      (Session{cl2, drop2, rem2, draft, joined2, chan, net, hist}, outs)

def step_on_chunk(+st: Session, +chunk: String) -> Session & List<&2, String>:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan, net, +hist}:
      step_chunk_got(draft, chan, net, hist, step_chunk(cl, drop, rem, chunk, joined, chan))

def BACKOFF_START() -> U32:
  250

def BACKOFF_CAP() -> U32:
  8000

def next_backoff.cap(+doubled: U32, over: Bool) -> U32:
  match over:
    case True{}:
      BACKOFF_CAP()
    case False{}:
      doubled

def next_backoff(+ms: U32) -> U32:
  +d = U32.add(ms, ms)
  next_backoff.cap(d, U32.is_gt(d, BACKOFF_CAP()))
