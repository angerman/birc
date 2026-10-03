# SPDX-License-Identifier: Apache-2.0
# Archive reads and no-append controls; Python owns all files/helpers.
import Base
import ./expect.bend as E
import ./live_context.bend as T
import ../../src/bend/live_context.bend as C
import ../../src/bend/preferences.bend as P
import ../../src/bend/session.bend as S
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/history.bend as H

def bit(on: Bool) -> String:
  Bool.pick(String, on, "1", "0")

def base(+mode: String, path: String) -> T.Stage:
  T.observe(T.load(T.reading(T.initial(path)),
    Bool.pick(Maybe<&2, P.Preferences>, String.eq(mode, "invalid") || String.eq(mode, "absent"), None{}, Some{T.stored(Bool.not(String.eq(mode, "off")), 3)}),
    Bool.pick(U32, String.eq(mode, "invalid"), 2, 0)))

def local(stage: T.Stage) -> T.Stage:
  match stage:
    case T.Stage{ctx, +st}: T.Stage{ctx, S.session_set_client(st, Cl.client_log(S.session_cl(st), 0n, Cl.System{}, "local status"))}

def modify(+mode: String, stage: T.Stage) -> T.Stage:
  match mode:
    case "cap": T.observe(T.command(stage, "/set hist_cap 1"))
    case "offedit": T.observe(T.command(stage, "/set history off"))
    case "off": local(stage)
    case "invalid": local(stage)
    case "drop":
      match stage:
        case T.Stage{ctx, st}: local(T.Stage{ctx, S.session_cancel_reconnect(st)})
    case _: stage

def stage.ctx(stage: T.Stage) -> C.Context:
  match stage:
    case T.Stage{ctx, _}: ctx

def stage.session(stage: T.Stage) -> S.Session:
  match stage:
    case T.Stage{_, st}: st

def ready(value: C.Details) -> Bool:
  match value:
    case C.Details{_, gate, _, _, _, _}: C.gate_ready(gate)

def archive_started(value: C.Details) -> Bool:
  match value:
    case C.Details{_, _, _, _, Some{C.Archive{0n, _, _, _, _, _, _, _, True{}}}, 1n}: True{}
    case _: False{}

def no_extra(got: Maybe<&1, S.UiMsg>) -> Bool:
  match got:
    case None{}: True{}
    case _: False{}

def queued(value: C.Details) -> String:
  match value:
    case C.Details{_, _, _, _, Some{C.Archive{ticket, _, _, cap, read, _, _, _, _}}, _}: Nat.show(ticket) ++ ":" ++ U32.show(cap) ++ ":" ++ bit(read)
    case _: "none"

def marker(got: Maybe<&1, S.NetCmd>) -> U32:
  match got:
    case Some{S.Begin{gen}}: gen
    case Some{S.Cont{Nil{}}}: 0
    case _: 99

def sentinel(got: Maybe<&1, S.NetCmd>) -> Bool:
  match got:
    case Some{S.Cont{Nil{}}}: True{}
    case _: False{}

def check_tail(on: Bool, cmd: Chan(S.NetCmd)) -> IO(Unit):
  match on:
    case False{}: IO.pure(Unit, Unit{})
    case True{}:
      do IO<Unit>:
        got : Maybe<&1, S.NetCmd> <- Chan.recv(S.NetCmd, cmd)
        E.must("completion sends at most one Begin", sentinel(got))

def checkpoint(+cl: Cl.Client) -> Bool:
  String.eq(H.extract_new_history_for("irc.example:6697", cl,
    Cl.client_log(cl, 0n, Cl.Msg{}, "post completion")),
    "BIRC2\tirc.example:6697\t*server*\tMSG\t\t\tpost completion\n")

def row_text(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{Cl.Reconnect{}, _, _, _, _}, rest}: row_text(rest)
    case Con{Cl.Line{_, _, text, _, _}, rest}: text ++ "|" ++ row_text(rest)

def divider_count(lines: List<&2, Cl.Line>) -> Nat:
  match lines:
    case Nil{}: 0n
    case Con{Cl.Line{Cl.Reconnect{}, _, _, _, _}, rest}: 1n+divider_count(rest)
    case Con{_, rest}: divider_count(rest)

def server_rows(cl: Cl.Client) -> List<&2, Cl.Line>:
  match cl:
    case Cl.Client{_, _, Con{Cl.Buffer{_, _, _, lines, _, _}, _}, _, _, _, _, _}: lines
    case _: Nil{}

def report(+stage: T.Stage, begin: U32) -> IO(Unit):
  +ctx = stage.ctx(stage)
  +st = stage.session(stage)
  +cl = S.session_cl(st)
  IO.print("begin=" ++ U32.show(begin) ++ ";ready=" ++ bit(ready(C.details(ctx)))
    ++ ";allowed=" ++ bit(C.history_allowed(ctx, st)) ++ ";queued=" ++ queued(C.details(ctx))
    ++ ";rows=" ++ row_text(server_rows(cl)) ++ ";divider=" ++ Nat.show(divider_count(server_rows(cl)))
    ++ ";checkpoint=" ++ bit(checkpoint(cl)))

def finish(result: C.Context & S.Session, +cmd: Chan(S.NetCmd)) -> IO(Unit):
  match result:
    case (ctx, st):
      do IO<Unit>:
        _ : Bool <- Chan.send(S.NetCmd, cmd, S.Cont{Nil{}})
        got : Maybe<&1, S.NetCmd> <- Chan.recv(S.NetCmd, cmd)
        +begin : U32 = marker(got)
        Unit <- check_tail(Bool.not(U32.is_zero(begin)), cmd)
        Unit <- Chan.close(S.NetCmd, cmd)
        report(T.observe(T.Stage{ctx, st}), begin)

def completed(got: Maybe<&1, S.UiMsg>, +mode: String, ctx: C.Context, st: S.Session, +cmd: Chan(S.NetCmd)) -> IO(Unit):
  match got:
    case Some{S.HistoryLoaded{ticket, gen, ep, snapshot}}:
      do IO<Unit>:
        result : C.Context & S.Session <- C.history(ctx, st, 1,
          Bool.pick(U32, String.eq(mode, "wronggen"), 2, gen),
          Bool.pick(Nat, String.eq(mode, "wrongticket"), 99n, ticket),
          Bool.pick(String, String.eq(mode, "wrongep"), "IRC.EXAMPLE:6697", ep), snapshot, cmd)
        finish(result, cmd)
    case _: IO.die(Unit, 1, "expected typed archive completion")

def run(+mode: String, +path: String) -> IO(Unit):
  +original = base(mode, Bool.pick(String, String.eq(mode, "drop"), "", path))
  do IO<Unit>:
    +evt : Chan(S.UiMsg) <- Chan.new(S.UiMsg, 4)
    +cmd : Chan(S.NetCmd) <- Chan.new(S.NetCmd, 4)
    +started : C.Context <- C.start(stage.ctx(original), evt)
    # Starting the same owned request again must not spawn another archive.
    +again : C.Context <- C.start(started, evt)
    Unit <- E.must("repeated start retains one immutable owned archive", archive_started(C.details(started)) && archive_started(C.details(again)))
    first : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
    Unit <- IO.sleep(30)
    Unit <- Chan.close(S.UiMsg, evt)
    extra : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
    Unit <- E.must("repeated start posts only one archive completion", no_extra(extra))
    +modified : T.Stage = modify(mode, T.Stage{again, stage.session(original)})
    completed(first, mode, stage.ctx(modified), stage.session(modified), cmd)

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{mode, Con{path, Nil{}}}}: run(mode, path)
    case _: IO.die(Unit, 1, "expected mode and owned archive path")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
