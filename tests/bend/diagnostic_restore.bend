# SPDX-License-Identifier: Apache-2.0
# Archived chat errors are restored rows, not new app-session diagnostics.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/history.bend as H
import ../../src/bend/session.bend as Sess

def log_lines.from(bufs: List<&2, Cl.Buffer>) -> List<&2, Cl.Line>:
  match bufs:
    case Con{Cl.Buffer{_, _, _, lines, _, _, _, _}, Nil{}}: lines
    case _: Nil{}

def log_lines(cl: Cl.Client) -> List<&2, Cl.Line>:
  log_lines.from(Cl.log_buffers(cl))

def lines_at.got(buf: Maybe<&2, Cl.Buffer>) -> List<&2, Cl.Line>:
  match buf:
    case Some{Cl.Buffer{_, _, _, lines, _, _, _, _}}: lines
    case None{}: Nil{}

def lines_at(cl: Cl.Client, i: Nat) -> List<&2, Cl.Line>:
  match cl:
    case Cl.Client{_, _, bufs, _, _, _, _, _}: lines_at.got(Cl.nth_buf(bufs, i))

def signature(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{kind, ts, text, author, id}, tail}:
      H.serialize_kind(kind) ++ "|" ++ ts ++ "|" ++ text ++ "|" ++ author
        ++ "|" ++ Nat.show(id) ++ ";" ++ signature(tail)

def entries() -> List<&2, H.HistEntry>:
  [H.ServerEntry{Cl.Line{Cl.Error{}, "12:34:56", "archived server error", "server-author", 900n}},
   H.ServerEntry{Cl.Line{Cl.System{}, "12:34:57", "archived server notice", "notice-author", 901n}},
   H.Entry{"server", Cl.Line{Cl.Error{}, "12:34:58", "archived query error", "query-author", 902n}},
   H.Entry{"server", Cl.Line{Cl.System{}, "12:34:59", "archived query notice", "query-notice", 903n}}]

def round_trip(cl: Cl.Client) -> Cl.Client:
  Sess.endpoint_client(Sess.endpoint_client(cl, "b.example", 6667, 6667), "a.example", 6667, 6667)

def lazy_restore() -> IO(Unit):
  +cl = H.apply_entries(entries(), Cl.set_now(Cl.init("probe", "a.example"), "22:00:00"))
  do IO<Unit>:
    Unit <- E.must("restored errors do not create log", Nat.is_eq(List.length(&2, Cl.Buffer, Cl.log_buffers(cl)), 0n))
    Unit <- E.must_eq("server errors and notices retain their metadata", signature(lines_at(cl, 0n)),
      "ERR|12:34:56|archived server error|server-author|1;SYS|12:34:57|archived server notice|notice-author|2;")
    Unit <- E.must_eq("query named server is distinct from control", signature(lines_at(cl, 1n)),
      "ERR|12:34:58|archived query error|query-author|3;SYS|12:34:59|archived query notice|query-notice|4;")
    Unit <- E.must("restore allocates only four fresh chat IDs", Nat.is_eq(Cl.log_seq_of(cl), 4n))
    Unit <- E.must("restoration does not steal focus", Nat.is_eq(Cl.active_of(cl), 0n))
    IO.pure(Unit, Unit{})

def retained_restore(+before: Cl.Client) -> IO(Unit):
  +once = H.apply_entries(entries(), round_trip(before))
  +twice = H.apply_entries(entries(), round_trip(once))
  +thrice = H.apply_entries(entries(), round_trip(twice))
  do IO<Unit>:
    Unit <- E.must_eq("retained log is not remirrored after A-B-A", signature(log_lines(once)), signature(log_lines(before)))
    Unit <- E.must_eq("second reload does not duplicate log", signature(log_lines(twice)), signature(log_lines(before)))
    Unit <- E.must_eq("third reload does not duplicate log", signature(log_lines(thrice)), signature(log_lines(before)))
    Unit <- E.must_eq("restored server metadata survives retained log", signature(lines_at(once, 0n)),
      "ERR|12:34:56|archived server error|server-author|2;SYS|12:34:57|archived server notice|notice-author|3;")
    Unit <- E.must_eq("restored query metadata survives retained log", signature(lines_at(once, 2n)),
      "ERR|12:34:58|archived query error|query-author|4;SYS|12:34:59|archived query notice|query-notice|5;")
    Unit <- E.must("IDs remain monotonic across endpoint reloads", Nat.is_eq(Cl.log_seq_of(thrice), 13n))
    Unit <- E.must_eq("retained diagnostics do not enter history", H.extract_new_history_for("a.example:6667", before, Cl.diagnostic(before, Cl.System{}, "log only")), "")
    Unit <- E.must("repeated restore does not steal focus", Nat.is_eq(Cl.active_of(thrice), 0n))
    IO.pure(Unit, Unit{})

def live_error() -> IO(Unit):
  +restored = H.apply_entries(entries(), Cl.init("probe", "a.example"))
  +live = Cl.client_log_author_ts(restored, 1n, Cl.Error{}, "23:00:00", "fresh query error", "live-author")
  do IO<Unit>:
    Unit <- E.must_eq("fresh error still creates and mirrors into log", signature(log_lines(live)),
      "ERR|23:00:00|fresh query error||5;")
    Unit <- E.must_eq("live original keeps author and same event ID", signature(lines_at(live, 1n)),
      "ERR|12:34:58|archived query error|query-author|3;SYS|12:34:59|archived query notice|query-notice|4;ERR|23:00:00|fresh query error|live-author|5;")
    Unit <- E.must("live mirror does not spend a second event ID", Nat.is_eq(Cl.log_seq_of(live), 5n))
    Unit <- E.must("live error does not steal focus", Nat.is_eq(Cl.active_of(live), 0n))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  +before = Cl.client_log_author_ts(Cl.init("probe", "a.example"), 0n, Cl.Error{}, "11:00:00", "retained error", "original-author")
  do IO<Unit>:
    Unit <- E.must_eq("live server mirror has stable ID and timestamp", signature(log_lines(before)), "ERR|11:00:00|retained error||1;")
    Unit <- lazy_restore()
    Unit <- retained_restore(before)
    Unit <- live_error()
    IO.print("diagnostic_restore=ok\n")
