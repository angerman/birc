#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Real loopback authentication with private credential/success pipes.

No Keychain access. Each hostile control precedes its positive control.
Never print captured wire or terminal bytes: they may contain test secrets.
"""
from __future__ import annotations

import base64
import fcntl
import os
import pty
import select
import socket
import struct
import subprocess
import sys
import termios
import time

SECRET = "test secret π".encode()
PREFIX = b"NickServ!service@services.test"
SUCCESS = b"BIRC_AUTH_OK\n"


class Client:
    def __init__(self, program, mode):
        # SASL accepts embedded spaces. NickServ's IDENTIFY arguments do not.
        self.secret = SECRET if mode == "sasl" else "test-secret-π".encode()
        self.server = socket.socket()
        self.server.bind(("127.0.0.1", 0))
        self.server.listen(1)
        self.server.settimeout(5)
        self.master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
        secret_r, secret_w = os.pipe()
        self.event, event_w = os.pipe()
        os.write(secret_w, self.secret)
        os.close(secret_w)
        self.wire, self.screen, self.event_bytes = bytearray(), bytearray(), bytearray()
        self.event_closed = False
        args = [program, "--connect", "127.0.0.1", "--port", str(self.server.getsockname()[1]),
                "--nick", "probe", "--channel", "#t", "--frames", "0",
                "--sasl-user", "account", "--auth", mode]
        if mode != "sasl":
            args += ["--nickserv-prefix", PREFIX.decode(), "--nickserv-success", "Account confirmed"]
        env = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none", "BIRC_IMAGES": "off",
               "BIRC_AUTH_SECRET_FD": str(secret_r), "BIRC_AUTH_EVENT_FD": str(event_w)}
        env.pop("BIRC_SASL_USER", None)
        env.pop("BIRC_SASL_PASS", None)
        try:
            self.proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                                         env=env, pass_fds=(secret_r, event_w))
        finally:
            os.close(slave)
            os.close(secret_r)
            os.close(event_w)
        self.conn, _ = self.server.accept()
        self.conn.setblocking(False)
        self.until(lambda: b"USER probe" in self.wire, "registration")

    def pump(self, duration=0.05):
        ready, _, _ = select.select([self.master, self.conn] + ([] if self.event_closed else [self.event]), [], [], duration)
        for fd in ready:
            if fd is self.conn:
                data = self.conn.recv(65536)
                self.wire.extend(data)
            elif fd == self.event:
                data = os.read(self.event, 64)
                self.event_bytes.extend(data)
                self.event_closed = not data
            else:
                try:
                    self.screen.extend(os.read(self.master, 65536))
                except OSError:
                    pass

    def until(self, predicate, label, timeout=4):
        deadline = time.monotonic() + timeout
        while not predicate() and time.monotonic() < deadline:
            self.pump()
        assert predicate(), "timeout: " + label

    def send(self, line):
        self.conn.sendall(line + b"\r\n")

    def redial(self, server):
        """Exercise the actual composer -> Dial -> writer continuation."""
        port = server.getsockname()[1]
        os.write(self.master, f"/connect 127.0.0.1 {port}\r".encode())
        conn, _ = server.accept()
        self.conn.close()
        self.conn = conn
        self.conn.setblocking(False)
        self.wire.clear()
        self.until(lambda: b"USER probe" in self.wire, "redial registration")

    def uncredentialed(self):
        self.until(lambda: b"CAP END\r\n" in self.wire, "non-auth registration")
        assert b"CAP REQ :sasl" not in self.wire, "out-of-scope SASL negotiation"
        assert b"AUTHENTICATE" not in self.wire, "out-of-scope SASL credential"
        assert self.secret not in self.wire, "out-of-scope clear credential"
        assert base64.b64encode(b"\0account\0" + self.secret) not in self.wire, "out-of-scope payload"

    def absent(self, needle=None):
        deadline = time.monotonic() + 0.25
        while time.monotonic() < deadline:
            self.pump()
        assert not self.event_bytes, "untrusted authentication success"
        if needle is not None:
            assert needle not in self.wire, "premature credential transmission"

    def authenticated(self):
        self.until(lambda: self.event_closed, "authentication event EOF")
        assert bytes(self.event_bytes) == SUCCESS, "invalid success frame"
        assert self.secret not in self.screen, "credential reached terminal output"
        payload = base64.b64encode(b"\0account\0" + self.secret)
        assert payload not in self.screen, "SASL payload reached terminal output"

    def close(self):
        try:
            if self.proc.poll() is None:
                os.write(self.master, b"/quit\r")
                self.until(lambda: self.proc.poll() is not None, "quit", 6)
            assert self.proc.returncode == 0, "client exit failure"
        finally:
            if self.proc.poll() is None:
                self.proc.kill()
                self.proc.wait()
            self.conn.close()
            self.server.close()
            os.close(self.master)
            os.close(self.event)


def sasl_exchange(client):
    assert b"CAP REQ :sasl\r\n" in client.wire
    client.send(b":irc.test CAP probe ACK :sasl")
    client.until(lambda: b"AUTHENTICATE PLAIN\r\n" in client.wire, "SASL start")
    client.send(b"AUTHENTICATE +")
    payload = base64.b64encode(b"\0account\0" + client.secret)
    client.until(lambda: b"AUTHENTICATE " + payload + b"\r\n" in client.wire, "SASL payload")


def nickserv_exchange(client):
    client.send(b":irc.test 001 probe :Welcome")
    client.until(lambda: b"PRIVMSG NickServ :HELP\r\n" in client.wire, "service identity probe")
    client.send(b":NickServ!impostor@evil.test NOTICE probe :Account confirmed")
    client.absent(b"IDENTIFY")
    client.send(b":" + PREFIX + b" NOTICE someone :Help")
    client.absent(b"IDENTIFY")
    client.send(b":" + PREFIX + b" NOTICE probe :Help")
    client.until(lambda: b"PRIVMSG NickServ :IDENTIFY account " + client.secret + b"\r\n" in client.wire, "verified service credential")
    client.send(b":NickServ!impostor@evil.test NOTICE probe :Account confirmed")
    client.absent()
    client.send(b":" + PREFIX + b" NOTICE probe :Not confirmed")
    client.absent()
    client.send(b":" + PREFIX + b" NOTICE probe :Account confirmed")
    client.authenticated()


def main():
    program = sys.argv[1]
    for mode in ("sasl", "nickserv", "sasl-nickserv", "bad-password"):
        client = Client(program, "sasl-nickserv" if mode == "bad-password" else mode)
        try:
            if mode in ("sasl", "bad-password"):
                sasl_exchange(client)
                client.send(b":irc.test!attacker@evil.test 903 probe :Forged")
                client.send(b":irc.test 903 someone :Wrong recipient")
                client.absent()
                if mode == "bad-password":
                    client.send(b":irc.test 904 probe :Authentication failed")
                    client.send(b":irc.test 001 probe :Welcome")
                    client.absent(b"IDENTIFY")
                else:
                    # The success edge must survive registration in the same chunk.
                    client.conn.sendall(b":irc.test 903 probe :Authenticated\r\n:irc.test 001 probe :Welcome\r\n")
                    client.authenticated()
            else:
                if mode == "nickserv":
                    assert b"CAP REQ :sasl" not in client.wire
                else:
                    client.send(b":irc.test CAP probe NAK :sasl")
                    client.until(lambda: b"CAP END\r\n" in client.wire, "unavailable SASL fallback")
                nickserv_exchange(client)
        finally:
            client.close()
        print("auth_profile_pty " + mode + "=ok")

    # (+) A same-endpoint reconnect still negotiates and uses the same profile.
    client = Client(program, "sasl")
    try:
        sasl_exchange(client)
        client.conn.sendall(b":irc.test 903 probe :Authenticated\r\n:irc.test 001 probe :Welcome\r\n")
        client.authenticated()
        client.redial(client.server)
        sasl_exchange(client)
        client.conn.sendall(b":irc.test 903 probe :Authenticated\r\n:irc.test 001 probe :Welcome\r\n")
        client.authenticated()  # The launch-bound success pipe remains one-shot.
    finally:
        client.close()
    print("auth_profile_pty same-endpoint=ok")

    # (-) Leaving the launch port clears credentials and negotiation forever.
    # Begin without a success so neither a forged 903 on the new port nor a
    # later return to the initial port can hide behind an earlier valid event.
    client = Client(program, "sasl")
    other = socket.socket()
    try:
        other.bind(("127.0.0.1", 0))
        other.listen(1)
        other.settimeout(5)
        sasl_exchange(client)
        for server in (other, client.server):
            client.redial(server)
            client.uncredentialed()
            client.conn.sendall(b":irc.test CAP probe ACK :sasl\r\nAUTHENTICATE +\r\n"
                                b":irc.test 903 probe :Authenticated\r\n:irc.test 001 probe :Welcome\r\n")
            client.absent()
            client.uncredentialed()
        assert client.secret not in client.screen, "credential reached terminal output"
    finally:
        other.close()
        client.close()
    print("auth_profile_pty changed-and-returned-endpoint=ok")
    print("auth_profile_pty=ok")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print("auth_profile_pty: FAIL: " + str(error), file=sys.stderr)
        raise SystemExit(1)
