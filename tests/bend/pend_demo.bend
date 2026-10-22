# SPDX-License-Identifier: Apache-2.0
# Optimistic-send slice: Enter records a pending echo, the themed paint
# shows it dimmed, the wire echo confirms it (FIFO or label), and
# timeout/failure reaps every body (oldest first) into an empty composer
# or the server buffer when the composer is busy.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client.bend as Feed
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/session.bend as Sess
import ../../src/bend/cap_notify.bend as Cap
import ../../src/bend/theme.bend as Theme
import ../../src/bend/view.bend as V

def chan0() -> Cl.Client:
  Feed.feed(Cl.init("me", "s"), ":me!me@localhost JOIN #t")

def echo_reg() -> Cap.Reg:
  Cap.Reg{Cap.caps_apply(Cap.caps0(), Cap.CapEvent{Cap.CapAck{}, "echo-message" <> Nil{}}), Cap.out0()}

def echo_session() -> Sess.Session:
  Sess.session_set_reg(Sess.session_demo(chan0(), "#t"), echo_reg())

def trip_st(t: Sess.Session & Sess.NetCmd & Bool) -> Sess.Session:
  match t:
    case (+st, _, _): st

def sent() -> Sess.Session:
  trip_st(Sess.step_keys(echo_session(), Sess.keys_of("hello", True{}, 0, 0, 0, 0, 0, 0, 0)))

def sent2() -> Sess.Session:
  trip_st(Sess.step_keys(sent(), Sess.keys_of("two", True{}, 0, 0, 0, 0, 0, 0, 0)))

def pend_buf(+p: Cl.PendSend) -> String:
  match p:
    case Cl.PendSend{+buf, _, _, _, _, _, _, _, _}: buf

def pend_body(+p: Cl.PendSend) -> String:
  match p:
    case Cl.PendSend{_, _, _, _, +body, _, _, _, _}: body

def first_pend(+ps: List<&2, Cl.PendSend>) -> Maybe<&2, Cl.PendSend>:
  match ps:
    case Nil{}: None{}
    case Con{+h, _}: Some{h}

def first_buf(got: Maybe<&2, Cl.PendSend>) -> String:
  match got:
    case None{}: ""
    case Some{+p}: pend_buf(p)

def first_body(got: Maybe<&2, Cl.PendSend>) -> String:
  match got:
    case None{}: ""
    case Some{+p}: pend_body(p)

# Enter records one pending echo routed to the active buffer.
def record_ok() -> Bool:
  +ps = Sess.session_pends(sent())
  Nat.is_eq(Sess.session_pend_count(sent()), 1n)
    && String.eq(first_buf(first_pend(ps)), "#t")
    && String.eq(first_body(first_pend(ps)), "hello")

# The buffer holds no local echo; the row exists only as pending paint.
def no_echo_ok() -> Bool:
  String.eq(CL.buf_texts(Sess.session_cl(sent()), 1n), "-> me joined #t|")

def ops_of(vm: V.ViewModel) -> List<&2, V.DrawOp>:
  match vm:
    case V.ViewModel{ops, _}: ops

def span_text(+sp: V.SpanOp) -> String:
  match sp:
    case V.Spn{_, +text}: text
    case V.Lnk{_, +text}: text
    case V.Col{_, _, +text}: text

def spans_text.go(+xs: List<&2, V.SpanOp>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Con{+h, t}: spans_text.go(t, acc ++ span_text(h))

# Body rows paint as OpLine with the kind fg; OpText covers chrome.
type LineHit is Data:
  LineMiss{}
  LineHit{fg: U32, text: String}

def opline_text(+op: V.DrawOp) -> LineHit:
  match op:
    case V.OpLine{_, _, _, +fg, +spans}: LineHit{fg, spans_text.go(spans, "")}
    case _: LineMiss{}

def hello_fg.pick(hit: Bool, +fg: U32, +rec: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{fg}
    case False{}: rec

def hello_fg.line(got: LineHit, +rec: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match got:
    case LineMiss{}: rec
    case LineHit{+fg, +text}: hello_fg.pick(String.contains(text, "hello"), fg, rec)

def hello_fg.go(ops: List<&2, V.DrawOp>) -> Maybe<&2, U32>:
  match ops:
    case Nil{}: None{}
    case Con{+h, t}: hello_fg.line(opline_text(h), hello_fg.go(t))

def fg_is(got: Maybe<&2, U32>, +want: U32) -> Bool:
  match got:
    case None{}: False{}
    case Some{+fg}: U32.is_eq(fg, want)

# The pending row paints dimmed, never in the plain self color.
def overlay_ok() -> Bool:
  +st = sent()
  +fg = hello_fg.go(ops_of(Sess.session_paint_vm(st)))
  +th = Sess.session_theme(st)
  fg_is(fg, Theme.kind_fg(th, Cl.Pending{Cl.Msg{}})) && Bool.not(fg_is(fg, Theme.kind_fg(th, Cl.Msg{})))

# The status label carries the sending count only while nonzero.
def label_ok() -> Bool:
  String.eq(Sess.net_label_lag_pend(Sess.Demo{}, 0, 1n), "demo · 1 sending")
    && String.eq(Sess.net_label_lag_pend(Sess.Demo{}, 0, 0n), "demo")

def confirmed_st(pair: Sess.Session & List<&2, String>) -> Sess.Session:
  match pair:
    case (+st, _): st

def confirmed() -> Sess.Session:
  confirmed_st(Sess.step_on_framed_ms(sent(), (":me!me@localhost PRIVMSG #t :hello" <> Nil{}, Nil{}, False{}), Nil{}, 0))

# The wire echo confirms the pending entry and renders the single line.
def confirm_ok() -> Bool:
  Nat.is_eq(Sess.session_pend_count(confirmed()), 0n)
    && String.eq(CL.buf_texts(Sess.session_cl(confirmed()), 1n), "-> me joined #t|<me> hello|")

def hello_count.hit(hit: Bool, +rec: Nat) -> Nat:
  match hit:
    case True{}: 1n+rec
    case False{}: rec

def hello_count.line(got: LineHit, +rec: Nat) -> Nat:
  match got:
    case LineMiss{}: rec
    case LineHit{_, +text}: hello_count.hit(String.contains(text, "hello"), rec)

def hello_count.go(ops: List<&2, V.DrawOp>) -> Nat:
  match ops:
    case Nil{}: 0n
    case Con{+h, t}: hello_count.line(opline_text(h), hello_count.go(t))

# After confirm the overlay is gone: exactly one plain hello remains.
def once_ok() -> Bool:
  +st = confirmed()
  +fg = hello_fg.go(ops_of(Sess.session_paint_vm(st)))
  Nat.is_eq(hello_count.go(ops_of(Sess.session_paint_vm(st))), 1n)
    && fg_is(fg, Theme.kind_fg(Sess.session_theme(st), Cl.Msg{}))

# FIFO confirm drops the oldest match and keeps the later send.
def fifo_ok() -> Bool:
  +ps = Sess.session_pends(sent2())
  +rest = Sess.pend_confirm_lines(Cl.dflt_cm(), ps, "me", ":me!me@localhost PRIVMSG #t :hello" <> Nil{})
  Nat.is_eq(List.length(&2, Cl.PendSend, ps), 2n)
    && Nat.is_eq(List.length(&2, Cl.PendSend, rest), 1n)
    && String.eq(first_body(first_pend(rest)), "two")

def expire_st(pair: Sess.Session & Bool) -> Sess.Session:
  match pair:
    case (+st, _): st

def expire_n(n: Nat, +st: Sess.Session) -> Sess.Session:
  match n:
    case 0n: st
    case 1n+p: expire_n(p, expire_st(Sess.session_expire_typing(st, 0)))

def timed_out() -> Sess.Session:
  expire_n(31n, sent())

# Past PEND_TICKS the entry reaps and its text returns to the draft.
def timeout_ok() -> Bool:
  Nat.is_eq(Sess.session_pend_count(timed_out()), 0n)
    && String.eq(Sess.session_draft(timed_out()), "hello")

# Connection failure clears pending rows and restores the draft too.
def fail_ok() -> Bool:
  +st = Sess.session_fail(sent(), "boom")
  Nat.is_eq(Sess.session_pend_count(st), 0n)
    && String.eq(Sess.session_draft(st), "hello")

def enter(+st: Sess.Session, +text: String) -> Sess.Session:
  trip_st(Sess.step_keys(st, Sess.keys_of(text, True{}, 0, 0, 0, 0, 0, 0, 0)))

def sent_one_two() -> Sess.Session:
  enter(enter(echo_session(), "one"), "two")

def server_text(+st: Sess.Session) -> String:
  CL.buf_texts(Sess.session_cl(st), 0n)

# Both unconfirmed bodies time out into an empty composer, oldest first.
def timeout_both_ok() -> Bool:
  +st = expire_n(31n, sent_one_two())
  Nat.is_eq(Sess.session_pend_count(st), 0n)
    && String.eq(Sess.session_draft(st), "one\ntwo")
    && Bool.not(String.contains(server_text(st), "one"))

# A busy composer stays; the reaped bodies are logged on the server buffer.
def timeout_busy_ok() -> Bool:
  +st = expire_n(31n, Sess.session_set_draft(sent_one_two(), "typing"))
  Nat.is_eq(Sess.session_pend_count(st), 0n)
    && String.eq(Sess.session_draft(st), "typing")
    && String.eq(server_text(st), "one|two|")

def send_cap.bump(+label: Nat) -> Nat:
  1n+label

def send_cap(n: Nat, +label: Nat, +st: Sess.Session) -> Sess.Session:
  match n:
    case 0n: st
    case 1n+p: send_cap(p, send_cap.bump(label), enter(st, "b" ++ Nat.show(label)))

# One past PEND_MAX (the 33rd send) evicts the oldest body into the empty composer.
def cap_evict_ok() -> Bool:
  +st = send_cap(1n+Cl.PEND_MAX(), 1n, echo_session())
  Nat.is_eq(Sess.session_pend_count(st), Cl.PEND_MAX())
    && String.eq(Sess.session_draft(st), "b1")
    && String.eq(first_body(first_pend(Sess.session_pends(st))), "b2")
    && Bool.not(String.contains(server_text(st), "b1"))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("record", record_ok())
    Unit <- E.must("no_local_echo", no_echo_ok())
    Unit <- E.must("overlay_dim", overlay_ok())
    Unit <- E.must("status_label", label_ok())
    Unit <- E.must("confirm", confirm_ok())
    Unit <- E.must("renders_once", once_ok())
    Unit <- E.must("fifo", fifo_ok())
    Unit <- E.must("timeout_reaps", timeout_ok())
    Unit <- E.must("fail_restores", fail_ok())
    Unit <- E.must("timeout_restores_both", timeout_both_ok())
    Unit <- E.must("timeout_logs_busy", timeout_busy_ok())
    Unit <- E.must("cap_shows_oldest", cap_evict_ok())
    IO.print("pend_demo=ok")
