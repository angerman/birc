#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Phase Nix eval/startup latency with load context; reports, never gates.

Default phases stay fast (config, trivial eval, one store round-trip).
--full adds the slow app-program eval, package instantiation, and a
realization-inclusive develop startup. Every phase has its own wall-clock
bound; owned children are killed on timeout, including descendants that
outlive an exited leader. A leader that exits 0 while a descendant still
holds an output pipe open is a timeout, never success. Retained
stdout/stderr evidence is byte-capped per phase. Exits nonzero when any
phase fails or times out; trivial-phase success never implies package
health. Run with ambient python3; needs only nix on PATH.
--self-test exercises run_phase on synthetic owned children (no nix): the
paired fixture for the pipe-orphan/owned-group-kill fix.
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import select
import shutil
import signal
import subprocess
import sys
import time

NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]
CHUNK = 4096


def load_context() -> dict:
    load, cpus = None, None
    try:
        with open("/proc/loadavg", encoding="utf-8") as handle:
            load = float(handle.read().split()[0])
    except (OSError, ValueError, IndexError):
        try:
            out = subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True,
                                 timeout=5, check=True).stdout.decode()
            load = float(out.replace("{", " ").replace("}", " ").split()[0])
        except (OSError, ValueError, IndexError, subprocess.SubprocessError):
            load = None
    for probe in (["nproc"], ["sysctl", "-n", "hw.ncpu"]):
        try:
            cpus = int(subprocess.run(probe, capture_output=True, timeout=5,
                                      check=True).stdout.decode().split()[0])
            break
        except (OSError, ValueError, IndexError, subprocess.SubprocessError):
            continue
    if cpus is None:
        cpus = os.cpu_count()
    return {"load1": load, "cpus": cpus}


def store_self() -> str | None:
    nix = shutil.which("nix")
    if not nix:
        return None
    real = os.path.realpath(nix)
    parts = real.split(os.sep)
    for index, part in enumerate(parts):
        if part == "store" and index + 1 < len(parts):
            return os.sep.join(parts[:index + 2])
    return None


def _drain_ready(proc: subprocess.Popen, out: bytearray, err: bytearray,
                 totals: list, keep: int, open_fds: set) -> None:
    waiters = [s for s in (proc.stdout, proc.stderr)
               if s is not None and s.fileno() in open_fds]
    if not waiters:
        return
    ready, _, _ = select.select(waiters, [], [], 0.05)
    for stream in ready:
        assert stream is not None
        try:
            chunk = os.read(stream.fileno(), CHUNK)
        except OSError:
            chunk = b""
        if stream is proc.stdout:
            buf, idx = out, 0
        else:
            buf, idx = err, 1
        if not chunk:
            open_fds.discard(stream.fileno())
            continue
        totals[idx] += len(chunk)
        room = keep - len(buf)
        if room > 0:
            buf.extend(chunk[:room])


def run_phase(name: str, argv: list, timeout: float, keep: int = 160,
              kind: str = "probe") -> dict:
    record = {"phase": name, "kind": kind, "elapsed_ms": None, "exit": None,
              "timeout": False, "output": None, "stderr": None,
              "truncated": False}
    start = time.monotonic()
    try:
        proc = subprocess.Popen(argv, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
    except OSError as error:
        record["stderr"] = f"spawn failed: {error}"[:keep]
        record["elapsed_ms"] = round(1000 * (time.monotonic() - start), 3)
        return record
    out, err = bytearray(), bytearray()
    totals = [0, 0]
    open_fds = {s.fileno() for s in (proc.stdout, proc.stderr) if s is not None}
    deadline = start + timeout
    try:
        while time.monotonic() < deadline:
            if proc.poll() is not None and not open_fds:
                break
            _drain_ready(proc, out, err, totals, keep, open_fds)
        # Complete means the leader exited AND both pipes reached EOF. A
        # leader that exits 0 while a descendant still holds an output pipe
        # open waits out the deadline the same as a live leader: incomplete
        # pipe EOF at the deadline is a timeout, never success, and the
        # owned process group is always killed so no descendant that holds
        # the pipe outlives the phase. Only the owned group (proc.pid) is
        # ever signalled.
        complete = proc.poll() is not None and not open_fds
        if not complete:
            record["timeout"] = True
            if proc.poll() is not None:
                record["exit"] = proc.returncode
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
            # Bounded post-kill drain for failure evidence only.
            end = time.monotonic() + 2
            while open_fds and time.monotonic() < end:
                _drain_ready(proc, out, err, totals, keep, open_fds)
                if not open_fds:
                    break
        else:
            record["exit"] = proc.returncode
        record["output"] = out.decode("utf-8", "replace")
        record["stderr"] = err.decode("utf-8", "replace")
        record["truncated"] = totals[0] > len(out) or totals[1] > len(err)
    finally:
        record["elapsed_ms"] = round(1000 * (time.monotonic() - start), 3)
        if proc.poll() is None or open_fds:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
    return record


def phase_ok(record: dict) -> bool:
    return (record.get("exit") == 0 and not record.get("timeout")
            and record.get("output") != "skipped")


def config_phase() -> dict:
    record = run_phase("config", NIX + ["show-config"], 30, keep=16384,
                       kind="config")
    settings = {}
    if record["output"]:
        for line in record["output"].splitlines():
            for key in ("sandbox ", "max-jobs ", "cores "):
                if line.startswith(key):
                    settings[key.strip()] = line.split("=", 1)[1].strip()
    record["settings"] = settings
    record["output"] = None
    return record


def app_attribute() -> str | None:
    machine = {"arm64": "aarch64", "aarch64": "aarch64",
               "x86_64": "x86_64"}.get(platform.machine())
    system = {"Darwin": "darwin", "Linux": "linux"}.get(platform.system())
    if machine is None or system is None:
        return None
    return f".#apps.{machine}-{system}.default.program"


def emit(record: dict) -> None:
    print("nix_eval " + json.dumps(record, sort_keys=True), flush=True)


def _self_test_dead(pid: int, timeout: float = 3.0) -> bool:
    """True once the owned pid no longer exists."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        time.sleep(0.05)
    return False


def self_test() -> None:
    """Paired fixture for the pipe-orphan/owned-group-kill fix.

    Synthetic owned children only; needs no nix. A leader that exits 0
    while a same-group descendant still holds an output pipe open must
    report timeout (never success), and the owned-group kill must leave no
    descendant behind. Controls prove the verdict comes from the orphan.
    """
    import shlex
    import tempfile
    shell = "/bin/sh"
    record = run_phase("control_exit0", [shell, "-c", "exit 0"], 10)
    assert record["timeout"] is False and record["exit"] == 0, record
    assert phase_ok(record), record
    print("nix_eval self-test control-exit0=ok", flush=True)
    record = run_phase("control_exit3", [shell, "-c", "exit 3"], 10)
    assert record["timeout"] is False and record["exit"] == 3, record
    print("nix_eval self-test control-exit3=ok", flush=True)
    record = run_phase("control_sleep", [shell, "-c", "exec sleep 30"], 1)
    assert record["timeout"] is True, record
    print("nix_eval self-test control-live-timeout=ok", flush=True)
    with tempfile.TemporaryDirectory() as tmp:
        pidfile = os.path.join(tmp, "orphan.pid")
        record = run_phase(
            "orphan_leader_exit0",
            [shell, "-c",
             f"sleep 30 & echo $! > {shlex.quote(pidfile)}; exit 0"],
            1)
        assert record["timeout"] is True, record
        assert record["exit"] == 0, record
        with open(pidfile, encoding="utf-8") as handle:
            orphan = int(handle.read().strip())
        assert orphan > 1, orphan
        assert _self_test_dead(orphan), f"orphan {orphan} outlived its phase"
    print("nix_eval self-test orphan-timeout-and-group-kill=ok", flush=True)
    record = run_phase(
        "control_flood",
        [shell, "-c",
         "i=0; while [ $i -lt 40 ]; do echo 0123456789; i=$((i+1)); done"],
        10, keep=160)
    assert record["timeout"] is False and record["exit"] == 0, record
    assert record["truncated"] is True, record
    assert len(record["output"]) == 160, record
    print("nix_eval self-test truncation-cap=ok", flush=True)
    record = run_phase("control_stderr",
                       [shell, "-c", "echo out; echo err >&2"], 10)
    assert record["output"] == "out\n" and record["stderr"] == "err\n", record
    print("nix_eval self-test stderr-split=ok", flush=True)
    print("nix_eval self-test=ok", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true",
                        help="also run the slow app-program eval, package "
                             "instantiation, and realization-inclusive "
                             "develop startup phases")
    parser.add_argument("--self-test", action="store_true",
                        help="run the synthetic run_phase fixture (no nix)")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    context = load_context()
    emit({"phase": "context", **context,
          "scope": "trivial/config/store success never implies package health"})
    failures = 0
    record = config_phase()
    failures += not phase_ok(record)
    emit(record)
    record = run_phase(
        "trivial", NIX + ["eval", "--offline", "--impure", "--expr", "1"],
        30, kind="eval-only")
    failures += not phase_ok(record)
    emit(record)
    known = store_self()
    if known is None:
        emit({"phase": "roundtrip", "kind": "daemon-roundtrip",
              "output": "skipped", "elapsed_ms": None, "exit": None,
              "timeout": False})
    else:
        record = run_phase(
            "roundtrip", NIX + ["path-info", "--offline", known], 30,
            kind="daemon-roundtrip")
        failures += not phase_ok(record)
        emit(record)
    if args.full:
        attribute = app_attribute()
        if attribute is None:
            failures += 1
            emit({"phase": "app_program", "kind": "eval-only",
                  "output": "unsupported platform"})
        else:
            record = run_phase(
                "app_program", NIX + ["eval", "--offline", "--no-update-lock-file",
                                      "--raw", attribute], 120, kind="eval-only")
            failures += not phase_ok(record)
            emit(record)
        record = run_phase(
            "package_drv", NIX + ["path-info", "--derivation", "--offline",
                                  "--no-update-lock-file", ".#birc"], 180,
            kind="instantiation")
        failures += not phase_ok(record)
        emit(record)
        record = run_phase(
            "develop_true", NIX + ["develop", "--no-update-lock-file", ".",
                                   "--command", "true"], 180,
            kind="realization-inclusive",
            )
        record["note"] = ("develop startup includes realization and shell "
                          "setup; not eval-only")
        failures += not phase_ok(record)
        emit(record)
    if failures:
        print("nix_eval=fail", flush=True)
        return 1
    print("nix_eval=ok", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
