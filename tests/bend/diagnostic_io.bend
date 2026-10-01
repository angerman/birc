# Safe helper completions notify once; failed saves remain outside history.
import Base
import ./expect.bend as E
import ../../src/bend/net.bend as Net
import ../../src/bend/session.bend as Sess
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/history.bend as H

def no_event(got: Maybe<&1, Sess.UiMsg>) -> Bool:
  match got:
    case None{}: True{}
    case _: False{}

def error_text(got: Maybe<&1, Sess.UiMsg>) -> String:
  match got:
    case Some{Sess.UiError{text}}: text
    case _: "wrong event"

def unchanged(status: Sess.Session & Bool, +old: Cl.Client) -> IO(Unit):
  match status:
    case (+st, repaint):
      do IO<Unit>:
        Unit <- E.must("successful save schedules no repaint", Bool.not(repaint))
        Unit <- E.must("successful save does not add a diagnostic", Nat.is_eq(Cl.log_seq_of(Sess.session_cl(st)), Cl.log_seq_of(old)))
        return Unit{}

def failed(status: Sess.Session & Bool, +old: Cl.Client) -> IO(Unit):
  match status:
    case (+st, repaint):
      +cl = Sess.session_cl(st)
      do IO<Unit>:
        Unit <- E.must("failed save schedules one repaint", repaint)
        Unit <- E.must_eq("failed save does not enter chat", H.extract_new_history_for("s:6667", old, cl), "")
        Unit <- E.must_eq("failed save does not steal focus", Cl.active_buf_name(cl), "server")
        Unit <- E.must_eq("failed save preserves connection", Sess.net_label(Sess.session_net(st)), "connecting")
        Unit <- unchanged(Net.history_notice(st, None{}), cl)
        return Unit{}

def run() -> IO(Unit):
  +st = Sess.session0("me", "s", "#t")
  +cl = Sess.session_cl(st)
  do IO<Unit>:
    Unit <- unchanged(Net.history_notice(st, None{}), cl)
    Unit <- failed(Net.history_notice(st, Some{"history save open failed (5)"}), cl)
    # None never fills even a one-slot channel; a failure produces one UiError.
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 1)
    Unit <- Net.helper_notify(None{}, Some{evt})
    Unit <- Net.launch_result(Done{(7, ("private stdout", "https://unused.invalid/secret stderr"))}, Some{evt})
    got : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    Unit <- E.must_eq("opener exit only", error_text(got), "cannot open link: opener failed (exit 7)")
    Unit <- Net.launch_result(Fail{(5, "private host diagnostic")}, Some{evt})
    got : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    Unit <- E.must_eq("opener OS code only", error_text(got), "cannot open link: opener failed (OS 5)")
    Unit <- Net.launch_result(Done{(0, ("ignored", "ignored"))}, Some{evt})
    Unit <- Net.helper_notify(Some{"no receiver"}, None{})
    Unit <- Chan.close(Sess.UiMsg, evt)
    quiet : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    Unit <- E.must("success emits no error", no_event(quiet))
    IO.print("diagnostic_io=ok\n")

def main() -> IO(Unit):
  run()
