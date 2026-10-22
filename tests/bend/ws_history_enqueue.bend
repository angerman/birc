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
import ../../src/bend/history_io.bend as HistIO
import ../../src/bend/live_context.bend as PrefLive
import ../../src/bend/preferences_worker.bend as PrefWorker

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
    case WsNet.WsHot{+on, _, +cap, _, +warm, +frame, +ts, +reload, _, _}:
      WsNet.WsHot{on, path, cap, Some{ch}, warm, frame, ts, reload, WsNet.ws_pend.empty(), 0n}

def hot_jobs(+path: String, +ch: Chan(WsNet.HistJob)) -> WsNet.WsHot:
  hot_jobs.from(WsNet.ws_hot.empty(), path, ch)

def fill_one(+ch: Chan(WsNet.HistJob), +path: String, +data: String) -> IO(Bool):
  do IO<Bool>:
    p : Poll<&1, &1, Result<&1, &1, WsNet.HistJob, Unit>, WsNet.HistJob> <- Chan.try_send(WsNet.HistJob, ch, WsNet.HistJob{path, data, 0n, 0n, 0n}, 0)
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
    case WsNet.WsHot{+on, _, +cap, _, +warm, +frame, +ts, +reload, +pending, _}:
      WsNet.WsHot{on, path, cap, None{}, warm, frame, ts, reload, pending, 0n}

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

# Channel accept must keep the live log_seq. Rewinding it reuses IDs.
def queued.finish(got: W.Workspace & Bool & WsNet.WsHot, +live: Cl.Client, +id: Key.ServerId) -> IO(Unit):
  match got:
    case (+ws2, rest):
      match rest:
        case (failed, _):
          +got_seq = Cl.log_seq_of(Sess.session_cl(WsNet.ws_part.st(ws2, id)))
          +want = Cl.log_seq_of(live)
          do IO<Unit>:
            Unit <- report_bool("failed", failed)
            report_bool("kept", Nat.is_eq(got_seq, want))

def queued.go(+path: String) -> IO(Unit):
  +ep = syncfail.ep()
  +old_ws = W.single_client("irc.example", 6697, False{}, Cl.init("me", "irc.example"), "#t")
  +id = W.ws_current(old_ws)
  +ckpt = WsNet.ws_part.st(old_ws, id)
  +live_cl = Cl.client_log(Sess.session_cl(ckpt), 0n, Cl.Msg{}, "queued-row")
  +new_st = Sess.session_set_client(ckpt, live_cl)
  +new_ws = syncfail.part(old_ws, new_st)
  +data = Hist.extract_new_history_for(ep, Sess.session_cl(ckpt), live_cl)
  do IO<Unit>:
    ch : Chan(WsNet.HistJob) <- Chan.new(WsNet.HistJob, 1)
    got : W.Workspace & Bool & WsNet.WsHot <- WsNet.ws_history.async_go(Bool.not(String.is_empty(data)), data, ckpt, new_ws, id, hot_jobs(path, ch))
    queued.finish(got, live_cl, id)

# Barrier ack means the queued line is already in the file.
def fence.after(flushed: WsNet.WsHot & Bool, +path: String) -> IO(Unit):
  match flushed:
    case (_, +ok):
      do IO<Unit>:
        notice : Maybe<&2, String> <- HistIO.history_append_file(path, "NEW\n")
        Unit <- report(notice)
        report_bool("fenced", ok)

def fence.send(+ch: Chan(WsNet.HistJob), +path: String) -> IO(WsNet.WsHot & Bool):
  do IO<WsNet.WsHot & Bool>:
    _ : Result<&1, &1, WsNet.HistJob, Unit> <- Chan.send(WsNet.HistJob, ch, WsNet.HistJob{path, "OLD\n", 0n, 0n, 1n})
    WsNet.ws_history.flush_before(hot_jobs(path, ch))

def fence.stop(+ch: Chan(WsNet.HistJob), +main: Chan(WsNet.WsMsg)) -> IO(Unit):
  do IO<Unit>:
    _ : Result<&1, &1, WsNet.HistJob, Unit> <- Chan.send(WsNet.HistJob, ch, WsNet.HistStop{})
    _ : Maybe<&1, WsNet.WsMsg> <- Chan.recv(WsNet.WsMsg, main)
    return Unit{}

def fence.run(+ch: Chan(WsNet.HistJob), +main: Chan(WsNet.WsMsg), +path: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.spawn(Unit, WsNet.hist_worker(ch, main))
    flushed : WsNet.WsHot & Bool <- fence.send(ch, path)
    Unit <- fence.after(flushed, path)
    fence.stop(ch, main)

def fence.go(+path: String) -> IO(Unit):
  do IO<Unit>:
    ch : Chan(WsNet.HistJob) <- Chan.new(WsNet.HistJob, 4)
    main : Chan(WsNet.WsMsg) <- Chan.new(WsNet.WsMsg, 4)
    fence.run(ch, main, path)

def stop.go() -> IO(Unit):
  do IO<Unit>:
    ch : Chan(WsNet.HistJob) <- Chan.new(WsNet.HistJob, 1)
    main : Chan(WsNet.WsMsg) <- Chan.new(WsNet.WsMsg, 4)
    stop.after(ch, main)

# 2^n copies. Depth stays small; 40000 = 2^15+2^12+2^11+2^10+2^6.
def retry.dbl(n: Nat, +s: String) -> String:
  match n:
    case 0n: s
    case 1n+p: retry.dbl(p, s ++ s)

def retry.k40() -> String:
  retry.dbl(15n, "x") ++ retry.dbl(12n, "x") ++ retry.dbl(11n, "x") ++ retry.dbl(10n, "x") ++ retry.dbl(6n, "x")

def retry.hot(+empty: WsNet.WsHot, +path: String, +ch: Chan(WsNet.HistJob), +pending: WsNet.WsPend, +hold: Nat) -> WsNet.WsHot:
  match empty:
    case WsNet.WsHot{+on, _, +cap, _, +warm, +frame, +ts, +reload, _, _}:
      WsNet.WsHot{on, path, cap, Some{ch}, warm, frame, ts, reload, pending, hold}

def retry.took(pair: W.Workspace & WsNet.WsHot) -> WsNet.WsHot:
  match pair:
    case (_, +hot): hot

def retry.report_in(inner: Maybe<&2, String> & WsNet.WsHot) -> IO(Unit):
  match inner:
    case (+notice, +hot):
      do IO<Unit>:
        Unit <- report(notice)
        IO.print("pending=" ++ Nat.show(String.length(WsNet.ws_hot.pending_of(hot))))

def retry.report(pair: (Maybe<&2, String> & WsNet.WsHot) & Bool) -> IO(Unit):
  match pair:
    case (inner, _): retry.report_in(inner)

# 40000 stored bytes, then on_fail prepends another 40000. The next
# write_chan.send into a channel with room must admit that 80000 blob:
# no notice, pending empty. A full-queue notice would leave it stuck.
def retry.after(+blob: String, +ws: W.Workspace, +id: Key.ServerId, +path: String, +ch: Chan(WsNet.HistJob)) -> IO(Unit):
  +stored : WsNet.WsPend = WsNet.WsPend{blob, 0n, 0n, 1n}
  +hot0 = retry.hot(WsNet.ws_hot.empty(), path, ch, stored, 2n)
  +hot1 = retry.took(WsNet.ws_history.on_fail(ws, id, 0n, 1n, blob, hot0))
  +pend = WsNet.ws_hot.pend_of(hot1)
  do IO<Unit>:
    Unit <- IO.print("before=" ++ Nat.show(String.length(WsNet.ws_hot.pending_of(hot1))))
    pair : (Maybe<&2, String> & WsNet.WsHot) & Bool <- WsNet.ws_history.write_chan.send(WsNet.ws_history.over_cap(String.length(WsNet.ws_pend.bytes(pend))), ch, hot1, path, pend)
    retry.report(pair)

def retry.go(+path: String) -> IO(Unit):
  +blob = retry.k40()
  +ws = W.single_client("irc.example", 6697, False{}, Cl.init("me", "irc.example"), "#t")
  +id = W.ws_current(ws)
  do IO<Unit>:
    ch : Chan(WsNet.HistJob) <- Chan.new(WsNet.HistJob, 1)
    retry.after(blob, ws, id, path, ch)

# Server 1, empty pending, hold above the failed seq. The stored record
# must keep this job's id, base, and seq, and a later mark for server 1
# must not refuse with "history part pending".
def empty_ident.eq(same_bytes: Bool, same_sid: Bool, same_base: Bool, same_seq: Bool) -> Bool:
  Bool.and(Bool.and(same_bytes, same_sid), Bool.and(same_base, same_seq))

def empty_ident.yes(+p: WsNet.WsPend, +sid: Nat, +base: Nat, +seq: Nat) -> Bool:
  match p:
    case WsNet.WsPend{+bytes, +got_sid, +got_base, +got_seq}:
      empty_ident.eq(String.eq(bytes, "ROW\n"), Nat.is_eq(got_sid, sid), Nat.is_eq(got_base, base), Nat.is_eq(got_seq, seq))

def empty_ident.notice_in(inner: Maybe<&2, String> & WsNet.WsHot) -> IO(Unit):
  match inner:
    case (+notice, _): report(notice)

def empty_ident.notice(pair: (Maybe<&2, String> & WsNet.WsHot) & Bool) -> IO(Unit):
  match pair:
    case (inner, _): empty_ident.notice_in(inner)

def empty_ident.after(+id: Key.ServerId, +base: Nat, +seq: Nat, +hold: Nat, +ws: W.Workspace, +path: String, +ch: Chan(WsNet.HistJob)) -> IO(Unit):
  +hot0 = retry.hot(WsNet.ws_hot.empty(), path, ch, WsNet.ws_pend.empty(), hold)
  +hot1 = retry.took(WsNet.ws_history.on_fail(ws, id, base, seq, "ROW\n", hot0))
  +pend = WsNet.ws_hot.pend_of(hot1)
  do IO<Unit>:
    Unit <- report_bool("ident", empty_ident.yes(pend, 1n, base, seq))
    pair : (Maybe<&2, String> & WsNet.WsHot) & Bool <- WsNet.ws_history.write_mark(hot1, "NEXT\n", 1n, base, seq)
    empty_ident.notice(pair)

def empty_ident.sid() -> Key.ServerId:
  Key.ServerId{1n}

def empty_ident.go(+path: String) -> IO(Unit):
  +id = empty_ident.sid()
  +base = W.id_base(id)
  +seq = Nat.add(base, 1n)
  +hold = Nat.add(seq, 1n)
  +ws = W.single_client("irc.example", 6697, False{}, Cl.init("me", "irc.example"), "#t")
  do IO<Unit>:
    ch : Chan(WsNet.HistJob) <- Chan.new(WsNet.HistJob, 1)
    empty_ident.after(id, base, seq, hold, ws, path, ch)

def history_off.quiet(+cl: Cl.Client) -> Cl.Client:
  Cl.set_settings(cl, Cl.set_history(Cl.get_settings(cl), False{}))

def history_off.finish(got: W.Workspace & Bool & WsNet.WsHot) -> IO(Unit):
  match got:
    case (_, rest):
      match rest:
        case (failed, _): report_bool("failed", failed)

def history_off.flags(off: Bool, same: Bool, moved: Bool, delta: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- report_bool("off", off)
    Unit <- report_bool("same", same)
    Unit <- report_bool("moved", moved)
    report_bool("delta", delta)

def history_off.save(+ctx: PrefLive.Context, +old_ws: W.Workspace, +new_ws: W.Workspace, +id: Key.ServerId, +hot: WsNet.WsHot) -> IO(Unit):
  do IO<Unit>:
    evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 1)
    got : W.Workspace & Bool & WsNet.WsHot <- WsNet.ws_history_save(ctx, old_ws, new_ws, id, hot, evt)
    history_off.finish(got)

# History disabled, same endpoint, nonempty extract. The file must stay absent.
# Flags and the save are separate continuations so a Session is not flattened
# into the same capture as both workspaces.
def history_off.go(+path: String) -> IO(Unit):
  +ep = syncfail.ep()
  +old_ws0 = W.single_client("irc.example", 6697, False{}, Cl.init("me", "irc.example"), "#t")
  +id = W.ws_current(old_ws0)
  +ckpt = WsNet.ws_part.st(old_ws0, id)
  +old_cl = history_off.quiet(Sess.session_cl(ckpt))
  +old_st = Sess.session_set_client(ckpt, old_cl)
  +old_ws = syncfail.part(old_ws0, old_st)
  +live_cl = Cl.client_log(old_cl, 0n, Cl.Msg{}, "off-row")
  +new_st = Sess.session_set_client(old_st, live_cl)
  +new_ws = syncfail.part(old_ws, new_st)
  +data = Hist.extract_new_history_for(ep, old_cl, live_cl)
  +ctx = PrefLive.initial(PrefWorker.Options{False{}, False{}, False{}, False{}}, new_st, 0, path)
  +hot = missing.hot(path)
  off = Bool.not(Cl.settings_history(Cl.get_settings(live_cl)))
  same = String.eq(PrefLive.endpoint(old_st), PrefLive.endpoint(new_st))
  moved = Bool.not(Nat.is_eq(Cl.log_seq_of(old_cl), Cl.log_seq_of(live_cl)))
  delta = Bool.not(String.is_empty(data))
  do IO<Unit>:
    Unit <- history_off.flags(off, same, moved, delta)
    history_off.save(ctx, old_ws, new_ws, id, hot)

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
    case "queued":
      queued.go(path)
    case "fence":
      fence.go(path)
    case "stop":
      stop.go()
    case "retry":
      retry.go(path)
    case "ident":
      empty_ident.go(path)
    case "off":
      history_off.go(path)
    case _: IO.die(Unit, 1, "unknown mode")

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Con{mode, Nil{}}}}: run(path, mode)
    case _: IO.die(Unit, 1, "expected path mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
