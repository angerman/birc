# SPDX-License-Identifier: Apache-2.0
# Manual service credentials keep their wire bytes, not chat/history copies.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as S
import ../../src/bend/history.bend as H
import ../../src/bend/frame.bend as F

def secret() -> String:
  "synthetic-password"

def take_cl(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def take_wire(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, xs): String.join(xs, "|")

def result_st(trip: S.Session & S.NetCmd & Bool) -> S.Session:
  match trip:
    case (st, _): st

def result_hist(+st: S.Session) -> S.Hist:
  match st:
    case S.Session{_, _, _, _, _, _, _, hist, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: hist

def private_ok() -> Bool:
  +base = Cl.init("me", "irc")
  +after = take_cl(Sub.submit(base, "/msg NickServ IDENTIFY account " ++ secret()))
  String.eq(take_wire(Sub.submit(base, "/msg NickServ IDENTIFY account " ++ secret())),
      "PRIVMSG NickServ :IDENTIFY account " ++ secret())
    && Bool.not(String.contains(CL.buf_texts(after, Cl.active_of(after)), secret()))
    && Bool.not(String.contains(H.extract_new_history_for("irc:6667", base, after), secret()))

def composer_ok() -> Bool:
  +st = S.session_online(S.session_with_client(Cl.init("me", "irc"), "#room"))
  +after = result_st(S.step_enter(st, "/msg NickServ IDENTIFY " ++ secret()))
  Nat.is_eq(S.hist_len(result_hist(after)), 0n)

def ordinary_ok() -> Bool:
  +base = Cl.init("me", "irc")
  +after = take_cl(Sub.submit(base, "/msg bob IDENTIFY " ++ secret()))
  +st = S.session_online(S.session_with_client(base, "#room"))
  String.eq(take_wire(Sub.submit(base, "/msg bob IDENTIFY " ++ secret())),
      "PRIVMSG bob :IDENTIFY " ++ secret())
    && String.contains(CL.buf_texts(after, Cl.active_of(after)), secret())
    && Nat.is_eq(S.hist_len(result_hist(result_st(S.step_enter(st, "/msg bob IDENTIFY " ++ secret())))), 1n)

def protected(+cl: Cl.Client, +input: String, +wire: String) -> Bool:
  +after = take_cl(Sub.submit(cl, input))
  String.eq(take_wire(Sub.submit(cl, input)), wire)
    && String.contains(CL.buf_texts(after, Cl.active_of(after)), "[credential command sent]")
    && Bool.not(String.contains(CL.buf_texts(after, Cl.active_of(after)), secret()))
    && Bool.not(String.contains(H.extract_new_history_for("irc:6667", cl, after), secret()))
    && Sub.input_sensitive(cl, input)
    && Nat.is_eq(S.hist_len(result_hist(result_st(S.step_enter(
      S.session_online(S.session_with_client(cl, "#room")), input)))), 0n)

def service_verbs(verbs: List<&2, String>) -> Bool:
  match verbs:
    case Nil{}: True{}
    case Con{+verb, rest}:
      +body = verb ++ " account " ++ secret()
      protected(Cl.init("me", "irc"), "/msg nIcKsErV " ++ body, "PRIVMSG nIcKsErV :" ++ body)
        && service_verbs(rest)

def query_ok() -> Bool:
  +cl = take_cl(Sub.submit(Cl.init("me", "irc"), "/query NickServ"))
  protected(Cl.init("me", "irc"), "/query NickServ IDENTIFY " ++ secret(), "PRIVMSG NickServ :IDENTIFY " ++ secret())
    && protected(cl, "  IDENTIFY " ++ secret(), "PRIVMSG NickServ :  IDENTIFY " ++ secret())

def configured_ok() -> Bool:
  +cl = Cl.client_set_auth(Cl.init("me", "irc"), Cl.NickServOnly{}, "irc", 6667,
    "AccountService!service@services.host", "confirmed", "account", "profile-password")
  +query = take_cl(Sub.submit(cl, "/query AccountService"))
  protected(cl, "/msg AccountService IDENTIFY " ++ secret(), "PRIVMSG AccountService :IDENTIFY " ++ secret())
    && protected(query, "IDENTIFY " ++ secret(), "PRIVMSG AccountService :IDENTIFY " ++ secret())
    && protected(Cl.init("me", "irc"), "/msg NickServ@services.host IDENTIFY " ++ secret(),
      "PRIVMSG NickServ@services.host :IDENTIFY " ++ secret())
    && protected(Cl.init("me", "irc"), "/msg bob,NickServ IDENTIFY " ++ secret(),
      "PRIVMSG bob,NickServ :IDENTIFY " ++ secret())

def boundaries_ok() -> Bool:
  +cl = Cl.init("me", "irc")
  +body = "IDENTIFICATION " ++ secret()
  +after = take_cl(Sub.submit(cl, "/msg NickServ " ++ body))
  Bool.not(Sub.input_sensitive(cl, "/msg NickServ " ++ body))
    && String.contains(CL.buf_texts(after, Cl.active_of(after)), secret())
    && Bool.not(Sub.input_sensitive(cl, "/msg NickServ SET LANGUAGE " ++ secret()))
    && Bool.not(Sub.input_sensitive(cl, "/msg #NickServ IDENTIFY " ++ secret()))
    && Bool.not(Sub.input_sensitive(cl, "/msg AccountService IDENTIFY " ++ secret()))
    && protected(cl, "/msg   NickServ    iDeNtIfY  account  " ++ secret(),
      "PRIVMSG NickServ :iDeNtIfY  account  " ++ secret())
    && protected(cl, "/msg NickServ IDEN\rTIFY " ++ secret(), "PRIVMSG NickServ :IDENTIFY " ++ secret())

def navigation_hist(+target: String) -> S.Hist:
  +cl = take_cl(Sub.submit(Cl.init("me", "irc"), "/query " ++ target))
  result_hist(result_st(S.step_keys(S.session_online(S.session_with_client(cl, "#room")),
    S.keys_of("IDENTIFY " ++ secret(), True{}, 1, 0, 0, 0, 0, 0, 0))))

def navigation_ok() -> Bool:
  Nat.is_eq(S.hist_len(navigation_hist("NickServ")), 0n)
    && Nat.is_eq(S.hist_len(navigation_hist("bob")), 1n)

def echo_cl(+line: String) -> Cl.Client:
  S.session_cl(S.st_of_chunk(S.step_on_chunk_ms(
    S.session_online(S.session_with_client(Cl.init("me", "irc"), "#room")),
    F.string_to_octets(line ++ "\r\n"), 1000)))

def echo_ok() -> Bool:
  +echo = ":me!u@h PRIVMSG NickServ :IDENTIFY " ++ secret()
  +peer = ":alice!u@h PRIVMSG me :IDENTIFY " ++ secret()
  +ordinary = ":me!u@h PRIVMSG bob :IDENTIFY " ++ secret()
  Sub.credential_echo(Cl.init("me", "irc"), echo)
    && Bool.not(Sub.credential_echo(Cl.init("me", "irc"), peer))
    && Bool.not(Sub.credential_echo(Cl.init("me", "irc"), ordinary))
    && Nat.is_eq(CL.nbuf(echo_cl(echo)), 1n)
    && String.contains(CL.buf_texts(echo_cl(peer), 1n), secret())
    && String.contains(CL.buf_texts(echo_cl(ordinary), 1n), secret())

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("ordinary peer IDENTIFY remains chat", ordinary_ok())
    Unit <- E.must("manual credentials stay off local echo and persisted history", private_ok())
    Unit <- E.must("manual credentials stay out of composer history", composer_ok())
    Unit <- E.must("supported credential verbs keep exact wire with safe copies", service_verbs(
      "IDENTIFY" <> "LOGIN" <> "REGISTER" <> "GHOST" <> "RECOVER" <> "RELEASE" <> "SET PASSWORD" <> Nil{}))
    Unit <- E.must("query text and active service query are private", query_ok())
    Unit <- E.must("configured service and service-qualified targets are private", configured_ok())
    Unit <- E.must("complete words and ordinary targets keep their old behavior", boundaries_ok())
    Unit <- E.must("history classification precedes simultaneous navigation", navigation_ok())
    Unit <- E.must("only our service credential wire echo is suppressed", echo_ok())
    IO.print("auth_privacy=ok")
