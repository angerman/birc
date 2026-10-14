# SPDX-License-Identifier: Apache-2.0
import Base
import ./expect.bend as E
import ../../src/bend/media.bend as M
import ../../src/bend/view.bend as V
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as Sess
import ../../src/bend/split.bend as Sp
import ../../src/bend/frame.bend as Fr
import ../../src/bend/history.bend as H

def url() -> String:
  "https://x.test/a.png?q=exact#part"

def text() -> String:
  "alice: before " ++ url() ++ " after :eyes:漢z"

def buffer() -> Cl.Buffer:
  Cl.Buffer{"server", False{}, "", [Cl.Line{Cl.Msg{}, "12:00:00", text(), "alice", 1n}], Nil{}, Cl.ScrollAt{0n, 0n}}

def client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "12:00:00", text(), "alice", 1n}])

def pending() -> M.State:
  M.enqueue(M.initial(True{}), M.Inline{1n}, url())

def ready() -> M.State:
  M.State{True{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Inline{1n}, url(), 7}], M.Supported{}}

def spans_text(xs: List<&2, V.SpanOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{h, t}: V.span_text(h) ++ spans_text(t)

def sequence(xs: List<&2, V.BodyRow>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.BodyRow{_, _, _, _, _, spans, _}, tail}: spans_text(spans) ++ sequence(tail)
    case Con{V.BodyMedia{_, _, _, _}, tail}: "#" ++ sequence(tail)
    case Con{_, tail}: sequence(tail)

def image_count(xs: List<&2, V.BodyRow>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{V.BodyMedia{_, _, _, _}, tail}: Nat.add(1n, image_count(tail))
    case Con{_, tail}: image_count(tail)

def ops_shape(xs: List<&2, V.DrawOp>) -> String:
  match xs:
    case Nil{}: ""
    case Con{V.OpMedia{x, y, w, h, clip_y, clip_h, token}, tail}:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(clip_y) ++ "," ++ U32.show(clip_h) ++ "," ++ U32.show(token) ++ ";" ++ ops_shape(tail)
    case Con{_, tail}: ops_shape(tail)

def vm_shape(vm: V.ViewModel) -> String:
  match vm:
    case V.ViewModel{ops, _}: ops_shape(ops)

def first_line(lines: List<&2, Cl.Line>) -> Cl.Line:
  match lines:
    case Con{h, _}: h
    case Nil{}: Cl.Line{Cl.Error{}, "", "missing", "", 0n}

def st_of(trip: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match trip:
    case (st, _, _): st

def chunk_st(pair: Sess.Session & List<&2, String>) -> Sess.Session:
  match pair:
    case (st, _): st

def queue_full(+n: Nat, state: M.State) -> M.State:
  match n:
    case 0n: state
    case 1n+p: queue_full(p, M.enqueue(state, M.Inline{1n}, "https://x.test/" ++ Nat.show(n) ++ ".png"))

def first_text(lines: List<&2, Cl.Line>) -> String:
  match lines:
    case Nil{}: ""
    case Con{Cl.Line{_, _, text, _, _}, _}: text

def main() -> IO(Unit):
  do IO<Unit>:
    +line : Cl.Line = first_line(Cl.active_buf_lines(client()))
    Unit <- E.must_eq("legacy empty-media wrapper unchanged", Nat.show(image_count(V.wrap_line(line, 80, False{}))), "0")
    Unit <- E.must_eq("empty logical line keeps legacy row count", Nat.show(List.length(&2, V.BodyRow, V.wrap_line_media(Cl.Line{Cl.System{}, "", "", "", 1n}, 8, False{}, M.empty()))), Nat.show(List.length(&2, V.BodyRow, V.wrap_line(Cl.Line{Cl.System{}, "", "", "", 1n}, 8, False{}))))
    Unit <- E.must_eq("six inline rows", Nat.show(image_count(V.wrap_line_media(line, 80, False{}, ready()))), "6")
    Unit <- E.must_eq("image directly after URL", sequence(V.wrap_line_media(line, 80, False{}, ready())), "alice: before " ++ url() ++ "###### after 👀漢z")
    Unit <- E.must_eq("history stays raw", H.serialize_line("server", line), "server\tMSG\t12:00:00\t" ++ text() ++ "\n")
    Unit <- E.must_eq("pending and ready geometry match", Nat.show(V.rows_chars(V.wrap_line_media(line, 10, False{}, pending()))), Nat.show(V.rows_chars(V.wrap_line_media(line, 10, False{}, ready()))))
    Unit <- E.must_eq("virtual units width-independent", Nat.show(V.rows_chars(V.wrap_line_media(line, 1, False{}, ready()))), Nat.show(V.rows_chars(V.wrap_line_media(line, 80, False{}, ready()))))
    Unit <- E.must_eq("small pane partial clip", ops_shape(V.body_ops(V.Rect{0, 0, 12, 4}, List.take(&2, V.BodyRow, List.drop(&2, V.BodyRow, V.media_rows(7, 10), 2n), 2n))), "1,1,10,6,2,2,7;")
    Unit <- E.must_eq("one op for whole image", ops_shape(V.body_ops(V.Rect{0, 0, 42, 8}, V.media_rows(7, 40))), "1,1,40,6,0,6,7;")
    +paused : Cl.Buffer = V.scroll_buf_media(buffer(), 3n, 24, False{}, Nil{}, True{}, True{}, "s", 4n, 0n, ready())
    Unit <- E.must("paused resize bounded", Nat.is_le(List.length(&2, V.BodyRow, V.body_of.buf_media(paused, 3n, 50, False{}, Nil{}, True{}, True{}, "s", ready())), 3n))
    Unit <- E.must("eviction anchor bounded", Nat.is_le(List.length(&2, V.BodyRow, V.body_of.buf_media(paused, 3n, 24, False{}, Nil{}, True{}, True{}, "s", M.empty())), 3n))
    +only : Cl.Buffer = Cl.Buffer{"server", False{}, "", [Cl.Line{Cl.Msg{}, "", "alice: " ++ url(), "alice", 1n}], Nil{}, Cl.ScrollAt{0n, 0n}}
    +inside : Cl.Buffer = V.scroll_buf_media(only, 2n, 12, False{}, Nil{}, True{}, True{}, "s", 2n, 0n, ready())
    Unit <- E.must_eq("paused inside image", ops_shape(V.body_ops(V.Rect{0, 0, 14, 4}, V.body_of.buf_media(inside, 2n, 12, False{}, Nil{}, True{}, True{}, "s", ready()))), "1,1,12,6,2,2,7;")
    Unit <- E.must_eq("resize preserves virtual image position", ops_shape(V.body_ops(V.Rect{0, 0, 42, 4}, V.body_of.buf_media(inside, 2n, 40, False{}, Nil{}, True{}, True{}, "s", ready()))), "1,1,40,6,2,2,7;")
    +manual : Cl.Buffer = Cl.Buffer{"*preview*", False{}, url(), Nil{}, Nil{}, Cl.ScrollAt{0n, 0n}}
    +manual_media : M.State = M.State{False{}, 1n, 2n, None{}, Nil{}, [M.MediaReady{M.Manual{}, url(), 9}], M.Supported{}}
    +manual_paused : Cl.Buffer = V.scroll_buf_media(manual, 2n, 20, False{}, Nil{}, True{}, True{}, "s", 2n, 0n, manual_media)
    Unit <- E.must_eq("manual preview uses expanded navigation rows", ops_shape(V.body_ops(V.Rect{0, 0, 22, 4}, V.body_of.buf_media(manual_paused, 2n, 20, False{}, Nil{}, True{}, True{}, "s", manual_media))), "1,1,20,6,2,2,9;")
    Unit <- E.must("split media painted", Bool.not(String.is_empty(vm_shape(V.view_draft.state_typing_media(client(), 24, 80, "", "online", Nil{}, Sp.On{Sp.SideBySide{}, "server", "server", 0}, ready())))))
    +live : Sess.Session = Sess.session_online(Sess.session0("me", "s", ""))
    +fed : Sess.Session = chunk_st(Sess.step_on_chunk(live, Fr.string_to_octets(":alice!u@h PRIVMSG me :https://x.test/a.gif\r\n")))
    Unit <- E.must_eq("new live message schedules", Nat.show(M.pending_count(Sess.session_media(fed))), "1")
    Unit <- E.must_eq("demo never automatically fetches", Nat.show(M.pending_count(Sess.session_media(chunk_st(Sess.step_on_chunk(Sess.session_demo(Cl.init("me", "s"), ""), Fr.string_to_octets(":alice!u@h PRIVMSG me :https://x.test/a.gif\r\n")))))), "0")
    Unit <- E.must_eq("off clears queue", Nat.show(M.pending_count(Sess.session_media(st_of(Sess.step_enter(fed, "/images off"))))), "0")
    Unit <- E.must("on enables auto", M.enabled(Sess.session_media(st_of(Sess.step_enter(st_of(Sess.step_enter(fed, "/images off")), "/images on")))))
    Unit <- E.must_eq("endpoint change resets media", Nat.show(M.pending_count(Sess.session_media(st_of(Sess.step_enter(fed, "/connect other.example 6668"))))), "0")
    Unit <- E.must_eq("endpoint change advances generation", Nat.show(M.generation(Sess.session_media(st_of(Sess.step_enter(fed, "/connect other.example 6668"))))), "2")
    Unit <- E.must_eq("local manual intent offline", Nat.show(M.pending_count(Sess.session_media(st_of(Sess.step_enter(Sess.session_demo(Cl.init("me", "s"), ""), "/preview /tmp/example.jpg"))))), "1")
    Unit <- E.must_eq("remote manual intent offline", Nat.show(M.pending_count(Sess.session_media(st_of(Sess.step_enter(Sess.session_demo(Cl.init("me", "s"), ""), "/preview https://x.test/example.gif"))))), "1")
    +full : Sess.Session = Sess.session_set_media(Sess.session_demo(client(), ""), queue_full(8n, M.initial(True{})))
    +rejected : Sess.Session = st_of(Sess.step_enter(full, "/preview " ++ url()))
    Unit <- E.must_eq("explicit full-queue diagnostic", first_text(Cl.active_buf_lines(Sess.session_cl(rejected))), "image preview queue is full; try again")
    Unit <- E.must_eq("saturation stays bounded", Nat.show(M.pending_count(Sess.session_media(rejected))), "8")
    Unit <- E.must_eq("duplicate manual intent remains quiet", first_text(Cl.active_buf_lines(Sess.session_cl(st_of(Sess.step_enter(st_of(Sess.step_enter(Sess.session_demo(Cl.init("me", "s"), ""), "/preview " ++ url())), "/preview " ++ url()))))), "")
    IO.print("media_view=ok")
