# SPDX-License-Identifier: Apache-2.0
# Actual last-frame callback: accepted input needs a later paint even when
# native input is drained. No frame, tty watcher, or public network is needed.
import Base
import ./expect.bend as E
import ../../src/bend/net.bend as Net
import ../../src/bend/session.bend as S
import ../../src/bend/timui.bend as T
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/app.bend as App

def same(+a: Bool, +b: Bool) -> Bool:
  (a && b) || (Bool.not(a) && Bool.not(b))

def no_event(got: Maybe<&1, S.UiMsg>) -> Bool:
  match got:
    case None{}: True{}
    case _: False{}

def continuation(got: Maybe<&1, S.UiMsg>) -> Bool:
  match got:
    case Some{S.UiContinue{}}: True{}
    case _: False{}

def has_ack(got: Maybe<&1, Unit>) -> Bool:
  match got:
    case Some{_}: True{}
    case _: False{}

def output(got: Maybe<&1, S.NetCmd>, sent: Bool) -> Bool:
  match got:
    case None{}: Bool.not(sent)
    case Some{S.Cont{Con{"NOTICE peer :owned", Nil{}}}}: sent
    case _: False{}

def stopped(net: S.NetState, halt: Bool) -> Bool:
  match net:
    case S.Connecting{}: Bool.not(halt)
    case S.Stopping{wait}: halt && Bool.not(wait)
    case _: False{}

def check_events(+evt: Chan(S.UiMsg), more: Bool) -> IO(Unit):
  match more:
    case True{}:
      do IO<Unit>:
        first : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
        Unit <- E.must("last-frame paint uses the coalesced continuation", continuation(first))
        again : Bool <- Net.more_schedule(True{}, False{}, True{}, evt)
        Unit <- E.must("a queued repaint remains coalesced", again)
        Unit <- Chan.close(S.UiMsg, evt)
        extra : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
        E.must("last-frame repaint schedules no extra event", no_event(extra))
    case False{}:
      do IO<Unit>:
        Unit <- Chan.close(S.UiMsg, evt)
        quiet : Maybe<&1, S.UiMsg> <- Chan.recv(S.UiMsg, evt)
        E.must("idle final frame emits no synthetic event", no_event(quiet))

def checked.got(
  ui: T.Ui, +st: S.Session, gen: U32, +more: Bool,
  +evt: Chan(S.UiMsg), +cmd: Chan(S.NetCmd), +ack: Chan(Unit),
  +want_more: Bool, +is_key: Bool, +halt: Bool, +sent: Bool, +tag: String
) -> IO(Unit):
  do IO<Unit>:
    Unit <- T.Timui.close(ui)
    Unit <- E.must(tag ++ ": final callback requests the required paint", same(more, want_more))
    Unit <- E.must(tag ++ ": final callback keeps the connection generation", U32.is_eq(gen, 7))
    Unit <- E.must(tag ++ ": accepted setting is preserved", Bool.not(Cl.settings_bell(Cl.get_settings(S.session_cl(st)))))
    Unit <- E.must(tag ++ ": halt policy is preserved", stopped(S.session_net(st), halt))
    Unit <- Chan.close(Unit, ack)
    first_ack : Maybe<&1, Unit> <- Chan.recv(Unit, ack)
    Unit <- E.must(tag ++ ": only the watcher key is acknowledged", same(has_ack(first_ack), is_key))
    extra_ack : Maybe<&1, Unit> <- Chan.recv(Unit, ack)
    Unit <- E.must(tag ++ ": final callback sends at most one ACK", Bool.not(has_ack(extra_ack)))
    Unit <- Chan.close(S.NetCmd, cmd)
    first_cmd : Maybe<&1, S.NetCmd> <- Chan.recv(S.NetCmd, cmd)
    Unit <- E.must(tag ++ ": command emits exactly its owned output", output(first_cmd, sent))
    extra_cmd : Maybe<&1, S.NetCmd> <- Chan.recv(S.NetCmd, cmd)
    Unit <- E.must(tag ++ ": final callback does not duplicate output", output(extra_cmd, False{}))
    pending : Bool <- Net.more_schedule(False{}, False{}, more, evt)
    Unit <- E.must(tag ++ ": final callback reaches the real scheduler", same(pending, want_more))
    check_events(evt, want_more)

def checked(
  acc: T.Ui & S.Session & U32 & Bool,
  evt: Chan(S.UiMsg), cmd: Chan(S.NetCmd), ack: Chan(Unit),
  want_more: Bool, is_key: Bool, halt: Bool, sent: Bool, tag: String
) -> IO(Unit):
  match acc:
    case (ui, st, gen, more):
      checked.got(ui, st, gen, more, evt, cmd, ack, want_more, is_key, halt, sent, tag)

def changed() -> S.Session:
  +st = S.session0("me", "irc.example", "#t")
  +cl = S.session_cl(st)
  S.session_set_client(st, Cl.set_settings(cl, Cl.set_bell(Cl.get_settings(cl), False{})))

def run_case(+hot: Bool, +more: Bool, +want_more: Bool, +is_key: Bool, +halt: Bool, +sent: Bool, +tag: String) -> IO(Unit):
  +outs = Bool.pick(List<&2, String>, sent, "NOTICE peer :owned" <> Nil{}, Nil{})
  do IO<Unit>:
    ui : T.Ui <- IO.try(T.Ui, T.Timui.open())
    +evt : Chan(S.UiMsg) <- Chan.new(S.UiMsg, 1)
    +cmd : Chan(S.NetCmd) <- Chan.new(S.NetCmd, 1)
    +ack : Chan(Unit) <- Chan.new(Unit, 1)
    Net.on_frame.final((Net.apply_pack(ui, changed(), S.Cont{outs}, halt, more), hot), is_key, evt, cmd, ack, 7,
      acc => checked(acc, evt, cmd, ack, want_more, is_key, halt, sent, tag))

def run() -> IO(Unit):
  do IO<Unit>:
    Unit <- run_case(False{}, False{}, False{}, False{}, False{}, False{}, "idle")
    Unit <- run_case(False{}, True{}, True{}, False{}, False{}, False{}, "native tail")
    Unit <- run_case(True{}, True{}, True{}, False{}, False{}, False{}, "hot native tail")
    Unit <- run_case(False{}, False{}, False{}, True{}, False{}, True{}, "watcher output")
    Unit <- run_case(False{}, False{}, False{}, True{}, True{}, False{}, "halt")
    Unit <- run_case(True{}, False{}, False{}, True{}, True{}, False{}, "halt suppresses deferred hot")
    Unit <- run_case(True{}, True{}, True{}, True{}, True{}, False{}, "halt preserves native tail")
    # (-) The last accepted Enter/navigation had no native tail. Dropping hot
    # let the UI park with changed state and the preceding frame's pixels.
    Unit <- run_case(True{}, False{}, True{}, True{}, False{}, False{}, "drained hot frame")
    IO.print("\ndeferred_frame=ok cases=8")

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Nil{}}: run()
    # Match shutdown_flush's fixture-only retention seam: thin TimUI FFI
    # needs the complete production dispatcher CIDs. The guard uses no args
    # and never executes this explicit arm, frame, watcher, or network loop.
    case Con{_, Con{"--retain-app", Nil{}}}: App.main()
    case _: IO.die(Unit, 2, "deferred_frame expects no arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
