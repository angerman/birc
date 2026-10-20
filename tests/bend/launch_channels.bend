# SPDX-License-Identifier: Apache-2.0
# Names-only profile/CLI CSV must populate the actual Session recovery plan.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/frame.bend as Fr
import ../../src/bend/args.bend as Args

def initial(channels: String) -> Sess.Session:
  Sess.session_with_client_at(Cl.init("me", "irc.example"), channels, 6667)

def welcome(st: Sess.Session) -> Sess.Session & List<&2, String>:
  # JOIN flush needs post-welcome MOTD (376/422), not 001 alone.
  Sess.step_on_chunk(st, Fr.string_to_octets(":irc.example 001 me :welcome\r\n:irc.example 376 me :end of MOTD\r\n"))

def wire(pair: Sess.Session & List<&2, String>) -> String:
  match pair:
    case (_, outs): String.join(outs, "|")

def entered(st: Sess.Session, line: String) -> Sess.Session:
  Sess.st_of_keys(Sess.step_enter(st, line))

def fresh() -> String:
  wire(Sess.step_on_chunk(entered(Sess.session_online(initial("#one,#two,+#third")), "/connect other.example 6667"),
    Fr.string_to_octets(":other.example 001 me :welcome\r\n:other.example 376 me :end of MOTD\r\n")))

def names(st: Sess.Session) -> String:
  String.join(Sess.session_desired_channels(st), "|")

def many(n: Nat) -> String:
  match n:
    case 0n: ""
    case 1n+ +p: "#c" ++ Nat.show(p) ++ Bool.pick(String, Nat.is_eq(p, 0n), "", ",") ++ many(p)

def accepted(parsed: Args.Parsed) -> Bool:
  match parsed:
    case Args.Good{_}: True{}
    case Args.Bad{_}: False{}

def cli(text: String) -> Bool:
  accepted(Args.parse("--channel" <> text <> Nil{}))

def cli_controls() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("CLI accepts names-only channel CSV", cli("#one,#two,+#third"))
    Unit <- E.must("CLI accepts explicit empty autojoin", cli(""))
    Unit <- E.must("CLI accepts fourteen channel entries", cli(many(14n)))
    Unit <- E.must("CLI rejects a fifteenth channel entry", Bool.not(cli(many(15n))))
    Unit <- E.must("CLI rejects unknown non-channel target", Bool.not(cli("someone")))
    Unit <- E.must("CLI rejects an empty CSV member", Bool.not(cli("#one,,#two")))
    Unit <- E.must("CLI rejects joining keys in channel metadata", Bool.not(cli("#one secret-key")))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("multi-channel launch rejoins every names-only CSV member", wire(welcome(initial("#one,#two,+#third"))), "JOIN #one|JOIN #two|JOIN +#third")
    Unit <- E.must_eq("single-channel launch behavior remains unchanged", wire(welcome(initial("#one"))), "JOIN #one")
    Unit <- E.must_eq("empty launch means no automatic JOIN", wire(welcome(initial(""))), "")
    Unit <- E.must_eq("unknown non-channel launch target remains absent", wire(welcome(initial("someone"))), "")
    Unit <- E.must_eq("membership names retain actual plus-channel identity", names(initial("+#third")), "+#third")
    Unit <- E.must_eq("changed endpoint still seeds complete initial channel CSV", fresh(), "JOIN #one|JOIN #two|JOIN +#third")
    Unit <- E.must("fourteen valid entries fit the plan", Nat.is_eq(List.length(&2, String, Sess.session_desired_channels(initial(many(14n)))), 14n))
    Unit <- E.must_eq("overcapacity whole list is refused without partial joins", wire(welcome(initial(many(15n)))), "")
    Unit <- E.must_eq("malformed whole list is refused without partial joins", wire(welcome(initial("#one,unknown,#two"))), "")
    Unit <- E.must_eq("empty comma member cannot partially populate intent", names(initial("#one,,#two")), "")
    Unit <- E.must_eq("launch names cannot carry runtime keys", names(initial("#one secret-key")), "")
    Unit <- E.must_eq("IRC-equivalent names deduplicate in first spelling", wire(welcome(initial("#one,#ONE,#two"))), "JOIN #one|JOIN #two")
    Unit <- cli_controls()
    IO.print("launch_channels=ok")
