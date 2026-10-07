#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""True upload frame qualification through real first/live Timui.frame.

Every key arrives as physical terminal bytes (typed text, Enter, F8, Esc);
the fixture never builds key structs. The driver owns a recording fake
helper and synthetic files, and asserts warning-before-F8, coalesced
Enter+F8 no-launch, launch exactly-once, Esc-after-held-start discard,
right-target outs, and the exact ledger total with unknown-row rejection.
No IRC, no public service, no user files, no private chat URLs. On failure,
retain the terminal, ledger, and synthetic files under build/.

WS_UPLOAD_FRAME_MODE selects fake-helper behavior; every mode runs the
full script to the closure stage. normal (default) must exit 0 with the
exact 6-row ledger and a promptly quiet group. linger (the once helper
detaches a rowless grandchild that waits on a cooperative release flag
with a never-disabled 90s alarm backstop; the ledger stays exact-6)
must exit nonzero via group-closure detection. late (the once helper
detaches a grandchild that awaits the closure.entered barrier, then
runs the owned no-op Cards fake on a synthetic URL) must exit 0 with
the upload total still six and the final Cards ledger holding exactly
that delayed launch. Non-normal modes are driver-qualification modes,
not fixture scope.

Ownership (from pinned bend2/effs/process_run.c): posix_spawn sets only
SIGDEF/CLOEXEC, no setsid/setpgid, so helpers inherit the fixture
process group; the fixture waitpids each direct child and SIGKILLs it
on timeout/error. The driver therefore NEVER kills logged PIDs: a
logged PID is not a process owner, and only the fixture, the true
parent, reaps or kills. Closure is proven over a test-only group owned
by a LIVING guardian: the guardian creates group G, the fixture joins
it, the guardian leaves but stays alive holding pid G (unreusable),
and the driver probes group existence with signal 0 only while
asserting the guardian unreaped. An empty group with a living
guardian proves closure: no live member means nothing can fork a late
straggler (modulo foreign setpgid into G, which nothing here does).
Alarms are never disabled; release flags are touched before main is
killed so synthetics exit cooperatively.
"""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

from split_identity import Screen

ROOT = Path(__file__).resolve().parents[2]
F8 = b"\x1b[19~"
ESC = b"\x1b"

FAKE_HELPER = r'''
import json, os, signal, sys, time
from pathlib import Path
signal.signal(signal.SIGALRM, signal.SIG_DFL)
signal.alarm(10)
mode = os.environ.get("WS_UPLOAD_FRAME_MODE", "normal")
folder = Path(os.environ["BIRC_UPLOAD_TEST_DIR"])
path = Path(sys.argv[2]) if len(sys.argv) == 3 else Path("invalid")
kind = path.name.split(" ", 1)[0]
code = 0
def detached():
    first = os.fork()
    if first != 0:
        os.waitpid(first, 0)
        return False
    second = os.fork()
    if second != 0:
        os._exit(0)
    for fd in (0, 1, 2):
        try: os.close(fd)
        except OSError: pass
    return True
def record(event, extra=None):
    row = {"event": event, "kind": kind, "args": sys.argv[1:], "pid": os.getpid()}
    if extra: row.update(extra)
    fd = os.open(folder / "helpers.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try: os.write(fd, (json.dumps(row) + "\n").encode())
    finally: os.close(fd)
record("start")
try:
    assert sys.argv[1] == "--local" and path.is_file()
    if kind == "held":
        deadline = time.monotonic() + 8
        while not (folder / "held.release").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        if not (folder / "held.release").exists():
            raise SystemExit(8)
    output = "https://0x0.st/s/synthetic/" + kind + path.suffix.lower() + "\n"
    record("result")
    try: os.write(1, output.encode())
    except BrokenPipeError: pass
except SystemExit as done:
    code = done.code if isinstance(done.code, int) else 1
    raise
except BaseException:
    code = 1
    raise
finally:
    record("exit", {"code": code})
    if mode == "linger" and kind == "once" and detached():
        signal.alarm(90)
        end = time.monotonic() + 89
        while not (folder / "linger.release").exists() and time.monotonic() < end:
            time.sleep(0.1)
        os._exit(0)
    if mode == "late" and kind == "once" and detached():
        signal.alarm(60)
        while not (folder / "closure.entered").exists():
            time.sleep(0.05)
        cards = folder / "birc-cards"
        os.execv(str(cards), [str(cards), "https://0x0.st/s/synthetic/late"])
'''

MARKERS = (
    "frame_coal_staged phase=confirm presented=0\n",
    "frame_held_staged phase=confirm presented=1\n",
    "frame_held_armed phase=confirm presented=1\n",
    "frame_held_fired phase=busy\n",
    "frame_held_escaped phase=busy allowed=0\n",
    "frame_held_routed phase=idle discarded=1 url=0\n",
    "frame_once_staged phase=confirm presented=0\n",
    "frame_once_armed phase=confirm presented=1\n",
    "frame_once_fired phase=busy\n",
    "frame_once_routed target=#a\n",
    "ws_upload_frame=ok\n",
)

# Exact helper accounting: every recorded row must match this shape, every
# kind/event must be known, and the total must equal the completed script.
KNOWN_KINDS = {"once", "held"}
KNOWN_EVENTS = {"start", "result", "exit"}
WANT_COUNTS = {("once", "start"): 1, ("once", "result"): 1, ("once", "exit"): 1,
               ("held", "start"): 1, ("held", "result"): 1, ("held", "exit"): 1}
WANT_TOTAL = 6


def url_for(kind):
    return "https://0x0.st/s/synthetic/" + kind + ".txt"


FAKE_CARDS = r'''
import json, os, signal, sys
from pathlib import Path
signal.signal(signal.SIGALRM, signal.SIG_DFL)
signal.alarm(10)
folder = Path(os.environ["BIRC_UPLOAD_TEST_DIR"])
row = {"event": "launch", "exe": sys.argv[0], "args": sys.argv[1:],
       "pid": os.getpid()}
fd = os.open(folder / "cards.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
try: os.write(fd, (json.dumps(row) + "\n").encode())
finally: os.close(fd)
'''

SYNTHETIC_URL_PREFIX = "https://0x0.st/s/synthetic/"
CARDS_LAUNCH_BOUND = 4
READY = "ws_upload_frame=ready\n"

# Test-only living group owner: creates group G (own pid), waits for the
# driver to confirm the fixture joined, leaves G for the driver's group,
# then holds pid G unreusable until stdin EOF. Never touches the pty,
# never launches children, never disables anything.
GUARDIAN = r'''
import os, sys
driver_pgid = int(sys.argv[1])
os.setpgid(0, 0)
sys.stdout.write("GUARD READY\n")
sys.stdout.flush()
line = sys.stdin.readline()
assert line.strip() == "JOINED", "guardian protocol error"
os.setpgid(0, driver_pgid)
sys.stdout.write("GUARD LEFT\n")
sys.stdout.flush()
for line in sys.stdin:
    pass
'''


def fixture_ok(raw: bytes | bytearray, saved_oflag: int) -> bool:
    """Match only the final token with its saved terminal newline mapping."""
    ending = b"\r\n" if saved_oflag & termios.OPOST and saved_oflag & termios.ONLCR else b"\n"
    return MARKERS[10].encode()[:-1] + ending in raw


def fixture_ok_controls() -> None:
    lf = MARKERS[10].encode()
    crlf = lf[:-1] + b"\r\n"
    cooked = termios.OPOST | termios.ONLCR
    for flags in (0, termios.OPOST, termios.ONLCR):
        assert fixture_ok(lf, flags), "final marker LF control failed"
        assert not fixture_ok(crlf, flags), "final marker accepted unexpected CRLF"
    assert fixture_ok(crlf, cooked), "final marker CRLF control failed"
    assert not fixture_ok(lf, cooked), "final marker accepted unexpected LF"
    assert not fixture_ok(b"", cooked), "final marker accepted missing token"
    assert not fixture_ok(b"ws_upload_frame=ok-fake\r\n", cooked), "final marker accepted forged token"
    assert not fixture_ok(b"ws_upload_frame=ok\x1b[0m\r\n", cooked), "final marker stripped a control"


class Client:
    def __init__(self, binary, folder, once_url):
        self.folder = folder
        folder.mkdir(parents=True)
        self.helper = folder / "birc-upload"
        self.helper.write_text("#!" + sys.executable + "\n" + FAKE_HELPER)
        self.helper.chmod(0o755)
        self.cards_helper = folder / "birc-cards"
        self.cards_helper.write_text("#!" + sys.executable + "\n" + FAKE_CARDS)
        self.cards_helper.chmod(0o755)
        self.ambient_cards = os.environ.get("BIRC_CARDS_HELPER")
        self.failed = False
        self.verified = False
        self.paths = {}
        self.raw = bytearray()
        self.master, slave = pty.openpty()
        self.saved = termios.tcgetattr(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        env = {**os.environ, "TERM": "xterm-256color", "BIRC_IMAGES": "off",
               "BIRC_CARDS": "off", "BIRC_HISTORY": "none",
               "BIRC_PREFERENCES": "none", "BIRC_IMAGE_CACHE": "none",
               "BIRC_UPLOAD_HELPER": str(self.helper),
               "BIRC_CARDS_HELPER": str(self.cards_helper),
               "BIRC_UPLOAD_TEST_DIR": str(folder), "PATH": str(folder)}
        for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH_SECRET_FD",
                     "BIRC_AUTH_EVENT_FD", "BIRC_NOTIFY_HELPER",
                     "BIRC_MEDIA_HELPER", "BIRC_DIE_AFTER_OPEN",
                     "BIRC_FRAME_PROFILE", "TIMUI_TRACE"):
            env.pop(name, None)
        # Living guardian first: it creates group G (its own pid) in our
        # session and holds pid G unreusable through cleanup. Same
        # session throughout, so the fixture keeps its exact ctty/pty
        # behavior; only its process group changes.
        try:
            self.guard = subprocess.Popen(
                [sys.executable, "-c", GUARDIAN, str(os.getpgrp())],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True,
            )
        except Exception:
            os.close(self.master)
            raise
        self.gid = self.guard.pid
        try:
            assert self.guard_line(5) == "GUARD READY\n", "guardian did not arm"
            assert self.guard.poll() is None, "guardian exited while arming"
            gid = self.gid
            self.proc = subprocess.Popen(
                [str(binary), "run", once_url],
                stdin=slave, stdout=slave, stderr=slave, env=env,
                preexec_fn=lambda: os.setpgid(0, gid),
            )
        except Exception:
            os.close(self.master)
            self.stop_guard()
            raise
        finally:
            os.close(slave)
        try:
            self.confirm_joined()
            self.guard.stdin.write("JOINED\n")
            self.guard.stdin.flush()
            assert self.guard_line(5) == "GUARD LEFT\n", "guardian did not leave"
        except Exception:
            if self.proc.poll() is None:
                self.proc.kill()
            self.stop_guard()
            raise

    def guard_line(self, seconds):
        """Bounded causal read of one guardian handshake line."""
        assert self.guard.poll() is None, "guardian exited mid-handshake"
        ready, _, _ = select.select([self.guard.stdout], [], [], seconds)
        assert ready, "guardian handshake timed out"
        return self.guard.stdout.readline()

    def confirm_joined(self):
        """Causal wait until the fixture's group is G: preexec runs
        before exec, so getpgid observes the join without reaping."""
        deadline = time.monotonic() + 5
        while True:
            try:
                joined = os.getpgid(self.proc.pid) == self.gid
            except ProcessLookupError:
                joined = False
            if joined:
                return
            assert self.guard.poll() is None, "guardian exited before join"
            assert time.monotonic() < deadline, "fixture never joined group G"
            time.sleep(0.02)

    def stop_guard(self):
        """EOF the guardian (its only exit path), reap it, surface failure."""
        try:
            self.guard.stdin.close()
        except (OSError, ValueError):
            pass
        try:
            code = self.guard.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.guard.kill()
            code = self.guard.wait(timeout=5)
        if code != 0:
            tail = self.guard.stderr.read()[-500:]
            print(f"ws_upload_frame: guardian exited {code}: {tail!r}",
                  file=sys.stderr, flush=True)
            raise AssertionError(f"guardian exited {code}")

    def pump(self, duration=0.05):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            if select.select([self.master], [], [], 0.01)[0]:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    continue
                self.raw.extend(data)

    def until(self, predicate, label, seconds=10):
        deadline = time.monotonic() + seconds
        while not predicate() and time.monotonic() < deadline:
            self.pump()
            assert self.proc.poll() is None, "fixture exited while waiting for " + label
        assert predicate(), "timeout: " + label

    def marker(self, text):
        encoded = text.encode()
        self.until(lambda: encoded in self.raw, "marker " + text.strip())

    def view(self):
        """Current screen with fixture markers stripped (markers are sync
        bytes, never painted content; frame output never contains them)."""
        data = bytes(self.raw)
        for text in (READY,) + MARKERS:
            data = data.replace(text.encode(), b"")
        screen = Screen()
        screen.feed(data)
        return screen.text()

    def painted(self, *markers):
        self.until(lambda: all(marker in self.view() for marker in markers),
                   "paint " + repr(markers))

    def file(self, kind):
        path = self.folder / (kind + " file.txt")
        path.write_bytes(b"synthetic frame upload fixture\n")
        self.paths[kind] = path
        return path

    def write(self, data):
        assert os.write(self.master, data) == len(data), "fixture input write was incomplete"

    def command(self, text):
        self.write(text.encode() + b"\r")

    def records(self):
        """Strict ledger parse: any malformed or unknown row fails."""
        ledger = self.folder / "helpers.jsonl"
        if not ledger.exists():
            return []
        rows = []
        for line in ledger.read_text().split("\n"):
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                raise AssertionError("ledger has non-JSON row: " + line[:120])
            assert isinstance(row, dict), "ledger row is not an object"
            event, kind = row.get("event"), row.get("kind")
            assert event in KNOWN_EVENTS, "ledger has unknown event: " + line[:160]
            assert kind in KNOWN_KINDS, "ledger has unknown kind: " + line[:160]
            args = row.get("args")
            assert isinstance(args, list) and len(args) == 2, "ledger args malformed"
            assert args[0] == "--local", "helper received non-local argv"
            assert str(args[1]).startswith(str(self.folder) + os.sep), "helper path escaped synthetic dir"
            assert isinstance(row.get("pid"), int) and row["pid"] > 0, "helper pid malformed"
            if event == "exit":
                assert row.get("code") == 0, "helper exited nonzero: " + line[:160]
            rows.append(row)
        return rows

    def counts(self):
        found = {}
        for row in self.records():
            key = (row["kind"], row["event"])
            found[key] = found.get(key, 0) + 1
        return found

    def ledger_total(self):
        """Exact-TOTAL oracle: every count exact, total exact, nothing else."""
        rows = self.records()
        assert len(rows) == WANT_TOTAL, f"ledger total {len(rows)} != {WANT_TOTAL}"
        found = self.counts()
        assert found == WANT_COUNTS, f"ledger counts wrong: {found}"
        for row in self.records():
            if row["event"] == "start":
                want = ["--local", str(self.paths[row["kind"]])]
                assert row["args"] == want, "helper received a changed path"
        ledger = self.folder / "helpers.jsonl"
        assert ledger.stat().st_mode & 0o777 == 0o600, "ledger is not owner-only"

    def cards_records(self):
        path = self.folder / "cards.jsonl"
        if not path.exists():
            return []
        rows = []
        for line in path.read_text().splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            assert row.get("event") == "launch", "cards ledger event unknown"
            assert row.get("exe") == str(self.cards_helper), "cards helper is not the owned fake"
            if self.ambient_cards is not None:
                assert row.get("exe") != self.ambient_cards, "ambient cards helper impostor ran"
            args = row.get("args")
            assert isinstance(args, list) and args, "cards ledger args malformed"
            for arg in args:
                if arg == "--local":
                    continue
                if str(arg).startswith(("http://", "https://")):
                    assert str(arg).startswith(SYNTHETIC_URL_PREFIX), "cards URL escaped synthetic space"
                else:
                    assert str(arg).startswith(str(self.folder) + os.sep), "cards path escaped synthetic dir"
            assert isinstance(row.get("pid"), int) and row["pid"] > 0, "cards pid malformed"
            rows.append(row)
        return rows

    def cards_ledger(self):
        """Owned-fake isolation: every cards launch ran the owned no-op fake,
        bounded, synthetic-only; an ambient helper never ran."""
        rows = self.cards_records()
        assert len(rows) <= CARDS_LAUNCH_BOUND, f"cards launches {len(rows)} exceed bound"
        ledger = self.folder / "cards.jsonl"
        if rows:
            assert ledger.stat().st_mode & 0o777 == 0o600, "cards ledger is not owner-only"

    def private(self):
        assert str(self.folder) not in self.view(), "screen exposed the complete local path"
        assert "Traceback" not in self.raw.decode("utf-8", "replace"), "helper traceback reached output"

    def scan_pids(self):
        """Tolerant PID harvest from both ledgers: malformed lines and
        unknown event/kind rows are skipped here (the final strict ledger
        judges them), so a parse error never aborts the termination poll
        before any PID is checked. Harvested PIDs are polled with signal
        0 only; a logged PID is never a license to kill."""
        pids = set()
        for name in ("helpers.jsonl", "cards.jsonl"):
            path = self.folder / name
            if not path.exists():
                continue
            for line in path.read_text().splitlines():
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(row, dict):
                    continue
                if name == "cards.jsonl":
                    if row.get("event") != "launch":
                        continue
                elif row.get("event") not in KNOWN_EVENTS or row.get("kind") not in KNOWN_KINDS:
                    continue
                pid = row.get("pid")
                if isinstance(pid, int) and pid > 0:
                    pids.add(pid)
        return pids

    @staticmethod
    def alive(pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        except OSError:
            return False
        return True

    def group_alive(self):
        """Non-destructive group-G existence probe (signal 0 only). The
        guardian is asserted unreaped first, so pid G is held and the
        probe cannot hit a reused ID; nothing destructive is ever sent."""
        assert self.guard.poll() is None, "guardian died: group seam broken"
        try:
            os.killpg(self.gid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        except OSError:
            return False
        return True

    def verify_closure(self, seconds=10, strict=True):
        """Bounded authoritative closure (no process-list scan, no argument
        reads, NOTHING destructive: the driver owns no helper handles and
        a logged PID is not a process owner, so it never kills; only the
        fixture, the true parent, reaps or kills per process_run.c).
        One loop polls harvested PIDs (signal 0, rescanned every tick)
        for precise diagnostics AND group-G existence for authority: an
        empty group with a living guardian PROVES closure, because no
        live member means nothing can fork a late straggler. No
        settle-sleep carries proof; the deadline is a failure bound,
        not a correctness delay. strict=True raises (fails a
        previously-successful run); strict=False warns (preserves an
        existing failure). The closure.entered barrier is published first
        so a late descendant can synchronize its delayed launch with the
        closure stage instead of guessing a sleep."""
        (self.folder / "closure.entered").touch(exist_ok=True)
        seen = set()
        pending = set()
        grouped = True
        deadline = time.monotonic() + seconds
        while True:
            seen |= self.scan_pids()
            pending = {pid for pid in seen if self.alive(pid)}
            grouped = self.group_alive()
            if not pending and not grouped:
                break
            if time.monotonic() >= deadline:
                break
            time.sleep(0.05)
        problems = []
        if pending:
            problems.append(f"helper PIDs still alive: {sorted(pending)}")
        elif grouped:
            problems.append(f"fixture group {self.gid} still alive after closure")
        if problems:
            if strict:
                raise AssertionError("; ".join(problems))
            print("ws_upload_frame: " + "; ".join(problems), file=sys.stderr, flush=True)
        return problems

    def wait_exit(self):
        deadline = time.monotonic() + 10
        while self.proc.poll() is None and time.monotonic() < deadline:
            self.pump()
        assert self.proc.poll() == 0, "fixture exited nonzero"
        self.pump(0.2)
        assert termios.tcgetattr(self.master) == self.saved, "exit did not restore terminal state"

    def close(self):
        # Cooperative release first so synthetics exit themselves; the
        # native main is killed only after its helpers were released.
        (self.folder / "held.release").touch(exist_ok=True)
        (self.folder / "linger.release").touch(exist_ok=True)
        if self.proc.poll() is None:
            self.proc.kill()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        # Post-release group check before the guardian retires: the
        # guardian stays living through release and main reap, then a
        # bounded group-quiet verification runs while pid G is still
        # held. Skipped only when strict closure already passed, which
        # is sound: releases cause exits, never launches, so proven
        # quiet stays quiet. Warn-only always: cleanup failure preserves
        # the original failure and its evidence.
        if not self.verified:
            try:
                self.verify_closure(seconds=5, strict=False)
            except Exception as unreported:
                print(f"ws_upload_frame: {unreported}", file=sys.stderr, flush=True)
        # The guardian outlives verification, then is reaped; a bad
        # guardian fails a clean run but never masks an earlier failure.
        try:
            self.stop_guard()
        except Exception as bad_guard:
            print(f"ws_upload_frame: {bad_guard}", file=sys.stderr, flush=True)
            if not self.failed:
                raise
        try:
            os.close(self.master)
        except OSError:
            pass

    def evidence(self):
        (self.folder / "screen.raw").write_bytes(self.raw)


def main(binary):
    fixture_ok_controls()
    mode = os.environ.get("WS_UPLOAD_FRAME_MODE", "normal")
    assert mode in ("normal", "linger", "late"), f"unknown WS_UPLOAD_FRAME_MODE={mode}"
    folder = Path(tempfile.mkdtemp(prefix="ws-upload-frame-pty-", dir=ROOT / "build"))
    once_url = url_for("once")
    success = False
    client = Client(binary, folder / "run", once_url)
    try:
        once = client.file("once")
        held = client.file("held")
        # Frame one: a coalesced Enter+F8 cannot authorize an unseen warning.
        # The first request is the held file from the outset; later frames
        # continue this SAME request (no replacement command: a pending
        # upload suppresses Enter, so a second /upload would prove nothing).
        # Ready ack first: Timui.open flushes pending input, so a blind sleep
        # can lose the coalesced write before the first frame reads it.
        client.marker(READY)
        client.write(("/upload " + shlex.quote(str(held))).encode() + b"\r" + F8)
        client.marker(MARKERS[0])
        assert not client.records(), "coalesced F8 started a helper"
        # Held case: retained warning painted, completed warning frame,
        # F8 fires once, Esc discards.
        client.marker(MARKERS[1])
        client.marker(MARKERS[2])
        client.painted("0x0.st", "F8", "Esc", "#a", "held file", "(files=1)")
        client.private()
        client.write(F8)
        client.marker(MARKERS[3])
        client.until(lambda: client.counts().get(("held", "start"), 0) == 1, "held helper start")
        assert client.counts().get(("held", "exit"), 0) == 0, "fixture did not hold the helper"
        client.write(ESC)
        client.marker(MARKERS[4])
        (client.folder / "held.release").touch()
        client.marker(MARKERS[5])
        client.painted("canceled or destination changed")
        client.pump(0.3)
        assert "https://0x0.st/" not in client.view(), "discarded upload reached the screen"
        client.private()
        # Once case: a later physical F8 authorizes exactly one send to #a.
        client.command("/upload " + shlex.quote(str(once)))
        client.marker(MARKERS[6])
        client.marker(MARKERS[7])
        client.painted("0x0.st", "F8", "Esc", "#a", "once file", "(files=1)")
        client.private()
        client.write(F8)
        client.marker(MARKERS[8])
        client.marker(MARKERS[9])
        client.painted(once_url)
        assert client.view().count(once_url) == 1, "upload URL sent more than once"
        # Strict ledger oracle with stability check.
        client.ledger_total()
        client.pump(0.3)
        client.ledger_total()
        client.wait_exit()
        # Single closure owner, then the final strict ledgers: a helper
        # lineage still alive here fails this run even though every
        # screen assertion passed.
        client.verify_closure()
        client.verified = True
        client.ledger_total()
        client.cards_ledger()
        if mode == "late":
            rows = client.cards_records()
            assert len(rows) == 1, f"late cards launches {len(rows)} != 1"
            assert rows[0]["args"] == ["https://0x0.st/s/synthetic/late"], "late cards argv wrong"
            assert rows[0]["exe"] == str(client.cards_helper), "late launch is not the owned fake"
        assert fixture_ok(client.raw, client.saved[1]), "fixture ok marker missing"
        client.private()
        success = True
    except Exception:
        client.failed = True
        client.evidence()
        print(f"ws_upload_frame evidence={client.folder}", file=sys.stderr, flush=True)
        raise
    finally:
        client.close()
        if success:
            shutil.rmtree(folder)
    print("ws_upload_frame=ok", flush=True)


if __name__ == "__main__":
    try:
        def wall_bound(_signal, _frame):
            raise TimeoutError("upload frame PTY wall-clock bound")
        signal.signal(signal.SIGALRM, wall_bound)
        signal.alarm(100)
        main(Path(sys.argv[1] if len(sys.argv) > 1 else "./build/ws_upload_frame").resolve())
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print("ws_upload_frame: " + str(error), file=sys.stderr)
        raise SystemExit(1)
