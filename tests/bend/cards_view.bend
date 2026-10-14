# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/cards.bend as C
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/submit.bend as Sub
import ../../src/bend/split.bend as Sp
import ../../src/bend/history.bend as H

def page() -> String:
  "https://x.test/read"

def full_card() -> C.CardReady:
  C.CardReady{C.CardInline{1n}, page(), "Hello", "A description", "https://x.test/i.png"}

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text(t)

def row_text(row: V.BodyRow) -> String:
  match row:
    case V.BodyRow{_, _, _, _, _, spans, _}: spans_text(spans)
    case _: "#"

def sequence(xs: List<&2, V.BodyRow>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, Nil{}}: row_text(h)
    case Con{h, t}: row_text(h) ++ "|" ++ sequence(t)

def ops_shape(xs: List<&2, V.DrawOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.OpBox{x, y, w, h}, tail}:
      "box:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ ";" ++ ops_shape(tail)
    case Con{V.OpMedia{x, y, w, h, clip_y, clip_h, token}, tail}:
      "media:" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(clip_y) ++ "," ++ U32.show(clip_h) ++ "," ++ U32.show(token) ++ ";" ++ ops_shape(tail)
    case Con{_, tail}: ops_shape(tail)

def cand_id(c: C.Candidate) -> Nat:
  match c:
    case C.Candidate{C.CardInline{id}, _}: id
    case _: 0n

def cand_url(c: C.Candidate) -> String:
  match c:
    case C.Candidate{_, +url}: url

def cand_shape(xs: List<&2, C.Candidate>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+h, Nil{}}: Nat.show(cand_id(h)) ++ ":" ++ cand_url(h)
    case Con{+h, t}: Nat.show(cand_id(h)) ++ ":" ++ cand_url(h) ++ "|" ++ cand_shape(t)

def lines(+n: Nat) -> List<&2, Cl.Line>:
  match n:
    case 0n: Nil{}
    case 1n+p: Cl.Line{Cl.Msg{}, "", "see https://x.test/p" ++ Nat.show(n), "alice", n} <> lines(p)

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

def ready_media() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, "https://x.test/a.png", 7}], M.Supported{}}

def card_client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see https://x.test/a.png", "alice", 1n}])

def retokened() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, "https://x.test/a.png", 9}], M.Supported{}}

def relocated() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, "https://x.test/other.png", 7}], M.Supported{}}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must_eq("full card paints three rows", Nat.show(List.length(&2, V.BodyRow, C.rows_for(full_card(), 80))), "3")
    Unit <- E.must_eq("card row text", sequence(C.rows_for(full_card(), 80)), "Hello|A description|image: https://x.test/i.png")
    Unit <- E.must_eq("empty title falls back to URL", sequence(C.rows_for(C.CardReady{C.CardInline{1n}, page(), "", "D", ""}, 80)), page() ++ "|D")
    Unit <- E.must_eq("empty card paints nothing", sequence(C.rows_for(C.CardReady{C.CardInline{1n}, page(), "", "", ""}, 80)), "")
    +long : String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    Unit <- E.must_eq("card rows capped at four", Nat.show(List.length(&2, V.BodyRow, C.rows_for(C.CardReady{C.CardInline{1n}, page(), "T", long, ""}, 10))), "4")
    +known : C.State = C.State{True{}, 1n, 2n, None{}, Nil{}, [C.CardReady{C.CardInline{1n}, page(), "T", "D", ""}],}
    Unit <- E.must_eq("unknown target paints nothing", Nat.show(List.length(&2, V.BodyRow, C.rows_for_target(known, C.CardInline{2n}, page(), 80))), "0")
    Unit <- E.must_eq("known target paints", Nat.show(List.length(&2, V.BodyRow, C.rows_for_target(known, C.CardInline{1n}, page(), 80))), "2")
    +src : Cl.Line = Cl.Line{Cl.Msg{}, "12:00:00", "see " ++ page(), "alice", 1n}
    Unit <- E.must_eq("history stays raw", H.serialize_line("server", src), "server\tMSG\t12:00:00\tsee " ++ page() ++ "\n")
    +single : Cl.Client = Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [src])
    Unit <- E.must_eq("visible single candidate", cand_shape(C.visible_candidates(single, 24, 80, Sp.Off{}, M.empty())), "1:" ++ page())
    Unit <- E.must_eq("visible single ignores image", cand_shape(C.visible_candidates(Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see https://x.test/a.png", "alice", 1n}]), 24, 80, Sp.Off{}, M.empty())), "")
    +ten : Cl.Client = Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, lines(10n))
    Unit <- E.must_eq("visible newest capped", Nat.show(List.length(&2, C.Candidate, C.visible_candidates(ten, 24, 80, Sp.Off{}, M.empty()))), "8")
    Unit <- E.must_eq("visible newest first", cand_shape(C.visible_candidates(ten, 24, 80, Sp.Off{}, M.empty())), "10:https://x.test/p10|9:https://x.test/p9|8:https://x.test/p8|7:https://x.test/p7|6:https://x.test/p6|5:https://x.test/p5|4:https://x.test/p4|3:https://x.test/p3")
    +synthetic : Cl.Client = Cl.Client{"me", "s", [Cl.Buffer{"*settings*", False{}, "", [src], Nil{}, Cl.ScrollAt{0n, 0n}}], 0n, "", Cl.settings0(), Cl.AuthIdle{}, 1n}
    Unit <- E.must_eq("synthetic buffers excluded", cand_shape(C.visible_candidates(synthetic, 24, 80, Sp.Off{}, M.empty())), "")
    +muted : Cl.Client = submitted(Sub.submit(channel("#room"), "/mute alice"))
    +muted_alice : Cl.Client = set_named(Feed.feed(muted, ":alice!u@h PRIVMSG #room :see " ++ page()), "#room")
    Unit <- E.must_eq("muted author excluded", cand_shape(C.visible_candidates(muted_alice, 24, 80, Sp.Off{}, M.empty())), "")
    +muted_bob : Cl.Client = set_named(Feed.feed(muted, ":bob!u@h PRIVMSG #room :see " ++ page()), "#room")
    Unit <- E.must_eq("unmuted author admitted", Nat.show(List.length(&2, C.Candidate, C.visible_candidates(muted_bob, 24, 80, Sp.Off{}, M.empty()))), "1")
    Unit <- E.must("unmuted candidate keeps exact URL", String.contains(cand_shape(C.visible_candidates(muted_bob, 24, 80, Sp.Off{}, M.empty())), page()))
    +split : Cl.Client = Feed.feed(Feed.feed(channel("#a"), ":me!u@h JOIN #b"), ":alice!u@h PRIVMSG #a :see https://x.test/pa")
    +split_both : Cl.Client = Feed.feed(split, ":bob!u@h PRIVMSG #b :see https://x.test/pb")
    Unit <- E.must_eq("split panes admit both", Nat.show(List.length(&2, C.Candidate, C.visible_candidates(split_both, 24, 80, Sp.On{Sp.SideBySide{}, "#a", "#b", 0}, M.empty()))), "2")
    +nonchat : Cl.Client = Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.LinkResult{}, "", page(), "", 1n}, Cl.Line{Cl.Notice{}, "", page(), "", 2n}, Cl.Line{Cl.Error{}, "", page(), "", 3n}, Cl.Line{Cl.System{}, "", page(), "", 4n}])
    Unit <- E.must_eq("non-chat rows never schedule", cand_shape(C.visible_candidates(nonchat, 24, 80, Sp.Off{}, M.empty())), "")
    +mixed : Cl.Client = Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Notice{}, "", page(), "", 1n}, Cl.Line{Cl.Error{}, "", page(), "", 2n}, Cl.Line{Cl.System{}, "", page(), "", 3n}, Cl.Line{Cl.Action{}, "", page(), "", 4n}, Cl.Line{Cl.Self{}, "", page(), "", 5n}, Cl.Line{Cl.Highlight{}, "", page(), "", 6n}])
    Unit <- E.must_eq("only chat rows schedule", cand_shape(C.visible_candidates(mixed, 24, 80, Sp.Off{}, M.empty())), "6:" ++ page() ++ "|5:" ++ page() ++ "|4:" ++ page())
    Unit <- E.must_eq("plaintext rows never schedule", cand_shape(C.visible_candidates(Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", "see http://example.test/read", "alice", 1n}]), 24, 80, Sp.Off{}, M.empty())), "")
    Unit <- E.must_eq("closed paints nothing", ops_shape(C.fullscreen_ops(24, 80, C.FullOff{})), "")
    Unit <- E.must_eq("zero token paints nothing", ops_shape(C.fullscreen_ops(24, 80, C.FullOn{M.Inline{1n}, "https://x.test/a.png", 0})), "")
    Unit <- E.must("unsupported terminal stays closed", Bool.not(C.is_open(C.open(M.set_supported(ready_media(), False{}), M.Inline{1n}, "https://x.test/a.png"))))
    Unit <- E.must("missing token stays closed", Bool.not(C.is_open(C.open(M.initial(True{}), M.Inline{1n}, "https://x.test/a.png"))))
    +full : C.Fullscreen = C.open(ready_media(), M.Inline{1n}, "https://x.test/a.png")
    Unit <- E.must("accepted token opens", C.is_open(full))
    Unit <- E.must_eq("overlay carries token", U32.show(C.token_of(full)), "7")
    Unit <- E.must_eq("closed token is zero", U32.show(C.token_of(C.FullOff{})), "0")
    Unit <- E.must_eq("overlay covers body", ops_shape(C.fullscreen_ops(24, 80, full)), "box:0,1,62,21;media:1,2,60,19,0,19,7;")
    Unit <- E.must_eq("tiny overlay covers body", ops_shape(C.fullscreen_ops(5, 10, full)), "box:0,1,5,2;media:1,1,3,2,0,2,7;")
    Unit <- E.must("close returns to chat", Bool.not(C.is_open(C.close(full))))
    Unit <- E.must("retained token stays open", C.is_open(C.maintain_full(full, ready_media(), card_client())))
    Unit <- E.must_eq("retained token paints", ops_shape(C.fullscreen_ops(24, 80, C.maintain_full(full, ready_media(), card_client()))), "box:0,1,62,21;media:1,2,60,19,0,19,7;")
    Unit <- E.must("unsupported terminal closes", Bool.not(C.is_open(C.maintain_full(full, M.set_supported(ready_media(), False{}), card_client()))))
    Unit <- E.must("reset closes", Bool.not(C.is_open(C.maintain_full(full, M.reset(ready_media()), card_client()))))
    Unit <- E.must("disable closes", Bool.not(C.is_open(C.maintain_full(full, M.set_enabled(ready_media(), False{}), card_client()))))
    Unit <- E.must("eviction closes", Bool.not(C.is_open(C.maintain_full(full, M.initial(True{}), card_client()))))
    Unit <- E.must("retoken closes", Bool.not(C.is_open(C.maintain_full(full, retokened(), card_client()))))
    Unit <- E.must("relocated source closes", Bool.not(C.is_open(C.maintain_full(full, relocated(), card_client()))))
    Unit <- E.must("removed source closes", Bool.not(C.is_open(C.maintain_full(full, ready_media(), Cl.init("me", "s")))))
    Unit <- E.must("closed stays closed", Bool.not(C.is_open(C.maintain_full(C.FullOff{}, ready_media(), card_client()))))
    Unit <- E.must_eq("cards need no image protocol", Nat.show(C.pending_count(C.enqueue(C.initial(True{}), C.CardInline{1n}, page()))), "1")
    Unit <- E.must_eq("card opt-out is silent", Nat.show(C.pending_count(C.enqueue(C.initial(False{}), C.CardInline{1n}, page()))), "0")
    IO.print("cards_view=ok")
