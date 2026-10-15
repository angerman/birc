# SPDX-License-Identifier: Apache-2.0
# Slice 5: cap-notify lifetime updates. CAP NEW enables like ACK, CAP DEL
# clears; both flow through the unchanged cap_trusted gate (G6.1).
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/cap_notify.bend as Cap

# NEW enables a mid-session bit, including one previously NAKed.
def new_enables_ok() -> Bool:
  +fresh = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NEW :away-notify", True{})
  +naked = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NAK :away-notify", True{})
  +late = Cap.caps_apply_line(naked, "s", "me", ":s CAP me NEW :away-notify", True{})
  Cap.away_ok(fresh) && Bool.not(Cap.away_ok(naked)) && Cap.away_ok(late)

# DEL clears a NEW-enabled bit; untouched bits survive.
def new_del_ok() -> Bool:
  +on = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NEW :message-tags away-notify", True{})
  +del = Cap.caps_apply_line(on, "s", "me", ":s CAP me DEL :away-notify", True{})
  Cap.tags_ok(on) && Cap.away_ok(on) && Cap.tags_ok(del) && Bool.not(Cap.away_ok(del))

# Hostile NEW never enables: user prefix, foreign recipient, registered '*'.
# Preregistration '*' still enables, matching the ACK trust rule.
def hostile_new_ok() -> Bool:
  +spoof = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":alice!u@h CAP me NEW :away-notify", True{})
  +other = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP other NEW :away-notify", True{})
  +star_reg = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * NEW :away-notify", True{})
  +star_pre = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * NEW :away-notify", False{})
  Bool.not(Cap.away_ok(spoof)) && Bool.not(Cap.away_ok(other)) && Bool.not(Cap.away_ok(star_reg)) && Cap.away_ok(star_pre)

# NEW with cap=val enables the bare name.
def new_value_ok() -> Bool:
  +valued = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NEW :away-notify=1", True{})
  Cap.away_ok(valued)

# Own request line (the global wanted union is integrator-owned).
def req_line_ok() -> Bool:
  String.eq(Irc.format_cap_req(Cap.CAP_NOTIFY()), "CAP REQ :cap-notify")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("cap_end_owner", Cap.cap_end_single_owner_ok())
    Unit <- E.must("caps_ack_only", Cap.caps_ack_only_ok())
    Unit <- E.must("new_enables", new_enables_ok())
    Unit <- E.must("new_del_clears", new_del_ok())
    Unit <- E.must("hostile_new", hostile_new_ok())
    Unit <- E.must("new_value", new_value_ok())
    Unit <- E.must("req_line", req_line_ok())
    IO.print("capnotify_demo=ok")
