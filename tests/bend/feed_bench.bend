# X1: buf_find must be linear in the buffer count.
# 15 self-JOINs fill MAX_BUFFERS; 20 PRIVMSGs each call buf_find.
# Bool.pick in both recursive arms is exponential (review77/feedbench.bend:
# 7.5 s user / 67 s wall at 1d9e5bd). This binary must finish under 2 s.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL

def priv_line() -> String:
  ":a!a@h PRIVMSG #c3 :hello"

def privs.go(n: Nat, acc: List<&2, String>) -> List<&2, String>:
  match n:
    case 0n:
      List.reverse(&2, String, acc)
    case 1n+p:
      privs.go(p, priv_line() <> acc)

def privs(+n: Nat) -> List<&2, String>:
  privs.go(n, Nil{})

def bench_cl() -> Cl.Client:
  Feed.feed_all(Feed.feed_all(Cl.init("me", "s"), CL.flood_joins(15n)), privs(20n))

def bench_on(+fed: Cl.Client) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("nbuf", Nat.show(CL.nbuf(fed)), "16")
    Unit <- E.must("has_c3", CL.has_buf(fed, "#c3"))
    Unit <- E.must("skip0", Bool.not(CL.has_buf(fed, "server")))
    IO.print("feed_bench=ok")

def main() -> IO(Unit):
  bench_on(bench_cl())
