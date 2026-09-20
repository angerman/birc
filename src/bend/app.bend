# birc main (M6). Bend owns the frame loop with Nat fuel; TimUI FFI is thin.
# LAW note (D4 / ui_loop_trust): App.budget / --frames supplies fuel; Escape quits.
import Base
import ./client.bend as Cl
import ./view.bend as V
import ./timui.bend as T
import ./net.bend as Net
import ./dns.bend as Dns
import ./args.bend as Args
import ./natutil.bend as NatU
import ./paint.bend as Paint

def DEMO_FRAMES() -> Nat:
  3n

def fuel_of.on(+frames: U32, zero: Bool) -> Nat:
  match zero:
    case True{}:
      DEMO_FRAMES()
    case False{}:
      NatU.u32_to_nat(frames)

def fuel_of(+frames: U32) -> Nat:
  fuel_of.on(frames, U32.is_eq(frames, 0))

# Fuel first; shrinks every self-call (Bend termination).
def ui_loop(fuel: Nat, quit: Bool, ui: T.Ui, +cl: Cl.Client) -> IO(Unit):
  match fuel:
    case 0n:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        IO.print("birc=ok")
    case 1n+p:
      match quit:
        case True{}:
          do IO<Unit>:
            Unit <- T.Timui.close(ui)
            IO.print("birc=ok")
        case False{}:
          do IO<Unit>:
            rows : U32 <- T.Timui.rows()
            ui2 : T.Ui <- Paint.paint(ui, V.view(cl, NatU.body_h(rows)))
            evs : List<&2, T.UiEvent> <- T.Timui.events()
            ui_loop(p, T.has_quit(evs), ui2, cl)

def run_demo(+frames: U32, +cl: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    ui_loop(fuel_of(frames), False{}, ui, cl)

def dns_die(e: U32 & String) -> IO(Unit):
  match e:
    case (code, +msg):
      IO.die(Unit, code, "cannot resolve: " ++ msg)

def main_live_on(
  +frames: U32,
  +port: U32,
  +nick: String,
  +chan: String,
  r: Result<&1, &1, U32 & String, String>
) -> IO(Unit):
  match r:
    case Done{+ip}:
      Net.run_live(frames, ip, port, nick, chan)
    case Fail{e}:
      dns_die(e)

def main_live(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- Dns.resolve(host)
    main_live_on(frames, port, nick, chan, r)

def main_dispatch(+frames: U32, demo: Bool, +host: String, +port: U32, +nick: String, +chan: String) -> IO(Unit):
  match demo:
    case True{}:
      run_demo(frames, Cl.feed_all(Cl.init("me", "irc.birc.dev"), Cl.demo_lines()))
    case False{}:
      main_live(frames, host, port, nick, chan)

def main_cfg(+cfg: Args.Cfg) -> IO(Unit):
  match cfg:
    case Args.Cfg{demo, frames, +host, port, +nick, +chan}:
      main_dispatch(frames, demo, host, port, nick, chan)

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
