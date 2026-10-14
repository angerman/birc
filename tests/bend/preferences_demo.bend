# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/preferences.bend as P
import ../../src/bend/buffer.bend as Cl

def source() -> String:
  "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t1\nmute\talice*#room@irc.example\nchannel\t+#room\nchannel\t#日本語\n"

def legacy() -> String:
  "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\nmute\talice*#room@irc.example\nchannel\t+#room\nchannel\t#日本語\n"

def nicks_off() -> String:
  "BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t0\nmute\talice*#room@irc.example\nchannel\t+#room\nchannel\t#日本語\n"

def repeat(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+p: "a" ++ repeat(p)

def accepted(value: Maybe<&2, P.Preferences>) -> Bool:
  match value:
    case None{}: False{}
    case Some{_}: True{}

def known_scope(value: Maybe<&2, P.Preferences>) -> Bool:
  match value:
    case None{}: True{}
    case Some{prefs}: P.known_channels(prefs)

def shown(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: "invalid"
    case Some{text}: text

def roundtrip(value: Maybe<&2, P.Preferences>) -> String:
  match value:
    case None{}: "invalid"
    case Some{prefs}: shown(P.serialize(prefs))

def apply_ok(value: Maybe<&2, P.Preferences>) -> Bool:
  match value:
    case None{}: False{}
    case Some{+prefs}:
      +cl = Cl.client_credentials(Cl.init("me", "irc.example"), "synthetic-user", "synthetic-pass")
      +applied = P.apply(cl, prefs)
      +stg = Cl.get_settings(applied)
      String.eq(Cl.client_sasl_user(applied), "synthetic-user")
        && String.eq(Cl.client_sasl_pass(applied), "synthetic-pass")
        && Bool.not(Cl.settings_joins(stg)) && Cl.settings_ts(stg)
        && Cl.settings_nicks(stg)
        && Bool.not(Cl.settings_bell(stg)) && U32.is_eq(Cl.settings_hist_cap(stg), 200)
        && Bool.not(P.images(prefs)) && Nat.is_eq(List.length(&2, String, P.channels(prefs)), 2n)
        && String.eq(shown(P.serialize(P.capture(applied, False{}, P.channels(prefs)))), source())

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("preferences exact roundtrip including channel spelling/Unicode", roundtrip(P.parse(source())), source())
    Unit <- E.must_eq("legacy nine-field settings default nicks on and rewrite ten-field", roundtrip(P.parse(legacy())), source())
    Unit <- E.must_eq("nicks off round-trips exactly", roundtrip(P.parse(nicks_off())), nicks_off())
    Unit <- E.must("invalid nicks bit rejected", Bool.not(accepted(P.parse("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\t2\n"))))
    Unit <- E.must("preferences preserve credentials and runtime settings", apply_ok(P.parse(source())))
    Unit <- E.must("missing optional prefs has no snapshot", Bool.not(accepted(P.parse(""))))
    Unit <- E.must("future version rejected", Bool.not(accepted(P.parse("BIRC_PREFS2\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\n"))))
    Unit <- E.must("invalid boolean rejected", Bool.not(accepted(P.parse("BIRC_PREFS1\nsettings\t2\t1\t0\t1\t200\t1\t0\t0\n"))))
    Unit <- E.must("unknown secret field rejected", Bool.not(accepted(P.parse(source() ++ "password\tsecret\n"))))
    Unit <- E.must("duplicate channel rejected", Bool.not(accepted(P.parse(source() ++ "channel\t+#room\n"))))
    Unit <- E.must("key never enters saved channels", Bool.not(accepted(P.parse(source() ++ "channel\t#room key\n"))))
    Unit <- E.must("comma channel rejected", Bool.not(accepted(P.parse(source() ++ "channel\t#bad,other\n"))))
    Unit <- E.must("bare channel prefixes rejected", Bool.not(accepted(P.parse(source() ++ "channel\t#\n"))) && Bool.not(accepted(P.parse(source() ++ "channel\t&\n"))) && Bool.not(accepted(P.parse(source() ++ "channel\t+\n"))) && Bool.not(accepted(P.parse(source() ++ "channel\t!\n"))))
    Unit <- E.must("one-character channel body accepted", accepted(P.parse(source() ++ "channel\t#a\n")))
    Unit <- E.must("masked channel colon accepted without treating it as a key", accepted(P.parse(source() ++ "channel\t#room:*.fi\n")))
    Unit <- E.must("masked channel plus key remains rejected", Bool.not(accepted(P.parse(source() ++ "channel\t#room:*.fi secret\n"))))
    Unit <- E.must("standalone JOIN 505-byte name can be saved with settings", P.valid(P.capture(Cl.init("me", "irc.example"), True{}, ("#" ++ repeat(504n)) <> Nil{})))
    Unit <- E.must("506-byte channel cannot be saved", Bool.not(P.valid(P.capture(Cl.init("me", "irc.example"), True{}, ("#" ++ repeat(505n)) <> Nil{}))))
    Unit <- E.must("unknown endpoint scope accepted but not a saved channel list", Bool.not(known_scope(P.parse("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0\nscope\t0\n"))))
    Unit <- E.must("scope with channels rejected", Bool.not(accepted(P.parse(source() ++ "scope\t0\n"))))
    Unit <- E.must("non-channel rejected", Bool.not(accepted(P.parse(source() ++ "channel\tserver\n"))))
    Unit <- E.must("truncated snapshot rejected", Bool.not(accepted(P.parse("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t200\t1\t0\t0"))))
    Unit <- E.must("extra empty record rejected", Bool.not(accepted(P.parse(source() ++ "\n"))))
    Unit <- E.must("oversized U32 rejected", Bool.not(accepted(P.parse("BIRC_PREFS1\nsettings\t0\t1\t0\t1\t4294967296\t1\t0\t0\n"))))
    IO.print("preferences_demo=ok\n")
