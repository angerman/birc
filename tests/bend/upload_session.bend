# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/session.bend as Sess
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/upload.bend as U

def online() -> Sess.Session:
  +cl = Feed.feed(Cl.init("me", "irc.example"), ":me!u@h JOIN :+#room")
  Sess.session_online(Sess.session_with_client_at(Cl.set_active(cl, 1n), "+#room", 6667))

def offered() -> Sess.Session:
  Sess.st_of_keys(Sess.step_enter(online(), "/upload '/tmp/private file.txt'"))

def shown(+st: Sess.Session) -> Sess.Session:
  Sess.session_upload_present(st, st)

def presented() -> Sess.Session:
  shown(offered())

def phase(state: U.State) -> String:
  match state:
    case U.Idle{}: "idle"
    case U.Confirm{U.Request{_, path}, _}: "confirm:" ++ path
    case U.Armed{U.Request{_, path}, _}: "ready:" ++ path
    case U.Busy{_, _, allowed}: "busy:" ++ Bool.show(allowed)

def command(triple: Sess.Session & Sess.NetCmd & Bool) -> String:
  match triple:
    case (_, cmd, _): Sess.show_netcmd(cmd)

def wire(triple: Sess.Session & Sess.NetCmd & Bool) -> String:
  match triple:
    case (_, Sess.Cont{outs}, _): String.join(outs, "|")
    case _: "other"

def halt(triple: Sess.Session & Sess.NetCmd & Bool) -> Bool:
  match triple:
    case (_, _, halt): halt

def history(st: Sess.Session) -> String:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, Sess.Hist{lines, _}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}: String.join(lines, "|")

def line_texts(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, _, text, _, _}, t}: text ++ "|" ++ line_texts(t)

def buffers_text(bufs: List<&2, Cl.Buffer>) -> String:
  match bufs:
    case Nil{}: ""
    case Con{Cl.Buffer{_, _, topic, lines, _, _, _, _}, t}: topic ++ "|" ++ line_texts(lines) ++ buffers_text(t)

def saved_text(st: Sess.Session) -> String:
  buffers_text(Cl.client_bufs(Sess.session_cl(st)))

def key_state(pair: Sess.Session & Bool) -> Sess.Session:
  match pair:
    case (st, _): st

def handled(pair: Sess.Session & Bool) -> Bool:
  match pair:
    case (_, on): on

def take_state(pair: Sess.Session & Maybe<&2, U.Request>) -> Sess.Session:
  match pair:
    case (st, _): st

def take_path(pair: Sess.Session & Maybe<&2, U.Request>) -> String:
  match pair:
    case (_, None{}): "none"
    case (_, Some{request}): U.request_path(request)

def busy() -> Sess.Session:
  take_state(Sess.session_upload_take(key_state(Sess.session_upload_key(presented(), 22, 0))))

def complete_result(pair: Sess.Session & Maybe<&2, String>) -> String:
  match pair:
    case (_, None{}): "none"
    case (_, Some{url}): url

def complete_state(pair: Sess.Session & Maybe<&2, String>) -> Sess.Session:
  match pair:
    case (st, _): st

def request() -> U.Request:
  U.Request{U.Scope{"irc.example", 6667, "+#room"}, "/tmp/private file.txt"}

def switch_target(+st: Sess.Session) -> Sess.Session:
  Sess.session_set_client(st, Cl.set_active(Sess.session_cl(st), 0n))

def nick_client() -> Cl.Client:
  Feed.feed(Feed.feed(Sess.session_cl(online()), ":alice!u@h JOIN :+#room"), ":adam!u@h JOIN :+#room")

def complete_tab(+st: Sess.Session, text: String) -> Sess.Session:
  Sess.st_of_keys(Sess.step_keys(st, Sess.Keys{text, False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 1, 0}))

def batch_busy() -> Sess.Session:
  +pending = Sess.st_of_keys(Sess.step_enter(online(), "/upload /tmp/a /tmp/b"))
  take_state(Sess.session_upload_take(key_state(Sess.session_upload_key(shown(pending), 22, 0))))

def unsent_batch() -> Sess.Session:
  Sess.st_of_keys(Sess.step_keys(batch_busy(), Sess.Keys{"unsent draft", False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 0, 0}))

def next_pending() -> Sess.Session:
  complete_state(Sess.session_upload_complete(unsent_batch(), U.Request{U.Scope{"irc.example", 6667, "+#room"}, "/tmp/a"}, "https://0x0.st/a\n"))

def ordinary_tab() -> Sess.Session:
  complete_tab(Sess.session_set_client(online(), nick_client()), "a")

def ordinary_cycle() -> Sess.Session:
  +first = ordinary_tab()
  complete_tab(first, Sess.session_draft(first))

def busy_tab() -> Sess.Session:
  complete_tab(Sess.session_set_client(busy(), nick_client()), "a")

def busy_cycle() -> Sess.Session:
  +first = busy_tab()
  complete_tab(first, Sess.session_draft(first))

def completion.word(got: Maybe<&2, Sess.CompWord>) -> String:
  match got:
    case None{}: "none"
    case Some{Sess.CompWord{pre, word, idx}}: pre ++ "|" ++ word ++ "|" ++ Nat.show(idx)

def completion(st: Sess.Session) -> String:
  match st:
    case Sess.Session{_, _, _, _, _, _, _, _, _, _, comp, _, _, _, _, _, _, _, _, _, _, _, _, _}: completion.word(Sess.comp_word(comp))

def batch_tab() -> Sess.Session:
  complete_tab(Sess.session_set_client(batch_busy(), nick_client()), "a")

def batch_tab_pending() -> Sess.Session:
  complete_state(Sess.session_upload_complete(batch_tab(), U.Request{U.Scope{"irc.example", 6667, "+#room"}, "/tmp/a"}, "https://0x0.st/a\n"))

def duplicate_busy() -> Sess.Session:
  +pending = Sess.st_of_keys(Sess.step_enter(online(), "/upload /tmp/a /tmp/a"))
  take_state(Sess.session_upload_take(key_state(Sess.session_upload_key(shown(pending), 22, 0))))

def duplicate_pending() -> Sess.Session:
  complete_state(Sess.session_upload_complete(duplicate_busy(), U.Request{U.Scope{"irc.example", 6667, "+#room"}, "/tmp/a"}, "https://0x0.st/a\n"))

def repeated(n: Nat, +part: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: part ++ repeated(p, part)

def drop_refused(+raw: String, +private: String) -> Bool:
  +st = Sess.st_of_keys(Sess.step_enter(online(), raw))
  String.is_empty(wire(Sess.step_enter(online(), raw))) && String.is_empty(history(st)) && String.is_empty(Sess.session_draft(st))
    && String.eq(phase(Sess.session_upload(st)), "idle")
    && Bool.not(String.contains(saved_text(st), private))
    && String.contains(saved_text(st), "usage: /upload <local-path>")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("quoted decoded malformed URI never sends or persists path", drop_refused("fi''le:///tmp/private%FF.jpg", "/tmp/private"))
    Unit <- E.must("escaped decoded malformed URI never sends or persists path", drop_refused("fi\\le:///tmp/private%FF.jpg", "/tmp/private"))
    Unit <- E.must("unclosed decoded URI prefix never sends or persists path", drop_refused("fi'le:///tmp/private%FF.jpg", "/tmp/private"))
    Unit <- E.must("uppercase malformed URI never sends or persists path", drop_refused("FILE:///tmp/private%FF.jpg", "/tmp/private"))
    Unit <- E.must("uppercase unsupported URI never sends or persists path", drop_refused("FILE:///tmp/private.jpg", "/tmp/private"))
    Unit <- E.must("empty quoted prefixes cannot hide malformed path", drop_refused("'' /tmp/private\\", "/tmp/private"))
    Unit <- E.must_eq("quoted decoded valid URI stages exact path", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(online(), "fi''le:///tmp/%C3%A9.txt")))), "confirm:/tmp/é.txt")
    Unit <- E.must_eq("escaped decoded valid URI stages exact path", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(online(), "fi\\le:///tmp/%C3%A9.txt")))), "confirm:/tmp/é.txt")
    Unit <- E.must_eq("quoted ordinary firstword retains later prose path", wire(Sess.step_enter(online(), "or''dinary /tmp/private")), "PRIVMSG +#room :or''dinary /tmp/private")
    Unit <- E.must_eq("empty quoted prefix retains ordinary prose", wire(Sess.step_enter(online(), "'' ordinary /tmp/private")), "PRIVMSG +#room :'' ordinary /tmp/private")
    Unit <- E.must("malformed UTF8 file URI never sends or persists path", drop_refused("file:///tmp/private%FF.jpg", "/tmp/private"))
    Unit <- E.must("oversize quoted drop batch never sends or persists paths", drop_refused(repeated(9n, "'/tmp/private' "), "/tmp/private"))
    Unit <- E.must("unclosed absolute quote never sends or persists path", drop_refused("'/tmp/private", "/tmp/private"))
    Unit <- E.must("escaped malformed drop never sends or persists path", drop_refused("\\/tmp/private\\", "/tmp/private"))
    Unit <- E.must("remote file URI never sends or persists path", drop_refused("file://remote/tmp/private", "/tmp/private"))
    Unit <- E.must("leading-space quoted malformed URI never sends", drop_refused("  \"file:///tmp/private%GG", "/tmp/private"))
    Unit <- E.must("concatenated quote prefix cannot hide malformed URI", drop_refused("''file:///tmp/private%FF", "/tmp/private"))
    Unit <- E.must("escaped URI prefix cannot hide malformed URI", drop_refused("\\file:///tmp/private%FF", "/tmp/private"))
    Unit <- E.must_eq("valid UTF8 URI still stages exact local path", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(online(), "file:///tmp/%C3%A9.txt")))), "confirm:/tmp/é.txt")
    Unit <- E.must_eq("prose with later path remains ordinary", wire(Sess.step_enter(online(), "please read /tmp/private")), "PRIVMSG +#room :please read /tmp/private")
    Unit <- E.must_eq("deliberate msg path remains explicit chat", wire(Sess.step_enter(online(), "/msg alice /tmp/private")), "PRIVMSG alice :/tmp/private")
    Unit <- E.must("F8 before presentation cannot authorize", Bool.not(handled(Sess.session_upload_key(offered(), 22, 0))))
    Unit <- E.must_eq("unpresented request cannot launch", take_path(Sess.session_upload_take(key_state(Sess.session_upload_key(offered(), 22, 0)))), "none")
    Unit <- E.must_eq("new staged request remains unpresented", take_path(Sess.session_upload_take(key_state(Sess.session_upload_key(Sess.session_upload_present(online(), offered()), 22, 0)))), "none")
    Unit <- E.must_eq("one completed paint enables same request", take_path(Sess.session_upload_take(key_state(Sess.session_upload_key(presented(), 22, 0)))), "/tmp/private file.txt")
    Unit <- E.must_eq("worker-completed next request remains unpresented", take_path(Sess.session_upload_take(key_state(Sess.session_upload_key(Sess.session_upload_present(unsent_batch(), next_pending()), 22, 0)))), "none")
    Unit <- E.must_eq("same path next file cannot reuse presentation", take_path(Sess.session_upload_take(key_state(Sess.session_upload_key(duplicate_pending(), 22, 0)))), "none")
    Unit <- E.must_eq("Busy transition cannot mark identical request presented", take_path(Sess.session_upload_take(key_state(Sess.session_upload_key(Sess.session_upload_present(duplicate_busy(), duplicate_pending()), 22, 0)))), "none")
    Unit <- E.must_eq("new paint can enable duplicate path next file", take_path(Sess.session_upload_take(key_state(Sess.session_upload_key(shown(duplicate_pending()), 22, 0)))), "/tmp/a")
    Unit <- E.must("maintain retains same presented request", Sess.session_upload_presented(Sess.session_upload_maintain(presented())))
    Unit <- E.must("pending ordinary editing retains presentation", Sess.session_upload_presented(Sess.st_of_keys(Sess.step_keys(presented(), Sess.Keys{"draft", False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 0, 0}))))
    Unit <- E.must("different request resets presentation", Bool.not(Sess.session_upload_presented(Sess.session_set_upload(presented(), U.Confirm{U.Request{U.Scope{"irc.example", 6667, "+#room"}, "/tmp/other"}, Nil{}}))))
    Unit <- E.must("Busy cannot retain presentation", Bool.not(Sess.session_upload_presented(busy())))
    Unit <- E.must("scope invalidation removes presentation", Bool.not(Sess.session_upload_presented(Sess.session_upload_maintain(switch_target(presented())))))
    Unit <- E.must_eq("presentation keeps unsent draft", Sess.session_draft(shown(next_pending())), "unsent draft")
    Unit <- E.must_eq("presentation keeps ordinary completion", completion(shown(batch_tab_pending())), completion(batch_tab_pending()))
    Unit <- E.must_eq("batch completion preserves unsent draft", Sess.session_draft(next_pending()), "unsent draft")
    Unit <- E.must_eq("next file still needs consent", phase(Sess.session_upload(next_pending())), "confirm:/tmp/b")
    Unit <- E.must_eq("F8 preserves unsent draft", Sess.session_draft(key_state(Sess.session_upload_key(shown(next_pending()), 22, 0))), "unsent draft")
    Unit <- E.must_eq("Esc preserves unsent draft", Sess.session_draft(key_state(Sess.session_upload_key(next_pending(), 1, 0))), "unsent draft")
    Unit <- E.must_eq("batch completion preserves ordinary completion", completion(batch_tab_pending()), completion(batch_tab()))
    Unit <- E.must_eq("F8 preserves ordinary completion", completion(key_state(Sess.session_upload_key(shown(batch_tab_pending()), 22, 0))), completion(batch_tab()))
    Unit <- E.must_eq("Esc preserves ordinary completion", completion(key_state(Sess.session_upload_key(batch_tab_pending(), 1, 0))), completion(batch_tab()))
    Unit <- E.must_eq("session stages explicit upload", phase(Sess.session_upload(offered())), "confirm:/tmp/private file.txt")
    Unit <- E.must_eq("exact drop never sends raw path", wire(Sess.step_enter(online(), "'/tmp/private file.txt'")), "")
    Unit <- E.must_eq("upload command absent from history", history(offered()), "")
    Unit <- E.must("local full path absent from stored lines", Bool.not(String.contains(saved_text(offered()), "/tmp/private file.txt")))
    Unit <- E.must_eq("warning includes public destination and explicit keys", Sess.session_upload_hint(offered()), "F8: upload publicly to 0x0.st; Esc: cancel | +#room | private file.txt (files=1)")
    Unit <- E.must_eq("warning never replaces composer", Sess.session_draft(offered()), "")
    Unit <- E.must_eq("drop is not staged until submit", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_keys(online(), Sess.Keys{"'/tmp/private file.txt'", False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 0, 0})))), "idle")
    Unit <- E.must_eq("explicit malformed path is refused", wire(Sess.step_enter(online(), "/upload file://remote/tmp/a")), "")
    Unit <- E.must_eq("malformed path absent from history", history(Sess.st_of_keys(Sess.step_enter(online(), "/upload file://remote/tmp/a"))), "")
    Unit <- E.must_eq("offline upload refuses without worker", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(Sess.session_fail(online(), "fixture"), "/upload /tmp/a")))), "idle")
    Unit <- E.must_eq("demo upload refuses without worker", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(Sess.session_demo(Sess.session_cl(online()), "+#room"), "/upload /tmp/a")))), "idle")
    Unit <- E.must_eq("control buffer upload refuses", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(switch_target(online()), "/upload /tmp/a")))), "idle")
    Unit <- E.must_eq("ordinary message remains exact", wire(Sess.step_enter(online(), "ordinary text")), "PRIVMSG +#room :ordinary text")
    Unit <- E.must_eq("public URL remains ordinary message", wire(Sess.step_enter(online(), "https://0x0.st/a")), "PRIVMSG +#room :https://0x0.st/a")
    Unit <- E.must("known quit command retains behavior", halt(Sess.step_enter(online(), "/quit")))
    Unit <- E.must_eq("known settings command never becomes path", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(online(), "/settings")))), "idle")
    Unit <- E.must_eq("Session-owned command alias never becomes path", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(online(), "/connect")))), "idle")
    Unit <- E.must_eq("pending paste cannot authorize or send", wire(Sess.step_enter(offered(), "/upload-confirm")), "")
    Unit <- E.must_eq("pending paste does not enter history", history(Sess.st_of_keys(Sess.step_enter(offered(), "/msg nick secret"))), "")
    Unit <- E.must_eq("pending blocked submit preserves draft", Sess.session_draft(Sess.st_of_keys(Sess.step_enter(offered(), "unsent draft"))), "unsent draft")
    Unit <- E.must_eq("pending blocked native submit reseeds same draft", U32.show(Sess.session_seed(Sess.st_of_keys(Sess.step_enter(offered(), "unsent draft")))), "1")
    Unit <- E.must("pending pasted quit does not bypass modal", Bool.not(halt(Sess.step_enter(offered(), "/quit"))))
    Unit <- E.must("modified F8 cannot confirm", Bool.not(handled(Sess.session_upload_key(presented(), 22, 1))))
    Unit <- E.must_eq("Enter is not confirmation", take_path(Sess.session_upload_take(Sess.st_of_keys(Sess.step_enter(offered(), "yes")))), "none")
    Unit <- E.must("physical unmodified F8 handled", handled(Sess.session_upload_key(presented(), 22, 0)))
    Unit <- E.must_eq("physical F8 authorizes exactly stored path", take_path(Sess.session_upload_take(key_state(Sess.session_upload_key(presented(), 22, 0)))), "/tmp/private file.txt")
    Unit <- E.must_eq("second take cannot start another worker", take_path(Sess.session_upload_take(busy())), "none")
    Unit <- E.must_eq("confirmation clears warning draft", Sess.session_draft(busy()), "")
    Unit <- E.must("Esc cancel consumed while pending", handled(Sess.session_upload_key(offered(), 1, 0)))
    Unit <- E.must_eq("Esc cancels without worker", phase(Sess.session_upload(key_state(Sess.session_upload_key(offered(), 1, 0)))), "idle")
    Unit <- E.must("ordinary Esc retains quit handling", Bool.not(handled(Sess.session_upload_key(online(), 1, 0))))
    Unit <- E.must_eq("busy permits ordinary message", wire(Sess.step_enter(busy(), "hello")), "PRIVMSG +#room :hello")
    Unit <- E.must_eq("busy message enters normal command history", history(Sess.st_of_keys(Sess.step_enter(busy(), "hello"))), "hello")
    Unit <- E.must_eq("busy keeps owner across message", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(busy(), "hello")))), "busy:True")
    Unit <- E.must_eq("busy ordinary draft retained", Sess.session_draft(Sess.st_of_keys(Sess.step_keys(busy(), Sess.Keys{"draft", False{}, Cl.TabStay{}, None{}, 0n, 0n, Sess.HistStay{}, 0, 0}))), "draft")
    Unit <- E.must("ordinary completion positive control", Bool.not(String.eq(Sess.session_draft(ordinary_tab()), "a")))
    Unit <- E.must("ordinary completion cycle positive control", Bool.not(String.eq(Sess.session_draft(ordinary_tab()), Sess.session_draft(ordinary_cycle()))))
    Unit <- E.must_eq("busy nickname completion starts like ordinary control", Sess.session_draft(busy_tab()), Sess.session_draft(ordinary_tab()))
    Unit <- E.must_eq("busy nickname completion cycles like ordinary control", Sess.session_draft(busy_cycle()), Sess.session_draft(ordinary_cycle()))
    Unit <- E.must_eq("new drop while busy never sends", wire(Sess.step_enter(busy(), "'/tmp/another.txt'")), "")
    Unit <- E.must_eq("new drop while busy never enters history", history(Sess.st_of_keys(Sess.step_enter(busy(), "'/tmp/another.txt'"))), "")
    Unit <- E.must_eq("new drop preserves original worker", phase(Sess.session_upload(Sess.st_of_keys(Sess.step_enter(busy(), "'/tmp/another.txt'")))), "busy:True")
    Unit <- E.must_eq("successful result contains URL only", complete_result(Sess.session_upload_complete(busy(), request(), "https://0x0.st/a.txt\n")), "https://0x0.st/a.txt")
    Unit <- E.must_eq("matching result releases worker", phase(Sess.session_upload(complete_state(Sess.session_upload_complete(busy(), request(), "https://0x0.st/a.txt\n")))), "idle")
    Unit <- E.must_eq("changed target prevents sending", complete_result(Sess.session_upload_complete(switch_target(busy()), request(), "https://0x0.st/a.txt\n")), "none")
    Unit <- E.must_eq("busy Esc keeps cancelled owner", phase(Sess.session_upload(key_state(Sess.session_upload_key(busy(), 1, 0)))), "busy:False")
    Unit <- E.must_eq("busy Esc result discarded", complete_result(Sess.session_upload_complete(key_state(Sess.session_upload_key(busy(), 1, 0)), request(), "https://0x0.st/a.txt\n")), "none")
    Unit <- E.must("presentation reset inspector", Sess.upload_presentation_reset_ok())
    IO.print("upload_session=ok")
