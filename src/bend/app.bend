# birc main (M6). Bend owns the frame loop with Nat fuel; TimUI FFI is thin.
# D4: `--frames` supplies fuel; Escape / `/quit` halt.
import Base
import ./buffer.bend as Cl
import ./client.bend as Feed
import ./net.bend as Net
import ./wsnet.bend as WsNet
import ./args.bend as Args
import ./clock.bend as Clock
import ./replay.bend as Replay
import ./auth_bridge.bend as AuthBridge
import ./endpoint.bend as Ep

def run_demo(+frames: U32, +cl: Cl.Client, +chan: String, port: U32, force_tls: Bool) -> IO(Unit):
  Net.run_offline(frames, cl, chan, port, force_tls)

def load_replay(+path: String, +nick: String, +server: String) -> IO(Cl.Client):
  Replay.load(path, nick, server)

def resolve_sasl.env(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{+v}: v
    case Fail{_}: ""

def resolve_sasl.empty(empty: Bool, +value: String, +name: String) -> IO(String):
  match empty:
    case True{}:
      do IO<String>:
        r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
        return resolve_sasl.env(r)
    case False{}:
      IO.pure(String, value)

def resolve_sasl(+value: String, +name: String) -> IO(String):
  resolve_sasl.empty(String.is_empty(value), value, name)

def resolve_sasl_user(+su: String) -> IO(String):
  resolve_sasl(su, "BIRC_SASL_USER")

def resolve_sasl_pass(+sp: String) -> IO(String):
  resolve_sasl(sp, "BIRC_SASL_PASS")

def main_live(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String, +auth: Args.AuthOptions, force_tls: Bool) -> IO(Unit):
  Net.run_live(frames, host, port, nick, chan, sasl_user, sasl_pass, auth, force_tls)


def demo_client(+nick: String) -> IO(Cl.Client):
  do IO<Cl.Client>:
    ts : String <- Clock.hhmmss()
    return Feed.feed_all(Cl.set_now(Cl.init(nick, "irc.birc.dev"), ts), Feed.demo_lines_for(nick))

def main_offline(+frames: U32, +chan: String, +cl: Cl.Client, port: U32, force_tls: Bool) -> IO(Unit):
  run_demo(frames, cl, chan, port, force_tls)

def main_replay(+frames: U32, +nick: String, +chan: String, +path: String, port: U32, force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    cl : Cl.Client <- load_replay(path, nick, "replay")
    main_offline(frames, chan, cl, port, force_tls)

def main_dispatch.servers(
  +frames: U32,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +sasl_user: String,
  +sasl_pass: String,
  +auth: Args.AuthOptions,
  force_tls: Bool,
  +servers: List<&2, Ep.Endpoint>,
  single: Bool
) -> IO(Unit):
  match single:
    case True{}:
      main_live(frames, host, port, nick, chan, sasl_user, sasl_pass, auth, force_tls)
    case False{}:
      WsNet.run_ws(frames, host, port, servers, nick, chan, sasl_user, sasl_pass, auth, force_tls)

def main_dispatch.demo(
  +frames: U32,
  demo: Bool,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +sasl_user: String,
  +sasl_pass: String,
  +auth: Args.AuthOptions,
  force_tls: Bool,
  +servers: List<&2, Ep.Endpoint>
) -> IO(Unit):
  match demo:
    case True{}:
      do IO<Unit>:
        cl : Cl.Client <- demo_client(nick)
        main_offline(frames, chan, cl, port, force_tls)
    case False{}:
      main_dispatch.servers(frames, host, port, nick, chan, sasl_user, sasl_pass, auth, force_tls, servers, List.is_empty(&2, Ep.Endpoint, servers))

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
  +sasl_pass: String,
  +auth: Args.AuthOptions,
  force_tls: Bool,
  +servers: List<&2, Ep.Endpoint>
) -> IO(Unit):
  match has_replay:
    case True{}:
      main_replay(frames, nick, chan, replay, port, force_tls)
    case False{}:
      main_dispatch.demo(frames, demo, host, port, nick, chan, sasl_user, sasl_pass, auth, force_tls, servers)

def main_dispatch(
  +frames: U32,
  demo: Bool,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +replay: String,
  +sasl_user: String,
  +sasl_pass: String,
  +auth: Args.AuthOptions,
  force_tls: Bool,
  +servers: List<&2, Ep.Endpoint>
) -> IO(Unit):
  main_dispatch.on(frames, demo, host, port, nick, chan, replay, Bool.not(String.is_empty(replay)), sasl_user, sasl_pass, auth, force_tls, servers)

def main_cfg.dispatch(
  +frames: U32,
  demo: Bool,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +replay: String,
  explicit: Bool,
  +user: String,
  +pass: String,
  +auth: Args.AuthOptions,
  force_tls: Bool,
  +servers: List<&2, Ep.Endpoint>
) -> IO(Unit):
  +n = Args.resolve_nick(nick, explicit, user)
  main_dispatch(frames, demo, host, port, n, chan, replay, user, pass, auth, force_tls, servers)

def resolve_private_pass.present(present: Bool, +secret: String, +legacy: String) -> IO(String):
  match present:
    case True{}: IO.pure(String, secret)
    case False{}: resolve_sasl_pass(legacy)

def resolve_private_pass(pair: U32 & String, +legacy: String) -> IO(String):
  match pair:
    case (0, +secret):
      resolve_private_pass.present(Bool.not(String.is_empty(secret)), secret, legacy)
    case (_, _): IO.die(String, 2, "birc: invalid private authentication pipe")

def main_cfg(+cfg: Args.Cfg) -> IO(Unit):
  match cfg:
    case Args.Cfg{demo, frames, +host, port, +nick, +chan, +replay, +su, +sp, explicit, +auth, force_tls, _, +servers}:
      do IO<Unit>:
        bridge : U32 & String <- AuthBridge.setup()
        user : String <- resolve_sasl_user(su)
        pass : String <- resolve_private_pass(bridge, sp)
        main_cfg.dispatch(frames, demo, host, port, nick, chan, replay, explicit, user, pass, auth, force_tls, servers)

def main_run(got: Args.Parsed) -> IO(Unit):
  match got:
    case Args.Bad{+msg}:
      IO.die(Unit, 2, msg)
    case Args.Good{cfg}:
      main_cfg(cfg)

def main() -> IO(Unit):
  do IO<Unit>:
    raw : List<&1, String> <- IO.args()
    main_run(Args.parse_raw(raw))
