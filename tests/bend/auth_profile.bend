# SPDX-License-Identifier: Apache-2.0
# Authentication remains scoped to one explicitly configured endpoint.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/auth.bend as Auth
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/history.bend as H

def prefix() -> String:
  "NickServ!service@services.example"

def confirmation() -> String:
  "You are now identified as account."

def notice(+body: String) -> String:
  ":" ++ prefix() ++ " NOTICE me :" ++ body

def welcome() -> String:
  ":actual.server 001 me :welcome"

def profile(mode: Cl.AuthMode) -> Cl.Client:
  Cl.client_set_auth(Cl.init("me", "irc.example"), mode, "irc.example", 6667, prefix(), confirmation(), "account", "secret")

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def wire(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, xs): String.join(xs, "|")

def seq(+cl: Cl.Client) -> String:
  Nat.show(Cl.auth_success_seq(cl))

def sasl_lines() -> List<&2, String>:
  [":actual.server CAP me ACK :sasl", "AUTHENTICATE +", ":actual.server 903 me :authenticated", welcome()]

def probing() -> Cl.Client:
  client(Sess.fold_lines(profile(Cl.NickServOnly{}), [welcome()]))

def identifying() -> Cl.Client:
  client(Sess.fold_lines(probing(), [notice("service help")]))

def credentials() -> Cl.Client:
  Cl.client_set_sasl(Cl.init("me", "irc.example"), "account", "secret")

def endpoint_controls() -> IO(Unit):
  +same = Sess.endpoint_client(credentials(), "irc.example", 6667, 6667)
  +host = Sess.endpoint_client(credentials(), "other.example", 6667, 6667)
  +port = Sess.endpoint_client(credentials(), "irc.example", 6667, 6668)
  +back = Sess.endpoint_client(host, "irc.example", 6667, 6667)
  +case_only = Sess.endpoint_client(credentials(), "IRC.EXAMPLE", 6667, 6667)
  do IO<Unit>:
    Unit <- E.must_eq("same endpoint retains credential", Cl.client_sasl_pass(same), "secret")
    Unit <- E.must_eq("host switch clears credential", Cl.client_sasl_pass(host), "")
    Unit <- E.must_eq("port switch clears credential", Cl.client_sasl_pass(port), "")
    Unit <- E.must_eq("returning to initial endpoint never restores credential", Cl.client_sasl_pass(back), "")
    Unit <- E.must("changed endpoints cannot enable SASL", Bool.not(Cl.client_has_sasl(host)) && Bool.not(Cl.client_has_sasl(port)))
    Unit <- E.must_eq("gate4 case-only clears credential", Cl.client_sasl_pass(case_only), "")
    IO.pure(Unit, Unit{})

def sasl_controls() -> IO(Unit):
  +base = profile(Cl.SaslOnly{})
  +good = client(Sess.fold_lines(base, sasl_lines()))
  +waiting = client(Sess.fold_lines(base, [":actual.server CAP me ACK :sasl", "AUTHENTICATE +"]))
  +again = client(Sess.fold_lines(Cl.reset_auth(good), sasl_lines()))
  +disabled = Sess.endpoint_client(good, "other.example", 6667, 6667)
  do IO<Unit>:
    Unit <- E.must_eq("SASL success survives 903 and 001 in one chunk", seq(good), "1")
    Unit <- E.must_eq("duplicate SASL success stays one event", seq(client(Sess.fold_lines(good, [":actual.server 903 me :duplicate"]))), "1")
    Unit <- E.must_eq("registration alone is not authentication", seq(client(Sess.fold_lines(base, [welcome()]))), "0")
    Unit <- E.must_eq("unsolicited SASL success cannot confirm", seq(client(Sess.fold_lines(base, [":actual.server 903 me :fake"]))), "0")
    Unit <- E.must_eq("user-prefixed numeric cannot confirm SASL", seq(client(Sess.fold_lines(waiting, [":peer!u@h 903 me :fake"]))), "0")
    Unit <- E.must_eq("numeric for another recipient cannot confirm", seq(client(Sess.fold_lines(waiting, [":actual.server 903 other :fake"]))), "0")
    Unit <- E.must_eq("success-looking chat cannot confirm", seq(client(Sess.fold_lines(waiting, [":peer!u@h PRIVMSG me :903 authenticated"]))), "0")
    Unit <- E.must_eq("reconnect reset preserves success count", seq(Cl.reset_auth(good)), "1")
    Unit <- E.must_eq("next verified connection advances once", seq(again), "2")
    Unit <- E.must_eq("endpoint invalidation preserves monotonic count", seq(disabled), "1")
    Unit <- E.must_eq("disabled profile cannot authenticate again", seq(client(Sess.fold_lines(disabled, sasl_lines()))), "1")
    IO.pure(Unit, Unit{})

def nickserv_controls() -> IO(Unit):
  +base = profile(Cl.NickServOnly{})
  +probe = probing()
  +sent = identifying()
  +good = client(Sess.fold_lines(sent, [notice(confirmation())]))
  +bold = "You are now identified as " ++ SCon{Chr{2}, "account" ++ SCon{Chr{2}, "."}}
  +echo = client(Sess.fold_lines(sent, [":me!u@h PRIVMSG NickServ :IDENTIFY account secret"]))
  do IO<Unit>:
    Unit <- E.must("NickServ mode does not request SASL", Bool.not(Cl.client_has_sasl(base)))
    Unit <- E.must_eq("welcome sends only harmless identity probe", wire(Sess.fold_lines(base, [welcome()])), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("welcome never confirms auth", seq(probe), "0")
    Unit <- E.must_eq("unverified service nickname receives no password", wire(Sess.fold_lines(probe, [":NickServ!impostor@evil.example NOTICE me :help"])), "")
    Unit <- E.must_eq("wrong service prefix case receives no password", wire(Sess.fold_lines(probe, [":NickServ!Service@services.example NOTICE me :help"])), "")
    Unit <- E.must_eq("wrong probe recipient receives no password", wire(Sess.fold_lines(probe, [":" ++ prefix() ++ " NOTICE other :help"])), "")
    Unit <- E.must_eq("trusted ordinary PRIVMSG is not service probe", wire(Sess.fold_lines(probe, [":" ++ prefix() ++ " PRIVMSG me :help"])), "")
    Unit <- E.must_eq("trusted probe releases one exact IDENTIFY", wire(Sess.fold_lines(probe, [notice("service help")])), "PRIVMSG NickServ :IDENTIFY account secret")
    Unit <- E.must_eq("IDENTIFY dispatch alone is not success", seq(sent), "0")
    Unit <- E.must_eq("duplicate help cannot repeat IDENTIFY", wire(Sess.fold_lines(sent, [notice("service help")])), "")
    Unit <- E.must_eq("untrusted confirmation cannot confirm", seq(client(Sess.fold_lines(sent, [":NickServ!impostor@evil.example NOTICE me :" ++ confirmation()]))), "0")
    Unit <- E.must_eq("confirmation for another nick cannot confirm", seq(client(Sess.fold_lines(sent, [":" ++ prefix() ++ " NOTICE other :" ++ confirmation()]))), "0")
    Unit <- E.must_eq("confirmation text must match exactly", seq(client(Sess.fold_lines(sent, [notice(confirmation() ++ " extra")]))), "0")
    Unit <- E.must_eq("confirmation text case is significant", seq(client(Sess.fold_lines(sent, [notice("you are now identified as account.")]))), "0")
    Unit <- E.must_eq("trusted display confirmation confirms", seq(good), "1")
    Unit <- E.must_eq("IRC formatting does not change exact display text", seq(client(Sess.fold_lines(sent, [notice(bold)]))), "1")
    Unit <- E.must_eq("duplicate NickServ confirmation stays one event", seq(client(Sess.fold_lines(good, [notice(confirmation())]))), "1")
    Unit <- E.must("trusted probe and confirmation never create chat", Bool.not(CL.has_buf(good, "NickServ")))
    Unit <- E.must("credential self echo never creates chat", Bool.not(CL.has_buf(echo, "NickServ")))
    Unit <- E.must("automatic credential never enters history", Bool.not(String.contains(H.extract_new_history_for("irc.example:6667", base, good), "secret")) && Bool.not(String.contains(H.extract_new_history_for("irc.example:6667", sent, echo), "secret")))
    IO.pure(Unit, Unit{})

def fallback_controls() -> IO(Unit):
  +base = profile(Cl.SaslNickServ{})
  +failure: List<&2, String> = [":actual.server CAP me ACK :sasl", "AUTHENTICATE +", ":actual.server 904 me :bad password", welcome(), notice("service help")]
  do IO<Unit>:
    Unit <- E.must("fallback still prefers SASL", Cl.client_has_sasl(base))
    Unit <- E.must_eq("CAP NAK enables only harmless fallback probe", wire(Sess.fold_lines(base, [":actual.server CAP me NAK :sasl", welcome()])), "CAP END|PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("server CAP unavailable enables fallback", wire(Sess.fold_lines(base, [":actual.server 421 me CAP :unknown command", welcome()])), "CAP END|PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("user CAP unavailable cannot enable fallback", wire(Sess.fold_lines(base, [":peer!u@h 421 me CAP :fake", welcome()])), "")
    Unit <- E.must_eq("unavailable numeric must name our nick", wire(Sess.fold_lines(base, [":actual.server 421 other CAP :fake", welcome()])), "")
    Unit <- E.must_eq("unavailable must name CAP", wire(Sess.fold_lines(base, [":actual.server 421 me OTHER :fake", welcome()])), "")
    Unit <- E.must("password failure never falls back", Bool.not(String.contains(wire(Sess.fold_lines(base, failure)), "PRIVMSG NickServ")))
    Unit <- E.must_eq("password failure does not confirm", seq(client(Sess.fold_lines(base, failure))), "0")
    Unit <- E.must_eq("SASL-only rejection never sends NickServ", wire(Sess.fold_lines(profile(Cl.SaslOnly{}), [":actual.server CAP me NAK :sasl", welcome()])), "CAP END")
    IO.pure(Unit, Unit{})

def credential_controls() -> IO(Unit):
  +long = Cl.client_set_auth(Cl.init("me", "irc.example"), Cl.NickServOnly{}, "irc.example", 6667, prefix(), confirmation(), "account", String.repeat("漢", 180n))
  +spaced = Cl.client_set_auth(Cl.init("me", "irc.example"), Cl.NickServOnly{}, "irc.example", 6667, prefix(), confirmation(), "account", "has space")
  +utf8 = Cl.client_set_auth(Cl.init("me", "irc.example"), Cl.NickServOnly{}, "irc.example", 6667, prefix(), confirmation(), "account", "päss")
  do IO<Unit>:
    Unit <- E.must("full prefix is required", Bool.not(Auth.valid_prefix("NickServ")))
    Unit <- E.must("wildcard identity is rejected", Bool.not(Auth.valid_prefix("NickServ!*@services.example")))
    Unit <- E.must("service wire delimiters are rejected", Bool.not(Auth.valid_prefix("NickServ,other!u@host")))
    Unit <- E.must("exact configured identity is accepted", Auth.valid_prefix(prefix()))
    Unit <- E.must_eq("oversize UTF8 credential is not truncated", wire(Sess.fold_lines(long, [welcome(), notice("service help")])), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("NickServ cannot split a credential into arguments", wire(Sess.fold_lines(spaced, [welcome(), notice("service help")])), "PRIVMSG NickServ :HELP")
    Unit <- E.must_eq("fitting UTF8 credential stays exact", wire(Sess.fold_lines(utf8, [welcome(), notice("service help")])), "PRIVMSG NickServ :HELP|PRIVMSG NickServ :IDENTIFY account päss")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- endpoint_controls()
    Unit <- sasl_controls()
    Unit <- nickserv_controls()
    Unit <- fallback_controls()
    Unit <- credential_controls()
    IO.print("auth_profile=ok")
