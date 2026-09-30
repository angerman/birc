# State regressions from the adversarial review.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL

def fill_buffers(+n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p:
      fill_buffers(p, Feed.feed(cl, ":a" ++ Nat.show(n) ++ "!a@h PRIVMSG me :hello"))

def rejected_remote(n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p:
      rejected_remote(p, Feed.feed(cl, ":overflow!a@h PRIVMSG me :hello"))

def cap_rejections_ok() -> Bool:
  +cl = rejected_remote(1050n, fill_buffers(15n, Cl.init("me", "s")))
  Nat.is_eq(CL.nbuf(cl), Cl.MAX_BUFFERS())
    && Nat.is_eq(CL.buf_nlines(cl, 0n), Cl.SCROLL_CAP())

def accepted_remote_ok() -> Bool:
  +cl = Feed.feed(Cl.init("me", "s"), ":ordinary!a@h PRIVMSG me :hello")
  Nat.is_eq(CL.nbuf(cl), 2n)
    && Nat.is_eq(CL.buf_nlines(cl, 0n), 0n)
    && String.eq(CL.buf_texts(cl, 1n), "<ordinary> hello|")

def auth_cap(phase: Cl.AuthPhase) -> Bool:
  match phase:
    case Cl.AuthCap{}: True{}
    case _: False{}

def auth_idle(phase: Cl.AuthPhase) -> Bool:
  match phase:
    case Cl.AuthIdle{}: True{}
    case _: False{}

def auth_phase_ok() -> Bool:
  +cl = Cl.client_set_sasl(Cl.init("me", "s"), "user", "pass")
  auth_cap(Cl.get_auth(cl))
    && auth_cap(Cl.get_auth(Feed.feed(cl, ":me!m@h JOIN #t")))
    && auth_idle(Cl.get_auth(Cl.client_set_sasl(cl, "user", "")))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("accepted_remote", accepted_remote_ok())
    Unit <- E.must("bounded_rejections", cap_rejections_ok())
    Unit <- E.must("auth_phase", auth_phase_ok())
    IO.print("state_demo=ok")
