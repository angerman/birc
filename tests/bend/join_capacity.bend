# SPDX-License-Identifier: Apache-2.0
# Accepted JOINs must fit the complete desired set, without ghost local tabs.
import Base
import ./expect.bend as E
import ../../src/bend/buffer.bend as Cl
import ../../src/bend/client_laws.bend as CL
import ../../src/bend/join_plan.bend as P
import ../../src/bend/isupport.bend as Is
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
    case P.State{desired, _, _, _, _, _, _}: P.key(desired, name)

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

def ascii_iso() -> Is.State:
  Is.apply_line(Is.defaults(), ":irc 005 me CASEMAPPING=ascii :are supported")

def pair_state(+iso: Is.State) -> P.State:
  plan_state(P.outbound_iso(P.demo(""), ["JOIN #a[ one", "JOIN #a{ two"], iso))

def flush_wire(got: P.Flush) -> String:
  match got:
    case P.Flush{_, outs, _}: String.join(outs, "|")

def plan_key_cm(state: P.State, name: String, cm: String) -> String:
  match state:
    case P.State{desired, _, _, _, _, _, _}: P.key_cm(desired, name, cm)

def pair_flush(+iso: Is.State, +state: P.State) -> String:
  +cl = Cl.init("me", "irc")
  +reset = P.reset(state, cl, 6697)
  +welcome = P.received_with(Is.casemapping(iso), reset, cl, ":irc 001 me :welcome")
  flush_wire(P.flush_iso(P.received_with(Is.casemapping(iso), welcome, cl, ":irc 376 me :end of MOTD"), cl, iso))

def ascii_pair_distinct() -> Bool:
  +iso = ascii_iso()
  +state = pair_state(iso)
  Nat.is_eq(List.length(&2, String, P.desired_names(state)), 2n)
    && String.eq(plan_key_cm(state, "#a[", "ascii"), "one")
    && String.eq(plan_key_cm(state, "#a{", "ascii"), "two")
    && String.eq(pair_flush(iso, state), "JOIN #a[ one|JOIN #a{ two")

def ascii_part_keeps_sibling() -> Bool:
  +iso = ascii_iso()
  +next = plan_state(P.outbound_iso(pair_state(iso), ["PART #a["], iso))
  String.eq(String.join(P.desired_names(next), "|"), "#a{")
    && String.eq(plan_key_cm(next, "#a{", "ascii"), "two")

def ascii_kick_keeps_sibling() -> Bool:
  +iso = ascii_iso()
  +next = P.received_with("ascii", pair_state(iso), Cl.init("me", "irc"), ":irc KICK #a[ me")
  String.eq(String.join(P.desired_names(next), "|"), "#a{")
    && String.eq(plan_key_cm(next, "#a{", "ascii"), "two")

def rfc_pair_folds() -> Bool:
  +state = pair_state(Is.defaults())
  Nat.is_eq(List.length(&2, String, P.desired_names(state)), 1n)
    && String.eq(plan_key(state, "#a["), "two")

def seeded_keys_stay_exact() -> Bool:
  +iso = ascii_iso()
  +seeded = P.seed_iso(pair_state(iso), ["#a{", "#a["], Is.defaults())
  String.eq(String.join(P.desired_names(seeded), "|"), "#a{|#a[")
    && String.eq(plan_key_cm(seeded, "#a{", "ascii"), "two")
    && String.eq(plan_key_cm(seeded, "#a[", "ascii"), "one")
    && String.eq(pair_flush(iso, seeded), "JOIN #a{ two|JOIN #a[ one")

def ascii_capacity_counts_distinct() -> Bool:
  +base = P.demo(csv(13n))
  plan_rejected(P.outbound_iso(base, ["JOIN #a[,#a{ one,two"], ascii_iso()), base)

def rfc_capacity_folds_pair() -> Bool:
  plan_exact(P.outbound_iso(P.demo(csv(13n)), ["JOIN #a[,#a{ one,two"], Is.defaults()),
    "JOIN #a[,#a{ one,two", List.append(&2, String, names(13n), ["#a["]))

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
    Unit <- E.must("ascii desired identities and keys remain distinct through reconnect", ascii_pair_distinct())
    Unit <- E.must("ascii PART removes only the exact desired identity", ascii_part_keeps_sibling())
    Unit <- E.must("ascii self-KICK removes only the exact desired identity", ascii_kick_keeps_sibling())
    Unit <- E.must("default RFC1459 still folds bracket and brace identities", rfc_pair_folds())
    Unit <- E.must("saved exact channel names retain only their own runtime keys", seeded_keys_stay_exact())
    Unit <- E.must("ascii capacity counts bracket and brace as two identities", ascii_capacity_counts_distinct())
    Unit <- E.must("default RFC1459 capacity folds bracket and brace", rfc_capacity_folds_pair())
    Unit <- E.must("Session reports rejected raw extra without changing intent", session_full_raw_rejected())
    Unit <- E.must("Session rejects staged JOIN without a ghost buffer", session_full_join_rejected())
    Unit <- E.must("Session reports rejected fifteen-channel list", session_list15_rejected())
    Unit <- E.must("Session accepts fitting raw extra", session_fitting_exact())
    Unit <- E.must("Session accepts complete fourteen-channel list", session_list14_exact())
    IO.print("join_capacity=ok\n")
