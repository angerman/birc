# SPDX-License-Identifier: Apache-2.0
# cap-notify lifetime updates. CAP NEW advertises, ACK enables, and CAP DEL
# clears through the unchanged cap_trusted gate (G6.1).
import Base
import ./expect.bend as E
import ../../src/bend/irc.bend as Irc
import ../../src/bend/cap_notify.bend as Cap

# NEW alone never enables a mid-session bit, including one previously NAKed.
def new_advertises_ok() -> Bool:
  +fresh = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NEW :away-notify", True{})
  +naked = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NAK :away-notify", True{})
  +late = Cap.caps_apply_line(naked, "s", "me", ":s CAP me NEW :away-notify", True{})
  Bool.not(Cap.away_ok(fresh)) && Bool.not(Cap.away_ok(naked)) && Bool.not(Cap.away_ok(late))

# ACK after NEW enables; DEL clears that bit while untouched bits survive.
def ack_del_ok() -> Bool:
  +advertised = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NEW :message-tags away-notify", True{})
  +on = Cap.caps_apply_line(advertised, "s", "me", ":s CAP me ACK :message-tags away-notify", True{})
  +del = Cap.caps_apply_line(on, "s", "me", ":s CAP me DEL :away-notify", True{})
  Bool.not(Cap.tags_ok(advertised)) && Bool.not(Cap.away_ok(advertised))
    && Cap.tags_ok(on) && Cap.away_ok(on) && Cap.tags_ok(del) && Bool.not(Cap.away_ok(del))

# NEW never enables regardless of whether its source passes the trust gate.
def hostile_new_ok() -> Bool:
  +spoof = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":alice!u@h CAP me NEW :away-notify", True{})
  +other = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP other NEW :away-notify", True{})
  +star_reg = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * NEW :away-notify", True{})
  +star_pre = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP * NEW :away-notify", False{})
  Bool.not(Cap.away_ok(spoof)) && Bool.not(Cap.away_ok(other)) && Bool.not(Cap.away_ok(star_reg)) && Bool.not(Cap.away_ok(star_pre))

# NEW with cap=val also only advertises the bare name.
def new_value_ok() -> Bool:
  +valued = Cap.caps_apply_line(Cap.caps0(), "s", "me", ":s CAP me NEW :away-notify=1", True{})
  Bool.not(Cap.away_ok(valued))

# Own request line (the global wanted union is integrator-owned).
def req_line_ok() -> Bool:
  String.eq(Irc.format_cap_req(Cap.CAP_NOTIFY()), "CAP REQ :cap-notify")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- E.must("cap_end_owner", Cap.cap_end_single_owner_ok())
    Unit <- E.must("caps_ack_only", Cap.caps_ack_only_ok())
    Unit <- E.must("new_advertises_only", new_advertises_ok())
    Unit <- E.must("ack_enables_del_clears", ack_del_ok())
    Unit <- E.must("hostile_new", hostile_new_ok())
    Unit <- E.must("new_value", new_value_ok())
    Unit <- E.must("req_line", req_line_ok())
    IO.print("capnotify_demo=ok")
