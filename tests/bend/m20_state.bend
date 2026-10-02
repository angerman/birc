# SPDX-License-Identifier: Apache-2.0
# M20 state regressions: rejected edges and ordinary behavior share each guard.
import Base
import ./expect.bend as E
import ./split_rename_demo.bend as R
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as Sess
import ../../src/bend/irc.bend as Irc
import ../../src/bend/media.bend as M

def client(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def text_at.got(+cl: Cl.Client, index: Maybe<&2, Nat>) -> String:
  match index:
    case None{}: ""
    case Some{i}: CL.buf_texts(cl, i)

def text_at(+cl: Cl.Client, +name: String) -> String:
  text_at.got(cl, Cl.buf_find(cl, name))

def search_pair(+name: String) -> Cl.Client & Cl.Client:
  +base = Feed.feed_all(Cl.init("me", "s"), [":me!u@h JOIN #room", ":alice!u@h PRIVMSG #room :hello"])
  +opened = client(Sub.submit(base, "/query " ++ name))
  +first = client(Sub.submit(opened, "/search hello"))
  (first, client(Sub.submit(first, "/search hello")))

def search_stable(pair: Cl.Client & Cl.Client) -> Bool:
  match pair:
    case (+first, +second):
      String.eq(Cl.active_buf_name(first), "*search*")
        && String.eq(text_at(first, "*search*"), "[#room] <alice> hello|")
        && String.eq(text_at(first, "*search*"), text_at(second, "*search*"))

def preview(+name: String) -> Sess.Session:
  +opened = client(Sub.submit(Cl.init("me", "s"), "/query " ++ name))
  Sess.st_of_keys(Sess.step_enter(Sess.session_demo(opened, ""), "/preview /tmp/m20.png"))

def preview_live.pending(media: M.State) -> Bool:
  match media:
    case M.State{_, _, _, _, Con{M.Request{M.Manual{}, url, _, _}, Nil{}}, _}: String.eq(url, "/tmp/m20.png")
    case _: False{}

def preview_live(+name: String) -> Bool:
  +st = preview(name)
  String.eq(Cl.active_buf_name(Sess.session_cl(st)), "*preview*")
    && M.alive(Sess.session_cl(st), M.Manual{}, "/tmp/m20.png")
    && preview_live.pending(Sess.session_media(st))

def synthetic() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("N03 uppercase search must replace, not search its previous results", search_stable(search_pair("*SEARCH*")))
    Unit <- E.must("N03 lowercase search remains stable", search_stable(search_pair("*search*")))
    Unit <- E.must("N03 uppercase preview owns a live manual request", preview_live("*PREVIEW*"))
    Unit <- E.must("N03 lowercase preview owns a live manual request", preview_live("*preview*"))
    Unit <- E.must_eq("N03 ordinary query spelling remains intact", Cl.active_buf_name(client(Sub.submit(Cl.init("me", "s"), "/query ALIce"))), "ALIce")
    Unit <- E.must("N03 literal synthetic wire targets remain rejected", Bool.not(CL.has_buf(Feed.feed(Cl.init("me", "s"), ":alice!u@h PRIVMSG *SEARCH* :hello"), "*search*")))
    E.must_eq("N03 known settings identity is canonical", Cl.active_buf_name(client(Sub.submit(Cl.init("me", "s"), "/query *SETTINGS*"))), "*settings*")

def joined(+input: String) -> Cl.Client:
  Feed.feed(client(Sub.submit(Cl.init("me", "s"), input)), ":me!u@h JOIN #room")

def join_wire(pair: Cl.Client & List<&2, String>, +want: String) -> Bool:
  match pair:
    case (cl, Con{line, Nil{}}): String.eq(Cl.active_buf_name(cl), "#room") && String.eq(line, want)
    case _: False{}

def join() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("N04 trailing separator does not create a second channel", Nat.show(CL.nbuf(joined("/join #room "))), "2")
    Unit <- E.must_eq("N04 key does not enter channel identity", Nat.show(CL.nbuf(joined("/join #room key"))), "2")
    Unit <- E.must("N04 keyed JOIN preserves the key on the wire", join_wire(Sub.submit(Cl.init("me", "s"), "/join #room key"), "JOIN #room key"))
    Unit <- E.must("N04 plain JOIN preserves the wire line", join_wire(Sub.submit(Cl.init("me", "s"), "/join #room"), "JOIN #room"))
    E.must_eq("N04 plain self JOIN reuses the channel", Nat.show(CL.nbuf(joined("/join #room"))), "2")

def members() -> Cl.Client:
  Feed.feed_all(Cl.init("me", "a.example"), [":me!u@h JOIN #room", ":s 353 me = #room :me alice", ":s 366 me #room :End", ":alice!u@h PRIVMSG #room :retained", ":s 332 me #room :old topic"])

def fresh_names(cl: Cl.Client) -> Cl.Client:
  Feed.feed_all(cl, [":me!u@h JOIN #room", ":s 353 me = #room :me", ":s 353 me = #room :bob", ":s 366 me #room :End"])

def reconnected() -> Cl.Client:
  +initial = Sess.session_online(Sess.session_with_client(members(), "#room"))
  +failed = Sess.session_fail(initial, "disconnected")
  +dialed = Sess.st_of_keys(Sess.step_enter(failed, "/reconnect"))
  Sess.session_cl(Sess.session_reconnected(dialed, "13:00:00"))

def topic.got(buf: Maybe<&2, Cl.Buffer>) -> String:
  match buf:
    case Some{Cl.Buffer{_, _, topic, _, _, _}}: topic
    case None{}: ""

def reconnect() -> IO(Unit):
  +online = reconnected()
  +after = fresh_names(online)
  +changed = Sess.endpoint_client(members(), "b.example", 6667, 6667)
  do IO<Unit>:
    Unit <- E.must_eq("N05 reconnect replaces departed channel members", CL.buf_nicks(after, "#room"), "me bob ")
    Unit <- E.must_eq("N05 new connection clears stale channel topic", topic.got(Cl.nth_buf(Cl.client_bufs(online), 1n)), "")
    Unit <- E.must("N05 reconnect retains chat history", String.contains(text_at(after, "#room"), "<alice> retained|"))
    Unit <- E.must_eq("N05 fresh multi-line NAMES still accumulates", CL.buf_nicks(fresh_names(Cl.init("me", "a.example")), "#room"), "me bob ")
    Unit <- E.must_eq("N05 changed endpoint drops old channels", Nat.show(CL.nbuf(changed)), "1")
    E.must_eq("N05 changed endpoint control server remains unseeded", CL.buf_nicks.idx(changed, 0n), "")

def auth() -> IO(Unit):
  +own = Feed.feed(Cl.init("AUTH", "s"), ":alice!u@h PRIVMSG AUTH :hello")
  +peer = Feed.feed(Cl.init("me", "s"), ":me!u@h PRIVMSG AUTH :hello")
  +own_notice = Feed.feed(Cl.init("AUTH", "s"), ":alice!u@h NOTICE AUTH :hello")
  +peer_notice = Feed.feed(Cl.init("me", "s"), ":me!u@h NOTICE AUTH :hello")
  do IO<Unit>:
    Unit <- E.must_eq("N06 own nick AUTH receives a private query", text_at(own, "alice"), "<alice> hello|")
    Unit <- E.must_eq("N06 own nick AUTH does not write private text on server", CL.buf_texts(own, 0n), "")
    Unit <- E.must("N06 own nick AUTH retains private alert", U32.is_eq(Cl.buf_unread_status(Cl.settings_unreads(Cl.get_settings(own)), "alice"), 2))
    Unit <- E.must_eq("N06 peer AUTH echo stays in peer query", text_at(peer, "AUTH"), "<me> hello|")
    Unit <- E.must_eq("N06 own nick AUTH receives private NOTICE", text_at(own_notice, "alice"), "<alice> hello|")
    Unit <- E.must_eq("N06 peer AUTH NOTICE echo stays private", text_at(peer_notice, "AUTH"), "<me> hello|")
    Unit <- E.must_eq("N06 registration NOTICE AUTH stays on server", CL.buf_texts(Feed.feed(Cl.init("me", "s"), ":irc NOTICE AUTH :hi"), 0n), "<irc> hi|")
    E.must_eq("N06 NOTICE star stays on server", CL.buf_texts(Feed.feed(Cl.init("me", "s"), ":irc NOTICE * :hi"), 0n), "<irc> hi|")

def rejected_rename(+target: String) -> Bool:
  +before = R.open_split(Cl.set_active(R.query("alice"), 2n), "alice")
  +after = R.nick(before, "alice", target)
  R.state_is(after, "#room", "alice", 0, 2n) && CL.has_buf(Sess.session_cl(after), "alice")

def split() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("N07 reserved NICK leaves query pane and focus unchanged", rejected_rename("*server*"))
    Unit <- E.must("N07 empty NICK leaves query pane and focus unchanged", rejected_rename(""))
    Unit <- E.must("N07 ordinary rename keeps its pane", R.second_unfocused())
    Unit <- E.must("N07 collision still coalesces queries", R.collision_one_pane())
    E.must("N07 framed control-prefixed ordinary nickname remains a valid rename", R.state_is(R.nick(R.open_split(Cl.set_active(R.query("alice"), 2n), "alice"), "alice", SCon{Chr{31}, "bob"}), "#room", "bob", 0, 2n))

def peer_nicks(+name: String) -> String:
  CL.buf_nicks(Feed.feed(Cl.init("me", "s"), ":" ++ name ++ "!u@h PRIVMSG me :hi"), name)

def seed() -> IO(Unit):
  +query = Feed.feed(Feed.feed(Cl.init("me", "s"), ":server!u@h PRIVMSG me :hi"), ":server!u@h NICK :other")
  do IO<Unit>:
    Unit <- E.must_eq("N11 legal peer server seeds completion", peer_nicks("server"), "server ")
    Unit <- E.must_eq("N11 legal peer server seed follows rename", CL.buf_nicks(query, "other"), "other ")
    Unit <- E.must_eq("N11 ordinary query still seeds peer", peer_nicks("alice"), "alice ")
    E.must_eq("N11 control server does not seed a peer", CL.buf_nicks.idx(query, 0n), "")

def completion.got(trip: Sess.Comp & String & U32, +want: String) -> Bool:
  match trip:
    case (_, text, seed): String.eq(text, want) && U32.is_eq(seed, 1)

def command_names(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: h ++ "|" ++ command_names(t)

def completion() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("N12 log command completes", completion.got(Sess.comp_step(Cl.init("me", "s"), Sess.comp0(), "/lo"), "/log "))
    Unit <- E.must_eq("N12 log dispatch remains accepted", Cl.active_buf_name(client(Sub.submit(Cl.init("me", "s"), "/log"))), "*log*")
    Unit <- E.must("N12 ordinary join completion remains", Sess.comp_step_ok())
    E.must_eq("K02 existing completion order and aliases remain explicit", command_names(Sess.slash_command_list()), "/join|/part|/close|/msg|/query|/nick|/me|/quit|/settings|/set|/toggle|/mute|/unmute|/mutes|/connect|/reconnect|/open|/links|/search|/preview|/images|/log|/split|/vsplit|/split-off|/unsplit|/focus|/upload|")

def scanned(pair: String & String, +token: String, +rest: String) -> Bool:
  match pair:
    case (got_token, got_rest): String.eq(got_token, token) && String.eq(got_rest, rest)

def spacing() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("K03 protocol scan keeps all separators", scanned(Irc.take_until_space("cmd   rest"), "cmd", "   rest"))
    Unit <- E.must("K03 verb scan drops one separator", scanned(Sub.take_verb("cmd   rest"), "cmd", "  rest"))
    Unit <- E.must("K03 word scan drops all separators", scanned(Sub.take_word("cmd   rest"), "cmd", "rest"))
    Unit <- E.must("K03 leading keep policy", scanned(Irc.take_until_space("  a"), "", "  a"))
    Unit <- E.must("K03 leading drop-one policy", scanned(Sub.take_verb("  a"), "", " a"))
    Unit <- E.must("K03 leading drop-all policy", scanned(Sub.take_word("  a"), "", "a"))
    Unit <- E.must("K03 no separator keeps entire token", scanned(Sub.take_word("cmd"), "cmd", ""))
    Unit <- E.must("K03 empty scan remains empty", scanned(Sub.take_verb(""), "", ""))
    E.must("K03 tab is not an IRC separator", scanned(Sub.take_word("a\tb"), "a\tb", ""))

def all() -> IO(Unit):
  do IO<Unit>:
    synthetic()
    join()
    reconnect()
    auth()
    split()
    seed()
    completion()
    spacing()
    IO.print("m20_state=ok")

def scenario(+mode: String) -> IO(Unit):
  match mode:
    case "synthetic": synthetic()
    case "join": join()
    case "reconnect": reconnect()
    case "auth": auth()
    case "split": split()
    case "seed": seed()
    case "completion": completion()
    case "spacing": spacing()
    case _: all()

def args(xs: List<&1, String>) -> IO(Unit):
  match xs:
    case Con{_, Con{mode, Nil{}}}: scenario(mode)
    case _: all()

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&1, String> <- IO.args()
    args(xs)
