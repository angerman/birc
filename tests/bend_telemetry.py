# SPDX-License-Identifier: Apache-2.0
"""Offline wrapper flags and the pinned compiler's early opt-out branch."""
import os
from pathlib import Path
import re
import subprocess


def flags(text):
    lines = re.findall(r"^\s*(export (?:BEND_NO_TELEMETRY|DO_NOT_TRACK)=[^\n]+)",
                       text, re.M)
    return (sorted(line.strip() for line in lines)
            == ["export BEND_NO_TELEMETRY=1", "export DO_NOT_TRACK=1"]
            and all(text.index(line) < text.index("exec bun run") for line in lines))


def skips(text):
    return bool(re.search(
        r"async function check\(\): Promise<void> \{\s*"
        r"if \(process\.env\.BEND_NO_TELEMETRY\) \{\s*return;\s*\}", text))


wrapper = Path("nix/bend.nix").read_text()
assert flags(wrapper), "Bend and Bun privacy flags must precede compiler launch"
assert not flags(wrapper.replace("export BEND_NO_TELEMETRY=1", ""))
assert not flags(wrapper.replace("export BEND_NO_TELEMETRY=1", "export BEND_NO_TELEMETRY=0"))
assert not flags(wrapper.replace("export DO_NOT_TRACK=1", ""))

# Only constant export lines execute; neither Bun nor the compiler is started.
exports = re.findall(r"^\s*(export (?:BEND_NO_TELEMETRY|DO_NOT_TRACK)=1)\s*$",
                     wrapper, re.M)
result = subprocess.run(
    ["/bin/sh", "-eu", "-c", "\n".join(exports)
     + '\nprintf "%s %s\\n" "$BEND_NO_TELEMETRY" "$DO_NOT_TRACK"'],
    env={"BEND_NO_TELEMETRY": "0", "DO_NOT_TRACK": "0"},
    stdin=subprocess.DEVNULL, capture_output=True, timeout=3, check=True)
assert result.stdout == b"1 1\n" and not result.stderr

compiler = (Path(os.environ["BIRC_BEND_SRC"]) / "bend2/main.ts").read_text()
assert skips(compiler), "Pinned Bend must skip before state access or version fetch"
assert not skips(compiler.replace("process.env.BEND_NO_TELEMETRY", "process.env.DO_NOT_TRACK"))
assert not skips(compiler.replace("return;", "void 0;"))
print("bend_telemetry=ok")
