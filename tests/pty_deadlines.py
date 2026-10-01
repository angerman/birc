#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Inspect Make's PTY plan without building or running its commands."""
import math
import re
import shlex
import subprocess
from pathlib import Path


def positive_duration(value: str) -> bool:
    if not re.fullmatch(r"(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)[smhd]?", value):
        return False
    number = float(value.rstrip("smhd")) * {"s": 1, "m": 60, "h": 3600, "d": 86400}.get(value[-1], 1)
    return math.isfinite(number) and number > 0


def bounded(prefix: list[str], inherited: bool) -> bool:
    return inherited or any(
        Path(token).name == "timeout" and positive_duration(prefix[index + 1])
        for index, token in enumerate(prefix[:-1])
    )


def pty_commands(line: str, inherited: bool = False) -> list[tuple[str, bool]]:
    lexer = shlex.shlex(line, posix=True, punctuation_chars=";&|")
    lexer.whitespace_split = True
    commands = []
    tokens = []
    for token in list(lexer) + [";"]:
        if token not in (";", "&&", "||", "|", "&"):
            tokens.append(token)
            continue
        for index, word in enumerate(tokens):
            if Path(word).name == "python3" and index + 1 < len(tokens):
                script = tokens[index + 1]
                if script.startswith("tests/pty/") and script.endswith(".py"):
                    commands.append((script, bounded(tokens[:index], inherited)))
            if Path(word).name == "sh" and tokens[index + 1:index + 2] == ["-c"]:
                commands.extend(pty_commands(tokens[index + 2], bounded(tokens[:index], inherited)))
        tokens = []
    return commands


def parser_controls() -> None:
    script = "tests/pty/probe.py"
    for command in (f"python3 {script}", f"timeout 0 python3 {script}",
                    f"timeout inf python3 {script}",
                    f"sh -c 'timeout 0 python3 {script}'",
                    f"timeout 5 true; python3 {script}"):
        assert pty_commands(command) == [(script, False)], command
    for command in (f"timeout 150 python3 {script}",
                    f"nix develop --command timeout 0.5s python3 {script}",
                    f"sh -c 'UBSAN_OPTIONS=halt_on_error=1 timeout 120 python3 {script}'",
                    f"timeout 40 sh -c 'python3 {script}'"):
        assert pty_commands(command) == [(script, True)], command
    print("pty_deadlines parser controls=ok")


def main() -> int:
    parser_controls()
    plan = subprocess.run(
        ["make", "-n", "-o", "build/birc", "-o", "build/birc-output-limit", "test-pty"],
        cwd=Path(__file__).resolve().parents[1], capture_output=True, text=True,
        check=True, timeout=15,
    ).stdout
    commands = [command for line in plan.splitlines() for command in pty_commands(line)]
    assert commands, "Make's plan contains no Python PTY commands"
    missing = sorted({script for script, finite in commands if not finite})
    if missing:
        print(f"pty_deadlines: {len(missing)} scripts without finite positive outer timeout "
              f"({len(commands)} planned commands):")
        for script in missing:
            print(f"  {script}")
        return 1
    print(f"pty_deadlines=ok ({len(commands)} planned commands)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
