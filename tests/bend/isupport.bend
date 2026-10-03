# SPDX-License-Identifier: Apache-2.0
# 005 ISUPPORT parsing, channel/mode metadata, and nick privileges.
import Base
import ./expect.bend as E
import ../../src/bend/isupport.bend as Is

def ch(+s: String) -> Char:
  match s:
    case SCon{+h, _}: h
    case SNil{}: Chr{0}

def cls.of(+c: Is.ModeClass) -> String:
  match c:
    case Is.Unknown{}: "unknown"
    case Is.ListMode{}: "list"
    case Is.ArgMode{}: "arg"
    case Is.SetMode{}: "set"
    case Is.FlagMode{}: "flag"

def cls(+st: Is.State, +c: Char) -> String:
  cls.of(Is.mode_class(st, c))

def idx(+m: Maybe<&2, Nat>) -> String:
  match m:
    case None{}: "none"
    case Some{+n}: Nat.show(n)

def burst() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=# PREFIX=(qaohv)~&@%+ CHANMODES=eIbq,k,flj,CFLMPQScgimnprstz MODES=4 NETWORK=ExampleNet STATUSMSG=@+ CASEMAPPING=ascii NICKLEN=16 CHANNELLEN=64 TOPICLEN=300 KICKLEN=300 MAXLIST=b:60,e:60,I:60 EXCEPTS INVEX FOO=bar :are supported by this server")

def narrow() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(ov)@+ :are supported")

def burst_show() -> String:
  "isupport chantypes=# status=@+ chanmodes=eIbq,k,flj,CFLMPQScgimnprstz modes=4 prefix=(qaohv)~&@%+ extra= nicklen=16 channellen=64 topiclen=300 kicklen=300 network=ExampleNet casemapping=ascii maxlist=b:60,e:60,I:60 updated=true"

def default_show() -> String:
  "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(ov)@+ extra=~&% nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=false"

def default_updated_show() -> String:
  "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(ov)@+ extra=~&% nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true"

def goldens() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("defaults golden", Is.show(Is.defaults()), default_show())
    Unit <- E.must_eq("full burst golden", Is.show(burst()), burst_show())
    Unit <- E.must_eq("later burst overrides nicklen", Is.show(Is.apply_line(burst(), ":s 005 me NICKLEN=31 :are supported")),
      "isupport chantypes=# status=@+ chanmodes=eIbq,k,flj,CFLMPQScgimnprstz modes=4 prefix=(qaohv)~&@%+ extra= nicklen=31 channellen=64 topiclen=300 kicklen=300 network=ExampleNet casemapping=ascii maxlist=b:60,e:60,I:60 updated=true")
    Unit <- E.must_eq("lowercase token names are accepted", Is.show(Is.apply_line(Is.defaults(), ":s 005 me nicklen=24 :are supported")),
      "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(ov)@+ extra=~&% nicklen=24 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true")
    IO.pure(Unit, Unit{})

def negatives() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("PREFIX without parens is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=ov@+ :are supported")), default_updated_show())
    Unit <- E.must_eq("PREFIX length mismatch is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(ov)@ :are supported")), default_updated_show())
    Unit <- E.must_eq("PREFIX empty modes are ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=() :are supported")), default_updated_show())
    Unit <- E.must_eq("PREFIX without value is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me PREFIX :are supported")), default_updated_show())
    Unit <- E.must_eq("CHANMODES wrong arity is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me CHANMODES=k,l,im :are supported")), default_updated_show())
    Unit <- E.must_eq("CHANMODES non-letters are ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me CHANMODES=b1,k,l,im :are supported")), default_updated_show())
    Unit <- E.must_eq("NICKLEN garbage is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN=abc :are supported")), default_updated_show())
    Unit <- E.must_eq("NICKLEN empty is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN= :are supported")), default_updated_show())
    Unit <- E.must_eq("NICKLEN zero is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN=0 :are supported")), default_updated_show())
    Unit <- E.must_eq("NICKLEN absurd is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN=99999 :are supported")), default_updated_show())
    Unit <- E.must_eq("CHANTYPES letters are ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=x :are supported")), default_updated_show())
    Unit <- E.must_eq("CHANTYPES comma is impossible", Is.show(Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=#,,& :are supported")), default_updated_show())
    Unit <- E.must_eq("CASEMAPPING unknown is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me CASEMAPPING=weird :are supported")), default_updated_show())
    Unit <- E.must_eq("MAXLIST garbage is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me MAXLIST=bogus :are supported")), default_updated_show())
    Unit <- E.must_eq("MAXLIST bad number is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me MAXLIST=b:xx :are supported")), default_updated_show())
    Unit <- E.must_eq("MODES zero is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 005 me MODES=0 :are supported")), default_updated_show())
    Unit <- E.must_eq("non-005 numeric is ignored", Is.show(Is.apply_line(Is.defaults(), ":s 004 me s vittu o :x")), default_show())
    Unit <- E.must_eq("chat line is ignored", Is.show(Is.apply_line(Is.defaults(), ":a!u@h PRIVMSG #c :005 me PREFIX=(q)~")), default_show())
    Unit <- E.must_eq("unparseable line is ignored", Is.show(Is.apply_line(Is.defaults(), "")), default_show())
    Unit <- E.must_eq("005 without tokens only marks updated", Is.show(Is.apply_line(Is.defaults(), ":s 005 me :are supported")),
      "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(ov)@+ extra=~&% nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true")
    IO.pure(Unit, Unit{})

def channels() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("default # is a channel", Is.is_channel(Is.defaults(), "#birc"))
    Unit <- E.must("default nick is not a channel", Bool.not(Is.is_channel(Is.defaults(), "alice")))
    Unit <- E.must("default STATUSMSG @# is a channel", Is.is_channel(Is.defaults(), "@#birc"))
    Unit <- E.must("default empty is not a channel", Bool.not(Is.is_channel(Is.defaults(), "")))
    Unit <- E.must("server # is a channel", Is.is_channel(burst(), "#birc"))
    Unit <- E.must("server & is not a channel", Bool.not(Is.is_channel(burst(), "&local")))
    Unit <- E.must("server audience strips", String.eq(Is.chan_target(burst(), "@#birc"), "#birc"))
    Unit <- E.must("server plain name is kept", String.eq(Is.chan_target(burst(), "#birc"), "#birc"))
    Unit <- E.must("default audience strips", String.eq(Is.chan_target(Is.defaults(), "@#birc"), "#birc"))
    Unit <- E.must("default +local is not an audience", String.eq(Is.chan_target(Is.defaults(), "+local"), "+local"))
    IO.pure(Unit, Unit{})

def privileges() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("default op outranks voice", Nat.is_gt(Is.rank(Is.defaults(), "@alice"), Is.rank(Is.defaults(), "+bob")))
    Unit <- E.must("default voice outranks plain", Nat.is_gt(Is.rank(Is.defaults(), "+bob"), Is.rank(Is.defaults(), "carol")))
    Unit <- E.must("default plain has no rank", Nat.is_eq(Is.rank(Is.defaults(), "carol"), 0n))
    Unit <- E.must("default op rank is two", Nat.is_eq(Is.rank(Is.defaults(), "@alice"), 2n))
    Unit <- E.must("server owner rank is five", Nat.is_eq(Is.rank(burst(), "~alice"), 5n))
    Unit <- E.must("server rank takes the highest sigil", Nat.is_eq(Is.rank(burst(), "+~alice"), 5n))
    Unit <- E.must("default strips legacy sigils", String.eq(Is.strip(Is.defaults(), "~&@%+alice"), "alice"))
    Unit <- E.must("server narrows the strip set", String.eq(Is.strip(narrow(), "~alice"), "~alice"))
    Unit <- E.must("narrowed server keeps @ stripping", String.eq(Is.strip(narrow(), "@alice"), "alice"))
    Unit <- E.must("server tilde is a sigil", String.eq(Is.strip(burst(), "~alice"), "alice"))
    Unit <- E.must("default keeps unknown prefix", String.eq(Is.strip(Is.defaults(), "!alice"), "!alice"))
    Unit <- E.must("sigil for o is @", String.eq(Is.sigil_for(Is.defaults(), ch("o")), "@"))
    Unit <- E.must("sigil for unknown is empty", String.eq(Is.sigil_for(Is.defaults(), ch("z")), ""))
    Unit <- E.must("mode for @ is o", String.eq(Is.mode_for(Is.defaults(), ch("@")), "o"))
    Unit <- E.must("mode for unknown is empty", String.eq(Is.mode_for(Is.defaults(), ch("!")), ""))
    Unit <- E.must("op has mode o", Is.has_mode(Is.defaults(), "@alice", ch("o")))
    Unit <- E.must("voice lacks mode o", Bool.not(Is.has_mode(Is.defaults(), "+bob", ch("o"))))
    Unit <- E.must("plain lacks every mode", Bool.not(Is.has_mode(Is.defaults(), "carol", ch("o"))))
    Unit <- E.must("unknown mode is never held", Bool.not(Is.has_mode(Is.defaults(), "@alice", ch("z"))))
    IO.pure(Unit, Unit{})

def modes() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("default b is a list mode", cls(Is.defaults(), ch("b")), "list")
    Unit <- E.must_eq("default k takes an argument", cls(Is.defaults(), ch("k")), "arg")
    Unit <- E.must_eq("default l is set-only", cls(Is.defaults(), ch("l")), "set")
    Unit <- E.must_eq("default i is a flag", cls(Is.defaults(), ch("i")), "flag")
    Unit <- E.must_eq("default o is a prefix argument", cls(Is.defaults(), ch("o")), "arg")
    Unit <- E.must_eq("default X is unknown", cls(Is.defaults(), ch("X")), "unknown")
    Unit <- E.must("unknown consumes an argument", Is.takes_arg(Is.defaults(), ch("X"), True{}) && Is.takes_arg(Is.defaults(), ch("X"), False{}))
    Unit <- E.must("set-only takes an argument when adding", Is.takes_arg(Is.defaults(), ch("l"), True{}))
    Unit <- E.must("set-only takes none when removing", Bool.not(Is.takes_arg(Is.defaults(), ch("l"), False{})))
    Unit <- E.must("flag never takes an argument", Bool.not(Is.takes_arg(Is.defaults(), ch("i"), True{})))
    Unit <- E.must_eq("server e is a list mode", cls(burst(), ch("e")), "list")
    Unit <- E.must_eq("server j is set-only", cls(burst(), ch("j")), "set")
    Unit <- E.must_eq("server C is a flag", cls(burst(), ch("C")), "flag")
    Unit <- E.must_eq("server q is a prefix argument", cls(burst(), ch("q")), "arg")
    Unit <- E.must_eq("key index of +ovk", idx(Is.key_index(Is.defaults(), "+ovk", ["a", "b", "s3cret"])), "2")
    Unit <- E.must_eq("unknown mode hides everything", idx(Is.key_index(Is.defaults(), "+oXk", ["a", "b", "s3cret"])), "none")
    Unit <- E.must_eq("extra argument hides everything", idx(Is.key_index(Is.defaults(), "+k", ["s3cret", "extra"])), "none")
    Unit <- E.must_eq("repeated key hides everything", idx(Is.key_index(Is.defaults(), "+kk", ["one", "two"])), "none")
    Unit <- E.must_eq("removed key keeps its index", idx(Is.key_index(Is.defaults(), "-k", ["s3cret"])), "0")
    IO.pure(Unit, Unit{})

def caret() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(o)^ :are supported")

def dollar() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=$ :are supported")

def star() -> Is.State:
  Is.apply_line(Is.defaults(), ":s 005 me CHANTYPES=* :are supported")

def caret_cleared() -> Is.State:
  Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me STATUSMSG= :x"), ":s 005 me PREFIX=(o)^ :x")

def caret_hat() -> Is.State:
  Is.apply_line(caret_cleared(), ":s 005 me STATUSMSG=^ :x")

def nicklen31_show() -> String:
  "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(ov)@+ extra=~&% nicklen=31 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true"

def caret_cleared_show() -> String:
  "isupport chantypes=#&+! status= chanmodes=b,k,l,imnpst modes=3 prefix=(o)^ extra= nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true"

def caret_hat_show() -> String:
  "isupport chantypes=#&+! status=^ chanmodes=b,k,l,imnpst modes=3 prefix=(o)^ extra= nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true"

def burst_nostatus_show() -> String:
  "isupport chantypes=# status= chanmodes=eIbq,k,flj,CFLMPQScgimnprstz modes=4 prefix=(qaohv)~&@%+ extra= nicklen=16 channellen=64 topiclen=300 kicklen=300 network=ExampleNet casemapping=ascii maxlist=b:60,e:60,I:60 updated=true"

def cleared_status_show() -> String:
  "isupport chantypes=#&+! status= chanmodes=b,k,l,imnpst modes=3 prefix=(ov)@+ extra=~&% nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true"

def repairs() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("-NICKLEN resets the previous burst value", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN=31 :x"), ":s 005 me -NICKLEN :x")), default_updated_show())
    Unit <- E.must_eq("-PREFIX restores modes, sigils, and extras", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(q)~ :x"), ":s 005 me -PREFIX :x")), default_updated_show())
    Unit <- E.must_eq("-STATUSMSG disables support", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me STATUSMSG=@ :x"), ":s 005 me -STATUSMSG :x")), cleared_status_show())
    Unit <- E.must_eq("-CHANMODES restores the default classes", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me CHANMODES=eIbq,k,flj,CFLMPQScgimnprstz :x"), ":s 005 me -CHANMODES :x")), default_updated_show())
    Unit <- E.must_eq("-CASEMAPPING restores rfc1459", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me CASEMAPPING=ascii :x"), ":s 005 me -CASEMAPPING :x")), default_updated_show())
    Unit <- E.must_eq("-UNKNOWN is ignored", Is.show(Is.apply_line(burst(), ":s 005 me -FOO :x")), Is.show(Is.apply_line(burst(), ":s 005 me :x")))
    Unit <- E.must_eq("lowercase removal is accepted", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN=31 :x"), ":s 005 me -nicklen :x")), default_updated_show())
    Unit <- E.must_eq("empty STATUSMSG= clears the audience", Is.show(Is.apply_line(Is.defaults(), ":s 005 me STATUSMSG= :are supported")), cleared_status_show())
    Unit <- E.must_eq("empty STATUSMSG= clears a burst value", Is.show(Is.apply_line(burst(), ":s 005 me STATUSMSG= :are supported")),
      "isupport chantypes=# status= chanmodes=eIbq,k,flj,CFLMPQScgimnprstz modes=4 prefix=(qaohv)~&@%+ extra= nicklen=16 channellen=64 topiclen=300 kicklen=300 network=ExampleNet casemapping=ascii maxlist=b:60,e:60,I:60 updated=true")
    Unit <- E.must("cleared STATUSMSG admits no audience", Bool.not(Is.is_channel(Is.apply_line(Is.defaults(), ":s 005 me STATUSMSG= :x"), "@#birc")))
    Unit <- E.must_eq("bare STATUSMSG keeps the previous audience", Is.show(Is.apply_line(Is.defaults(), ":s 005 me STATUSMSG :are supported")), default_updated_show())
    Unit <- E.must_eq("duplicate prefix modes are rejected", Is.show(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(oo)@+ :are supported")), default_updated_show())
    Unit <- E.must_eq("duplicate prefix sigils are rejected", Is.show(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(ov)@@ :are supported")), default_updated_show())
    Unit <- E.must_eq("duplicate prefix keeps the previous valid setting", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(q)~ :x"), ":s 005 me PREFIX=(oo)@+ :x")),
      "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(q)~ extra= nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true")
    Unit <- E.must_eq("unique (ov)@+ is accepted", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me PREFIX=(q)~ :x"), ":s 005 me PREFIX=(ov)@+ :x")),
      "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(ov)@+ extra= nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459 maxlist= updated=true")
    Unit <- E.must_eq("strip keeps an interior sigil", Is.strip(caret(), "a^b"), "a^b")
    Unit <- E.must_eq("strip keeps trailing sigils", Is.strip(caret(), "a^^"), "a^^")
    Unit <- E.must_eq("strip stops at the first plain char", Is.strip(caret(), "^a^b"), "a^b")
    Unit <- E.must_eq("strip removes only the leading run", Is.strip(caret(), "^^a"), "a")
    Unit <- E.must_eq("strip keeps a sigil-only tail word", Is.strip(Is.defaults(), "@a+b"), "a+b")
    Unit <- E.must("trailing sigils grant no mode", Bool.not(Is.has_mode(caret(), "a^^", ch("o"))))
    Unit <- E.must("leading sigil grants its mode", Is.has_mode(caret(), "^alice", ch("o")))
    Unit <- E.must("advertised $room is a channel", Is.is_channel(dollar(), "$room"))
    Unit <- E.must("advertised $room joins", Is.join_admit(dollar(), "$room", ""))
    Unit <- E.must("advertised $room joins with a key", Is.join_admit(dollar(), "$room", "s3cret"))
    Unit <- E.must("unadvertised #room is not a channel", Bool.not(Is.is_channel(dollar(), "#room")))
    Unit <- E.must("unadvertised #room does not join", Bool.not(Is.join_admit(dollar(), "#room", "")))
    Unit <- E.must("unupdated $room does not join", Bool.not(Is.join_admit(Is.defaults(), "$room", "")))
    Unit <- E.must("advertised $ rejects comma names", Bool.not(Is.join_admit(dollar(), "$a,$b", "")))
    Unit <- E.must("advertised $ rejects bare type", Bool.not(Is.join_admit(dollar(), "$", "")))
    Unit <- E.must("default folds [ with {", Is.cm_eq(Is.defaults(), "a[b", "a{b"))
    Unit <- E.must("default folds ^ with ~", Is.cm_eq(Is.defaults(), "^", "~"))
    Unit <- E.must("default folds case", Is.cm_eq(Is.defaults(), "Alice", "alice"))
    Unit <- E.must("ascii folds case", Is.cm_eq(Is.apply_line(Is.defaults(), ":s 005 me CASEMAPPING=ascii :x"), "Alice", "alice"))
    Unit <- E.must("ascii keeps [ distinct from {", Bool.not(Is.cm_eq(Is.apply_line(Is.defaults(), ":s 005 me CASEMAPPING=ascii :x"), "a[b", "a{b")))
    Unit <- E.must("strict folds [ with {", Is.cm_eq(Is.apply_line(Is.defaults(), ":s 005 me CASEMAPPING=rfc1459-strict :x"), "a[b", "a{b"))
    Unit <- E.must("strict keeps ^ distinct from ~", Bool.not(Is.cm_eq(Is.apply_line(Is.defaults(), ":s 005 me CASEMAPPING=rfc1459-strict :x"), "^", "~")))
    Unit <- E.must_eq("legacy strict alias is accepted", Is.show(Is.apply_line(Is.defaults(), ":s 005 me CASEMAPPING=strict-rfc1459 :x")),
      "isupport chantypes=#&+! status=@+ chanmodes=b,k,l,imnpst modes=3 prefix=(ov)@+ extra=~&% nicklen=9 channellen=50 topiclen=390 kicklen=390 network= casemapping=rfc1459-strict maxlist= updated=true")
    IO.pure(Unit, Unit{})

def second_review() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("advertised $room still joins", Is.join_admit(dollar(), "$room", ""))
    Unit <- E.must("CHANTYPES=* rejects *log*", Bool.not(Is.join_admit(star(), "*log*", "")))
    Unit <- E.must("CHANTYPES=* rejects *LOG*", Bool.not(Is.join_admit(star(), "*LOG*", "")))
    Unit <- E.must("CHANTYPES=* rejects *log* with key", Bool.not(Is.join_admit(star(), "*log*", "s3cret")))
    Unit <- E.must_eq("malformed -NICKLEN=garbage retains 31", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN=31 :x"), ":s 005 me -NICKLEN=garbage :x")), nicklen31_show())
    Unit <- E.must_eq("malformed -NICKLEN= retains 31", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN=31 :x"), ":s 005 me -NICKLEN= :x")), nicklen31_show())
    Unit <- E.must_eq("valid -NICKLEN resets 31 to 9", Is.show(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me NICKLEN=31 :x"), ":s 005 me -NICKLEN :x")), default_updated_show())
    Unit <- E.must_eq("-STATUSMSG disables a burst value", Is.show(Is.apply_line(burst(), ":s 005 me -STATUSMSG :x")), burst_nostatus_show())
    Unit <- E.must("disabled -STATUSMSG admits no audience", Bool.not(Is.is_channel(Is.apply_line(Is.apply_line(Is.defaults(), ":s 005 me STATUSMSG=@ :x"), ":s 005 me -STATUSMSG :x"), "@#birc")))
    Unit <- E.must_eq("STATUSMSG=^ accepted under PREFIX=(o)^", Is.show(caret_hat()), caret_hat_show())
    Unit <- E.must("narrow ^ authorizes ^#room", Is.is_channel(caret_hat(), "^#room"))
    Unit <- E.must_eq("STATUSMSG=@ rejected under PREFIX=(o)^ keeps empty", Is.show(Is.apply_line(caret_cleared(), ":s 005 me STATUSMSG=@ :x")), caret_cleared_show())
    Unit <- E.must("rejected @ does not authorize @#room", Bool.not(Is.is_channel(Is.apply_line(caret_cleared(), ":s 005 me STATUSMSG=@ :x"), "@#birc")))
    Unit <- E.must_eq("STATUSMSG=@ rejected under PREFIX=(o)^ keeps ^", Is.show(Is.apply_line(caret_hat(), ":s 005 me STATUSMSG=@ :x")), caret_hat_show())
    Unit <- E.must("kept ^ still authorizes ^#room", Is.is_channel(Is.apply_line(caret_hat(), ":s 005 me STATUSMSG=@ :x"), "^#room"))
    Unit <- E.must("kept ^ does not authorize @#room", Bool.not(Is.is_channel(Is.apply_line(caret_hat(), ":s 005 me STATUSMSG=@ :x"), "@#birc")))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- goldens()
    Unit <- negatives()
    Unit <- channels()
    Unit <- privileges()
    Unit <- modes()
    Unit <- repairs()
    Unit <- second_review()
    IO.print("isupport=ok")
