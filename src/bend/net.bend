# IRC UI loop. Writer owns the Socket and blocks on NetCmd. Reader owns a
# dup and parks in recv_octets. The UI parks on Chan(UiMsg).
import Base
import ./buffer.bend as Cl
import ./view.bend as V
import ./timui.bend as T
import ./session.bend as Sess
import ./clock.bend as Clock
import ./actor.bend as Act

def shutdown_finish(ui: T.Ui) -> IO(Unit):
  do IO<Unit>:
    Unit <- T.Timui.close(ui)
    Unit <- IO.print("birc=ok")
    IO.die(Unit, 0, "")

def shutdown_eof(same: Bool, ui: T.Ui, k: T.Ui -> IO(Unit)) -> IO(Unit):
  match same:
    case True{}:
      shutdown_finish(ui)
    case False{}:
      k(ui)

def shutdown_on(
  g: Maybe<&1, Sess.UiMsg>,
  ui: T.Ui,
  +gen: U32,
  k: T.Ui -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      shutdown_finish(ui)
    case Some{m}:
      match m:
        case Sess.FromNet{got, e}:
          match e:
            case Sess.Eof{}:
              shutdown_eof(U32.is_eq(got, gen), ui, k)
            case _:
              k(ui)
        case _:
          k(ui)

# Close cmd so the writer flushes QUIT and posts Eof. Do not close evt:
# a recv after close deadlocks. Skip a stale generation.
@unsafe
def shutdown_wait(ui: T.Ui, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    shutdown_on(g, ui, gen, u => shutdown_wait(u, evt, gen))

# A dial parks inside TCP.connect. Quit must not wait for that SYN.
def shutdown_waits(net: Sess.NetState) -> Bool:
  match net:
    case Sess.Connecting{}:
      False{}
    case _:
      True{}

def shutdown_pick(wait: Bool, ui: T.Ui, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  match wait:
    case True{}:
      shutdown_wait(ui, evt, gen)
    case False{}:
      shutdown_finish(ui)

def shutdown(ui: T.Ui, +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +evt: Chan(Sess.UiMsg), +gen: U32, wait: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- Chan.close(Unit, ack)
    shutdown_pick(wait, ui, evt, gen)

def paint_vm(ui: T.Ui, +vm: V.ViewModel, +seed: U32) -> IO(T.Ui & T.UiKeys):
  match vm:
    case V.ViewModel{+ops, +inp}:
      T.Timui.frame(ui, ops, inp, seed)

def paint_go(
  ui: T.Ui,
  +cl: Cl.Client,
  +draft: String,
  +net: Sess.NetState,
  +seed: U32,
  size: Sess.Size
) -> IO(T.Ui & T.UiKeys):
  match size:
    case Sess.Size{+rows, cols}:
      paint_vm(ui, V.view_draft(cl, rows, cols, draft, Sess.net_label(net)), seed)

def paint_session(ui: T.Ui, +st: Sess.Session) -> IO(T.Ui & T.UiKeys):
  match st:
    case Sess.Session{+cl, _, _, +draft, _, _, +net, _, size, seed}:
      paint_go(ui, cl, draft, net, seed, size)

def outs_nil(+xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def emit_outs(chan: Chan(Sess.NetCmd), +outs: List<&2, String>, +gen: U32, empty: Bool) -> IO(U32):
  match empty:
    case True{}:
      IO.pure(U32, gen)
    case False{}:
      do IO<U32>:
        ok : Bool <- Chan.send(Sess.NetCmd, chan, Sess.Cont{outs})
        return gen

def emit_cmd(chan: Chan(Sess.NetCmd), c: Sess.NetCmd, +gen: U32) -> IO(U32):
  match c:
    case Sess.Dial{+host, port, _}:
      do IO<U32>:
        ok : Bool <- Chan.send(Sess.NetCmd, chan, Sess.Dial{host, port, U32.add(gen, 1)})
        return U32.add(gen, 1)
    case Sess.Cont{+outs}:
      emit_outs(chan, outs, gen, outs_nil(outs))
    case Sess.Handoff{_}:
      IO.pure(U32, gen)

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

def apply_frame.go(
  ui: T.Ui,
  triple: Sess.Session & Sess.NetCmd & Bool,
  quit: Bool,
  more: Bool
) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  match triple:
    case (+st, rest):
      match rest:
        case (+cmd, halt):
          (ui, st, cmd, Bool.or(quit, halt), more)

def apply_pol(
  ui: T.Ui,
  +st: Sess.Session,
  enter: Bool,
  +typed: String,
  +rows: U32,
  +cols: U32,
  +click: U32,
  more: Bool,
  pol: Sess.KeyPol
) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  match pol:
    case Sess.KeyPol{tab, up, dn, hist, quit}:
      apply_frame.go(ui, step_size(Sess.step_keys(st, Sess.keys_of(typed, enter, tab, click, up, dn, hist)), rows, cols), T.flag_on(quit), more)

def apply_frame(
  got: T.Ui & T.UiKeys,
  +st: Sess.Session
) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  match got:
    case (ui, keys):
      match keys:
        case T.UiKeys{enter, +typed, +rows, cols, click, key, mods, wheel, more}:
          apply_pol(ui, st, T.flag_on(enter), typed, rows, cols, click, T.flag_on(more), Sess.key_pol(key, mods, wheel, rows))

def handle_more.done(is_key: Bool, +ack: Chan(Unit)) -> IO(Unit):
  match is_key:
    case True{}:
      do IO<Unit>:
        _ : Bool <- Chan.send(Unit, ack, Unit{})
        return Unit{}
    case False{}:
      IO.pure(Unit, Unit{})

def handle_more(
  more: Bool,
  is_key: Bool,
  +evt: Chan(Sess.UiMsg),
  +ack: Chan(Unit)
) -> IO(Unit):
  match more:
    case True{}:
      do IO<Unit>:
        _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.Key{})
        return Unit{}
    case False{}:
      handle_more.done(is_key, ack)

def after_emit(
  gen: U32,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  halt: Bool,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match halt:
    case True{}:
      shutdown(ui, cmd, ack, evt, gen, shutdown_waits(Sess.session_net(st)))
    case False{}:
      k((ui, st, gen, False{}))

# timui_begin reads the tty on every frame, including a chunk or Eof
# paint. Dropping those keys swallows /quit: the watcher is already back
# in POLLIN, the line is gone, and shutdown never runs.
def on_key_cmd(
  is_key: Bool,
  packed: T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match packed:
    case (ui, rest):
      match rest:
        case (+st, rest2):
          match rest2:
            case (+ncmd, rest3):
              match rest3:
                case (halt, more):
                  do IO<Unit>:
                    gen2 : U32 <- emit_cmd(cmd, ncmd, gen)
                    Unit <- handle_more(more, is_key, evt, ack)
                    after_emit(gen2, ui, st, evt, cmd, ack, halt, frames, k)

def on_chunk.paint(
  got: T.Ui & T.UiKeys,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_key_cmd(False{}, apply_frame(got, st), evt, cmd, ack, gen, frames, k)

def on_chunk_go(
  pair: Sess.Session & List<&2, String>,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (+st2, +outs):
      do IO<Unit>:
        gen2 : U32 <- emit_outs(cmd, outs, gen, outs_nil(outs))
        got : T.Ui & T.UiKeys <- paint_session(ui, st2)
        on_chunk.paint(got, st2, evt, cmd, ack, gen2, frames, k)

def on_chunk(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  xs: List<&2, U32>,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_chunk_go(Sess.step_on_chunk(st, xs), ui, evt, cmd, ack, gen, frames, k)

def on_up_go(
  +st2: Sess.Session,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st2)
    on_chunk.paint(got, st2, evt, cmd, ack, gen, frames, k)

def on_up(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_up_go(Sess.session_online(st), ui, evt, cmd, ack, gen, frames, k)

def on_fail_go(
  +st2: Sess.Session,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st2)
    on_chunk.paint(got, st2, evt, cmd, ack, gen, frames, k)

def on_fail(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  +msg: String,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    on_fail_go(Sess.session_fail(Sess.session_set_now(st, ts), msg), ui, evt, cmd, ack, gen, frames, k)

def on_evt(
  e: Sess.NetEvt,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match e:
    case Sess.Chunk{xs}:
      on_chunk(ui, st, evt, cmd, ack, gen, frames, xs, k)
    case Sess.Up{_}:
      on_up(ui, st, evt, cmd, ack, gen, frames, k)
    case Sess.Eof{}:
      on_fail(ui, st, evt, cmd, ack, gen, frames, "disconnected", k)
    case Sess.Fail{+msg}:
      on_fail(ui, st, evt, cmd, ack, gen, frames, msg, k)
    case Sess.Tick{}:
      k((ui, st, gen, False{}))

def on_from(
  +got: U32,
  e: Sess.NetEvt,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  same: Bool,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match same:
    case False{}:
      k((ui, st, gen, False{}))
    case True{}:
      on_evt(e, ui, st, evt, cmd, ack, gen, frames, k)

def on_key(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st)
    on_key_cmd(True{}, apply_frame(got, st), evt, cmd, ack, gen, frames, k)

def apply_pack(
  ui: T.Ui,
  +st: Sess.Session,
  cmd: Sess.NetCmd,
  halt: Bool,
  more: Bool
) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  (ui, st, cmd, halt, more)

def on_resize.redo(
  ui2: T.Ui,
  +st2: Sess.Session,
  +ncmd: Sess.NetCmd,
  halt: Bool,
  more: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match halt:
    case True{}:
      on_key_cmd(False{}, apply_pack(ui2, st2, ncmd, halt, more), evt, cmd, ack, gen, frames, k)
    case False{}:
      do IO<Unit>:
        gen2 : U32 <- emit_cmd(cmd, ncmd, gen)
        Unit <- handle_more(more, False{}, evt, ack)
        got2 : T.Ui & T.UiKeys <- paint_session(ui2, st2)
        on_key_cmd(False{}, apply_frame(got2, st2), evt, cmd, ack, gen2, frames, k)

def on_resize.pick(
  same: Bool,
  ui2: T.Ui,
  +st2: Sess.Session,
  +ncmd: Sess.NetCmd,
  halt: Bool,
  more: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match same:
    case True{}:
      on_key_cmd(False{}, apply_pack(ui2, st2, ncmd, halt, more), evt, cmd, ack, gen, frames, k)
    case False{}:
      on_resize.redo(ui2, st2, ncmd, halt, more, evt, cmd, ack, gen, frames, k)

def on_resize.check(
  packed: T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool,
  old_sz: Sess.Size,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match packed:
    case (ui2, rest):
      match rest:
        case (+st2, rest2):
          match rest2:
            case (+ncmd, rest3):
              match rest3:
                case (halt, more):
                  on_resize.pick(
                    Sess.size_eq(old_sz, Sess.session_size(st2)),
                    ui2, st2, ncmd, halt, more, evt, cmd, ack, gen, frames, k
                  )

# Resize paints the new size and applies whatever the frame read. When
# terminal dimensions change, an immediate second redraw with the updated
# session size prevents stale viewport rendering (V-06).
def on_resize.go(
  old_sz: Sess.Size,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st)
    on_resize.check(apply_frame(got, st), old_sz, evt, cmd, ack, gen, frames, k)

def on_resize(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_resize.go(Sess.session_size(st), ui, st, evt, cmd, ack, gen, frames, k)

def on_msg(
  m: Sess.UiMsg,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match m:
    case Sess.Key{}:
      on_key(ui, st, evt, cmd, ack, gen, frames, k)
    case Sess.Resize{}:
      on_resize(ui, st, evt, cmd, ack, gen, frames, k)
    case Sess.FromNet{+got, e}:
      on_from(got, e, ui, st, evt, cmd, ack, gen, frames, U32.is_eq(got, gen), k)

def on_recv(
  g: Maybe<&1, Sess.UiMsg>,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      shutdown(ui, cmd, ack, evt, gen, shutdown_waits(Sess.session_net(st)))
    case Some{m}:
      on_msg(m, ui, st, evt, cmd, ack, gen, frames, k)

def live_step(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  quit: Bool,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match quit:
    case True{}:
      shutdown(ui, cmd, ack, evt, gen, shutdown_waits(Sess.session_net(st)))
    case False{}:
      do IO<Unit>:
        g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
        on_recv(g, ui, st, evt, cmd, ack, gen, frames, k)

def live_go(
  fuel: Nat,
  acc: T.Ui & Sess.Session & U32 & Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32
) -> IO(Unit):
  match fuel:
    case 0n:
      match acc:
        case (ui, +st, gen, _):
          shutdown(ui, cmd, ack, evt, gen, shutdown_waits(Sess.session_net(st)))
    case 1n+p:
      match acc:
        case (ui, +st, gen, quit):
          live_step(ui, st, evt, cmd, ack, gen, frames, quit, nxt => live_go(p, nxt, evt, cmd, ack, frames))

@unsafe
def live_idle(
  acc: T.Ui & Sess.Session & U32 & Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32
) -> IO(Unit):
  match acc:
    case (ui, +st, gen, quit):
      live_step(ui, st, evt, cmd, ack, gen, frames, quit, nxt => live_idle(nxt, evt, cmd, ack, frames))

def live_boot(zero: Bool, +frames: U32, ui: T.Ui, +st: Sess.Session, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit)) -> IO(Unit):
  match zero:
    case True{}:
      live_idle((ui, st, gen, False{}), evt, cmd, ack, frames)
    case False{}:
      live_go(Sess.ticks_of(frames), (ui, st, gen, False{}), evt, cmd, ack, frames)

def tty_watch.ack(
  g: Maybe<&1, Unit>,
  tty: T.Tty,
  k: T.Tty -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      T.Tty.close(tty)
    case Some{_}:
      k(tty)

def tty_watch.on(
  ok: Bool,
  tty: T.Tty,
  +ack: Chan(Unit),
  k: T.Tty -> IO(Unit)
) -> IO(Unit):
  match ok:
    case False{}:
      T.Tty.close(tty)
    case True{}:
      do IO<Unit>:
        g : Maybe<&1, Unit> <- Chan.recv(Unit, ack)
        tty_watch.ack(g, tty, k)

@unsafe
def tty_watch(tty: T.Tty, +evt: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    tty2 : T.Tty <- T.Tty.ready(tty)
    ok : Bool <- Chan.send(Sess.UiMsg, evt, Sess.Key{})
    tty_watch.on(ok, tty2, ack, t => tty_watch(t, evt, ack))

def winch_watch.on(ok: Bool, w: T.Winch, k: T.Winch -> IO(Unit)) -> IO(Unit):
  match ok:
    case False{}:
      T.Winch.close(w)
    case True{}:
      k(w)

@unsafe
def winch_watch(w: T.Winch, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    w2 : T.Winch <- T.Winch.ready(w)
    ok : Bool <- Chan.send(Sess.UiMsg, evt, Sess.Resize{})
    winch_watch.on(ok, w2, w3 => winch_watch(w3, evt))

def watch_paint(
  packed: T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  tty: T.Tty,
  w: T.Winch
) -> IO(Unit):
  match packed:
    case (ui, rest):
      match rest:
        case (+st, rest2):
          match rest2:
            case (+ncmd, rest3):
              match rest3:
                case (halt, more):
                  match halt:
                    case True{}:
                      shutdown(ui, cmd, ack, evt, gen, shutdown_waits(Sess.session_net(st)))
                    case False{}:
                      do IO<Unit>:
                        gen2 : U32 <- emit_cmd(cmd, ncmd, gen)
                        Unit <- handle_more(more, False{}, evt, ack)
                        Unit <- IO.spawn(Unit, tty_watch(tty, evt, ack))
                        Unit <- IO.spawn(Unit, winch_watch(w, evt))
                        live_boot(U32.is_eq(frames, 0), frames, ui, st, gen2, evt, cmd, ack)

def watch_die(e: U32 & String, ui: T.Ui) -> IO(Unit):
  match e:
    case (code, +msg):
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        IO.die(Unit, code, msg)

def watch_die_tty(e: U32 & String, tty: T.Tty, ui: T.Ui) -> IO(Unit):
  match e:
    case (code, +msg):
      do IO<Unit>:
        Unit <- T.Tty.close(tty)
        Unit <- T.Timui.close(ui)
        IO.die(Unit, code, msg)

def watch_win(
  wr: Result<&1, &1, U32 & String, T.Winch>,
  tty: T.Tty,
  ui: T.Ui,
  +st: Sess.Session,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32
) -> IO(Unit):
  match wr:
    case Fail{e}:
      watch_die_tty(e, tty, ui)
    case Done{w}:
      do IO<Unit>:
        got : T.Ui & T.UiKeys <- paint_session(ui, st)
        watch_paint(apply_frame(got, st), gen, evt, cmd, ack, frames, tty, w)

def watch_die_win(
  wr: Result<&1, &1, U32 & String, T.Winch>,
  e: U32 & String,
  ui: T.Ui
) -> IO(Unit):
  match wr:
    case Done{w}:
      do IO<Unit>:
        Unit <- T.Winch.close(w)
        watch_die(e, ui)
    case Fail{_}:
      watch_die(e, ui)

def watch_go(
  tr: Result<&1, &1, U32 & String, T.Tty>,
  wr: Result<&1, &1, U32 & String, T.Winch>,
  ui: T.Ui,
  +st: Sess.Session,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32
) -> IO(Unit):
  match tr:
    case Fail{e}:
      watch_die_win(wr, e, ui)
    case Done{tty}:
      watch_win(wr, tty, ui, st, gen, evt, cmd, ack, frames)

def open_tty(
  pair: T.Ui & Result<&1, &1, U32 & String, T.Tty>,
  +st: Sess.Session,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  wr: Result<&1, &1, U32 & String, T.Winch>
) -> IO(Unit):
  match pair:
    case (ui, tr):
      watch_go(tr, wr, ui, st, gen, evt, cmd, ack, frames)

def open_watch(ui: T.Ui, +st: Sess.Session, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +frames: U32) -> IO(Unit):
  do IO<Unit>:
    wr : Result<&1, &1, U32 & String, T.Winch> <- T.Winch.open()
    pair : T.Ui & Result<&1, &1, U32 & String, T.Tty> <- T.Timui.tty(ui)
    open_tty(pair, st, gen, evt, cmd, ack, frames, wr)

def smoke_painted(
  got: T.Ui & T.UiKeys,
  k: T.Ui -> IO(Unit)
) -> IO(Unit):
  match got:
    case (ui, _):
      k(ui)

@unsafe
def smoke_go(n: Nat, ui: T.Ui, +st: Sess.Session) -> IO(Unit):
  match n:
    case 0n:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        Unit <- IO.print("birc=ok")
        IO.die(Unit, 0, "")
    case 1n+p:
      do IO<Unit>:
        got : T.Ui & T.UiKeys <- paint_session(ui, st)
        smoke_painted(got, u => smoke_go(p, u, st))

def smoke(+frames: U32, +cl: Cl.Client, +chan: String, +ts: String) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    smoke_go(Sess.ticks_of(frames), ui, Sess.session_set_now(Sess.session_demo(cl, chan), ts))

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

def boot_die(+cmd: Chan(Sess.NetCmd), +msg: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    IO.die(Unit, 1, msg)

def start_ui(
  +frames: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +chan: String
) -> IO(Unit):
  do IO<Unit>:
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    open_watch(ui, Sess.session0(nick, host, chan), 1, evt, cmd, ack, frames)

def boot_ui_on(
  e: Act.Boot,
  +frames: U32,
  +evt: Chan(Sess.UiMsg),
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
  +evt: Chan(Sess.UiMsg),
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
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Act.Boot),
  +stop: Chan(Unit)
) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.spawn(Unit, Act.actor_boot(host, port, nick, 1, evt, cmd, boot))
    Unit <- IO.spawn(Unit, boot_clock(boot, stop))
    g : Maybe<&1, Act.Boot> <- Chan.recv(Act.Boot, boot)
    boot_ui(g, boot, stop, frames, evt, cmd, nick, host, chan)

def run_live(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String) -> IO(Unit):
  do IO<Unit>:
    evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    stop : Chan(Unit) <- Chan.new(Unit, 80)
    run_live_on(frames, host, port, nick, chan, evt, cmd, boot, stop)

def run_demo_go(
  evt0: Chan(Sess.UiMsg),
  cmd0: Chan(Sess.NetCmd),
  ack: Chan(Unit),
  +frames: U32,
  +cl: Cl.Client,
  +nick: String,
  +chan: String,
  +ts: String
) -> IO(Unit):
  +evt = evt0
  +cmd = cmd0
  do IO<Unit>:
    Unit <- IO.spawn(Unit, Act.idle_start(nick, evt, cmd))
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    open_watch(ui, Sess.session_set_now(Sess.session_demo(cl, chan), ts), 0, evt, cmd, ack, frames)

def run_demo_tty(+frames: U32, +cl: Cl.Client, +nick: String, +chan: String, +ts: String) -> IO(Unit):
  do IO<Unit>:
    evt0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    cmd0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    run_demo_go(evt0, cmd0, ack, frames, cl, nick, chan, ts)

def run_offline_pick(headless: Bool, +frames: U32, +cl: Cl.Client, +nick: String, +chan: String, +ts: String) -> IO(Unit):
  match headless:
    case True{}:
      smoke(frames, cl, chan, ts)
    case False{}:
      run_demo_tty(frames, cl, nick, chan, ts)

def run_offline(+frames: U32, +cl: Cl.Client, +nick: String, +chan: String) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    t : U32 <- T.Timui.isatty()
    run_offline_pick(U32.is_eq(t, 0), frames, cl, nick, chan, ts)
