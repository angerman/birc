# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/cards.bend as C
import ../../src/bend/media.bend as M
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed

def page() -> String:
  "https://x.test/read"

def image() -> String:
  "https://x.test/a.png"

def client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see " ++ page(), "alice", 1n}])

def state_of(pair: C.State & Maybe<&2, C.Request>) -> C.State:
  match pair:
    case (state, _): state

def job_of(pair: C.State & Maybe<&2, C.Request>) -> String:
  match pair:
    case (_, None{}): "none"
    case (_, Some{C.Request{_, url, generation, ticket}}): Nat.show(generation) ++ ":" ++ Nat.show(ticket) ++ ":" ++ url

def started(state: C.State) -> C.State:
  state_of(C.take_job(state))

def queued() -> C.State:
  C.enqueue(C.initial(True{}), C.CardInline{1n}, page())

def active() -> C.State:
  started(queued())

def fill(+n: Nat, state: C.State) -> C.State:
  match n:
    case 0n: state
    case 1n+p: fill(p, C.enqueue(state, C.CardInline{1n}, "https://x.test/" ++ Nat.show(n)))

def complete_job(pair: C.State & Maybe<&2, C.Request>, +cl: Cl.Client, payload: String) -> C.State:
  match pair:
    case (state, None{}): state
    case (+state, Some{C.Request{_, url, gen, ticket}}): C.complete(state, cl, gen, ticket, url, payload)

def populate(+n: Nat, state: C.State) -> C.State:
  match n:
    case 0n: state
    case 1n+p:
      populate(p, complete_job(C.take_job(C.enqueue(state, C.CardInline{1n}, "https://x.test/" ++ Nat.show(n))), client(), "t" ++ Nat.show(n) ++ "\nd\ni"))

def shown_title(m: Maybe<&2, C.CardReady>) -> String:
  match m:
    case None{}: "missing"
    case Some{+r}: C.ready_title(r)

def long_title() -> String:
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

def overlong() -> String:
  "https://x.test/" ++ long_title() ++ long_title() ++ long_title() ++ long_title() ++ long_title() ++ long_title() ++ long_title() ++ long_title()

def exact1024() -> String:
  String.take(overlong(), 1024n)

def over1025() -> String:
  String.take(overlong(), 1025n)

def many(+n: Nat) -> List<&2, C.Candidate>:
  match n:
    case 0n: Nil{}
    case 1n+p: C.Candidate{C.CardInline{n}, "https://x.test/o" ++ Nat.show(n)} <> many(p)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("page URL eligible", C.eligible_url(page()))
    Unit <- E.must("http page rejected", Bool.not(C.eligible_url("http://example.test/post?id=1#part")))
    Unit <- E.must("query page eligible", C.eligible_url("https://example.test/no-image?name=photo.png"))
    Unit <- E.must("image URL not a card", Bool.not(C.eligible_url(image())))
    Unit <- E.must("image query not a card", Bool.not(C.eligible_url("https://example.test/photo.JPEG?token=exact")))
    Unit <- E.must("unknown protocol rejected", Bool.not(C.eligible_url("file:///tmp/page.html")))
    Unit <- E.must("empty rejected", Bool.not(C.eligible_url("")))
    Unit <- E.must("overlong fixture exceeds bound", Nat.is_gt(String.length(overlong()), 1024n))
    Unit <- E.must("overlong URL not eligible", Bool.not(C.eligible_url(overlong())))
    Unit <- E.must("DEL rejected", Bool.not(C.eligible_url("https://x.test/re" ++ SCon{Chr{127}, "ad"})))
    Unit <- E.must_eq("exact-1024 length", Nat.show(String.length(exact1024())), "1024")
    Unit <- E.must("exact-1024 page eligible", C.eligible_url(exact1024()))
    Unit <- E.must("1025 page rejected", Bool.not(C.eligible_url(over1025())))
    Unit <- E.must_eq("page extracted", String.join(C.targets("see " ++ page() ++ " now"), "|"), page())
    Unit <- E.must_eq("image excluded from targets", String.join(C.targets("see " ++ image() ++ " now"), "|"), "")
    Unit <- E.must_eq("mixed keeps page only", String.join(C.targets(image() ++ " " ++ page()), "|"), page())
    Unit <- E.must_eq("opaque code never schedules", String.join(C.targets("`" ++ page() ++ "`"), "|"), "")
    Unit <- E.must_eq("explicit markdown image stays on media", String.join(C.targets("before ![alt](" ++ page() ++ "?raw=1) after"), "|"), "")
    Unit <- E.must_eq("ordinary markdown link is a card", String.join(C.targets("[alt](" ++ page() ++ ")"), "|"), page())
    Unit <- E.must_eq("targets capped", Nat.show(List.length(&2, String, C.targets("https://x/1 https://x/2 https://x/3 https://x/4 https://x/5 https://x/6 https://x/7 https://x/8 https://x/9 https://x/10"))), "8")
    Unit <- E.must_eq("payload title", C.fields_title(C.parse("Hello\ndesc\nhttps://x.test/i.png")), "Hello")
    Unit <- E.must_eq("payload desc", C.fields_desc(C.parse("Hello\ndesc\nhttps://x.test/i.png")), "desc")
    Unit <- E.must_eq("payload image", C.fields_image(C.parse("Hello\ndesc\nhttps://x.test/i.png")), "https://x.test/i.png")
    Unit <- E.must_eq("missing lines are empty", C.fields_desc(C.parse("only")), "")
    Unit <- E.must_eq("empty payload is empty", C.fields_title(C.parse("")), "")
    Unit <- E.must_eq("title truncates to 128", Nat.show(String.length(C.fields_title(C.parse(long_title() ++ long_title() ++ "\nd\n")))), "128")
    Unit <- E.must_eq("desc truncates to 256", Nat.show(String.length(C.fields_desc(C.parse("t\n" ++ long_title() ++ long_title() ++ long_title() ++ "\n")))), "256")
    Unit <- E.must_eq("non-http image dropped", C.fields_image(C.parse("t\nd\nfile:///tmp/i.png")), "")
    Unit <- E.must_eq("http image dropped", C.fields_image(C.parse("t\nd\nhttp://example.test/i.png")), "")
    Unit <- E.must_eq("overlong image dropped", C.fields_image(C.parse("t\nd\n" ++ overlong())), "")
    Unit <- E.must_eq("exact-1024 image preserved", C.fields_image(C.parse("t\nd\n" ++ exact1024())), exact1024())
    Unit <- E.must_eq("1025 image dropped", C.fields_image(C.parse("t\nd\n" ++ over1025())), "")
    Unit <- E.must_eq("queue bound", Nat.show(C.pending_count(fill(12n, C.initial(True{})))), "8")
    Unit <- E.must("bounded queue", C.bounded(fill(12n, C.initial(True{}))))
    Unit <- E.must("full manual queue reported", C.manual_saturated(fill(12n, C.initial(True{})), "https://x.test/manual"))
    Unit <- E.must_eq("worker starts first request", job_of(C.take_job(queued())), "1:1:" ++ page())
    Unit <- E.must_eq("one worker only", job_of(C.take_job(active())), "none")
    Unit <- E.must_eq("active duplicate suppressed", Nat.show(C.pending_count(C.enqueue(active(), C.CardInline{1n}, page()))), "0")
    Unit <- E.must("valid exact completion accepted", C.accept(active(), client(), 1n, 1n, page()))
    Unit <- E.must("wrong ticket rejected", Bool.not(C.accept(active(), client(), 1n, 2n, page())))
    Unit <- E.must("wrong URL rejected", Bool.not(C.accept(active(), client(), 1n, 1n, "https://x.test/other")))
    Unit <- E.must_eq("wrong result does not release worker", job_of(C.take_job(C.complete(active(), client(), 1n, 2n, page(), "t\nd\n"))), "none")
    Unit <- E.must_eq("accepted title stored", shown_title(C.card_for([C.CardReady{C.CardInline{1n}, page(), "T", "D", ""}], C.CardInline{1n}, page())), "T")
    Unit <- E.must_eq("unknown card is missing", shown_title(C.card_for([C.CardReady{C.CardInline{1n}, page(), "T", "D", ""}], C.CardInline{2n}, page())), "missing")
    Unit <- E.must_eq("accepted completion occupies identity", Nat.show(C.pending_count(C.enqueue(C.complete(active(), client(), 1n, 1n, page(), "T\nD\n"), C.CardInline{1n}, page()))), "0")
    Unit <- E.must_eq("empty completion still occupies identity", Nat.show(C.pending_count(C.enqueue(C.complete(active(), client(), 1n, 1n, page(), ""), C.CardInline{1n}, page()))), "0")
    Unit <- E.must_eq("disabled auto request rejected", Nat.show(C.pending_count(C.enqueue(C.initial(False{}), C.CardInline{1n}, page()))), "0")
    Unit <- E.must_eq("disabled hides in-flight automatic row", String.join(C.known_urls(C.set_enabled(active(), False{}), C.CardInline{1n}), "|"), "")
    Unit <- E.must("late disabled completion rejected", Bool.not(C.accept(C.set_enabled(active(), False{}), client(), 1n, 1n, page())))
    Unit <- E.must_eq("reset retains physical worker", job_of(C.take_job(C.enqueue(C.reset(active()), C.CardManual{}, "https://x.test/m"))), "none")
    Unit <- E.must_eq("ready cache bound", Nat.show(C.ready_count(populate(12n, C.initial(True{})))), "8")
    Unit <- E.must("ready and queue bounds", C.bounded(populate(12n, C.initial(True{}))))
    Unit <- E.must_eq("dropped line purges ready state", Nat.show(C.ready_count(C.maintain(C.complete(active(), client(), 1n, 1n, page(), "T\nD\n"), Cl.init("me", "s")))), "0")
    +query : Cl.Client = Feed.feed(Cl.init("me", "s"), ":alice!u@h PRIVMSG me :see " ++ page())
    Unit <- E.must_eq("query rename retains stable-ID ready entry", Nat.show(C.ready_count(C.maintain(C.complete(active(), query, 1n, 1n, page(), "T\nD\n"), Feed.feed(query, ":alice!u@h NICK :bob")))), "1")
    Unit <- E.must_eq("unlisted buffers never schedule", Nat.show(C.pending_count(C.observe(C.initial(True{}), client(), Nil{}, True{}))), "0")
    Unit <- E.must_eq("visible candidate schedules", Nat.show(C.pending_count(C.observe(C.initial(True{}), client(), [C.Candidate{C.CardInline{1n}, page()}], True{}))), "1")
    Unit <- E.must_eq("offline candidates do not schedule", Nat.show(C.pending_count(C.observe(C.initial(True{}), client(), [C.Candidate{C.CardInline{1n}, page()}], False{}))), "0")
    Unit <- E.must_eq("offline observe purges dead ready", Nat.show(C.ready_count(C.observe(C.complete(active(), client(), 1n, 1n, page(), "T\nD\n"), Cl.init("me", "s"), Nil{}, False{}))), "0")
    Unit <- E.must_eq("http candidate rejected", Nat.show(C.pending_count(C.observe(C.initial(True{}), client(), [C.Candidate{C.CardInline{1n}, "http://example.test/read"}], True{}))), "0")
    Unit <- E.must_eq("image candidate rejected", Nat.show(C.pending_count(C.observe(C.initial(True{}), client(), [C.Candidate{C.CardInline{1n}, image()}], True{}))), "0")
    Unit <- E.must_eq("duplicate candidates schedule once", Nat.show(C.pending_count(C.observe(C.initial(True{}), client(), [C.Candidate{C.CardInline{1n}, page()}, C.Candidate{C.CardInline{1n}, page()}], True{}))), "1")
    Unit <- E.must_eq("candidates capped at eight", Nat.show(C.pending_count(C.observe(C.initial(True{}), client(), many(10n), True{}))), "8")
    IO.print("cards_policy=ok")
