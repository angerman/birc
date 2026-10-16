#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verified IRC TLS against owned loopback servers and ephemeral certificates.

Usage: tls.py BIRC PINNED_OPENSSL [CASE ...]
No public DNS/IRC, real credentials, Keychain access, or committed private keys.
Failed cases retain synthetic wire/terminal evidence under build/.
"""
from __future__ import annotations

import base64
import fcntl
import json
import os
from pathlib import Path
import pty
import runpy
import select
import shutil
import signal
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parents[2]
SECRET = "TLS synthetic password π".encode()
ACCOUNT = b"account"
SUCCESS = b"BIRC_AUTH_OK\n"
PAYLOAD = base64.b64encode(b"\0" + ACCOUNT + b"\0" + SECRET)
CAPTURE_LIMIT = 2 * 1024 * 1024


def append_bounded(sink, data):
    assert len(sink) + len(data) <= CAPTURE_LIMIT, "TLS fixture capture exceeded its bound"
    sink.extend(data)


def listen():
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(2)
    server.settimeout(7)
    return server


class Certificates:
    def __init__(self, folder, openssl):
        self.folder = folder
        folder.mkdir()
        (folder / "req.cnf").write_text("[req]\ndistinguished_name=subject\n[subject]\n")

        def command(*args, good=True):
            result = subprocess.run([openssl, *args], cwd=folder, capture_output=True, timeout=15)
            assert (result.returncode == 0) == good, "synthetic certificate fixture command failed"

        for name in ("ca", "foreign"):
            command("req", "-config", "req.cnf", "-x509", "-newkey", "rsa:2048", "-noenc", "-sha256", "-days", "2",
                    "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign",
                    "-subj", "/CN=birc-synthetic-" + name, "-keyout", name + ".key", "-out", name + ".pem")
        command("req", "-config", "req.cnf", "-new", "-newkey", "rsa:2048", "-noenc", "-sha256", "-subj", "/CN=birc-synthetic-leaf",
                "-keyout", "server.key", "-out", "server.csr")
        for serial, name, san in ((1, "valid", "IP:127.0.0.1,DNS:localhost"),
                                  (2, "wronghost", "IP:127.0.0.2,DNS:wrong.invalid"),
                                  (3, "dns-only", "DNS:localhost")):
            (folder / (name + ".ext")).write_text(
                "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\n"
                "extendedKeyUsage=serverAuth\nsubjectAltName=" + san + "\n")
            command("x509", "-req", "-in", "server.csr", "-CA", "ca.pem", "-CAkey", "ca.key",
                    "-set_serial", str(serial), "-days", "1", "-sha256", "-extfile", name + ".ext",
                    "-out", name + ".pem")
        (folder / "index").write_text("")
        (folder / "serial").write_text("04\n")
        (folder / "issued").mkdir()
        (folder / "ca.cnf").write_text(
            "[ca]\ndefault_ca=fixture\n[fixture]\n"
            "database=index\nserial=serial\nnew_certs_dir=issued\ncertificate=ca.pem\nprivate_key=ca.key\n"
            "default_md=sha256\ndefault_days=1\npolicy=subject\nx509_extensions=server\n"
            "[subject]\ncommonName=supplied\n[server]\nbasicConstraints=critical,CA:FALSE\n"
            "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n"
            "subjectAltName=IP:127.0.0.1,DNS:localhost\n")
        command("ca", "-batch", "-notext", "-config", "ca.cnf", "-in", "server.csr",
                "-startdate", "20000101000000Z", "-enddate", "20010101000000Z", "-out", "expired.pem")
        for path in folder.glob("*.key"):
            path.chmod(0o600)
        (folder / "invalid.pem").write_text("not a certificate\n")
        (folder / "empty-trust-dir").mkdir()
        # Characterize fixture validity before blaming a client for a failure.
        command("verify", "-CAfile", "ca.pem", "-verify_ip", "127.0.0.1", "valid.pem")
        command("verify", "-CAfile", "ca.pem", "-verify_hostname", "localhost", "valid.pem")
        for name in ("wronghost", "dns-only", "expired"):
            command("verify", "-CAfile", "ca.pem", "-verify_ip", "127.0.0.1", name + ".pem", good=False)
        command("verify", "-CAfile", "foreign.pem", "valid.pem", good=False)

    def context(self, name="valid"):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(self.folder / (name + ".pem"), self.folder / "server.key")
        return context


class Peer:
    """OpenSSL MemoryBIO makes encrypted-record fragmentation explicit."""
    def __init__(self, raw, context=None):
        self.raw = raw
        self.cipher = bytearray()
        self.wire = bytearray()
        self.closed = False
        self.incoming = self.outgoing = self.tls = None
        if context is not None:
            self.incoming, self.outgoing = ssl.MemoryBIO(), ssl.MemoryBIO()
            self.tls = context.wrap_bio(self.incoming, self.outgoing, server_side=True)

    def flush(self, fragment=False):
        if self.outgoing is None:
            return
        while self.outgoing.pending:
            data = self.outgoing.read()
            if fragment:
                # Split inside the TLS record header and encrypted payload.
                for part in (data[:2], data[2:7], data[7:]):
                    if part:
                        self.raw.sendall(part)
                        time.sleep(0.02)
            else:
                self.raw.sendall(data)

    def handshake(self):
        if self.tls is None:
            self.raw.setblocking(False)
            return
        deadline = time.monotonic() + 7
        self.raw.settimeout(0.2)
        while time.monotonic() < deadline:
            try:
                self.tls.do_handshake()
                self.flush()
                self.raw.setblocking(False)
                return
            except ssl.SSLWantReadError:
                self.flush()
                try:
                    data = self.raw.recv(65536)
                except socket.timeout:
                    continue
                if not data:
                    raise AssertionError("TLS peer closed during handshake")
                append_bounded(self.cipher, data)
                self.incoming.write(data)
            except ssl.SSLWantWriteError:
                self.flush()
        raise AssertionError("owned TLS server handshake exceeded its bound")

    def receive(self):
        if self.closed:
            return b""
        while True:
            try:
                if self.tls is None:
                    data = self.raw.recv(65536)
                else:
                    data = self.tls.read(65536)
                    self.flush()
                if not data:
                    self.closed = True
                append_bounded(self.wire, data)
                return data
            except ssl.SSLWantReadError:
                self.flush()
                try:
                    encrypted = self.raw.recv(65536)
                except BlockingIOError:
                    return None
                if not encrypted:
                    self.incoming.write_eof()
                    self.closed = True
                    return b""
                append_bounded(self.cipher, encrypted)
                self.incoming.write(encrypted)
            except BlockingIOError:
                return None
            except ssl.SSLZeroReturnError:
                self.closed = True
                return b""

    def send(self, data, fragment=False):
        self.raw.settimeout(1)
        try:
            if self.tls is None:
                self.raw.sendall(data)
            else:
                assert self.tls.write(data) == len(data), "fixture TLS write was incomplete"
                self.flush(fragment)
        finally:
            self.raw.setblocking(False)

    def close(self):
        self.raw.close()
        self.closed = True


def environment(certs, trust="ca.pem"):
    env = {**os.environ, "TERM": "xterm-256color", "BIRC_PREFERENCES": "none", "BIRC_HISTORY": "none", "BIRC_IMAGES": "off",
           "SSL_CERT_FILE": str(certs.folder / trust), "SSL_CERT_DIR": str(certs.folder / "empty-trust-dir")}
    for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH_SECRET_FD", "BIRC_AUTH_EVENT_FD",
                 "BIRC_FRAME_PROFILE", "TIMUI_TRACE"):
        env.pop(name, None)
    return env


def auth_pipes(env):
    secret_r, secret_w = os.pipe()
    event_r, event_w = os.pipe()
    os.write(secret_w, SECRET)
    os.close(secret_w)
    env.update(BIRC_AUTH_SECRET_FD=str(secret_r), BIRC_AUTH_EVENT_FD=str(event_w))
    return secret_r, event_r, event_w


def wrapper_launch(binary, config, security):
    launcher = runpy.run_path(str(ROOT / "src/launcher/keychain_birc.py"), run_name="tls_wrapper_fixture")
    return launcher["main"](["--profile", "test", "--config", config, "--channel", "#t", "--frames", "0"],
                            security=security, birc=binary, prompt=lambda _: SECRET.decode(), platform="darwin")


class Live:
    def __init__(self, binary, certs, folder, *, tls=True, explicit_tls=False,
                 shorthand=False, duplicate_port=False, port_first=False,
                 auth=False, wrapper=False):
        from split_identity import Screen

        self.folder, self.certs = folder, certs
        folder.mkdir()
        self.server, self.peer = listen(), None
        self.wire, self.raw, self.events, self.pending = bytearray(), bytearray(), bytearray(), bytearray()
        self.screen = Screen()
        self.event = None
        self.event_closed = False
        self.auth, self.wrapper = auth, wrapper
        self.master, slave = pty.openpty()
        self.saved = termios.tcgetattr(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        port = str(self.server.getsockname()[1])
        host = "127.0.0.1:" + port if shorthand or duplicate_port else "127.0.0.1"
        connect_args = ["--connect", host]
        port_args = [] if shorthand and not duplicate_port else ["--port", port]
        endpoint_args = port_args + connect_args if port_first else connect_args + port_args
        args = [str(binary), *endpoint_args,
                "--nick", "probe", "--channel", "#t", "--frames", "0"]
        if not tls:
            args += ["--plain"]
        elif explicit_tls:
            args += ["--tls"]
        env = environment(certs)
        inherited = ()
        if auth and not wrapper:
            args += ["--sasl-user", ACCOUNT.decode(), "--auth", "sasl"]
            secret_r, self.event, event_w = auth_pipes(env)
            inherited = (secret_r, event_w)
        if wrapper:
            config = folder / "config.toml"
            config.write_text('[profiles.test]\nhost="127.0.0.1"\n'
                              f'port={self.server.getsockname()[1]}\naccount="account"\nnick="probe"\n'
                              'auth="sasl"\ntls=true\n')
            config.chmod(0o600)
            security = folder / "security"
            security.write_text("#!" + sys.executable + "\n" +
                "import json,sys\nfrom pathlib import Path\n"
                "root=Path(__file__).parent\n"
                "row={'args':sys.argv[1:],'stdin':sys.stdin.read() if sys.argv[1:]==['-i'] else ''}\n"
                "with (root/'security.jsonl').open('a') as out: out.write(json.dumps(row)+'\\n')\n"
                "raise SystemExit(0 if sys.argv[1:]==['-i'] else 44)\n")
            security.chmod(0o700)
            code = "import runpy,sys; n=runpy.run_path(sys.argv[1],run_name='wrapper_only'); raise SystemExit(n['wrapper_launch'](*sys.argv[2:]))"
            args = [sys.executable, "-c", code, str(Path(__file__).resolve()), str(binary), str(config), str(security)]
        try:
            self.proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, env=env,
                                         pass_fds=inherited, start_new_session=wrapper)
        except Exception:
            self.server.close()
            os.close(self.master)
            if self.event is not None:
                os.close(self.event)
            raise
        finally:
            os.close(slave)
            for fd in inherited:
                os.close(fd)

    def accept(self, server=None, *, tls=True):
        raw, _ = (server or self.server).accept()
        if self.peer is not None:
            self.peer.close()
        self.peer = Peer(raw, self.certs.context() if tls else None)
        self.peer.handshake()
        self.wire.clear()
        self.pending.clear()
        self.until(lambda: b"USER probe" in self.wire, "registration")

    def pump(self, duration=0.05):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            if self.peer is not None:
                data = self.peer.receive()
                if data:
                    append_bounded(self.wire, data)
                    self.pending.extend(data)
                    while b"\r\n" in self.pending:
                        line, _, rest = self.pending.partition(b"\r\n")
                        self.pending = bytearray(rest)
                        if line.startswith(b"PING :birc_"):
                            self.peer.send(b"PONG " + line[5:] + b"\r\n")
            readers = [self.master] + ([] if self.event is None or self.event_closed else [self.event])
            for fd in select.select(readers, [], [], 0.01)[0]:
                if fd == self.event:
                    data = os.read(self.event, 64)
                    self.events.extend(data)
                    self.event_closed = not data
                else:
                    try:
                        data = os.read(self.master, 65536)
                    except OSError:
                        continue
                    append_bounded(self.raw, data)
                    self.screen.feed(data)

    def until(self, predicate, label, seconds=5):
        deadline = time.monotonic() + seconds
        while not predicate() and time.monotonic() < deadline:
            self.pump()
            assert self.proc.poll() is None or predicate(), "client exited during " + label
        assert predicate(), "timeout: " + label

    def welcome(self):
        self.peer.send(b":irc.test 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n"
                       b":a!u@h PRIVMSG #t :TLS-READY\r\n")
        self.until(lambda: b"JOIN #t\r\n" in self.wire and "TLS-READY" in self.screen.text(), "welcome")

    def command(self, text):
        os.write(self.master, text.encode() + b"\r")
        self.pump(0.15)

    def sasl(self):
        self.until(lambda: b"CAP REQ :sasl\r\n" in self.wire, "SASL negotiation")
        self.peer.send(b":irc.test CAP probe ACK :sasl\r\n")
        self.until(lambda: b"AUTHENTICATE PLAIN\r\n" in self.wire, "SASL mechanism")
        self.peer.send(b"AUTHENTICATE +\r\n")
        self.until(lambda: b"AUTHENTICATE " + PAYLOAD + b"\r\n" in self.wire, "SASL private payload")

    def security_calls(self):
        path = self.folder / "security.jsonl"
        return [] if not path.exists() else [json.loads(line) for line in path.read_text().splitlines()]

    def authenticated(self):
        if self.wrapper:
            self.until(lambda: len(self.security_calls()) == 2, "fake Keychain save")
            calls = self.security_calls()
            assert calls[1]["args"] == ["-i"], "fake Keychain used secret argv"
            envelope = b"birc-v1:" + base64.b64encode(SECRET)
            assert calls[1]["stdin"].endswith(" -X " + envelope.hex() + "\n"), "fake Keychain did not store its envelope"
        else:
            self.until(lambda: self.event_closed, "private success EOF")
            assert bytes(self.events) == SUCCESS, "invalid private success event"
        assert SECRET not in self.raw and PAYLOAD not in self.raw, "TLS credentials reached terminal output"

    def quit(self):
        self.command("/quit")
        deadline = time.monotonic() + 4
        while self.proc.poll() is None and time.monotonic() < deadline:
            self.pump()
        assert self.proc.poll() == 0, "TLS quit did not finish cleanly"
        self.pump(0.1)
        assert b"QUIT" in self.wire, "TLS quit dropped IRC QUIT"
        assert termios.tcgetattr(self.master) == self.saved, "TLS quit did not restore the terminal"

    def evidence(self):
        # Capture startup diagnostics even when handshake/accept failed before
        # the first ordinary pump. Never print these synthetic secret captures.
        while select.select([self.master], [], [], 0)[0]:
            try:
                data = os.read(self.master, 65536)
            except OSError:
                break
            if not data:
                break
            append_bounded(self.raw, data)
        (self.folder / "screen.raw").write_bytes(self.raw)
        (self.folder / "wire.raw").write_bytes(self.wire)
        if self.peer is not None:
            (self.folder / "cipher.raw").write_bytes(self.peer.cipher)

    def close(self):
        if self.proc.poll() is None:
            if self.wrapper:
                os.killpg(self.proc.pid, signal.SIGKILL)
            else:
                self.proc.kill()
        self.proc.wait(timeout=3)
        if self.peer is not None:
            self.peer.close()
        self.server.close()
        os.close(self.master)
        if self.event is not None:
            os.close(self.event)


def trusted(client):
    client.accept()
    client.welcome()
    client.peer.send(b"PING :tls-fragment\r\n", fragment=True)
    client.until(lambda: b"PONG :tls-fragment\r\n" in client.wire, "fragmented encrypted record PONG")
    # One SSL_write holds >4096 plaintext bytes. The trailing PING requires
    # native SSL_pending data to be read without a fresh socket readiness edge.
    lines = b"".join(b":a!u@h PRIVMSG #t :buffered " + str(index).encode() + b" " + b"x" * 80 + b"\r\n"
                     for index in range(60))
    data = lines + b":a!u@h PRIVMSG #t :TLS-BUFFERED-END\r\nPING :tls-buffered\r\n"
    assert 4096 < len(data) < 16384, "buffered TLS fixture has the wrong record size"
    client.peer.send(data)
    client.until(lambda: b"PONG :tls-buffered\r\n" in client.wire and "TLS-BUFFERED-END" in client.screen.text(),
                 "buffered plaintext progress", 6)
    client.command("TLS-NORMAL-CHAT")
    client.until(lambda: b"PRIVMSG #t :TLS-NORMAL-CHAT\r\n" in client.wire, "ordinary TLS chat")


def authenticated(client):
    client.accept()
    client.sasl()
    if client.wrapper:
        assert len(client.security_calls()) == 1, "fake Keychain stored before authenticated success"
    else:
        assert not client.events, "SASL emitted success before server confirmation"
    client.peer.send(b":irc.test!attacker@evil.test 903 probe :Forged\r\n:irc.test 903 wrong :Wrong recipient\r\n")
    client.pump(0.2)
    assert (len(client.security_calls()) == 1 if client.wrapper else not client.events), "forged TLS authentication success"
    client.peer.send(b":irc.test 903 probe :Authenticated\r\n")
    client.authenticated()
    client.welcome()
    client.peer.send(b"PING :tls-auth\r\n")
    client.until(lambda: b"PONG :tls-auth\r\n" in client.wire, "authenticated TLS PONG")


def reconnect(client):
    authenticated(client)
    client.peer.close()
    client.peer = None
    client.accept()
    client.sasl()
    client.peer.send(b":irc.test 903 probe :Authenticated again\r\n")
    client.authenticated()  # the launch event remains one-shot
    client.welcome()
    other = listen()
    try:
        for server in (other, client.server):
            client.command(f"/connect 127.0.0.1 {server.getsockname()[1]}")
            client.accept(server)
            client.until(lambda: b"CAP END\r\n" in client.wire, "credential-isolated TLS registration")
            assert b"CAP REQ :sasl" not in client.wire and b"AUTHENTICATE" not in client.wire, "TLS endpoint change retained authentication"
            assert SECRET not in client.wire and PAYLOAD not in client.wire, "TLS endpoint change leaked credentials"
            client.welcome()
    finally:
        other.close()


def plaintext(client):
    client.accept(tls=False)
    client.welcome()
    client.peer.send(b"PING :plain-control\r\n")
    client.until(lambda: b"PONG :plain-control\r\n" in client.wire, "unchanged plaintext PONG")


def slash_endpoint(client):
    client.accept()
    client.welcome()
    port = client.server.getsockname()[1]
    for command in (f"/connect 127.0.0.1:{port}", "/connect 127.0.0.1"):
        client.command(command)
        client.accept()
        client.welcome()
        client.peer.send(b"PING :inherited-tls\r\n")
        client.until(lambda: b"PONG :inherited-tls\r\n" in client.wire,
                     "slash endpoint retained verified TLS and custom port")


def connecting_quit(client):
    raw, _ = client.server.accept()
    raw.setblocking(False)
    client.peer = Peer(raw)
    client.until(lambda: bool(client.wire) and "connecting" in client.screen.text(), "stalled TLS dial")
    client.command("/quit")
    deadline = time.monotonic() + 3
    while client.proc.poll() is None and time.monotonic() < deadline:
        client.pump()
    assert client.proc.poll() == 0, "quit waited for the stalled TLS handshake"
    client.pump(0.1)
    assert not any(token in client.wire for token in (b"NICK ", b"USER ", b"CAP ", b"AUTHENTICATE ", b"QUIT ")), "stalled TLS dial emitted IRC application bytes"
    assert not client.events, "stalled TLS dial emitted authentication success"
    assert termios.tcgetattr(client.master) == client.saved, "stalled TLS quit did not restore the terminal"


def drain_output(proc, sink):
    # Do not let the headless child's pipes fill during a bounded handshake.
    # Captures are finite even if a regression produces unexpected diagnostics.
    while True:
        ready, _, _ = select.select([proc.stdout, proc.stderr], [], [], 0)
        if not ready:
            return
        received = False
        for fd in ready:
            data = os.read(fd.fileno(), 4096)
            append_bounded(sink, data)
            received = received or bool(data)
        if not received:
            return


def rejected(binary, certs, folder, kind):
    folder.mkdir()
    server = listen()
    trust = {"untrusted": "foreign.pem", "missing-ca": "missing.pem", "invalid-ca": "invalid.pem"}.get(kind, "ca.pem")
    env = environment(certs, trust)
    secret_r, event_r, event_w = auth_pipes(env)
    args = [str(binary), "--connect", "127.0.0.1", "--port", str(server.getsockname()[1]),
            "--nick", "probe", "--frames", "1", "--sasl-user", ACCOUNT.decode(), "--auth", "sasl"]
    peer, proc = None, None
    output = bytearray()
    try:
        proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=env, pass_fds=(secret_r, event_w))
        os.close(secret_r)
        secret_r = -1
        os.close(event_w)
        event_w = -1
        deadline = time.monotonic() + 7
        while not select.select([server], [], [], 0.02)[0] and proc.poll() is None and time.monotonic() < deadline:
            pass
        if select.select([server], [], [], 0)[0]:
            raw, _ = server.accept()
            context = None if kind in ("non-tls", "stalled") else certs.context(kind if kind in ("wronghost", "dns-only", "expired") else "valid")
            peer = Peer(raw, context)
            if context is not None:
                try:
                    peer.handshake()
                except (ssl.SSLError, AssertionError, OSError):
                    pass  # failure is expected; application bytes remain forbidden
            else:
                raw.setblocking(False)
                if kind == "non-tls":
                    peer.send(b":irc.test 001 probe :Plaintext is not TLS\r\nAUTHENTICATE +\r\n")
        else:
            assert kind in ("missing-ca", "invalid-ca"), "TLS client did not reach the owned server"
        deadline = time.monotonic() + 8
        while proc.poll() is None and time.monotonic() < deadline:
            if peer is not None:
                try:
                    peer.receive()
                except (ssl.SSLError, OSError):
                    peer.closed = True
            drain_output(proc, output)
            time.sleep(0.01)
        # The final send can race process exit; drain bytes already available.
        if peer is not None:
            try:
                while peer.receive():
                    pass
            except (ssl.SSLError, OSError):
                pass
        proc.wait(timeout=1)
        drain_output(proc, output)
        event = os.read(event_r, 64)
        assert proc.returncode != 0, "TLS rejection exited successfully"
        assert not event, "TLS rejection emitted authenticated success"
        wire = peer.wire if peer is not None else b""
        if peer is not None and peer.tls is not None:
            assert not wire, "TLS rejection emitted IRC application bytes"
        else:
            assert not any(token in wire for token in (b"NICK ", b"USER ", b"CAP ", b"AUTHENTICATE ")), "TLS rejection emitted IRC application bytes"
        assert SECRET not in output and PAYLOAD not in output, "TLS rejection exposed credentials in diagnostics"
        assert str(certs.folder).encode() not in output, "TLS diagnostic exposed the trust-store path"
        assert SECRET not in wire and PAYLOAD not in wire, "TLS rejection sent credentials"
    except Exception:
        (folder / "output.raw").write_bytes(output)
        if peer is not None:
            (folder / "wire.raw").write_bytes(peer.wire)
            (folder / "cipher.raw").write_bytes(peer.cipher)
        print(f"tls_pty case={kind} evidence={folder}", file=sys.stderr, flush=True)
        raise
    finally:
        if proc is not None:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=3)
            proc.stdout.close()
            proc.stderr.close()
        if peer is not None:
            peer.close()
        server.close()
        for fd in (secret_r, event_r, event_w):
            if fd >= 0:
                os.close(fd)


def endpoint_conflicts(binary, certs, folder):
    folder.mkdir()
    for port_first in (False, True):
        first, second = listen(), listen()
        master, slave = pty.openpty()
        saved = termios.tcgetattr(slave)
        connect = ["--connect", "127.0.0.1:" + str(first.getsockname()[1])]
        port = ["--port", str(second.getsockname()[1])]
        arguments = port + connect if port_first else connect + port
        process = None
        try:
            process = subprocess.Popen([str(binary), *arguments, "--frames", "1"],
                stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment(certs))
            output, error = process.communicate(timeout=5)
            (folder / ("port-first" if port_first else "host-first")).write_bytes(output + error)
            assert process.returncode == 2, "conflicting endpoint ports were not rejected by the CLI"
            assert not output and b"\x1b" not in error, "conflicting endpoint painted a client frame"
            assert not select.select([first, second], [], [], 0)[0], "conflicting endpoint opened a connection"
            assert termios.tcgetattr(slave) == saved, "conflicting endpoint changed terminal state"
        finally:
            if process is not None:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=3)
                process.stdout.close()
                process.stderr.close()
            os.close(master)
            os.close(slave)
            first.close()
            second.close()


def main(binary, openssl, selected):
    folder = Path(tempfile.mkdtemp(prefix="tls-pty-", dir=ROOT / "build"))
    success = False
    try:
        certs = Certificates(folder / "certs", openssl)
        cases = (("trusted", trusted, {}),
                 ("shorthand", trusted, {"shorthand": True}),
                 ("explicit-tls", trusted, {"explicit_tls": True}),
                 ("same-port-first", trusted, {"duplicate_port": True, "port_first": True}),
                 ("same-port-last", trusted, {"duplicate_port": True}),
                 ("slash-endpoint", slash_endpoint, {}),
                 ("sasl", authenticated, {"auth": True}),
                 ("wrapper", authenticated, {"auth": True, "wrapper": True}),
                 ("reconnect", reconnect, {"auth": True}),
                 ("connecting-quit", connecting_quit, {"auth": True}),
                 ("plaintext", plaintext, {"tls": False}),
                 ("plain-shorthand", plaintext, {"tls": False, "shorthand": True}))
        rejected_cases = ("untrusted", "wronghost", "dns-only", "expired", "missing-ca", "invalid-ca", "non-tls", "stalled")
        assert selected <= ({name for name, _, _ in cases} | set(rejected_cases) | {"conflicts"}), "unknown TLS test case"
        for name, case, options in cases:
            if selected and name not in selected:
                continue
            client = Live(binary, certs, folder / name, **options)
            try:
                case(client)
                if client.proc.poll() is None:
                    client.quit()
            except Exception:
                client.evidence()
                print(f"tls_pty case={name} evidence={client.folder}", file=sys.stderr, flush=True)
                raise
            finally:
                client.close()
            print("tls_pty " + name + "=ok", flush=True)
        for kind in rejected_cases:
            if selected and kind not in selected:
                continue
            rejected(binary, certs, folder / kind, kind)
            print("tls_pty " + kind + "=ok", flush=True)
        if not selected or "conflicts" in selected:
            try:
                endpoint_conflicts(binary, certs, folder / "conflicts")
            except Exception:
                print(f"tls_pty case=conflicts evidence={folder / 'conflicts'}", file=sys.stderr, flush=True)
                raise
            print("tls_pty conflicts=ok", flush=True)
        success = True
    finally:
        if success:
            shutil.rmtree(folder)
    print("tls_pty=ok", flush=True)


if __name__ == "__main__":
    try:
        def wall_bound(_signal, _frame):
            raise TimeoutError("TLS PTY wall-clock bound")
        signal.signal(signal.SIGALRM, wall_bound)
        signal.alarm(110)
        main(Path(sys.argv[1]).resolve(), sys.argv[2], set(sys.argv[3:]))
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print("tls_pty: " + str(error), file=sys.stderr)
        raise SystemExit(1)
