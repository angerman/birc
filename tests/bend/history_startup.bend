# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history_startup.bend as H

def row(+text: String, id: Nat) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "12:00:00", text, "alice", id}

def base(cap: U32) -> Cl.Client:
  +settings = Cl.set_hist_cap(Cl.get_settings(Cl.client_set_sasl(Cl.init("me", "irc.example"), "account", "secret")), cap)
  Cl.Client{"me", "irc.example", Cl.buf_indexed("server", False{}, "local topic", row("local", 50n) <> Nil{}, "kept" <> Nil{}, Cl.ScrollAt{0n, 0n}) <> Cl.empty_buf("early", False{}) <> Nil{}, 1n, "14:00:00", settings, Cl.AuthCap{}, 50n}

def snapshot() -> Cl.Client:
  Cl.Client{"archive", "irc.example", Cl.buf_indexed("server", False{}, "stale topic", row("old1", 1n) <> row("old2", 2n) <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}) <> Cl.buf_indexed("#room", True{}, "stale room", row("chat", 3n) <> Nil{}, "stale nick" <> Nil{}, Cl.ScrollAt{0n, 0n}) <> Nil{}, 0n, "old time", Cl.settings0(), Cl.AuthIdle{}, 3n}

def metadata(cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{+nick, +host, Con{Cl.Buffer{+name, False{}, +topic, Con{Cl.Line{_, _, +text, _, id}, _}, +nicks, _, _, _}, _}, active, +now, +settings, Cl.AuthCap{}, +seq}:
      String.eq(nick, "me") && String.eq(host, "irc.example") && String.eq(name, "server")
        && String.eq(topic, "local topic") && String.eq(text, "local") && Nat.is_eq(id, 50n)
        && String.eq(String.join(nicks, "|"), "kept") && Nat.is_eq(active, 1n)
        && String.eq(now, "14:00:00") && String.eq(Cl.settings_sasl_user(settings), "account")
        && String.eq(Cl.settings_sasl_pass(settings), "secret") && Nat.is_ge(seq, 50n)
    case _: False{}

def positive() -> Bool:
  +got = H.install(base(1), snapshot())
  metadata(got) && String.eq(CL.buf_texts(got, 0n), "local|old2|")
    && String.eq(CL.buf_texts(got, 1n), "") && String.eq(CL.buf_texts(got, 2n), "chat|")
    && Nat.is_eq(Cl.log_seq_of(got), 52n)

def negative() -> Bool:
  +off = Cl.set_settings(base(1), Cl.set_history(Cl.get_settings(base(1)), False{}))
  +wrong = Cl.set_server(snapshot(), "IRC.EXAMPLE")
  +zero = H.install(base(0), snapshot())
  String.eq(CL.buf_texts(H.install(off, snapshot()), 0n), "local|")
    && String.eq(CL.buf_texts(H.install(base(1), wrong), 0n), "local|")
    && String.eq(CL.buf_texts(zero, 0n), "local|") && Nat.is_eq(Cl.buf_count(Cl.client_bufs(zero)), 2n)

def fill.client(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def fill(+n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p: fill(p, fill.client(Cl.buf_get(cl, "local" ++ Nat.show(n), False{}, True{})))

def archive_buf(+name: String, +text: String, id: Nat) -> Cl.Buffer:
  Cl.buf_indexed(name, Cl.target_channel(name), "", row(text, id) <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})

def admission_snapshot() -> Cl.Client:
  Cl.Client{"old", "irc.example", Cl.server_buf() <> archive_buf("#old", "old target", 1n)
    <> archive_buf("early", "shared", 2n) <> archive_buf("#new", "recent target", 3n) <> Nil{}, 0n, "", Cl.settings0(), Cl.AuthIdle{}, 3n}

def missing(got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: True{}
    case _: False{}

def text_of.found(cl: Cl.Client, got: Maybe<&2, Nat>) -> String:
  match got:
    case None{}: ""
    case Some{index}: CL.buf_texts(cl, index)

def text_of(+cl: Cl.Client, name: String) -> String:
  text_of.found(cl, Cl.buf_find(cl, name))

def admission() -> Bool:
  +partial = H.install(fill(12n, base(1)), admission_snapshot())
  +full = H.install(fill(13n, base(1)), admission_snapshot())
  missing(Cl.buf_find(partial, "#old")) && String.eq(text_of(partial, "#new"), "recent target|")
    && String.eq(text_of(partial, "early"), "shared|") && Nat.is_eq(Cl.buf_count(Cl.client_bufs(partial)), 15n)
    && missing(Cl.buf_find(full, "#old")) && missing(Cl.buf_find(full, "#new"))
    && String.eq(text_of(full, "early"), "shared|") && Nat.is_eq(Cl.buf_count(Cl.client_bufs(full)), 15n)
    && missing(Cl.buf_find(full, "*log*"))

def rows(n: Nat, +id: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p: row("local", id) <> rows(p, 1n+id)

def full_server(+n: Nat) -> Cl.Client:
  Cl.Client{"me", "irc.example", Cl.buf_indexed("server", False{}, "", rows(n, 1n), Nil{}, Cl.ScrollAt{0n, 0n}) <> Nil{}, 0n, "", Cl.settings0(), Cl.AuthIdle{}, n}

def server_snapshot() -> Cl.Client:
  Cl.Client{"old", "irc.example", archive_buf("server", "last archived row", 1n) <> Nil{}, 0n, "", Cl.settings0(), Cl.AuthIdle{}, 1n}

def server_rows(cl: Cl.Client) -> List<&2, Cl.Line>:
  match cl:
    case Cl.Client{_, _, Con{Cl.Buffer{_, _, _, lines, _, _, _, _}, _}, _, _, _, _, _}: lines
    case _: Nil{}

def last_text(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, _, text, _, _}, Nil{}}: text
    case Con{_, rest}: last_text(rest)

def capacity() -> Bool:
  +one = H.install(full_server(U32.to_nat(1023)), server_snapshot())
  +none = H.install(full_server(Cl.SCROLL_CAP()), server_snapshot())
  Nat.is_eq(List.length(&2, Cl.Line, server_rows(one)), Cl.SCROLL_CAP())
    && String.eq(last_text(server_rows(one)), "last archived row") && Nat.is_eq(Cl.log_seq_of(one), Cl.SCROLL_CAP())
    && Nat.is_eq(List.length(&2, Cl.Line, server_rows(none)), Cl.SCROLL_CAP())
    && String.eq(last_text(server_rows(none)), "local") && Nat.is_eq(Cl.log_seq_of(none), Cl.SCROLL_CAP())

def peer_server() -> Bool:
  +snap: Cl.Client = Cl.Client{"old", "irc.example", Cl.server_buf() <> archive_buf("server", "peer named server", 1n)
    <> archive_buf("*log*", "never replay diagnostics", 2n) <> Nil{}, 0n, "", Cl.settings0(), Cl.AuthIdle{}, 2n}
  +got = H.install(base(1), snap)
  String.eq(text_of(got, "server"), "peer named server|") && String.eq(CL.buf_texts(got, 0n), "local|")
    && missing(Cl.buf_find(got, "*log*")) && Nat.is_eq(Cl.log_seq_of(got), 51n)

def diagnostic_reporting() -> Bool:
  +archive = Cl.client_restore_author_ts(Cl.init("old", "irc.example"), 0n, Cl.Error{}, "12:00:00", "archived error", "")
  +failed = Cl.client_log(archive, 0n, Cl.Error{}, "history read failed (5)")
  +current = Cl.diagnostic(base(1), Cl.Error{}, "current diagnostic")
  +got = H.report_diagnostics(current, failed)
  +installed = H.install(got, failed)
  String.eq(String.join(H.diagnostics(failed), "|"), "history read failed (5)")
    && List.is_empty(&2, String, H.diagnostics(archive))
    && Nat.is_eq(Cl.log_seq_of(H.report_diagnostics(current, archive)), Cl.log_seq_of(current))
    && String.eq(text_of(got, "*log*"), "current diagnostic|history read failed (5)|")
    && String.eq(CL.buf_texts(got, 0n), "local|history read failed (5)|") && Nat.is_eq(Cl.active_of(got), 1n)
    && Nat.is_eq(Cl.log_seq_of(got), 52n)
    && String.eq(CL.buf_texts(installed, 0n), "local|history read failed (5)|archived error|")
    && String.eq(text_of(installed, "*log*"), "current diagnostic|history read failed (5)|")
    && Nat.is_eq(Cl.log_seq_of(installed), 53n)
    && Nat.is_eq(Cl.log_seq_of(H.report_diagnostics(current, Cl.set_server(failed, "other.example"))), Cl.log_seq_of(current))

def line_ids(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, _, _, _, id}, rest}: Nat.show(id) ++ "|" ++ line_ids(rest)

def ids_at.found(got: Maybe<&2, Cl.Buffer>) -> String:
  match got:
    case None{}: ""
    case Some{Cl.Buffer{_, _, _, lines, _, _, _, _}}: line_ids(lines)

def ids_at(cl: Cl.Client, index: Nat) -> String:
  ids_at.found(Cl.nth_buf(Cl.client_bufs(cl), index))

def diagnostic_identity() -> Bool:
  +archive = Cl.client_restore_author_ts(Cl.init("old", "irc.example"), 0n, Cl.Error{}, "12:00:00", "same error", "")
  +failed = Cl.client_log(archive, 0n, Cl.Error{}, "same error")
  +reported = H.report_diagnostics(base(1), failed)
  +got = H.install(reported, failed)
  String.eq(CL.buf_texts(got, 0n), "local|same error|same error|")
    && String.eq(text_of(got, "*log*"), "same error|")
    && String.eq(ids_at(got, 0n), "50|51|52|") && String.eq(ids_at(got, 2n), "51|")
    && Nat.is_eq(Cl.log_seq_of(got), 52n)

def zero_mirror() -> Bool:
  +snapshot: Cl.Client = Cl.Client{"old", "irc.example", archive_buf("server", "archive with zero ID", 0n)
    <> Cl.buf_indexed("*log*", False{}, "", Cl.Line{Cl.Error{}, "", "unassigned", "", 0n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}) <> Nil{}, 0n, "", Cl.settings0(), Cl.AuthIdle{}, 0n}
  String.eq(CL.buf_texts(H.install(base(1), snapshot), 0n), "local|archive with zero ID|")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("startup import preserves local rows/IDs/metadata and applies cap to imported rows only", positive())
    Unit <- E.must("disabled history, zero cap, and stale exact host cannot import", negative())
    Unit <- E.must("current tabs survive full capacity and recent archive targets get remaining slots", admission())
    Unit <- E.must("archive cannot trim current rows at SCROLL_CAP", capacity())
    Unit <- E.must("server peer stays separate and app-session diagnostics never replay", peer_server())
    Unit <- E.must("only current worker failures become diagnostics, never archived Error mirrors", diagnostic_reporting())
    Unit <- E.must("equal error text stays distinct and one operation mirror shares its server ID", diagnostic_identity())
    Unit <- E.must("zero mirror IDs cannot suppress archived rows", zero_mirror())
    IO.print("history_startup=ok")
