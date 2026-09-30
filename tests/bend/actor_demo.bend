import Base
import ./expect.bend as E
import ../../src/bend/actor.bend as Act

def lines(+n: Nat) -> List<&2, String>:
  match n:
    case 0n: Nil{}
    case 1n+p: Nat.show(n) <> lines(p)

def batch_now(b: Act.Batch) -> List<&2, String>:
  match b:
    case Act.Batch{now, _, _}: now

def batch_later(b: Act.Batch) -> List<&2, String>:
  match b:
    case Act.Batch{_, later, _}: later

def batch_budget(b: Act.Batch) -> Act.Budget:
  match b:
    case Act.Batch{_, _, budget}: budget

def next(b: Act.Batch) -> Act.Batch:
  match b:
    case Act.Batch{_, later, budget}: Act.batch(later, budget)

def same(xs: List<&2, String>, ys: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      match ys:
        case Nil{}: True{}
        case _: False{}
    case Con{+h, t}:
      match ys:
        case Con{+j, u}: String.eq(h, j) && same(t, u)
        case _: False{}

def fifo(b: Act.Batch, original: List<&2, String>) -> Bool:
  match b:
    case Act.Batch{now, later, _}:
      same(List.append(&2, String, now, later), original)

def boundary(+n: Nat, +want: Nat) -> IO(Unit):
  do IO<Unit>:
    +xs : List<&2, String> = lines(n)
    +b : Act.Batch = Act.batch(xs, Act.Unlimited{})
    Unit <- E.must_eq("cap boundary " ++ Nat.show(n), Nat.show(List.length(&2, String, batch_now(b))), Nat.show(want))
    E.must("FIFO boundary " ++ Nat.show(n), fifo(b, xs))

def bounded_all(+n: Nat) -> IO(Unit):
  match n:
    case 0n: boundary(0n, 0n)
    case 1n+p:
      do IO<Unit>:
        +b : Act.Batch = Act.batch(lines(n), Act.Unlimited{})
        Unit <- E.must("all turns capped", Nat.is_le(List.length(&2, String, batch_now(b)), Act.SEND_CAP()))
        Unit <- E.must("all turns FIFO", fifo(b, lines(n)))
        bounded_all(p)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- boundary(0n, 0n)
    Unit <- boundary(7n, 7n)
    Unit <- boundary(8n, 8n)
    Unit <- boundary(9n, 8n)
    Unit <- boundary(16n, 8n)
    Unit <- boundary(17n, 8n)
    Unit <- bounded_all(33n)
    +one : Act.Batch = Act.batch(lines(17n), Act.budget_frames(1))
    Unit <- E.must_eq("finite first grant", Nat.show(List.length(&2, String, batch_now(one))), "8")
    Unit <- E.must_eq("finite exhausted holds FIFO", String.join(batch_later(next(one)), ","), String.join(batch_later(one), ","))
    Unit <- E.must_eq("finite exhausted sends none", Nat.show(List.length(&2, String, batch_now(next(one)))), "0")
    Unit <- E.must("finite exhausted closed", Bool.not(Act.budget_open(batch_budget(one))))
    +two : Act.Batch = Act.batch(lines(17n), Act.budget_frames(2))
    Unit <- E.must_eq("second grant", Nat.show(List.length(&2, String, batch_now(next(two)))), "8")
    Unit <- E.must_eq("second grant remainder", Nat.show(List.length(&2, String, batch_later(next(two)))), "1")
    Unit <- E.must_eq("two grants exhausted", Nat.show(List.length(&2, String, batch_now(next(next(two))))), "0")
    +small : Act.Batch = Act.batch(lines(3n), Act.budget_frames(1))
    Unit <- E.must_eq("small command shares frame credit", Nat.show(List.length(&2, String, batch_now(Act.batch(lines(9n), batch_budget(small))))), "5")
    +empty : Act.Batch = Act.batch(Nil{}, Act.budget_frames(1))
    Unit <- E.must_eq("empty command keeps full grant", Nat.show(List.length(&2, String, batch_now(Act.batch(lines(9n), batch_budget(empty))))), "8")
    Unit <- E.must_eq("zero frames unlimited", Nat.show(List.length(&2, String, batch_now(next(Act.batch(lines(17n), Act.budget_frames(0)))))), "8")
    Unit <- E.must_eq("maximum frames does not overflow", Nat.show(List.length(&2, String, batch_now(next(Act.batch(lines(17n), Act.budget_frames(4294967295)))))), "8")
    IO.print("actor_demo=ok")
