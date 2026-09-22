# IRC networking UI loop (M4). Actor lives in actor.bend.
# IO.spawn net actor owns Socket; UI ↔ actor via Chan(Sess.NetEvt)/Chan(Sess.NetCmd).
# D3: TCP.send String; inbound octets via recv_octets, framed by Fr.push.
# Shutdown: actor Socket.close then Timui.close (drain evt after Chan.close(cmd)).
# Dial: actor owns the fd (never Chan(Socket)). Demo/Connecting Cont is
# held (empty outs) so queued JOIN/PRIVMSG cannot flush after Dial.
# frames=0 uses @unsafe idle; --frames N is fuel.
# Eof: UI spawns a fresh idle actor on new channels and keeps painting.
import Base
import ./irc.bend as Irc
import ./buffer.bend as Cl
import ./view.bend as V
import ./timui.bend as T
import ./session.bend as Sess
import ./clock.bend as Clock
import ./actor.bend as Act

# Close cmd so the actor can flush pending and post Eof. Wait for that Eof
# (skip Tick/Chunk) before Timui.close; do not Chan.close(evt) — a recv after
# close deadlocks (chunk_flood /quit vs FIN).
# checker: expected a decreasing self-call / observed wait_eof.g
def wait_eof.g(fuel: Nat, ui: T.Ui, +evt: Chan(Sess.NetEvt), g: Maybe<&1, Sess.NetEvt>) -> IO(Unit):
  match fuel:
    case 0n:
      T.Timui.close(ui)
    case 1n+p:
      match g:
        case None{}:
          T.Timui.close(ui)
        case Some{e}:
          match e:
            case Sess.Eof{}:
              T.Timui.close(ui)
            case _:
              do IO<Unit>:
                g2 : Maybe<&1, Sess.NetEvt> <- Chan.recv(Sess.NetEvt, evt)
                wait_eof.g(p, ui, evt, g2)

def shutdown(ui: T.Ui, +evt: Chan(Sess.NetEvt), +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    g0 : Maybe<&1, Sess.NetEvt> <- Chan.recv(Sess.NetEvt, evt)
    Unit <- wait_eof.g(256n, ui, evt, g0)
    Unit <- IO.print("birc=ok")
    IO.die(Unit, 0, "")

def paint_vm(ui: T.Ui, +vm: V.ViewModel, +seed: U32, +page: U32, +wait: U32, +wake: U32) -> IO(T.Ui & T.UiKeys):
  match vm:
    case V.ViewModel{+ops, +inp}:
      T.Timui.frame(ui, ops, inp, seed, page, wait, wake)

def paint_session.size(
  ui: T.Ui,
  +cl: Cl.Client,
  +draft: String,
  +net: Sess.NetState,
  +seed: U32,
  size: Sess.Size,
  +wait: U32,
  +wake: U32
) -> IO(T.Ui & T.UiKeys):
  match size:
    case Sess.Size{+rows, cols}:
      paint_vm(ui, V.view_draft(cl, rows, cols, draft, Sess.net_label(net)), seed, U32.from_nat(Sess.body_h(rows)), wait, wake)

def paint_session.wait(
  ui: T.Ui,
  +cl: Cl.Client,
  +draft: String,
  +net: Sess.NetState,
  +seed: U32,
  size: Sess.Size,
  +wake: U32,
  +until: U32,
  now: Nat
) -> IO(T.Ui & T.UiKeys):
  paint_session.size(ui, cl, draft, net, seed, size, Sess.wait_ms.at(net, until, String.is_empty(draft), U32.from_nat(now)), wake)

def paint_session(ui: T.Ui, +st: Sess.Session) -> IO(T.Ui & T.UiKeys):
  match st:
    case Sess.Session{+cl, _, _, +draft, _, _, +net, _, size, seed, wake, until}:
      do IO<T.Ui & T.UiKeys>:
        now : Nat <- IO.now()
        paint_session.wait(ui, cl, draft, net, seed, size, wake, until, now)

def after_ui_send(
  ok: Bool,
  ui: T.Ui,
  +st2: Sess.Session,
  quit: Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match ok:
    case False{}:
      shutdown(ui, evt, cmd)
    case True{}:
      k((ui, st2, evt, cmd, quit))

def send_pair(
  ui: T.Ui,
  quit: Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  pair: Sess.Session & Sess.NetCmd & Bool,
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (+st2, rest):
      match rest:
        case (+ncmd, halt):
          do IO<Unit>:
            ok : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.hold_cmd(Sess.session_net(st2), Sess.merge_cmd(pending, ncmd)))
            after_ui_send(ok, ui, st2, Bool.or(quit, halt), evt, cmd, k)

def step_size(
  triple: Sess.Session & Sess.NetCmd & Bool,
  +rows: U32,
  +cols: U32
) -> Sess.Session & Sess.NetCmd & Bool:
  match triple:
    case (+st, rest):
      match rest:
        case (+cmd, halt):
          (Sess.session_set_size(st, rows, cols), cmd, halt)

def with_keys.go(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +keys: Sess.Keys,
  +rows: U32,
  +cols: U32,
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit),
  quit: Bool
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    now : Nat <- IO.now()
    send_pair(ui, quit, evt, cmd, step_size(Sess.step_keys(Sess.session_touch_if(Sess.session_set_now(st, ts), U32.from_nat(now), Sess.keys_hot(keys)), keys), rows, cols), pending, k)

def with_keys(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ukeys: T.UiKeys,
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match ukeys:
    case T.UiKeys{quit, enter, +typed, rows, cols, tab, click, up, dn, hist}:
      with_keys.go(ui, st, evt, cmd, Sess.keys_of(typed, T.flag_on(enter), tab, click, up, dn, hist), rows, cols, pending, k, T.flag_on(quit))

def with_tick.got(
  got: T.Ui & T.UiKeys,
  +st2: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match got:
    case (ui2, keys):
      with_keys(ui2, st2, evt, cmd, keys, pending, k)

def with_tick_pend(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +pending: List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st)
    with_tick.got(got, st, evt, cmd, pending, k)

def with_tick(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  with_tick_pend(ui, st, evt, cmd, Nil{}, k)

def with_chunk_pair(
  ui: T.Ui,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  pair: Sess.Session & List<&2, String>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (+st2, +outs):
      with_tick_pend(ui, st2, evt, cmd, outs, k)

def with_chunk.ts(
  ui: T.Ui,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +ts: String,
  +st: Sess.Session,
  xs: List<&2, U32>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  with_chunk_pair(ui, evt, cmd, Sess.step_on_chunk(Sess.session_set_now(st, ts), xs), k)

def with_chunk(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  xs: List<&2, U32>,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    now : Nat <- IO.now()
    with_chunk.ts(ui, evt, cmd, ts, Sess.session_touch(st, U32.from_nat(now)), xs, k)

def with_fail(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +msg: String,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    now : Nat <- IO.now()
    with_tick(ui, Sess.session_touch(Sess.session_fail(Sess.session_set_now(st, ts), msg), U32.from_nat(now)), evt, cmd, k)
def with_eof.go(
  ui: T.Ui,
  +st: Sess.Session,
  +cmd: Chan(Sess.NetCmd),
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit),
  evt0: Chan(Sess.NetEvt),
  cmd0: Chan(Sess.NetCmd)
) -> IO(Unit):
  +evt2 = evt0
  +cmd2 = cmd0
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    now : Nat <- IO.now()
    Unit <- IO.spawn(Unit, Act.idle_start(Sess.session_nick(st), frames, evt2, cmd2))
    Unit <- Chan.close(Sess.NetCmd, cmd)
    with_tick(ui, Sess.session_touch(Sess.session_fail(Sess.session_set_now(st, ts), "disconnected"), U32.from_nat(now)), evt2, cmd2, k)

def with_eof(
  ui: T.Ui,
  +st: Sess.Session,
  +cmd: Chan(Sess.NetCmd),
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    evt0 : Chan(Sess.NetEvt) <- Chan.new(Sess.NetEvt, 64)
    cmd0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    with_eof.go(ui, st, cmd, frames, k, evt0, cmd0)

def on_evt_up(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +fd: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    now : Nat <- IO.now()
    with_tick(ui, Sess.session_touch(Sess.session_set_wake(Sess.session_online(st), fd), U32.from_nat(now)), evt, cmd, k)

def on_evt_some(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  e: Sess.NetEvt,
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match e:
    case Sess.Eof{}:
      with_eof(ui, st, cmd, frames, k)
    case Sess.Tick{}:
      with_tick(ui, st, evt, cmd, k)
    case Sess.Chunk{xs}:
      with_chunk(ui, st, evt, cmd, xs, k)
    case Sess.Up{fd}:
      on_evt_up(ui, st, evt, cmd, fd, k)
    case Sess.Fail{+msg}:
      with_fail(ui, st, evt, cmd, msg, k)

def on_evt(
  g: Maybe<&1, Sess.NetEvt>,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      shutdown(ui, evt, cmd)
    case Some{e}:
      on_evt_some(ui, st, evt, cmd, e, frames, k)

def live_step(
  quit: Bool,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +frames: U32,
  k: (T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool) -> IO(Unit)
) -> IO(Unit):
  match quit:
    case True{}:
      shutdown(ui, evt, cmd)
    case False{}:
      do IO<Unit>:
        got : Maybe<&1, Sess.NetEvt> <- Chan.recv(Sess.NetEvt, evt)
        on_evt(got, ui, st, evt, cmd, frames, k)

# checker: expected a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks) / observed live_go
def live_go(
  fuel: Nat,
  acc: T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool,
  +frames: U32
) -> IO(Unit):
  match fuel:
    case 0n:
      match acc:
        case (ui, _, evt, cmd, _):
          shutdown(ui, evt, cmd)
    case 1n+p:
      match acc:
        case (ui, +st, evt, cmd, quit):
          live_step(quit, ui, st, evt, cmd, frames, nxt => live_go(p, nxt, frames))

@unsafe
def live_idle(
  acc: T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool,
  +frames: U32
) -> IO(Unit):
  match acc:
    case (ui, +st, evt, cmd, quit):
      live_step(quit, ui, st, evt, cmd, frames, nxt => live_idle(nxt, frames))
def boot_clock.step(n: Nat, ok: Bool, +boot: Chan(Act.Boot), +stop: Chan(Unit)) -> IO(Unit):
  match n:
    case 0n:
      match ok:
        case False{}:
          IO.pure(Unit, Unit{})
        case True{}:
          do IO<Unit>:
            t : Bool <- Chan.send(Act.Boot, boot, Act.Timeout{})
            return Unit{}
    case 1n+p:
      match ok:
        case False{}:
          IO.pure(Unit, Unit{})
        case True{}:
          do IO<Unit>:
            Unit <- IO.sleep(100)
            nxt : Bool <- Chan.send(Unit, stop, Unit{})
            boot_clock.step(p, nxt, boot, stop)

def boot_clock(+boot: Chan(Act.Boot), +stop: Chan(Unit)) -> IO(Unit):
  boot_clock.step(80n, True{}, boot, stop)

def live_boot.acc(
  zero: Bool,
  +frames: U32,
  acc: T.Ui & Sess.Session & Chan(Sess.NetEvt) & Chan(Sess.NetCmd) & Bool
) -> IO(Unit):
  match zero:
    case True{}:
      live_idle(acc, frames)
    case False{}:
      live_go(Sess.ticks_of(frames), acc, frames)

def live_boot.on(
  zero: Bool,
  +frames: U32,
  trip: T.Ui & Sess.Session & Bool,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  match trip:
    case (ui, +st, quit):
      live_boot.acc(zero, frames, (ui, st, evt, cmd, quit))

def start_ui(
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +chan: String
) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.Cont{Nil{}})
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    live_boot.on(U32.is_eq(frames, 0), frames, (ui, Sess.session0(nick, host, chan), False{}), evt, cmd)

def boot_die(+cmd: Chan(Sess.NetCmd), +msg: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    IO.die(Unit, 1, msg)

def boot_ui_on(
  e: Act.Boot,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +chan: String
) -> IO(Unit):
  match e:
    case Act.Timeout{}:
      boot_die(cmd, "connect timeout")
    case Act.Down{+msg}:
      boot_die(cmd, msg)
    case Act.Ready{}:
      start_ui(frames, evt, cmd, nick, host, chan)

def boot_ui(
  g: Maybe<&1, Act.Boot>,
  +boot: Chan(Act.Boot),
  +stop: Chan(Unit),
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +chan: String
) -> IO(Unit):
  match g:
    case None{}:
      boot_die(cmd, "connect failed")
    case Some{e}:
      do IO<Unit>:
        Unit <- Chan.close(Act.Boot, boot)
        Unit <- Chan.close(Unit, stop)
        boot_ui_on(e, frames, evt, cmd, nick, host, chan)

def run_live_on(
  +frames: U32,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  evt0: Chan(Sess.NetEvt),
  cmd0: Chan(Sess.NetCmd),
  boot0: Chan(Act.Boot),
  stop0: Chan(Unit)
) -> IO(Unit):
  +evt = evt0
  +cmd = cmd0
  +boot = boot0
  +stop = stop0
  do IO<Unit>:
    Unit <- IO.spawn(Unit, Act.actor_boot(host, port, nick, frames, evt, cmd, boot))
    Unit <- IO.spawn(Unit, boot_clock(boot, stop))
    g : Maybe<&1, Act.Boot> <- Chan.recv(Act.Boot, boot)
    boot_ui(g, boot, stop, frames, evt, cmd, nick, host, chan)

def run_live(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String) -> IO(Unit):
  do IO<Unit>:
    evt0 : Chan(Sess.NetEvt) <- Chan.new(Sess.NetEvt, 64)
    cmd0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    boot0 : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    stop0 : Chan(Unit) <- Chan.new(Unit, 80)
    run_live_on(frames, host, port, nick, chan, evt0, cmd0, boot0, stop0)

def boot_demo(
  ui: T.Ui,
  +cl: Cl.Client,
  +chan: String,
  +ts: String,
  +frames: U32,
  +evt: Chan(Sess.NetEvt),
  +cmd: Chan(Sess.NetCmd)
) -> IO(Unit):
  live_boot.on(U32.is_eq(frames, 0), frames, (ui, Sess.session_set_now(Sess.session_demo(cl, chan), ts), False{}), evt, cmd)

def run_offline_on(
  +frames: U32,
  +cl: Cl.Client,
  +nick: String,
  +chan: String,
  evt0: Chan(Sess.NetEvt),
  cmd0: Chan(Sess.NetCmd)
) -> IO(Unit):
  +evt = evt0
  +cmd = cmd0
  do IO<Unit>:
    Unit <- IO.spawn(Unit, Act.idle_start(nick, frames, evt, cmd))
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    ts : String <- Clock.hhmmss()
    boot_demo(ui, cl, chan, ts, frames, evt, cmd)

def run_offline(+frames: U32, +cl: Cl.Client, +nick: String, +chan: String) -> IO(Unit):
  do IO<Unit>:
    evt0 : Chan(Sess.NetEvt) <- Chan.new(Sess.NetEvt, 64)
    cmd0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    run_offline_on(frames, cl, nick, chan, evt0, cmd0)
