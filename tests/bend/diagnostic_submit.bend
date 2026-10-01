# Local diagnostic command and read-only send boundary, including offline use.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as Sess
import ../../src/bend/history.bend as History

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def no_out(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, outs): List.is_empty(&2, String, outs)

def one_out(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, outs): String.concat(outs)

def local_name(trip: Cl.Client & String & Sess.NetCmd) -> String:
  match trip:
    case (cl, _): Cl.active_buf_name(cl)

def main() -> IO(Unit):
  +cl = Cl.init("me", "s")
  +log = client(Sub.submit(cl, "/log"))
  do IO<Unit>:
    Unit <- E.must_eq("open_focus", Cl.active_buf_name(log), "*log*")
    Unit <- E.must("log_no_wire", no_out(Sub.submit(cl, "/log")))
    Unit <- E.must("log_offline_classification", Bool.not(Sub.needs_connection(Sub.parse_input("/log"))))
    Unit <- E.must_eq("log_offline", local_name(Sess.submit_send(cl, Sub.parse_input("/log"), False{})), "*log*")
    Unit <- E.must("plain_readonly", no_out(Sub.submit(log, "private message")))
    Unit <- E.must("action_readonly", no_out(Sub.submit(log, "/me action")))
    Unit <- E.must("explicit_msg_readonly", no_out(Sub.submit(cl, "/msg *log* private message")))
    Unit <- E.must("explicit_query_readonly", no_out(Sub.submit(cl, "/query *LOG* private message")))
    Unit <- E.must_eq("ordinary_msg", one_out(Sub.submit(cl, "/msg alice hi")), "PRIVMSG alice :hi")
    Unit <- E.must("close_no_wire", no_out(Sub.submit(log, "/close")))
    Unit <- E.must_eq("close_reopen", Cl.active_buf_name(client(Sub.submit(client(Sub.submit(log, "/close")), "/log"))), "*log*")
    Unit <- E.must_eq("not_persisted", History.extract_new_history(cl, Cl.diagnostic(log, Cl.System{}, "diagnostic")), "")
    Unit <- E.must_eq("canonical_alias", Cl.active_buf_name(client(Sub.submit(cl, "/query *LOG*"))), "*log*")
    IO.print("diagnostic_submit=ok\n")
