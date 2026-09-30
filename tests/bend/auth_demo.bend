import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/session.bend as Sess
import ../../src/bend/irc.bend as Irc

def credentials() -> Cl.Client:
  Cl.client_set_sasl(Cl.init("me", "s"), "user", "pass")

def outs(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, xs): String.concat(xs)

def auth_after(pair: Cl.Client & List<&2, String>, +line: String) -> String:
  match pair:
    case (cl, _): outs(Sess.fold_lines(cl, line <> Nil{}))

def chat_kept(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (+cl, xs):
      Nat.is_eq(List.length(&2, String, xs), 0n) && String.contains(CL.buf_texts(cl, 1n), "AUTHENTICATE + 903 ")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("parsed_ack", Irc.is_cap_ack_sasl(":s CAP me ACK :server-time sasl"))
    Unit <- E.must("chat_not_ack", Bool.not(Irc.is_cap_ack_sasl(":a PRIVMSG me :CAP ACK sasl")))
    Unit <- E.must("exact_capability", Bool.not(Irc.is_cap_ack_sasl(":s CAP me ACK :not-sasl")))
    Unit <- E.must("chat_not_auth", Bool.not(Irc.is_authenticate_plus(":a PRIVMSG me :AUTHENTICATE +")))
    Unit <- E.must("exact_auth", Bool.not(Irc.is_authenticate_plus("AUTHENTICATE +suffix")))
    Unit <- E.must("chat_not_success", Bool.not(Irc.is_sasl_success(":a PRIVMSG me :text 903 here")))
    Unit <- E.must("unsolicited_challenge", String.is_empty(outs(Sess.fold_lines(credentials(), "AUTHENTICATE +" <> Nil{}))))
    Unit <- E.must("unsolicited_success", String.is_empty(outs(Sess.fold_lines(credentials(), ":s 903 me :ok" <> Nil{}))))
    Unit <- E.must("chat_kept", chat_kept(Sess.fold_lines(credentials(), ":a PRIVMSG me :AUTHENTICATE + 903 " <> Nil{})))
    Unit <- E.must("valid_exchange", String.eq(outs(Sess.fold_lines(credentials(), ":s CAP me ACK :sasl" <> "AUTHENTICATE +" <> ":s 903 me :ok" <> Nil{})), "AUTHENTICATE PLAINAUTHENTICATE AHVzZXIAcGFzcw==CAP END"))
    Unit <- E.must("phase_survives_chunk", String.eq(auth_after(Sess.fold_lines(credentials(), ":s CAP me ACK :sasl" <> Nil{}), "AUTHENTICATE +"), "AUTHENTICATE AHVzZXIAcGFzcw=="))
    Unit <- E.must("no_credentials", String.is_empty(outs(Sess.fold_lines(Cl.init("me", "s"), ":s CAP me ACK :sasl" <> "AUTHENTICATE +" <> Nil{}))))
    Unit <- E.must("completed_no_restart", String.is_empty(auth_after(Sess.fold_lines(credentials(), ":s CAP me ACK :sasl" <> "AUTHENTICATE +" <> ":s 903 me :ok" <> Nil{}), ":s CAP me ACK :sasl")))
    Unit <- E.must("valid_rejection", String.eq(outs(Sess.fold_lines(credentials(), ":s CAP me NAK :sasl" <> Nil{})), "CAP END"))
    Unit <- E.must("valid_failure", String.eq(outs(Sess.fold_lines(credentials(), ":s CAP me ACK :sasl" <> ":s 904 me :failed" <> Nil{})), "AUTHENTICATE PLAINCAP END"))
    IO.print("auth_demo=ok")
