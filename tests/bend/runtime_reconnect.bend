# Exercise real reconnect transitions, not just marker insertion.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/session.bend as Sess

def markers(xs: List<&2, Cl.Line>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{Cl.Line{kind, _, _, _, _}, t}:
      Nat.add(Bool.pick(Nat, Cl.is_reconnect(kind), 1n, 0n), markers(t))

def chat() -> Cl.Client:
  +cl = Cl.set_active(Feed.feed_all(Cl.init("probe", "a.example"),
    ":probe!u@h JOIN #t" <> ":alice!u@h PRIVMSG #t :before reconnect" <> Nil{}), 1n)
  Cl.set_settings(cl, Cl.set_autoreconn(Cl.get_settings(cl), True{}))

def count(+st: Sess.Session) -> String:
  Nat.show(markers(Cl.active_buf_lines(Sess.session_cl(st))))

def auto_up(pair: Sess.Session & Sess.NetCmd) -> Sess.Session:
  match pair:
    case (st, _): Sess.session_reconnected(st, "13:00:00")

def manual_up(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match trip:
    case (st, _, _): Sess.session_reconnected(st, "13:00:00")

type SBox is Data:
  SBox{cell: List<&2, Sess.Session>}

# Singleton-list box: a live Session flattens to dozens of words, so the
# four Sessions held across one do-block breach the 247-word native
# continuation limit ("an arity over 247"). Boxing keeps bind captures
# narrow (session_drafts_demo idiom); use sites unbox transiently. The
# Nil arm is unreachable by construction.
def sbox(+st: Sess.Session) -> SBox:
  SBox{st <> Nil{}}

def sunbox.cell(+cell: List<&2, Sess.Session>) -> Sess.Session:
  match cell:
    case Con{+st, _}: st
    case Nil{}: Sess.session_fail(Sess.session_online(Sess.session_with_client(chat(), "#t")), "unreachable")

def sunbox(+b: SBox) -> Sess.Session:
  match b:
    case SBox{+cell}: sunbox.cell(cell)

def ph_first(+initial: SBox, +online: SBox, +auto: SBox) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("initial_connection_has_no_divider", count(Sess.session_reconnected(sunbox(initial), "13:00:00")), "0")
    Unit <- E.must_eq("ordinary_paint_has_no_divider", count(sunbox(online)), "0")
    Unit <- E.must_eq("automatic_reconnect_divider", count(sunbox(auto)), "1")
    IO.pure(Unit, Unit{})

def ph_second(+online: SBox, +failed: SBox, +auto: SBox) -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("manual_online_reconnect_divider", count(manual_up(Sess.step_enter(sunbox(online), "/reconnect"))), "1")
    Unit <- E.must_eq("manual_offline_reconnect_divider", count(manual_up(Sess.step_enter(sunbox(failed), "/reconnect"))), "1")
    Unit <- E.must_eq("second_up_does_not_repeat_divider", count(Sess.session_reconnected(sunbox(auto), "13:01:00")), "1")
    Unit <- E.must_eq("new_endpoint_has_no_divider", count(manual_up(Sess.step_enter(sunbox(online), "/connect b.example"))), "0")
    IO.print("runtime_reconnect=ok")

def main() -> IO(Unit):
  +initial = sbox(Sess.session_with_client(chat(), "#t"))
  +online = sbox(Sess.session_online(sunbox(initial)))
  +failed = sbox(Sess.session_fail(sunbox(online), "disconnected"))
  +auto = sbox(auto_up(Sess.session_autoreconnect(sunbox(failed))))
  do IO<Unit>:
    Unit <- ph_first(initial, online, auto)
    Unit <- ph_second(online, failed, auto)
    IO.pure(Unit, Unit{})
