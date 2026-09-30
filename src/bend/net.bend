# IRC UI loop. Writer owns the Socket and blocks on NetCmd. Reader owns a
# dup and parks in recv_octets. The UI parks on Chan(UiMsg).
import Base
import ./buffer.bend as Cl
import ./view.bend as V
import ./timui.bend as T
import ./session.bend as Sess
import ./split.bend as Sp
import ./clock.bend as Clock
import ./actor.bend as Act
import ./history.bend as Hist
import ./typing.bend as Ty

def endpoint(+host: String, +port: U32) -> String:
  host ++ ":" ++ U32.show(port)

def session_endpoint(+st: Sess.Session) -> String:
  endpoint(Cl.server_of(Sess.session_cl(st)), Sess.session_port(st))

def shutdown_finish(ui: T.Ui) -> IO(Unit):
  do IO<Unit>:
    Unit <- T.Timui.close(ui)
    T.Sys.exit_done()

def shutdown_failed(ui: T.Ui, +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +msg: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- Chan.close(Unit, ack)
    Unit <- T.Timui.close(ui)
    T.Sys.exit_fail(msg)

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
              shutdown_eof(Sess.event_current(Sess.FromNet{got, Sess.Eof{}}, gen), ui, k)
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

def frame_clipboard.on(+text: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, T.Sys.copy_clipboard(text))
        return Unit{}

def frame_clipboard(+text: String) -> IO(Unit):
  frame_clipboard.on(text, String.is_empty(text))

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
  size: Sess.Size,
  split: Sp.State,
  +typers: List<&2, String>
) -> IO(T.Ui & T.UiKeys):
  match size:
    case Sess.Size{+rows, cols}:
      paint_vm(ui, V.view_draft.state_typing(cl, rows, cols, draft, Sess.net_label_lag(net, Cl.client_lag(cl)), typers, split), seed)

def paint_session(ui: T.Ui, +st: Sess.Session) -> IO(T.Ui & T.UiKeys):
  match st:
    case Sess.Session{+cl, _, _, +draft, _, _, +net, _, size, seed, _, split, +typing, _}:
      paint_go(ui, cl, draft, net, seed, size, split, Ty.names(typing, Cl.active_buf_name(cl)))


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

def launch_fail(notice: Maybe<&2, Chan(Sess.UiMsg)>, +msg: String) -> IO(Unit):
  match notice:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{+evt}:
      do IO<Unit>:
        _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.UiError{msg})
        return Unit{}

def launch_exit(ok: Bool, +notice: Maybe<&2, Chan(Sess.UiMsg)>, +code: U32) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      launch_fail(notice, "cannot open link: opener exited " ++ U32.show(code))

def launch_result(r: Result<&1, &1, U32 & String, U32 & (String & String)>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match r:
    case Fail{e}:
      match e:
        case (_, +msg):
          launch_fail(notice, "cannot open link: " ++ msg)
    case Done{out}:
      match out:
        case (+code, _):
          launch_exit(U32.is_eq(code, 0), notice, code)

# Process.run owns and reaps the helper on its worker thread. Only the
# completion message touches the UI; neither spawn nor wait parks painting.
# Quit does not cancel external applications; an active helper is then
# adopted by the OS. Process.run has no cancellation handle.
def launch_run(+notice: Maybe<&2, Chan(Sess.UiMsg)>, +url: String) -> IO(Unit):
  do IO<Unit>:
    program : String <- T.Sys.open_program()
    result : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(program, url <> Nil{}, "", 4096, 2000)
    launch_result(result, notice)

def open_clicked.go(+notice: Maybe<&2, Chan(Sess.UiMsg)>, +url: String, empty: Bool) -> IO(Unit):
  match empty:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.spawn(Unit, launch_run(notice, url))

def open_clicked(+notice: Maybe<&2, Chan(Sess.UiMsg)>, +url: String) -> IO(Unit):
  open_clicked.go(notice, url, String.is_empty(url))

def emit_cmd(+evt: Chan(Sess.UiMsg), chan: Chan(Sess.NetCmd), c: Sess.NetCmd, +gen: U32) -> IO(U32):
  match c:
    case Sess.Dial{+host, port, _, +nick}:
      do IO<U32>:
        ok : Bool <- Chan.send(Sess.NetCmd, chan, Sess.Dial{host, port, U32.add(gen, 1), nick})
        return U32.add(gen, 1)
    case Sess.Drop{}:
      do IO<U32>:
        ok : Bool <- Chan.send(Sess.NetCmd, chan, Sess.Drop{})
        return gen
    case Sess.Cont{+outs}:
      emit_outs(chan, outs, gen, outs_nil(outs))
    case Sess.Pump{_}:
      IO.pure(U32, gen)
    case Sess.OpenUrl{+url}:
      do IO<U32>:
        Unit <- open_clicked(Some{evt}, url)
        return gen

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
    case Sess.KeyPol{tab, up, dn, hist, quit, comp, focus}:
      apply_frame.go(ui, step_size(Sess.step_keys(st, Sess.keys_of(typed, enter, tab, click, up, dn, hist, comp, focus)), rows, cols), T.flag_on(quit), more)


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
        _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.UiKey{})
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
                    gen2 : U32 <- emit_cmd(evt, cmd, ncmd, gen)
                    Unit <- handle_more(more, is_key, evt, ack)
                    after_emit(gen2, ui, st, evt, cmd, ack, halt, frames, k)

def apply_pack(
  ui: T.Ui,
  +st: Sess.Session,
  cmd: Sess.NetCmd,
  halt: Bool,
  more: Bool
) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  (ui, st, cmd, halt, more)

def pol_hot(+tab: U32, +click: U32, +up: U32, +dn: U32, +hist: U32, +enter: Bool, +comp: U32, +focus: U32) -> Bool:
  Bool.or(enter,
  Bool.or(Bool.not(U32.is_zero(tab)),
  Bool.or(Bool.not(U32.is_zero(click)),
  Bool.or(Bool.not(U32.is_zero(up)),
  Bool.or(Bool.not(U32.is_zero(dn)),
  Bool.or(Bool.not(U32.is_zero(hist)),
  Bool.or(Bool.not(U32.is_zero(comp)),
          Bool.not(U32.is_zero(focus)))))))))

# A frame always consumes input, regardless of what woke the UI. This is
# the single path for URLs, clipboard work, key policy, and updated size.
def frame_result.pol(
  ui: T.Ui,
  +st: Sess.Session,
  +enter: Bool,
  +typed: String,
  +rows: U32,
  +cols: U32,
  +click: U32,
  +more: Bool,
  pol: Sess.KeyPol,
  +url: String,
  +clipboard: String,
  +notice: Maybe<&2, Chan(Sess.UiMsg)>
) -> IO((T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool):
  match pol:
    case Sess.KeyPol{+tab, +up, +dn, +hist, +quit, +comp, +focus}:
      do IO<(T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool>:
        Unit <- open_clicked(notice, url)
        Unit <- frame_clipboard(clipboard)
        return (
          apply_pol(ui, st, enter, typed, rows, cols, click, more, Sess.KeyPol{tab, up, dn, hist, quit, comp, focus}),
          pol_hot(tab, click, up, dn, hist, enter, comp, focus) || Bool.not(Sess.size_eq(Sess.session_size(st), Sess.Size{rows, cols}))
        )

def frame_result.keys(ui: T.Ui, +st: Sess.Session, keys: T.UiKeys, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO((T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool):
  match keys:
    case T.UiKeys{enter, +typed, +rows, cols, click, key, mods, codepoint, wheel, more, +url, +clipboard}:
      frame_result.pol(ui, st, T.flag_on(enter), typed, rows, cols, click, T.flag_on(more), Sess.key_pol_for(st, key, mods, codepoint, wheel, rows), url, clipboard, notice)

def frame_result(got: T.Ui & T.UiKeys, +st: Sess.Session, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO((T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool):
  match got:
    case (ui, keys):
      frame_result.keys(ui, st, keys, notice)

def on_frame.final(
  result: (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool,
  +is_key: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match result:
    case (packed, _):
      on_key_cmd(is_key, packed, evt, cmd, ack, gen, frames, k)

# At most one immediate redraw. It too passes through frame_result, so
# a click or key consumed by that redraw is not lost.
def on_frame.redo(
  ui: T.Ui,
  +st: Sess.Session,
  +ncmd: Sess.NetCmd,
  halt: Bool,
  more: Bool,
  +is_key: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match halt:
    case True{}:
      on_key_cmd(is_key, apply_pack(ui, st, ncmd, halt, more), evt, cmd, ack, gen, frames, k)
    case False{}:
      do IO<Unit>:
        gen2 : U32 <- emit_cmd(evt, cmd, ncmd, gen)
        got : T.Ui & T.UiKeys <- paint_session(ui, st)
        result : (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool <- frame_result(got, st, Some{evt})
        on_frame.final(result, is_key, evt, cmd, ack, gen2, frames, k)

def on_frame.pick(
  redo: Bool,
  ui: T.Ui,
  +st: Sess.Session,
  +ncmd: Sess.NetCmd,
  halt: Bool,
  more: Bool,
  +is_key: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match redo:
    case False{}:
      on_key_cmd(is_key, apply_pack(ui, st, ncmd, halt, more), evt, cmd, ack, gen, frames, k)
    case True{}:
      on_frame.redo(ui, st, ncmd, halt, more, is_key, evt, cmd, ack, gen, frames, k)

def on_frame.check(
  result: (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool,
  +is_key: Bool,
  +redraw: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match result:
    case (packed, hot):
      match packed:
        case (ui, rest):
          match rest:
            case (+st, rest2):
              match rest2:
                case (+ncmd, rest3):
                  match rest3:
                    case (halt, more):
                      on_frame.pick(redraw && hot, ui, st, ncmd, halt, more, is_key, evt, cmd, ack, gen, frames, k)

def on_frame(
  got: T.Ui & T.UiKeys,
  +st: Sess.Session,
  +is_key: Bool,
  +redraw: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    result : (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool <- frame_result(got, st, Some{evt})
    on_frame.check(result, is_key, redraw, evt, cmd, ack, gen, frames, k)

def paint_input(
  ui: T.Ui,
  +st: Sess.Session,
  +is_key: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st)
    on_frame(got, st, is_key, True{}, evt, cmd, ack, gen, frames, k)

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
  on_frame(got, st, False{}, True{}, evt, cmd, ack, gen, frames, k)

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
  do IO<Unit>:
    now_ms : U32 <- Clock.millis()
    on_chunk_go(Sess.step_on_chunk_ms(st, xs, now_ms), ui, evt, cmd, ack, gen, frames, k)

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
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    on_up_go(Sess.session_reconnected(st, ts), ui, evt, cmd, ack, gen, frames, k)

@unsafe
def reconnect_watch(+evt: Chan(Sess.UiMsg), +host: String, +port: U32, +gen: U32) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(2000)
    ok : Bool <- Chan.send(Sess.UiMsg, evt, Sess.Reconnect{host, port, gen})
    return Unit{}

def emit_fail_cmd(
  c: Sess.NetCmd,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +gen: U32
) -> IO(U32):
  match c:
    case Sess.Dial{+host, port, _, _}:
      do IO<U32>:
        dropped : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.Drop{})
        Unit <- IO.spawn(Unit, reconnect_watch(evt, host, port, gen))
        return gen
    case other:
      emit_cmd(evt, cmd, other, gen)

def on_fail_recon(
  recon: Sess.Session & Sess.NetCmd,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match recon:
    case (+st3, recon_cmd):
      do IO<Unit>:
        gen2 : U32 <- emit_fail_cmd(recon_cmd, evt, cmd, gen)
        got : T.Ui & T.UiKeys <- paint_session(ui, st3)
        on_chunk.paint(got, st3, evt, cmd, ack, gen2, frames, k)

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
  on_fail_recon(Sess.session_autoreconnect(st2), ui, evt, cmd, ack, gen, frames, k)

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
    case Sess.Up{}:
      on_up(ui, st, evt, cmd, ack, gen, frames, k)
    case Sess.Eof{}:
      on_fail(ui, st, evt, cmd, ack, gen, frames, "disconnected", k)
    case Sess.NetFail{+msg}:
      on_fail(ui, st, evt, cmd, ack, gen, frames, msg, k)
    case Sess.InitialFail{+msg}:
      shutdown_failed(ui, cmd, ack, msg)

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


def on_typing_tick.pick(
  pair: Sess.Session & Bool,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (+st2, changed):
      match changed:
        case False{}:
          k((ui, st2, gen, False{}))
        case True{}:
          do IO<Unit>:
            got : T.Ui & T.UiKeys <- paint_session(ui, st2)
            on_chunk.paint(got, st2, evt, cmd, ack, gen, frames, k)

def on_typing_tick(
  ui: T.Ui,
  +st: Sess.Session,
  +now_ms: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_typing_tick.pick(Sess.session_expire_typing(st, now_ms), ui, evt, cmd, ack, gen, frames, k)

def on_reconnect.enabled(
  enabled: Bool,
  ui: T.Ui,
  +st: Sess.Session,
  +host: String,
  +port: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match enabled:
    case False{}:
      +st2 = Sess.session_cancel_reconnect(st)
      do IO<Unit>:
        got : T.Ui & T.UiKeys <- paint_session(ui, st2)
        on_chunk.paint(got, st2, evt, cmd, ack, gen, frames, k)
    case True{}:
      do IO<Unit>:
        gen2 : U32 <- emit_cmd(evt, cmd, Sess.Dial{host, port, 0, Cl.nick_of(Sess.session_cl(st))}, gen)
        k((ui, st, gen2, False{}))

def on_reconnect.same(
  same: Bool,
  ui: T.Ui,
  +st: Sess.Session,
  +host: String,
  +port: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match same:
    case False{}:
      k((ui, st, gen, False{}))
    case True{}:
      on_reconnect.enabled(Sess.session_autoreconnect_on(st), ui, st, host, port, evt, cmd, ack, gen, frames, k)

def on_reconnect(
  ui: T.Ui,
  +st: Sess.Session,
  +host: String,
  +port: U32,
  +scheduled_gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_reconnect.same(U32.is_eq(scheduled_gen, gen), ui, st, host, port, evt, cmd, ack, gen, frames, k)

def on_msg_go(
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
    case Sess.UiKey{}:
      paint_input(ui, st, True{}, evt, cmd, ack, gen, frames, k)
    case Sess.Resize{}:
      paint_input(ui, st, False{}, evt, cmd, ack, gen, frames, k)
    case Sess.UiError{+msg}:
      paint_input(ui, Sess.session_error(st, msg), False{}, evt, cmd, ack, gen, frames, k)
    case Sess.TypingTick{now_ms}:
      on_typing_tick(ui, st, now_ms, evt, cmd, ack, gen, frames, k)
    case Sess.Reconnect{+host, port, scheduled_gen}:
      on_reconnect(ui, st, host, port, scheduled_gen, evt, cmd, ack, gen, frames, k)
    case Sess.FromNet{+got, +e}:
      on_from(got, e, ui, st, evt, cmd, ack, gen, frames, Sess.event_current(Sess.FromNet{got, e}, gen), k)

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
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    on_msg_go(m, ui, Sess.session_set_now(st, ts), evt, cmd, ack, gen, frames, k)

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

def live_step.next(
  acc: T.Ui & Sess.Session & U32 & Bool,
  +old_cl: Cl.Client,
  +hist_path: String,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match acc:
    case (ui, +new_st, gen, quit):
      do IO<Unit>:
        Unit <- Hist.maybe_save_history(hist_path, session_endpoint(new_st), old_cl, Sess.session_cl(new_st))
        k((ui, new_st, gen, quit))

def live_step(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +frames: U32,
  quit: Bool,
  +hist_path: String,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match quit:
    case True{}:
      shutdown(ui, cmd, ack, evt, gen, shutdown_waits(Sess.session_net(st)))
    case False{}:
      do IO<Unit>:
        g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
        on_recv(g, ui, st, evt, cmd, ack, gen, frames, nxt => live_step.next(nxt, Sess.session_cl(st), hist_path, k))

def live_go(
  fuel: Nat,
  acc: T.Ui & Sess.Session & U32 & Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  +hist_path: String
) -> IO(Unit):
  match fuel:
    case 0n:
      match acc:
        case (ui, +st, gen, _):
          shutdown(ui, cmd, ack, evt, gen, shutdown_waits(Sess.session_net(st)))
    case 1n+p:
      match acc:
        case (ui, +st, gen, quit):
          live_step(ui, st, evt, cmd, ack, gen, frames, quit, hist_path, nxt => live_go(p, nxt, evt, cmd, ack, frames, hist_path))

@unsafe
def live_idle(
  acc: T.Ui & Sess.Session & U32 & Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  +hist_path: String
) -> IO(Unit):
  match acc:
    case (ui, +st, gen, quit):
      live_step(ui, st, evt, cmd, ack, gen, frames, quit, hist_path, nxt => live_idle(nxt, evt, cmd, ack, frames, hist_path))

def live_boot(zero: Bool, +frames: U32, ui: T.Ui, +st: Sess.Session, +gen: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +hist_path: String) -> IO(Unit):
  match zero:
    case True{}:
      live_idle((ui, st, gen, False{}), evt, cmd, ack, frames, hist_path)
    case False{}:
      live_go(Sess.ticks_of(frames), (ui, st, gen, False{}), evt, cmd, ack, frames, hist_path)

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
    ok : Bool <- Chan.send(Sess.UiMsg, evt, Sess.UiKey{})
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

# A one-second Bend-owned clock tick expires transient typing notices. The UI
# only paints when expiration changes state, so idle ticks do not redraw.
@unsafe
def typing_watch(+evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(1000)
    now_ms : U32 <- Clock.millis()
    _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.TypingTick{now_ms})
    typing_watch(evt)

def watch_start(
  acc: T.Ui & Sess.Session & U32 & Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  tty: T.Tty,
  w: T.Winch,
  +hist_path: String
) -> IO(Unit):
  match acc:
    case (ui, +st, gen, _):
      do IO<Unit>:
        Unit <- IO.spawn(Unit, tty_watch(tty, evt, ack))
        Unit <- IO.spawn(Unit, winch_watch(w, evt))
        Unit <- IO.spawn(Unit, typing_watch(evt))
        live_boot(U32.is_eq(frames, 0), frames, ui, st, gen, evt, cmd, ack, hist_path)

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
  +frames: U32,
  +hist_path: String
) -> IO(Unit):
  match wr:
    case Fail{e}:
      watch_die_tty(e, tty, ui)
    case Done{w}:
      do IO<Unit>:
        got : T.Ui & T.UiKeys <- paint_session(ui, st)
        on_frame(got, st, False{}, True{}, evt, cmd, ack, gen, frames, acc => watch_start(acc, evt, cmd, ack, frames, tty, w, hist_path))

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
  +frames: U32,
  +hist_path: String
) -> IO(Unit):
  match tr:
    case Fail{e}:
      watch_die_win(wr, e, ui)
    case Done{tty}:
      watch_win(wr, tty, ui, st, gen, evt, cmd, ack, frames, hist_path)

def open_tty(
  pair: T.Ui & Result<&1, &1, U32 & String, T.Tty>,
  +st: Sess.Session,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  wr: Result<&1, &1, U32 & String, T.Winch>,
  +hist_path: String
) -> IO(Unit):
  match pair:
    case (ui, tr):
      watch_go(tr, wr, ui, st, gen, evt, cmd, ack, frames, hist_path)

def open_watch(
  ui: T.Ui,
  +st: Sess.Session,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  +hist_path: String
) -> IO(Unit):
  do IO<Unit>:
    wr : Result<&1, &1, U32 & String, T.Winch> <- T.Winch.open()
    pair : T.Ui & Result<&1, &1, U32 & String, T.Tty> <- T.Timui.tty(ui)
    open_tty(pair, st, gen, evt, cmd, ack, frames, wr, hist_path)

def smoke_painted(
  result: (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool,
  k: T.Ui -> Sess.Session -> IO(Unit)
) -> IO(Unit):
  match result:
    case (packed, _):
      match packed:
        case (ui, +st, _, _, _):
          k(ui, st)

@unsafe
def smoke_go(n: Nat, ui: T.Ui, +st: Sess.Session) -> IO(Unit):
  match n:
    case 0n:
      shutdown_finish(ui)
    case 1n+p:
      do IO<Unit>:
        got : T.Ui & T.UiKeys <- paint_session(ui, st)
        result : (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool <- frame_result(got, st, None{})
        smoke_painted(result, u => s => smoke_go(p, u, s))

def smoke(+frames: U32, +cl: Cl.Client, +chan: String, +ts: String) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    smoke_go(Sess.ticks_of(frames), ui, Sess.session_set_now(Sess.session_demo(cl, chan), ts))

def start_ui_go(
  ui: T.Ui,
  +st: Sess.Session,
  +frames: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +hist_path: String
) -> IO(Unit):
  open_watch(ui, st, 1, evt, cmd, ack, frames, hist_path)

@unsafe
def heartbeat_step(ok: Bool, +cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  match ok:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        Unit <- IO.sleep(5000)
        ms : U32 <- Clock.millis()
        nxt : Bool <- Chan.send(Sess.NetCmd, cmd, Sess.Cont{ ("PING :birc_" ++ U32.show(ms)) <> Nil{} })
        heartbeat_step(nxt, cmd)

def heartbeat(+cmd: Chan(Sess.NetCmd)) -> IO(Unit):
  heartbeat_step(True{}, cmd)

def live_client(+cl: Cl.Client, +sasl_user: String, +sasl_pass: String) -> Cl.Client:
  +cl1 = Cl.client_set_sasl(cl, sasl_user, sasl_pass)
  Cl.set_settings(cl1, Cl.set_autoreconn(Cl.get_settings(cl1), True{}))

def start_ui_load(
  +hist_path: String,
  +hist_cap: U32,
  +nick: String,
  +host: String,
  +port: U32,
  +now: String,
  ui: T.Ui,
  +chan: String,
  +frames: U32,
  +sasl_user: String,
  +sasl_pass: String,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  do IO<Unit>:
    cl : Cl.Client <- Hist.history_init_client(hist_path, endpoint(host, port), hist_cap, nick, host, now)
    start_ui_go(ui, Sess.session_with_client_at(live_client(cl, sasl_user, sasl_pass), chan, port), frames, evt, cmd, ack, hist_path)

def start_ui(
  +frames: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +port: U32,
  +chan: String,
  +sasl_user: String,
  +sasl_pass: String
) -> IO(Unit):
  do IO<Unit>:
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    hist_path : String <- Hist.resolve_history_path()
    hist_cap : U32 <- Hist.resolve_history_cap()
    now : String <- Clock.hhmmss()
    Unit <- IO.spawn(Unit, heartbeat(cmd))
    start_ui_load(hist_path, hist_cap, nick, host, port, now, ui, chan, frames, sasl_user, sasl_pass, evt, cmd, ack)

def boot_watch.event(e: Act.Boot, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  match e:
    case Act.Down{+msg}:
      Act.post(evt, gen, Sess.InitialFail{msg})
    case Act.Ready{}:
      IO.pure(Unit, Unit{})

def boot_watch.got(g: Maybe<&1, Act.Boot>, +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  match g:
    case None{}:
      Act.post(evt, gen, Sess.InitialFail{"connect failed"})
    case Some{e}:
      boot_watch.event(e, evt, gen)

# Boot reports only the initial failure policy. Connection progress and
# input use the ordinary UI channel; DNS/connect never gate the first paint.
def boot_watch(+boot: Chan(Act.Boot), +evt: Chan(Sess.UiMsg), +gen: U32) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Act.Boot> <- Chan.recv(Act.Boot, boot)
    Unit <- Chan.close(Act.Boot, boot)
    boot_watch.got(g, evt, gen)

def run_live_on(
  +frames: U32,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +sasl_user: String,
  +sasl_pass: String,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Act.Boot)
) -> IO(Unit):
  +has_sasl = Bool.not(String.is_empty(sasl_user)) && Bool.not(String.is_empty(sasl_pass))
  do IO<Unit>:
    Unit <- IO.spawn(Unit, Act.actor_boot(host, port, nick, 1, evt, cmd, boot, has_sasl, frames))
    Unit <- IO.spawn(Unit, boot_watch(boot, evt, 1))
    start_ui(frames, evt, cmd, nick, host, port, chan, sasl_user, sasl_pass)

def run_live(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String) -> IO(Unit):
  do IO<Unit>:
    evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    run_live_on(frames, host, port, nick, chan, sasl_user, sasl_pass, evt, cmd, boot)

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
    Unit <- IO.spawn(Unit, Act.idle_start(evt, cmd, frames))
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    open_watch(ui, Sess.session_set_now(Sess.session_demo(cl, chan), ts), 0, evt, cmd, ack, frames, "")

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
