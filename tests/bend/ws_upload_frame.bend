# SPDX-License-Identifier: Apache-2.0
# True upload frame qualification: every key arrives as physical terminal
# input through a real first/live paint. The fixture never builds key
# structs, never calls the painted/keys entries directly, and never touches
# the consent seam. Frame one crosses WsNet.ws_first.frame; every later
# frame crosses WsNet.ws_paint. The post-stage take and the helper spawn run
# inside those entries. Completions are awaited from the owned part channel
# and routed through WsNet.ws_routed; the send lands on the part channel as
# production Cont outs. The driver owns a recording fake helper plus
# synthetic files, and asserts warning-before-F8, coalesced Enter+F8
# no-launch, launch exactly-once, Esc-after-held-start discard, right-target
# outs, and the exact ledger total with unknown-row rejection. Cases run
# coal, held, once so no link card worker can post ahead of an awaited
# completion.
# Defs run bottom-up so no dotted name is used before its definition.
# Native CC backend. Source-only: Main qualifies the exact binary.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/upload.bend as U
import ../../src/bend/wsnet.bend as WsNet
import ../../src/bend/timui.bend as T
import ../../src/bend/live_context.bend as PrefLive
import ../../src/bend/preferences_worker.bend as PrefWorker
import ../../src/bend/app.bend as App

# One box for every continuation: live channels plus the expected send.
type Ctx is Data:
  Ctx{main: Chan(WsNet.WsMsg), c0: Chan(Sess.NetCmd), c1: Chan(Sess.NetCmd), c2: Chan(Sess.NetCmd), c3: Chan(Sess.NetCmd), e0: Chan(Sess.UiMsg), e1: Chan(Sess.UiMsg), e2: Chan(Sess.UiMsg), e3: Chan(Sess.UiMsg), pevts: Chan(Sess.UiMsg), ack: Chan(Unit), once_url: String}

def online_at(+host: String, +chan: String, +port: U32) -> Sess.Session:
  +cl = Feed.feed(Cl.init("me", host), ":me!u@h JOIN :" ++ chan)
  Sess.session_online(Sess.session_with_client_at(Cl.set_active(cl, 1n), chan, port))

def ws_two() -> W.Workspace:
  W.do_add(W.single_client("h.example", 6697, False{}, Cl.init("me", "h.example"), "#a"), "i.example", 6697, False{}, "me", "#b")

def ws_put.got(+got: Maybe<&2, W.Part>, +ws: W.Workspace, +st: Sess.Session) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+pid, +gen, +scope, _}: W.replace_part(ws, W.Part{pid, gen, scope, st})

def ws_put(+ws: W.Workspace, +id: Key.ServerId, +st: Sess.Session) -> W.Workspace:
  ws_put.got(W.find_part(ws, id), ws, st)

def ws_online() -> W.Workspace:
  ws_put(ws_put(ws_two(), Key.ServerId{0n}, online_at("h.example", "#a", 6697)), Key.ServerId{1n}, online_at("i.example", "#b", 6697))

def phase.state(+state: U.State) -> String:
  match state:
    case U.Idle{}: "idle"
    case U.Confirm{_, _}: "confirm"
    case U.Armed{_, _}: "ready"
    case U.Busy{_, _, _}: "busy"

def phase.got(+got: Maybe<&2, W.Part>) -> String:
  match got:
    case None{}: "missing"
    case Some{+p}:
      match p:
        case W.Part{_, _, _, +st}: phase.state(Sess.session_upload(st))

def phase.of(+ws: W.Workspace) -> String:
  phase.got(W.find_part(ws, Key.ServerId{0n}))

def presented.got(+got: Maybe<&2, W.Part>) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}:
      match p:
        case W.Part{_, _, _, +st}: Sess.session_upload_presented(st)

def presented.of(+ws: W.Workspace) -> Bool:
  presented.got(W.find_part(ws, Key.ServerId{0n}))

def bit(+on: Bool) -> String:
  match on:
    case True{}: "1"
    case False{}: "0"

def allowed.state(+state: U.State) -> String:
  match state:
    case U.Busy{_, _, allowed}: bit(allowed)
    case _: "n/a"

def allowed.got(+got: Maybe<&2, W.Part>) -> String:
  match got:
    case None{}: "missing"
    case Some{+p}:
      match p:
        case W.Part{_, _, _, +st}: allowed.state(Sess.session_upload(st))

def allowed.of(+ws: W.Workspace) -> String:
  allowed.got(W.find_part(ws, Key.ServerId{0n}))

def lines_has(+xs: List<&2, Cl.Line>, +needle: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Cl.Line{_, _, text, _, _}, t}: String.contains(text, needle) || lines_has(t, needle)

def bufs_has(+xs: List<&2, Cl.Buffer>, +needle: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Cl.Buffer{_, _, topic, lines, _, _}, t}: String.contains(topic, needle) || lines_has(lines, needle) || bufs_has(t, needle)

def chat_has.got(+got: Maybe<&2, W.Part>, +needle: String) -> Bool:
  match got:
    case None{}: False{}
    case Some{+p}:
      match p:
        case W.Part{_, _, _, +st}: bufs_has(Cl.client_bufs(Sess.session_cl(st)), needle)

def chat_has(+ws: W.Workspace, +id: Key.ServerId, +needle: String) -> Bool:
  chat_has.got(W.find_part(ws, id), needle)

def loop.ws(+loop: WsNet.WsLoop) -> W.Workspace:
  match loop:
    case WsNet.WsLoop{+ws, _, _, _, _, _, _, _, _, _}: ws

def loop.of(+ws: W.Workspace) -> WsNet.WsLoop:
  WsNet.WsLoop{ws, 0, False{}, PrefLive.initial(PrefWorker.Options{False{}, False{}, False{}, False{}}, W.current_session(ws), 0, ""), None{}, None{}, Nil{}, WsNet.ws_notify.seed_all(ws), WsNet.ws_cards_all.empty(), True{}}

def first.go(ui: T.Ui, +ws: W.Workspace, +ctx: Ctx, k: (T.Ui & W.Workspace & Sid.RoutedCmd & Bool) -> IO(Unit)) -> IO(Unit):
  match ctx:
    case Ctx{_, _, _, _, _, +e0, +e1, +e2, +e3, _, _, _}:
      do IO<Unit>:
        got : T.Ui & W.Workspace & Sid.RoutedCmd & Bool <- WsNet.ws_first.frame(ui, ws, WsNet.WsEvts{e0, e1, e2, e3})
        k(got)

def live.go(ui: T.Ui, +loop: WsNet.WsLoop, +ctx: Ctx, k: (T.Ui & WsNet.WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsNet.WsLoop{+ws, +bell, +scheduled, +pctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match ctx:
        case Ctx{+main, +c0, +c1, +c2, +c3, +e0, +e1, +e2, +e3, +pevts, +ack, _}:
          WsNet.ws_paint(ws, ui, False{}, main, WsNet.WsCmds{c0, c1, c2, c3}, WsNet.WsEvts{e0, e1, e2, e3}, pevts, ack, scheduled, False{}, bell, pctx, media, owner, ups, notify, cards, begun, k)

def gate.fail(e: U32 & String, ui: T.Ui) -> IO(Unit):
  match e:
    case (_, +msg):
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        IO.die(Unit, 1, "tty unavailable: " ++ msg)

def gate.tty(got: T.Ui & Result<&1, &1, U32 & String, T.Tty>, k: T.Ui -> IO(Unit)) -> IO(Unit):
  match got:
    case (ui, res):
      match res:
        case Fail{e}: gate.fail(e, ui)
        case Done{tty}:
          do IO<Unit>:
            tty2 : T.Tty <- T.Tty.ready(tty)
            Unit <- T.Tty.close(tty2)
            k(ui)

def gate.ui(ui: T.Ui, k: T.Ui -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    got : T.Ui & Result<&1, &1, U32 & String, T.Tty> <- T.Timui.tty(ui)
    gate.tty(got, k)

def route.go(m: Sess.UiMsg, ui: T.Ui, +loop: WsNet.WsLoop, +ctx: Ctx, k: (T.Ui & WsNet.WsLoop & Bool) -> IO(Unit)) -> IO(Unit):
  match loop:
    case WsNet.WsLoop{+ws, +bell, +scheduled, +pctx, +media, +owner, +ups, +notify, +cards, +begun}:
      match ctx:
        case Ctx{+main, +c0, +c1, +c2, +c3, +e0, +e1, +e2, +e3, +pevts, +ack, _}:
          WsNet.ws_routed(Sid.RoutedMsg{Key.ServerId{0n}, m}, ws, ui, main, WsNet.WsCmds{c0, c1, c2, c3}, WsNet.WsEvts{e0, e1, e2, e3}, pevts, ack, scheduled, bell, pctx, media, owner, ups, notify, cards, begun, k)

# Test-side settle for the trailing link worker, then close and report.
# Production deadlines are untouched; the driver adds its own bounded waits.
def settle(ui: T.Ui) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.sleep(1500)
    Unit <- T.Timui.close(ui)
    IO.print("ws_upload_frame=ok\n")

def once4.drained_c(got: Maybe<&1, Sess.NetCmd>, ui: T.Ui, +tag: String) -> IO(T.Ui):
  match got:
    case None{}: IO.pure(T.Ui, ui)
    case Some{cmd}:
      match cmd:
        case Sess.Cont{outs}:
          do IO<T.Ui>:
            Unit <- T.Timui.close(ui)
            IO.die(T.Ui, 1, tag ++ " duplicate Cont: " ++ String.join(outs, "|"))
        case _:
          do IO<T.Ui>:
            Unit <- T.Timui.close(ui)
            IO.die(T.Ui, 1, tag ++ " unexpected queued send")

def once4.sealed(+c0: Chan(Sess.NetCmd), +c1: Chan(Sess.NetCmd), ui: T.Ui) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.NetCmd, c0)
    Unit <- Chan.close(Sess.NetCmd, c1)
    g0 : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, c0)
    ui2 : T.Ui <- once4.drained_c(g0, ui, "c0")
    g1 : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, c1)
    ui3 : T.Ui <- once4.drained_c(g1, ui2, "c1")
    settle(ui3)

def once4.sent(cmd: Sess.NetCmd, ui: T.Ui, +loop: WsNet.WsLoop, +ctx: Ctx) -> IO(Unit):
  match cmd:
    case Sess.Cont{outs}:
      match ctx:
        case Ctx{_, +c0, +c1, _, _, _, _, _, _, _, _, +once_url}:
          do IO<Unit>:
            Unit <- E.must_eq("once outs", String.join(outs, "|"), "PRIVMSG #a :" ++ once_url)
            Unit <- IO.print("frame_once_routed target=#a\n")
            once4.sealed(c0, c1, ui)
    case _:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        IO.die(Unit, 1, "once completion did not send Cont")

def once4.cmd(g: Maybe<&1, Sess.NetCmd>, ui: T.Ui, +loop: WsNet.WsLoop, +ctx: Ctx) -> IO(Unit):
  match g:
    case None{}:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        IO.die(Unit, 1, "cmd closed before upload send")
    case Some{cmd}: once4.sent(cmd, ui, loop, ctx)

def once4.after(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      match ctx:
        case Ctx{_, +c0, _, _, _, _, _, _, _, _, _, _}:
          do IO<Unit>:
            Unit <- E.must("once routed live", Bool.not(halt))
            Unit <- E.must_eq("once routed phase", phase.of(loop.ws(loop)), "idle")
            g : Maybe<&1, Sess.NetCmd> <- Chan.recv(Sess.NetCmd, c0)
            once4.cmd(g, ui, loop, ctx)

def once4.evt(g: Maybe<&1, Sess.UiMsg>, ui: T.Ui, +loop: WsNet.WsLoop, +ctx: Ctx) -> IO(Unit):
  match g:
    case None{}:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        IO.die(Unit, 1, "evt closed before upload completion")
    case Some{m}: route.go(m, ui, loop, ctx, next => once4.after(next, ctx))

def once3.fired(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      match ctx:
        case Ctx{_, _, _, _, _, +e0, _, _, _, _, _, _}:
          do IO<Unit>:
            Unit <- E.must("once fired live", Bool.not(halt))
            Unit <- E.must_eq("once fired phase", phase.of(loop.ws(loop)), "busy")
            Unit <- IO.print("frame_once_fired phase=busy\n")
            g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, e0)
            once4.evt(g, ui, loop, ctx)

def once2.armed(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      do IO<Unit>:
        Unit <- E.must("once armed live", Bool.not(halt))
        Unit <- E.must_eq("once armed phase", phase.of(loop.ws(loop)), "confirm")
        Unit <- E.must("once armed shown", presented.of(loop.ws(loop)))
        Unit <- IO.print("frame_once_armed phase=confirm presented=1\n")
        gate.ui(ui, u => live.go(u, loop, ctx, next => once3.fired(next, ctx)))

def once1.staged(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      do IO<Unit>:
        Unit <- E.must("once staged live", Bool.not(halt))
        Unit <- E.must_eq("once staged phase", phase.of(loop.ws(loop)), "confirm")
        Unit <- E.must("once staged silent", Bool.not(presented.of(loop.ws(loop))))
        Unit <- IO.print("frame_once_staged phase=confirm presented=0\n")
        live.go(ui, loop, ctx, next => once2.armed(next, ctx))

def once1.ui(ui: T.Ui, +ctx: Ctx) -> IO(Unit):
  gate.ui(ui, u => live.go(u, loop.of(ws_online()), ctx, next => once1.staged(next, ctx)))

def held5.after(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      do IO<Unit>:
        Unit <- E.must("held routed live", Bool.not(halt))
        Unit <- E.must_eq("held routed phase", phase.of(loop.ws(loop)), "idle")
        Unit <- E.must("held discarded", chat_has(loop.ws(loop), Key.ServerId{0n}, "canceled or destination changed"))
        Unit <- E.must("held no url", Bool.not(chat_has(loop.ws(loop), Key.ServerId{0n}, "https://0x0.st/")))
        Unit <- IO.print("frame_held_routed phase=idle discarded=1 url=0\n")
        once1.ui(ui, ctx)

def held5.evt(g: Maybe<&1, Sess.UiMsg>, ui: T.Ui, +loop: WsNet.WsLoop, +ctx: Ctx) -> IO(Unit):
  match g:
    case None{}:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        IO.die(Unit, 1, "evt closed before held completion")
    case Some{m}: route.go(m, ui, loop, ctx, next => held5.after(next, ctx))

def held4.escaped(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      match ctx:
        case Ctx{_, _, _, _, _, +e0, _, _, _, _, _, _}:
          do IO<Unit>:
            Unit <- E.must("held escaped live", Bool.not(halt))
            Unit <- E.must_eq("held escaped phase", phase.of(loop.ws(loop)), "busy")
            Unit <- E.must_eq("held escaped allowed", allowed.of(loop.ws(loop)), "0")
            Unit <- IO.print("frame_held_escaped phase=busy allowed=0\n")
            g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, e0)
            held5.evt(g, ui, loop, ctx)

# A raw lone Escape can leave timed input pending after its first paint.
# Mirror the next watcher readiness and one real paint; do not add input.
def held4.timed(got: T.Ui & U32, +loop: WsNet.WsLoop, +ctx: Ctx) -> IO(Unit):
  match got:
    case (ui, ready):
      do IO<Unit>:
        Unit <- E.must("held escape maintenance", U32.is_eq(ready, 1))
        gate.ui(ui, u => live.go(u, loop, ctx, next => held4.escaped(next, ctx)))

def held4.resolved(resolved: Bool, ui: T.Ui, +loop: WsNet.WsLoop, halt: Bool, +ctx: Ctx) -> IO(Unit):
  match resolved:
    case True{}: held4.escaped((ui, loop, halt), ctx)
    case False{}:
      do IO<Unit>:
        got : T.Ui & U32 <- T.Timui.redraw_ready(ui)
        held4.timed(got, loop, ctx)

def held4.input.rest(rest: WsNet.WsLoop & Bool, ui: T.Ui, +ctx: Ctx) -> IO(Unit):
  match rest:
    case (+loop, +halt):
      do IO<Unit>:
        Unit <- E.must("held input live", Bool.not(halt))
        Unit <- E.must_eq("held input phase", phase.of(loop.ws(loop)), "busy")
        held4.resolved(String.eq(allowed.of(loop.ws(loop)), "0"), ui, loop, halt, ctx)

def held4.input(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, rest): held4.input.rest(rest, ui, ctx)

def held3.fired(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      do IO<Unit>:
        Unit <- E.must("held fired live", Bool.not(halt))
        Unit <- E.must_eq("held fired phase", phase.of(loop.ws(loop)), "busy")
        Unit <- IO.print("frame_held_fired phase=busy\n")
        gate.ui(ui, u => live.go(u, loop, ctx, next => held4.input(next, ctx)))

def held2.armed(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      do IO<Unit>:
        Unit <- E.must("held armed live", Bool.not(halt))
        Unit <- E.must_eq("held armed phase", phase.of(loop.ws(loop)), "confirm")
        Unit <- E.must("held armed shown", presented.of(loop.ws(loop)))
        Unit <- IO.print("frame_held_armed phase=confirm presented=1\n")
        gate.ui(ui, u => live.go(u, loop, ctx, next => held3.fired(next, ctx)))

def held1.staged(acc: T.Ui & WsNet.WsLoop & Bool, +ctx: Ctx) -> IO(Unit):
  match acc:
    case (ui, +loop, halt):
      do IO<Unit>:
        Unit <- E.must("held staged live", Bool.not(halt))
        Unit <- E.must_eq("held staged phase", phase.of(loop.ws(loop)), "confirm")
        Unit <- E.must("held staged painted", presented.of(loop.ws(loop)))
        Unit <- IO.print("frame_held_staged phase=confirm presented=1\n")
        live.go(ui, loop, ctx, next => held2.armed(next, ctx))

def held1.ui(ui: T.Ui, +ws: W.Workspace, +ctx: Ctx) -> IO(Unit):
  live.go(ui, loop.of(ws), ctx, next => held1.staged(next, ctx))

def coal.staged(got: T.Ui & W.Workspace & Sid.RoutedCmd & Bool, +ctx: Ctx) -> IO(Unit):
  match got:
    case (ui, +ws1, +rc, halt):
      match ctx:
        case Ctx{_, +c0, +c1, +c2, +c3, +e0, +e1, +e2, +e3, _, _, _}:
          do IO<Unit>:
            Unit <- E.must("coal live", Bool.not(halt))
            Unit <- E.must_eq("coal phase", phase.of(ws1), "confirm")
            Unit <- E.must("coal silent", Bool.not(presented.of(ws1)))
            Unit <- IO.print("frame_coal_staged phase=confirm presented=0\n")
            Unit <- WsNet.ws_emit(rc, WsNet.WsCmds{c0, c1, c2, c3}, WsNet.WsEvts{e0, e1, e2, e3})
            held1.ui(ui, ws1, ctx)

def run.go(ui: T.Ui, main: Chan(WsNet.WsMsg), c0: Chan(Sess.NetCmd), c1: Chan(Sess.NetCmd), c2: Chan(Sess.NetCmd), c3: Chan(Sess.NetCmd), e0: Chan(Sess.UiMsg), e1: Chan(Sess.UiMsg), e2: Chan(Sess.UiMsg), e3: Chan(Sess.UiMsg), pevts: Chan(Sess.UiMsg), ack: Chan(Unit), +once_url: String) -> IO(Unit):
  +ctx : Ctx = Ctx{main, c0, c1, c2, c3, e0, e1, e2, e3, pevts, ack, once_url}
  gate.ui(ui, u => first.go(u, ws_online(), ctx, next => coal.staged(next, ctx)))

def run(+once_url: String) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    Unit <- IO.print("ws_upload_frame=ready\n")
    main : Chan(WsNet.WsMsg) <- Chan.new(WsNet.WsMsg, 64)
    c0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    c1 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    c2 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    c3 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 64)
    e0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    e1 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    e2 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    e3 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    pevts : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    ack : Chan(Unit) <- Chan.new(Unit, 1)
    run.go(ui, main, c0, c1, c2, c3, e0, e1, e2, e3, pevts, ack, once_url)

def dispatch(+mode: String, +once_url: String) -> IO(Unit):
  match mode:
    # Preserve all production FFI IDs; the local guard does not run this arm.
    case "app": App.main()
    case _: run(once_url)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+mode, Con{+once_url, Nil{}}}}: dispatch(mode, once_url)
    case _: IO.die(Unit, 1, "expected mode once-url")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
