# History enqueue must not treat a full worker channel as success.
# Fill the capacity-1 jobs channel, then offer further records: they must
# land via the sync fallback (ws_history.write), never be discarded.
# Sync-append failure must not advance the extract baseline (rewind log_seq).
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

def fill_one(+ch: Chan(WsNet.HistJob), +path: String) -> IO(Bool):
  do IO<Bool>:
    p : Poll<&1, &1, Result<&1, &1, WsNet.HistJob, Unit>, WsNet.HistJob> <- Chan.try_send(WsNet.HistJob, ch, WsNet.HistJob{path, "held\n"}, 0)
    return WsNet.ws_history.enqueue_poll(p)

def overflow.go(+path: String, +ch: Chan(WsNet.HistJob)) -> IO(Unit):
  do IO<Unit>:
    filled : Bool <- fill_one(ch, path)
    Unit <- report_bool("filled", filled)
    notice : Maybe<&2, String> <- WsNet.ws_history.write(True{}, Some{ch}, path, "line-a\n")
    Unit <- report(notice)
    notice2 : Maybe<&2, String> <- WsNet.ws_history.write(True{}, Some{ch}, path, "line-b\n")
    report(notice2)

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

def missing.go(+path: String) -> IO(Unit):
  do IO<Unit>:
    notice : Maybe<&2, String> <- WsNet.ws_history.write(True{}, None{}, path, "sync-only\n")
    report(notice)

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
    got : W.Workspace & Bool & WsNet.WsHot <- WsNet.ws_history.async_go(False{}, None{}, bad, data, ckpt, new_ws, id, WsNet.ws_hot.empty())
    syncfail.finish(got, ckpt, id, ep)

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
    case _: IO.die(Unit, 1, "unknown mode")

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Con{mode, Nil{}}}}: run(path, mode)
    case _: IO.die(Unit, 1, "expected path mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
