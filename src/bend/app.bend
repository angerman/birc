# birc main (M6). Bend owns the frame loop with Nat fuel; TimUI FFI is thin.
# D4: `--frames` supplies fuel; Escape / `/quit` halt.
import Base
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./net.bend as Net
import ./args.bend as Args
import ./clock.bend as Clock

def run_demo(+frames: U32, +cl: Cl.Client, +chan: String) -> IO(Unit):
  Net.run_offline(frames, cl, chan)

def replay_die(+path: String, +msg: String) -> IO(Cl.Client):
  IO.die(Cl.Client, 1, "birc: cannot read replay " ++ path ++ ": " ++ msg)

def replay_read.got(+path: String, +nick: String, +server: String, f: File, r: Result<&1, &1, U32 & String, String>) -> IO(Cl.Client):
  match r:
    case Fail{e}:
      match e:
        case (_, +msg):
          do IO<Cl.Client>:
            Unit <- File.close(f)
            replay_die(path, msg)
    case Done{+text}:
      do IO<Cl.Client>:
        Unit <- File.close(f)
        ts : String <- Clock.hhmmss()
        return Feed.feed_all(Cl.set_now(Cl.init(nick, server), ts), Cl.replay_lines(text))

def replay_read(+path: String, +nick: String, +server: String, pair: File & Result<&1, &1, U32 & String, String>) -> IO(Cl.Client):
  match pair:
    case (f, r):
      replay_read.got(path, nick, server, f, r)

def replay_open(+path: String, +nick: String, +server: String, r: Result<&1, &1, U32 & String, File>) -> IO(Cl.Client):
  match r:
    case Fail{e}:
      match e:
        case (_, +msg):
          replay_die(path, msg)
    case Done{f}:
      do IO<Cl.Client>:
        pair : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        replay_read(path, nick, server, pair)

def load_replay(+path: String, +nick: String, +server: String) -> IO(Cl.Client):
  do IO<Cl.Client>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    replay_open(path, nick, server, r)

def resolve_sasl_user.env(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+v}: v
    case Fail{_}: ""

def resolve_sasl_user.empty(empty: Bool, +su: String) -> IO(String):
  match empty:
    case True{}:
      do IO<String>:
        r : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_SASL_USER")
        return resolve_sasl_user.env(r)
    case False{}:
      IO.pure(String, su)

def resolve_sasl_user(+su: String) -> IO(String):
  resolve_sasl_user.empty(String.is_empty(su), su)

def resolve_sasl_pass.env(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+v}: v
    case Fail{_}: ""

def resolve_sasl_pass.empty(empty: Bool, +sp: String) -> IO(String):
  match empty:
    case True{}:
      do IO<String>:
        r : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_SASL_PASS")
        return resolve_sasl_pass.env(r)
    case False{}:
      IO.pure(String, sp)

def resolve_sasl_pass(+sp: String) -> IO(String):
  resolve_sasl_pass.empty(String.is_empty(sp), sp)

def main_live(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String) -> IO(Unit):
  Net.run_live(frames, host, port, nick, chan, sasl_user, sasl_pass)


def demo_client(+nick: String) -> IO(Cl.Client):
  do IO<Cl.Client>:
    ts : String <- Clock.hhmmss()
    return Feed.feed_all(Cl.set_now(Cl.init(nick, "irc.birc.dev"), ts), Feed.demo_lines_for(nick))

def main_offline(+frames: U32, +chan: String, +cl: Cl.Client) -> IO(Unit):
  run_demo(frames, cl, chan)

def main_replay(+frames: U32, +nick: String, +chan: String, +path: String) -> IO(Unit):
  do IO<Unit>:
    cl : Cl.Client <- load_replay(path, nick, "replay")
    main_offline(frames, chan, cl)

def main_dispatch.demo(
  +frames: U32,
  demo: Bool,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +sasl_user: String,
  +sasl_pass: String
) -> IO(Unit):
  match demo:
    case True{}:
      do IO<Unit>:
        cl : Cl.Client <- demo_client(nick)
        main_offline(frames, chan, cl)
    case False{}:
      main_live(frames, host, port, nick, chan, sasl_user, sasl_pass)

def main_dispatch.on(
  +frames: U32,
  demo: Bool,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +replay: String,
  has_replay: Bool,
  +sasl_user: String,
  +sasl_pass: String
) -> IO(Unit):
  match has_replay:
    case True{}:
      main_replay(frames, nick, chan, replay)
    case False{}:
      main_dispatch.demo(frames, demo, host, port, nick, chan, sasl_user, sasl_pass)

def main_dispatch(
  +frames: U32,
  demo: Bool,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +replay: String,
  +sasl_user: String,
  +sasl_pass: String
) -> IO(Unit):
  main_dispatch.on(frames, demo, host, port, nick, chan, replay, Bool.not(String.is_empty(replay)), sasl_user, sasl_pass)

def align_sasl_nick.pick(should_align: Bool, +user: String, +nick: String) -> String:
  match should_align:
    case True{}: user
    case False{}: nick

def align_sasl_nick(+user: String, +nick: String) -> String:
  +is_def = String.eq(nick, "birc") || String.eq(nick, "me")
  +has_user = Bool.not(String.is_empty(user))
  align_sasl_nick.pick(is_def && has_user, user, nick)

def main_cfg.dispatch(
  +frames: U32,
  demo: Bool,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +replay: String,
  +user: String,
  +pass: String
) -> IO(Unit):
  +n = align_sasl_nick(user, nick)
  main_dispatch(frames, demo, host, port, n, chan, replay, user, pass)

def main_cfg(+cfg: Args.Cfg) -> IO(Unit):
  match cfg:
    case Args.Cfg{demo, frames, +host, port, +nick, +chan, +replay, +su, +sp}:
      do IO<Unit>:
        user : String <- resolve_sasl_user(su)
        pass : String <- resolve_sasl_pass(sp)
        main_cfg.dispatch(frames, demo, host, port, nick, chan, replay, user, pass)

def main_run(got: Args.Parsed) -> IO(Unit):
  match got:
    case Args.Bad{+msg}:
      do IO<Unit>:
        Unit <- IO.print_err(msg)
        IO.die(Unit, 2, msg)
    case Args.Good{cfg}:
      main_cfg(cfg)

def main() -> IO(Unit):
  do IO<Unit>:
    raw : List<&1, String> <- IO.args()
    main_run(Args.parse_raw(raw))
