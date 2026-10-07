# SPDX-License-Identifier: Apache-2.0
# SOURCE UNRUN: actual stamped/parked carrier entries and owned Ui teardown.
# Lease records are synthetic retention markers, not spawned helper work.
# These paths spawn no actor/helper and perform no paint, connect, or fetch.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/isupport.bend as Iso
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/wsnet.bend as WsNet
import ../../src/bend/cards.bend as C
import ../../src/bend/media.bend as M
import ../../src/bend/timui.bend as T
import ../../src/bend/drafts.bend as Drafts
import ../../src/bend/live_context.bend as PrefLive
import ../../src/bend/preferences_worker.bend as PrefWorker

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def seed_session() -> Sess.Session:
  +st = Sess.session_demo(Cl.init("me", "carrier.test"), "#t")
  +iso = Iso.apply_line(Iso.defaults(), ":carrier.test 005 me CASEMAPPING=ascii :x")
  Sess.session_upload_draft(Sess.session_set_iso(st, iso), "carrier draft", 17)

def seed_ws() -> W.Workspace:
  W.Workspace{[W.Part{s0(), 0, Sid.Scope{"carrier.test", 6697, False{}}, seed_session()}], s0(), Drafts.set(Drafts.empty(), s0(), "#t", "stored draft"), Nil{}}

def seed_loop() -> WsNet.WsLoop:
  +ws = seed_ws()
  +ctx = PrefLive.initial(PrefWorker.Options{False{}, False{}, False{}, False{}}, seed_session(), 0, "carrier.history")
  +notify : WsNet.WsNotify = WsNet.WsNotify{WsNet.ws_notify.parts(WsNet.ws_notify.seed_all(ws)), Some{WsNet.WsNotifyLease{Key.ServerId{1n}, 53, 59n, "notify.test:6697"}}, 61n}
  +cards : WsNet.WsCardsAll = WsNet.WsCardsAll{[WsNet.WsCards{s0(), 0, C.initial(True{}), C.FullOff{}}], Some{WsNet.WsCardsLease{Key.ServerId{2n}, 67, C.Request{C.CardInline{11n}, "https://carrier.test/card", 71n, 73n}}}}
  WsNet.ws_mkloop(ws, 77, True{}, ctx, Some{WsNet.WsMedia{Key.ServerId{1n}, 41, M.Request{M.Inline{3n}, "https://carrier.test/a.png", 5n, 7n}}}, Some{WsNet.WsLease{Key.ServerId{2n}, 43}}, [WsNet.WsLease{Key.ServerId{3n}, 47}], notify, cards, False{})

def ws_ok(+ws: W.Workspace) -> Bool:
  match ws:
    case W.Workspace{Con{W.Part{Key.ServerId{0n}, 0, Sid.Scope{"carrier.test", 6697, False{}}, +st}, Nil{}}, Key.ServerId{0n}, +ds, Nil{}}:
      String.eq(Sess.session_cm(st), "ascii") && String.eq(Sess.session_draft(st), "carrier draft") && U32.is_eq(Sess.session_seed(st), 17) && String.eq(Cl.nick_of(Sess.session_cl(st)), "me") && String.eq(Cl.server_of(Sess.session_cl(st)), "carrier.test") && U32.is_eq(Sess.session_port(st), 6697) && String.eq(Drafts.get(ds, s0(), "#t"), "stored draft")
    case _: False{}

def ctx_ok(value: PrefLive.Details) -> Bool:
  match value:
    case PrefLive.Details{_, PrefLive.Ready{}, Some{True{}}, "carrier.history", None{}, 0n}: True{}
    case _: False{}

# Check the same physical identities in smaller parameter-match trees.
def loop_leases_ok(+media: Maybe<&2, WsNet.WsMedia>, +owner: Maybe<&2, WsNet.WsLease>, +ups: List<&2, WsNet.WsLease>) -> Bool:
  match media:
    case Some{WsNet.WsMedia{Key.ServerId{1n}, 41, M.Request{M.Inline{3n}, "https://carrier.test/a.png", 5n, 7n}}}:
      match owner:
        case Some{WsNet.WsLease{Key.ServerId{2n}, 43}}:
          match ups:
            case Con{WsNet.WsLease{Key.ServerId{3n}, 47}, Nil{}}: True{}
            case _: False{}
        case _: False{}
    case _: False{}

def loop_notify_ok(+notify: WsNet.WsNotify) -> Bool:
  match notify:
    case WsNet.WsNotify{Con{WsNet.WsNotifyPart{Key.ServerId{0n}, 0, +nl}, Nil{}}, Some{WsNet.WsNotifyLease{Key.ServerId{1n}, 53, 59n, "notify.test:6697"}}, 61n}: String.eq(Sess.notify_live_endpoint(nl), "carrier.test:6697")
    case _: False{}

def loop_cards_ok(+cards: WsNet.WsCardsAll) -> Bool:
  match cards:
    case WsNet.WsCardsAll{Con{WsNet.WsCards{Key.ServerId{0n}, 0, +cs, C.FullOff{}}, Nil{}}, Some{WsNet.WsCardsLease{Key.ServerId{2n}, 67, C.Request{C.CardInline{11n}, "https://carrier.test/card", 71n, 73n}}}}: C.enabled(cs)
    case _: False{}

# All ten outer fields and every captured physical lease identity are checked.
# Workspace/Context/logical sidecars are explicit metadata projections, not
# whole-record equality or evidence of a real worker having been spawned.
def loop_ok(+loop: WsNet.WsLoop) -> Bool:
  match loop:
    case WsNet.WsLoop{+ws, 77, True{}, +ctx, +media, +owner, +ups, +notify, +cards, False{}}:
      ws_ok(ws) && ctx_ok(PrefLive.details(ctx)) && loop_leases_ok(media, owner, ups) && loop_notify_ok(notify) && loop_cards_ok(cards)
    case _: False{}

# Only the absent-origin preferences callback retires the inactive owner.
# Reuse the original strict predicate for every other field and every other mode.
def loop_prefs_owner(+loop: WsNet.WsLoop, owner: Maybe<&2, WsNet.WsLease>) -> WsNet.WsLoop:
  match loop:
    case WsNet.WsLoop{ws, bell, scheduled, ctx, media, _, ups, notify, cards, begun}:
      WsNet.ws_mkloop(ws, bell, scheduled, ctx, media, owner, ups, notify, cards, begun)

def loop_retired(+loop: WsNet.WsLoop) -> Bool:
  match loop:
    case WsNet.WsLoop{_, _, _, _, _, None{}, _, _, _, _}:
      loop_ok(loop_prefs_owner(loop, Some{WsNet.WsLease{Key.ServerId{2n}, 43}}))
    case _: False{}

def loop_return_ok(mode: String, loop: WsNet.WsLoop) -> Bool:
  match mode:
    case "parked-prefs": loop_retired(loop)
    case _: loop_ok(loop)

def prefs_retired_ok(result: PrefLive.Context & Maybe<&2, WsNet.WsLease>) -> Bool:
  match result:
    case (+ctx, None{}): ctx_ok(PrefLive.details(ctx)) && Bool.not(PrefLive.active(ctx))
    case _: False{}

def finish(+mode: String, +wanted: Bool, trip: T.Ui & WsNet.WsLoop & Bool) -> IO(Unit):
  match trip:
    case (ui, +loop, halt):
      +ok = loop_return_ok(mode, loop)
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        Unit <- IO.print("carrier_callback:" ++ mode ++ "\n")
        Unit <- E.must("carrier returns exact seeded metadata/leases", ok)
        Unit <- E.must("carrier returns expected halt", Bool.not(Bool.xor(halt, wanted)))
        Unit <- IO.print("carrier_case=ok:" ++ mode ++ "\n")
        T.Sys.exit_done()

def parked(+mode: String, +saved: List<&2, WsNet.WsLoop>, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(WsNet.WsMsg, main)
    g : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
    WsNet.ws_parked.recv(g, saved, ui, main, cmds, evts, pevts, ack, trip => finish(mode, True{}, trip))

# Require the actual buffered receive before exercising any Some branch.
def parked_some.got(g: Maybe<&1, WsNet.WsMsg>, +mode: String, +saved: List<&2, WsNet.WsLoop>, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  match g:
    case None{}:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        T.Sys.exit_fail("birc: carrier queue returned no message")
    case Some{msg}:
      WsNet.ws_parked.recv(Some{msg}, saved, ui, main, cmds, evts, pevts, ack, trip => finish(mode, False{}, trip))

def parked_some.sent(sent: Bool, +mode: String, +saved: List<&2, WsNet.WsLoop>, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  match sent:
    case False{}:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        T.Sys.exit_fail("birc: carrier queue refused message")
    case True{}:
      do IO<Unit>:
        Unit <- Chan.close(WsNet.WsMsg, main)
        g : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
        parked_some.got(g, mode, saved, ui, main, cmds, evts, pevts, ack)

def parked_some(+mode: String, +saved: List<&2, WsNet.WsLoop>, +msg: WsNet.WsMsg, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(WsNet.WsMsg, main, msg)
    parked_some.sent(sent, mode, saved, ui, main, cmds, evts, pevts, ack)

def quiet_tick(value: W.TickOut) -> Bool:
  match value:
    case W.TickOut{+ws, False{}, Nil{}}: ws_ok(ws)
    case _: False{}

# The seeded preferences owner (Sid2/gen43) is absent from the sole Part0.
# The positive exercises the real preferences clock then the absent-owner drop;
# the callback requires exact None for this inactive preferences owner only;
# all other metadata and physical leases keep the original strict checks.
def run_mode.prefs(+mode: String, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  match mode:
    case "parked-prefs": parked_some(mode, [seed_loop()], WsNet.WsPrefs{Sess.UiContinue{}}, ui, main, cmds, evts, pevts, ack)
    case "parked-prefs-nil": parked_some(mode, Nil{}, WsNet.WsPrefs{Sess.UiContinue{}}, ui, main, cmds, evts, pevts, ack)
    case _:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        T.Sys.exit_fail("birc: unknown carrier mode")

def run_mode.tail(+mode: String, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  match mode:
    case "parked-tick": parked_some(mode, [seed_loop()], WsNet.WsTick{123}, ui, main, cmds, evts, pevts, ack)
    case "parked-some-nil": parked_some(mode, Nil{}, WsNet.WsNet{Sid.RoutedMsg{s0(), Sess.UiContinue{}}}, ui, main, cmds, evts, pevts, ack)
    case _: run_mode.prefs(mode, ui, main, cmds, evts, pevts, ack)

def run_mode.mid(+mode: String, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  match mode:
    case "parked-nil": parked(mode, Nil{}, ui, main, cmds, evts, pevts, ack)
    case "parked-net": parked_some(mode, [seed_loop()], WsNet.WsNet{Sid.RoutedMsg{s0(), Sess.UiContinue{}}}, ui, main, cmds, evts, pevts, ack)
    case _: run_mode.tail(mode, ui, main, cmds, evts, pevts, ack)

def run_mode(+mode: String, ui: T.Ui, +main: Chan(WsNet.WsMsg), +cmds: WsNet.WsCmds, +evts: WsNet.WsEvts, +pevts: Chan(Sess.UiMsg), +ack: Chan(Unit)) -> IO(Unit):
  match mode:
    case "routed":
      WsNet.ws_routed.stamped([seed_loop()], Sid.RoutedMsg{s0(), Sess.UiContinue{}}, ui, main, cmds, evts, pevts, ack, 123, "01:02:03", trip => finish(mode, False{}, trip))
    case "routed-nil":
      WsNet.ws_routed.stamped(Nil{}, Sid.RoutedMsg{s0(), Sess.UiContinue{}}, ui, main, cmds, evts, pevts, ack, 123, "01:02:03", trip => finish(mode, False{}, trip))
    case "parked": parked(mode, [seed_loop()], ui, main, cmds, evts, pevts, ack)
    case _: run_mode.mid(mode, ui, main, cmds, evts, pevts, ack)

def run_case(+mode: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("carrier seed has nondefault metadata and held leases", loop_ok(seed_loop()))
    Unit <- E.must("carrier retired prefs accepts exact None", loop_return_ok("parked-prefs", loop_prefs_owner(seed_loop(), None{})))
    Unit <- E.must("carrier retired prefs rejects retained Some", Bool.not(loop_return_ok("parked-prefs", seed_loop())))
    Unit <- E.must("carrier retired prefs rejects foreign Some", Bool.not(loop_return_ok("parked-prefs", loop_prefs_owner(seed_loop(), Some{WsNet.WsLease{Key.ServerId{3n}, 47}}))))
    Unit <- E.must("carrier other path retains exact Some", loop_return_ok("parked-net", seed_loop()))
    Unit <- E.must("carrier other path rejects None", Bool.not(loop_return_ok("parked-net", loop_prefs_owner(seed_loop(), None{}))))
    Unit <- E.must("carrier other path rejects foreign Some", Bool.not(loop_return_ok("parked-net", loop_prefs_owner(seed_loop(), Some{WsNet.WsLease{Key.ServerId{3n}, 47}}))))
    Unit <- E.must("carrier inactive prefs rejection retires physical owner", prefs_retired_ok(WsNet.ws_prefs.rejected(Sess.UiContinue{}, PrefLive.initial(PrefWorker.Options{False{}, False{}, False{}, False{}}, seed_session(), 0, "carrier.history"), Some{WsNet.WsLease{Key.ServerId{2n}, 43}})))
    Unit <- E.must("carrier tick seed has no paint or outbound work", quiet_tick(W.tick_typing(seed_ws(), 123)))
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    +main : Chan(WsNet.WsMsg) <- Chan.new(WsNet.WsMsg, 1)
    +c0 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +c1 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +c2 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +c3 : Chan(Sess.NetCmd) <- Chan.new(Sess.NetCmd, 1)
    +e0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 1)
    +e1 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 1)
    +e2 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 1)
    +e3 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 1)
    +pevts : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 1)
    +ack : Chan(Unit) <- Chan.new(Unit, 1)
    run_mode(mode, ui, main, WsNet.WsCmds{c0, c1, c2, c3}, WsNet.WsEvts{e0, e1, e2, e3}, pevts, ack)

# Byte-exact existing native fixture public FFI retention bodies.
# None of the nine guard modes enters ffi-retain; no watcher is spawned.
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

def args_go(+mode: String) -> IO(Unit):
  match mode:
    case "ffi-retain": run_retain()
    case _: run_case(mode)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+mode, Nil{}}}: args_go(mode)
    case _: T.Sys.exit_fail("birc: expected one carrier mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
