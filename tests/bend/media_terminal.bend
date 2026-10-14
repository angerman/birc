# SPDX-License-Identifier: Apache-2.0
# Unsupported terminals must not make image requests or replace ordinary URLs.
import Base
import ./expect.bend as E
import ./media_branches.bend as Rows
import ../../src/bend/media.bend as M
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/session.bend as S
import ../../src/bend/frame.bend as Fr
import ../../src/bend/view.bend as V
import ../../src/bend/history.bend as H
import ../../src/bend/preferences.bend as P
import ../../src/bend/preferences_live.bend as Pref

def url() -> String:
  "https://offline.invalid/image.png?private=synthetic#exact"

def unsupported(on: Bool) -> M.State:
  M.set_supported(M.initial(on), False{})

def queued(supported: Bool) -> M.State:
  M.enqueue(M.set_supported(M.initial(True{}), supported), M.Inline{1n}, url())

def state_of(pair: M.State & Maybe<&2, M.Request>) -> M.State:
  match pair:
    case (state, _): state

def has_job(pair: M.State & Maybe<&2, M.Request>) -> Bool:
  match pair:
    case (_, Some{_}): True{}
    case _: False{}

def has_active(state: M.State) -> Bool:
  match state:
    case M.State{_, _, _, Some{_}, _, _, _}: True{}
    case _: False{}

def quiet(+state: M.State) -> Bool:
  Nat.is_eq(M.pending_count(state), 0n) && Nat.is_eq(M.ready_count(state), 0n)
    && List.is_empty(&2, U32, M.retained_tokens(state))
    && List.is_empty(&2, String, M.known_urls(state, M.Inline{1n}))
    && List.is_empty(&2, String, M.known_urls(state, M.Manual{}))
    && Bool.not(has_job(M.take_job(state)))

def client() -> Cl.Client:
  Cl.buf_set_lines_at(Cl.init("me", "s"), 0n, [Cl.Line{Cl.Msg{}, "", url(), "alice", 1n}])

def lines.found(found: Maybe<&2, Nat>, cl: Cl.Client) -> List<&2, Cl.Line>:
  match found:
    case None{}: Nil{}
    case Some{i}: Cl.active_buf_lines.on(Cl.nth_buf(Cl.client_bufs(cl), i))

def lines(+cl: Cl.Client, name: String) -> List<&2, Cl.Line>:
  lines.found(Cl.buf_find(cl, name), cl)

def notices(xs: List<&2, Cl.Line>) -> Nat:
  match xs:
    case Nil{}: 0n
    case Con{Cl.Line{_, _, text, _, _}, tail}:
      (Bool.pick(Nat, String.eq(text, M.unsupported_text()), 1n, 0n) + notices(tail) : Nat)

def notice_count(st: S.Session) -> Nat:
  notices(lines(S.session_cl(st), "*log*"))

def notice_kind(xs: List<&2, Cl.Line>) -> Bool:
  match xs:
    case Con{Cl.Line{Cl.System{}, _, text, author, id}, Nil{}}:
      String.eq(text, M.unsupported_text()) && String.is_empty(author) && Nat.is_gt(id, 0n)
    case _: False{}

def pair_state(pair: S.Session & List<&2, String>) -> S.Session:
  match pair:
    case (st, _): st

def pair_wire(pair: S.Session & List<&2, String>) -> String:
  match pair:
    case (_, outs): String.join(outs, "|")

def entered(trip: S.Session & S.NetCmd & Bool) -> S.Session:
  match trip:
    case (st, _, _): st

def initial(supported: Bool, on: Bool) -> S.Session:
  S.session_set_media(S.session_online(S.session0("me", "s", "")), M.set_supported(M.initial(on), supported))

def chunk(st: S.Session) -> S.Session & List<&2, String>:
  S.step_on_chunk(st, Fr.string_to_octets(":alice!u@h PRIVMSG me :before " ++ url() ++ " after\r\nPING :unchanged\r\n"))

def automatic(supported: Bool, on: Bool) -> S.Session:
  pair_state(chunk(initial(supported, on)))

def repeated(st: S.Session) -> S.Session:
  pair_state(chunk(entered(S.step_enter(entered(S.step_enter(st, "/images off")), "/images on"))))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("supported image request starts", has_job(M.take_job(queued(True{}))))
    Unit <- E.must("unsupported has no queue, worker, ready token, or image URL", quiet(queued(False{})))
    Unit <- E.must("unsupported intent reports without changing enabled", M.reported(queued(False{})) && M.enabled(queued(False{})))
    Unit <- E.must("unsupported installation is lazy", Bool.not(M.reported(unsupported(True{}))))
    Unit <- E.must("automatic off is silent", quiet(M.enqueue(unsupported(False{}), M.Inline{1n}, url())) && Bool.not(M.reported(M.enqueue(unsupported(False{}), M.Inline{1n}, url()))))
    Unit <- E.must("malformed automatic source is silent", Bool.not(M.reported(M.enqueue(unsupported(True{}), M.Inline{1n}, "ftp://offline.invalid/a.png"))))
    Unit <- E.must("empty manual intent is silent", Bool.not(M.reported(M.enqueue(unsupported(True{}), M.Manual{}, ""))))
    Unit <- E.must("accepted manual while auto off reports but never requests", quiet(M.enqueue(unsupported(False{}), M.Manual{}, "/tmp/synthetic.png")) && M.reported(M.enqueue(unsupported(False{}), M.Manual{}, "/tmp/synthetic.png")))
    +reported : M.State = M.enqueue(unsupported(True{}), M.Inline{1n}, url())
    Unit <- E.must("reset, disable, enable and maintain retain report", M.reported(M.maintain(M.set_enabled(M.set_enabled(M.reset(reported), False{}), True{}), client())))
    Unit <- E.must("repeat remains quiet", quiet(M.enqueue(reported, M.Inline{1n}, url())) && M.reported(M.enqueue(reported, M.Inline{1n}, url())))
    +active : M.State = state_of(M.take_job(queued(True{})))
    +blocked : M.State = M.enqueue(M.set_supported(active, False{}), M.Inline{1n}, url())
    Unit <- E.must("support removal retains only physical worker ownership", has_active(blocked) && quiet(blocked))
    Unit <- E.must("support removal rejects old completion", Bool.not(M.accept(blocked, client(), 1n, 1n, url())))
    Unit <- E.must("support re-enable cannot revive old generation", Bool.not(M.accept(M.set_supported(blocked, True{}), client(), 1n, 1n, url())))
    +drained : M.State = M.complete(blocked, client(), 1n, 1n, url(), 7)
    Unit <- E.must("late completion releases worker without token or report loss", Bool.not(has_active(drained)) && quiet(drained) && M.reported(drained))
    +cached : M.State = M.State{True{}, 1n, 3n, Some{M.Request{M.Inline{1n}, url(), 1n, 1n}}, [M.Request{M.Inline{1n}, "https://offline.invalid/b.png", 1n, 2n}], [M.MediaReady{M.Inline{1n}, url(), 7}], M.Supported{}}
    Unit <- E.must("support removal clears preexisting pending and ready ownership", quiet(M.set_supported(cached, False{})) && has_active(M.set_supported(cached, False{})))
    +before : S.Session = initial(False{}, True{})
    +after : S.Session = pair_state(chunk(before))
    +ordinary : S.Session = automatic(True{}, False{})
    Unit <- E.must_eq("one lazy fixed explanation", Nat.show(notice_count(after)), "1")
    Unit <- E.must("explanation is System with fresh ID and no author", notice_kind(lines(S.session_cl(after), "*log*")))
    Unit <- E.must_eq("explanation preserves focus", Cl.active_buf_name(S.session_cl(after)), Cl.active_buf_name(S.session_cl(ordinary)))
    Unit <- E.must("unsupported live view uses complete ordinary URL rows", Rows.rows_eq(V.wrap_lines_media(lines(S.session_cl(after), "alice"), 80, False{}, S.session_media(after)), V.wrap_lines(lines(S.session_cl(ordinary), "alice"), 80, False{})))
    Unit <- E.must_eq("live protocol response stays original", pair_wire(chunk(before)), pair_wire(chunk(initial(True{}, False{}))))
    Unit <- E.must("fixed explanation never enters chat history", Bool.not(String.contains(H.extract_new_history(S.session_cl(before), S.session_cl(after)), M.unsupported_text())))
    Unit <- E.must("original URL still enters chat history", String.contains(H.extract_new_history(S.session_cl(before), S.session_cl(after)), url()))
    Unit <- E.must_eq("repeat and user toggles do not repeat explanation", Nat.show(notice_count(repeated(after))), "1")
    Unit <- E.must_eq("automatic off has no explanation", Nat.show(notice_count(automatic(False{}, False{}))), "0")
    Unit <- E.must_eq("invalid manual command keeps ordinary validation without explanation", Nat.show(notice_count(entered(S.step_enter(before, "/preview")))), "0")
    Unit <- E.must("invalid manual does not mark terminal reported", Bool.not(M.reported(S.session_media(entered(S.step_enter(before, "/preview file://"))))))
    +manual : S.Session = entered(S.step_enter(initial(False{}, False{}), "/preview /tmp/synthetic.png"))
    Unit <- E.must("accepted manual never requests", quiet(S.session_media(manual)))
    Unit <- E.must_eq("accepted manual while automatic off explains once", Nat.show(notice_count(manual)), "1")
    +reconnected : S.Session = S.session_reconnected(entered(S.step_enter(after, "/reconnect")), "12:00:00")
    Unit <- E.must("same-endpoint reconnect retains unsupported report", M.reported(S.session_media(reconnected)) && Bool.not(M.supported(S.session_media(reconnected))))
    Unit <- E.must_eq("post-reconnect image does not repeat explanation", Nat.show(notice_count(pair_state(chunk(reconnected)))), "1")
    +switched : S.Session = entered(S.step_enter(after, "/connect other.example 6697"))
    Unit <- E.must("endpoint change retains app-session report", M.reported(S.session_media(switched)))
    +loaded : S.Session = Pref.apply(Some{P.capture(S.session_cl(after), False{}, Nil{})}, after)
    Unit <- E.must("saved images off keeps unsupported report", Bool.not(M.enabled(S.session_media(loaded))) && M.reported(S.session_media(loaded)))
    Unit <- E.must("saved images on cannot enable unsupported terminal requests", quiet(S.session_media(Pref.apply(Some{P.capture(S.session_cl(after), True{}, Nil{})}, loaded))))
    Unit <- E.must("persisted user images preference stays on", P.images(Pref.capture(after, 1)))
    IO.print("media_terminal=ok")
