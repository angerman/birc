#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Owned loopback recovery: repeat authentication and full keyed joins.

No public IRC, user credentials, Keychain, or user files. All child/FD ownership
is established before startup and released even when accept or registration fails.
Captured wire is synthetic, but assertions never print credential-bearing bytes.
"""
from __future__ import annotations

import base64
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
import tomllib


PREFIX = b"NickServ!service@services.test"


class Peer:
    def __init__(self, program, directory, auth="nickserv", preferences=False):
        self.proc = None
        self.conn = None
        self.master = self.event = None
        self.server = socket.socket()
        self.wire = bytearray()
        self.screen = bytearray()
        self.events = bytearray()
        self.event_closed = False
        self.directory = directory
        self.helper_ledger = Path(directory) / "helpers.jsonl"
        self.preferences = preferences
        self.auth = auth
        self.nick = b"probe"
        slave = secret_r = secret_w = event_w = None
        try:
            self.server.bind(("127.0.0.1", 0))
            self.server.listen(3)
            self.server.setblocking(False)
            self.master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            self.saved_terminal = termios.tcgetattr(slave)
            secret_r, secret_w = os.pipe()
            self.event, event_w = os.pipe()
            os.write(secret_w, b"synthetic-secret")
            os.close(secret_w)
            secret_w = None
            env = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none",
                   "BIRC_IMAGES": "off", "BIRC_PREFERENCES": "none",
                   "XDG_CONFIG_HOME": directory, "BIRC_AUTH_SECRET_FD": str(secret_r),
                   "BIRC_AUTH_EVENT_FD": str(event_w)}
            if preferences:
                source = Path(__file__).resolve().parents[2] / "src/launcher/preferences_birc.py"
                helper = Path(directory) / "preferences-helper"
                helper.write_text(f"#!{sys.executable}\n"
                                  "import json, os, runpy, signal, sys\n"
                                  "signal.signal(signal.SIGALRM, signal.SIG_DFL)\n"
                                  "signal.alarm(6)\n"
                                  "def record(event, code=None):\n"
                                  f"    fd = os.open({str(self.helper_ledger)!r}, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)\n"
                                  "    try:\n"
                                  "        row = {'event': event, 'mode': sys.argv[1], 'pid': os.getpid(), 'pgid': os.getpgrp(), 'code': code}\n"
                                  "        os.write(fd, (json.dumps(row) + '\\n').encode())\n"
                                  "    finally:\n"
                                  "        os.close(fd)\n"
                                  "record('start')\n"
                                  f"code = runpy.run_path({str(source)!r})['main']()\n"
                                  "record('done', code)\n"
                                  "raise SystemExit(code)\n")
                helper.chmod(0o700)
                env.update(BIRC_PREFERENCES=str(Path(directory) / "preferences.toml"),
                           BIRC_PREFS_HELPER=str(helper))
            for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH"):
                env.pop(name, None)
            args = [program, "--plain", "--connect", "127.0.0.1", "--port",
                    str(self.server.getsockname()[1]), "--nick", "probe", "--channel",
                    "#start", "--frames", "0", "--auth", auth, "--sasl-user",
                    "account", "--nickserv-prefix", PREFIX.decode(), "--nickserv-success",
                    "Account confirmed"]
            self.proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                                         env=env, pass_fds=(secret_r, event_w), start_new_session=True)
        except BaseException:
            self.close()
            raise
        finally:
            for fd in (slave, secret_r, secret_w, event_w):
                if fd is not None:
                    os.close(fd)

    def close_connection(self):
        if self.conn is not None:
            self.conn.close()
            self.conn = None

    def close(self):
        self.close_connection()
        self.server.close()
        try:
            if self.proc is not None:
                # Only this fixture's isolated session owns this group. A
                # helper can outlive an early app exit; include descendants.
                try:
                    os.killpg(self.proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    try:
                        self.proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        try:
                            os.killpg(self.proc.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        self.proc.wait(timeout=2)
                finally:
                    try:
                        os.killpg(self.proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
        finally:
            for name in ("master", "event"):
                fd = getattr(self, name)
                if fd is not None:
                    os.close(fd)
                    setattr(self, name, None)

    def helpers_done(self):
        if not self.preferences:
            return
        assert self.helper_ledger.exists(), "preferences helper was not exercised"
        assert self.helper_ledger.stat().st_size <= 65536, "bounded helper ledger"
        rows = [json.loads(line) for line in self.helper_ledger.read_text().splitlines()]
        starts = [(row["pid"], row["pgid"], row["mode"]) for row in rows if row["event"] == "start"]
        dones = [(row["pid"], row["pgid"], row["mode"]) for row in rows if row["event"] == "done"]
        assert any(mode == "read" for _, _, mode in starts), "real preferences read was not exercised"
        assert sorted(starts) == sorted(dones) and len(rows) == 2 * len(starts), "helper lifecycle incomplete"
        assert all(row["code"] == 0 for row in rows if row["event"] == "done"), "preferences helper failed"
        assert all(group == self.proc.pid for _, group, _ in starts), "helper escaped owned app session"
        for pid, _, _ in starts:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                continue
            raise AssertionError("helper was not reaped on normal quit")

    def pump(self, duration=0.05, accepting=False):
        fds = [self.master]
        if self.conn is not None:
            fds.append(self.conn)
        if not self.event_closed:
            fds.append(self.event)
        if accepting:
            fds.append(self.server)
        ready, _, _ = select.select(fds, [], [], duration)
        for fd in ready:
            if fd is self.server:
                self.conn, _ = self.server.accept()
                self.conn.setblocking(False)
            elif fd is self.conn:
                data = self.conn.recv(65536)
                if data:
                    self.wire.extend(data)
                    assert len(self.wire) <= 65536, "bounded synthetic wire"
            elif fd == self.event:
                data = os.read(self.event, 64)
                self.events.extend(data)
                self.event_closed = not data
            else:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    data = b""
                self.screen.extend(data)
                if len(self.screen) > 262144:
                    del self.screen[:-262144]

    def until(self, predicate, label, timeout=5, accepting=False):
        deadline = time.monotonic() + timeout
        while not predicate() and time.monotonic() < deadline:
            assert self.proc.poll() is None, "child exited during " + label
            self.pump(0.05, accepting)
        assert predicate(), "timeout: " + label

    def quiet(self, duration=0.25):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            self.pump(min(0.05, max(0, deadline - time.monotonic())))

    def accept(self):
        self.wire.clear()
        self.until(lambda: self.conn is not None, "owned connection", 8, True)
        self.until(lambda: b"USER " + self.nick + b" " in self.wire, "registration")

    def send(self, line):
        self.conn.settimeout(2)
        try:
            self.conn.sendall(line + b"\r\n")
        finally:
            self.conn.setblocking(False)

    def command(self, text, wire):
        start = len(self.wire)
        os.write(self.master, text.encode() + b"\r")
        self.until(lambda: wire + b"\r\n" in self.wire[start:], "composer command")

    def notice(self, prefix, body):
        self.send(b":" + prefix + b" NOTICE " + self.nick + b" :" + body)

    def welcome(self, assigned_nick):
        self.nick = assigned_nick or self.nick
        self.send(b":irc 001 " + self.nick + b" :welcome")

    def authenticate(self, expected, assigned_nick=None):
        if self.auth == "sasl":
            self.authenticate_sasl(assigned_nick)
        else:
            self.authenticate_nickserv(assigned_nick)
        self.until(lambda: all(line + b"\r\n" in self.wire for line in expected), "recovery JOIN set")
        self.quiet()
        joins = [line for line in bytes(self.wire).split(b"\r\n") if line.startswith(b"JOIN ")]
        assert joins == expected, "recovery JOIN set/order differs"
        for line in expected:
            name = line.split()[1]
            self.send(b":" + self.nick + b"!u@h JOIN :" + name)

    def authenticate_sasl(self, assigned_nick):
        assert self.wire.count(b"CAP REQ :sasl\r\n") == 1, "SASL not requested on this connection"
        assert b"CAP END\r\n" not in self.wire, "registration ended before SASL"
        self.send(b":irc CAP " + self.nick + b" LS :sasl=PLAIN server-time message-tags")
        self.send(b":irc CAP " + self.nick + b" ACK :server-time message-tags")
        self.quiet()
        assert b"AUTHENTICATE " not in self.wire, "unrelated ACK started SASL"
        self.send(b":irc CAP " + self.nick + b" ACK :sasl")
        self.until(lambda: b"AUTHENTICATE PLAIN\r\n" in self.wire, "SASL mechanism")
        self.send(b"AUTHENTICATE +")
        payload = base64.b64encode(b"\0account\0synthetic-secret")
        self.until(lambda: b"AUTHENTICATE " + payload + b"\r\n" in self.wire, "SASL response")
        self.send(b":hostile!u@h 903 " + self.nick + b" :fake success")
        self.send(b":irc 903 other :wrong recipient")
        self.quiet()
        assert b"CAP END\r\n" not in self.wire, "untrusted SASL success released registration"
        assert b"JOIN " not in self.wire, "JOIN preceded SASL success"
        self.send(b":irc 900 " + self.nick + b" " + self.nick + b"!u@h account :You are now logged in")
        self.send(b":irc 903 " + self.nick + b" :SASL authentication successful")
        self.until(lambda: b"CAP END\r\n" in self.wire, "SASL completion")
        self.quiet()
        assert b"JOIN " not in self.wire, "JOIN preceded welcome"
        self.welcome(assigned_nick)
        assert self.wire.count(b"AUTHENTICATE " + payload + b"\r\n") == 1, "SASL response repeated"
        assert b"PRIVMSG NickServ " not in self.wire, "successful SASL redundantly identified"

    def authenticate_nickserv(self, assigned_nick):
        self.welcome(assigned_nick)
        self.until(lambda: b"PRIVMSG NickServ :HELP\r\n" in self.wire, "NickServ probe")
        assert b"JOIN " not in self.wire, "JOIN preceded NickServ verification"
        self.notice(b"NickServ!hostile@evil.test", b"Help")
        self.quiet()
        assert b"IDENTIFY " not in self.wire, "hostile probe released credentials"
        self.notice(PREFIX, b"Help")
        self.until(lambda: b"PRIVMSG NickServ :IDENTIFY account synthetic-secret\r\n" in self.wire,
                   "trusted identify")
        assert b"JOIN " not in self.wire, "JOIN preceded confirmation"
        self.notice(b"NickServ!hostile@evil.test", b"Account confirmed")
        self.quiet()
        assert b"JOIN " not in self.wire, "hostile confirmation released JOIN"
        self.notice(PREFIX, b"Account confirmed")
        self.until(lambda: b"JOIN " in self.wire, "verified NickServ completion")
        assert self.wire.count(b"PRIVMSG NickServ :HELP\r\n") == 1, "probe repeated"
        assert self.wire.count(b"PRIVMSG NickServ :IDENTIFY ") == 1, "identify repeated"


def deadline(_signum, _frame):
    raise TimeoutError("reconnect recovery total wall deadline")


def case(program, auth, preferences=False):
    with tempfile.TemporaryDirectory(prefix="birc-recovery-") as directory:
        peer = Peer(program, directory, auth, preferences)
        try:
            peer.accept()
            peer.authenticate([b"JOIN #start"])
            peer.until(lambda: peer.event_closed, "one-shot auth event")
            assert peer.events == b"BIRC_AUTH_OK\n", "auth event edge differs"
            peer.command("/join #other runtime-key", b"JOIN #other runtime-key")
            peer.send(b":probe!u@h JOIN :#other")
            peer.command("/join #third third-key", b"JOIN #third third-key")
            peer.send(b":probe!u@h JOIN :#third")
            peer.command("/part #third", b"PART #third")
            os.write(peer.master, b"/reconnect\r")
            peer.close_connection()
            peer.accept()
            peer.authenticate([b"JOIN #start", b"JOIN #other runtime-key"])
            peer.command("/part #start", b"PART #start")
            peer.conn.shutdown(socket.SHUT_RDWR)
            peer.close_connection()
            peer.accept()
            peer.authenticate([b"JOIN #other runtime-key"], assigned_nick=b"Guest42")
            assert peer.events == b"BIRC_AUTH_OK\n", "reconnect replayed wrapper success edge"
            os.write(peer.master, b"/quit\r")
            end = time.monotonic() + 5
            while peer.proc.poll() is None and time.monotonic() < end:
                peer.pump()
            assert peer.proc.wait(timeout=2) == 0, "quit exit"
            assert termios.tcgetattr(peer.master) == peer.saved_terminal, "terminal state was not restored"
            peer.helpers_done()
            if preferences:
                path = Path(directory) / "preferences.toml"
                body = path.read_text()
                assert path.stat().st_mode & 0o777 == 0o600, "settings file is not private"
                assert "runtime-key" not in body and "synthetic-secret" not in body, "settings retained secrets"
                servers = tomllib.loads(body)["servers"]
                assert servers == [{"host": "127.0.0.1", "port": peer.server.getsockname()[1],
                                    "channels": ["#other"]}], "settings lost surviving room intent"
            print(f"reconnect_recovery_pty={auth} preferences={preferences}=ok "
                  "connections=3 manual=1 automatic=1 reaped=True", flush=True)
        finally:
            peer.close()


def main():
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(55)
    try:
        for auth in ("nickserv", "sasl"):
            case(sys.argv[1], auth)
        case(sys.argv[1], "sasl", preferences=True)
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    main()
