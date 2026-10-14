# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/preferences.bend as P
import ../../src/bend/preferences_runtime.bend as R
import ../../src/bend/session.bend as Sess

def base() -> Sess.Session:
  Sess.session_demo_at(Cl.init("me", "irc.example"), "#room", 6667)

def enter(st: Sess.Session, text: String) -> Sess.Session:
  Sess.st_of_keys(Sess.step_enter(st, text))

def nicks(st: Sess.Session) -> Bool:
  Cl.settings_nicks(Cl.get_settings(Sess.session_cl(st)))

def edits(st: Sess.Session) -> String:
  String.join(Sess.session_preference_edits(st), "|")

def wire_on() -> String:
  "BIRC_PREFS1\nsettings\t1\t1\t1\t1\t100\t0\t1\t1\t1\n"

def wire_off() -> String:
  "BIRC_PREFS1\nsettings\t1\t1\t1\t1\t100\t0\t1\t1\t0\n"

def wire_legacy() -> String:
  "BIRC_PREFS1\nsettings\t1\t1\t1\t1\t100\t0\t1\t1\n"

def shown(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "invalid"
    case Some{text}: text

def roundtrip(value: Maybe<&2, P.Preferences>) -> String:
  match value:
    case None{}: "invalid"
    case Some{prefs}: shown(P.serialize(prefs))

def applied_nicks(value: Maybe<&2, P.Preferences>) -> Bool:
  match value:
    case None{}: False{}
    case Some{prefs}: Cl.settings_nicks(Cl.get_settings(P.apply(Cl.init("me", "irc.example"), prefs)))

def mask_nicks(before: Maybe<&2, P.Preferences>, after: Maybe<&2, P.Preferences>) -> String:
  match before:
    case None{}: "invalid"
    case Some{b}:
      match after:
        case None{}: "invalid"
        case Some{a}: R.mask_text(R.edits(R.edits.empty(), b, a))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("nicks defaults on", nicks(base()))
    Unit <- E.must("set nicks off hides nick changes", Bool.not(nicks(enter(base(), "/set nicks off"))))
    Unit <- E.must_eq("nick alias records canonical intent", edits(enter(base(), "/set nick off")), "nicks")
    Unit <- E.must("toggle nick flips value", nicks(enter(enter(base(), "/set nicks off"), "/toggle nick")))
    Unit <- E.must_eq("show-only set records no intent", edits(enter(base(), "/set nicks")), "")
    Unit <- E.must("invalid set keeps value and records no intent", nicks(enter(base(), "/set nicks maybe")) && String.is_empty(edits(enter(base(), "/set nicks maybe"))))
    Unit <- E.must_eq("nicks off round-trips exactly", roundtrip(P.parse(wire_off())), wire_off())
    Unit <- E.must("legacy settings default nicks on", applied_nicks(P.parse(wire_legacy())))
    Unit <- E.must("nicks off applies to client", Bool.not(applied_nicks(P.parse(wire_off()))))
    Unit <- E.must_eq("nicks-only change marks trailing edit bit", mask_nicks(P.parse(wire_on()), P.parse(wire_off())), "00000000001")
    IO.print("settings_nicks_demo=ok")
