# History enqueue must not treat a full worker channel as success.
# Overflow coalesces onto WsHot.pending (FIFO); a held worker then drains
# A then B then C. HistStop acks after the queue. Sync-append failure must
# not advance the extract baseline (rewind log_seq).
import Base
import ../../src/bend/wsnet.bend as WsNet
import ../../src/bend/workspace.bend as W
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/history.bend as Hist
import ../../src/bend/session.bend as Sess
import ../../src/bend/server_key.bend as Key

def report(result: Maybe<&2, String>) -> IO(Unit):
  match result:
    case None{}: IO.print("save=ok")
    case Some{text}: IO.print("save=error:" ++ text)

def report_bool(tag: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print(tag ++ "=yes")
    case False{}: IO.print(tag ++ "=no")

def report_pair(pair: Maybe<&2, String> & WsNet.WsHot) -> IO(WsNet.WsHot):
  match pair:
    case (+notice, +hot):
      do IO<WsNet.WsHot>:
        Unit <- report(notice)
        return hot

def report_held(tag: String, +hot: WsNet.WsHot) -> IO(WsNet.WsHot):
  do IO<WsNet.WsHot>:
    Unit <- report_bool(tag, Bool.not(String.is_empty(WsNet.ws_hot.pending_of(hot))))
    return hot

def hot_jobs.from(+empty: WsNet.WsHot, +path: String, +ch: Chan(WsNet.HistJob)) -> WsNet.WsHot:
  match empty:
    case WsNet.WsHot{+on, _, +cap, _, +warm, +frame, +ts, +reload, _}:
      WsNet.WsHot{on, path, cap, Some{ch}, warm, frame, ts, reload, ""}

def hot_jobs(+path: String, +ch: Chan(WsNet.HistJob)) -> WsNet.WsHot:
  hot_jobs.from(WsNet.ws_hot.empty(), path, ch)

def fill_one(+ch: Chan(WsNet.HistJob), +path: String, +data: String) -> IO(Bool):
  do IO<Bool>:
    p : Poll<&1, &1, Result<&1, &1, WsNet.HistJob, Unit>, WsNet.HistJob> <- Chan.try_send(WsNet.HistJob, ch, WsNet.HistJob{path, data}, 0)
    return WsNet.ws_history.enqueue_poll(p)

def overflow.pending(+path: String, +ch: Chan(WsNet.HistJob)) -> IO(WsNet.WsHot):
  +hot0 = hot_jobs(path, ch)
  do IO<WsNet.WsHot>:
    filled : Bool <- fill_one(ch, path, "line-a\n")
    Unit <- report_bool("filled", filled)
    pair_b : Maybe<&2, String> & WsNet.WsHot <- WsNet.ws_history.write(hot0, "line-b\n")
    hot1 : WsNet.WsHot <- report_pair(pair_b)
    hot1b : WsNet.WsHot <- report_held("held-b", hot1)
    pair_c : Maybe<&2, String> & WsNet.WsHot <- WsNet.ws_history.write(hot1b, "line-c\n")
    hot2 : WsNet.WsHot <- report_pair(pair_c)
    report_held("held-c", hot2)

def overflow.done(g: Maybe<&1, WsNet.WsMsg>) -> IO(Unit):
  match g:
    case Some{WsNet.WsHistDone{}}: IO.print("stop=yes")
    case _: IO.print("stop=no")

def overflow.spawn_jobs(jobs: Maybe<&2, Chan(WsNet.HistJob)>, +main: Chan(WsNet.WsMsg)) -> IO(Unit):
  match jobs:
    case None{}: IO.pure(Unit, Unit{})
    case Some{+ch}: IO.spawn(Unit, WsNet.hist_worker(ch, main))

def overflow.spawn(+hot: WsNet.WsHot, +main: Chan(WsNet.WsMsg)) -> IO(Unit):
  overflow.spawn_jobs(WsNet.ws_hot.jobs_of(hot), main)

def overflow.after(+hot: WsNet.WsHot, +main: Chan(WsNet.WsMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- overflow.spawn(hot, main)
    Unit <- WsNet.ws_history.drain_stop(hot)
    g : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
    overflow.done(g)

def overflow.go(+path: String, +ch: Chan(WsNet.HistJob)) -> IO(Unit):
  do IO<Unit>:
    hot : WsNet.WsHot <- overflow.pending(path, ch)
    main : Chan(WsNet.WsMsg) <- Chan.new(WsNet.WsMsg, 4)
    overflow.after(hot, main)

def accepted.shown(accepted: Bool, +path: String) -> IO(Unit):
  match accepted:
    case False{}:
      do IO<Unit>:
        Unit <- report_bool("accepted", False{})
        notice : Maybe<&2, String> <- WsNet.ws_history.write_accepted(False{}, path, "queued\n")
        report(notice)
    case True{}:
      do IO<Unit>:
        Unit <- report_bool("accepted", True{})
        # Channel owns the bytes: do not sync-write (file must stay absent).
        notice : Maybe<&2, String> <- WsNet.ws_history.write_accepted(True{}, path, "queued\n")
        report(notice)

def accepted.go(+path: String, +ch: Chan(WsNet.HistJob)) -> IO(Unit):
  do IO<Unit>:
    accepted : Bool <- WsNet.ws_history.enqueue(True{}, Some{ch}, path, "queued\n")
    accepted.shown(accepted, path)

def missing.hot.from(+empty: WsNet.WsHot, +path: String) -> WsNet.WsHot:
  match empty:
    case WsNet.WsHot{+on, _, +cap, _, +warm, +frame, +ts, +reload, +pending}:
      WsNet.WsHot{on, path, cap, None{}, warm, frame, ts, reload, pending}

def missing.hot(+path: String) -> WsNet.WsHot:
  missing.hot.from(WsNet.ws_hot.empty(), path)

def missing.go(+path: String) -> IO(Unit):
  do IO<Unit>:
    pair : Maybe<&2, String> & WsNet.WsHot <- WsNet.ws_history.write(missing.hot(path), "sync-only\n")
    _ : WsNet.WsHot <- report_pair(pair)
    return Unit{}

def syncfail.part_got(+ws: W.Workspace, +st: Sess.Session, got: Maybe<&2, W.Part>) -> W.Workspace:
  match got:
    case None{}: ws
    case Some{+p}:
      match p:
        case W.Part{+id, +gen, +scope, _}:
          W.replace_part(ws, W.Part{id, gen, scope, st})

def syncfail.part(+ws: W.Workspace, +st: Sess.Session) -> W.Workspace:
  syncfail.part_got(ws, st, W.find_part(ws, W.ws_current(ws)))

def syncfail.finish(got: W.Workspace & Bool & WsNet.WsHot, +ckpt: Sess.Session, +id: Key.ServerId, +ep: String) -> IO(Unit):
  match got:
    case (+ws2, rest):
      match rest:
        case (failed, _):
          +base = Cl.log_seq_of(Sess.session_cl(ckpt))
          +got_cl = Sess.session_cl(WsNet.ws_part.st(ws2, id))
          +got_seq = Cl.log_seq_of(got_cl)
          # Equal log_seq short-circuits extract; bump once so the rewound
          # baseline still exposes the unsaved row on the next save.
          +later = Cl.client_log(got_cl, 0n, Cl.Msg{}, "after-fail")
          +retry = Hist.extract_new_history_for(ep, Sess.session_cl(ckpt), later)
          do IO<Unit>:
            Unit <- report_bool("failed", failed)
            Unit <- report_bool("baseline", Nat.is_eq(got_seq, base))
            report_bool("retry", Bool.not(String.is_empty(retry)))

def syncfail.ep() -> String:
  "irc.example:6697"

def syncfail.go(+bad: String) -> IO(Unit):
  +ep = syncfail.ep()
  +old_ws = W.single_client("irc.example", 6697, False{}, Cl.init("me", "irc.example"), "#t")
  +id = W.ws_current(old_ws)
  +ckpt = WsNet.ws_part.st(old_ws, id)
  +live_cl = Cl.client_log(Sess.session_cl(ckpt), 0n, Cl.Msg{}, "unsaved-row")
  +new_st = Sess.session_set_client(ckpt, live_cl)
  +new_ws = syncfail.part(old_ws, new_st)
  +data = Hist.extract_new_history_for(ep, Sess.session_cl(ckpt), live_cl)
  do IO<Unit>:
    Unit <- report_bool("delta", Bool.not(String.is_empty(data)))
    got : W.Workspace & Bool & WsNet.WsHot <- WsNet.ws_history.async_go(False{}, data, ckpt, new_ws, id, missing.hot(bad))
    syncfail.finish(got, ckpt, id, ep)

def stop.after(+ch: Chan(WsNet.HistJob), +main: Chan(WsNet.WsMsg)) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.spawn(Unit, WsNet.hist_worker(ch, main))
    _ : Result<&1, &1, WsNet.HistJob, Unit> <- Chan.send(WsNet.HistJob, ch, WsNet.HistStop{})
    g : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
    overflow.done(g)

def stop.go() -> IO(Unit):
  do IO<Unit>:
    ch : Chan(WsNet.HistJob) <- Chan.new(WsNet.HistJob, 1)
    main : Chan(WsNet.WsMsg) <- Chan.new(WsNet.WsMsg, 4)
    stop.after(ch, main)

def run(+path: String, mode: String) -> IO(Unit):
  match mode:
    case "overflow":
      do IO<Unit>:
        ch : Chan(WsNet.HistJob) <- Chan.new(WsNet.HistJob, 1)
        overflow.go(path, ch)
    case "accepted":
      do IO<Unit>:
        ch : Chan(WsNet.HistJob) <- Chan.new(WsNet.HistJob, 1)
        accepted.go(path, ch)
    case "missing":
      missing.go(path)
    case "syncfail":
      syncfail.go(path)
    case "stop":
      stop.go()
    case _: IO.die(Unit, 1, "unknown mode")

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Con{mode, Nil{}}}}: run(path, mode)
    case _: IO.die(Unit, 1, "expected path mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
