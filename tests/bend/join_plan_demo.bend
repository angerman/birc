# SPDX-License-Identifier: Apache-2.0
# Bounded, explicit desired membership and per-connection readiness.
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/auth.bend as Auth
import ../../src/bend/join_plan.bend as P

def plan(pair: P.State & List<&2, String>) -> P.State:
  match pair:
    case (state, _): state

def wire(state: P.State) -> String:
  match state:
    case P.State{desired, _, _, _, _, _, _}: String.join(P.lines(desired), "|")

def lines(got: P.Flush) -> String:
  match got:
    case P.Flush{_, outs, _}: String.join(outs, "|")

def notice(got: P.Flush) -> String:
  match got:
    case P.Flush{_, _, P.Quiet{}}: "quiet"
    case P.Flush{_, _, P.Held{}}: "held"
    case P.Flush{_, _, P.Failed{}}: "failed"

def flushed(got: P.Flush) -> P.State:
  match got:
    case P.Flush{state, _, _}: state

def channels(n: Nat, state: P.State) -> P.State:
  match n:
    case Zero{}: state
    case Succ{+rest}: channels(rest, P.remember(state, "#c" ++ Nat.show(rest), "", True{}))

def capacity_controls() -> IO(Unit):
  +full = channels(14n, P.initial(""))
  do IO<Unit>:
    Unit <- E.must("all fourteen channel slots are retained", Nat.is_eq(List.length(&2, String, P.desired_names(full)), 14n))
    Unit <- E.must("fifteenth channel cannot grow the plan", Nat.is_eq(List.length(&2, String, P.desired_names(P.remember(full, "#extra", "", True{}))), 14n))
    Unit <- E.must_eq("existing channel key can update at capacity", wire(P.seed(P.remember(full, "#c0", "new-key", True{}), "#c0" <> Nil{})), "JOIN #c0 new-key")
    Unit <- E.must("invalid whitespace/key cannot create intent", Nat.is_eq(List.length(&2, String, P.desired_names(P.remember(P.initial(""), "#bad name", "key", True{}))), 0n))
    IO.pure(Unit, Unit{})

def auth_apply.reply(+cl: Cl.Client, reply: Auth.Reply) -> Cl.Client:
  match reply:
    case Auth.Reply{phase, _, notice}: Auth.apply_reply(cl, phase, notice)

def auth_apply(+cl: Cl.Client, +line: String, +port: U32) -> Cl.Client:
  auth_apply.reply(cl, Auth.step_for(cl, line, port))

def auth_held(phase: Cl.AuthPhase) -> Bool:
  match phase:
    case Cl.AuthHeld{_}: True{}
    case _: False{}

def auth_is(want: Cl.AuthPhase, phase: Cl.AuthPhase) -> Bool:
  match want:
    case Cl.AuthChallenge{}:
      match phase:
        case Cl.AuthChallenge{}: True{}
        case _: False{}
    case Cl.AuthResult{}:
      match phase:
        case Cl.AuthResult{}: True{}
        case _: False{}
    case Cl.AuthDone{}:
      match phase:
        case Cl.AuthDone{}: True{}
        case _: False{}
    case _: False{}

def auth_controls() -> IO(Unit):
  +cl = Cl.client_set_auth(Cl.init("me", "irc.example"), Cl.SaslOnly{}, "irc.example", 6667, "", "", "account", "secret")
  +welcome: String = ":irc.example 001 me :welcome"
  +motd: String = ":irc.example 376 me :end of MOTD"
  +waiting = P.received(P.reset(P.initial("#start"), cl, 6667), cl, welcome)
  +held = flushed(P.flush(waiting, cl))
  +failed_cl = Cl.set_auth(cl, Cl.AuthDone{})
  +ok_cl = Cl.advance_auth_success(Cl.set_auth(cl, Cl.AuthDone{}))
  +wrong_port = P.reset(P.initial("#start"), cl, 6697)
  # Live fold order: Auth.step then JoinPlan.flush. Bare 001 during SASL
  # must land AuthHeld, not AuthDone-as-failure.
  +cap_held = auth_apply(cl, welcome, 6667)
  +challenge = auth_apply(cl, ":irc.example CAP me ACK :sasl", 6667)
  +challenge_held = auth_apply(challenge, welcome, 6667)
  +result = auth_apply(challenge, "AUTHENTICATE +", 6667)
  +result_held = auth_apply(result, welcome, 6667)
  do IO<Unit>:
    Unit <- E.must("same host live port match requires auth", Auth.join_required(cl, 6667))
    Unit <- E.must("same host different live port skips auth barrier", Bool.not(Auth.join_required(cl, 6697)))
    Unit <- E.must_eq("mismatched live port resets without NeedAuth", notice(P.flush(P.received(wrong_port, cl, welcome), cl)), "quiet")
    Unit <- E.must_eq("mismatched port still waits for MOTD", lines(P.flush(P.received(wrong_port, cl, welcome), cl)), "")
    Unit <- E.must_eq("mismatched port flushes at MOTD without auth wait", lines(P.flush(P.received(P.received(wrong_port, cl, welcome), cl, motd), cl)), "JOIN #start")
    Unit <- E.must_eq("configured auth holds joins", lines(P.flush(waiting, cl)), "")
    Unit <- E.must_eq("waiting is reported once", notice(P.flush(waiting, cl)), "held")
    Unit <- E.must_eq("bare 001 stays held not failed", notice(P.flush(held, cl)), "quiet")
    Unit <- E.must("AuthCap bare 001 is AuthHeld", auth_held(Cl.get_auth(cap_held)))
    Unit <- E.must_eq("Auth.step+flush AuthCap 001 is held not failed", notice(P.flush(waiting, cap_held)), "held")
    Unit <- E.must("AuthChallenge bare 001 is AuthHeld", auth_held(Cl.get_auth(challenge_held)))
    Unit <- E.must_eq("Auth.step+flush AuthChallenge 001 is held not failed", notice(P.flush(waiting, challenge_held)), "held")
    Unit <- E.must("AuthResult bare 001 is AuthHeld", auth_held(Cl.get_auth(result_held)))
    Unit <- E.must("held AuthCap still accepts SASL ack", auth_is(Cl.AuthChallenge{}, Cl.get_auth(auth_apply(cap_held, ":irc.example CAP me ACK :sasl", 6667))))
    Unit <- E.must("held AuthCap still accepts SASL nak", auth_is(Cl.AuthDone{}, Cl.get_auth(auth_apply(cap_held, ":irc.example CAP me NAK :sasl", 6667))))
    Unit <- E.must("held AuthChallenge still accepts plus", auth_is(Cl.AuthResult{}, Cl.get_auth(auth_apply(challenge_held, "AUTHENTICATE +", 6667))))
    Unit <- E.must("held AuthResult still accepts 903", auth_is(Cl.AuthDone{}, Cl.get_auth(auth_apply(result_held, ":irc.example 903 me :ok", 6667))))
    Unit <- E.must("held AuthResult still accepts 904", auth_is(Cl.AuthDone{}, Cl.get_auth(auth_apply(result_held, ":irc.example 904 me :failed", 6667))))
    Unit <- E.must_eq("Auth.step+flush AuthResult 001 is held not failed", notice(P.flush(waiting, result_held)), "held")
    Unit <- E.must_eq("auth failure is reported despite previous wait", notice(P.flush(held, failed_cl)), "failed")
    Unit <- E.must_eq("auth failure cannot release joins", lines(P.flush(held, failed_cl)), "")
    Unit <- E.must_eq("repeat auth failure is silent", notice(P.flush(flushed(P.flush(held, failed_cl)), failed_cl)), "quiet")
    Unit <- E.must_eq("auth success alone still waits for MOTD", lines(P.flush(held, ok_cl)), "")
    Unit <- E.must_eq("MOTD wait after auth success is quiet", notice(P.flush(held, ok_cl)), "quiet")
    Unit <- E.must_eq("auth success releases joins at MOTD", lines(P.flush(P.received(held, ok_cl, motd), ok_cl)), "JOIN #start")
    Unit <- E.must_eq("AuthDone with success_seq is not failure", notice(P.flush(held, ok_cl)), "quiet")
    IO.pure(Unit, Unit{})

def key_controls() -> IO(Unit):
  +state = plan(P.outbound(P.demo("#start"), "JOIN #one,#two first-key,second-key" <> Nil{}))
  do IO<Unit>:
    Unit <- E.must_eq("leading-colon key preserves its IRC value", P.channel_line("#one", ":key"), "JOIN #one ::key")
    Unit <- E.must_eq("normal key remains a normal parameter", P.channel_line("#one", "key"), "JOIN #one key")
    Unit <- E.must_eq("each target retains its matching runtime key", wire(P.seed(state, "#one" <> "#two" <> Nil{})), "JOIN #one first-key|JOIN #two second-key")
    Unit <- E.must("explicit same-name key update advances revision", Nat.is_gt(P.revision(plan(P.outbound(state, "JOIN #one changed-key" <> Nil{}))), P.revision(state)))
    IO.pure(Unit, Unit{})

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- key_controls()
    Unit <- capacity_controls()
    Unit <- auth_controls()
    IO.print("join_plan_demo=ok")
