# Input ownership: one watcher ACK and one fair, coalesced continuation.
import Base
import ./expect.bend as E
import ../../src/bend/net.bend as Net
import ../../src/bend/session.bend as Sess

def is_resize(g: Maybe<&1, Sess.UiMsg>) -> Bool:
  match g:
    case Some{Sess.Resize{}}: True{}
    case _: False{}

def is_continue(g: Maybe<&1, Sess.UiMsg>) -> Bool:
  match g:
    case Some{+m}: Net.is_continue(m)
    case _: False{}

def no_event(g: Maybe<&1, Sess.UiMsg>) -> Bool:
  match g:
    case None{}: True{}
    case _: False{}

def has_ack(g: Maybe<&1, Unit>) -> Bool:
  match g:
    case Some{_}: True{}
    case _: False{}

def fill(fuel: Nat, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.Resize{})
        fill(p, evt)

def drain(fuel: Nat, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        g : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
        Unit <- E.must("full event queue stays FIFO", is_resize(g))
        drain(p, evt)

def coalesce(fuel: Nat, +evt: Chan(Sess.UiMsg)) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        queued : Bool <- Net.more_schedule(True{}, False{}, True{}, evt)
        Unit <- E.must("more input keeps one continuation", queued)
        queued2 : Bool <- Net.more_schedule(True{}, False{}, False{}, evt)
        Unit <- E.must("another paint cannot forget a queued continuation", queued2)
        coalesce(p, evt)

def run() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("watcher key is not a continuation", Bool.not(Net.is_continue(Sess.UiKey{})))
    Unit <- E.must("synthetic input is a continuation", Net.is_continue(Sess.UiContinue{}))
    Unit <- E.must("idle needs no continuation", Bool.not(Net.more_pending(False{}, False{}, False{})))
    Unit <- E.must("a fresh paste needs a continuation", Net.more_pending(False{}, False{}, True{}))
    Unit <- E.must("an unrelated paint preserves a continuation", Net.more_pending(True{}, False{}, False{}))
    Unit <- E.must("an exhausted continuation clears pending", Bool.not(Net.more_pending(True{}, True{}, False{})))
    Unit <- E.must("a paste tail schedules another turn", Net.more_pending(True{}, True{}, True{}))
    +ack : Chan(Unit) <- Chan.new(Unit, 1)
    Unit <- Net.ack_key(True{}, ack)
    # (-) Two synthetic completions used to block on this full ACK queue.
    Unit <- Net.ack_key(False{}, ack)
    Unit <- Net.ack_key(False{}, ack)
    g : Maybe<&1, Unit> <- Chan.recv(Unit, ack)
    Unit <- E.must("the watcher receives its acknowledgement", has_ack(g))
    Unit <- Chan.close(Unit, ack)
    empty : Maybe<&1, Unit> <- Chan.recv(Unit, ack)
    Unit <- E.must("synthetic input does not acknowledge the watcher", Bool.not(has_ack(empty)))
    +evt : Chan(Sess.UiMsg) <- Chan.new(Sess.UiMsg, 64)
    Unit <- fill(64n, evt)
    # (-) Sending the 65th event on the UI itself used to deadlock here.
    queued : Bool <- Net.more_schedule(False{}, False{}, True{}, evt)
    Unit <- E.must("scheduling returns even with a full queue", queued)
    Unit <- coalesce(100n, evt)
    Unit <- drain(64n, evt)
    continuation : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    Unit <- E.must("only one continuation follows the full queue", is_continue(continuation))
    _ : Bool <- Chan.send(Sess.UiMsg, evt, Sess.Resize{})
    again : Bool <- Net.more_schedule(True{}, True{}, True{}, evt)
    Unit <- E.must("a paste tail stays pending", again)
    next : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    Unit <- E.must("existing events run before the paste tail", is_resize(next))
    last : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    Unit <- E.must("the paste tail gets its next turn", is_continue(last))
    done : Bool <- Net.more_schedule(True{}, True{}, False{}, evt)
    Unit <- E.must("drained input parks again", Bool.not(done))
    Unit <- Chan.close(Sess.UiMsg, evt)
    end : Maybe<&1, Sess.UiMsg> <- Chan.recv(Sess.UiMsg, evt)
    Unit <- E.must("coalescing leaves no extra work", no_event(end))
    IO.print("ui_input_queue=ok")

def main() -> IO(Unit):
  run()
