# SPDX-License-Identifier: Apache-2.0
# Session/cards/fullscreen adapter goldens: bounded visible scheduling,
# worker ownership, stale-result policy, fullscreen re-validation and
# closure, endpoint isolation, and exact wire preservation. Positive
# controls schedule, fetch, and open; negative controls stay silent,
# release without storing, and close.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/frame.bend as Fr
import ../../src/bend/submit.bend as Sub
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V
import ../../src/bend/cards.bend as C
import ../../src/bend/session_cards.bend as SC
import ../../src/bend/cards_view.bend as CV
import ../../src/bend/cards_net.bend as CN

def page() -> String:
  "https://x.test/read"

def image() -> String:
  "https://x.test/a.png"

def exact_url() -> String:
  "https://x.test/r?a=b#frag"

def link_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see " ++ page(), "alice", 1n}])

def img_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see " ++ image(), "alice", 1n}])

def online() -> SC.AD:
  SC.wrap(Sess.session_online(Sess.session_with_client(link_client(), "#t")))

def online_img() -> SC.AD:
  SC.wrap(Sess.session_online(Sess.session_with_client(img_client(), "#t")))

def connecting() -> SC.AD:
  SC.wrap(Sess.session_with_client(link_client(), "#t"))

def demo() -> SC.AD:
  SC.wrap(Sess.session_demo(link_client(), "#t"))

def stopping() -> SC.AD:
  SC.wrap(Sess.session_set_net(Sess.session_with_client(link_client(), "#t"), Sess.Stopping{False{}}))

def offline_net() -> SC.AD:
  SC.wrap(Sess.session_set_net(Sess.session_with_client(link_client(), "#t"), Sess.Offline{}))

def submitted(pair: Cl.Client & List<&2, String>) -> Cl.Client:
  match pair:
    case (cl, _): cl

def channel(+name: String) -> Cl.Client:
  Feed.feed(Cl.init("me", "irc.example"), ":me!u@h JOIN " ++ name)

def set_named.found(found: Maybe<&2, Nat>, +cl: Cl.Client) -> Cl.Client:
  match found:
    case None{}: cl
    case Some{i}: Cl.set_active(cl, i)

def set_named(+cl: Cl.Client, name: String) -> Cl.Client:
  set_named.found(Cl.buf_find(cl, name), cl)

def muted_client() -> Cl.Client:
  set_named(Feed.feed(submitted(Sub.submit(channel("#room"), "/mute alice")), ":alice!u@h PRIVMSG #room :see " ++ page()), "#room")

def unmuted_client() -> Cl.Client:
  set_named(Feed.feed(submitted(Sub.submit(channel("#room"), "/mute alice")), ":bob!u@h PRIVMSG #room :see " ++ page()), "#room")

def ready_media() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, image(), 7}], M.Supported{}}

def retokened_media() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, image(), 9}], M.Supported{}}

def media_ad() -> SC.AD:
  SC.with_cards(Sess.session_set_media(Sess.session_online(Sess.session_with_client(img_client(), "#t")), ready_media()), C.initial(True{}), C.FullOff{})

def opened_ad() -> SC.AD:
  SC.open_full(media_ad(), M.Inline{1n}, image())

def job_of(pair: SC.AD & Maybe<&2, C.Request>) -> String:
  match pair:
    case (_, None{}): "none"
    case (_, Some{C.Request{_, url, generation, ticket}}): Nat.show(generation) ++ ":" ++ Nat.show(ticket) ++ ":" ++ url

def ad_of_job(pair: SC.AD & Maybe<&2, C.Request>) -> SC.AD:
  match pair:
    case (ad, _): ad

def started() -> SC.AD:
  ad_of_job(SC.take_job(SC.observe_visible(online())))

def outs_of(+cmd: Sess.NetCmd) -> String:
  match cmd:
    case Sess.Cont{+outs}: String.join(outs, "|")
    case _: "NOCONT"

def outs_ok(+cmd: Sess.NetCmd) -> Bool:
  match cmd:
    case Sess.Cont{+outs}: Sub.out_all_ok(outs)
    case _: False{}

def stepped_ad(trip: SC.AD & Sess.NetCmd & Bool) -> SC.AD:
  match trip:
    case (ad, _, _): ad

def stepped_cmd(trip: SC.AD & Sess.NetCmd & Bool) -> Sess.NetCmd:
  match trip:
    case (_, cmd, _): cmd

def stepped_halt(trip: SC.AD & Sess.NetCmd & Bool) -> String:
  match trip:
    case (_, _, halt): Bool.pick(String, halt, "halt", "go")

def chunk_ad(pair: SC.AD & List<&2, String>) -> SC.AD:
  match pair:
    case (ad, _): ad

def chunk_outs(pair: SC.AD & List<&2, String>) -> String:
  match pair:
    case (_, +outs): String.join(outs, "|")

def sess_chunk_outs(pair: Sess.Session & List<&2, String>) -> String:
  match pair:
    case (_, +outs): String.join(outs, "|")

def ops_shape(xs: List<&2, V.DrawOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.OpBox{x, y, w, h, _}, tail}:
      "box:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ ";" ++ ops_shape(tail)
    case Con{V.OpMedia{x, y, w, h, clip_y, clip_h, token}, tail}:
      "media:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(clip_y) ++ "," ++ U32.show(clip_h) ++ "," ++ U32.show(token) ++ ";" ++ ops_shape(tail)
    case Con{_, tail}: ops_shape(tail)

def overlay_of(+ad: SC.AD, +rows: U32, +cols: U32) -> String:
  match ad:
    case SC.AD{+st, _, +full}:
      ops_shape(CV.overlay_ops(full, Sess.session_media(st), Sess.session_cl(st), rows, cols))

def lines(+n: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p: Cl.Line{Cl.Msg{}, "", "see https://x.test/p" ++ Nat.show(n), "alice", n} <> lines(p)

def repeat(n: Nat, +s: String) -> String:
  match n:
    case 0n: ""
    case 1n+p: s ++ repeat(p, s)

def idle_keys() -> Sess.Keys:
  Sess.keys_of("", False{}, 0, 0, 0, 0, 0, 0, 0)

def enter_keys(+line: String) -> Sess.Keys:
  Sess.keys_of(line, True{}, 0, 0, 0, 0, 0, 0, 0)

def card_title(m: Maybe<&2, C.CardReady>) -> String:
  match m:
    case None{}: "missing"
    case Some{+r}: C.ready_title(r)

def session_of(+ad: SC.AD) -> Sess.Session:
  match ad:
    case SC.AD{+st, +cards, +full}: Sess.session_set_full(Sess.session_set_cards(st, cards), full)

def on_card_st(pair: Sess.Session & Bool) -> Sess.Session:
  match pair:
    case (st, _): st

def on_card_repaint(pair: Sess.Session & Bool) -> String:
  match pair:
    case (_, repaint): Bool.pick(String, repaint, "repaint", "quiet")

def stepped_sess_cmd(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.NetCmd:
  match trip:
    case (_, cmd, _): cmd

def stepped_sess_halt(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (_, _, halt): Bool.pick(String, halt, "halt", "go")

def args_shape(xs: List<&1, String>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, Nil{}}: h
    case Con{+h, t}: h ++ "|" ++ args_shape(t)

def trip_wire(trip: SC.AD & Sess.NetCmd & Bool) -> String:
  match trip:
    case (_, cmd, halt): outs_of(cmd) ++ ";" ++ Bool.pick(String, halt, "halt", "go")

def sess_trip_wire(trip: Sess.Session & Sess.NetCmd & Bool) -> String:
  match trip:
    case (_, cmd, halt): outs_of(cmd) ++ ";" ++ Bool.pick(String, halt, "halt", "go")

type ADBox is Data:
  ADBox{cell: List<&2, SC.AD>}

# Singleton-list box: AD embeds Session by value, so the live AD captures
# in one main flatten past the 247-word native continuation limit ("an
# arity over 247"). Boxing each fixture behind a recursive List cell keeps
# bind captures narrow (session_drafts_demo idiom); use sites unbox
# transiently. The Nil arm is unreachable by construction.
def box(+ad: SC.AD) -> ADBox:
  ADBox{ad <> Nil{}}

def unbox.cell(+cell: List<&2, SC.AD>) -> SC.AD:
  match cell:
    case Con{+ad, _}: ad
    case Nil{}: online()

def unbox(+b: ADBox) -> SC.AD:
  match b:
    case ADBox{+cell}: unbox.cell(cell)

type SBox is Data:
  SBox{cell: List<&2, Sess.Session>}

def sbox(+st: Sess.Session) -> SBox:
  SBox{st <> Nil{}}

def sunbox.cell(+cell: List<&2, Sess.Session>) -> Sess.Session:
  match cell:
    case Con{+st, _}: st
    case Nil{}: Sess.session_online(Sess.session_with_client(link_client(), "#t"))

def sunbox(+b: SBox) -> Sess.Session:
  match b:
    case SBox{+cell}: sunbox.cell(cell)

# The pinned native backend permits at most 247 flattened capture words
# per continuation (AGENTS.md). One main holding the live AD/Session
# fixtures breaches it ("an arity over 247"); each phase below holds only
# boxed fixtures, and main only sequences phases. Assertions are unchanged,
# in the same order.
def ph_schedule() -> IO(Unit):
  +ten = box(SC.wrap(Sess.session_online(Sess.session_with_client(Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, lines(10n)), "#t"))))
  +exact = box(SC.wrap(Sess.session_online(Sess.session_with_client(Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see " ++ exact_url(), "alice", 1n}]), "#t"))))
  do IO<Unit>:
    Unit <- E.must_eq("online schedules visible page", Nat.show(SC.ad_pending(SC.observe_visible(online()))), "1")
    Unit <- E.must_eq("demo schedules nothing", Nat.show(SC.ad_pending(SC.observe_visible(demo()))), "0")
    Unit <- E.must_eq("stopping schedules nothing", Nat.show(SC.ad_pending(SC.observe_visible(stopping()))), "0")
    Unit <- E.must_eq("connecting schedules like media", Nat.show(SC.ad_pending(SC.observe_visible(connecting()))), "1")
    Unit <- E.must_eq("offline-net schedules like media", Nat.show(SC.ad_pending(SC.observe_visible(offline_net()))), "1")
    Unit <- E.must_eq("disabled schedules nothing", Nat.show(SC.ad_pending(SC.observe_visible(SC.set_enabled(online(), False{})))), "0")
    Unit <- E.must_eq("muted author schedules nothing", Nat.show(SC.ad_pending(SC.observe_visible(SC.wrap(Sess.session_online(Sess.session_with_client(muted_client(), "#room")))))), "0")
    Unit <- E.must_eq("unmuted author admitted", Nat.show(SC.ad_pending(SC.observe_visible(SC.wrap(Sess.session_online(Sess.session_with_client(unmuted_client(), "#room")))))), "1")
    Unit <- E.must_eq("image URL never schedules", Nat.show(SC.ad_pending(SC.observe_visible(online_img()))), "0")
    Unit <- E.must_eq("plaintext never schedules", Nat.show(SC.ad_pending(SC.observe_visible(SC.wrap(Sess.session_online(Sess.session_with_client(Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see http://example.test/read", "alice", 1n}]), "#t")))))), "0")
    Unit <- E.must_eq("code stays opaque", Nat.show(SC.ad_pending(SC.observe_visible(SC.wrap(Sess.session_online(Sess.session_with_client(Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "`" ++ page() ++ "`", "alice", 1n}]), "#t")))))), "0")
    Unit <- E.must_eq("non-chat rows never schedule", Nat.show(SC.ad_pending(SC.observe_visible(SC.wrap(Sess.session_online(Sess.session_with_client(Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.System{}, "", page(), "", 1n}]), "#t")))))), "0")
    Unit <- E.must_eq("visible queue capped at eight", Nat.show(SC.ad_pending(SC.observe_visible(unbox(ten)))), "8")
    Unit <- E.must_eq("settle never schedules", Nat.show(SC.ad_pending(SC.settle(online()))), "0")
    Unit <- E.must_eq("exact URL text preserved", String.join(C.known_urls(SC.ad_cards(SC.observe_visible(unbox(exact))), C.CardInline{1n}), "|"), exact_url())
    return Unit{}

def ph_worker() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("worker starts exact job", job_of(SC.take_job(SC.observe_visible(online()))), "1:1:" ++ page())
    Unit <- E.must_eq("one worker only", job_of(SC.take_job(started())), "none")
    Unit <- E.must_eq("idle takes nothing", job_of(SC.take_job(online())), "none")
    Unit <- E.must("stopping forbids jobs", Bool.not(SC.job_allowed(stopping())))
    Unit <- E.must("online allows jobs", SC.job_allowed(online()))
    return Unit{}

def ph_admit() -> IO(Unit):
  +done = box(SC.complete(started(), 1n, 1n, page(), "Hello\nA description\n"))
  +gone = box(SC.with_cards(Sess.session_online(Sess.session_with_client(Cl.init("me", "s"), "#t")), SC.ad_cards(started()), SC.ad_full(started())))
  do IO<Unit>:
    Unit <- E.must("exact completion accepted", SC.accept_result(started(), 1n, 1n, page()))
    Unit <- E.must("wrong ticket rejected", Bool.not(SC.accept_result(started(), 1n, 2n, page())))
    Unit <- E.must("wrong generation rejected", Bool.not(SC.accept_result(started(), 2n, 1n, page())))
    Unit <- E.must("wrong URL rejected", Bool.not(SC.accept_result(started(), 1n, 1n, "https://x.test/other")))
    Unit <- E.must("stale attempt keeps worker", SC.accept_result(SC.complete(started(), 1n, 2n, page(), "T\nD\n"), 1n, 1n, page()))
    Unit <- E.must_eq("stale attempt stores nothing", Nat.show(SC.ad_ready(SC.complete(started(), 1n, 2n, page(), "T\nD\n"))), "0")
    Unit <- E.must_eq("accepted title stored", card_title(C.card(SC.ad_cards(unbox(done)), C.CardInline{1n}, page())), "Hello")
    Unit <- E.must_eq("accepted completion releases worker", job_of(SC.take_job(unbox(done))), "none")
    Unit <- E.must_eq("stored card never refetches", Nat.show(SC.ad_pending(SC.observe_visible(unbox(done)))), "0")
    Unit <- E.must("disabled completion rejected", Bool.not(SC.accept_result(SC.set_enabled(started(), False{}), 1n, 1n, page())))
    Unit <- E.must_eq("disabled completion stores nothing", Nat.show(SC.ad_ready(SC.complete(SC.set_enabled(started(), False{}), 1n, 1n, page(), "T\nD\n"))), "0")
    Unit <- E.must_eq("removed-source completion stores nothing", Nat.show(SC.ad_ready(SC.complete(unbox(gone), 1n, 1n, page(), "T\nD\n"))), "0")
    Unit <- E.must_eq("reset generation stores nothing", Nat.show(SC.ad_ready(SC.complete(SC.reset_endpoint(started()), 1n, 1n, page(), "T\nD\n"))), "0")
    Unit <- E.must_eq("reject stores nothing", Nat.show(SC.ad_ready(SC.reject(started(), 1n, 1n, page()))), "0")
    Unit <- E.must_eq("reject releases worker", job_of(SC.take_job(SC.reject(started(), 1n, 1n, page()))), "none")
    Unit <- E.must("wrong reject keeps worker", SC.accept_result(SC.reject(started(), 1n, 2n, page()), 1n, 1n, page()))
    return Unit{}

def ph_full() -> IO(Unit):
  +unsupported = box(SC.with_cards(Sess.session_set_media(SC.ad_session(media_ad()), M.set_supported(ready_media(), False{})), SC.ad_cards(media_ad()), SC.ad_full(media_ad())))
  do IO<Unit>:
    Unit <- E.must("open without token stays closed", Bool.not(SC.ad_open(SC.open_full(online_img(), M.Inline{1n}, image()))))
    Unit <- E.must("accepted token opens", SC.ad_open(opened_ad()))
    Unit <- E.must_eq("overlay carries token", U32.show(C.token_of(SC.ad_full(opened_ad()))), "7")
    Unit <- E.must("open without support stays closed", Bool.not(SC.ad_open(SC.open_full(unbox(unsupported), M.Inline{1n}, image()))))
    Unit <- E.must_eq("overlay covers body", overlay_of(opened_ad(), 24, 80), "box:0,1,62,23;media:1,2,60,21,0,21,7;")
    Unit <- E.must_eq("closed paints nothing", overlay_of(media_ad(), 24, 80), "")
    Unit <- E.must_eq("stale token paints nothing", overlay_of(SC.with_cards(Sess.session_set_media(SC.ad_session(media_ad()), retokened_media()), SC.ad_cards(opened_ad()), SC.ad_full(opened_ad())), 24, 80), "")
    Unit <- E.must_eq("unsupported paints nothing", overlay_of(SC.with_cards(Sess.session_set_media(SC.ad_session(media_ad()), M.set_supported(ready_media(), False{})), SC.ad_cards(opened_ad()), SC.ad_full(opened_ad())), 24, 80), "")
    Unit <- E.must_eq("zero token paints nothing", ops_shape(CV.overlay_ops(C.FullOn{M.Inline{1n}, image(), 0}, ready_media(), img_client(), 24, 80)), "")
    Unit <- E.must("explicit close returns to chat", Bool.not(SC.ad_open(SC.close_full(opened_ad()))))
    Unit <- E.must("media reset closes overlay", Bool.not(SC.ad_open(SC.settle(SC.with_cards(Sess.session_set_media(SC.ad_session(media_ad()), M.reset(ready_media())), SC.ad_cards(opened_ad()), SC.ad_full(opened_ad()))))))
    Unit <- E.must("media disable closes overlay", Bool.not(SC.ad_open(SC.settle(SC.with_cards(Sess.session_set_media(SC.ad_session(media_ad()), M.set_enabled(ready_media(), False{})), SC.ad_cards(opened_ad()), SC.ad_full(opened_ad()))))))
    Unit <- E.must("endpoint reset closes overlay", Bool.not(SC.ad_open(SC.reset_endpoint(opened_ad()))))
    Unit <- E.must("removed source closes overlay", Bool.not(SC.ad_open(SC.settle(SC.with_cards(Sess.session_set_client(SC.ad_session(opened_ad()), Cl.init("me", "s")), SC.ad_cards(opened_ad()), SC.ad_full(opened_ad()))))))
    Unit <- E.must("key-step settle closes stale overlay", Bool.not(SC.ad_open(stepped_ad(SC.step_keys(SC.with_cards(Sess.session_set_media(SC.ad_session(media_ad()), M.initial(True{})), SC.ad_cards(media_ad()), SC.ad_full(opened_ad())), idle_keys())))))
    return Unit{}

def ph_isolate() -> IO(Unit):
  +done = box(SC.complete(started(), 1n, 1n, page(), "Hello\nA description\n"))
  +other = box(SC.complete(started(), 1n, 1n, page(), "T\nD\n"))
  do IO<Unit>:
    Unit <- E.must_eq("endpoint reset drops queue", Nat.show(SC.ad_pending(SC.reset_endpoint(started()))), "0")
    Unit <- E.must_eq("endpoint reset drops ready", Nat.show(SC.ad_ready(SC.reset_endpoint(unbox(done)))), "0")
    Unit <- E.must_eq("scopes stay isolated", Nat.show(SC.ad_ready(SC.observe_visible(online()))), "0")
    Unit <- E.must_eq("completed scope keeps its card", Nat.show(SC.ad_ready(unbox(other))), "1")
    Unit <- E.must_eq("observe emits no diagnostics", Nat.show(Cl.log_seq_of(SC.ad_client(SC.observe_visible(online())))), Nat.show(Cl.log_seq_of(SC.ad_client(online()))))
    Unit <- E.must_eq("settle emits no diagnostics", Nat.show(Cl.log_seq_of(SC.ad_client(SC.settle(online())))), Nat.show(Cl.log_seq_of(SC.ad_client(online()))))
    Unit <- E.must_eq("complete emits no diagnostics", Nat.show(Cl.log_seq_of(SC.ad_client(unbox(done)))), Nat.show(Cl.log_seq_of(SC.ad_client(online()))))
    return Unit{}

def ph_wire() -> IO(Unit):
  +live = sbox(Sess.session_online(Sess.session_with_client(set_named(channel("#t"), "#t"), "#t")))
  +long = repeat(600n, "a")
  do IO<Unit>:
    Unit <- E.must_eq("key-step outs preserved", trip_wire(SC.step_keys(SC.wrap(sunbox(live)), enter_keys("hello"))), sess_trip_wire(Sess.step_keys(sunbox(live), enter_keys("hello"))))
    Unit <- E.must("key-step outs within cap", outs_ok(stepped_cmd(SC.step_keys(SC.wrap(sunbox(live)), enter_keys("hello")))))
    Unit <- E.must_eq("overlong rejection preserved", trip_wire(SC.step_keys(SC.wrap(sunbox(live)), enter_keys(long))), sess_trip_wire(Sess.step_keys(sunbox(live), enter_keys(long))))
    Unit <- E.must("overlong outs within cap", outs_ok(stepped_cmd(SC.step_keys(SC.wrap(sunbox(live)), enter_keys(long)))))
    Unit <- E.must_eq("enter outs preserved", trip_wire(SC.step_enter(SC.wrap(sunbox(live)), "hello")), sess_trip_wire(Sess.step_enter(sunbox(live), "hello")))
    Unit <- E.must_eq("chunk outs preserved", chunk_outs(SC.step_chunk(SC.wrap(sunbox(live)), Fr.string_to_octets("PING :abc\r\n"), 0)), sess_chunk_outs(Sess.step_on_chunk_ms(sunbox(live), Fr.string_to_octets("PING :abc\r\n"), 0)))
    Unit <- E.must("wire_ok on control hello", SC.wire_ok(Sess.session_online(Sess.session_with_client(Cl.init("me", "s"), "#t")), "hello"))
    Unit <- E.must("chunk_ok on ping", SC.chunk_ok(Sess.session_online(Sess.session_with_client(Cl.init("me", "s"), "#t")), Fr.string_to_octets("PING :abc\r\n"), 0))
    return Unit{}

def ph_proto() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("remote arg is exact URL", args_shape(CN.cards_args(page())), page())
    Unit <- E.must_eq("local path takes --local", args_shape(CN.cards_args("/tmp/page.html")), "--local|/tmp/page.html")
    Unit <- E.must_eq("failed worker yields empty", CN.cards_payload(Fail{(7, "boom")}), "")
    Unit <- E.must_eq("nonzero worker yields empty", CN.cards_payload(Done{(1, ("T\nD\n", ""))}), "")
    Unit <- E.must_eq("zero worker yields payload", CN.cards_payload(Done{(0, ("T\nD\n", ""))}), "T\nD\n")
    Unit <- E.must_eq("accepted completion repaints", on_card_repaint(CN.on_card_session(True{}, session_of(started()), 1n, 1n, page(), "T\nD\n")), "repaint")
    Unit <- E.must_eq("accepted on_card stores", Nat.show(C.ready_count(Sess.session_cards(on_card_st(CN.on_card_session(True{}, session_of(started()), 1n, 1n, page(), "T\nD\n"))))), "1")
    Unit <- E.must_eq("stale completion stays quiet", on_card_repaint(CN.on_card_session(False{}, session_of(started()), 1n, 1n, page(), "T\nD\n")), "quiet")
    Unit <- E.must_eq("stale on_card stores nothing", Nat.show(C.ready_count(Sess.session_cards(on_card_st(CN.on_card_session(False{}, session_of(started()), 1n, 1n, page(), "T\nD\n"))))), "0")
    return Unit{}

def ph_rows() -> IO(Unit):
  +known : C.State = C.State{True{}, 1n, 2n, None{}, Nil{}, [C.CardReady{C.CardInline{1n}, page(), "T", "D", ""}],}
  do IO<Unit>:
    Unit <- E.must_eq("known target paints rows", Nat.show(List.length(&2, V.BodyRow, V.card_rows_for(C.paint_entries(known), 1n, 80))), "2")
    Unit <- E.must_eq("unknown target paints nothing", Nat.show(List.length(&2, V.BodyRow, V.card_rows_for(C.paint_entries(known), 2n, 80))), "0")
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- ph_schedule()
    Unit <- ph_worker()
    Unit <- ph_admit()
    Unit <- ph_full()
    Unit <- ph_isolate()
    Unit <- ph_wire()
    Unit <- ph_proto()
    Unit <- ph_rows()
    IO.print("session_cards_demo=ok")
