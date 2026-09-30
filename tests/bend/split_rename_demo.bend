# A remote NICK renames an open query; it must not remove its split pane.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/frame.bend as Fr

def client(pair: Cl.Client & Maybe<&2, Nat>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def query(+who: String) -> Cl.Client:
  Cl.set_active(client(Cl.buf_get(Feed.feed(Cl.init("me", "s"), ":" ++ who ++ "!u@h PRIVMSG me :hello"), "#room", True{}, True{})), 1n)

def open_split(+cl: Cl.Client, +target: String) -> Sess.Session:
  Sess.st_of_keys(Sess.step_enter(Sess.session_demo(cl, "#room"), "/split " ++ target))

def focus_second(st: Sess.Session) -> Sess.Session:
  Sess.st_of_keys(Sess.step_keys(st, Sess.keys_focus()))

def chunk(st: Sess.Session, wire: String) -> Sess.Session:
  Sess.st_of_chunk(Sess.step_on_chunk(st, Fr.string_to_octets(wire)))

def nick(st: Sess.Session, +from: String, +to: String) -> Sess.Session:
  chunk(st, ":" ++ from ++ "!u@h NICK :" ++ to ++ "\r\n")

def state_is.split(split: Sp.State, +cl: Cl.Client, +first: String, +second: String, focus: U32, +active: Nat) -> Bool:
  match split:
    case Sp.On{Sp.Stacked{}, a, b, f}:
      String.eq(a, first) && String.eq(b, second) && U32.is_eq(f, focus)
        && Nat.is_eq(Cl.active_of(cl), active)
    case _: False{}

def state_is(+st: Sess.Session, +first: String, +second: String, focus: U32, +active: Nat) -> Bool:
  state_is.split(Sess.session_split(st), Sess.session_cl(st), first, second, focus, active)

def first_focused() -> Bool:
  state_is(nick(open_split(query("alice"), "#room"), "alice", "bob"), "bob", "#room", 0, 1n)

def first_unfocused() -> Bool:
  state_is(nick(focus_second(open_split(query("alice"), "#room")), "alice", "bob"), "bob", "#room", 1, 2n)

def second_unfocused() -> Bool:
  state_is(nick(open_split(Cl.set_active(query("alice"), 2n), "alice"), "alice", "bob"), "#room", "bob", 0, 2n)

def second_focused() -> Bool:
  state_is(nick(focus_second(open_split(Cl.set_active(query("alice"), 2n), "alice")), "alice", "bob"), "#room", "bob", 1, 1n)

def query_named_server() -> Bool:
  state_is(nick(open_split(query("server"), "*server*"), "server", "other"), "other", "*server*", 0, 1n)

def query_renamed_server() -> Bool:
  state_is(nick(focus_second(open_split(Cl.set_active(query("alice"), 0n), "alice")), "alice", "server"), "*server*", "server", 1, 1n)

def control_not_renamed() -> Bool:
  state_is(nick(open_split(Cl.set_active(query("server"), 0n), "server"), "server", "other"), "*server*", "other", 0, 0n)

def casefold_and_case_only() -> Bool:
  state_is(nick(open_split(query("alice"), "#room"), "ALICE", "ALIce"), "ALIce", "#room", 0, 1n)

def rename_chain() -> Bool:
  state_is(chunk(open_split(query("alice"), "#room"), ":alice!u@h NICK :bob\r\n:bob!u@h NICK :carol\r\n"), "carol", "#room", 0, 1n)

def partial_nick() -> Bool:
  +before = open_split(query("alice"), "#room")
  +partial = chunk(before, ":alice!u@h NI")
  state_is(partial, "alice", "#room", 0, 1n)
    && state_is(chunk(partial, "CK :bob\r\n"), "bob", "#room", 0, 1n)

def text_is_not_rename() -> Bool:
  state_is(chunk(open_split(query("alice"), "#room"), ":alice!u@h PRIVMSG #room :alice is now known as bob\r\n"), "alice", "#room", 0, 1n)

def real_close() -> Bool:
  +closed = Sess.st_of_keys(Sess.step_enter(open_split(query("alice"), "#room"), "/close"))
  Bool.not(Sp.is_on(Sess.session_split(closed)))
    && Nat.is_eq(Cl.buf_count(Cl.client_bufs(Sess.session_cl(closed))), 2n)

def collision_client() -> Cl.Client:
  Cl.set_active(Feed.feed(query("alice"), ":bob!u@h PRIVMSG me :second"), 1n)

def collision_both_panes() -> Bool:
  +after = nick(open_split(collision_client(), "bob"), "alice", "BOB")
  Bool.not(Sp.is_on(Sess.session_split(after)))
    && Nat.is_eq(Cl.buf_count(Cl.client_bufs(Sess.session_cl(after))), 3n)
    && String.eq(Cl.active_buf_name(Sess.session_cl(after)), "BOB")

def collision_one_pane() -> Bool:
  +after = nick(open_split(collision_client(), "#room"), "alice", "bob")
  state_is(after, "bob", "#room", 0, 1n)
    && Nat.is_eq(Cl.buf_count(Cl.client_bufs(Sess.session_cl(after))), 3n)

def collision_destination_pane() -> Bool:
  +after = nick(open_split(Cl.set_active(collision_client(), 3n), "#room"), "alice", "bob")
  state_is(after, "bob", "#room", 0, 1n)
    && Nat.is_eq(Cl.buf_count(Cl.client_bufs(Sess.session_cl(after))), 3n)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("focused_first_query", first_focused())
    Unit <- E.must("unfocused_first_query", first_unfocused())
    Unit <- E.must("unfocused_second_query", second_unfocused())
    Unit <- E.must("focused_second_query", second_focused())
    Unit <- E.must("query_named_server", query_named_server())
    Unit <- E.must("query_renamed_server", query_renamed_server())
    Unit <- E.must("control_not_renamed", control_not_renamed())
    Unit <- E.must("casefold_and_case_only", casefold_and_case_only())
    Unit <- E.must("rename_chain", rename_chain())
    Unit <- E.must("partial_nick", partial_nick())
    Unit <- E.must("text_is_not_rename", text_is_not_rename())
    Unit <- E.must("real_close", real_close())
    Unit <- E.must("collision_both_panes", collision_both_panes())
    Unit <- E.must("collision_one_pane", collision_one_pane())
    Unit <- E.must("collision_destination_pane", collision_destination_pane())
    IO.print("split_rename_demo=ok")
