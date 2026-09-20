# Tiny IO assertions. Fail closed: mismatch dies nonzero.
import Base

def must(+msg: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, msg)

def must_eq(+tag: String, +got: String, +want: String) -> IO(Unit):
  must(tag ++ " got=[" ++ got ++ "] want=[" ++ want ++ "]", String.eq(got, want))
