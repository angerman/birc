# Safe helper completions notify once; failed saves remain outside history.
# HistIO save failure must rewind log_seq to the pre-save checkpoint so
# unsaved chat IDs stay visible to the next extract (ws syncfail port).
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
    case (+st0, repaint):
      +st = Net.history_kept(st0, True{}, Cl.log_seq_of(old))
      +cl = Sess.session_cl(st)
      do IO<Unit>:
        Unit <- E.must("failed save schedules one repaint", repaint)
        Unit <- E.must("failed save rewinds log_seq to pre-save checkpoint", Nat.is_eq(Cl.log_seq_of(cl), Cl.log_seq_of(old)))
        Unit <- E.must_eq("failed save does not enter chat", H.extract_new_history_for("s:6667", old, cl), "")
        Unit <- E.must_eq("failed save does not steal focus", Cl.active_buf_name(cl), "server")
        Unit <- E.must_eq("failed save preserves connection", Sess.net_label(Sess.session_net(st)), "connecting")
        Unit <- unchanged(Net.history_notice(st, None{}), cl)
        return Unit{}

# − without history_kept: diagnostic advances seq past unsaved IDs.
# + with history_kept: baseline rewinds; retry extract still sees the row.
def syncfail.ep() -> String:
  "irc.example:6697"

def syncfail.finish(+st: Sess.Session, failed: Bool, +ckpt: Cl.Client, +ep: String) -> IO(Unit):
  +base = Cl.log_seq_of(ckpt)
  +got = Sess.session_cl(st)
  +got_seq = Cl.log_seq_of(got)
  +later = Cl.client_log(got, 0n, Cl.Msg{}, "after-fail")
  +retry = H.extract_new_history_for(ep, ckpt, later)
  do IO<Unit>:
    Unit <- E.must("syncfail failed", failed)
    Unit <- E.must("syncfail baseline", Nat.is_eq(got_seq, base))
    Unit <- E.must("syncfail retry", Bool.not(String.is_empty(retry)))
    return Unit{}

def syncfail.after(status: Sess.Session & Bool, +base: Nat, +ckpt: Cl.Client, +ep: String) -> IO(Unit):
  match status:
    case (+noted, +failed):
      syncfail.finish(Net.history_kept(noted, failed, base), failed, ckpt, ep)

def syncfail.go() -> IO(Unit):
  +ep = syncfail.ep()
  +st0 = Sess.session0("me", "irc.example", "#t")
  +ckpt = Sess.session_cl(st0)
  +base = Cl.log_seq_of(ckpt)
  +live = Cl.client_log(ckpt, 0n, Cl.Msg{}, "unsaved-row")
  +st_live = Sess.session_set_client(st0, live)
  syncfail.after(Net.history_notice(st_live, Some{"history save open failed (5)"}), base, ckpt, ep)

def run() -> IO(Unit):
  +st = Sess.session0("me", "s", "#t")
  +cl = Sess.session_cl(st)
  do IO<Unit>:
    Unit <- unchanged(Net.history_notice(st, None{}), cl)
    Unit <- failed(Net.history_notice(st, Some{"history save open failed (5)"}), cl)
    Unit <- syncfail.go()
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
