# SPDX-License-Identifier: Apache-2.0
# Proof-only selectors for the actual Workspace JOIN fixture.
# These partial laws do not prove Workspace guard admission or isolation.
import Base
import ./buffer.bend as Cl
import ./session.bend as Sess
import ./session_drafts.bend as AD
import ./drafts.bend as Drafts
import ./server_key.bend as Key

def s0() -> Key.ServerId:
  Key.ServerId{0n}

def s1() -> Key.ServerId:
  Key.ServerId{1n}

# Initialize JoinPlan/HistLive from the original unseeded Client. Install q
# only in Session.cl AFTER initialization, at the production seed location.
def online_at(+host: String, +chan: String, q: Nat) -> Sess.Session:
  +initial = Sess.session_with_client_at(Cl.init("me", host), chan, 6697)
  Sess.session_online(Sess.session_set_client(initial, Cl.set_log_seq(Sess.session_cl(initial), q)))

def post_seq(trip: AD.AD & Sess.NetCmd & Bool) -> Nat:
  match trip:
    case (ad, _, _): Cl.log_seq_of(Sess.session_cl(AD.ad_session(ad)))

def post_drafts(trip: AD.AD & Sess.NetCmd & Bool) -> Drafts.Drafts:
  match trip:
    case (ad, _, _): AD.ad_drafts(ad)

# A's input floor is 0; its actual resulting drafts are retained below.
def a_trip() -> AD.AD & Sess.NetCmd & Bool:
  AD.step_keys(AD.with_drafts(online_at("a.example", "#a", 0n), Drafts.empty(), s0()), Sess.keys_enter("/join #a"))

def b_first(q: Nat) -> AD.AD & Sess.NetCmd & Bool:
  AD.step_keys(AD.with_drafts(online_at("b.example", "#b", q), post_drafts(a_trip()), s1()), Sess.keys_enter("/join #b"))

# Consume the actual first tuple. Preserve its complete Session and drafts,
# and use s1 in with_drafts EXACTLY as the second Workspace call rebuilds AD.
def b_second.from(trip: AD.AD & Sess.NetCmd & Bool) -> AD.AD & Sess.NetCmd & Bool:
  match trip:
    case (+ad, _, _):
      AD.step_keys(AD.with_drafts(AD.ad_session(ad), AD.ad_drafts(ad), s1()), Sess.keys_enter("/join #extra"))

law a_actual_post_sequence:
  {post_seq(a_trip()) == 0n : Nat}

def a_actual_post_sequence():
  {==}

law b_first_actual_post_sequence:
  for +q: Nat
  {post_seq(b_first(q)) == q : Nat}

def b_first_actual_post_sequence(q):
  {==}

law b_second_actual_post_sequence:
  for +q: Nat
  {post_seq(b_second.from(b_first(q))) == q : Nat}

def b_second_actual_post_sequence(q):
  {==}
