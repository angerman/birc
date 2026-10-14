# SPDX-License-Identifier: Apache-2.0
# NATIVE-TESTED (four cases): actual ws_media_stage -> jobs -> job None/Some effects.
# The helper records synthetic local arguments; it reads no source and fetches
# nothing. Clear-before-spawn is source-reviewed, not a runtime order oracle:
# Timui.media_clear only mutates private payload-cache state, with no output.
import Base
import ./expect.bend as E
import ./cards_handoff_native.bend as Retain
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key
import ../../src/bend/server_id.bend as Sid
import ../../src/bend/workspace.bend as W
import ../../src/bend/wsnet.bend as WsNet
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V
import ../../src/bend/submit.bend as Sub
import ../../src/bend/timui.bend as T
import ../../src/bend/drafts.bend as Drafts

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

def request() -> M.Request:
  M.Request{M.Manual{}, "media-stage-fixture.png", 11n, 17n}

# Deliberately stale/noncurrent physical owner. None must keep every field,
# not prune it or replace it with the current server's queued request.
def held() -> Maybe<&2, WsNet.WsMedia>:
  Some{WsNet.WsMedia{s0(), 99, M.Request{M.Inline{33n}, "held-fixture.png", 5n, 7n}}}

def media() -> M.State:
  M.State{True{}, 11n, 17n, None{}, [request()], Nil{}, M.Supported{}}

def preview_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def owner() -> Sess.Session:
  # Manual requests stay live only while the real preview buffer owns source.
  +cl = Cl.set_log_seq(preview_client(Sub.submit_preview(Cl.init("owner", "media-owner.test"), "media-stage-fixture.png")), 20n)
  +st = Sess.session_online(Sess.session_with_client_at(cl, "#owner", 6697))
  Sess.session_set_media(Sess.session_upload_draft(Sess.session_set_size(st, 24, 80), "owner draft", 17), media())

def other() -> Sess.Session:
  Sess.session_upload_draft(Sess.session_with_client_at(Cl.init("other", "media-other.test"), "#other", 6667), "other draft", 23)

def workspace() -> W.Workspace:
  W.Workspace{[W.Part{s0(), 3, Sid.Scope{"media-other.test", 6667, True{}}, other()}, W.Part{s1(), 7, Sid.Scope{"media-owner.test", 6697, False{}}, owner()}], s1(), Drafts.set(Drafts.empty(), s1(), "#owner", "stored draft"), [W.SlotEpoch{Key.ServerId{3n}, 99, 101n}]}

def media_ok(started: Bool, state: M.State) -> Bool:
  match started state:
    case True{} M.State{True{}, 11n, 17n, Some{M.Request{M.Manual{}, "media-stage-fixture.png", 11n, 17n}}, Nil{}, Nil{}, M.Supported{}}: True{}
    case False{} M.State{True{}, 11n, 17n, None{}, Con{M.Request{M.Manual{}, "media-stage-fixture.png", 11n, 17n}, Nil{}}, Nil{}, M.Supported{}}: True{}
    case _ _: False{}

def workspace_ok(+started: Bool, ws: W.Workspace) -> Bool:
  match ws:
    case W.Workspace{Con{W.Part{Key.ServerId{0n}, 3, Sid.Scope{"media-other.test", 6667, True{}}, +st0}, Con{W.Part{Key.ServerId{1n}, 7, Sid.Scope{"media-owner.test", 6697, False{}}, +st1}, Nil{}}}, Key.ServerId{1n}, +ds, Con{W.SlotEpoch{Key.ServerId{3n}, 99, 101n}, Nil{}}}:
      String.eq(Sess.session_draft(st0), "other draft") && U32.is_eq(Sess.session_seed(st0), 23) && U32.is_eq(Sess.session_port(st0), 6667)
        && String.eq(Sess.session_draft(st1), "owner draft") && U32.is_eq(Sess.session_seed(st1), 17) && U32.is_eq(Sess.session_port(st1), 6697)
        && String.eq(Cl.nick_of(Sess.session_cl(st1)), "owner") && String.eq(Cl.server_of(Sess.session_cl(st1)), "media-owner.test")
        && Nat.is_eq(Cl.log_seq_of(Sess.session_cl(st1)), 20n) && String.eq(Drafts.get(ds, s1(), "#owner"), "stored draft")
        && M.alive(Sess.session_cl(st1), M.Manual{}, "media-stage-fixture.png") && media_ok(started, Sess.session_media(st1))
    case _: False{}

def lease_ok(started: Bool, lease: Maybe<&2, WsNet.WsMedia>) -> Bool:
  match started lease:
    case True{} Some{WsNet.WsMedia{Key.ServerId{1n}, 7, M.Request{M.Manual{}, "media-stage-fixture.png", 11n, 17n}}}: True{}
    case False{} Some{WsNet.WsMedia{Key.ServerId{0n}, 99, M.Request{M.Inline{33n}, "held-fixture.png", 5n, 7n}}}: True{}
    case _ _: False{}

def completion_ok(got: Maybe<&1, Sess.UiMsg>) -> Bool:
  match got:
    case Some{Sess.MediaFetched{11n, 17n, "media-stage-fixture.png", "synthetic-media-result\n"}}: True{}
    case _: False{}

def absent(got: Maybe<&1, Sess.UiMsg>) -> Bool:
  match got:
    case None{}: True{}
    case Some{_}: False{}

def empty_event(+evt: Chan(Sess.UiMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- Chan.close(Sess.UiMsg, evt)
    got : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    E.must("no unrelated or duplicate worker completion", absent(got))

def events(started: Bool, +evts: WsNet.WsEvts) -> IO(Unit):
  match started:
    case False{}:
      do IO<Unit>:
        Unit <- empty_event(WsNet.ws_evt.at(evts, 0n))
        Unit <- empty_event(WsNet.ws_evt.at(evts, 1n))
        Unit <- empty_event(WsNet.ws_evt.at(evts, 2n))
        empty_event(WsNet.ws_evt.at(evts, 3n))
    case True{}:
      do IO<Unit>:
        got : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, WsNet.ws_evt.at(evts, 1n))
        Unit <- E.must("worker posts exact generation/ticket/source/payload to owning e1", completion_ok(got))
        Unit <- empty_event(WsNet.ws_evt.at(evts, 0n))
        Unit <- empty_event(WsNet.ws_evt.at(evts, 1n))
        Unit <- empty_event(WsNet.ws_evt.at(evts, 2n))
        empty_event(WsNet.ws_evt.at(evts, 3n))

def finish(+mode: String, +started: Bool, wanted_repaint: Bool, +evts: WsNet.WsEvts, quad: T.Ui & W.Workspace & Bool & Maybe<&2, WsNet.WsMedia>) -> IO(Unit):
  match quad:
    case (ui, ws, repaint, lease):
      +ok = workspace_ok(started, ws) && lease_ok(started, lease) && Bool.not(Bool.xor(repaint, wanted_repaint))
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        Unit <- E.must("actual stage returns exact workspace/lease/repaint", ok)
        Unit <- events(started, evts)
        IO.print("ws_media_stage_native=ok:" ++ mode)

def run_mode(+mode: String, ui: T.Ui, +evts: WsNet.WsEvts) -> IO(Unit):
  match mode:
    case "free":
      do IO<Unit>:
        quad : T.Ui & W.Workspace & Bool & Maybe<&2, WsNet.WsMedia> <- WsNet.ws_media_stage(ui, workspace(), evts, None{})
        finish(mode, True{}, False{}, evts, quad)
    case "blocked":
      do IO<Unit>:
        quad : T.Ui & W.Workspace & Bool & Maybe<&2, WsNet.WsMedia> <- WsNet.ws_media_stage(ui, workspace(), evts, held())
        finish(mode, False{}, False{}, evts, quad)
    case "jobs-none":
      # Different old generation -> clear=True; observed log 20 > old 19.
      do IO<Unit>:
        quad : T.Ui & W.Workspace & Bool & Maybe<&2, WsNet.WsMedia> <- WsNet.ws_media.jobs(M.take_job_allowed(False{}, media()), owner(), 10n, 19n, ui, workspace(), s1(), 7, evts, held())
        finish(mode, False{}, True{}, evts, quad)
    case "jobs-some":
      # Same old generation -> clear=False; observed log 20 == old 20.
      do IO<Unit>:
        quad : T.Ui & W.Workspace & Bool & Maybe<&2, WsNet.WsMedia> <- WsNet.ws_media.jobs(M.take_job(media()), owner(), 11n, 20n, ui, workspace(), s1(), 7, evts, None{})
        finish(mode, True{}, False{}, evts, quad)
    case _:
      do IO<Unit>:
        Unit <- T.Timui.close(ui)
        IO.die(Unit, 1, "expected free|blocked|jobs-none|jobs-some")

def run_case(+mode: String) -> IO(Unit):
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    +e0 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 2)
    +e1 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 2)
    +e2 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 2)
    +e3 : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 2)
    run_mode(mode, ui, WsNet.WsEvts{e0, e1, e2, e3})

# Separate public frame/constructor retention seam. The four media cases never
# enter this mode. No production hook, helper, network, or file preview is added.
def frame_done(pair: T.Ui & T.UiKeys) -> IO(Unit):
  match pair:
    case (ui, T.UiKeys{_, _, _, _, _, _, _, _, _, _, _, _}): T.Timui.close(ui)

def frame_retain() -> IO(Unit):
  +ops : List<&2, V.DrawOp> = [V.OpBox{0, 0, 0, 0}, V.OpSplit{0, 0, 0, 0, 0}, V.OpText{0, 0, 0, 0, 0, ""}, V.OpTabs{0, 0, 0, 0, Nil{}, Nil{}, 0, 0}, V.OpLine{0, 0, 0, 0, [V.Spn{0, ""}, V.Lnk{"", ""}, V.Col{0, 0, ""}]}, V.OpImage{0, 0, 0, 0, ""}, V.OpMedia{0, 0, 0, 0, 0, 0, 0}]
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    ui2 : T.Ui <- T.Timui.view_begin(ui)
    pair : T.Ui & T.UiKeys <- T.Timui.frame(ui2, ops, "", 0, 0)
    frame_done(pair)

def frame_mode(mode: String) -> IO(Unit):
  match mode:
    case "frame-retain": frame_retain()
    case _: run_case(mode)

def args_go(retain: Bool, mode: String) -> IO(Unit):
  match retain:
    case True{}: Retain.run_retain()
    case False{}: frame_mode(mode)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+mode, Nil{}}}: args_go(String.eq(mode, "ffi-retain"), mode)
    case _: IO.die(Unit, 1, "expected mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
