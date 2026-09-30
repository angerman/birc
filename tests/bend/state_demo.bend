# State regressions from the adversarial review.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as H

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

def alerts_isolated_ok() -> Bool:
  +alerts: List<&2, Cl.Alert> = Cl.Alert{"!ABCDEroom", Cl.Activity{}} <> Cl.Alert{"query", Cl.Mention{}} <> Nil{}
  U32.is_eq(Cl.buf_unread_status(alerts, "!ABCDEroom"), 1)
    && U32.is_eq(Cl.buf_unread_status(alerts, "ABCDEroom"), 0)
    && U32.is_eq(Cl.buf_unread_status(Cl.del_unread_items(alerts, "ABCDEroom"), "!ABCDEroom"), 1)
    && U32.is_eq(Cl.buf_unread_status(Cl.del_unread_items(alerts, "QUERY"), "query"), 0)

def alerts_escalate_ok() -> Bool:
  +stg = Cl.mark_unread.check(False{}, False{}, "#T", Cl.settings0())
  +hl = Cl.mark_unread.check(False{}, True{}, "#t", stg)
  +later = Cl.mark_unread.check(False{}, False{}, "#T", hl)
  U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(stg), "#t"), 1)
    && U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(later), "#t"), 2)
    && Nat.is_eq(List.length(&2, Cl.Alert, Cl.settings_unreads(later)), 1n)

def query_source() -> Cl.Client:
  +a = Feed.feed(Cl.init("me", "s"), ":a!u@h PRIVMSG me :first")
  +b = Feed.feed(a, ":b!u@h PRIVMSG me :second")
  Feed.feed(b, ":a!u@h PRIVMSG me :third")

def query_collision_ok() -> Bool:
  +old = query_source()
  +new = Feed.feed(old, ":a!u@h NICK :B")
  Nat.is_eq(CL.nbuf(new), 2n) && String.eq(Cl.active_buf_name(new), "server")
    && String.eq(CL.buf_texts(new, 1n), "<a> first|<b> second|<a> third|a is now known as B|")
    && Nat.is_eq(List.length(&2, Cl.Alert, Cl.settings_unreads(Cl.get_settings(new))), 1n)
    && U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(new)), "B"), 2)
    && String.eq(H.extract_new_history(old, new), "B\tSYS\t\ta is now known as B\n")

def query_focus_ok() -> Bool:
  +source = query_source()
  +from = Feed.feed(Cl.set_active(source, 1n), ":a!u@h NICK :b")
  +dest = Feed.feed(Cl.set_active(source, 2n), ":a!u@h NICK :b")
  String.eq(Cl.active_buf_name(from), "b") && String.eq(Cl.active_buf_name(dest), "b")
    && U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(from)), "b"), 0)
    && Nat.is_eq(CL.nbuf(from), 2n) && Nat.is_eq(CL.nbuf(dest), 2n)

def query_normal_ok() -> Bool:
  +new = Feed.feed(Cl.set_active(query_source(), 1n), ":a!u@h NICK :c")
  +server = Feed.feed(Cl.init("me", "s"), ":server!u@h NICK :other")
  Nat.is_eq(CL.nbuf(new), 3n) && String.eq(Cl.active_buf_name(new), "c")
    && String.eq(CL.buf_texts(new, 2n), "<b> second|")
    && Nat.is_eq(CL.nbuf(server), 1n) && String.eq(Cl.active_buf_name(server), "server")

def fill_queries(n: Nat, cl: Cl.Client) -> Cl.Client:
  match n:
    case 0n: cl
    case 1n+p: fill_queries(p, Cl.client_log(Cl.client_log(cl, 1n, Cl.Msg{}, "a"), 2n, Cl.Msg{}, "b"))

def ids_increasing(lines: List<&2, Cl.Line>, +last: Nat) -> Bool:
  match lines:
    case Nil{}: True{}
    case Con{Cl.Line{_, _, _, _, +id}, t}: Nat.is_gt(id, last) && ids_increasing(t, id)

def query_merge_cap_ok() -> Bool:
  +old = fill_queries(600n, query_source())
  +new = Cl.set_active(Feed.feed(old, ":a!u@h NICK :b"), 1n)
  Nat.is_eq(CL.buf_nlines(new, 1n), Cl.SCROLL_CAP())
    && ids_increasing(Cl.active_buf_lines(new), 0n)
    && String.eq(H.extract_new_history(old, new), "b\tSYS\t\ta is now known as b\n")

def server_nick_ok() -> Bool:
  +server = Feed.feed(Cl.init("me", "s"), ":server!u@h PRIVMSG me :private")
  +source = Feed.feed(server, ":a!u@h PRIVMSG me :first")
  +renamed = Feed.feed(Cl.set_active(source, 1n), ":server!u@h NICK :other")
  +collision = Feed.feed(Cl.set_active(source, 2n), ":a!u@h NICK :server")
  +quit = Feed.feed(server, ":server!u@h QUIT :bye")
  +focus_control = Cl.set_active(server, 0n)
  +closed = Cl.drop_buf(server, 1n)
  Nat.is_eq(CL.buf_nlines(renamed, 0n), 0n) && String.eq(Cl.active_buf_name(renamed), "other")
    && Nat.is_eq(CL.nbuf(collision), 2n) && String.eq(Cl.active_buf_name(collision), "server")
    && Nat.is_eq(CL.buf_nlines(collision, 0n), 0n) && Nat.is_eq(CL.buf_nlines(collision, 1n), 3n)
    && U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(server)), "server"), 2)
    && U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(focus_control)), "server"), 2)
    && U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(closed)), "server"), 0)
    && Nat.is_eq(CL.buf_nlines(quit, 0n), 0n)
    && String.eq(CL.buf_texts(quit, 1n), "<server> private|<- server quit (bye)|")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("accepted_remote", accepted_remote_ok())
    Unit <- E.must("bounded_rejections", cap_rejections_ok())
    Unit <- E.must("auth_phase", auth_phase_ok())
    Unit <- E.must("alerts_isolated", alerts_isolated_ok())
    Unit <- E.must("alerts_escalate", alerts_escalate_ok())
    Unit <- E.must("query_collision", query_collision_ok())
    Unit <- E.must("query_focus", query_focus_ok())
    Unit <- E.must("query_normal", query_normal_ok())
    Unit <- E.must("query_merge_cap", query_merge_cap_ok())
    Unit <- E.must("legal_server_nick", server_nick_ok())
    IO.print("state_demo=ok")
