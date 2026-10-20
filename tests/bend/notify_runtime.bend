# SPDX-License-Identifier: Apache-2.0
# N9 policy seams: View/Theme output agreement, Session dispatch of desktop
# notifications, and bounded queue/argv checks. Synthetic fixtures only.
# This fixture does not start a notification worker.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/theme.bend as Theme
import ../../src/bend/view.bend as V
import ../../src/bend/notify.bend as Notify
import ../../src/bend/notify_io.bend as NotifyIO
import ../../src/bend/session.bend as Sess
import ../../src/bend/history_startup.bend as Startup

# ---- part 1: palette/status output agreement --------------------------------
# Pin historic Dark values and compare View's Light/Mono status outputs with
# Theme.status_of. These checks do not require View to delegate to Theme.

# ---- part 2: Session dispatch -----------------------------------------------
# Live mentions/DMs build NotifyEvents with exact-spelling server scope and
# dispatch through Notify.decide; seed() from the history cutoff keeps
# restored rows silent; post-restore seed uses the final imported log_seq.

def scope() -> String:
  "irc.test:6697"

def other_scope() -> String:
  "other.test:6697"

def cl0() -> Cl.Client:
  Cl.init("me", "irc.test")

def cl_joined() -> Cl.Client:
  Feed.feed(cl0(), ":me!u@h JOIN #room")

def cl_mention() -> Cl.Client:
  Feed.feed(cl_joined(), ":bob!u@h PRIVMSG #room :hi me")

def cl_chatter() -> Cl.Client:
  Feed.feed(cl_joined(), ":bob!u@h PRIVMSG #room :hello")

def cl_dm() -> Cl.Client:
  Feed.feed(cl0(), ":bob!u@h PRIVMSG me :hello")

def cl_self() -> Cl.Client:
  Feed.feed(cl_joined(), ":me!u@h PRIVMSG #room :hi")

def cl_action() -> Cl.Client:
  Feed.feed(cl_joined(), ":bob!u@h PRIVMSG #room :" ++ SCon{Chr{1}, "ACTION waves at me" ++ SCon{Chr{1}, ""}})

def cl_notice() -> Cl.Client:
  Feed.feed(cl0(), ":bob!u@h NOTICE me :hey")

def cl_hist() -> Cl.Client:
  Feed.feed(Feed.feed(cl_mention(), ":bob!u@h PRIVMSG me :hello"), ":bob!u@h PRIVMSG #room :hello")

def cl_live() -> Cl.Client:
  Feed.feed(cl_hist(), ":bob!u@h PRIVMSG #room :are you there me")

def snapshot() -> Cl.Client:
  Feed.feed(Feed.feed(Cl.init("me", "irc.test"), ":me!u@h JOIN #room"), ":bob!u@h PRIVMSG #room :hi me")

def imported() -> Cl.Client:
  Startup.install_startup(cl0(), snapshot(), scope(), scope())

def observed(+st: Notify.State, +cl: Cl.Client, +cutoff: Nat) -> Notify.State & List<&2, Notify.Req>:
  Sess.notify_observe(st, cl, scope(), cutoff, "", "")

def after.go(pair: Notify.State & List<&2, Notify.Req>) -> Notify.State:
  match pair:
    case (st2, _): st2

def after(+st: Notify.State, +cl: Cl.Client, +cutoff: Nat) -> Notify.State:
  after.go(observed(st, cl, cutoff))

def reqs_len(pair: Notify.State & List<&2, Notify.Req>) -> String:
  match pair:
    case (_, rs): Nat.show(List.length(&2, Notify.Req, rs))

def req_titles(rs: List<&2, Notify.Req>) -> String:
  match rs:
    case Nil{}: ""
    case Con{r, t}: Notify.req_title(r) ++ ";" ++ req_titles(t)

def reqs_titles(pair: Notify.State & List<&2, Notify.Req>) -> String:
  match pair:
    case (_, rs): req_titles(rs)

def req_bodies(rs: List<&2, Notify.Req>) -> String:
  match rs:
    case Nil{}: ""
    case Con{r, t}: Notify.req_body(r) ++ ";" ++ req_bodies(t)

def reqs_bodies(pair: Notify.State & List<&2, Notify.Req>) -> String:
  match pair:
    case (_, rs): req_bodies(rs)

def sess_mention() -> Sess.Session:
  Sess.session_with_client(cl_mention(), "#room")

def stage_handed(+s: Notify.Stage) -> String:
  req_titles(Notify.stage_reqs(s))

def stage_reqs_len(+s: Notify.Stage) -> String:
  Nat.show(List.length(&2, Notify.Req, Notify.stage_reqs(s)))

def hi_shown(+got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: "unknown"
    case Some{hi}: Nat.show(hi)

# ---- part 3: bounded queue and argv seams ------------------------------------
# Check reject-new/FIFO queue bounds and helper argument construction only.
# Detached worker ownership and helper delivery are not exercised here.

def req_at(+n: Nat) -> Notify.Req:
  Notify.Req{"t" ++ Nat.show(n), "b" ++ Nat.show(n)}

def reqs_upto(left: Nat, +n: Nat) -> List<&2, Notify.Req>:
  match left:
    case 0n: Nil{}
    case 1n+p: req_at(n) <> reqs_upto(p, Nat.add(n, 1n))

def q8() -> Notify.Queue:
  Notify.enqueue_all(Notify.queue_empty(), reqs_upto(8n, 0n))

def q9() -> Notify.Queue:
  Notify.enqueue_all(Notify.queue_empty(), reqs_upto(9n, 0n))

def reqs_of(pair: Notify.State & List<&2, Notify.Req>) -> List<&2, Notify.Req>:
  match pair:
    case (_, rs): rs

def staged(pair: Notify.Queue & List<&2, Notify.Req>) -> List<&2, Notify.Req>:
  match pair:
    case (_, rs): rs

def kept(pair: Notify.Queue & List<&2, Notify.Req>) -> Notify.Queue:
  match pair:
    case (q, _): q

def staged_len(pair: Notify.Queue & List<&2, Notify.Req>) -> String:
  Nat.show(List.length(&2, Notify.Req, staged(pair)))

def kept_len(pair: Notify.Queue & List<&2, Notify.Req>) -> String:
  Nat.show(Notify.queue_len(kept(pair)))

def staged_titles(pair: Notify.Queue & List<&2, Notify.Req>) -> String:
  req_titles(staged(pair))

def chars(left: Nat) -> String:
  match left:
    case 0n: ""
    case 1n+p: "x" ++ chars(p)

def cl_longbody() -> Cl.Client:
  Feed.feed(cl_joined(), ":bob!u@h PRIVMSG #room :hi me " ++ chars(200n))

def cl_longnick() -> Cl.Client:
  Feed.feed(cl_joined(), ":" ++ chars(200n) ++ "!u@h PRIVMSG #room :hi me")

def first_title_len.of(rs: List<&2, Notify.Req>) -> String:
  match rs:
    case Nil{}: "silent"
    case Con{r, _}: Nat.show(String.length(Notify.req_title(r)))

def first_title_len(pair: Notify.State & List<&2, Notify.Req>) -> String:
  first_title_len.of(reqs_of(pair))

def first_body_len.of(rs: List<&2, Notify.Req>) -> String:
  match rs:
    case Nil{}: "silent"
    case Con{r, _}: Nat.show(String.length(Notify.req_body(r)))

def first_body_len(pair: Notify.State & List<&2, Notify.Req>) -> String:
  first_body_len.of(reqs_of(pair))

def req_head(rs: List<&2, Notify.Req>) -> Notify.Req:
  match rs:
    case Nil{}: Notify.Req{"", ""}
    case Con{r, _}: r

def arg0(xs: List<&1, String>) -> String:
  match xs:
    case Nil{}: "noargs"
    case Con{h, _}: h

def args_len(xs: List<&1, String>) -> String:
  Nat.show(List.length(&1, String, xs))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("view style msg historic", U32.show(V.style_of(Cl.Msg{})), "13158600")
    Unit <- E.must_eq("view style self historic", U32.show(V.style_of(Cl.Self{})), "5893695")
    Unit <- E.must_eq("view style system historic", U32.show(V.style_of(Cl.System{})), "10526880")
    Unit <- E.must_eq("view style action historic", U32.show(V.style_of(Cl.Action{})), "13079274")
    Unit <- E.must_eq("view style notice historic", U32.show(V.style_of(Cl.Notice{})), "8563455")
    Unit <- E.must_eq("view style error historic", U32.show(V.style_of(Cl.Error{})), "16223340")
    Unit <- E.must_eq("view style highlight historic", U32.show(V.style_of(Cl.Highlight{})), "16766720")
    Unit <- E.must_eq("view style reconnect historic", U32.show(V.style_of(Cl.Reconnect{})), "10526880")
    Unit <- E.must_eq("view style linkresult historic", U32.show(V.style_of(Cl.LinkResult{})), "10526880")
    Unit <- E.must_eq("view status online historic", U32.show(V.status_color("online · 3ms")), "5635925")
    Unit <- E.must_eq("view status offline historic", U32.show(V.status_color("offline")), "16223340")
    Unit <- E.must_eq("view status connecting historic", U32.show(V.status_color("connecting")), "15720050")
    Unit <- E.must_eq("view status other historic", U32.show(V.status_color("demo")), "10526880")
    Unit <- E.must_eq("themed light online delegates",
      U32.show(V.status_color_themed(Theme.Light{}, "online · 3ms")), U32.show(Theme.status_of(Theme.Light{}, "online · 3ms")))
    Unit <- E.must_eq("themed light offline delegates",
      U32.show(V.status_color_themed(Theme.Light{}, "offline")), U32.show(Theme.status_of(Theme.Light{}, "offline")))
    Unit <- E.must_eq("themed light connecting delegates",
      U32.show(V.status_color_themed(Theme.Light{}, "connecting")), U32.show(Theme.status_of(Theme.Light{}, "connecting")))
    Unit <- E.must_eq("themed light other delegates",
      U32.show(V.status_color_themed(Theme.Light{}, "demo")), U32.show(Theme.status_of(Theme.Light{}, "demo")))
    Unit <- E.must_eq("themed mono online delegates",
      U32.show(V.status_color_themed(Theme.Mono{}, "online · 3ms")), U32.show(Theme.status_of(Theme.Mono{}, "online · 3ms")))
    Unit <- E.must_eq("themed mono offline delegates",
      U32.show(V.status_color_themed(Theme.Mono{}, "offline")), U32.show(Theme.status_of(Theme.Mono{}, "offline")))
    Unit <- E.must_eq("themed mono connecting delegates",
      U32.show(V.status_color_themed(Theme.Mono{}, "connecting")), U32.show(Theme.status_of(Theme.Mono{}, "connecting")))
    Unit <- E.must_eq("themed mono other delegates",
      U32.show(V.status_color_themed(Theme.Mono{}, "demo")), U32.show(Theme.status_of(Theme.Mono{}, "demo")))
    Unit <- E.must_eq("scope keeps exact spelling", Sess.notify_scope("IRC.TEST", 6697), "IRC.TEST:6697")
    Unit <- E.must_eq("scope keeps root dot", Sess.notify_scope("a.", 1), "a.:1")
    Unit <- E.must_eq("scope joins port", Sess.notify_scope("h", 6667), "h:6667")
    Unit <- E.must_eq("live mention notifies", reqs_len(observed(Notify.on(), cl_mention(), 0n)), "1")
    Unit <- E.must_eq("mention title names author and target",
      reqs_titles(observed(Notify.on(), cl_mention(), 0n)), "bob in #room;")
    Unit <- E.must_eq("mention body keeps painted text",
      reqs_bodies(observed(Notify.on(), cl_mention(), 0n)), "<bob> hi me;")
    Unit <- E.must_eq("channel chatter silent", reqs_len(observed(Notify.on(), cl_chatter(), 0n)), "0")
    Unit <- E.must_eq("live dm notifies", reqs_len(observed(Notify.on(), cl_dm(), 0n)), "1")
    Unit <- E.must_eq("dm title is private",
      reqs_titles(observed(Notify.on(), cl_dm(), 0n)), "bob (private);")
    Unit <- E.must_eq("dm body keeps painted text",
      reqs_bodies(observed(Notify.on(), cl_dm(), 0n)), "<bob> hello;")
    Unit <- E.must_eq("own channel line silent", reqs_len(observed(Notify.on(), cl_self(), 0n)), "0")
    Unit <- E.must_eq("action mention notifies", reqs_len(observed(Notify.on(), cl_action(), 0n)), "1")
    Unit <- E.must_eq("peer notice stays silent", reqs_len(observed(Notify.on(), cl_notice(), 0n)), "0")
    Unit <- E.must_eq("restored rows silent",
      reqs_len(observed(Sess.notify_seed_postrestore(Notify.on(), scope(), cl_hist()), cl_hist(), 0n)), "0")
    Unit <- E.must_eq("pre-import seed does not silence restore",
      reqs_len(observed(Notify.seed(Notify.on(), scope(), Cl.log_seq_of(cl0())), imported(), 0n)), "1")
    Unit <- E.must_eq("post-restore seed silences import",
      reqs_len(observed(Sess.notify_seed_postrestore(Notify.on(), scope(), imported()), imported(), 0n)), "0")
    Unit <- E.must_eq("first live above mark notifies once",
      reqs_len(observed(after(Notify.on(), cl_hist(), 0n), cl_live(), Cl.log_seq_of(cl_hist()))), "1")
    Unit <- E.must_eq("second live observe replays silent",
      reqs_len(observed(after(after(Notify.on(), cl_hist(), 0n), cl_live(), Cl.log_seq_of(cl_hist())), cl_live(), 0n)), "0")
    Unit <- E.must_eq("same rows under fresh scope notify",
      reqs_len(Sess.notify_observe(after(Notify.on(), cl_mention(), 0n), cl_mention(), other_scope(), 0n, "", "")), "1")
    Unit <- E.must_eq("session seam dispatches one mention",
      stage_reqs_len(Sess.notify_observe_session_staged(Notify.on(), sess_mention(), 0n, Notify.queue_empty())), "1")
    Unit <- E.must_eq("session seam title exact",
      stage_handed(Sess.notify_observe_session_staged(Notify.on(), sess_mention(), 0n, Notify.queue_empty())), "bob in #room;")
    Unit <- E.must_eq("disabled stays silent", reqs_len(observed(Notify.off(), cl_mention(), 0n)), "0")
    Unit <- E.must_eq("mention advances scope mark",
      hi_shown(Notify.hi_of(after(Notify.on(), cl_mention(), 0n), scope())), "2")
    Unit <- E.must_eq("dm advances scope mark",
      hi_shown(Notify.hi_of(after(Notify.on(), cl_dm(), 0n), scope())), "1")
    Unit <- E.must_eq("history cutoff is final seq",
      hi_shown(Notify.hi_of(Sess.notify_seed_postrestore(Notify.on(), scope(), cl_hist()), scope())), "4")
    Unit <- E.must_eq("queue starts empty", Nat.show(Notify.queue_len(Notify.queue_empty())), "0")
    Unit <- E.must_eq("enqueue one keeps one",
      Nat.show(Notify.queue_len(Notify.enqueue(Notify.queue_empty(), req_at(0n)))), "1")
    Unit <- E.must_eq("enqueue nine keeps eight", Nat.show(Notify.queue_len(q9())), "8")
    Unit <- E.must_eq("full queue keeps first eight",
      staged_titles(Notify.take_jobs(q9(), 8n)), "t0;t1;t2;t3;t4;t5;t6;t7;")
    Unit <- E.must_eq("take respects bound", staged_len(Notify.take_jobs(q8(), 2n)), "2")
    Unit <- E.must_eq("take keeps remainder", kept_len(Notify.take_jobs(q8(), 2n)), "6")
    Unit <- E.must_eq("take zero stages nothing", staged_len(Notify.take_jobs(q8(), 0n)), "0")
    Unit <- E.must_eq("take zero keeps all", kept_len(Notify.take_jobs(q8(), 0n)), "8")
    Unit <- E.must_eq("take past end drains", staged_len(Notify.take_jobs(q8(), 99n)), "8")
    Unit <- E.must_eq("take past end keeps none", kept_len(Notify.take_jobs(q8(), 99n)), "0")
    Unit <- E.must_eq("staging is fifo", staged_titles(Notify.take_jobs(q8(), 2n)), "t0;t1;")
    Unit <- E.must_eq("second stage continues fifo",
      staged_titles(Notify.take_jobs(kept(Notify.take_jobs(q8(), 2n)), 2n)), "t2;t3;")
    Unit <- E.must_eq("four frames of two drain eight",
      kept_len(Notify.take_jobs(kept(Notify.take_jobs(kept(Notify.take_jobs(kept(Notify.take_jobs(q8(), 2n)), 2n)), 2n)), 2n)), "0")
    Unit <- E.must_eq("dispatched req stages once",
      Nat.show(Notify.queue_len(Notify.enqueue_all(Notify.queue_empty(),
        reqs_of(observed(Notify.on(), cl_mention(), 0n))))), "1")
    Unit <- E.must_eq("replayed dispatch stages nothing more",
      Nat.show(Notify.queue_len(Notify.enqueue_all(
        Notify.enqueue_all(Notify.queue_empty(), reqs_of(observed(Notify.on(), cl_mention(), 0n))),
        reqs_of(observed(after(Notify.on(), cl_mention(), 0n), cl_mention(), 0n))))), "1")
    Unit <- E.must_eq("pipeline body bound is 160 chars",
      first_body_len(observed(Notify.on(), cl_longbody(), 0n)), "160")
    Unit <- E.must_eq("pipeline title bound is 80 chars",
      first_title_len(observed(Notify.on(), cl_longnick(), 0n)), "80")
    Unit <- E.must_eq("staged req keeps -- argv",
      arg0(NotifyIO.args_for("notify-send", req_head(reqs_of(observed(Notify.on(), cl_mention(), 0n))))), "--")
    Unit <- E.must_eq("staged req unknown helper has no args",
      args_len(NotifyIO.args_for("x-notify", req_head(reqs_of(observed(Notify.on(), cl_mention(), 0n))))), "0")
    IO.print("notify_runtime=ok")
