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

type NumPh is Data:
  NStr{}
  NChr{}
  NGe{}
  NLe{}

def parse_u32.done(seen: Bool, acc: U32) -> Num:
  match seen:
    case False{}:
      Num{False{}, 0}
    case True{}:
      Num{True{}, acc}

def parse_u32.go(fuel: Nat, phase: NumPh, +s: String, +acc: U32, seen: Bool, +h: Char, +code: U32, ge: Bool, le: Bool) -> Num:
  match fuel:
    case 0n:
      Num{False{}, 0}
    case 1n+p:
      match phase:
        case NStr{}:
          match s:
            case SNil{}:
              parse_u32.done(seen, acc)
            case SCon{+hd, t}:
              parse_u32.go(p, NChr{}, t, acc, seen, hd, 0, False{}, False{})
        case NChr{}:
          match h:
            case Chr{c}:
              parse_u32.go(p, NGe{}, s, acc, seen, h, c, U32.is_ge(c, 48), False{})
        case NGe{}:
          match ge:
            case False{}:
              Num{False{}, 0}
            case True{}:
              parse_u32.go(p, NLe{}, s, acc, seen, h, code, U32.is_gt(acc, 429496729) || (U32.is_eq(acc, 429496729) && U32.is_gt(U32.sub(code, 48), 5)), U32.is_le(code, 57))
        case NLe{}:
          match ge:
            case True{}:
              Num{False{}, 0}
            case False{}:
              match le:
                case False{}:
                  Num{False{}, 0}
                case True{}:
                  parse_u32.go(p, NStr{}, s, U32.add(U32.mul(acc, 10), U32.sub(code, 48)), True{}, h, 0, False{}, False{})

def parse_u32(+s: String) -> Num:
  parse_u32.go(Nat.add(1n, Nat.mul(4n, String.length(s))), NStr{}, s, 0, False{}, Chr{0}, 0, False{}, False{})

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

def args_num_which(+t: List<&2, String>, +cfg: Cfg, +n: U32, frames: Bool) -> Step:
  match frames:
    case True{}:
      args_num_frames(t, cfg, n, U32.is_gt(n, FRAMES_MAX()))
    case False{}:
      Go{ t, set_port(cfg, n)}

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

def args_opt.help(+h: String, hit: Bool) -> Step:
  match hit:
    case True{}:
      Stop{Bad{USAGE()}}
    case False{}:
      Stop{Bad{"birc: unknown option " ++ h}}

def args_opt.replay(+t: List<&2, String>, +cfg: Cfg, +h: String, hit: Bool) -> Step:
  match hit:
    case True{}:
      args_replay(t, cfg)
    case False{}:
      args_opt.help(h, String.eq(h, "--help-irc"))

def args_opt.chan(+t: List<&2, String>, +cfg: Cfg, +h: String, hit: Bool) -> Step:
  match hit:
    case True{}:
      args_chan(t, cfg)
    case False{}:
      args_opt.replay(t, cfg, h, String.eq(h, "--replay"))

def args_opt.nick(+t: List<&2, String>, +cfg: Cfg, +h: String, hit: Bool) -> Step:
  match hit:
    case True{}:
      args_word(t, cfg, False{})
    case False{}:
      args_opt.chan(t, cfg, h, String.eq(h, "--channel"))

def args_opt.port(+t: List<&2, String>, +cfg: Cfg, +h: String, hit: Bool) -> Step:
  match hit:
    case True{}:
      args_take(t, cfg, False{})
    case False{}:
      args_opt.nick(t, cfg, h, String.eq(h, "--nick"))

def args_opt.connect(+t: List<&2, String>, +cfg: Cfg, +h: String, hit: Bool) -> Step:
  match hit:
    case True{}:
      args_word(t, cfg, True{})
    case False{}:
      args_opt.port(t, cfg, h, String.eq(h, "--port"))

def args_opt.frames(+t: List<&2, String>, +cfg: Cfg, +h: String, hit: Bool) -> Step:
  match hit:
    case True{}:
      args_take(t, cfg, True{})
    case False{}:
      args_opt.connect(t, cfg, h, String.eq(h, "--connect"))

def args_opt.demo(+t: List<&2, String>, +cfg: Cfg, +h: String, hit: Bool) -> Step:
  match hit:
    case True{}:
      Go{ t, set_demo(cfg)}
    case False{}:
      args_opt.frames(t, cfg, h, String.eq(h, "--frames"))

def args_flag(+xs: List<&2, String>, +cfg: Cfg) -> Step:
  match xs:
    case Nil{}:
      Stop{Good{cfg}}
    case Con{+h, t}:
      args_opt.demo(t, cfg, h, String.eq(h, "--demo"))

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

def copy_args(fuel: Nat, src: List<&1, String>, +acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+p:
      match src:
        case Nil{}:
          List.reverse(&2, String, acc)
        case Con{+h, t}:
          copy_args(p, t, h <> acc)

def parse_raw(raw: List<&1, String>) -> Parsed:
  parse(copy_args(64n, raw, Nil{}))

def show_cfg(+cfg: Cfg) -> String:
  match cfg:
    case Cfg{demo, frames, +host, port, +nick, +chan, +replay}:
      "demo=" ++ Bool.show(demo)
        ++ " frames=" ++ U32.show(frames)
        ++ " host=" ++ host
        ++ " port=" ++ U32.show(port)
        ++ " nick=" ++ nick
        ++ " chan=" ++ chan
        ++ " replay=" ++ replay

def show_parsed(p: Parsed) -> String:
  match p:
    case Good{cfg}:
      "good:" ++ show_cfg(cfg)
    case Bad{+msg}:
      "bad:" ++ msg

def show_num(got: Num) -> String:
  match got:
    case Num{ok, n}:
      Bool.show(ok) ++ ":" ++ U32.show(n)
