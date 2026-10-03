# SPDX-License-Identifier: Apache-2.0
# ISUPPORT client/feed and join-plan adapters, plus secret-safe MODE redaction.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/channel_policy.bend as Channels
import ../../src/bend/isupport.bend as Is

def base() -> Cl.Client:
  Cl.init("me", "irc")

def joined(+args: List<&2, String>) -> String:
  String.join(args, "|")

def feed() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("server 005 marks the state updated", Is.updated(Is.feed_state(Is.defaults(), base(), ":irc 005 me PREFIX=(q)~ NETWORK=X :are supported")))
    Unit <- E.must_eq("server 005 sets the prefix", Is.show(Is.feed_state(Is.defaults(), base(), ":irc 005 me PREFIX=(q)~ NETWORK=X :are supported")),
      "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(q)~ extra= nicklen=9 channellen=50 topiclen=390 kicklen=390 network=X casemapping=rfc1459 maxlist= updated=true")
    Unit <- E.must_eq("peer 005 changes no state", Is.show(Is.feed_state(Is.defaults(), base(), ":mallory!u@h 005 me PREFIX=(q)~ :x")), Is.show(Is.defaults()))
    Unit <- E.must_eq("bare-nick 005 changes no state", Is.show(Is.feed_state(Is.defaults(), base(), ":mallory 005 me PREFIX=(q)~ :x")), Is.show(Is.defaults()))
    Unit <- E.must_eq("other server numerics change no state", Is.show(Is.feed_state(Is.defaults(), base(), ":irc 001 me :welcome")), Is.show(Is.defaults()))
    Unit <- E.must("server 005 still logs to the server buffer", String.contains(CL.buf_texts(Feed.feed(base(), ":irc 005 me PREFIX=(q)~ :are supported"), 0n), "[5]"))
    Unit <- E.must_eq("new endpoint resets metadata", Is.show(Is.endpoint(False{}, Is.feed_state(Is.defaults(), base(), ":irc 005 me PREFIX=(q)~ :x"))), Is.show(Is.defaults()))
    Unit <- E.must("same endpoint keeps metadata", Is.updated(Is.endpoint(True{}, Is.feed_state(Is.defaults(), base(), ":irc 005 me PREFIX=(q)~ :x"))))
    IO.pure(Unit, Unit{})

def server() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=# CHANNELLEN=18 :are supported")

def joins() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("unupdated admit matches base policy", Is.join_admit(Is.defaults(), "#room", "") && Channels.valid("#room", ""))
    Unit <- E.must("unupdated reject matches base policy", Bool.not(Is.join_admit(Is.defaults(), "alice", "")) && Bool.not(Channels.valid("alice", "")))
    Unit <- E.must("unupdated keyed admit matches base policy", Is.join_admit(Is.defaults(), "#room", "s3cret") && Channels.valid("#room", "s3cret"))
    Unit <- E.must("server accepts its own channel type", Is.join_admit(server(), "#room", ""))
    Unit <- E.must("server rejects foreign channel type", Bool.not(Is.join_admit(server(), "&local", "")))
    Unit <- E.must("server rejects overlong names", Bool.not(Is.join_admit(server(), "#0123456789012345678901234567890123456789", "")))
    Unit <- E.must("server accepts names at the bound", Is.join_admit(server(), "#0123456789abcdef0", ""))
    Unit <- E.must("server still rejects non-channels", Bool.not(Is.join_admit(server(), "alice", "")))
    IO.pure(Unit, Unit{})

def server_modes() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANMODES=b,k,j,ilm PREFIX=(ov)@+ :are supported")

def redact() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("precise +ovk hides only the key", joined(Is.redact_params(Is.defaults(), "#c", "+ovk", ["a", "b", "s3cret"])), "a|b|[channel key hidden]")
    Unit <- E.must_eq("unknown mode hides everything", joined(Is.redact_params(Is.defaults(), "#c", "+oXk", ["a", "b", "s3cret"])), "[channel key hidden]")
    Unit <- E.must_eq("extra argument hides everything", joined(Is.redact_params(Is.defaults(), "#c", "+k", ["s3cret", "extra"])), "[channel key hidden]")
    Unit <- E.must_eq("repeated key hides everything", joined(Is.redact_params(Is.defaults(), "#c", "+kk", ["one", "two"])), "[channel key hidden]")
    Unit <- E.must_eq("key removal redacts its argument", joined(Is.redact_params(Is.defaults(), "#c", "-k", ["s3cret"])), "[channel key hidden]")
    Unit <- E.must_eq("ordinary mode renders", joined(Is.redact_params(Is.defaults(), "#c", "+o", ["bob"])), "bob")
    Unit <- E.must_eq("flag-only mode renders", joined(Is.redact_params(Is.defaults(), "#c", "+i", ["ignored"])), "ignored")
    Unit <- E.must_eq("user target is untouched", joined(Is.redact_params(Is.defaults(), "alice", "+k", ["s3cret"])), "s3cret")
    Unit <- E.must_eq("unsigned flags are untouched", joined(Is.redact_params(Is.defaults(), "#c", "k", ["s3cret"])), "s3cret")
    Unit <- E.must_eq("uppercase K is untouched", joined(Is.redact_params(Is.defaults(), "#c", "+K", ["s3cret"])), "s3cret")
    Unit <- E.must_eq("missing arguments are untouched", joined(Is.redact_params(Is.defaults(), "#c", "+k", Nil{})), "")
    Unit <- E.must("key never survives +ovk", Bool.not(String.contains(joined(Is.redact_params(Is.defaults(), "#c", "+ovk", ["a", "b", "s3cret"])), "s3cret")))
    Unit <- E.must("key never survives -k", Bool.not(String.contains(joined(Is.redact_params(Is.defaults(), "#c", "-k", ["s3cret"])), "s3cret")))
    Unit <- E.must("key never survives uncertain input", Bool.not(String.contains(joined(Is.redact_params(Is.defaults(), "#c", "+oXk", ["a", "b", "s3cret"])), "s3cret")))
    Unit <- E.must_eq("server classes drive precision", joined(Is.redact_params(server_modes(), "#c", "+lk", ["50", "s3cret"])), "[channel key hidden]")
    Unit <- E.must_eq("defaults stay precise on the same input", joined(Is.redact_params(Is.defaults(), "#c", "+lk", ["50", "s3cret"])), "50|[channel key hidden]")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- feed()
    Unit <- joins()
    Unit <- redact()
    IO.print("isupport_adapters=ok")
