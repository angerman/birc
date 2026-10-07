# Cards removed-origin handoff (native): after an exact completion for an
# absent origin retires the global lease, the shared stage must start the
# current part's queued visible URL with no unrelated input. Wrong
# completions keep the lease and start nothing; an open fullscreen stays
# quiet even with the lease freed. Real T.Timui open (headless), real
# ws_cards.got_on/gone/retired/staged path, real helper spawn observed via
# the part evt channel. Helper is BIRC_CARDS_HELPER from the recipe
# (an owned fake prints a success marker, then exits 0). Modes: handoff (exact A
# done, absent origin -> B starts + B completion posted), wrong (bad ticket
# -> lease kept, B still pending, no spawn), quiet (exact A done with B
# fullscreen open -> lease freed, B still pending, no spawn).
# Ported to ws-cards base: WsLoop carries the WsNotify bundle (per-part
# NotifyLive + one worker lease), so the three got_on calls seed
# WsNet.ws_notify.seed_all(ws) instead of donor N.off(). All receipts,
# FFI retentions, and assertions preserved verbatim.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/cards.bend as C
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/wsnet.bend as WsNet
import ../../src/bend/cards_net.bend as CNet
import ../../src/bend/notify.bend as N
import ../../src/bend/media.bend as M
import ../../src/bend/timui.bend as T
import ../../src/bend/drafts.bend as Drafts
import ../../src/bend/live_context.bend as PrefLive
import ../../src/bend/preferences_worker.bend as PrefWorker

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

def pageA() -> String:
  "https://x.test/page1"

def pageB() -> String:
  "https://x.test/other"

def image1() -> String:
  "https://x.test/a.png"

def reqA() -> C.Request:
  C.Request{C.CardInline{3n}, pageA(), 5n, 7n}

def leaseA() -> WsNet.WsCardsLease:
  WsNet.WsCardsLease{s1(), 0, reqA()}

def chatB() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "h"), 0n,
    [Cl.Line{Cl.Msg{}, "", "see " ++ pageB(), "bob", 1n}])

def chatBQ() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "h"), 0n,
    [Cl.Line{Cl.Msg{}, "", "see " ++ pageB(), "bob", 1n},
     Cl.Line{Cl.Msg{}, "", "see " ++ image1(), "bob", 9n}])

def media9() -> M.State:
  M.State{True{}, 1n, 1n, None{}, Nil{}, M.Ready{M.Inline{9n}, image1(), 11} <> Nil{}, M.Supported{}}

def stB(+chat: Cl.Client, +media: M.State) -> Sess.Session:
  Sess.session_set_media(Sess.session_set_size(Sess.session_online(Sess.session_with_client(chat, "#t")), 24, 80), media)

def wsB(+st: Sess.Session) -> W.Workspace:
  W.Workspace{W.Part{s0(), 0, Sid.Scope{"h", 6697, False{}}, st} <> Nil{}, s0(), Drafts.empty(), Nil{}}

def ctxB(+st: Sess.Session) -> PrefLive.Context:
  PrefLive.initial(PrefWorker.Options{False{}, False{}, False{}, False{}}, st, 0, "")

def cardsB(+cs: C.State, +fl: C.Fullscreen) -> WsNet.WsCardsAll:
  WsNet.WsCardsAll{WsNet.WsCards{s0(), 0, cs, fl} <> Nil{}, Some{leaseA()}}

def owner_text.other(s1hit: Bool) -> String:
  match s1hit:
    case True{}: "s1"
    case False{}: "other"

def owner_text.s1(+owner: Key.ServerId, s0hit: Bool) -> String:
  match s0hit:
    case True{}: "s0"
    case False{}: owner_text.other(Key.eq(owner, s1()))

def owner_text(+owner: Key.ServerId) -> String:
  owner_text.s1(owner, Key.eq(owner, s0()))

def lease_text(+l: Maybe<&2, WsNet.WsCardsLease>) -> String:
  match l:
    case None{}: "none"
    case Some{+held}:
      match held:
        case WsNet.WsCardsLease{+owner, _, +req}:
          match req:
            case C.Request{_, +url, +g, +t}:
              owner_text(owner) ++ ":" ++ Nat.show(g) ++ ":" ++ Nat.show(t) ++ ":" ++ url

def bool_text(+b: Bool) -> String:
  match b:
    case True{}: "true"
    case False{}: "false"

def found_text(found: C.State & C.Fullscreen) -> String:
  match found:
    case (+cs, +fl):
      match cs:
        case C.State{_, _, _, +active, +pending, _}:
          match active:
            case None{}: "idle:" ++ Nat.show(List.length(&2, C.Request, pending)) ++ ":" ++ bool_text(C.is_open(fl))
            case Some{+req}:
              match req:
                case C.Request{_, +url, +g, +t}:
                  "active:" ++ Nat.show(g) ++ ":" ++ Nat.show(t) ++ ":" ++ url

def finish(+res: Chan(WsNet.WsLoop & Bool), trip: T.Ui & WsNet.WsLoop & Bool) -> IO(Unit):
  match trip:
    case (ui, +loop, repaint):
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        _ : Bool <- Chan.send(WsNet.WsLoop & Bool, res, (loop, repaint))
        return Unit{}

def loop_cards(+loop: WsNet.WsLoop) -> WsNet.WsCardsAll:
  match loop:
    case WsNet.WsLoop{_, _, _, _, _, _, _, _, +cards, _}: cards

def loop_text(got: Maybe<&1, WsNet.WsLoop & Bool>) -> String:
  match got:
    case None{}: "none"
    case Some{pair}:
      match pair:
        case (+loop, repaint):
          lease_text(WsNet.ws_cards_all.lease(loop_cards(loop))) ++ "|" ++ found_text(WsNet.ws_cards.sidecar(WsNet.ws_cards_all.parts(loop_cards(loop)), s0(), 0, True{})) ++ "|" ++ bool_text(repaint)

def fetched_text(got: Maybe<&1, Sess.UiMsg>) -> String:
  match got:
    case None{}: "none"
    case Some{+m}:
      match m:
        case Sess.CardFetched{_, +t, +url, _}: Nat.show(t) ++ ":" ++ url
        case _: "other"

def fetched_payload(msg: Sess.UiMsg) -> String:
  match msg:
    case Sess.CardFetched{_, _, _, +payload}: payload
    case _: ""

def fetched_verified(got: Maybe<&1, Sess.UiMsg>) -> IO(Maybe<&1, Sess.UiMsg>):
  match got:
    case None{}: IO.pure(Maybe<&1, Sess.UiMsg>, None{})
    case Some{+msg}:
      do IO<Maybe<&1, Sess.UiMsg>>:
        Unit <- E.must_eq("handoff helper invoked successfully", fetched_payload(msg), "birc-cards-fixture-invoked=ok\n")
        return Some{msg}

def check_loop(+res: Chan(WsNet.WsLoop & Bool), +want: String, +tag: String) -> IO(Unit):
  do IO<Unit>:
    got : Maybe<&1, WsNet.WsLoop & Bool> <- Chan.recv(WsNet.WsLoop & Bool, res)
    E.must_eq(tag, loop_text(got), want)

def run_handoff(ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +res: Chan(WsNet.WsLoop & Bool), +e0: Chan(Sess.UiMsg), +on: Bool) -> IO(Unit):
  +st = stB(chatB(), M.initial(True{}))
  +ws = wsB(st)
  +cards = cardsB(C.initial(True{}), C.FullOff{})
  do IO<Unit>:
    Unit <- E.must("cards default enabled", on)
    Unit <- E.must_eq("helper success preserves invocation marker", CNet.cards_payload(Done{(0, ("birc-cards-fixture-invoked=ok\n", ""))}), "birc-cards-fixture-invoked=ok\n")
    Unit <- E.must_eq("helper nonzero rejects invocation marker", CNet.cards_payload(Done{(1, ("birc-cards-fixture-invoked=ok\n", ""))}), "")
    Unit <- E.must_eq("helper launch failure rejects invocation marker", CNet.cards_payload(Fail{(1, "synthetic helper launch failure")}), "")
    Unit <- WsNet.ws_cards.got_on(on, None{}, ui, ws, s1(), 5n, 7n, pageA(), "T\nD\n", "0", main, cmds, evts, pevts, ack, False{}, 0, ctxB(st), None{}, None{}, Nil{}, WsNet.ws_notify.seed_all(ws), cards, True{}, finish(res))
    Unit <- check_loop(res, "s0:1:1:" ++ pageB() ++ "|active:1:1:" ++ pageB() ++ "|false", "handoff loop")
    raw_fetched : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, e0)
    fetched : Maybe<&1, Sess.UiMsg> <- fetched_verified(raw_fetched)
    Unit <- E.must_eq("handoff helper posted B", fetched_text(fetched), "1:" ++ pageB())
    IO.print("\ncards_handoff_native=ok")

def run_wrong(ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +res: Chan(WsNet.WsLoop & Bool), on: Bool) -> IO(Unit):
  +st = stB(chatB(), M.initial(True{}))
  +ws = wsB(st)
  +cs = C.enqueue(C.initial(True{}), C.CardInline{2n}, pageB())
  +cards = cardsB(cs, C.FullOff{})
  do IO<Unit>:
    Unit <- WsNet.ws_cards.got_on(on, None{}, ui, ws, s1(), 5n, 8n, pageA(), "T\nD\n", "0", main, cmds, evts, pevts, ack, False{}, 0, ctxB(st), None{}, None{}, Nil{}, WsNet.ws_notify.seed_all(ws), cards, True{}, finish(res))
    Unit <- check_loop(res, "s1:5:7:" ++ pageA() ++ "|idle:1:false|false", "wrong loop")
    IO.print("\ncards_handoff_native=ok")

def run_quiet(ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +res: Chan(WsNet.WsLoop & Bool), on: Bool) -> IO(Unit):
  +st = stB(chatBQ(), media9())
  +ws = wsB(st)
  +cs = C.enqueue(C.initial(True{}), C.CardInline{1n}, pageB())
  +cards = cardsB(cs, C.FullOn{M.Inline{9n}, image1(), 11})
  do IO<Unit>:
    Unit <- WsNet.ws_cards.got_on(on, None{}, ui, ws, s1(), 5n, 7n, pageA(), "T\nD\n", "0", main, cmds, evts, pevts, ack, False{}, 0, ctxB(st), None{}, None{}, Nil{}, WsNet.ws_notify.seed_all(ws), cards, True{}, finish(res))
    Unit <- check_loop(res, "none|idle:1:true|false", "quiet loop")
    IO.print("\ncards_handoff_native=ok")

def run_mode(+mode: String, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit), +res: Chan(WsNet.WsLoop & Bool), +e0: Chan(Sess.UiMsg), on: Bool) -> IO(Unit):
  match mode:
    case "handoff": run_handoff(ui, main, cmds, evts, pevts, ack, res, e0, on)
    case "wrong": run_wrong(ui, main, cmds, evts, pevts, ack, res, on)
    case "quiet": run_quiet(ui, main, cmds, evts, pevts, ack, res, on)
    case _: IO.die(Unit, 1, "expected handoff|wrong|quiet")

def run_case(+mode: String) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    +main : Chan(WsNet.WsMsg) <- Chan.new(WsNet.WsMsg, 8)
    +c0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +c1 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +c2 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +c3 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +e0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +e1 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +e2 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +e3 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +pevts : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 8)
    +ack : Chan(Unit) <- Chan.new(Unit, 1)
    +res : Chan(WsNet.WsLoop & Bool) <- Chan.new(WsNet.WsLoop & Bool, 1)
    +on : Bool <- CNet.cards_enabled()
    run_mode(mode, ui, main, WsNet.WsCmds{c0, c1, c2, c3}, WsNet.WsEvts{e0, e1, e2, e3}, pevts, ack, res, e0, on)

# Fixture-only FFI retention seam (C8): the three guard modes never run
# the diagnostic arm. The normal path passes wait=False through the
# non-specialized Bool helpers so both ready refs/CIDs survive the locked
# book walk. Uses only existing public Timui/Tty/Winch effects.
def retain_tty(wait: Bool, tty: T.Tty) -> IO(Unit):
  match wait:
    case False{}: T.Tty.close(tty)
    case True{}:
      do IO<Unit>:
        tty2 : T.Tty <- T.Tty.ready(tty)
        T.Tty.close(tty2)

def retain_winch(wait: Bool, w: T.Winch) -> IO(Unit):
  match wait:
    case False{}: T.Winch.close(w)
    case True{}:
      do IO<Unit>:
        w2 : T.Winch <- T.Winch.ready(w)
        T.Winch.close(w2)

def retain_tty_res(+wait: Bool, tr: Result<&1, &1, U32 & String, T.Tty>) -> IO(Unit):
  match tr:
    case Fail{_}: IO.pure(Unit, Unit{})
    case Done{tty}: retain_tty(wait, tty)

def retain_winch_res(+wait: Bool, wr: Result<&1, &1, U32 & String, T.Winch>) -> IO(Unit):
  match wr:
    case Fail{_}: IO.pure(Unit, Unit{})
    case Done{w}: retain_winch(wait, w)

def retain_isatty(wait: Bool, +v: U32) -> IO(Unit):
  match wait:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: IO.pure(Unit, Unit{})

def retain_done(pair: T.Ui & Result<&1, &1, U32 & String, T.Tty>, wr: Result<&1, &1, U32 & String, T.Winch>) -> IO(Unit):
  match pair:
    case (ui, tr):
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        Unit <- retain_tty_res(False{}, tr)
        Unit <- retain_winch_res(False{}, wr)
        IO.print("\nffi_retain=ok")

def run_retain() -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    wr : Result<&1, &1, U32 & String, T.Winch> <- T.Winch.open()
    pair : T.Ui & Result<&1, &1, U32 & String, T.Tty> <- T.Timui.tty(ui)
    t : U32 <- T.Timui.isatty()
    Unit <- retain_isatty(False{}, t)
    retain_done(pair, wr)

def args_go(retain: Bool, +mode: String) -> IO(Unit):
  match retain:
    # Fixture-only retention seam; the guard modes never run this arm.
    case True{}: run_retain()
    case False{}: run_case(mode)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+mode, Nil{}}}: args_go(String.eq(mode, "ffi-retain"), mode)
    case _: IO.die(Unit, 1, "expected mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
