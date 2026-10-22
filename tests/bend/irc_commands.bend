# Basic IRC user commands are exact, bounded wire lines with explicit failures.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as S
import ../../src/bend/irc_commands.bend as Commands

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def channel() -> Cl.Client:
  client(S.submit(Cl.init("me", "irc.example"), "/join #room"))

def wires(pair: Cl.Client & List<&2, String>) -> String:
  match pair:
    case (_, outs): String.join(outs, "|")

def no_wire(pair: Cl.Client & List<&2, String>) -> Bool:
  match pair:
    case (_, outs): List.is_empty(&2, String, outs)

def bad(+cl: Cl.Client, +input: String) -> IO(Unit):
  E.must("reject malformed command without sending", no_wire(S.submit(cl, input)))

def need_wire(+input: String) -> IO(Unit):
  E.must("new IRC commands need a connection", S.needs_connection(S.parse_input(input)))

def main() -> IO(Unit):
  +cl = channel()
  +server = Cl.init("me", "irc.example")
  +plus_channels = Cl.set_active(client(S.submit(cl, "/join +local")), 1n)
  +keyed_join = client(S.submit(cl, "/join #private opaque-secret"))
  do IO<Unit>:
    Unit <- E.must_eq("whois nick", wires(S.submit(cl, "/whois alice")), "WHOIS alice")
    Unit <- E.must_eq("whois server nick", wires(S.submit(cl, "/whois irc.example alice")), "WHOIS irc.example alice")
    Unit <- E.must_eq("who current channel", wires(S.submit(cl, "/who")), "WHO #room")
    Unit <- E.must_eq("who mask flags", wires(S.submit(cl, "/who *.example o")), "WHO *.example o")
    Unit <- E.must_eq("list all", wires(S.submit(cl, "/list")), "LIST")
    Unit <- E.must_eq("names current channel", wires(S.submit(cl, "/names")), "NAMES #room")
    Unit <- E.must_eq("names all on server", wires(S.submit(server, "/names")), "NAMES")
    Unit <- E.must_eq("topic query", wires(S.submit(cl, "/topic")), "TOPIC #room")
    Unit <- E.must_eq("topic current text", wires(S.submit(cl, "/topic hello there")), "TOPIC #room :hello there")
    Unit <- E.must_eq("topic named query", wires(S.submit(cl, "/topic #other")), "TOPIC #other")
    Unit <- E.must_eq("topic clear", wires(S.submit(cl, "/topic #other :")), "TOPIC #other :")
    Unit <- E.must_eq("mode query", wires(S.submit(cl, "/mode")), "MODE #room")
    Unit <- E.must_eq("mode user query", wires(S.submit(server, "/mode")), "MODE me")
    Unit <- E.must_eq("mode current flags", wires(S.submit(cl, "/mode +o alice")), "MODE #room +o alice")
    Unit <- E.must_eq("mode single implicit flag", wires(S.submit(cl, "/mode +i")), "MODE #room +i")
    Unit <- E.must_eq("mode plus-prefixed channel query", wires(S.submit(cl, "/mode +#other")), "MODE +#other")
    Unit <- E.must_eq("mode plus-prefixed channel flags", wires(S.submit(cl, "/mode +#other +m")), "MODE +#other +m")
    Unit <- E.must_eq("mode resident plus channel query", wires(S.submit(plus_channels, "/mode +local")), "MODE +local")
    Unit <- E.must_eq("mode resident plus channel flags", wires(S.submit(plus_channels, "/mode +local +m")), "MODE +local +m")
    Unit <- E.must_eq("mode unseen plus channel explicit flags", wires(S.submit(cl, "/mode +else +m")), "MODE +else +m")
    Unit <- E.must_eq("mode single unseen plus word stays implicit flags", wires(S.submit(cl, "/mode +else")), "MODE #room +else")
    Unit <- E.must("mode key stays outside composer history", S.input_sensitive(cl, "/mode +k opaque-secret"))
    Unit <- E.must("later mode flag group stays outside composer history", S.input_sensitive(cl, "/mode #room +o alice +k opaque-secret"))
    Unit <- E.must("first flags word key stays outside composer history", S.input_sensitive(cl, "/mode #room +k opaque-secret"))
    Unit <- E.must("mode unset key stays outside composer history", S.input_sensitive(cl, "/mode -k old-secret"))
    Unit <- E.must("combined mode key stays outside composer history", S.input_sensitive(cl, "/mode #room +ovk alice bob opaque-secret"))
    Unit <- E.must("ordinary mode stays in composer history", Bool.not(S.input_sensitive(cl, "/mode +o alice")))
    Unit <- E.must("mode no-key flag query stays in composer history", Bool.not(S.input_sensitive(cl, "/mode +k")))
    Unit <- E.must("channel name containing k is not a key mode", Bool.not(S.input_sensitive(cl, "/mode #key +o alice")))
    Unit <- E.must("mode key predicate rejects arbitrary command text", Bool.not(Commands.mode_has_key.line("PRIVMSG #room :MODE #room +k opaque-secret")))
    Unit <- E.must("mode key predicate rejects nonsigned parameter text", Bool.not(Commands.mode_has_key.line("MODE #room monkey opaque-secret")))
    Unit <- E.must("mode key predicate excludes user mode target", Bool.not(Commands.mode_has_key.line("MODE me +k opaque-secret")))
    Unit <- E.must("mode key predicate flags unsigned k", Commands.mode_has_key.line("MODE #room k opaque-secret"))
    Unit <- E.must("mode key predicate flags malformed signed k", Commands.mode_has_key.line("MODE #room +k! opaque-secret"))
    Unit <- E.must("unsigned mode key stays outside composer history", S.input_sensitive(cl, "/mode #room k opaque-secret"))
    Unit <- E.must("implicit unsigned mode key stays outside composer history", S.input_sensitive(cl, "/mode k opaque-secret"))
    Unit <- E.must("opaque trailing mode key stays outside composer history", S.input_sensitive(cl, "/mode #room +k :opaque secret words"))
    Unit <- E.must("plus channel key stays outside composer history", S.input_sensitive(cl, "/mode +foo +k secret"))
    Unit <- E.must("plus channel opaque key stays outside composer history", S.input_sensitive(cl, "/mode +foo +k :opaque secret words"))
    Unit <- E.must("plus channel raw fallback flags explicit key", S.input_sensitive.mode_raw(cl, "+foo +k secret"))
    Unit <- E.must("plus hash channel key stays outside composer history", S.input_sensitive(cl, "/mode +#room +k secret"))
    Unit <- E.must("short channel key stays outside composer history", S.input_sensitive(cl, "/mode #c +k secret"))
    Unit <- E.must("implicit short key stays outside composer history", S.input_sensitive(cl, "/mode +k secret"))
    Unit <- E.must("short channel plain words stay in composer history", Bool.not(S.input_sensitive(cl, "/mode #c monkey stuff")))
    Unit <- E.must("short channel single word stays in composer history", Bool.not(S.input_sensitive(cl, "/mode #c monkey")))
    Unit <- E.must("short channel non-key flags stay in composer history", Bool.not(S.input_sensitive(cl, "/mode #c +nt")))
    Unit <- E.must_eq("mode explicit target", wires(S.submit(cl, "/mode me +i")), "MODE me +i")
    Unit <- E.must_eq("kick current", wires(S.submit(cl, "/kick alice bye there")), "KICK #room alice :bye there")
    Unit <- E.must_eq("kick explicit", wires(S.submit(cl, "/kick #other alice")), "KICK #other alice")
    Unit <- E.must_eq("invite current", wires(S.submit(cl, "/invite alice")), "INVITE alice #room")
    Unit <- E.must_eq("invite explicit", wires(S.submit(cl, "/invite alice #other")), "INVITE alice #other")
    Unit <- E.must_eq("away clear", wires(S.submit(cl, "/away")), "AWAY")
    Unit <- E.must_eq("away text", wires(S.submit(cl, "/away lunch break")), "AWAY :lunch break")
    Unit <- E.must_eq("notice", wires(S.submit(cl, "/notice alice hello there")), "NOTICE alice :hello there")
    Unit <- E.must_eq("raw exact", wires(S.submit(cl, "/raw WHOIS alice")), "WHOIS alice")
    Unit <- E.must_eq("quote alias", wires(S.submit(cl, "/quote PRIVMSG alice :hello")), "PRIVMSG alice :hello")
    Unit <- E.must("raw stays outside composer history", S.input_sensitive(cl, "/raw PASS opaque-secret"))
    Unit <- E.must("keyed join stays outside composer history", S.input_sensitive(cl, "/join #private opaque-secret"))
    Unit <- E.must("ordinary join stays in composer history", Bool.not(S.input_sensitive(cl, "/join #public")))
    Unit <- E.must("keyed join stays outside local chat", Bool.not(String.contains(CL.buf_texts(keyed_join, Cl.active_of(keyed_join)), "opaque-secret")))
    Unit <- E.must("quote stays outside composer history", S.input_sensitive(cl, "/quote AUTHENTICATE opaque-secret"))
    Unit <- E.must("notice credential stays outside composer history", S.input_sensitive(cl, "/notice NickServ IDENTIFY opaque-secret"))
    Unit <- E.must("notice trailing colon cannot bypass credential history policy", S.input_sensitive(cl, "/notice NickServ :IDENTIFY opaque-secret"))
    Unit <- E.must("ordinary peer notice remains eligible for history", Bool.not(S.input_sensitive(cl, "/notice alice IDENTIFY ordinary-text")))
    Unit <- E.must("notice credential echo suppressed", S.credential_echo(cl, ":me!m@h NOTICE NickServ :IDENTIFY opaque-secret"))
    Unit <- E.must("ordinary peer notice echo remains chat", Bool.not(S.credential_echo(cl, ":me!m@h NOTICE alice :IDENTIFY ordinary-text")))
    Unit <- E.must("raw credential not locally echoed", Bool.not(String.contains(CL.buf_texts(client(S.submit(cl, "/raw PRIVMSG NickServ :IDENTIFY opaque-secret")), 1n), "opaque-secret")))
    Unit <- bad(cl, "/whois")
    Unit <- bad(cl, "/whois alice bob extra")
    Unit <- bad(server, "/topic")
    Unit <- bad(server, "/kick alice")
    Unit <- bad(server, "/invite alice")
    Unit <- bad(cl, "/notice *log* secret")
    Unit <- bad(cl, "/raw")
    Unit <- bad(cl, "/raw :me PRIVMSG alice :forged")
    Unit <- bad(cl, "/raw @tag=x PRIVMSG alice :forged")
    Unit <- bad(cl, "/raw WHOIS alice" ++ SCon{Chr{9}, "bob"})
    Unit <- bad(cl, "/raw PASS opaque" ++ SCon{Chr{0}, "secret"})
    Unit <- bad(cl, "/raw MODE #room a b c d e f g h i j k l m n o")
    Unit <- E.must_eq("raw fifteen parameters stay exact", wires(S.submit(cl, "/raw MODE #room a b c d e f g h i j k l m n")), "MODE #room a b c d e f g h i j k l m n")
    Unit <- bad(cl, "/raw PRIVMSG alice :hi" ++ SCon{Chr{13}, SCon{Chr{10}, "QUIT :injected"}})
    Unit <- bad(cl, "/topic hello" ++ SCon{Chr{0}, "hidden"})
    Unit <- bad(cl, "/raw PRIVMSG alice :" ++ Irc.stars.go(510n))
    Unit <- E.must_eq("raw exact boundary", wires(S.submit(cl, "/raw PRIVMSG alice :" ++ Irc.stars.go(495n))), "PRIVMSG alice :" ++ Irc.stars.go(495n))
    Unit <- E.must_eq("raw trailing controls remain text", wires(S.submit(cl, "/raw PRIVMSG alice :" ++ SCon{Chr{1}, "ACTION waves" ++ SCon{Chr{1}, ""}})), "PRIVMSG alice :" ++ SCon{Chr{1}, "ACTION waves" ++ SCon{Chr{1}, ""}})
    Unit <- E.must("raw auth self echo suppressed", S.credential_echo(cl, ":me!m@h PASS opaque-secret"))
    Unit <- E.must("raw authentication controls are private", S.input_sensitive(cl, "/quote OPER user opaque-secret") && S.credential_echo(cl, ":me!m@h AUTHENTICATE opaque-secret"))
    Unit <- need_wire("/whois alice")
    Unit <- need_wire("/topic")
    Unit <- need_wire("/notice alice hi")
    Unit <- need_wire("/raw WHOIS alice")
    IO.print("irc_commands=ok")
