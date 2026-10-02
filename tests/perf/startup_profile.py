#!/usr/bin/env python3
"""Measure cached launch separately from terminal initialization; not a gate.

--nix-run compares the current prebuilt Nix app with that same installed binary.
Warm-ups are reported separately. All timestamps are external observations:
first_visible_ms observes the mode label, not completion of the entire frame.
The committed BIRC_FRAME_PROFILE timer supplies the View/native phase split.
Only demo data, a loopback mock, and optional owned synthetic history are used.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import platform
import pty
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path


PROFILE = re.compile(
    rb"birc_profile frames=(\d+) prepare_us=(\d+) begin_us=(\d+) "
    rb"draw_us=(\d+) end_us=(\d+) view_us=(\d+)"
)
PHASES = ("frames", "prepare_us", "begin_us", "draw_us", "end_us", "view_us")
CAP = 1_048_576
NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]


def stop(process: subprocess.Popen) -> None:
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    process.wait(timeout=2)


def append(target: bytearray, data: bytes, cap: int = CAP) -> None:
    if len(target) + len(data) > cap:
        raise RuntimeError("owned fixture output exceeded its capture limit")
    target.extend(data)


def clean_env(history: str) -> dict[str, str]:
    env = dict(os.environ)
    for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH_SECRET_FD",
                 "BIRC_AUTH_EVENT_FD", "TIMUI_TRACE"):
        env.pop(name, None)
    env.update(TERM="xterm-256color", BIRC_HISTORY=history,
               BIRC_IMAGES="off", BIRC_FRAME_PROFILE="1")
    return env


def captured(command: list[str], deadline: float) -> tuple[int, bytes, float]:
    started = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True, env=clean_env("none"))
    output = bytearray()
    errors = bytearray()
    assert process.stdout is not None and process.stderr is not None
    streams = {process.stdout.fileno(): output, process.stderr.fileno(): errors}
    try:
        while streams:
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError("Nix evaluation exceeded its wall-clock bound")
            for fd in select.select(list(streams), [], [], min(left, 0.02))[0]:
                chunk = os.read(fd, 65536)
                if chunk:
                    append(streams[fd], chunk, 65536)
                else:
                    del streams[fd]
        code = process.wait(timeout=max(0.001, deadline - time.monotonic()))
        return code, bytes(output), 1000 * (time.monotonic() - started)
    finally:
        stop(process)
        process.stdout.close()
        process.stderr.close()


def cached_app(timeout: float, whole_end: float) -> str:
    machine = {"arm64": "aarch64", "aarch64": "aarch64", "x86_64": "x86_64"}.get(
        platform.machine()
    )
    system = {"Darwin": "darwin", "Linux": "linux"}.get(platform.system())
    if machine is None or system is None:
        raise RuntimeError("this platform has no declared Nix app")
    command = NIX + ["eval", "--no-update-lock-file", "--raw",
                     f".#apps.{machine}-{system}.default.program"]
    code, output, elapsed = captured(command, min(whole_end, time.monotonic() + timeout))
    if code != 0:
        raise RuntimeError(f"Nix app evaluation exited {code}")
    binary = output.decode("utf-8").strip()
    if not binary.startswith("/nix/store/") or not os.access(binary, os.X_OK):
        raise RuntimeError("Nix app is not prebuilt; run make build-package before profiling")
    print("startup_profile " + json.dumps(
        {"phase": "nix_eval", "elapsed_ms": round(elapsed, 3), "cached": True,
         "binary": binary}, sort_keys=True), flush=True)
    return binary


def run_case(command: list[str], mode: str, history_rows: int, timeout: float,
             whole_end: float) -> dict:
    master = slave = None
    process = connection = server = None
    result = {"mode": mode, "history_rows": history_rows if mode == "live" else 0,
              "first_bytes_ms": None, "raw_mode_ms": None, "first_visible_ms": None,
              "registration_ms": None, "exit_ms": None, "status": "failed"}
    output = bytearray()
    errors = bytearray()
    wire = bytearray()
    with tempfile.TemporaryDirectory(prefix="birc-startup-profile-") as directory:
        try:
            args = ["--nick", "probe", "--channel", "#t", "--frames", "0"]
            history = "none"
            if mode == "live":
                server = socket.socket()
                server.bind(("127.0.0.1", 0))
                server.listen(1)
                server.setblocking(False)
                port = server.getsockname()[1]
                args += ["--connect", "127.0.0.1", "--port", str(port)]
                if history_rows:
                    history = str(Path(directory, "history.log"))
                    with open(history, "x", encoding="utf-8") as fixture:
                        os.chmod(history, 0o600)
                        for index in range(history_rows):
                            fixture.write(f"BIRC2\t127.0.0.1:{port}\t*server*\tSYS\t12:00:00\t"
                                          f"\tsynthetic-startup-{index:04d}\n")
            else:
                args += ["--demo"]
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            env = clean_env(history)
            env["BIRC_HISTORY_LINES"] = str(max(100, history_rows))
            started = time.monotonic()
            deadline = min(started + timeout, whole_end)
            process = subprocess.Popen(command + args, stdin=slave, stdout=slave,
                                       stderr=subprocess.PIPE, env=env,
                                       start_new_session=True, close_fds=True)
            result["popen_ms"] = round(1000 * (time.monotonic() - started), 3)
            result["pid"] = process.pid
            os.close(slave)
            slave = None
            assert process.stderr is not None
            err_fd = process.stderr.fileno()
            open_fds = {master, err_fd}
            quit_at = None
            marker = b"connecting" if mode == "live" else b"demo"
            while True:
                now = time.monotonic()
                if now >= deadline:
                    result["status"] = "timeout"
                    break
                if result["raw_mode_ms"] is None and not termios.tcgetattr(master)[3] & termios.ICANON:
                    result["raw_mode_ms"] = round(1000 * (now - started), 3)
                watched = list(open_fds)
                if server is not None and connection is None:
                    watched.append(server)
                if connection is not None:
                    watched.append(connection)
                for ready in select.select(watched, [], [], min(0.005, deadline - now))[0]:
                    if ready is server:
                        connection, _ = server.accept()
                        connection.setblocking(False)
                    elif ready is connection:
                        try:
                            chunk = connection.recv(65536)
                        except ConnectionResetError:
                            # Immediate quit can reset an unread mock welcome.
                            # Startup markers and successful exit remain required.
                            chunk = b""
                        if chunk:
                            append(wire, chunk, 16384)
                            if result["registration_ms"] is None and b"USER probe" in wire:
                                result["registration_ms"] = round(1000 * (time.monotonic() - started), 3)
                        else:
                            connection.close()
                            connection = None
                            server.close()
                            server = None
                    else:
                        try:
                            chunk = os.read(ready, 65536)
                        except OSError:
                            chunk = b""
                        if not chunk:
                            open_fds.discard(ready)
                        elif ready == master:
                            append(output, chunk)
                            elapsed = round(1000 * (time.monotonic() - started), 3)
                            if result["raw_mode_ms"] is None and not termios.tcgetattr(master)[3] & termios.ICANON:
                                result["raw_mode_ms"] = elapsed
                            if result["first_bytes_ms"] is None:
                                result["first_bytes_ms"] = elapsed
                            if result["first_visible_ms"] is None and marker in output:
                                result["first_visible_ms"] = elapsed
                        else:
                            append(errors, chunk, 65536)
                registered = mode != "live" or result["registration_ms"] is not None
                if quit_at is None and registered and result["first_visible_ms"] is not None:
                    if connection is not None:
                        connection.sendall(b":local 001 probe :startup fixture\r\n")
                    os.write(master, b"/quit\r")
                    quit_at = time.monotonic()
                    deadline = min(deadline, quit_at + 3)
                if process.poll() is not None and err_fd not in open_fds:
                    result["exit_ms"] = round(1000 * (time.monotonic() - started), 3)
                    result["status"] = "ok" if quit_at is not None and process.returncode == 0 else "early_exit"
                    break
            result["returncode"] = process.poll()
            result["terminal_bytes"] = len(output)
            match = PROFILE.search(errors)
            if match is not None:
                result["frame_profile"] = dict(zip(PHASES, map(int, match.groups())))
            elif result["status"] == "ok":
                result["status"] = "missing_frame_profile"
            if result["raw_mode_ms"] is not None and result["first_visible_ms"] is not None:
                result["raw_to_visible_ms"] = round(
                    result["first_visible_ms"] - result["raw_mode_ms"], 3)
            return result
        finally:
            if process is not None:
                stop(process)
                if process.stderr is not None:
                    process.stderr.close()
            if connection is not None:
                connection.close()
            if server is not None:
                server.close()
            if slave is not None:
                os.close(slave)
            if master is not None:
                os.close(master)


def self_test() -> None:
    # Controlled fixtures qualify capture/cleanup without benchmarking birc.
    ready = ("import os,sys,termios,tty;old=termios.tcgetattr(0);tty.setraw(0);"
             "os.write(1,b'demo');os.read(0,6);termios.tcsetattr(0,termios.TCSANOW,old);"
             "os.write(2,b'birc_profile frames=1 prepare_us=1 begin_us=2 draw_us=3 end_us=4 view_us=5\\n')")
    positive = run_case([sys.executable, "-c", ready], "demo", 0, 3, time.monotonic() + 3)
    assert positive["status"] == "ok" and positive["raw_mode_ms"] is not None
    assert positive["first_visible_ms"] is not None and positive["frame_profile"]["view_us"] == 5
    reset = ("import os,socket,struct,sys,termios,time,tty;"
             "s=socket.socket();s.connect(('127.0.0.1',int(sys.argv[sys.argv.index('--port')+1])));"
             "s.sendall(b'USER probe 0 * :probe\\r\\n');old=termios.tcgetattr(0);tty.setraw(0);"
             "os.write(1,b'connecting');os.read(0,6);"
             "s.setsockopt(socket.SOL_SOCKET,socket.SO_LINGER,struct.pack('ii',1,0));s.close();"
             "time.sleep(.05);termios.tcsetattr(0,termios.TCSANOW,old);"
             "os.write(2,b'birc_profile frames=1 prepare_us=1 begin_us=2 draw_us=3 end_us=4 view_us=5\\n')")
    closed = run_case([sys.executable, "-c", reset], "live", 0, 3, time.monotonic() + 3)
    assert closed["status"] == "ok" and closed["registration_ms"] is not None
    early = run_case([sys.executable, "-c", "raise SystemExit(7)"], "demo", 0, 3, time.monotonic() + 3)
    assert early["status"] == "early_exit" and early["returncode"] == 7
    stalled = run_case([sys.executable, "-c", "import time;time.sleep(10)"], "demo", 0, 0.2,
                       time.monotonic() + 0.2)
    assert stalled["status"] == "timeout" and stalled["first_visible_ms"] is None
    try:
        os.kill(stalled["pid"], 0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError("timed-out owned fixture was not reaped")
    print("startup_profile_selftest=ok", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", nargs="?", help="installed app; defaults to build/birc without --nix-run")
    parser.add_argument("--nix-run", action="store_true", help="compare the cached current default Nix app")
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--mode", choices=("demo", "live", "both"), default="both")
    parser.add_argument("--history-rows", type=int, default=0, help="owned live-history rows, never real history")
    parser.add_argument("--timeout", type=float, default=15, help="per-launch bound in seconds")
    parser.add_argument("--self-test", action="store_true", help="test controlled capture and cleanup only")
    args = parser.parse_args()
    if not 1 <= args.samples <= 10 or not 0 <= args.history_rows <= 1024 or not 1 <= args.timeout <= 60:
        parser.error("samples must be 1..10; history rows 0..1024; timeout 1..60")
    if args.self_test:
        self_test()
        return 0
    whole_end = time.monotonic() + 180
    binary = cached_app(args.timeout, whole_end) if args.nix_run else args.binary or "./build/birc"
    if args.nix_run and args.binary and os.path.realpath(args.binary) != os.path.realpath(binary):
        parser.error("--nix-run must compare the same installed app, not another build")
    commands = [("installed", [binary])]
    if args.nix_run:
        commands.append(("nix_run_cached", NIX + ["run", "--no-update-lock-file", ".", "--"]))
    modes = ("demo", "live") if args.mode == "both" else (args.mode,)
    for sample in range(args.samples + 1):
        for mode in modes:
            for launcher, command in commands if sample % 2 == 0 else reversed(commands):
                result = run_case(command, mode, args.history_rows, args.timeout, whole_end)
                result.update(launcher=launcher, sample=sample, warmup=sample == 0)
                print("startup_profile " + json.dumps(result, sort_keys=True), flush=True)
                if result["status"] != "ok":
                    return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, RuntimeError, TimeoutError, subprocess.TimeoutExpired) as error:
        print(f"startup_profile: {error}", file=sys.stderr)
        raise SystemExit(1)
