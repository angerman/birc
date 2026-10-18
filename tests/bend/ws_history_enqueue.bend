# History enqueue must not treat a full worker channel as success.
# Fill the capacity-1 jobs channel, then offer further records: they must
# land via the sync fallback (ws_history.write), never be discarded.
import Base
import ../../src/bend/wsnet.bend as WsNet

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
    case _: IO.die(Unit, 1, "unknown mode")

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Con{mode, Nil{}}}}: run(path, mode)
    case _: IO.die(Unit, 1, "expected path mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
