# SPDX-License-Identifier: Apache-2.0
# Accepted JOINs must fit the complete desired set, without ghost local tabs.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/join_plan.bend as P
import ../../src/bend/session.bend as S

def names(+n: Nat) -> List<&2, String>:
  match n:
    case 0n: Nil{}
    case 1n+p: List.append(&2, String, names(p), ("#r" ++ Nat.show(p)) <> Nil{})

def csv(n: Nat) -> String:
  String.join(names(n), ",")

def plan_rejected(pair: P.State & List<&2, String>, +before: P.State) -> Bool:
  match pair:
    case (+next, outs): List.is_empty(&2, String, outs)
      && String.eq(String.join(P.desired_names(next), "|"), String.join(P.desired_names(before), "|"))
      && Nat.is_eq(P.revision(next), P.revision(before))

def plan_exact(pair: P.State & List<&2, String>, expected: String, wanted: List<&2, String>) -> Bool:
  match pair:
    case (next, outs): String.eq(String.join(outs, "|"), expected)
      && String.eq(String.join(P.desired_names(next), "|"), String.join(wanted, "|"))

def plan_full_rejected() -> Bool:
  +base = P.demo(csv(14n))
  plan_rejected(P.outbound(base, ["JOIN #extra"]), base)

def plan_fitting_exact() -> Bool:
  plan_exact(P.outbound(P.demo(csv(13n)), ["JOIN #extra"]), "JOIN #extra", List.append(&2, String, names(13n), ["#extra"]))

def plan_list15_rejected() -> Bool:
  +base = P.demo("")
  plan_rejected(P.outbound(base, ["JOIN " ++ csv(15n)]), base)

def plan_list14_exact() -> Bool:
  plan_exact(P.outbound(P.demo(""), ["JOIN " ++ csv(14n)]), "JOIN " ++ csv(14n), names(14n))

def plan_key(state: P.State, name: String) -> String:
  match state:
    case P.State{desired, _, _, _, _, _}: P.key(desired, name)

def plan_existing_key.got(pair: P.State & List<&2, String>) -> Bool:
  match pair:
    case (+next, outs): plan_exact((next, outs), "JOIN #R0 replacement-key", names(14n))
      && String.eq(plan_key(next, "#r0"), "replacement-key")

def plan_existing_key_exact() -> Bool:
  plan_existing_key.got(P.outbound(P.demo(csv(14n)), ["JOIN #R0 replacement-key"]))

def plan_state(pair: P.State & List<&2, String>) -> P.State:
  match pair:
    case (state, _): state

def plan_mixed.got(pair: P.State & List<&2, String>, before: P.State) -> Bool:
  match pair:
    case (+next, outs): plan_rejected((next, outs), before) && String.eq(plan_key(next, "#r0"), "old-key")

def plan_mixed_rejected() -> Bool:
  +base = plan_state(P.outbound(P.demo(csv(14n)), ["JOIN #r0 old-key"]))
  plan_mixed.got(P.outbound(base, ["JOIN #r0,#extra changed-key,new-key"]), base)

def plan_duplicate_exact() -> Bool:
  plan_exact(P.outbound(P.demo(csv(14n)), ["JOIN #r0,#R0"]), "JOIN #r0,#R0", names(14n))

def ordered_capacity() -> Bool:
  +base = P.demo(csv(14n))
  P.capacity_ok(["PART #r0", "JOIN #extra"], base)
    && Bool.not(P.capacity_ok(["JOIN #extra", "PART #r0"], base))

def online(n: Nat) -> S.Session:
  S.session_online(S.session_demo_at(Cl.init("me", "irc.example"), csv(n), 6667))

def session_wires(cmd: S.NetCmd) -> String:
  match cmd:
    case S.Cont{outs}: String.join(outs, "|")
    case _: "[unexpected command]"

def session_rejected(trip: S.Session & S.NetCmd & Bool, n: Nat) -> Bool:
  match trip:
    case (+next, cmd, halt): String.is_empty(session_wires(cmd)) && Bool.not(halt)
      && String.eq(String.join(S.session_desired_channels(next), "|"), String.join(names(n), "|"))
      && Nat.is_eq(S.session_channel_revision(next), 0n)
      && Nat.is_eq(Cl.normal_buffer_count(Cl.client_bufs(S.session_cl(next))), 1n)
      && String.contains(CL.buf_texts(S.session_cl(next), 0n), "channel limit reached")

def session_full_raw_rejected() -> Bool:
  session_rejected(S.step_enter(online(14n), "/raw JOIN #extra"), 14n)

def session_full_join_rejected() -> Bool:
  session_rejected(S.step_enter(online(14n), "/join #extra"), 14n)

def session_list15_rejected() -> Bool:
  session_rejected(S.step_enter(online(0n), "/raw JOIN " ++ csv(15n)), 0n)

def session_exact(trip: S.Session & S.NetCmd & Bool, wire: String, want: List<&2, String>) -> Bool:
  match trip:
    case (+next, cmd, halt): String.eq(session_wires(cmd), wire) && Bool.not(halt)
      && String.eq(String.join(S.session_desired_channels(next), "|"), String.join(want, "|"))

def session_fitting_exact() -> Bool:
  session_exact(S.step_enter(online(13n), "/raw JOIN #extra"), "JOIN #extra", List.append(&2, String, names(13n), ["#extra"]))

def session_list14_exact() -> Bool:
  session_exact(S.step_enter(online(0n), "/raw JOIN " ++ csv(14n)), "JOIN " ++ csv(14n), names(14n))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("fourteen desired channels reject raw extra atomically", plan_full_rejected())
    Unit <- E.must("thirteen desired channels accept raw extra completely", plan_fitting_exact())
    Unit <- E.must("raw fifteen-channel list rejects atomically", plan_list15_rejected())
    Unit <- E.must("raw fourteen-channel list is retained completely", plan_list14_exact())
    Unit <- E.must("existing desired channel can change key at capacity", plan_existing_key_exact())
    Unit <- E.must("mixed existing/new overflow cannot partially update a key", plan_mixed_rejected())
    Unit <- E.must("case-folded duplicate channels consume no new slot", plan_duplicate_exact())
    Unit <- E.must("preflight respects ordered PART capacity release", ordered_capacity())
    Unit <- E.must("Session reports rejected raw extra without changing intent", session_full_raw_rejected())
    Unit <- E.must("Session rejects staged JOIN without a ghost buffer", session_full_join_rejected())
    Unit <- E.must("Session reports rejected fifteen-channel list", session_list15_rejected())
    Unit <- E.must("Session accepts fitting raw extra", session_fitting_exact())
    Unit <- E.must("Session accepts complete fourteen-channel list", session_list14_exact())
    IO.print("join_capacity=ok\n")
