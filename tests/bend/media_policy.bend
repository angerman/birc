# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/media.bend as M
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/submit.bend as Sub

def client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "https://x.test/a.png", "alice", 1n}])

def state_of(pair: M.State & Maybe<&2, M.Request>) -> M.State:
  match pair:
    case (state, _): state

def job_of.fields(got: Maybe<&2, M.Work>) -> String:
  match got:
    case None{}: "none"
    case Some{M.Work{_, url, generation, ticket}}: Nat.show(generation) ++ ":" ++ Nat.show(ticket) ++ ":" ++ url

def job_of(pair: M.State & Maybe<&2, M.Request>) -> String:
  match pair:
    case (_, None{}): "none"
    # SoftFence / StickyFence yield None via work_fields (never take_job work).
    case (_, Some{req}): job_of.fields(M.work_fields(req))

def started(state: M.State) -> M.State:
  state_of(M.take_job(state))

def queued() -> M.State:
  M.enqueue(M.initial(True{}), M.Inline{1n}, "https://x.test/a.png")

def active() -> M.State:
  started(queued())

def fill(+n: Nat, state: M.State) -> M.State:
  match n:
    case 0n: state
    case 1n+p: fill(p, M.enqueue(state, M.Inline{1n}, "https://x.test/" ++ Nat.show(n) ++ ".png"))

def complete_job.work(+state: M.State, +cl: Cl.Client, token: U32, got: Maybe<&2, M.Work>) -> M.State:
  match got:
    case None{}: state
    case Some{M.Work{_, url, gen, ticket}}: M.complete(state, cl, gen, ticket, url, token)

def complete_job(pair: M.State & Maybe<&2, M.Request>, +cl: Cl.Client, token: U32) -> M.State:
  match pair:
    case (state, None{}): state
    case (+state, Some{req}): complete_job.work(state, cl, token, M.work_fields(req))

def populate(+n: Nat, state: M.State) -> M.State:
  match n:
    case 0n: state
    case 1n+p:
      populate(p, complete_job(M.take_job(M.enqueue(state, M.Inline{1n}, "https://x.test/" ++ Nat.show(n) ++ ".png")), client(), U32.from_nat(n)))

def manual_client.got(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def manual_client() -> Cl.Client:
  manual_client.got(Sub.submit(Cl.init("me", "s"), "/preview https://x.test/a.png"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("PNG direct", M.auto_url("https://example.test/image.png"))
    Unit <- E.must("JPEG case and query", M.auto_url("http://example.test/photo.JPEG?token=exact#view"))
    Unit <- E.must("encoded path is not fetched", M.auto_url("https://example.test/Screenshot%202026-09-30%20at%202.51.58%E2%80%AFPM.png"))
    Unit <- E.must("query extension is not path extension", Bool.not(M.auto_url("https://example.test/no-image?name=photo.png")))
    Unit <- E.must("unsupported protocol", Bool.not(M.auto_url("file:///tmp/image.png")))
    Unit <- E.must("unknown extension", Bool.not(M.auto_url("https://example.test/index.html")))
    Unit <- E.must_eq("all supported extensions", Nat.show(List.length(&2, String, M.targets("https://x/a.png http://x/a.jpg https://x/a.jpeg https://x/a.gif https://x/a.webp https://x/a.bmp https://x/a.tif https://x/a.tiff https://x/a.avif"))), "8")
    Unit <- E.must("AVIF supported", M.auto_url("https://x/a.avif"))
    Unit <- E.must_eq("Markdown explicit non-extension source", String.join(M.targets("before ![alt](https://x.test/raw?id=1#part) after"), "|"), "https://x.test/raw?id=1#part")
    Unit <- E.must_eq("ordinary link is not explicit image", String.join(M.targets("[alt](https://x.test/raw)"), "|"), "")
    Unit <- E.must_eq("opaque code is never automatic", String.join(M.targets("`https://x/a.png` `![alt](https://x/raw)`"), "|"), "")
    Unit <- E.must_eq("unknown protocol cannot auto-read local files", String.join(M.targets("file:///tmp/a.png ftp://x/a.png"), "|"), "")
    Unit <- E.must_eq("exact URL retained", String.join(M.targets("https://x.test/a.png?q=:eyes:*_#part,"), "|"), "https://x.test/a.png?q=:eyes:*_#part")
    Unit <- E.must_eq("queue bound", Nat.show(M.pending_count(fill(12n, M.initial(True{})))), "8")
    Unit <- E.must("bounded queue", M.bounded(fill(12n, M.initial(True{}))))
    Unit <- E.must("full manual queue reported", M.manual_saturated(fill(12n, M.initial(True{})), "https://x.test/manual.png"))
    Unit <- E.must("active manual duplicate is not saturation", Bool.not(M.manual_saturated(M.State{True{}, 1n, 20n, Some{M.Request{M.Manual{}, "https://x.test/manual.png", 1n, 19n}}, [M.Request{M.Inline{1n}, "a", 1n, 1n}, M.Request{M.Inline{1n}, "b", 1n, 2n}, M.Request{M.Inline{1n}, "c", 1n, 3n}, M.Request{M.Inline{1n}, "d", 1n, 4n}, M.Request{M.Inline{1n}, "e", 1n, 5n}, M.Request{M.Inline{1n}, "f", 1n, 6n}, M.Request{M.Inline{1n}, "g", 1n, 7n}, M.Request{M.Inline{1n}, "h", 1n, 8n}], Nil{}, M.Supported{}}, "https://x.test/manual.png")))
    Unit <- E.must_eq("worker starts first request", job_of(M.take_job(queued())), "1:1:https://x.test/a.png")
    Unit <- E.must_eq("one worker only", job_of(M.take_job(active())), "none")
    Unit <- E.must_eq("active duplicate suppressed", Nat.show(M.pending_count(M.enqueue(active(), M.Inline{1n}, "https://x.test/a.png"))), "0")
    Unit <- E.must("valid exact completion accepted", M.accept(active(), client(), 1n, 1n, "https://x.test/a.png"))
    Unit <- E.must("wrong ticket rejected", Bool.not(M.accept(active(), client(), 1n, 2n, "https://x.test/a.png")))
    Unit <- E.must("wrong URL rejected", Bool.not(M.accept(active(), client(), 1n, 1n, "https://x.test/other.png")))
    Unit <- E.must_eq("wrong result does not release worker", job_of(M.take_job(M.complete(active(), client(), 1n, 2n, "https://x.test/a.png", 4))), "none")
    Unit <- E.must_eq("accepted token stored", U32.show(M.token(M.complete(active(), client(), 1n, 1n, "https://x.test/a.png", 4), M.Inline{1n}, "https://x.test/a.png")), "4")
    Unit <- E.must_eq("permanent auto failure does not loop", Nat.show(M.pending_count(M.enqueue(M.complete(active(), client(), 1n, 1n, "https://x.test/a.png", 0), M.Inline{1n}, "https://x.test/a.png"))), "0")
    Unit <- E.must_eq("disabled auto request rejected", Nat.show(M.pending_count(M.enqueue(M.initial(False{}), M.Inline{1n}, "https://x.test/a.png"))), "0")
    Unit <- E.must_eq("disabled hides in-flight automatic row", String.join(M.known_urls(M.set_enabled(active(), False{}), M.Inline{1n}), "|"), "")
    Unit <- E.must("late disabled completion rejected", Bool.not(M.accept(M.set_enabled(active(), False{}), client(), 1n, 1n, "https://x.test/a.png")))
    Unit <- E.must_eq("reset retains physical worker", job_of(M.take_job(M.enqueue(M.reset(active()), M.Manual{}, "https://x.test/a.png"))), "none")
    Unit <- E.must_eq("old generation completion releases old physical worker", job_of(M.take_job(M.complete(M.enqueue(M.reset(active()), M.Manual{}, "https://x.test/a.png"), manual_client(), 1n, 1n, "https://x.test/a.png", 9))), "2:2:https://x.test/a.png")
    Unit <- E.must("manual preview allowed while auto off", M.accept(started(M.enqueue(M.initial(False{}), M.Manual{}, "https://x.test/a.png")), manual_client(), 1n, 1n, "https://x.test/a.png"))
    Unit <- E.must_eq("manual failure retries identical intent", Nat.show(M.pending_count(M.enqueue(M.complete(started(M.enqueue(M.initial(False{}), M.Manual{}, "https://x.test/a.png")), manual_client(), 1n, 1n, "https://x.test/a.png", 0), M.Manual{}, "https://x.test/a.png"))), "1")
    Unit <- E.must_eq("ready cache bound", Nat.show(M.ready_count(populate(12n, M.initial(True{})))), "8")
    Unit <- E.must("ready and queue bounds", M.bounded(populate(12n, M.initial(True{}))))
    Unit <- E.must_eq("old token evicted", U32.show(M.token(populate(12n, M.initial(True{})), M.Inline{1n}, "https://x.test/12.png")), "0")
    Unit <- E.must_eq("dropped line purges ready state", Nat.show(M.ready_count(M.maintain(M.complete(active(), client(), 1n, 1n, "https://x.test/a.png", 4), Cl.init("me", "s")))), "0")
    +query : Cl.Client = Feed.feed(Cl.init("me", "s"), ":alice!u@h PRIVMSG me :https://x.test/a.png")
    Unit <- E.must_eq("query rename retains stable-ID ready entry", Nat.show(M.ready_count(M.maintain(M.complete(active(), query, 1n, 1n, "https://x.test/a.png", 4), Feed.feed(query, ":alice!u@h NICK :bob")))), "1")
    Unit <- E.must_eq("historical IDs do not schedule", Nat.show(M.pending_count(M.observe(M.initial(True{}), client(), 1n, True{}))), "0")
    Unit <- E.must_eq("offline IDs do not schedule", Nat.show(M.pending_count(M.observe(M.initial(True{}), client(), 0n, False{}))), "0")
    Unit <- E.must_eq("fresh live ID schedules", Nat.show(M.pending_count(M.observe(M.initial(True{}), client(), 0n, True{}))), "1")
    Unit <- E.must_eq("LinkResult cannot recurse", Nat.show(M.pending_count(M.observe(M.initial(True{}), Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.LinkResult{}, "", "https://x/a.png", "", 1n}]), 0n, True{}))), "0")
    Unit <- E.must_eq("only chat event kinds allowed", Nat.show(M.pending_count(M.observe(M.initial(True{}), Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Notice{}, "", "https://x/a.png", "", 1n}, Cl.Line{Cl.Error{}, "", "https://x/a.png", "", 2n}, Cl.Line{Cl.System{}, "", "https://x/a.png", "", 3n}, Cl.Line{Cl.Action{}, "", "https://x/a.png", "", 4n}, Cl.Line{Cl.Self{}, "", "https://x/a.png", "", 5n}, Cl.Line{Cl.Highlight{}, "", "https://x/a.png", "", 6n}]), 0n, True{}))), "3")
    IO.print("media_policy=ok")
