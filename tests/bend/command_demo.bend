import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as Sess

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def result_client(triple: Cl.Client & String & Sess.NetCmd) -> Cl.Client:
  match triple:
    case (cl, _, _): cl

def no_wire(triple: Cl.Client & String & Sess.NetCmd) -> Bool:
  match triple:
    case (_, _, Sess.Cont{xs}): Nat.is_eq(List.length(&2, String, xs), 0n)
    case _: False{}

def submit_no_wire(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, xs): Nat.is_eq(List.length(&2, String, xs), 0n)

def local_commands(+net: Sess.NetState) -> Bool:
  +cl = Cl.init("me", "s")
  +settings = result_client(Sess.apply_keys(cl, net, 6667, "/settings", True{}, False{}))
  +disabled = result_client(Sess.apply_keys(settings, net, 6667, "/set autoreconn off", True{}, False{}))
  +preview = result_client(Sess.apply_keys(cl, net, 6667, "/preview /tmp/x.png", True{}, False{}))
  +search = result_client(Sess.apply_keys(cl, net, 6667, "/search hello", True{}, False{}))
  String.eq(Sub.active_name(settings), "*settings*")
    && Bool.not(Cl.settings_autoreconn(Cl.get_settings(disabled)))
    && String.eq(Sub.active_name(preview), "*preview*")
    && String.eq(Sub.active_name(search), "*search*")

def channel() -> Cl.Client:
  client(Sub.submit(Cl.init("me", "s"), "/join #x"))

def endpoint_switch_ok() -> Bool:
  +cl = channel()
  +same = Sess.endpoint_client(cl, "s", 6667, 6667)
  +host = Sess.endpoint_client(cl, "other", 6667, 6667)
  +port = Sess.endpoint_client(cl, "s", 6667, 6668)
  Nat.is_eq(Cl.buf_count(Cl.client_bufs(same)), 2n)
    && Nat.is_eq(Cl.buf_count(Cl.client_bufs(host)), 1n)
    && Nat.is_eq(Cl.buf_count(Cl.client_bufs(port)), 1n)
    && String.eq(Cl.server_of(host), "other")
    && Nat.is_eq(Cl.log_seq_of(host), Cl.log_seq_of(cl))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("offline_local", local_commands(Sess.Offline{}))
    Unit <- E.must("connecting_local", local_commands(Sess.Connecting{}))
    Unit <- E.must("offline_wire_rejected", no_wire(Sess.apply_keys(channel(), Sess.Offline{}, 6667, "hello", True{}, False{})))
    Unit <- E.must("connecting_wire_rejected", no_wire(Sess.apply_keys(channel(), Sess.Connecting{}, 6667, "/me hello", True{}, False{})))
    Unit <- E.must("offline_close_local", no_wire(Sess.apply_keys(channel(), Sess.Offline{}, 6667, "/close", True{}, False{})))
    Unit <- E.must("synthetic_me_rejected", submit_no_wire(Sub.submit(client(Sub.submit(Cl.init("me", "s"), "/settings")), "/me waves")))
    Unit <- E.must("channel_me_allowed", Bool.not(submit_no_wire(Sub.submit(channel(), "/me waves"))))
    Unit <- E.must("query_me_allowed", Bool.not(submit_no_wire(Sub.submit(client(Sub.submit(Cl.init("me", "s"), "/query alice")), "/me waves"))))
    Unit <- E.must("endpoint_switch", endpoint_switch_ok())
    IO.print("command_demo=ok")
