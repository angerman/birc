import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as H
import ../../src/bend/history_io.bend as HistIO

def configured() -> Cl.Client:
  +settings = Cl.set_ts(Cl.get_settings(Cl.client_set_sasl(Cl.init("configured", "a"), "user", "pass")), False{})
  Cl.Client{"configured", "a", Cl.buf_indexed("server", False{}, "", Cl.Line{Cl.Msg{}, "", "prefix", "author", 50n} <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}) <> Nil{}, 0n, "14:00:00", settings, Cl.AuthCap{}, 50n, False{}}

def errors(xs: List<&2, Cl.Line>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{Cl.Line{Cl.Error{}, _, _, _, _}, t}: 1n+errors(t)
    case Con{_, t}: errors(t)

def preserved(cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{+nick, +server, Con{Cl.Buffer{_, _, _, Con{Cl.Line{_, _, +text, +author, id}, _}, _, _, _, _}, _}, _, +now, +settings, Cl.AuthCap{}, seq, _}:
      String.eq(nick, "configured") && String.eq(server, "a") && String.eq(now, "14:00:00")
        && Bool.not(Cl.settings_ts(settings)) && String.eq(Cl.settings_sasl_user(settings), "user")
        && String.eq(text, "prefix") && String.eq(author, "author") && Nat.is_eq(id, 50n) && Nat.is_ge(seq, 50n)
    case _: False{}

def errors_cl(cl: Cl.Client) -> Nat:
  match cl:
    case Cl.Client{_, _, Con{Cl.Buffer{_, _, _, lines, _, _, _, _}, _}, _, _, _, _, _, _}: errors(lines)
    case _: 0n

def report(+cl: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("configuration and retained IDs survive history errors", preserved(cl))
    Unit <- E.must("one diagnostic per failed operation", Nat.is_le(errors_cl(cl), 1n))
    IO.print("texts:" ++ CL.buf_texts(cl, 0n))

def size_result(r: Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  match r:
    case Done{size}: IO.print("done:" ++ U32.show(size))
    case Fail{(code, +msg)}: IO.print("fail:" ++ U32.show(code) ++ ":" ++ msg)

def size_pair(pair: File & Result<&1, &1, U32 & String, U32>) -> IO(Unit):
  match pair:
    case (f, r):
      do IO<Unit>:
        Unit <- File.close(f)
        size_result(r)

def read_error(f: File) -> IO(Unit):
  do IO<Unit>:
    cl : Cl.Client <- H.read_loop.got((f, Fail{(5, "injected I/O failure")}), H.ReadState{configured(), 65 <> Nil{}, 1n, False{}}, "a:6667", 3, "14:00:00", 1n,
      f2 => state => rest => do IO<Cl.Client>:
        Unit <- File.close(f2)
        IO.die(Cl.Client, 1, "read error called continuation"))
    report(cl)

def opened(r: Result<&1, &1, U32 & String, File>, size: Bool) -> IO(Unit):
  match r:
    case Fail{_}: IO.die(Unit, 1, "probe file open failed")
    case Done{f}:
      match size:
        case True{}:
          do IO<Unit>:
            pair : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
            size_pair(pair)
        case False{}: read_error(f)

def run(load: Bool, +path: String, +mode: String) -> IO(Unit):
  match load:
    case True{}:
      do IO<Unit>:
        cl : Cl.Client <- HistIO.history_load_client(path, "a:6667", 3, configured())
        report(cl)
    case False{}:
      do IO<Unit>:
        r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        opened(r, String.eq(mode, "size"))

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+path, Con{+mode, Nil{}}}}: run(String.eq(mode, "load"), path, mode)
    case _: IO.die(Unit, 1, "expected path mode")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
