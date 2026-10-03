# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ./history_startup.bend as T
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history_startup.bend as H

def last_is_marker(lines: List<&2, Cl.Line>) -> Bool:
  match lines:
    case Con{Cl.Line{Cl.Reconnect{}, "", "14:00:00", "", id}, Nil{}}: Nat.is_gt(id, 50n)
    case Con{_, rest}: last_is_marker(rest)
    case _: False{}

def marker_at.got(got: Maybe<&2, Cl.Buffer>) -> Bool:
  match got:
    case Some{Cl.Buffer{_, _, _, lines, _, _}}: last_is_marker(lines)
    case None{}: False{}

def marker_at(cl: Cl.Client, index: Nat) -> Bool:
  marker_at.got(Cl.nth_buf(Cl.client_bufs(cl), index))

def positive() -> Bool:
  +got = H.install_startup(T.base(1), T.snapshot())
  T.metadata(got) && marker_at(got, 0n) && marker_at(got, 2n)
    && String.eq(CL.buf_texts(got, 0n), "local|old2|14:00:00|")
    && String.eq(CL.buf_texts(got, 2n), "chat|14:00:00|")
    && Nat.is_eq(Cl.log_seq_of(got), 54n)

def negative() -> Bool:
  +empty = H.install_startup(T.base(1), Cl.init("archive", "irc.example"))
  +off = Cl.set_settings(T.base(1), Cl.set_history(Cl.get_settings(T.base(1)), False{}))
  +failure = Cl.diagnostic(Cl.init("archive", "irc.example"), Cl.Error{}, "history read failed")
  +reported = H.report_diagnostics(T.base(1), failure)
  +only_error = H.install_startup(reported, failure)
  String.eq(CL.buf_texts(empty, 0n), "local|") && Nat.is_eq(Cl.log_seq_of(empty), 50n)
    && String.eq(CL.buf_texts(H.install_startup(off, T.snapshot()), 0n), "local|")
    && String.eq(CL.buf_texts(only_error, 0n), "local|history read failed|")
    && String.eq(T.text_of(only_error, "*log*"), "history read failed|")
    && Nat.is_eq(Cl.log_seq_of(only_error), 51n)

def full() -> Bool:
  +one = H.install_startup(T.full_server(1023n), T.server_snapshot())
  +none = H.install_startup(T.full_server(Cl.SCROLL_CAP()), T.server_snapshot())
  Nat.is_eq(List.length(&2, Cl.Line, T.server_rows(one)), Cl.SCROLL_CAP())
    && String.eq(T.last_text(T.server_rows(one)), "last archived row")
    && Nat.is_eq(Cl.log_seq_of(one), Cl.SCROLL_CAP())
    && String.eq(T.last_text(T.server_rows(none)), "local")
    && Nat.is_eq(Cl.log_seq_of(none), Cl.SCROLL_CAP())

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("startup imported targets receive fresh nontrimming dividers", positive())
    Unit <- E.must("empty, disabled, local-only, and operation diagnostic targets receive no divider", negative())
    Unit <- E.must("full retained targets never lose a row to a divider", full())
    IO.print("history_startup_divider=ok")
