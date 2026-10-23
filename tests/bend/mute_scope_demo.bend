import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/submit.bend as Sub
import ../../src/bend/isupport.bend as Is

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def channel(+name: String) -> Cl.Client:
  Feed.feed(Cl.init("me", "irc.example"), ":me!u@h JOIN " ++ name)

def muted_channel(+name: String) -> Cl.Client:
  client(Sub.submit(channel(name), "/mute alice"))

def suppressed_target(+target: String) -> Bool:
  +muted = Cl.set_active(muted_channel("#room"), 0n)
  +fed = Feed.feed(muted, ":alice!u@h PRIVMSG " ++ target ++ " :me hello")
  Nat.is_eq(Cl.log_seq_of(fed), Cl.log_seq_of(muted))
    && U32.is_eq(Cl.client_bell_seq(fed), Cl.client_bell_seq(muted))
    && Nat.is_eq(List.length(&2, Cl.Alert, Cl.settings_unreads(Cl.get_settings(fed))), 0n)

def accepted_target(+target: String) -> Bool:
  +muted = Cl.set_active(muted_channel("#room"), 0n)
  +fed = Feed.feed(muted, ":bob!u@h PRIVMSG " ++ target ++ " :me hello")
  Nat.is_eq(Cl.log_seq_of(fed), 1n+Cl.log_seq_of(muted))
    && U32.is_eq(Cl.client_bell_seq(fed), U32.add(Cl.client_bell_seq(muted), 1))
    && U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(fed)), "#room"), 2)

def restored_scoped(+name: String) -> Bool:
  +cl = muted_channel(name)
  +line = {Cl.Line{Cl.Msg{}, "", "<alice> old message", "alice", 1n} : Cl.Line}
  Cl.is_line_muted(Cl.settings_mutes(Cl.get_settings(cl)), line, name, "irc.example")
    && Bool.not(Cl.is_line_muted(Cl.settings_mutes(Cl.get_settings(cl)), line, name, "other.example"))
    && Bool.not(Cl.is_line_muted(Cl.settings_mutes(Cl.get_settings(cl)), line, "#other", "irc.example"))

def unmute_scoped(+name: String) -> Bool:
  +cl = Cl.add_mute_client(muted_channel(name), "alicex" ++ name ++ "@irc.example")
  +unmuted = client(Sub.submit(cl, "/unmute ALICE"))
  Bool.not(Cl.is_muted_client(unmuted, "alice", name))
    && Cl.is_muted_client(unmuted, "alicex", name)
    && Nat.is_eq(List.length(&2, String, Cl.settings_mutes(Cl.get_settings(unmuted))), 1n)

def ascii_state() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=# CASEMAPPING=ascii :are supported")

def mute_text(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, t}: h ++ "|" ++ mute_text(t)

def ascii_mute_base() -> Cl.Client:
  Cl.add_mute_client(Cl.init("me", "server"), "a{*@server")

def ascii_unmute_bracket() -> Cl.Client:
  client(Sub.submit_with(ascii_state(), ascii_mute_base(), "/unmute a["))

def ascii_unmute_brace() -> Cl.Client:
  client(Sub.submit_with(ascii_state(), ascii_unmute_bracket(), "/unmute a{"))

def ascii_unmute_keeps_brace() -> Bool:
  String.eq(mute_text(Cl.settings_mutes(Cl.get_settings(ascii_unmute_bracket()))), "a{*@server|")

def ascii_unmute_removes_brace() -> Bool:
  String.eq(mute_text(Cl.settings_mutes(Cl.get_settings(ascii_unmute_brace()))), "")

def unmute_exact() -> Bool:
  +cl = Cl.add_mute_client(muted_channel("&room"), "alice#other@irc.example")
  +unmuted = client(Sub.submit(cl, "/unmute alice&room@irc.example"))
  Bool.not(Cl.is_muted_client(unmuted, "alice", "&room"))
    && Cl.is_muted_client(unmuted, "alice", "#other")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("muted_plain_target", suppressed_target("#room"))
    Unit <- E.must("muted_operator_target", suppressed_target("@#room"))
    Unit <- E.must("muted_voice_target", suppressed_target("+#room"))
    Unit <- E.must("accepted_plain_target", accepted_target("#room"))
    Unit <- E.must("accepted_operator_target", accepted_target("@#room"))
    Unit <- E.must("accepted_voice_target", accepted_target("+#room"))
    Unit <- E.must("restored_hash_scope", restored_scoped("#room"))
    Unit <- E.must("restored_amp_scope", restored_scoped("&room"))
    Unit <- E.must("restored_plus_scope", restored_scoped("+room"))
    Unit <- E.must("restored_bang_scope", restored_scoped("!ABCDEroom"))
    Unit <- E.must("unmute_hash_scope", unmute_scoped("#room"))
    Unit <- E.must("unmute_amp_scope", unmute_scoped("&room"))
    Unit <- E.must("unmute_plus_scope", unmute_scoped("+room"))
    Unit <- E.must("unmute_bang_scope", unmute_scoped("!ABCDEroom"))
    Unit <- E.must("unmute_exact_pattern", unmute_exact())
    Unit <- E.must("ascii unmute bracket keeps brace pattern", ascii_unmute_keeps_brace())
    Unit <- E.must("ascii unmute brace removes brace pattern", ascii_unmute_removes_brace())
    IO.print("mute_scope_demo=ok")
