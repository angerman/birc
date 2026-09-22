# CLI flags for birc (IO.args). Pure. app.bend runs parse; tests assert it.
import Base

type Cfg is Data:
  Cfg{demo: Bool, frames: U32, host: String, port: U32, nick: String, chan: String, replay: String}

type Parsed is Data:
  Good{cfg: Cfg}
  Bad{msg: String}

type Num is Data:
  Num{ok: Bool, n: U32}

def cfg0() -> Cfg:
  Cfg{True{}, 0, "", 6667, "birc", "#birc", ""}

def parse_u32.on(m: Maybe<&2, U32>) -> Num:
  match m:
    case None{}:
      Num{False{}, 0}
    case Some{n}:
      Num{True{}, n}

def parse_u32(+s: String) -> Num:
  parse_u32.on(U32.read(s))

def set_frames(+cfg: Cfg, n: U32) -> Cfg:
  match cfg:
    case Cfg{demo, _, +host, port, +nick, +chan, +replay}:
      Cfg{demo, n, host, port, nick, chan, replay}

def set_host(+cfg: Cfg, +host: String) -> Cfg:
  match cfg:
    case Cfg{_, frames, _, port, +nick, +chan, +replay}:
      Cfg{False{}, frames, host, port, nick, chan, replay}

def set_port(+cfg: Cfg, n: U32) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, _, +nick, +chan, +replay}:
      Cfg{demo, frames, host, n, nick, chan, replay}

def set_nick(+cfg: Cfg, +nick: String) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, port, _, +chan, +replay}:
      Cfg{demo, frames, host, port, nick, chan, replay}

def set_chan(+cfg: Cfg, +chan: String) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, port, +nick, _, +replay}:
      Cfg{demo, frames, host, port, nick, chan, replay}

def set_replay(+cfg: Cfg, +replay: String) -> Cfg:
  match cfg:
    case Cfg{demo, frames, +host, port, +nick, +chan, _}:
      Cfg{demo, frames, host, port, nick, chan, replay}

def set_demo(+cfg: Cfg) -> Cfg:
  match cfg:
    case Cfg{_, frames, +host, port, +nick, +chan, +replay}:
      Cfg{True{}, frames, host, port, nick, chan, replay}

type Step is Data:
  Go{xs: List<&2, String>, cfg: Cfg}
  Stop{got: Parsed}

def args_need(+xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def FRAMES_MAX() -> U32:
  65535

def args_num_frames(+t: List<&2, String>, +cfg: Cfg, n: U32, over: Bool) -> Step:
  match over:
    case True{}:
      Stop{Bad{"birc: --frames too large"}}
    case False{}:
      Go{ t, set_frames(cfg, n)}

def PORT_MAX() -> U32:
  65535

def args_num_port(+t: List<&2, String>, +cfg: Cfg, n: U32, bad: Bool) -> Step:
  match bad:
    case True{}:
      Stop{Bad{"birc: --port out of range"}}
    case False{}:
      Go{ t, set_port(cfg, n)}

def args_num_which(+t: List<&2, String>, +cfg: Cfg, +n: U32, frames: Bool) -> Step:
  match frames:
    case True{}:
      args_num_frames(t, cfg, n, U32.is_gt(n, FRAMES_MAX()))
    case False{}:
      args_num_port(t, cfg, n, U32.is_eq(n, 0) || U32.is_gt(n, PORT_MAX()))

def args_num_ok(+t: List<&2, String>, +cfg: Cfg, n: U32, ok: Bool, frames: Bool) -> Step:
  match ok:
    case False{}:
      Stop{Bad{"birc: expected a number"}}
    case True{}:
      args_num_which(t, cfg, n, frames)

def args_num_on(+t: List<&2, String>, +cfg: Cfg, got: Num, frames: Bool) -> Step:
  match got:
    case Num{ok, n}:
      args_num_ok(t, cfg, n, ok, frames)

def args_num(+t: List<&2, String>, +cfg: Cfg, +tok: String, frames: Bool) -> Step:
  args_num_on(t, cfg, parse_u32(tok), frames)

def args_take_con(+xs: List<&2, String>, +cfg: Cfg, frames: Bool) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      args_num(t, cfg, h, frames)

def args_take_on(+xs: List<&2, String>, +cfg: Cfg, frames: Bool, need: Bool) -> Step:
  match need:
    case True{}:
      Stop{Bad{"birc: missing value"}}
    case False{}:
      args_take_con(xs, cfg, frames)

def args_take(+xs: List<&2, String>, +cfg: Cfg, frames: Bool) -> Step:
  args_take_on(xs, cfg, frames, args_need(xs))

def args_word_set(+t: List<&2, String>, +cfg: Cfg, +h: String, host: Bool) -> Step:
  match host:
    case True{}:
      Go{ t, set_host(cfg, h)}
    case False{}:
      Go{ t, set_nick(cfg, h)}

def args_word_con(+xs: List<&2, String>, +cfg: Cfg, host: Bool) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      args_word_set(t, cfg, h, host)

def args_word_on(+xs: List<&2, String>, +cfg: Cfg, host: Bool, need: Bool) -> Step:
  match need:
    case True{}:
      Stop{Bad{"birc: missing value"}}
    case False{}:
      args_word_con(xs, cfg, host)

def args_word(+xs: List<&2, String>, +cfg: Cfg, host: Bool) -> Step:
  args_word_on(xs, cfg, host, args_need(xs))

def args_chan_con(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      Go{ t, set_chan(cfg, h)}

def args_chan_on(+xs: List<&2, String>, +cfg: Cfg, need: Bool) -> Step:
  match need:
    case True{}:
      Stop{Bad{"birc: missing value"}}
    case False{}:
      args_chan_con(xs, cfg)

def args_chan(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  args_chan_on(xs, cfg, args_need(xs))

def args_replay_con(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      Stop{Bad{"birc: missing value"}}
    case Con{+h, t}:
      Go{ t, set_replay(cfg, h)}

def args_replay_on(+xs: List<&2, String>, +cfg: Cfg, need: Bool) -> Step:
  match need:
    case True{}:
      Stop{Bad{"birc: missing value"}}
    case False{}:
      args_replay_con(xs, cfg)

def args_replay(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  args_replay_on(xs, cfg, args_need(xs))

def USAGE() -> String:
  "usage: birc [--frames N] [--connect HOST] [--port N] [--nick N] [--channel #c] [--replay FILE] [--demo] [--help-irc]"

type Flag is Data:
  FDemo{}
  FFrames{}
  FConnect{}
  FPort{}
  FNick{}
  FChan{}
  FReplay{}
  FHelp{}
  FUnknown{}

type FlagRow is Data:
  FlagRow{name: String, f: Flag}

def flag_rows() -> List<&2, FlagRow>:
  FlagRow{"--demo", FDemo{}} <> FlagRow{"--frames", FFrames{}} <> FlagRow{"--connect", FConnect{}} <> FlagRow{"--port", FPort{}} <> FlagRow{"--nick", FNick{}} <> FlagRow{"--channel", FChan{}} <> FlagRow{"--replay", FReplay{}} <> FlagRow{"--help-irc", FHelp{}} <> Nil{}

def flag_of(xs: List<&2, FlagRow>, +h: String) -> Flag:
  match xs:
    case Nil{}:
      FUnknown{}
    case Con{row, t}:
      match row:
        case FlagRow{+name, +f}:
          Bool.pick(Flag, String.eq(name, h), f, flag_of(t, h))

def args_opt.do(+t: List<&2, String>, +cfg: Cfg, +h: String, f: Flag) -> Step:
  match f:
    case FDemo{}:
      Go{ t, set_demo(cfg)}
    case FFrames{}:
      args_take(t, cfg, True{})
    case FConnect{}:
      args_word(t, cfg, True{})
    case FPort{}:
      args_take(t, cfg, False{})
    case FNick{}:
      args_word(t, cfg, False{})
    case FChan{}:
      args_chan(t, cfg)
    case FReplay{}:
      args_replay(t, cfg)
    case FHelp{}:
      Stop{Bad{USAGE()}}
    case FUnknown{}:
      Stop{Bad{"birc: unknown option " ++ h}}

def args_flag(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      Stop{Good{cfg}}
    case Con{+h, t}:
      args_opt.do(t, cfg, h, flag_of(flag_rows(), h))

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed args_go
def args_go(fuel: Nat, st: Step) -> Parsed:
  match fuel:
    case 0n:
      Bad{"birc: too many arguments"}
    case 1n+p:
      match st:
        case Stop{got}:
          got
        case Go{+xs, +cfg}:
          args_go(p, args_flag(xs, cfg))

def parse(+xs: List<&2, String>) -> Parsed:
  args_go(64n, Go{ xs, cfg0()})

def copy_args(src: List<&1, String>, acc: List<&2, String>) -> List<&2, String>:
  match src:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{+h, t}:
      copy_args(t, h <> acc)

def parse_raw(raw: List<&1, String>) -> Parsed:
  parse(copy_args(raw, Nil{}))

# Fail closed on leftover argv. Tests construct the remainder as List<&2>
# without IO.args (copy_args itself has no cap; parse is 64 flags).
def copy_fin2(rest: List<&2, String>, acc: List<&2, String>) -> Parsed:
  match rest:
    case Nil{}:
      parse(List.reverse(&2, String, acc))
    case Con{_, _}:
      Bad{"birc: too many arguments"}
