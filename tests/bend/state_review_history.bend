# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ./diagnostic_wire.bend as W
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/frame.bend as Fr
import ../../src/bend/history.bend as H
import ../../src/bend/submit.bend as S

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def record(+target: String, text: String) -> String:
  "BIRC2\ta:6667\t" ++ target ++ "\tMSG\t\talice\t" ++ text ++ "\n"

def old_records(+n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: record("old" ++ Nat.show(n), "old") ++ old_records(p)

def restored.state(state: H.ReadState) -> Cl.Client:
  match state:
    case H.ReadState{cl, _, _, _}: cl

def restored(cl: Cl.Client, text: String, +cap: U32) -> Cl.Client:
  restored.state(H.read_chunk(Fr.string_to_octets(text), H.ReadState{cl, Nil{}, 0n, False{}}, "a:6667", cap))

def rejected(entry: Maybe<&2, H.HistEntry>) -> Bool:
  match entry:
    case None{}: True{}
    case Some{_}: False{}

def parsed(+target: String) -> Maybe<&2, H.HistEntry>:
  H.parse_line_for("a:6667", "BIRC2\ta:6667\t" ++ target ++ "\tMSG\t\talice\tsecret")

def recent_guards() -> IO(Unit):
  +base = Cl.init("me", "a")
  +many = restored(base, old_records(14n) ++ record("recent", "latest"), 1)
  +touched = restored(base, old_records(14n) ++ record("OLD14", "touched") ++ record("recent", "latest"), 1)
  +alias = restored(base, old_records(14n) ++ record("ol" ++ SCon{Chr{31}, "d14"}, "touched"), 1)
  +zero = restored(base, old_records(20n) ++ record("*server*", "server"), 0)
  do IO<Unit>:
    Unit <- E.must("newest target replaces oldest restored target", CL.has_buf(many, "recent") && Bool.not(CL.has_buf(many, "old14")) && Nat.is_eq(CL.nbuf(many), 15n))
    Unit <- E.must("target recency follows last retained record", CL.has_buf(touched, "old14") && Bool.not(CL.has_buf(touched, "old13")))
    Unit <- E.must("normalized history alias does not evict a resident target", CL.has_buf(alias, "old13") && Nat.is_eq(CL.nbuf(alias), 15n))
    Unit <- E.must_eq("normalized history alias updates canonical target", CL.buf_texts(alias, 1n), "touched|")
    Unit <- E.must_eq("casefold target keeps latest per-buffer row", CL.buf_texts(touched, 1n), "touched|")
    Unit <- E.must("bounded restore does not generate buffer-limit errors", String.is_empty(CL.buf_texts(many, 0n)))
    Unit <- E.must("zero cap restores neither chat targets nor server rows", Nat.is_eq(CL.nbuf(zero), 1n) && String.is_empty(CL.buf_texts(zero, 0n)))
    Unit <- E.must_eq("per-buffer row cap retains most recent", CL.buf_texts(restored(base, record("alice", "one") ++ record("alice", "two"), 1), 1n), "two|")
    IO.pure(Unit, Unit{})

def reserved_guards() -> IO(Unit):
  +base = Cl.log_open(Cl.diagnostic(Cl.client_set_sasl(Cl.init("me", "a"), "account", "secret"), Cl.System{}, "account secret"))
  +loaded = restored(base, old_records(20n), 1)
  do IO<Unit>:
    Unit <- E.must("control-prefixed log history is rejected", rejected(parsed(SCon{Chr{31}, "*log*"})))
    Unit <- E.must("control-prefixed settings history is rejected", rejected(parsed(SCon{Chr{31}, "*settings*"})))
    Unit <- E.must("legacy history remains rejected", rejected(H.parse_line_for("a:6667", "alice\tMSG\t\thi")))
    Unit <- E.must("explicit server record is accepted", Bool.not(rejected(H.parse_line_for("a:6667", "BIRC2\ta:6667\t*server*\tMSG\t\talice\thi"))))
    Unit <- E.must_eq("log rows and IDs survive target eviction", W.buffers_signature(Cl.log_buffers(loaded)), W.buffers_signature(Cl.log_buffers(base)))
    Unit <- E.must_eq("restore preserves configured account", Cl.settings_sasl_user(Cl.get_settings(loaded)), "account")
    Unit <- E.must("restore IDs remain globally monotonic", Nat.is_gt(Cl.log_seq_of(loaded), Cl.log_seq_of(base)))
    Unit <- E.must_eq("zero cap leaves existing app-session log untouched", W.signature(restored(base, old_records(20n), 0)), W.signature(base))
    IO.pure(Unit, Unit{})

def local_guards() -> IO(Unit):
  +base = Cl.log_open(client(S.submit(Cl.client_log(Cl.init("me", "a"), 0n, Cl.System{}, "server retained"), "/settings")))
  +loaded = restored(base, old_records(20n) ++ record("recent", "latest"), 1)
  do IO<Unit>:
    Unit <- E.must("local tabs never become eviction candidates", CL.has_buf(loaded, "*settings*") && CL.has_buf(loaded, "*log*") && CL.has_buf(loaded, "recent"))
    Unit <- E.must_eq("eviction preserves focused local tab", Cl.active_buf_name(loaded), "*log*")
    Unit <- E.must_eq("server row is not evicted", CL.buf_texts(loaded, 0n), "server retained|")
    Unit <- E.must_eq("local rows and IDs are unchanged", W.buffers_signature(List.take(&2, Cl.Buffer, List.drop(&2, Cl.Buffer, Cl.client_bufs(loaded), 1n), 2n)), W.buffers_signature(List.drop(&2, Cl.Buffer, Cl.client_bufs(base), 1n)))
    Unit <- E.must("slots remain bounded with local tabs", Nat.is_eq(CL.nbuf(loaded), 16n))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    recent_guards()
    reserved_guards()
    local_guards()
    IO.print("state_review_history=ok")
