# IRC UI loop. Writer owns the Socket and blocks on NetCmd. Reader owns a
# dup and parks in recv_octets. The UI parks on Chan(UiMsg).
import Base
import ./diagnostic.bend as Diagnostic
import ./buffer.bend as Cl
import ./view.bend as V
import ./timui.bend as T
import ./session.bend as Sess
import ./split.bend as Sp
import ./clock.bend as Clock
import ./actor.bend as Act
import ./history.bend as Hist
import ./history_io.bend as HistIO
import ./typing.bend as Ty
import ./media.bend as M
import ./links.bend as Links
import ./args.bend as Args
import ./auth_bridge.bend as AuthBridge
import ./upload.bend as Up
import ./upload_io.bend as UploadIO
import ./view_hint.bend as Hint
import ./live_context.bend as PrefLive
import ./preferences_worker.bend as PrefWorker
import ./startup_headless.bend as Headless
import ./preferences_live.bend as LoadedPrefs

def endpoint(+host: String, +port: U32) -> String:
  host ++ ":" ++ U32.show(port)

def session_endpoint(+st: Sess.Session) -> String:
  endpoint(Cl.server_of(Sess.session_cl(st)), Sess.session_port(st))

def shutdown_exit(success: Bool) -> IO(Unit):
  match success:
    case True{}: T.Sys.exit_done()
    case False{}: T.Sys.exit_fail("birc: preferences were not fully saved (helper failure or timeout)")

def shutdown_finish(ui: T.Ui, success: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- T.Timui.close(ui)
    shutdown_exit(success)

def shutdown_failed(ui: T.Ui, +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +msg: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- Chan.close(Unit, ack)
    Unit <- T.Timui.close(ui)
    T.Sys.exit_fail(msg)

def shutdown_done(same: Bool, ui: T.Ui, success: Bool, k: T.Ui -> IO(Unit)) -> IO(Unit):
  match same:
    case True{}:
      shutdown_finish(ui, success)
    case False{}:
      k(ui)

def shutdown_on(
  g: Maybe<&1, Sess.UiMsg>,
  ui: T.Ui,
  +gen: U32,
  success: Bool,
  k: T.Ui -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      shutdown_finish(ui, success)
    case Some{m}:
      shutdown_done(Sess.writer_done_current(m, gen), ui, success, k)

# Closing cmd lets the writer flush QUIT, close its Socket, and post WriterDone.
# Keep evt open until that acknowledgement; reader EOF and stale events cannot
# acknowledge the writer's pending queue.
@unsafe
def shutdown_wait(ui: T.Ui, +evt: Chan(Sess.UiMsg), +gen: U32, +success: Bool) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    shutdown_on(g, ui, gen, success, u => shutdown_wait(u, evt, gen, success))

# A dial parks inside TCP.connect. Quit must not wait for that SYN.
def shutdown_waits(net: Sess.NetState) -> Bool:
  match net:
    case Sess.Connecting{}:
      False{}
    case Sess.Reconnecting{}:
      False{}
    case _:
      True{}

def shutdown_pick(wait: Bool, ui: T.Ui, +evt: Chan(Sess.UiMsg), +gen: U32, success: Bool) -> IO(Unit):
  match wait:
    case True{}:
      shutdown_wait(ui, evt, gen, success)
    case False{}:
      shutdown_finish(ui, success)

def shutdown(ui: T.Ui, +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +evt: Chan(Sess.UiMsg), +gen: U32, wait: Bool, success: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    Unit <- Chan.close(Unit, ack)
    shutdown_pick(wait, ui, evt, gen, success)

def helper_post(notice: Maybe<&2, Chan(Sess.UiMsg)>, +msg: String) -> IO(Unit):
  match notice:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+evt}:
      do IO<Unit>:
        _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.UiError{msg})
        return Unit{}

def helper_notify(result: Maybe<&2, String>, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match result:
    case None{}: IO.pure(Unit, Unit{})
    case Some{msg}: helper_post(notice, msg)

def frame_clipboard.run(text: String, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  do IO<Unit>:
    result : Maybe<&2, String> <- T.Sys.copy_clipboard(text)
    helper_notify(result, notice)

def frame_clipboard.on(+text: String, empty: Bool, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  match empty:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, frame_clipboard.run(text, notice))
        return Unit{}

def frame_clipboard(+text: String, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  frame_clipboard.on(text, String.is_empty(text), notice)

def paint_vm(ui: T.Ui, +vm: V.ViewModel, +seed: U32) -> IO(T.Ui & T.UiKeys):
  match vm:
    case V.ViewModel{+ops, +inp}:
      T.Timui.frame(ui, ops, inp, seed)

def paint_go.hint(
  ui: T.Ui,
  +cl: Cl.Client,
  +draft: String,
  +net: Sess.NetState,
  +seed: U32,
  size: Sess.Size,
  split: Sp.State,
  +typers: List<&2, String>,
  +media: M.State,
  hint: String
) -> IO(T.Ui & T.UiKeys):
  match size:
    case Sess.Size{+rows, +cols}:
      do IO<T.Ui & T.UiKeys>:
        ui : T.Ui <- T.Timui.view_begin(ui)
        paint_vm(ui, Hint.status(V.view_draft.state_typing_media(cl, rows, cols, draft, Sess.net_label_lag(net, Cl.client_lag(cl)), typers, split, media), rows, cols, hint), seed)

def paint_go(ui: T.Ui, +cl: Cl.Client, +draft: String, +net: Sess.NetState, +seed: U32, size: Sess.Size, split: Sp.State, +typers: List<&2, String>, +media: M.State) -> IO(T.Ui & T.UiKeys):
  paint_go.hint(ui, cl, draft, net, seed, size, split, typers, media, "")

def paint_session.hint(ui: T.Ui, st: Sess.Session, hint: String) -> IO(T.Ui & T.UiKeys):
  match st:
    case Sess.Session{+cl, _, _, +draft, _, _, +net, _, size, seed, _, split, +typing, _, media, _, _}:
      paint_go.hint(ui, cl, draft, net, seed, size, split, Ty.names(typing, Cl.active_buf_name(cl)), media, hint)

def paint_session(ui: T.Ui, +st: Sess.Session) -> IO(T.Ui & T.UiKeys):
  paint_session.hint(ui, st, Sess.session_upload_hint(st))

def emit_outs(chan: Chan(Sess.NetCmd), +outs: List<&2, String>, +gen: U32, empty: Bool) -> IO(U32):
  match empty:
    case True{}:
      IO.pure(U32, gen)
    case False{}:
      do IO<U32>:
        ok : Bool <- Chan.send(Sess.NetCmd, chan, Sess.Cont{outs})
        return gen

def launch_result(r: Result<&1, &1, U32 & String, U32 & (String & String)>, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO(Unit):
  helper_notify(Diagnostic.process_result("cannot open link: opener", r), notice)

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
      emit_outs(chan, outs, gen, List.is_empty(&2, String, outs))
    case Sess.Pump{_}:
      IO.pure(U32, gen)
    case Sess.Begin{_}:
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


# Only the tty watcher's UiKey owns an acknowledgement. Native paste
# continuations are UiContinue, not extra watcher keys.
def ack_key(is_key: Bool, +ack: Chan(Unit)) -> IO(Unit):
  match is_key:
    case True{}:
      do IO<Unit>:
        _ : Bool <- Chan.send(Unit, ack, Unit{})
        return Unit{}
    case False{}:
      IO.pure(Unit, Unit{})

def more_pending(+scheduled: Bool, +consumed: Bool, +more: Bool) -> Bool:
  (scheduled && Bool.not(consumed)) || more

def more_enqueue(+evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.UiContinue{})
    return Unit{}

def more_schedule.go(enqueue: Bool, +pending: Bool, +evt: Chan(Sess.UiMsg)) -> IO(Bool):
  match enqueue:
    case True{}:
      do IO<Bool>:
        # Never send to the UI's own bounded channel from the UI. One
        # scheduled flag bounds both queued and blocked continuations.
        Unit <- IO.spawn(Unit, more_enqueue(evt))
        return pending
    case False{}:
      IO.pure(Bool, pending)

def more_schedule(+scheduled: Bool, +consumed: Bool, +more: Bool, +evt: Chan(Sess.UiMsg)) -> IO(Bool):
  more_schedule.go(more && (Bool.not(scheduled) || consumed), more_pending(scheduled, consumed, more), evt)

def after_emit(
  gen: U32,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  halt: Bool,
  more: Bool,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match halt:
    case True{}:
      k((ui, Sess.session_set_net(st, Sess.Stopping{shutdown_waits(Sess.session_net(st))}), gen, more))
    case False{}:
      k((ui, st, gen, more))

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
                    Unit <- ack_key(is_key, ack)
                    after_emit(gen2, ui, st, evt, cmd, ack, halt, more, k)

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
        Unit <- frame_clipboard(clipboard, notice)
        return (
          apply_pol(ui, st, enter, typed, rows, cols, click, more, Sess.KeyPol{tab, up, dn, hist, quit, comp, focus}),
          pol_hot(tab, click, up, dn, hist, enter, comp, focus) || Bool.not(Sess.size_eq(Sess.session_size(st), Sess.Size{rows, cols}))
        )

def frame_result.restore(packed: T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool, restore: Bool, typed: String) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  match packed:
    case (ui, +st, cmd, halt, more):
      (ui, Bool.pick(Sess.Session, restore, Sess.session_upload_draft(st, typed, 1), st), cmd, halt, more)

def frame_result.hot(result: (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool, +handled: Bool, restore: Bool, typed: String) -> (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool:
  match result:
    case (packed, hot): (frame_result.restore(packed, restore, typed), hot || handled)

def frame_result.upload(pair: Sess.Session & Bool, ui: T.Ui, +enter: Bool, +typed: String, +rows: U32, cols: U32, click: U32, +key: U32, mods: U32, codepoint: U32, wheel: U32, more: Bool, url: String, clipboard: String, notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO((T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool):
  match pair:
    case (+st, +handled):
      do IO<(T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool>:
        result : (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool <- frame_result.pol(ui, st, enter && Bool.not(handled), typed, rows, cols, click, more || handled,
          Sess.key_pol_for(st, Bool.pick(U32, handled, 0, key), mods, Bool.pick(U32, handled, 0, codepoint), wheel, rows), url, clipboard, notice)
        # Apply after ordinary key processing, which resets the input seed.
        # Native Enter already cleared the editor, even when suppressed here.
        return frame_result.hot(result, handled, handled && enter, typed)

def frame_result.keys(ui: T.Ui, +st: Sess.Session, keys: T.UiKeys, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO((T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool):
  match keys:
    case T.UiKeys{enter, +typed, +rows, cols, click, +key, +mods, codepoint, wheel, more, +url, +clipboard}:
      # Authorize only a request that existed before this frame's submission.
      # A coalesced Enter+F8 cannot stage and approve a new public upload.
      frame_result.upload(Sess.session_upload_key(st, key, mods), ui, T.flag_on(enter), typed, rows, cols, click, key, mods, codepoint, wheel, T.flag_on(more), url, clipboard, notice)

def frame_result.present_pack(packed: T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool, before: Sess.Session) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  match packed:
    case (ui, after, cmd, halt, more):
      (ui, Sess.session_upload_present(before, after), cmd, halt, more)

def frame_result.present(result: (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool, before: Sess.Session) -> (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool:
  match result:
    case (packed, hot): (frame_result.present_pack(packed, before), hot)

def frame_result(got: T.Ui & T.UiKeys, +st: Sess.Session, +notice: Maybe<&2, Chan(Sess.UiMsg)>) -> IO((T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool):
  match got:
    case (ui, keys):
      do IO<(T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool>:
        result : (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool <- frame_result.keys(ui, st, keys, notice)
        # Native begin reads keys before drawing. Only a request that existed
        # across this completed frame becomes eligible for a later F8.
        return frame_result.present(result, st)

def on_frame.defer.go(ui: T.Ui, +st: Sess.Session, +ncmd: Sess.NetCmd, +halt: Bool, more: Bool, hot: Bool) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  apply_pack(ui, st, ncmd, halt, more || (hot && Bool.not(halt)))

def on_frame.defer(packed: T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool, hot: Bool) -> T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool:
  match packed:
    case (ui, st, ncmd, halt, more): on_frame.defer.go(ui, st, ncmd, halt, more, hot)

def on_frame.final(
  result: (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool,
  +is_key: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match result:
    case (packed, hot):
      # This frame painted before applying its keys. Defer one fair repaint
      # for its last change, even when native input is now drained.
      on_key_cmd(is_key, on_frame.defer(packed, hot), evt, cmd, ack, gen, k)

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
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match halt:
    case True{}:
      on_key_cmd(is_key, apply_pack(ui, st, ncmd, halt, more), evt, cmd, ack, gen, k)
    case False{}:
      do IO<Unit>:
        gen2 : U32 <- emit_cmd(evt, cmd, ncmd, gen)
        got : T.Ui & T.UiKeys <- paint_session(ui, st)
        result : (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool <- frame_result(got, st, Some{evt})
        on_frame.final(result, is_key, evt, cmd, ack, gen2, k)

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
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match redo:
    case False{}:
      on_key_cmd(is_key, apply_pack(ui, st, ncmd, halt, more), evt, cmd, ack, gen, k)
    case True{}:
      on_frame.redo(ui, st, ncmd, halt, more, is_key, evt, cmd, ack, gen, k)

def on_frame.check(
  result: (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool,
  +is_key: Bool,
  +redraw: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
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
                      on_frame.pick(redraw && hot, ui, st, ncmd, halt, more, is_key, evt, cmd, ack, gen, k)

def on_frame(
  got: T.Ui & T.UiKeys,
  +st: Sess.Session,
  +is_key: Bool,
  +redraw: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    result : (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool <- frame_result(got, st, Some{evt})
    on_frame.check(result, is_key, redraw, evt, cmd, ack, gen, k)

def paint_input(
  ui: T.Ui,
  +st: Sess.Session,
  +is_key: Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st)
    on_frame(got, st, is_key, True{}, evt, cmd, ack, gen, k)

def on_chunk.paint(
  got: T.Ui & T.UiKeys,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_frame(got, st, False{}, True{}, evt, cmd, ack, gen, k)

def on_chunk_go(
  pair: Sess.Session & List<&2, String>,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match pair:
    case (+st2, +outs):
      do IO<Unit>:
        gen2 : U32 <- emit_outs(cmd, outs, gen, List.is_empty(&2, String, outs))
        got : T.Ui & T.UiKeys <- paint_session(ui, st2)
        on_chunk.paint(got, st2, evt, cmd, ack, gen2, k)

def on_chunk.framed(
  framed: List<&2, String> & List<&2, U32> & Bool,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  now_ms: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match framed:
    case (+lines, rem, drop):
      do IO<Unit>:
        stamps : List<&2, Maybe<&2, String>> <- Clock.line_stamps(lines)
        on_chunk_go(Sess.step_on_framed_ms(st, (lines, rem, drop), stamps, now_ms), ui, evt, cmd, ack, gen, k)

def on_chunk(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  xs: List<&2, U32>,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    now_ms : U32 <- Clock.millis()
    on_chunk.framed(Sess.frame_chunk(st, xs), ui, st, evt, cmd, ack, gen, now_ms, k)

def on_up_go(
  +st2: Sess.Session,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & T.UiKeys <- paint_session(ui, st2)
    on_chunk.paint(got, st2, evt, cmd, ack, gen, k)

def on_up(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    on_up_go(Sess.session_reconnected(st, ts), ui, evt, cmd, ack, gen, k)

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
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match recon:
    case (+st3, recon_cmd):
      do IO<Unit>:
        gen2 : U32 <- emit_fail_cmd(recon_cmd, evt, cmd, gen)
        got : T.Ui & T.UiKeys <- paint_session(ui, st3)
        on_chunk.paint(got, st3, evt, cmd, ack, gen2, k)

def on_fail_go(
  +st2: Sess.Session,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_fail_recon(Sess.session_autoreconnect(st2), ui, evt, cmd, ack, gen, k)

def on_fail(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +msg: String,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    on_fail_go(Sess.session_fail(Sess.session_set_now(st, ts), msg), ui, evt, cmd, ack, gen, k)

def on_evt(
  e: Sess.NetEvt,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match e:
    case Sess.Chunk{xs}:
      on_chunk(ui, st, evt, cmd, ack, gen, xs, k)
    case Sess.Up{}:
      on_up(ui, st, evt, cmd, ack, gen, k)
    case Sess.Eof{}:
      on_fail(ui, st, evt, cmd, ack, gen, "disconnected", k)
    case Sess.WriterDone{}:
      k((ui, st, gen, False{}))
    case Sess.NetFail{+msg}:
      on_fail(ui, st, evt, cmd, ack, gen, "disconnected: " ++ msg, k)
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
  same: Bool,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match same:
    case False{}:
      k((ui, st, gen, False{}))
    case True{}:
      on_evt(e, ui, st, evt, cmd, ack, gen, k)


def on_typing_tick.pick(
  pair: Sess.Session & Bool,
  ui: T.Ui,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
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
            on_chunk.paint(got, st2, evt, cmd, ack, gen, k)

def on_typing_tick.retry(pair: Sess.Session & Bool, retry: Bool) -> Sess.Session & Bool:
  match pair:
    case (st, changed): (st, changed || retry)

def on_typing_tick.ready(
  got: T.Ui & U32,
  +st: Sess.Session,
  +now_ms: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match got:
    case (ui, ready):
      on_typing_tick.pick(on_typing_tick.retry(Sess.session_expire_typing(st, now_ms), T.flag_on(ready)), ui, evt, cmd, ack, gen, k)

def on_typing_tick(
  ui: T.Ui,
  +st: Sess.Session,
  +now_ms: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & U32 <- T.Timui.redraw_ready(ui)
    on_typing_tick.ready(got, st, now_ms, evt, cmd, ack, gen, k)

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
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match enabled:
    case False{}:
      +st2 = Sess.session_cancel_reconnect(st)
      do IO<Unit>:
        got : T.Ui & T.UiKeys <- paint_session(ui, st2)
        on_chunk.paint(got, st2, evt, cmd, ack, gen, k)
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
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match same:
    case False{}:
      k((ui, st, gen, False{}))
    case True{}:
      on_reconnect.enabled(Sess.session_autoreconnect_on(st), ui, st, host, port, evt, cmd, ack, gen, k)

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
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  on_reconnect.same(U32.is_eq(scheduled_gen, gen), ui, st, host, port, evt, cmd, ack, gen, k)

# One bounded external worker; only its exact completion can release ownership.
def media_payload(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Fail{_}: ""
    case Done{(code, (out, _))}: Bool.pick(String, U32.is_zero(code), out, "")

def media_args.pick(remote: Bool, source: String) -> List<&1, String>:
  match remote:
    case True{}: [source]
    case False{}: ["--local", source]

def media_args(+source: String) -> List<&1, String>:
  media_args.pick(Links.is_url_prefix(source), source)

def media_run(req: M.Request, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match req:
    case M.Request{_, +url, +generation, +ticket}:
      do IO<Unit>:
        program : String <- T.Sys.media_program()
        result : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run(program, media_args(url), "", 2800000, 11000)
        _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.MediaFetched{generation, ticket, url, media_payload(result)})
        return Unit{}

def media_spawn(job: Maybe<&2, M.Request>, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match job:
    case None{}: IO.pure(Unit, Unit{})
    case Some{req}: IO.spawn(Unit, media_run(req, evt))

def media_clear(changed: Bool, ui: T.Ui) -> IO(T.Ui):
  match changed:
    case True{}: T.Timui.media_clear(ui)
    case False{}: IO.pure(T.Ui, ui)

def media_stage.job(pair: M.State & Maybe<&2, M.Request>, ui: T.Ui, +st: Sess.Session, gen: U32, more: Bool, old_gen: Nat, +evt: Chan(Sess.UiMsg), k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (+media, job):
      do IO<Unit>:
        ui2 : T.Ui <- media_clear(Bool.not(Nat.is_eq(old_gen, M.generation(media))), ui)
        Unit <- media_spawn(job, evt)
        k((ui2, Sess.session_set_media(st, media), gen, more))

def media_stage(acc: T.Ui & Sess.Session & U32 & Bool, old_gen: Nat, +evt: Chan(Sess.UiMsg), k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match acc:
    case (ui, +st, gen, pending):
      # Restored and newly visible chat shares the live request/worker path.
      # Admission is pure; IO starts only after the completed frame/event.
      +observed = Sess.session_observe_visible_media(st)
      do IO<Unit>:
        repaint : Bool <- more_schedule(pending, False{},
          Nat.is_gt(Cl.log_seq_of(Sess.session_cl(observed)), Cl.log_seq_of(Sess.session_cl(st))), evt)
        media_stage.job(M.take_job_allowed(Sess.session_media_job_allowed(observed),
          M.maintain(Sess.session_media(observed), Sess.session_cl(observed))), ui, observed, gen, repaint, old_gen, evt, k)

def upload_run.result(result: String & U32 & U32, request: Up.Request, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match result:
    case (output, error, http_status):
      do IO<Unit>:
        _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.UploadFetched{request, output, error, http_status})
        return Unit{}

def upload_run(+request: Up.Request, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    result : String & U32 & U32 <- UploadIO.run_detail(Up.request_path(request))
    upload_run.result(result, request, evt)

def upload_spawn(job: Maybe<&2, Up.Request>, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match job:
    case None{}: IO.pure(Unit, Unit{})
    case Some{request}: IO.spawn(Unit, upload_run(request, evt))

def upload_stage.job(pair: Sess.Session & Maybe<&2, Up.Request>, ui: T.Ui, gen: U32, more: Bool, +evt: Chan(Sess.UiMsg), k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (st, job):
      do IO<Unit>:
        Unit <- upload_spawn(job, evt)
        k((ui, st, gen, more))

# Run after every event, even when it does not paint. Scope invalidation is
# permanent; returning to an old endpoint or target never restores consent.
def upload_stage(acc: T.Ui & Sess.Session & U32 & Bool, +evt: Chan(Sess.UiMsg), k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match acc:
    case (ui, +st, gen, more):
      upload_stage.job(Sess.session_upload_take(st), ui, gen, more, evt, k)

def upload_owned(state: Up.State, request: Up.Request) -> Bool:
  match state:
    case Up.Busy{active, _, _}: Up.request_eq(active, request)
    case _: False{}

def on_upload.sent(pair: Cl.Client & String & Sess.NetCmd, ui: T.Ui, +st: Sess.Session, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +gen: U32, k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (cl, _, ncmd):
      +next = Sess.session_observe_media(Sess.session_set_client(st, cl), Cl.log_seq_of(Sess.session_cl(st)))
      do IO<Unit>:
        gen2 : U32 <- emit_cmd(evt, cmd, ncmd, gen)
        paint_input(ui, next, False{}, evt, cmd, ack, gen2, k)

def on_upload.url(fits: Bool, ui: T.Ui, +st: Sess.Session, url: String, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +gen: U32, k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match fits:
    case False{}: paint_input(ui, Sess.session_error(st, "upload URL exceeds IRC message limit"), False{}, evt, cmd, ack, gen, k)
    case True{}:
      # Submit the validated URL through the ordinary echo/wire path. Keep
      # the real draft and composer history; the helper is not a keystroke.
      on_upload.sent(Sess.apply_keys(Sess.session_cl(st), Sess.session_net(st), Sess.session_port(st), url, True{}), ui, st, evt, cmd, ack, gen, k)

def on_upload.completed(pair: Sess.Session & Maybe<&2, String>, ui: T.Ui, request: Up.Request, allowed: Bool, +error: U32, http_status: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +gen: U32, k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (+st, result):
      match result:
        case Some{+url}: on_upload.url(Up.wire_fits(request, url), ui, st, url, evt, cmd, ack, gen, k)
        case None{}:
          +msg = Bool.pick(String, Bool.not(allowed), "upload result discarded: canceled or destination changed",
            Bool.pick(String, U32.is_zero(error), "upload returned an invalid URL", UploadIO.error_text(error, http_status)))
          paint_input(ui, Sess.session_error(st, msg), False{}, evt, cmd, ack, gen, k)

def on_upload(owned: Bool, ui: T.Ui, +st: Sess.Session, +request: Up.Request, result: String, error: U32, http_status: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +gen: U32, k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match owned:
    case False{}: k((ui, st, gen, False{}))
    case True{}:
      on_upload.completed(Sess.session_upload_complete(st, request, result), ui, request,
        Up.eligible(Sess.session_upload(st), request, Sess.session_upload_scope(st), Sess.session_upload_online(st)), error, http_status, evt, cmd, ack, gen, k)

def on_media.added(pair: T.Ui & U32, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +gen: U32, k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (ui, +token):
      +media = M.complete(Sess.session_media(st), Sess.session_cl(st), generation, ticket, url, token)
      +next = Sess.session_set_media(st, media)
      paint_input(ui, Bool.pick(Sess.Session, U32.is_zero(token), Sess.session_error(next, "image preview unavailable"), next), False{}, evt, cmd, ack, gen, k)

def on_media(accepted: Bool, ui: T.Ui, +st: Sess.Session, +generation: Nat, +ticket: Nat, +url: String, payload: String, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +gen: U32, k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match accepted:
    case False{}:
      k((ui, Sess.session_set_media(st, M.reject(Sess.session_media(st), generation, ticket, url)), gen, False{}))
    case True{}:
      do IO<Unit>:
        pair : T.Ui & U32 <- T.Timui.media_add(ui, payload,
          M.retained_tokens(M.complete(Sess.session_media(st), Sess.session_cl(st), generation, ticket, url, 0)))
        on_media.added(pair, st, generation, ticket, url, evt, cmd, ack, gen, k)

def images_enabled.got(result: Result<&1, &1, U32 & String, String>) -> Bool:
  match result:
    case Fail{_}: True{}
    case Done{value}: Bool.not(String.eq(value, "off"))

def images_enabled() -> IO(Bool):
  do IO<Bool>:
    result : Result<&1, &1, U32 & String, String> <- IO.get_env("BIRC_IMAGES")
    return images_enabled.got(result)

def on_msg_go(
  m: Sess.UiMsg,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match m:
    case Sess.UiKey{}:
      paint_input(ui, st, True{}, evt, cmd, ack, gen, k)
    case Sess.UiContinue{}:
      paint_input(ui, st, False{}, evt, cmd, ack, gen, k)
    case Sess.Resize{}:
      paint_input(ui, st, False{}, evt, cmd, ack, gen, k)
    case Sess.UiError{+msg}:
      paint_input(ui, Sess.session_error(st, msg), False{}, evt, cmd, ack, gen, k)
    case Sess.TypingTick{now_ms}:
      on_typing_tick(ui, st, now_ms, evt, cmd, ack, gen, k)
    case Sess.Reconnect{+host, port, scheduled_gen}:
      on_reconnect(ui, st, host, port, scheduled_gen, evt, cmd, ack, gen, k)
    case Sess.MediaFetched{+generation, +ticket, +url, payload}:
      on_media(Sess.session_accept_media_result(st, generation, ticket, url), ui, st, generation, ticket, url, payload, evt, cmd, ack, gen, k)
    # C8-SESSION-ADAPTER: pass-through until the parent merge threads the
    # cards adapter state through the loop; then route to CardsNet.on_card.
    case Sess.CardFetched{_, _, _, _}: k((ui, st, gen, False{}))
    case Sess.UploadFetched{+request, result, error, http_status}:
      on_upload(upload_owned(Sess.session_upload(st), request), ui, st, request, result, error, http_status, evt, cmd, ack, gen, k)
    case Sess.PreferencesLoaded{_, _, _}: k((ui, st, gen, False{}))
    case Sess.PreferencesSaved{_, _}: k((ui, st, gen, False{}))
    case Sess.PreferencesDeadline{_}: k((ui, st, gen, False{}))
    case Sess.HistoryLoaded{_, _, _, _}: k((ui, st, gen, False{}))
    case Sess.FromNet{+got, +e}:
      on_from(got, e, ui, st, evt, cmd, ack, gen, Sess.event_current(Sess.FromNet{got, e}, gen), k)

def on_msg(
  m: Sess.UiMsg,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    on_msg_go(m, ui, Sess.session_set_now(st, ts), evt, cmd, ack, gen, k)

def live_step.reload(
  changed: Bool,
  ui: T.Ui,
  +st: Sess.Session,
  +gen: U32,
  +pending: Bool,
  +hist_path: String,
  +new_endpoint: String,
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match changed:
    case False{}:
      k((ui, st, gen, pending))
    case True{}:
      do IO<Unit>:
        loaded : Cl.Client <- Hist.history_load_client(hist_path, new_endpoint, Cl.settings_hist_cap(Cl.get_settings(Sess.session_cl(st))), Sess.session_cl(st))
        k((ui, Sess.session_set_client(st, loaded), gen, pending))

def history_notice(+st: Sess.Session, notice: Maybe<&2, String>) -> Sess.Session & Bool:
  match notice:
    case None{}: (st, False{})
    case Some{msg}:
      (Sess.session_set_client(st, Cl.diagnostic(Sess.session_cl(st), Cl.Error{}, msg)), True{})

def auth_notice(+st: Sess.Session, code: U32) -> Sess.Session:
  match code:
    case 0: st
    case _:
      Sess.session_set_client(st, Cl.diagnostic(Sess.session_cl(st), Cl.Error{},
        "authentication notification failed (code: " ++ U32.show(code) ++ ")"))

def live_step.saved(
  status: Sess.Session & Bool,
  ui: T.Ui,
  gen: U32,
  more: Bool,
  scheduled: Bool,
  consumed: Bool,
  old_endpoint: String,
  old_media_gen: Nat,
  +hist_path: String,
  +new_endpoint: String,
  allowed: Bool,
  +evt: Chan(Sess.UiMsg),
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match status:
    case (+st, failed):
      do IO<Unit>:
        pending : Bool <- more_schedule(scheduled, consumed, more || failed, evt)
        live_step.reload(allowed && Bool.not(String.eq(old_endpoint, new_endpoint)), ui, st, gen, pending, hist_path, new_endpoint, next => media_stage(next, old_media_gen, evt, after => upload_stage(after, evt, k)))

def live_step.next(
  acc: T.Ui & Sess.Session & U32 & Bool,
  +scheduled: Bool,
  +consumed: Bool,
  +old_cl: Cl.Client,
  +old_endpoint: String,
  +old_media_gen: Nat,
  +hist_path: String,
  +ctx: PrefLive.Context,
  +evt: Chan(Sess.UiMsg),
  k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)
) -> IO(Unit):
  match acc:
    case (ui, +new_st, gen, more):
      +new_endpoint = session_endpoint(new_st)
      +allowed = PrefLive.history_allowed(ctx, new_st)
      do IO<Unit>:
        +auth_code : U32 <- AuthBridge.observed(String.eq(old_endpoint, new_endpoint)
          && Nat.is_gt(Cl.auth_success_seq(Sess.session_cl(new_st)), Cl.auth_success_seq(old_cl)))
        +observed_st : Sess.Session <- IO.pure(Sess.Session, auth_notice(new_st, auth_code))
        # Save only the current event. Imported rows get fresh IDs and must
        # become the next baseline, never part of this append comparison.
        notice : Maybe<&2, String> <- HistIO.maybe_save_history.check(allowed && Cl.settings_history(Cl.get_settings(Sess.session_cl(observed_st))), hist_path, new_endpoint, old_cl, Sess.session_cl(observed_st))
        # A save failure belongs only in the non-persisted diagnostic buffer.
        # Repaint through the existing coalesced continuation, never UiError:
        # saving an Error chat row would recursively fail and notify again.
        live_step.saved(history_notice(observed_st, notice), ui, gen, more || Bool.not(U32.is_zero(auth_code)), scheduled, consumed, old_endpoint, old_media_gen, hist_path, new_endpoint, allowed, evt, k)

def is_continue(m: Sess.UiMsg) -> Bool:
  match m:
    case Sess.UiContinue{}: True{}
    case _: False{}

def preferences_exit.drained(result: Sess.Session & Bool, ui: T.Ui, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), gen: U32, wait: Bool) -> IO(Unit):
  match result:
    case (_, success): shutdown(ui, cmd, ack, evt, gen, wait, success)

def preferences_exit(ctx: PrefLive.Context, ui: T.Ui, st: Sess.Session, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +gen: U32, +wait: Bool) -> IO(Unit):
  do IO<Unit>:
    result : Sess.Session & Bool <- PrefLive.drain(ctx, st, evt, gen)
    preferences_exit.drained(result, ui, evt, cmd, ack, gen, wait)

def preferences_stage.stopping(stop: Maybe<&2, Bool>, ctx: PrefLive.Context, ui: T.Ui, st: Sess.Session, +gen: U32, more: Bool, +evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), k: ((T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context) -> IO(Unit)) -> IO(Unit):
  match stop:
    case Some{wait}: preferences_exit(ctx, ui, st, evt, cmd, ack, gen, wait)
    case None{}:
      do IO<Unit>:
        next : PrefLive.Context <- PrefLive.start(ctx, evt)
        k(((ui, st, gen, more), next))

def preferences_stage.observed(pair: PrefLive.Context & Sess.Session, ui: T.Ui, +gen: U32, more: Bool, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), k: ((T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context) -> IO(Unit)) -> IO(Unit):
  match pair:
    case (ctx, +st): preferences_stage.stopping(Sess.session_stopping(st), ctx, ui, st, gen, more, evt, cmd, ack, k)

def preferences_stage(acc: T.Ui & Sess.Session & U32 & Bool, ctx: PrefLive.Context, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), k: ((T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context) -> IO(Unit)) -> IO(Unit):
  match acc:
    case (ui, +st, +gen, more): preferences_stage.observed(PrefLive.observe(ctx, st, gen), ui, gen, more, evt, cmd, ack, k)

def preferences_message.painted(paint: Bool, ui: T.Ui, st: Sess.Session, gen: U32, +evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), k: (T.Ui & Sess.Session & U32 & Bool) -> IO(Unit)) -> IO(Unit):
  match paint:
    case False{}: k((ui, st, gen, False{}))
    case True{}: paint_input(ui, st, False{}, evt, cmd, ack, gen, k)

def preferences_message.result(result: PrefLive.Context & Sess.Session & List<&2, String> & Bool, ui: T.Ui, +gen: U32, +scheduled: Bool, old_cl: Cl.Client, old_endpoint: String, old_media_gen: Nat, hist_path: String, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), k: ((T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context) -> IO(Unit)) -> IO(Unit):
  match result:
    case (+ctx, +st, outs, paint):
      do IO<Unit>:
        emitted : U32 <- emit_cmd(evt, cmd, Sess.Cont{outs}, gen)
        preferences_message.painted(paint, ui, st, emitted, evt, cmd, ack,
          acc => live_step.next(acc, scheduled, False{}, old_cl, old_endpoint, old_media_gen, hist_path, ctx, evt,
            next => preferences_stage(next, ctx, evt, cmd, ack, k)))

def history_message.result(result: PrefLive.Context & Sess.Session, ui: T.Ui, +gen: U32, +scheduled: Bool, hist_path: String, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), k: ((T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context) -> IO(Unit)) -> IO(Unit):
  match result:
    case (+ctx, +st):
      # Install the archive checkpoint BEFORE this paint reads more input.
      # Imports are not new events; commands read by this paint still are.
      preferences_message.painted(True{}, ui, st, gen, evt, cmd, ack,
        acc => live_step.next(acc, scheduled, False{}, Sess.session_cl(st), session_endpoint(st), M.generation(Sess.session_media(st)), hist_path, ctx, evt,
          next => preferences_stage(next, ctx, evt, cmd, ack, k)))

def live_step.dispatch(+m: Sess.UiMsg, ui: T.Ui, +st: Sess.Session, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +gen: U32, +scheduled: Bool, +hist_path: String, +ctx: PrefLive.Context, k: ((T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context) -> IO(Unit)) -> IO(Unit):
  match m:
    case Sess.PreferencesLoaded{ticket, prefs, code}:
      preferences_message.result(PrefLive.loaded(ctx, st, gen, ticket, prefs, code), ui, gen, scheduled, Sess.session_cl(st), session_endpoint(st), M.generation(Sess.session_media(st)), hist_path, evt, cmd, ack, k)
    case Sess.PreferencesSaved{ticket, code}:
      preferences_message.result(PrefLive.saved(ctx, st, ticket, code), ui, gen, scheduled, Sess.session_cl(st), session_endpoint(st), M.generation(Sess.session_media(st)), hist_path, evt, cmd, ack, k)
    case Sess.HistoryLoaded{ticket, got_gen, ep, snapshot}:
      do IO<Unit>:
        result : PrefLive.Context & Sess.Session <- PrefLive.history(ctx, st, gen, got_gen, ticket, ep, snapshot, cmd)
        history_message.result(result, ui, gen, scheduled, hist_path, evt, cmd, ack, k)
    case _:
      on_msg(m, ui, st, evt, cmd, ack, gen, nxt => live_step.next(nxt, scheduled, is_continue(m), Sess.session_cl(st), session_endpoint(st), M.generation(Sess.session_media(st)), hist_path, ctx, evt, next => preferences_stage(next, ctx, evt, cmd, ack, k)))

# Frame callbacks return `more`; the loop stores whether a single
# continuation is outstanding. Other paints can consume input but cannot
# add another continuation until that one reaches the head of the queue.
def live_step.recv(
  g: Maybe<&1, Sess.UiMsg>,
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +scheduled: Bool,
  +hist_path: String,
  +ctx: PrefLive.Context,
  k: ((T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context) -> IO(Unit)
) -> IO(Unit):
  match g:
    case None{}:
      preferences_exit(ctx, ui, st, evt, cmd, ack, gen, shutdown_waits(Sess.session_net(st)))
    case Some{+m}:
      live_step.dispatch(m, ui, st, evt, cmd, ack, gen, scheduled, hist_path, ctx, k)

def live_step(
  ui: T.Ui,
  +st: Sess.Session,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +gen: U32,
  +scheduled: Bool,
  +hist_path: String,
  +ctx: PrefLive.Context,
  k: ((T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context) -> IO(Unit)
) -> IO(Unit):
  do IO<Unit>:
    g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    live_step.recv(g, ui, st, evt, cmd, ack, gen, scheduled, hist_path, ctx, k)

def live_go(
  fuel: Nat,
  acc: (T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +hist_path: String
) -> IO(Unit):
  match fuel:
    case 0n:
      match acc:
        case ((ui, +st, gen, _), ctx):
          preferences_exit(ctx, ui, st, evt, cmd, ack, gen, shutdown_waits(Sess.session_net(st)))
    case 1n+p:
      match acc:
        case ((ui, +st, gen, scheduled), ctx):
          live_step(ui, st, evt, cmd, ack, gen, scheduled, hist_path, ctx, nxt => live_go(p, nxt, evt, cmd, ack, hist_path))

@unsafe
def live_idle(
  acc: (T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +hist_path: String
) -> IO(Unit):
  match acc:
    case ((ui, +st, gen, scheduled), ctx):
      live_step(ui, st, evt, cmd, ack, gen, scheduled, hist_path, ctx, nxt => live_idle(nxt, evt, cmd, ack, hist_path))

def live_boot(zero: Bool, +frames: U32, ui: T.Ui, +st: Sess.Session, +gen: U32, +scheduled: Bool, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +ack: Chan(Unit), +hist_path: String, ctx: PrefLive.Context) -> IO(Unit):
  match zero:
    case True{}:
      live_idle(((ui, st, gen, scheduled), ctx), evt, cmd, ack, hist_path)
    case False{}:
      live_go(Sess.ticks_of(frames), ((ui, st, gen, scheduled), ctx), evt, cmd, ack, hist_path)

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

# A one-second Bend-owned tick expires typing and repairs short frames or
# timed input read by a non-key paint before the tty watcher observed it.
# Failed output waits for a writable tick, never a hot input continuation.
# Normal idle ticks do not repaint.
@unsafe
def typing_watch(+evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(1000)
    now_ms : U32 <- Clock.millis()
    _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.TypingTick{now_ms})
    typing_watch(evt)

def watch_start.boot(pair: (T.Ui & Sess.Session & U32 & Bool) & PrefLive.Context, +frames: U32, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), hist_path: String) -> IO(Unit):
  match pair:
    case ((ui, st, gen, scheduled), ctx):
      live_boot(U32.is_eq(frames, 0), frames, ui, st, gen, scheduled, evt, cmd, ack, hist_path, ctx)

def watch_start(
  acc: T.Ui & Sess.Session & U32 & Bool,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  tty: T.Tty,
  w: T.Winch,
  +hist_path: String,
  +ctx: PrefLive.Context
) -> IO(Unit):
  match acc:
    case (ui, +st, gen, more):
      do IO<Unit>:
        Unit <- IO.spawn(Unit, tty_watch(tty, evt, ack))
        Unit <- IO.spawn(Unit, winch_watch(w, evt))
        Unit <- IO.spawn(Unit, typing_watch(evt))
        scheduled : Bool <- more_schedule(False{}, False{}, more, evt)
        media_stage((ui, st, gen, scheduled), M.generation(Sess.session_media(st)), evt,
          observed => preferences_stage(observed, ctx, evt, cmd, ack,
            next => watch_start.boot(next, frames, evt, cmd, ack, hist_path)))

def watch_die(e: U32 & String, ui: T.Ui) -> IO(Unit):
  match e:
    case (_, +msg):
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        T.Sys.exit_fail(msg)

def watch_die_tty(e: U32 & String, tty: T.Tty, ui: T.Ui) -> IO(Unit):
  match e:
    case (_, +msg):
      do IO<Unit>:
        Unit <- T.Tty.close(tty)
        Unit <- T.Timui.close(ui)
        T.Sys.exit_fail(msg)

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
  +hist_path: String,
  +ctx: PrefLive.Context
) -> IO(Unit):
  match wr:
    case Fail{e}:
      watch_die_tty(e, tty, ui)
    case Done{w}:
      do IO<Unit>:
        got : T.Ui & T.UiKeys <- paint_session(ui, st)
        on_frame(got, st, False{}, True{}, evt, cmd, ack, gen, acc => watch_start(acc, evt, cmd, ack, frames, tty, w, hist_path, ctx))

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
  +hist_path: String,
  ctx: PrefLive.Context
) -> IO(Unit):
  match tr:
    case Fail{e}:
      watch_die_win(wr, e, ui)
    case Done{tty}:
      watch_win(wr, tty, ui, st, gen, evt, cmd, ack, frames, hist_path, ctx)

def open_tty(
  pair: T.Ui & Result<&1, &1, U32 & String, T.Tty>,
  +st: Sess.Session,
  +gen: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit),
  +frames: U32,
  wr: Result<&1, &1, U32 & String, T.Winch>,
  +hist_path: String,
  ctx: PrefLive.Context
) -> IO(Unit):
  match pair:
    case (ui, tr):
      watch_go(tr, wr, ui, st, gen, evt, cmd, ack, frames, hist_path, ctx)

def open_watch.supported(support: T.Ui & U32, +st: Sess.Session, +gen: U32, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), frames: U32, hist_path: String, +ctx: PrefLive.Context) -> IO(Unit):
  match support:
    case (ui, flag):
      +configured = Sess.session_set_media(st, M.set_supported(Sess.session_media(st), T.flag_on(flag)))
      do IO<Unit>:
        wr : Result<&1, &1, U32 & String, T.Winch> <- T.Winch.open()
        pair : T.Ui & Result<&1, &1, U32 & String, T.Tty> <- T.Timui.tty(ui)
        open_tty(pair, PrefLive.hold(PrefLive.waiting(ctx), configured), gen, evt, cmd, ack, frames, wr, hist_path, ctx)

def open_watch.context(ui: T.Ui, +st: Sess.Session, +gen: U32, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), frames: U32, hist_path: String, +ctx: PrefLive.Context) -> IO(Unit):
  do IO<Unit>:
    support : T.Ui & U32 <- T.Timui.image_supported(ui)
    open_watch.supported(support, st, gen, evt, cmd, ack, frames, hist_path, ctx)

def open_watch.ready(options: PrefWorker.Options, ui: T.Ui, +st: Sess.Session, +gen: U32, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), ack: Chan(Unit), frames: U32, +hist_path: String) -> IO(Unit):
  open_watch.context(ui, st, gen, evt, cmd, ack, frames, hist_path, PrefLive.initial(options, st, gen, hist_path))

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
    options : PrefWorker.Options <- PrefWorker.options()
    open_watch.ready(options, ui, st, gen, evt, cmd, ack, frames, hist_path)

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
      shutdown_finish(ui, True{})
    case 1n+p:
      do IO<Unit>:
        got : T.Ui & T.UiKeys <- paint_session(ui, st)
        result : (T.Ui & Sess.Session & Sess.NetCmd & Bool & Bool) & Bool <- frame_result(got, st, None{})
        smoke_painted(result, u => s => smoke_go(p, u, s))

def smoke(+frames: U32, +cl: Cl.Client, +chan: String, +ts: String, port: U32) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    smoke_go(Sess.ticks_of(frames), ui, Sess.session_set_now(Sess.session_demo_at(cl, chan, port), ts))

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

def live_client(+cl: Cl.Client, +host: String, +port: U32, +sasl_user: String, +sasl_pass: String, auth: Args.AuthOptions) -> Cl.Client:
  match auth:
    case Args.AuthOptions{mode, prefix, success}:
      +cl1 = Cl.client_set_auth(cl, mode, host, port, prefix, success, sasl_user, sasl_pass)
      Cl.set_settings(cl1, Cl.set_autoreconn(Cl.get_settings(cl1), True{}))

def start_ui_client(gated: Bool, +path: String, +ep: String, +cap: U32, +nick: String, +host: String, +now: String) -> IO(Cl.Client):
  match gated:
    case True{}: IO.pure(Cl.Client, Cl.set_now(Cl.init_with_cap(nick, host, cap), now))
    case False{}: Hist.history_init_client(path, ep, cap, nick, host, now)

def start_ui_load(
  gated: Bool,
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
  +auth: Args.AuthOptions,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +ack: Chan(Unit)
) -> IO(Unit):
  do IO<Unit>:
    cl : Cl.Client <- start_ui_client(gated, hist_path, endpoint(host, port), hist_cap, nick, host, now)
    on : Bool <- images_enabled()
    start_ui_go(ui, Sess.session_set_media(Sess.session_with_client_at(live_client(cl, host, port, sasl_user, sasl_pass, auth), chan, port), M.initial(on)), frames, evt, cmd, ack, hist_path)

def start_ui(
  gated: Bool,
  +frames: U32,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +nick: String,
  +host: String,
  +port: U32,
  +chan: String,
  +sasl_user: String,
  +sasl_pass: String,
  +auth: Args.AuthOptions
) -> IO(Unit):
  do IO<Unit>:
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    hist_path : String <- Hist.resolve_history_path()
    hist_cap : U32 <- Hist.resolve_history_cap()
    now : String <- Clock.hhmmss()
    Unit <- IO.spawn(Unit, heartbeat(cmd))
    start_ui_load(gated, hist_path, hist_cap, nick, host, port, now, ui, chan, frames, sasl_user, sasl_pass, auth, evt, cmd, ack)

def start_ui_prepared(st: Sess.Session, ctx: PrefLive.Context, frames: U32, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), hist_path: String) -> IO(Unit):
  do IO<Unit>:
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    Unit <- IO.spawn(Unit, heartbeat(cmd))
    open_watch.context(ui, st, 1, evt, cmd, ack, frames, hist_path, ctx)

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

def boot_headless.fail(+cmd: Chan(Sess.NetCmd), +msg: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, cmd)
    T.Sys.exit_fail(msg)

def boot_headless(g: Maybe<&1, Act.Boot>, +cmd: Chan(Sess.NetCmd), start: Unit -> IO(Unit)) -> IO(Unit):
  match g:
    case None{}:
      boot_headless.fail(cmd, "connect failed")
    case Some{e}:
      match e:
        case Act.Down{+msg}:
          boot_headless.fail(cmd, msg)
        case Act.Ready{}:
          start(Unit{})

# Interactive startup paints immediately. Headless EOF instead waits for
# the bounded boot result: it must not report success before registration
# or suppress an initial connection failure.
def run_live_start(headless: Bool, +boot: Chan(Act.Boot), +cmd: Chan(Sess.NetCmd), +evt: Chan(Sess.UiMsg), start: Unit -> IO(Unit)) -> IO(Unit):
  match headless:
    case True{}:
      do IO<Unit>:
        g : Maybe<&1, Act.Boot> <- Chan.recv(Act.Boot, boot)
        Unit <- Chan.close(Act.Boot, boot)
        boot_headless(g, cmd, start)
    case False{}:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, boot_watch(boot, evt, 1))
        start(Unit{})

def run_live_legacy(
  +frames: U32,
  +host: String,
  +port: U32,
  +nick: String,
  +chan: String,
  +sasl_user: String,
  +sasl_pass: String,
  +auth: Args.AuthOptions,
  +evt: Chan(Sess.UiMsg),
  +cmd: Chan(Sess.NetCmd),
  +boot: Chan(Act.Boot),
  +force_tls: Bool
) -> IO(Unit):
  +has_sasl = Cl.client_has_sasl(live_client(Cl.init(nick, host), host, port, sasl_user, sasl_pass, auth))
  do IO<Unit>:
    Unit <- IO.spawn(Unit, Act.actor_boot_tls(host, port, nick, 1, evt, cmd, boot, has_sasl, frames, force_tls))
    tty : U32 <- T.Timui.isatty()
    run_live_start(U32.is_eq(tty, 0), boot, cmd, evt, _ => start_ui(False{}, frames, evt, cmd, nick, host, port, chan, sasl_user, sasl_pass, auth))

def run_live_prepared.result(result: LoadedPrefs.Context & Sess.Session & Bool, +path: String, +frames: U32, +host: String, +port: U32, +nick: String, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Act.Boot), force_tls: Bool) -> IO(Unit):
  match result:
    case (prefs, +st, known):
      +ctx = PrefLive.prepared(prefs, path, known)
      do IO<Unit>:
        Unit <- IO.spawn(Unit, Act.actor_boot_tls(host, port, nick, 1, evt, cmd, boot, Cl.client_has_sasl(Sess.session_cl(st)), frames, force_tls))
        run_live_start(True{}, boot, cmd, evt, _ => start_ui_prepared(st, ctx, frames, evt, cmd, path))

def run_live_prepared(options: PrefWorker.Options, +frames: U32, +host: String, +port: U32, +nick: String, chan: String, sasl_user: String, sasl_pass: String, auth: Args.AuthOptions, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Act.Boot), force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    +path : String <- Hist.resolve_history_path()
    +cap : U32 <- Hist.resolve_history_cap()
    +now : String <- Clock.hhmmss()
    on : Bool <- images_enabled()
    result : LoadedPrefs.Context & Sess.Session & Bool <- Headless.prepare(options,
      Sess.session_set_media(Sess.session_with_client_at(live_client(Cl.set_now(Cl.init_with_cap(nick, host, cap), now), host, port, sasl_user, sasl_pass, auth), chan, port), M.initial(on)), 1, path)
    run_live_prepared.result(result, path, frames, host, port, nick, evt, cmd, boot, force_tls)

def run_live_interactive(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String, +auth: Args.AuthOptions, +evt: Chan(Sess.UiMsg), +cmd: Chan(Sess.NetCmd), +boot: Chan(Act.Boot), force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.spawn(Unit, Act.deferred_start_tls(host, port, nick, evt, cmd, boot,
      Cl.client_has_sasl(live_client(Cl.init(nick, host), host, port, sasl_user, sasl_pass, auth)), frames, force_tls))
    run_live_start(False{}, boot, cmd, evt, _ => start_ui(True{}, frames, evt, cmd, nick, host, port, chan, sasl_user, sasl_pass, auth))

def run_live_settings(headless: Bool, options: PrefWorker.Options, frames: U32, host: String, port: U32, nick: String, chan: String, sasl_user: String, sasl_pass: String, auth: Args.AuthOptions, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), boot: Chan(Act.Boot), force_tls: Bool) -> IO(Unit):
  match headless:
    case True{}: run_live_prepared(options, frames, host, port, nick, chan, sasl_user, sasl_pass, auth, evt, cmd, boot, force_tls)
    case False{}: run_live_interactive(frames, host, port, nick, chan, sasl_user, sasl_pass, auth, evt, cmd, boot, force_tls)

def run_live_policy(options: PrefWorker.Options, tty: U32, frames: U32, host: String, port: U32, nick: String, chan: String, sasl_user: String, sasl_pass: String, auth: Args.AuthOptions, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), boot: Chan(Act.Boot), force_tls: Bool) -> IO(Unit):
  match options:
    case PrefWorker.Options{False{}, _, _, _}: run_live_legacy(frames, host, port, nick, chan, sasl_user, sasl_pass, auth, evt, cmd, boot, force_tls)
    case PrefWorker.Options{True{}, explicit, images, cap}: run_live_settings(U32.is_zero(tty), PrefWorker.Options{True{}, explicit, images, cap}, frames, host, port, nick, chan, sasl_user, sasl_pass, auth, evt, cmd, boot, force_tls)

def run_live_on(frames: U32, host: String, port: U32, nick: String, chan: String, sasl_user: String, sasl_pass: String, auth: Args.AuthOptions, evt: Chan(Sess.UiMsg), cmd: Chan(Sess.NetCmd), boot: Chan(Act.Boot), force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    options : PrefWorker.Options <- PrefWorker.options()
    tty : U32 <- T.Timui.isatty()
    run_live_policy(options, tty, frames, host, port, nick, chan, sasl_user, sasl_pass, auth, evt, cmd, boot, force_tls)

def run_live(+frames: U32, +host: String, +port: U32, +nick: String, +chan: String, +sasl_user: String, +sasl_pass: String, +auth: Args.AuthOptions, +force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    cmd : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    boot : Chan(Act.Boot) <- Chan.new(Act.Boot, 1)
    run_live_on(frames, host, port, nick, chan, sasl_user, sasl_pass, auth, evt, cmd, boot, force_tls)

def run_demo_go(
  evt0: Chan(Sess.UiMsg),
  cmd0: Chan(Sess.NetCmd),
  ack: Chan(Unit),
  +frames: U32,
  +cl: Cl.Client,
  +chan: String,
  +ts: String,
  port: U32,
  force_tls: Bool
) -> IO(Unit):
  +evt = evt0
  +cmd = cmd0
  do IO<Unit>:
    Unit <- IO.spawn(Unit, Act.idle_start_tls(evt, cmd, frames, force_tls))
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    on : Bool <- images_enabled()
    open_watch(ui, Sess.session_set_media(Sess.session_set_now(Sess.session_demo_at(cl, chan, port), ts), M.initial(on)), 0, evt, cmd, ack, frames, "")

def run_demo_tty(+frames: U32, +cl: Cl.Client, +chan: String, +ts: String, port: U32, force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    evt0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    cmd0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    run_demo_go(evt0, cmd0, ack, frames, cl, chan, ts, port, force_tls)

def run_offline_pick(headless: Bool, +frames: U32, +cl: Cl.Client, +chan: String, +ts: String, port: U32, force_tls: Bool) -> IO(Unit):
  match headless:
    case True{}:
      smoke(frames, cl, chan, ts, port)
    case False{}:
      run_demo_tty(frames, cl, chan, ts, port, force_tls)

def run_offline(+frames: U32, +cl: Cl.Client, +chan: String, port: U32, force_tls: Bool) -> IO(Unit):
  do IO<Unit>:
    ts : String <- Clock.hhmmss()
    t : U32 <- T.Timui.isatty()
    run_offline_pick(U32.is_eq(t, 0), frames, cl, chan, ts, port, force_tls)
