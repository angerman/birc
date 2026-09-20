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

type Session is Data:
  Session{
    cl: Cl.Client,
    drop: Bool,
    rem: String,
    draft: String,
    joined: Bool,
    chan: String
  }

def session0(+nick: String, +host: String, +chan: String) -> Session:
  Session{Cl.init(nick, host), False{}, "", "", False{}, chan}

def step_keys_got(
  drop: Bool,
  +rem: String,
  joined: Bool,
  +chan: String,
  +tab: U32,
  triple: Cl.Client & String & List<&2, String>
) -> Session & List<&2, String>:
  match triple:
    case (cl2, draft2, outs):
      (Session{Cl.cycle_tab(cl2, tab), drop, rem, draft2, joined, chan}, outs)

def step_keys(+st: Session, +typed: String, enter: Bool, bs: Bool, +tab: U32) -> Session & List<&2, String>:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan}:
      step_keys_got(drop, rem, joined, chan, tab, apply_keys(cl, draft, typed, enter, bs))

def step_chunk_got(
  +draft: String,
  +chan: String,
  got: Cl.Client & String & Bool & List<&2, String> & Bool
) -> Session & List<&2, String>:
  match got:
    case (cl2, rem2, drop2, outs, joined2):
      (Session{cl2, drop2, rem2, draft, joined2, chan}, outs)

def step_on_chunk(+st: Session, +chunk: String) -> Session & List<&2, String>:
  match st:
    case Session{+cl, drop, +rem, +draft, joined, +chan}:
      step_chunk_got(draft, chan, step_chunk(cl, drop, rem, chunk, joined, chan))

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
