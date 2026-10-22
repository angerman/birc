# Safe helper completions notify once; failed saves remain outside history.
# HistIO save failure must rewind log_seq to the pre-save checkpoint so
# unsaved chat IDs stay visible to the next extract (ws syncfail port).
import Base
import ./expect.bend as E
import ../../src/bend/net.bend as Net
import ../../src/bend/session.bend as Sess
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/history.bend as H
import ../../src/bend/history_io.bend as HistIO

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

def rewind_log_ids.show(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, _, _, _, id}, +rest}:
      Nat.show(id) ++ "|" ++ rewind_log_ids.show(rest)

# Log, rewind log_seq to the pre-log value, log again. The stored row keeps
# its id, so the next allocation must not reuse it.
def rewind_log_ids.client() -> Cl.Client:
  +base = Cl.init("me", "s")
  +first = Cl.client_log(base, 0n, Cl.Msg{}, "one")
  Cl.client_log(Cl.set_log_seq(first, Cl.log_seq_of(base)), 0n, Cl.Msg{}, "two")

# One saved channel row is already in the file. One newer row sits on the
# pre-dial client with log_seq rewound to that checkpoint, the same baseline
# maybe_save_history uses (id > seq). A different host must append only the
# newer row under the old endpoint. The same host skips that prior append;
# the ordinary extract still writes the newer row once.
def d17.mark_kept() -> String:
  "d17-kept"

def d17.mark_fresh() -> String:
  "d17-fresh"

def d17.host_old() -> String:
  "old.example"

def d17.host_new() -> String:
  "other.example"

def d17.room() -> String:
  "#room"

def d17.drop_text(empty: Bool, cl: Cl.Client) -> Cl.Client:
  match empty:
    case False{}: cl
    case True{}: cl

def d17.log_at(got: Cl.Client & Maybe<&2, Nat>, text: String) -> Cl.Client:
  match got:
    case (+cl, Some{i}): Cl.client_log(cl, i, Cl.Msg{}, text)
    case (+cl, None{}): d17.drop_text(String.is_empty(text), cl)

def d17.log(cl: Cl.Client, text: String) -> Cl.Client:
  d17.log_at(Cl.buf_get(cl, d17.room(), True{}, True{}), text)

def d17.client_saved() -> Cl.Client:
  d17.log(Cl.init("me", d17.host_old()), d17.mark_kept())

def d17.client_live() -> Cl.Client:
  Cl.set_log_seq(d17.log(d17.client_saved(), d17.mark_fresh()), 1n)

def d17.live_session() -> Sess.Session:
  Sess.session_with_client(d17.client_live(), d17.room())

def d17.bufs(cl: Cl.Client) -> List<&2, Cl.Buffer>:
  match cl:
    case Cl.Client{_, _, bufs, _, _, _, _, _, _}: bufs

def d17.seed_text(ep: String) -> String:
  H.serialize_entries(H.new_entries(d17.bufs(d17.client_saved()), 0n, True{}), ep)

def d17.checkpoint.seq(scan: Bool, seq: Nat) -> Nat:
  match scan:
    case False{}: seq
    case True{}: seq

def d17.checkpoint(fold: Bool & Nat) -> Nat:
  match fold:
    case (scan, seq): d17.checkpoint.seq(scan, seq)

def d17.line_both(+line: String, endpoint: String, mark: String) -> Bool:
  String.contains(line, endpoint) && String.contains(line, mark)

def d17.any_go(xs: List<&2, String>, +endpoint: String, +mark: String, found: Bool) -> Bool:
  match xs:
    case Nil{}: found
    case Con{line, t}: d17.any_go(t, endpoint, mark, found || d17.line_both(line, endpoint, mark))

def d17.kept(+text: String, endpoint: String, mark: String) -> Bool:
  d17.any_go(String.split(text, Chr{10}), endpoint, mark, False{})

def d17.count_hit(hit: Bool, n: Nat) -> Nat:
  match hit:
    case True{}: 1n+n
    case False{}: n

def d17.count_go(xs: List<&2, String>, +mark: String, n: Nat) -> Nat:
  match xs:
    case Nil{}: n
    case Con{line, t}: d17.count_go(t, mark, d17.count_hit(String.contains(line, mark), n))

def d17.count(text: String, mark: String) -> Nat:
  d17.count_go(String.split(text, Chr{10}), mark, 0n)

def d17.once(text: String, mark: String) -> Bool:
  Nat.is_eq(d17.count(text, mark), 1n)

def d17.path_ok(+path: String) -> Bool:
  String.starts_with(path, "build/d17.") && Bool.not(String.contains(path, ".birc_history.log"))

def d17.none() -> List<&2, Nat>:
  Nil{}

def d17.seed_ok(got: HistIO.Append) -> IO(Unit):
  match got:
    case HistIO.Ok{}: IO.pure(Unit, Unit{})
    case _: IO.die(Unit, 1, "history seed failed")

def d17.saved_ok(notice: Maybe<&2, String>) -> IO(Unit):
  match notice:
    case None{}: IO.pure(Unit, Unit{})
    case Some{_}: IO.die(Unit, 1, "history save failed")

def d17.dial(+st: Sess.Session, host: String) -> Sess.Session:
  Sess.session_on_cmd(st, Sess.Dial{host, Sess.session_port(st), 0, Cl.nick_of(Sess.session_cl(st))})

def d17.save(path: String, +st: Sess.Session, host: String) -> IO(Unit):
  +old_cl = Sess.session_cl(st)
  +next = d17.dial(st, host)
  +new_cl = Sess.session_cl(next)
  do IO<Unit>:
    notice : Maybe<&2, String> <- Net.live_step.next.save_history(True{}, path, Net.session_endpoint(st), Net.session_endpoint(next), d17.checkpoint(Net.live_step.next.fold(old_cl, new_cl, False{})), old_cl, new_cl, d17.none())
    d17.saved_ok(notice)

def d17.assert_changed(+text: String, ep: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("endpoint change keeps the unsaved channel row", d17.kept(text, ep, d17.mark_fresh()))
    Unit <- E.must("endpoint change does not rewrite the saved row", d17.once(text, d17.mark_kept()))
    E.must("endpoint change writes the unsaved row once", d17.once(text, d17.mark_fresh()))

def d17.assert_same(+text: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("same endpoint does not duplicate the saved row", d17.once(text, d17.mark_kept()))
    E.must("same endpoint writes the unsaved row once", d17.once(text, d17.mark_fresh()))

def d17.finish(changed: String, same_text: String, ep: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- d17.assert_changed(changed, ep)
    d17.assert_same(same_text)

def d17.read_got(r: Result<&1, &1, U32 & String, String>, f: File) -> IO(String):
  match r:
    case Fail{_}:
      do IO<String>:
        Unit <- File.close(f)
        IO.die(String, 1, "history read failed")
    case Done{+text}:
      do IO<String>:
        Unit <- File.close(f)
        return text

def d17.read_pair(pair: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  match pair:
    case (f, r): d17.read_got(r, f)

def d17.read_open(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Fail{_}: IO.die(String, 1, "history file missing")
    case Done{f}:
      do IO<String>:
        pair : File & Result<&1, &1, U32 & String, String> <- File.read(f, 1048576)
        d17.read_pair(pair)

def d17.read(path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    d17.read_open(r)

def d17.one(+path: String, st: Sess.Session, host: String, seed: String) -> IO(Unit):
  do IO<Unit>:
    got : HistIO.Append <- HistIO.history_append_file.claim(path, seed)
    Unit <- d17.seed_ok(got)
    d17.save(path, st, host)

def d17.read_both(changed_path: String, same_path: String, ep: String) -> IO(Unit):
  do IO<Unit>:
    changed : String <- d17.read(changed_path)
    same_text : String <- d17.read(same_path)
    d17.finish(changed, same_text, ep)

def d17.go(+dir: String, +st: Sess.Session, ep: String, +seed: String) -> IO(Unit):
  +changed = dir ++ "/changed.log"
  +samep = dir ++ "/same.log"
  do IO<Unit>:
    Unit <- d17.one(changed, st, d17.host_new(), seed)
    Unit <- d17.one(samep, st, d17.host_old(), seed)
    d17.read_both(changed, samep, ep)

def d17.temp_use(+path: String) -> IO(Unit):
  +st = d17.live_session()
  +ep = Net.session_endpoint(st)
  seed = d17.seed_text(ep)
  do IO<Unit>:
    Unit <- E.must("history path stays out of the home log", d17.path_ok(path))
    d17.go(path, st, ep, seed)

def d17.temp_require(empty: Bool, +path: String) -> IO(Unit):
  match empty:
    case True{}: IO.die(Unit, 1, "temp directory failed")
    case False{}: d17.temp_use(path)

def d17.temp_from(+path: String) -> IO(Unit):
  d17.temp_require(String.is_empty(path), path)

def d17.mktemp_args() -> List<&1, String>:
  "-d" <> "build/d17.XXXXXX" <> Nil{}

def d17.tmp_stdout(rest: String & String) -> String:
  match rest:
    case (+out, _): out

def d17.tmp_done(pair: U32 & (String & String)) -> String:
  match pair:
    case (_, rest): d17.tmp_stdout(rest)

def d17.tmp_got(got: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match got:
    case Fail{_}: ""
    case Done{pair}: d17.tmp_done(pair)

def d17.chomp_on(nl: Bool, +s: String) -> String:
  match nl:
    case True{}: String.take(s, Nat.sub(String.length(s), 1n))
    case False{}: s

def d17.chomp(+s: String) -> String:
  d17.chomp_on(String.ends_with(s, "\n"), s)

def d17.temp_dir() -> IO(Unit):
  do IO<Unit>:
    got : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("mktemp", d17.mktemp_args(), "", 4096, 5000)
    d17.temp_from(d17.chomp(d17.tmp_got(got)))

def run() -> IO(Unit):
  +st = Sess.session0("me", "s", "#t")
  +cl = Sess.session_cl(st)
  do IO<Unit>:
    Unit <- d17.temp_dir()
    Unit <- unchanged(Net.history_notice(st, None{}), cl)
    Unit <- failed(Net.history_notice(st, Some{"history save open failed (5)"}), cl)
    Unit <- syncfail.go()
    Unit <- E.must_eq("rewound log line ids differ", rewind_log_ids.show(Cl.active_buf_lines(rewind_log_ids.client())), "1|2|")
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
