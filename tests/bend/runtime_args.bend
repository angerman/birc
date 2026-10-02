# Resolve nickname intent once, after the SASL user (CLI or env) is known.
import Base
import ./expect.bend as E
import ../../src/bend/args.bend as Args

def resolved(+env_user: String, got: Args.Parsed) -> String:
  match got:
    case Args.Bad{+msg}: "bad:" ++ msg
    case Args.Good{Args.Cfg{_, _, _, _, +nick, _, _, +user, _, explicit, _}}:
      Args.resolve_nick(nick, explicit, Bool.pick(String, String.is_empty(user), env_user, user))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("default_without_user", resolved("", Args.parse(Nil{})), "birc")
    Unit <- E.must_eq("default_cli_user", resolved("", Args.parse("--sasl-user" <> "alice" <> Nil{})), "alice")
    Unit <- E.must_eq("default_env_user", resolved("alice", Args.parse(Nil{})), "alice")
    Unit <- E.must_eq("cli_user_overrides_env", resolved("eve", Args.parse("--sasl-user" <> "alice" <> Nil{})), "alice")
    Unit <- E.must_eq("me_before_user", resolved("", Args.parse("--nick" <> "me" <> "--sasl-user" <> "alice" <> Nil{})), "me")
    Unit <- E.must_eq("me_after_user", resolved("", Args.parse("--sasl-user" <> "alice" <> "--nick" <> "me" <> Nil{})), "me")
    Unit <- E.must_eq("birc_before_user", resolved("", Args.parse("--nick" <> "birc" <> "--sasl-user" <> "alice" <> Nil{})), "birc")
    Unit <- E.must_eq("birc_after_user", resolved("", Args.parse("--sasl-user" <> "alice" <> "--nick" <> "birc" <> Nil{})), "birc")
    Unit <- E.must_eq("explicit_me_env", resolved("alice", Args.parse("--nick" <> "me" <> Nil{})), "me")
    Unit <- E.must_eq("explicit_birc_env", resolved("alice", Args.parse("--nick" <> "birc" <> Nil{})), "birc")
    IO.print("runtime_args=ok")
