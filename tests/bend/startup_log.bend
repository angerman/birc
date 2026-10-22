# SPDX-License-Identifier: Apache-2.0
# Interactive startup focuses *log* and keeps stage lines across archive import.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/history.bend as H
import ../../src/bend/history_startup.bend as HS

def ep() -> String:
  "irc.example:6697"

def base() -> Cl.Client:
  Cl.set_now(Cl.init("me", "irc.example"), "12:00:00")

def loading() -> Cl.Client:
  Cl.startup_shown(True{}, base(), ep())

def connecting() -> Cl.Client:
  Cl.startup_connect(loading(), ep())

def direct() -> Cl.Client:
  Cl.startup_shown(False{}, base(), ep())

def quiet() -> Cl.Client:
  Cl.startup_connect(base(), ep())

def line(+id: Nat, +text: String) -> Cl.Line:
  Cl.Line{Cl.Msg{}, "12:00:00", text, "alice", id}

def snap() -> Cl.Client:
  Cl.Client{"archive", "irc.example",
    Cl.buf_indexed("server", False{}, "", line(1n, "motd") <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})
      <> (Cl.buf_indexed("#room", True{}, "", line(2n, "archived") <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})
      <> (Cl.buf_indexed("ChanServ", False{}, "", line(20n, "registered") <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})
      <> (Cl.buf_indexed("SaslServ", False{}, "", line(21n, "ready") <> Nil{}, Nil{}, Cl.ScrollAt{0n, 0n})
      <> Nil{}))),
    0n, "old", Cl.settings0(), Cl.AuthIdle{}, 21n, False{}}

def joined_log() -> Cl.Client:
  Feed.feed(loading(), ":me!u@h JOIN #chan")

def found_buf(got: Maybe<&2, Nat>) -> Bool:
  match got:
    case None{}: False{}
    case Some{_}: True{}

def restored() -> Cl.Client:
  HS.install_startup(connecting(), snap(), ep(), ep())

def held() -> Cl.Client:
  Cl.diagnostic_notice(restored(), Cl.System{}, "channel joins held: waiting for authentication")

def established() -> Cl.Client:
  Cl.diagnostic_notice(held(), Cl.System{}, "IRC connection established")

def texts.go(lines: List<&2, Cl.Line>, +acc: String) -> String:
  match lines:
    case Nil{}: acc
    case Con{Cl.Line{_, _, +text, _, _}, +t}: texts.go(t, acc ++ text ++ "|")

def log_text.from(bufs: List<&2, Cl.Buffer>) -> String:
  match bufs:
    case Nil{}: ""
    case Con{Cl.Buffer{_, _, _, +lines, _, _, _, _}, _}: texts.go(lines, "")

def log_text(+cl: Cl.Client) -> String:
  log_text.from(Cl.log_buffers(cl))

def names(bufs: List<&2, Cl.Buffer>) -> String:
  match bufs:
    case Nil{}: ""
    case Con{Cl.Buffer{+name, _, _, _, _, _, _, _}, +t}: name ++ ";" ++ names(t)

def client_names(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _, _}: names(bufs)

def room_text.keep(hit: Bool, +lines: List<&2, Cl.Line>, k: Unit -> String) -> String:
  match hit:
    case True{}: texts.go(lines, "")
    case False{}: k(Unit{})

def room_text.go(fuel: Nat, bufs: List<&2, Cl.Buffer>) -> String:
  match fuel:
    case 0n: ""
    case 1n+p:
      match bufs:
        case Nil{}: ""
        case Con{Cl.Buffer{+name, _, _, +lines, _, _, _, _}, +t}:
          room_text.keep(String.eq(name, "#room"), lines, done => room_text.go(p, t))

def room_text(+cl: Cl.Client) -> String:
  match cl:
    case Cl.Client{_, _, +bufs, _, _, _, _, _, _}: room_text.go(16n, bufs)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("loading focuses log", Cl.active_buf_name(loading()), "*log*")
    Unit <- E.must_eq("loading names", client_names(loading()), "server;*log*;")
    Unit <- E.must_eq("loading line", log_text(loading()), Cl.startup_loading(ep()) ++ "|")
    Unit <- E.must_eq("direct connect focuses log", Cl.active_buf_name(direct()), "*log*")
    Unit <- E.must_eq("direct connect line", log_text(direct()), Cl.startup_connecting(ep()) ++ "|")
    Unit <- E.must_eq("closed notice stays lazy", client_names(quiet()), "server;")
    Unit <- E.must("closed notice spends no id", Nat.is_eq(Cl.log_seq_of(quiet()), 0n))
    Unit <- E.must("closed notice keeps server focus", Nat.is_eq(Cl.active_of(quiet()), 0n))
    Unit <- E.must_eq("connect appends without moving focus", Cl.active_buf_name(connecting()), "*log*")
    Unit <- E.must_eq("connect line follows loading", log_text(connecting()),
      Cl.startup_loading(ep()) ++ "|" ++ Cl.startup_connecting(ep()) ++ "|")
    Unit <- E.must_eq("import keeps the stage log", log_text(restored()), log_text(connecting()))
    Unit <- E.must_eq("import keeps log focus", Cl.active_buf_name(restored()), "*log*")
    Unit <- E.must_eq("import appends archive order", client_names(restored()), "server;*log*;#room;ChanServ;SaslServ;")
    Unit <- E.must_eq("self JOIN on the log stays there", Cl.active_buf_name(joined_log()), "*log*")
    Unit <- E.must("self JOIN still opens the channel", found_buf(Cl.buf_find(joined_log(), "#chan")))
    Unit <- E.must("import keeps the archived room line", String.contains(room_text(restored()), "archived"))
    Unit <- E.must_eq("stage lines are not chat history", H.extract_new_history(Cl.init("me", "irc.example"), connecting()), "")
    Unit <- E.must_eq("held and connected stay on log", Cl.active_buf_name(established()), "*log*")
    Unit <- E.must("held line is visible", String.contains(log_text(established()), "channel joins held: waiting for authentication"))
    Unit <- E.must("connected line is visible", String.contains(log_text(established()), "IRC connection established"))
    IO.print("startup_log=ok\n")
