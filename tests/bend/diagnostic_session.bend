# SPDX-License-Identifier: Apache-2.0
# App-session diagnostics survive endpoints, not chat/history marker policy.
import Base
import ./expect.bend as E
import ./view_preds.bend as VP
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/diagnostic.bend as D
import ../../src/bend/history.bend as H
import ../../src/bend/session.bend as Sess
import ../../src/bend/view.bend as V

def log_lines.from(bufs: List<&2, Cl.Buffer>) -> List<&2, Cl.Line>:
  match bufs:
    case Con{Cl.Buffer{_, _, _, lines, _, _, _, _}, Nil{}}: lines
    case _: Nil{}

def log_lines(cl: Cl.Client) -> List<&2, Cl.Line>:
  log_lines.from(Cl.log_buffers(cl))

def log_count(cl: Cl.Client) -> Nat:
  List.length(&2, Cl.Line, log_lines(cl))

def last_line(lines: List<&2, Cl.Line>) -> Cl.Line:
  match lines:
    case Nil{}: Cl.Line{Cl.Error{}, "", "missing", "", 0n}
    case Con{h, Nil{}}: h
    case Con{_, tail}: last_line(tail)

def signature(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, ts, text, author, id}, tail}:
      ts ++ "|" ++ text ++ "|" ++ author ++ "|" ++ Nat.show(id) ++ ";" ++ signature(tail)

def names(bufs: List<&2, Cl.Buffer>) -> String:
  match bufs:
    case Nil{}: ""
    case Con{Cl.Buffer{name, _, _, _, _, _, _, _}, tail}: name ++ ";" ++ names(tail)

def client_names(cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, bufs, _, _, _, _, _}: names(bufs)

def chats() -> Cl.Client:
  +start = Cl.set_now(Cl.client_set_sasl(Cl.init_with_cap("probe", "a.example", 12), "synth-user", "synth-secret"), "12:34:56")
  +fed = Feed.feed_all(Cl.client_log(start, 0n, Cl.System{}, "old server history"),
    [":probe!u@h JOIN #old", ":alice!u@h PRIVMSG #old :old chat history"])
  Cl.set_auth(Cl.set_active(fed, 1n), Cl.AuthResult{})

def with_log() -> Cl.Client:
  Cl.diagnostic(chats(), Cl.System{}, "persistent diagnostic")

def fill_notices(+n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p: fill_notices(p, Cl.diagnostic(cl, Cl.System{}, "notice " ++ Nat.show(n)))

def full_log() -> Cl.Client:
  fill_notices(D.ROW_CAP(), chats())

# The two independent negative cases are reported together. On the unfixed
# paths they are 129 and 3: a reconnect row exceeds the diagnostic cap, while
# an unrelated history cap trims the app-session log to two rows plus a marker.
def marker_history_counts(+cl: Cl.Client) -> String:
  Nat.show(log_count(H.add_markers_cl(cl, "13:00:00"))) ++ ","
    ++ Nat.show(log_count(H.apply_history(cl, Nil{}, "13:00:00", 2)))

def marker_line(line: Cl.Line) -> Bool:
  match line:
    case Cl.Line{Cl.Reconnect{}, _, text, _, _}: String.eq(text, "13:00:00")
    case _: False{}

def ordinary_marker(old: List<&2, Cl.Line>, +new: List<&2, Cl.Line>) -> Bool:
  Nat.is_eq(List.length(&2, Cl.Line, new), 1n+List.length(&2, Cl.Line, old)) && marker_line(last_line(new))

def notice_line(line: Cl.Line, expected: String, id: Nat) -> Bool:
  match line:
    case Cl.Line{Cl.System{}, ts, text, author, actual}:
      String.eq(ts, "12:34:56") && String.eq(text, expected)
        && String.is_empty(author) && Nat.is_eq(actual, id)
    case _: False{}

def phase_result(phase: Cl.AuthPhase) -> Bool:
  match phase:
    case Cl.AuthResult{}: True{}
    case _: False{}

def phase_idle(phase: Cl.AuthPhase) -> Bool:
  match phase:
    case Cl.AuthIdle{}: True{}
    case _: False{}

def endpoint_metadata(+cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{+nick, +host, _, +active, +now, +stg, _, _}:
      String.eq(nick, "probe") && String.eq(host, "b.example") && Nat.is_eq(active, 0n)
        && String.eq(now, "12:34:56") && U32.is_eq(Cl.settings_hist_cap(stg), 12)
        && String.is_empty(Cl.settings_sasl_user(stg))
        && String.is_empty(Cl.settings_sasl_pass(stg)) && phase_idle(Cl.get_auth(cl))

def no_log_notice(+cl: Cl.Client) -> IO(Unit):
  +next = Cl.diagnostic_notice(cl, Cl.System{}, "connection established")
  do IO<Unit>:
    Unit <- E.must_eq("notice remains lazy", client_names(next), client_names(cl))
    Unit <- E.must_eq("notice keeps chat rows", CL.buf_texts(next, 1n), CL.buf_texts(cl, 1n))
    Unit <- E.must("no log notice spends no event ID", Nat.is_eq(Cl.log_seq_of(next), Cl.log_seq_of(cl)))
    Unit <- E.must("no log notice preserves focus", Nat.is_eq(Cl.active_of(next), Cl.active_of(cl)))
    IO.pure(Unit, Unit{})

def existing_log_notice(+cl: Cl.Client) -> IO(Unit):
  +next = Cl.diagnostic_notice(cl, Cl.System{}, "stage synth-user synth-secret https://offline.invalid/private")
  do IO<Unit>:
    Unit <- E.must_eq("notice keeps buffer list", client_names(next), client_names(cl))
    Unit <- E.must("notice preserves chat focus", Nat.is_eq(Cl.active_of(next), 1n))
    Unit <- E.must_eq("notice keeps ordinary chat", CL.buf_texts(next, 1n), CL.buf_texts(cl, 1n))
    Unit <- E.must("notice appends one row", Nat.is_eq(log_count(next), 1n+log_count(cl)))
    Unit <- E.must("notice is safe and gets one stable ID",
      notice_line(last_line(log_lines(next)), "stage [redacted] [redacted] [url]", 1n+Cl.log_seq_of(cl)))
    IO.pure(Unit, Unit{})

def endpoints(+cl: Cl.Client) -> IO(Unit):
  +changed = Sess.endpoint_client(cl, "b.example", 6667, 6667)
  +port_changed = Sess.endpoint_client(cl, "a.example", 6667, 6668)
  +same = Sess.endpoint_client(cl, "A.EXAMPLE", 6667, 6667)
  +credential_same = Sess.endpoint_client(cl, "a.example", 6667, 6667)
  do IO<Unit>:
    Unit <- E.must_eq("changed host retains only server and log", client_names(changed), "server;*log*;")
    Unit <- E.must_eq("changed port retains only server and log", client_names(port_changed), "server;*log*;")
    Unit <- E.must_eq("new server has no old history", CL.buf_texts(changed, 0n), "")
    Unit <- E.must_eq("retained log keeps content and IDs", signature(log_lines(changed)), signature(log_lines(cl)))
    Unit <- E.must("endpoint preserves noncredential config and clears authentication", endpoint_metadata(changed))
    Unit <- E.must("changed port also clears credentials and authentication",
      String.is_empty(Cl.client_sasl_user(port_changed)) && String.is_empty(Cl.client_sasl_pass(port_changed)) && phase_idle(Cl.get_auth(port_changed)))
    Unit <- E.must("exact same endpoint retains credentials and pending authentication",
      String.eq(Cl.client_sasl_user(credential_same), "synth-user") && String.eq(Cl.client_sasl_pass(credential_same), "synth-secret") && phase_result(Cl.get_auth(credential_same)))
    Unit <- E.must("endpoint preserves global event sequence", Nat.is_eq(Cl.log_seq_of(changed), Cl.log_seq_of(cl)))
    Unit <- E.must_eq("same endpoint keeps chats", client_names(same), client_names(cl))
    Unit <- E.must_eq("same endpoint keeps chat history", CL.buf_texts(same, 1n), CL.buf_texts(cl, 1n))
    Unit <- E.must_eq("no log remains lazy on endpoint change", client_names(Sess.endpoint_client(chats(), "b.example", 6667, 6667)), "server;")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  +full = full_log()
  +marked = H.add_markers_cl(full, "13:00:00")
  +restored = H.apply_history(full, Nil{}, "13:00:00", 2)
  +reconnected = Sess.session_cl(Sess.session_reconnected(Sess.session_set_client(Sess.session0("probe", "a.example", "#old"), full), "12:34:56"))
  do IO<Unit>:
    Unit <- E.must_eq("diagnostic marker and history caps", marker_history_counts(full), Nat.show(D.ROW_CAP()) ++ "," ++ Nat.show(D.ROW_CAP()))
    Unit <- E.must_eq("generic markers leave log untouched", signature(log_lines(marked)), signature(log_lines(full)))
    Unit <- E.must_eq("history cap leaves log untouched", signature(log_lines(restored)), signature(log_lines(full)))
    Unit <- E.must("ordinary chat still gets reconnect marker", ordinary_marker(Cl.active_buf_lines(full), Cl.active_buf_lines(marked)))
    Unit <- E.must("connection notice stays bounded", Nat.is_eq(log_count(reconnected), D.ROW_CAP()))
    Unit <- E.must("connection notice is System, not Reconnect", notice_line(last_line(log_lines(reconnected)), "IRC connection established", Cl.log_seq_of(reconnected)))
    Unit <- E.must("connection notice preserves chat focus", Nat.is_eq(Cl.active_of(reconnected), 1n))
    Unit <- no_log_notice(chats())
    Unit <- existing_log_notice(with_log())
    Unit <- endpoints(with_log())
    Unit <- E.must_eq("OpMedia printer includes all seven fields", VP.show_op(V.OpMedia{1, 2, 3, 4, 5, 6, 7}), "M:1,2,3,4,5,6,7")
    IO.print("diagnostic_session=ok\n")
