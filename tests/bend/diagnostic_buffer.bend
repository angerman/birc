# The diagnostic slot is lazy, private, bounded, and not an IRC destination.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/diagnostic.bend as D

def lines(+cl: Cl.Client) -> List<&2, Cl.Line>:
  Cl.active_buf_lines(Cl.log_open(cl))

def last_text(xs: List<&2, Cl.Line>) -> String:
  match xs:
    case Nil{}: ""
    case Con{Cl.Line{_, _, text, _, _}, Nil{}}: text
    case Con{_, t}: last_text(t)

def make.got(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def fill(+n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p: fill(p, make.got(Cl.buf_get(cl, "#" ++ Nat.show(n), True{}, True{})))

def notices(+n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p: notices(p, Cl.diagnostic(cl, Cl.System{}, Nat.show(n)))

def overflow(cl: Cl.Client) -> Cl.Client:
  make.got(Cl.buf_get(cl, "#overflow", True{}, True{}))

def mirrored(+cl: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("original_error", last_text(Cl.active_buf_lines(cl)), "private secret https://example.invalid/path")
    Unit <- E.must_eq("log_copy", last_text(lines(cl)), "private [redacted] [url]")
    Unit <- E.must("no_focus_steal", Nat.is_eq(Cl.active_of(cl), 0n))
    Unit <- E.must("single_event", Nat.is_eq(Cl.log_seq_of(cl), 1n))
    Unit <- E.must("retention_only_log", Nat.is_eq(List.length(&2, Cl.Buffer, Cl.log_buffers(cl)), 1n))
    IO.pure(Unit, Unit{})

def capacity(+full: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("normal_cap", Nat.is_eq(CL.nbuf(full), 15n))
    Unit <- E.must("lazy_log", Nat.is_eq(CL.nbuf(Cl.log_open(full)), Cl.MAX_BUFFERS()))
    Unit <- E.must("rejection_total_cap", Nat.is_eq(CL.nbuf(overflow(full)), Cl.MAX_BUFFERS()))
    Unit <- E.must_eq("rejection_log", last_text(lines(overflow(full))), "buffer limit reached")
    Unit <- E.must("normal_existing", Nat.is_eq(CL.nbuf(make.got(Cl.buf_get(full, "#2", True{}, True{}))), 15n))
    Unit <- E.must("closed_slot_reserved", Nat.is_eq(CL.nbuf(overflow(Cl.drop_buf(Cl.log_open(full), 15n))), Cl.MAX_BUFFERS()))
    IO.pure(Unit, Unit{})

def bounded(+cl: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("row_cap", Nat.is_eq(List.length(&2, Cl.Line, lines(cl)), D.ROW_CAP()))
    Unit <- E.must_eq("newest_retained", last_text(lines(cl)), "1")
    Unit <- E.must("stable_original_focus", Nat.is_eq(Cl.active_of(cl), 0n))
    Unit <- E.must("recreate", Nat.is_eq(CL.nbuf(Cl.diagnostic(Cl.drop_buf(Cl.log_open(cl), 1n), Cl.System{}, "new")), 2n))
    IO.pure(Unit, Unit{})

def local_errors(+cl: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("local_original", last_text(Cl.active_buf_lines(cl)), "local failure")
    Unit <- E.must_eq("local_mirrored", last_text(lines(cl)), "local failure")
    Unit <- E.must("local_single_event", Nat.is_eq(Cl.log_seq_of(cl), 1n))
    Unit <- E.must("no_remirror", Nat.is_eq(List.length(&2, Cl.Line, lines(Cl.stamp_logs(cl))), 1n))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  +cl = Cl.init("me", "s")
  do IO<Unit>:
    Unit <- E.must("initial_lazy", Nat.is_eq(CL.nbuf(cl), 1n))
    Unit <- E.must("empty_retention", Nat.is_eq(List.length(&2, Cl.Buffer, Cl.log_buffers(cl)), 0n))
    Unit <- E.must("normal_not_retained", Nat.is_eq(List.length(&2, Cl.Buffer, Cl.log_buffers(fill(2n, cl))), 0n))
    Unit <- E.must("system_not_mirrored", Nat.is_eq(CL.nbuf(Cl.client_log(cl, 0n, Cl.System{}, "normal")), 1n))
    Unit <- mirrored(Cl.client_log(Cl.client_set_sasl(cl, "", "secret"), 0n, Cl.Error{}, "private secret https://example.invalid/path"))
    Unit <- local_errors(Cl.stamp_logs(Cl.buf_modify_client(cl, 0n, b => Cl.buf_log(b, Cl.Error{}, "local failure"))))
    Unit <- capacity(fill(14n, cl))
    Unit <- bounded(notices(130n, cl))
    Unit <- E.must("text_cap", Nat.is_eq(String.length(last_text(lines(Cl.diagnostic(cl, Cl.System{}, String.repeat("x", 600n))))), D.TEXT_CAP()))
    Unit <- E.must_eq("active_log_redacted", last_text(lines(Cl.client_log(Cl.log_open(Cl.client_set_sasl(cl, "", "secret")), 1n, Cl.Error{}, "secret"))), "[redacted]")
    IO.print("diagnostic_buffer=ok\n")
