# Splitting preserves all source text, complete clusters, and local/wire parity.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as S
import ../../src/bend/history.bend as H
import ../../src/bend/session.bend as Sess

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def base() -> Cl.Client:
  client(S.submit(Cl.init("me", "irc.example"), "/join #room"))

def bodies.one(parsed: Maybe<&2, Irc.Message>) -> String:
  match parsed:
    case None{}: "[invalid]"
    case Some{m}: Irc.msg_param(m, 1n)

def bodies(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: bodies.one(Irc.parse(h)) ++ bodies(t)

def wire_ok(+xs: List<&2, String>, +want: String, n: Nat) -> Bool:
  S.out_all_ok(xs) && String.eq(bodies(xs), want) && Nat.is_eq(List.length(&2, String, xs), n)

def echoes(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{wire, rest}: "<me> " ++ bodies.one(Irc.parse(wire)) ++ "|" ++ echoes(rest)

def split_ok(pair: Cl.Client & List<&2, String>, +want: String, +n: Nat) -> Bool:
  match pair:
    case (+cl, +outs):
      wire_ok(outs, want, n) && Nat.is_eq(CL.buf_nlines(cl, 1n), n)
        && String.eq(CL.buf_texts(cl, 1n), echoes(outs))

def repeat(n: Nat, +s: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: s ++ repeat(p, s)

def secret_ok(pair: Cl.Client & List<&2, String>, +want: String, send: Bool) -> Bool:
  match pair:
    case (+cl, +outs):
      Bool.not(String.contains(CL.buf_texts(cl, Cl.active_of(cl)), "opaque-secret"))
        && Bool.pick(Bool, send, String.eq(String.concat(outs), want), List.is_empty(&2, String, outs))

def cluster_boundary(pair: Cl.Client & List<&2, String>, +first: String, +second: String) -> Bool:
  match pair:
    case (_, Con{a, Con{b, Nil{}}}):
      String.eq(bodies.one(Irc.parse(a)), first) && String.eq(bodies.one(Irc.parse(b)), second)
    case _: False{}

def boundary_body(+target: String, notice: Bool) -> String:
  Irc.stars.go(Nat.sub(Irc.LINE_MAX(), Irc.utf8_len(S.message_wire(target, "", notice))))
    ++ "IDENTIFY opaque-secret"

def composer_len.session(st: Sess.Session) -> Nat:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, hist, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: Sess.hist_len(hist)

def composer_len.result(result: Sess.Session & Sess.NetCmd & Bool) -> Nat:
  match result:
    case (st, _): composer_len.session(st)

def composer_len(+cl: Cl.Client, input: String) -> Nat:
  composer_len.result(Sess.step_enter(Sess.session_online(Sess.session_with_client(cl, "#room")), input))

def boundary_private(+cl: Cl.Client, +target: String, +input: String, +body: String) -> Bool:
  +after = client(S.submit(cl, input))
  Bool.not(S.credential_message(cl, target, body)) && S.input_sensitive(cl, input)
    && List.is_empty(&2, String, Pair.snd(Cl.Client, List<&2, String>, S.submit(cl, input)))
    && Bool.not(String.contains(CL.buf_texts(after, Cl.active_of(after)), "opaque-secret"))
    && Bool.not(String.contains(H.extract_new_history_for("irc.example:6667", cl, after), "opaque-secret"))
    && Nat.is_eq(composer_len(cl, input), 0n)

def ordinary_boundary(+cl: Cl.Client, +input: String, +body: String) -> Bool:
  +after = client(S.submit(cl, input))
  Bool.not(S.input_sensitive(cl, input))
    && wire_ok(Pair.snd(Cl.Client, List<&2, String>, S.submit(cl, input)), body, 2n)
    && String.contains(CL.buf_texts(after, Cl.active_of(after)), "IDENTIFY opaque-secret")
    && Nat.is_eq(composer_len(cl, input), 1n)

def no_credentials(+cl: Cl.Client, outs: List<&2, String>) -> Bool:
  match outs:
    case Nil{}: True{}
    case Con{wire, rest}: Bool.not(S.credential_wire(cl, Irc.parse(wire))) && no_credentials(cl, rest)

def action_boundary(+cl: Cl.Client, +body: String) -> Bool:
  +input = "/me " ++ body
  +outs = Pair.snd(Cl.Client, List<&2, String>, S.submit(cl, input))
  Bool.not(S.input_sensitive(cl, input)) && S.out_all_ok(outs)
    && Nat.is_eq(List.length(&2, String, outs), 2n)
    && no_credentials(cl, outs)

def main() -> IO(Unit):
  +cl = base()
  +ascii = Irc.stars.go(1000n)
  +accent = "e" ++ SCon{Chr{769}, ""}
  +emoji: String = SCon{Chr{128105}, SCon{Chr{8205}, SCon{Chr{128187}, ""}}}
  +flag: String = SCon{Chr{127472}, SCon{Chr{127479}, ""}}
  +long_secret = "IDENTIFY opaque-secret" ++ Irc.stars.go(600n)
  +oversized_cluster = "e" ++ repeat(260n, SCon{Chr{769}, ""})
  +boundary = boundary_body("NickServ", False{})
  +notice_boundary = boundary_body("NickServ", True{})
  +service = Cl.client_set_auth(cl, Cl.NickServOnly{}, "irc.example", 6667,
    "AccountService!service@services.host", "confirmed", "account", "profile-password")
  +configured_boundary = boundary_body("AccountService", False{})
  +service_query = client(S.submit(cl, "/query NickServ"))
  +action_body = Irc.stars.go(Nat.sub(Irc.LINE_MAX(), Irc.utf8_len(Irc.format_privmsg("NickServ", S.ctcp_action("")))))
    ++ "IDENTIFY opaque-secret"
  do IO<Unit>:
    Unit <- E.must("long ASCII splits without loss", split_ok(S.submit(cl, ascii), ascii, 3n))
    Unit <- E.must("short text remains one line", split_ok(S.submit(cl, "hi"), "hi", 1n))
    Unit <- E.must("UTF8 splits without loss", split_ok(S.submit(cl, repeat(400n, "漢")), repeat(400n, "漢"), 3n))
    Unit <- E.must("combining cluster stays whole", cluster_boundary(S.submit(cl, Irc.stars.go(494n) ++ accent), Irc.stars.go(494n), accent))
    Unit <- E.must("ZWJ cluster stays whole", cluster_boundary(S.submit(cl, Irc.stars.go(492n) ++ emoji), Irc.stars.go(492n), emoji))
    Unit <- E.must("regional indicator pair stays whole", cluster_boundary(S.submit(cl, Irc.stars.go(492n) ++ flag), Irc.stars.go(492n), flag))
    Unit <- E.must("action combining cluster stays whole", cluster_boundary(S.submit(cl, "/me " ++ Irc.stars.go(485n) ++ accent), S.ctcp_action(Irc.stars.go(485n)), S.ctcp_action(accent)))
    Unit <- E.must("action ZWJ cluster stays whole", cluster_boundary(S.submit(cl, "/me " ++ Irc.stars.go(480n) ++ emoji), S.ctcp_action(Irc.stars.go(480n)), S.ctcp_action(emoji)))
    Unit <- E.must("notice splits without loss", wire_ok(Pair.snd(Cl.Client, List<&2, String>, S.submit(cl, "/notice alice " ++ ascii)), ascii, 3n))
    Unit <- E.must("oversize credentials rejected without truncation or split", secret_ok(S.submit(cl, "/msg NickServ " ++ long_secret), "", False{}))
    Unit <- E.must("oversize notice credentials rejected without split", secret_ok(S.submit(cl, "/notice NickServ " ++ long_secret), "", False{}))
    Unit <- E.must("oversize UTF8 credentials rejected without split", secret_ok(S.submit(cl, "/msg NickServ IDENTIFY opaque-secret" ++ repeat(200n, "漢")), "", False{}))
    Unit <- E.must("fitting credentials exact and redacted", secret_ok(S.submit(cl, "/msg NickServ IDENTIFY opaque-secret"), "PRIVMSG NickServ :IDENTIFY opaque-secret", True{}))
    Unit <- E.must("credential at later message chunk rejects all wires and history", boundary_private(cl, "NickServ", "/msg NickServ " ++ boundary, boundary))
    Unit <- E.must("credential at later notice chunk rejects all wires and history", boundary_private(cl, "NickServ", "/notice NickServ " ++ notice_boundary, notice_boundary))
    Unit <- E.must("notice trailing colon preserves split credential guard", boundary_private(cl, "NickServ", "/notice NickServ :" ++ notice_boundary, notice_boundary))
    Unit <- E.must("query text uses split credential guard", boundary_private(cl, "NickServ", "/query NickServ " ++ boundary, boundary))
    Unit <- E.must("plain service text uses split credential guard", boundary_private(service_query, "NickServ", boundary, boundary))
    Unit <- E.must("configured service uses split credential guard", boundary_private(service, "AccountService", "/msg AccountService " ++ configured_boundary, configured_boundary))
    Unit <- E.must("ordinary user later IDENTIFY chunk stays ordinary", ordinary_boundary(cl, "/msg alice " ++ boundary_body("alice", False{}), boundary_body("alice", False{})))
    Unit <- E.must("ordinary notice later IDENTIFY chunk stays ordinary", ordinary_boundary(cl, "/notice alice " ++ boundary_body("alice", True{}), boundary_body("alice", True{})))
    Unit <- E.must("ACTION envelope prevents a chunk becoming a service command", action_boundary(service_query, action_body))
    Unit <- E.must("one oversized cluster rejects the whole request", List.is_empty(&2, String, Pair.snd(Cl.Client, List<&2, String>, S.submit(cl, oversized_cluster))))
    Unit <- E.must("oversized cluster after fitting text still rejects all output", List.is_empty(&2, String, Pair.snd(Cl.Client, List<&2, String>, S.submit(cl, "okay " ++ oversized_cluster))))
    Unit <- E.must("one oversized action cluster rejects the whole request", List.is_empty(&2, String, Pair.snd(Cl.Client, List<&2, String>, S.submit(cl, "/me " ++ oversized_cluster))))
    IO.print("message_split=ok")
