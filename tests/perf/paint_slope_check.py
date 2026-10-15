# SPDX-License-Identifier: Apache-2.0
"""Deterministic checks for the paint_footprint slope verdict.

Pure-function checks only: no binary build, no pty, no footprint tool.
Covers linfit, the slope_verdict layers (trigger, tail agreement,
backstop, flat, endpoint fallback), trigger confirmation, and the
threshold env overrides.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from paint_footprint import (  # noqa: E402
    _env_float,
    combine_triggers,
    linfit,
    slope_verdict,
)

N = 32
BASE = 4000


def check(name, cond):
    assert cond, name


# linfit basics.
slope, r2 = linfit([float(BASE + 25 * i) for i in range(N)])
check("linear slope", abs(slope - 25.0) < 1e-9)
check("linear r2", abs(r2 - 1.0) < 1e-9)
check("constant", linfit([7.0] * N) == (0.0, 0.0))
check("short", linfit([7.0]) == (0.0, 0.0))


def decide(series, delta):
    verdict, trigger, _s, _r, _t, code = slope_verdict(series, delta)
    return verdict, trigger, code


# Sustained linear climb with noise triggers.
climb = [BASE + 25 * i + (i % 3) for i in range(N)]
check("climb", decide(climb, 25 * (N - 1)) == ("climbs", "profile", 3))

# Front-loaded transient (steep first quarter, flat rest) must not trigger.
front = [BASE + 80 * i for i in range(8)] + [BASE + 80 * 7] * 24
v, t, c = decide(front, 80 * 7)
check("front no trigger", t == "none" and c == 0)

# Back-loaded transient (flat then steep) must not trigger.
back = [BASE] * 24 + [BASE + 80 * (i - 23) for i in range(24, 32)]
v, t, c = decide(back, 80 * 8)
check("back no trigger", t == "none" and c == 0)

# Single mid-run step must not trigger (backstop needs >= 2048).
step = [BASE] * 16 + [BASE + 1500] * 16
v, t, c = decide(step, 1500)
check("step no trigger", t == "none" and c == 0)

# Census-shaped staircase must not trigger.
stair = [BASE] * 8 + [BASE + 300] * 16 + [BASE + 800] * 8
v, t, c = decide(stair, 800)
check("staircase no trigger", t == "none" and c == 0)

# Flat noisy series is flat.
check("flat", decide([BASE + (i % 5) * 10 for i in range(N)], 40)[0] == "flat")

# Short series falls back to the endpoint verdict.
check("short fallback", decide([BASE, BASE + 100], 100) == ("flat", "none", 0))
check("short endpoint", decide([BASE, BASE + 3000], 3000)[0] == "climbs")

# Endpoint backstop climbs without profiling.
big = [BASE] * 16 + [BASE + 2500] * 16
check("backstop", decide(big, 2500) == ("climbs", "none", 0))

# Confirmation: profile only if both runs trigger.
prof = {"trigger": "profile", "verdict": "climbs"}
flat = {"trigger": "none", "verdict": "flat"}
unclear = {"trigger": "none", "verdict": "unclear"}
check("confirm both", combine_triggers(prof, prof) == ("climbs", "profile", 3))
check("confirm downgrade", combine_triggers(prof, flat) == ("flat", "none", 0))
check("confirm unclear", combine_triggers(prof, unclear) == ("unclear", "none", 0))

# Env overrides.
os.environ["PAINT_SLOPE_TRIGGER"] = "0.5"
os.environ["PAINT_R2_TIGHT"] = "not-a-number"
check("env set", _env_float("PAINT_SLOPE_TRIGGER", 8.0) == 0.5)
check("env bad", _env_float("PAINT_R2_TIGHT", 0.9) == 0.9)
del os.environ["PAINT_SLOPE_TRIGGER"]
del os.environ["PAINT_R2_TIGHT"]
check("env unset", _env_float("PAINT_SLOPE_TRIGGER", 8.0) == 8.0)

print("paint_slope=ok")
