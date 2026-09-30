# Read past one MiB through EOF without retaining the whole file.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as H

def repeat(n: Nat, +text: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: text ++ repeat(p, text)

def wrote(pair: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
  match pair:
    case (f, Done{_}): IO.pure(File, f)
    case (f, Fail{_}):
      do IO<File>:
        Unit <- File.close(f)
        IO.die(File, 1, "fixture write failed")

def write_many(n: Nat, f: File, +batch: String) -> IO(File):
  match n:
    case 0n: IO.pure(File, f)
    case 1n+p:
      do IO<File>:
        pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, batch)
        f : File <- wrote(pair)
        write_many(p, f, batch)

def marker_count(lines: List<&2, Cl.Line>) -> Nat:
  match lines:
    case Nil{}: 0n
    case Con{Cl.Line{kind, _, _, _, _}, t}:
      Nat.add(Bool.pick(Nat, Cl.is_reconnect(kind), 1n, 0n), marker_count(t))

def loaded_ok(+cl: Cl.Client) -> Bool:
  match cl:
    case Cl.Client{_, _, Con{Cl.Buffer{_, _, _, +lines, _, _}, Nil{}}, _, _, _, _, _}:
      Nat.is_eq(List.length(&2, Cl.Line, lines), 4n)
        && Nat.is_eq(marker_count(lines), 1n)
        && String.ends_with(CL.buf_texts(cl, 0n), "last-2|last-1|last-é|12:00:00|")
    case _: False{}

def main() -> IO(Unit):
  +path: String = "build/history_io.fixture"
  +old = "BIRC2\ta:6667\tserver\tMSG\t\ta\t" ++ repeat(300n, "x") ++ "\n"
  +end = "server\tMSG\t\tambiguous-legacy\n"
    ++ "BIRC2\tb:6667\tprivate\tMSG\t\ta\tother-server\n"
    ++ "BIRC2\ta:6667\tserver\tMSG\t\ta\tlast-2\n"
    ++ "BIRC2\ta:6667\tserver\tMSG\t\ta\tlast-1\n"
    ++ "BIRC2\ta:6667\tserver\tMSG\t\ta\tlast-é\n"
    ++ repeat(9000n, "z") ++ "\n"
    ++ "BIRC2\ta:6667\tserver\tMSG\t\ta\tunterminated"
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    f : File <- write_many(20n, f, repeat(200n, old))
    pair : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, end)
    f : File <- wrote(pair)
    Unit <- File.close(f)
    cl : Cl.Client <- H.history_init_client(path, "a:6667", 3, "me", "a", "12:00:00")
    Unit <- E.must("latest_after_one_mib", loaded_ok(cl))
    missing : Cl.Client <- H.history_init_client("build/history_io.absent", "a:6667", 3, "me", "a", "12:00:00")
    Unit <- E.must("missing_file", Nat.is_eq(CL.buf_nlines(missing, 0n), 0n))
    IO.print("history_io=ok")
