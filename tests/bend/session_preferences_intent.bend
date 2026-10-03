# SPDX-License-Identifier: Apache-2.0
# Accepted local settings intent must survive even an unchanged value.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/media.bend as Media
import ../../src/bend/frame.bend as Fr

def base() -> Sess.Session:
  +cl = Cl.init("me", "irc.example")
  +settings = Cl.set_hist_cap(Cl.set_ts(Cl.get_settings(cl), True{}), 50)
  Sess.session_demo_at(Cl.set_settings(cl, settings), "#room", 6667)

def enter(st: Sess.Session, text: String) -> Sess.Session:
  Sess.st_of_keys(Sess.step_enter(st, text))

def edits(st: Sess.Session) -> String:
  String.join(Sess.session_preference_edits(st), "|")

def commands(xs: List<&2, String>, st: Sess.Session) -> Sess.Session:
  match xs:
    case Nil{}: st
    case Con{h, t}: commands(t, enter(st, h))

def same_value() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("fresh Session has no settings intent", edits(base()), "")
    Unit <- E.must_eq("same-value timestamp alias still records accepted intent", edits(enter(base(), "/set timestamp on")), "ts")
    Unit <- E.must("same-value setting stays unchanged", Cl.settings_ts(Cl.get_settings(Sess.session_cl(enter(base(), "/set ts on")))))
    Unit <- E.must_eq("same-value history cap alias records canonical intent", edits(enter(base(), "/set history_cap 50")), "hist_cap")
    Unit <- E.must_eq("same-value enabled image command records intent", edits(enter(base(), "/images on")), "images")
    Unit <- E.must_eq("unmute of absent entry records accepted intent", edits(enter(base(), "/unmute absent")), "mutes")
    IO.pure(Unit, Unit{})

def invalid() -> IO(Unit):
  +bad: List<&2, String> = "/set unknown on" <> "/set ts maybe" <> "/set ts on extra"
    <> "/set hist_cap nope" <> "/set hist_cap 4294967296"
    <> "/toggle hist_cap" <> "/toggle unknown" <> "/mute" <> "/unmute"
    <> "/images maybe" <> "/images on extra" <> Nil{}
  +show: List<&2, String> = "/set" <> "/set ts" <> "/images" <> "/mutes" <> Nil{}
  do IO<Unit>:
    Unit <- E.must_eq("invalid commands never create durable intent", edits(commands(bad, base())), "")
    Unit <- E.must_eq("show-only commands never create durable intent", edits(commands(show, base())), "")
    Unit <- E.must_eq("typing without Enter is not accepted intent", edits(Sess.st_of_keys(Sess.step_keys(base(), Sess.keys_of("/set ts on", False{}, 0, 0, 0, 0, 0, 0, 0)))), "")
    IO.pure(Unit, Unit{})

def bounded() -> IO(Unit):
  +all: List<&2, String> = "/set join on" <> "/toggle timestamps" <> "/set motd on"
    <> "/set hist on" <> "/set lines 50" <> "/set reconn off"
    <> "/set alert on" <> "/images off" <> "/mute alice" <> Nil{}
  +duplicates: List<&2, String> = "/set joins on" <> "/set ts on" <> "/toggle beep"
    <> "/set histcap 50" <> "/images off" <> "/unmute absent" <> Nil{}
  +st = commands(duplicates, commands(all, base()))
  do IO<Unit>:
    Unit <- E.must("intent is bounded to nine unique canonical names", Nat.is_eq(List.length(&2, String, Sess.session_preference_edits(st)), 9n))
    Unit <- E.must_eq("aliases and repeated edits retain first intent order", edits(st), "joins|ts|motd|history|hist_cap|autoreconn|bell|images|mutes")
    Unit <- E.must_eq("established toggle trailing-word acceptance is preserved", edits(enter(base(), "/toggle ts extra")), "ts")
    IO.pure(Unit, Unit{})

def retained() -> IO(Unit):
  +st = enter(base(), "/set ts on")
  +draft = Sess.st_of_keys(Sess.step_keys(st, Sess.keys_of("unsent draft", False{}, 0, 0, 0, 0, 0, 0, 0)))
  do IO<Unit>:
    Unit <- E.must_eq("non-key IO preserves intent", edits(Sess.st_of_chunk(Sess.step_on_chunk(st, Fr.string_to_octets("PING :test\r\n")))), "ts")
    Unit <- E.must_eq("reconnect preserves intent", edits(Sess.session_reconnected(enter(st, "/reconnect"), "12:00:00")), "ts")
    Unit <- E.must_eq("endpoint change preserves cumulative intent", edits(enter(st, "/connect other.example 6667")), "ts")
    Unit <- E.must_eq("loaded-client installation preserves intent", edits(Sess.session_set_client(st, Cl.init("me", "irc.example"))), "ts")
    Unit <- E.must_eq("intent hook preserves unsent draft", Sess.session_draft(draft), "unsent draft")
    Unit <- E.must("image setting still uses normal media policy", Bool.not(Media.enabled(Sess.session_media(enter(base(), "/images off")))))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- same_value()
    Unit <- invalid()
    Unit <- bounded()
    Unit <- retained()
    IO.print("session_preferences_intent=ok")
