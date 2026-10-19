# SPDX-License-Identifier: Apache-2.0
# ISUPPORT client/feed and join-plan adapters, plus secret-safe MODE redaction.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/channel_policy.bend as Channels
import ../../src/bend/isupport.bend as Is
import ../../src/bend/submit.bend as Sub

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
    Unit <- E.must_eq("wrong-recipient 005 changes no state", Is.show(Is.feed_state(Is.defaults(), base(), ":irc 005 mallory PREFIX=(q)~ :x")), Is.show(Is.defaults()))
    Unit <- E.must("wrong-recipient 005 is not marked updated", Bool.not(Is.updated(Is.feed_state(Is.defaults(), base(), ":irc 005 mallory PREFIX=(q)~ :x"))))
    Unit <- E.must_eq("case-folded recipient 005 applies", Is.show(Is.feed_state(Is.defaults(), base(), ":irc 005 ME PREFIX=(q)~ :x")),
      "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(q)~ extra= nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true")
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

def submit_no_wire(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, xs): Nat.is_eq(List.length(&2, String, xs), 0n)

def submit_wire(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, xs): String.join(xs, "|")

def submit_client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def dollar_server() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=$ :are supported")

def dollar_channel() -> Cl.Client:
  submit_client(Sub.submit_with(dollar_server(), base(), "/join $room"))

def amp_channel() -> Cl.Client:
  submit_client(Sub.submit(base(), "/join &room"))

def mute_pattern(pair: Cl.Client & List<&2, String>) -> String:
  String.join(Cl.settings_mutes(Cl.get_settings(submit_client(pair))), "|")

def negotiated_commands() -> IO(Unit):
  +iso = dollar_server()
  +cl = base()
  +dollar = dollar_channel()
  +amp = amp_channel()
  do IO<Unit>:
    Unit <- E.must_eq("negotiated JOIN accepts advertised type", submit_wire(Sub.submit_with(iso, cl, "/join $room")), "JOIN $room")
    Unit <- E.must("negotiated JOIN rejects withdrawn fixed type", submit_no_wire(Sub.submit_with(iso, cl, "/join &room")))
    Unit <- E.must("fixed JOIN still rejects negotiated-only type", submit_no_wire(Sub.submit(cl, "/join $room")))
    Unit <- E.must_eq("fixed JOIN still accepts fixed type", submit_wire(Sub.submit(cl, "/join &room")), "JOIN &room")
    Unit <- E.must_eq("negotiated explicit PART accepts advertised type", submit_wire(Sub.submit_with(iso, cl, "/part $room")), "PART $room")
    Unit <- E.must("negotiated explicit PART rejects withdrawn fixed type", submit_no_wire(Sub.submit_with(iso, cl, "/part &room")))
    Unit <- E.must_eq("negotiated PART recognizes advertised type", submit_wire(Sub.submit_with(iso, dollar, "/part")), "PART $room")
    Unit <- E.must("negotiated PART rejects withdrawn fixed type", submit_no_wire(Sub.submit_with(iso, amp, "/part")))
    Unit <- E.must("fixed PART keeps context-free classification", submit_no_wire(Sub.submit(dollar, "/part")))
    Unit <- E.must_eq("negotiated missing CLOSE accepts advertised type", submit_wire(Sub.submit_with(iso, cl, "/close $room")), "PART $room")
    Unit <- E.must("negotiated missing CLOSE rejects withdrawn fixed type", submit_no_wire(Sub.submit_with(iso, cl, "/close &room")))
    Unit <- E.must_eq("negotiated CLOSE recognizes advertised type", submit_wire(Sub.submit_with(iso, dollar, "/close")), "PART $room")
    Unit <- E.must("negotiated CLOSE treats withdrawn fixed type as non-channel", submit_no_wire(Sub.submit_with(iso, amp, "/close")))
    Unit <- E.must("fixed CLOSE keeps context-free classification", submit_no_wire(Sub.submit(dollar, "/close")))
    Unit <- E.must_eq("negotiated MUTE scopes advertised type", mute_pattern(Sub.submit_with(iso, dollar, "/mute alice")), "alice$room@irc")
    Unit <- E.must_eq("negotiated MUTE does not scope withdrawn fixed type", mute_pattern(Sub.submit_with(iso, amp, "/mute alice")), "alice*@irc")
    Unit <- E.must_eq("fixed MUTE keeps context-free classification", mute_pattern(Sub.submit(dollar, "/mute alice")), "alice*@irc")
    IO.pure(Unit, Unit{})

def plusroom() -> Cl.Client:
  Feed.feed(base(), ":me!u@h JOIN +#room")

def audience() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("exact resident +#room is preserved", Is.chan_target_cl(Is.defaults(), plusroom(), "+#room"), "+#room")
    Unit <- E.must_eq("non-resident +#room falls back to STATUSMSG", Is.chan_target_cl(Is.defaults(), base(), "+#room"), "#room")
    Unit <- E.must_eq("resident #room is preserved", Is.chan_target_cl(Is.defaults(), Feed.feed(base(), ":me!u@h JOIN #room"), "#room"), "#room")
    Unit <- E.must_eq("plain audience still strips", Is.chan_target_cl(Is.defaults(), base(), "@#room"), "#room")
    IO.pure(Unit, Unit{})

def server_modes() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANMODES=b,k,j,ilm PREFIX=(ov)@+ :are supported")

def known_map() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANMODES=b,k,s,l :x")

def withdrawn() -> Is.State:
  Is.apply_line(known_map(), ":s 005 me -CHANMODES :x")

def readvertised() -> Is.State:
  Is.apply_line(withdrawn(), ":s 005 me CHANMODES=b,k,s,l :x")

def lifecycle_neg() -> Is.State:
  Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me STATUSMSG=@ :x"), ":s 005 me PREFIX=(o)^ :x")

def lifecycle_pos() -> Is.State:
  Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(o)^ :x"), ":s 005 me STATUSMSG=^ :x")

def burst_order1() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(o)^ STATUSMSG=@ :x")

def burst_order2() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me STATUSMSG=@ PREFIX=(o)^ :x")

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
    Unit <- E.must_eq("wire MODE redacts its key", joined(Is.redact_line(Is.defaults(), ":a!u@h MODE #c +k s3cret")), "[channel key hidden]")
    Unit <- E.must_eq("wire 324 redacts its key", joined(Is.redact_line(Is.defaults(), ":s 324 me #c +k s3cret")), "[channel key hidden]")
    Unit <- E.must_eq("wire 324 keeps precise offsets", joined(Is.redact_line(Is.defaults(), ":s 324 me #c +ovk alice bob s3cret")), "alice|bob|[channel key hidden]")
    Unit <- E.must_eq("wire 324 without a key renders", joined(Is.redact_line(Is.defaults(), ":s 324 me #c +ov alice bob")), "alice|bob")
    Unit <- E.must_eq("wire 324 removal redacts", joined(Is.redact_line(Is.defaults(), ":s 324 me #c -k s3cret")), "[channel key hidden]")
    Unit <- E.must_eq("non-mode wire passes through", joined(Is.redact_line(Is.defaults(), ":s 001 me :welcome")), "me|welcome")
    Unit <- E.must_eq("unparseable wire redacts to nothing", joined(Is.redact_line(Is.defaults(), "")), "")
    Unit <- E.must("key never survives wire 324", Bool.not(String.contains(joined(Is.redact_line(Is.defaults(), ":s 324 me #c +k s3cret")), "s3cret")))
    Unit <- E.must("key never survives uncertain 324", Bool.not(String.contains(joined(Is.redact_line(Is.defaults(), ":s 324 me #c +oXk alice bob s3cret")), "s3cret")))
    IO.pure(Unit, Unit{})

def third_review() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("known +lks redacts only the key", joined(Is.redact_params(known_map(), "#c", "+lks", ["s3cret", "50"])), "[channel key hidden]|50")
    Unit <- E.must("key never survives known +lks", Bool.not(String.contains(joined(Is.redact_params(known_map(), "#c", "+lks", ["s3cret", "50"])), "s3cret")))
    Unit <- E.must_eq("withdrawn +lks hides all", joined(Is.redact_params(withdrawn(), "#c", "+lks", ["s3cret", "50"])), "[channel key hidden]")
    Unit <- E.must("key never survives withdrawn +lks", Bool.not(String.contains(joined(Is.redact_params(withdrawn(), "#c", "+lks", ["s3cret", "50"])), "s3cret")))
    Unit <- E.must_eq("withdrawn +ovk hides all", joined(Is.redact_params(withdrawn(), "#c", "+ovk", ["a", "b", "s3cret"])), "[channel key hidden]")
    Unit <- E.must_eq("withdrawn +o renders (no key)", joined(Is.redact_params(withdrawn(), "#c", "+o", ["bob"])), "bob")
    Unit <- E.must_eq("readvertised +lks redacts only the key", joined(Is.redact_params(readvertised(), "#c", "+lks", ["s3cret", "50"])), "[channel key hidden]|50")
    Unit <- E.must_eq("wire 324 known +lks precise", joined(Is.redact_line(known_map(), ":s 324 me #c +lks s3cret 50")), "[channel key hidden]|50")
    Unit <- E.must_eq("wire 324 withdrawn +lks hides all", joined(Is.redact_line(withdrawn(), ":s 324 me #c +lks s3cret 50")), "[channel key hidden]")
    Unit <- E.must("key never survives withdrawn 324", Bool.not(String.contains(joined(Is.redact_line(withdrawn(), ":s 324 me #c +lks s3cret 50")), "s3cret")))
    Unit <- E.must_eq("lifecycle_neg resident +#room preserved", Is.chan_target_cl(lifecycle_neg(), plusroom(), "+#room"), "+#room")
    Unit <- E.must_eq("lifecycle_neg stale @ does not strip", Is.chan_target_cl(lifecycle_neg(), base(), "@#room"), "@#room")
    Unit <- E.must_eq("lifecycle_pos resident +#room preserved", Is.chan_target_cl(lifecycle_pos(), plusroom(), "+#room"), "+#room")
    Unit <- E.must_eq("lifecycle_pos ^ strips", Is.chan_target_cl(lifecycle_pos(), base(), "^#room"), "#room")
    Unit <- E.must_eq("lifecycle_pos @ does not strip", Is.chan_target_cl(lifecycle_pos(), base(), "@#room"), "@#room")
    Unit <- E.must_eq("burst order1 resident +#room preserved", Is.chan_target_cl(burst_order1(), plusroom(), "+#room"), "+#room")
    Unit <- E.must_eq("burst order1 @ does not strip", Is.chan_target_cl(burst_order1(), base(), "@#room"), "@#room")
    Unit <- E.must_eq("burst order2 resident +#room preserved", Is.chan_target_cl(burst_order2(), plusroom(), "+#room"), "+#room")
    Unit <- E.must_eq("burst order2 @ does not strip", Is.chan_target_cl(burst_order2(), base(), "@#room"), "@#room")
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- feed()
    Unit <- audience()
    Unit <- joins()
    Unit <- negotiated_commands()
    Unit <- redact()
    Unit <- third_review()
    IO.print("isupport_adapters=ok")
