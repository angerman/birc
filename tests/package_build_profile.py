#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Evaluate pinned build recipes; run only synthetic compiler functions."""
import argparse
import json
import re
import subprocess


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--eval-timeout", type=int, default=45)
args = parser.parse_args()
if not 1 <= args.eval_timeout <= 300:
    parser.error("evaluation timeout must be 1..300 seconds")


expression = '''
let
  flake = builtins.getFlake (toString ./.);
  packages = flake.packages.${builtins.currentSystem};
in { plain = packages.birc.buildPhase; timed = packages.birc-profiled.buildPhase; }
'''
result = subprocess.run(
    ["nix", "--extra-experimental-features", "nix-command flakes", "--offline", "eval",
     "--no-update-lock-file", "--impure", "--json", "--expr", expression],
    capture_output=True, timeout=args.eval_timeout, check=True,
)
phases = json.loads(result.stdout)
assert "birc-build" not in phases["plain"], "ordinary build enabled timers"
assert "birc-build" in phases["timed"], "profile build omitted timers"
assert re.findall(r"^\s*(bend|clang)\s", phases["plain"], re.M) == ["bend", "clang"]
assert re.findall(r"^\s*(bend|clang)\s", phases["timed"], re.M) == ["bend", "clang"]

for name, phase in phases.items():
    for fail in ("none", "bend", "clang"):
        prelude = f'''
runHook() {{ :; }}
bend() {{ printf 'synthetic-codegen\\n'; [ '{fail}' != bend ] || return 65; }}
clang() {{ printf 'synthetic-native\\n'; [ '{fail}' != clang ] || return 66; }}
'''
        got = subprocess.run(["bash", "-eu", "-c", prelude + phase],
                             capture_output=True, timeout=5)
        assert got.returncode == {"none": 0, "bend": 65, "clang": 66}[fail]
        expected = b"synthetic-codegen\n"
        if fail != "bend":
            expected += b"synthetic-native\n"
        assert got.stdout == expected, "timer changed command order or admission"
        if name == "plain":
            assert not got.stderr, "ordinary recipe wrote profile output"
        else:
            lines = got.stderr.decode().splitlines()
            assert lines[0] == "birc-build stage=codegen begin"
            pids = [line for line in lines if "stage=codegen pid=" in line]
            assert len(pids) == 1 and re.fullmatch(
                r"birc-build stage=codegen pid=[1-9][0-9]*", pids[0])
            completed = re.findall(r"stage=(codegen|native) elapsed_s=\d+", got.stderr.decode())
            assert completed == {"none": ["codegen", "native"], "bend": [], "clang": ["codegen"]}[fail]
            assert ("birc-build stage=native begin" in lines) is (fail != "bend")

print("package_build_profile=ok cases=6")
