#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Two owned loopback peers on the --server path.

No public IRC, credentials, Keychain, or user files. Progress waits on
observable wire and visible-cell edges. A fixed sleep is not a pass condition.

Asserts:
- each part completes its own registration (NICK/USER, then that part's 001)
- a PRIVMSG on one peer is painted only while that part is current
- F7 cycles slots and restores each part's composer draft
- reader EOF plus the retired generation's writer completion does not
  acknowledge shutdown; /quit still delivers QUIT on both current generations
"""
from __future__ import annotations

import fcntl
import os
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import time


WIRE_LIMIT = 65536
RAW_LIMIT = 262144


class Screen:
    """Cell buffer. Cursor addressing overwrites; stripping CSI does not."""

    def __init__(self) -> None:
        self.rows: dict[int, dict[int, str]] = {}
        self.row = 0
        self.col = 0

    def feed(self, data: bytes) -> None:
        text = data.decode("utf-8", "replace")
        i = 0
        n = len(text)
        while i < n:
            ch = text[i]
            if ch == "\x1b":
                i = self._esc(text, i)
                continue
            if ch == "\x9b":
                i = self._csi(text, i + 1)
                continue
            if ch == "\r":
                self.col = 0
            elif ch == "\n":
                self.row += 1
            elif ch == "\b":
                self.col = max(0, self.col - 1)
            elif ord(ch) >= 32:
                self.rows.setdefault(self.row, {})[self.col] = ch
                self.col += 1
            i += 1

    def _esc(self, text: str, i: int) -> int:
        if i + 1 >= len(text):
            return len(text)
        kind = text[i + 1]
        if kind == "[":
            return self._csi(text, i + 2)
        if kind == "]":
            j = i + 2
            while j < len(text) and text[j] != "\x07":
                if text[j] == "\x1b" and j + 1 < len(text) and text[j + 1] == "\\":
                    return j + 2
                j += 1
            return min(j + 1, len(text))
        return i + 2

    def _csi(self, text: str, j: int) -> int:
        params: list[int] = []
        cur = 0
        saw = False
        while j < len(text):
            ch = text[j]
            if ch.isdigit():
                cur = cur * 10 + int(ch)
                saw = True
                j += 1
                continue
            if ch == ";":
                params.append(cur if saw else 0)
                cur = 0
                saw = False
                j += 1
                continue
            if 0x40 <= ord(ch) <= 0x7E:
                params.append(cur if saw else 0)
                self._apply(ch, params)
                return j + 1
            j += 1
        return j

    def _apply(self, final: str, params: list[int]) -> None:
        def p(index: int, default: int) -> int:
            if index >= len(params) or params[index] == 0:
                return default
            return params[index]

        if final == "H" or final == "f":
            self.row = p(0, 1) - 1
            self.col = p(1, 1) - 1
        elif final == "A":
            self.row = max(0, self.row - p(0, 1))
        elif final == "B":
            self.row += p(0, 1)
        elif final == "C":
            self.col += p(0, 1)
        elif final == "D":
            self.col = max(0, self.col - p(0, 1))
        elif final == "G":
            self.col = p(0, 1) - 1
        elif final == "K":
            row = self.rows.get(self.row)
            if row is not None:
                for col in [c for c in row if c >= self.col]:
                    del row[col]
        elif final == "J" and p(0, 0) == 2:
            self.rows.clear()

    def text(self) -> str:
        if not self.rows:
            return ""
        lines = []
        for row in range(max(self.rows) + 1):
            cells = self.rows.get(row, {})
            if not cells:
                lines.append("")
                continue
            width = max(cells) + 1
            lines.append("".join(cells.get(col, " ") for col in range(width)).rstrip())
        return "\n".join(lines)


class Slot:
    def __init__(self, name: str) -> None:
        self.name = name
        self.listener = socket.socket()
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(2)
        self.listener.setblocking(False)
        self.conn: socket.socket | None = None
        self.wire = bytearray()
        self.parsed = 0
        self.generation = 0

    @property
    def port(self) -> int:
        return self.listener.getsockname()[1]

    def close_conn(self) -> None:
        if self.conn is not None:
            try:
                self.conn.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.conn.close()
            self.conn = None

    def close(self) -> None:
        self.close_conn()
        self.listener.close()


def extend_wire(buf: bytearray, data: bytes) -> None:
    if len(buf) + len(data) > WIRE_LIMIT:
        raise AssertionError("owned wire capture exceeded 64 KiB")
    buf.extend(data)


def extend_raw(buf: bytearray, data: bytes) -> None:
    buf.extend(data)
    if len(buf) > RAW_LIMIT:
        del buf[:-RAW_LIMIT]


class Client:
    def __init__(self, program: str) -> None:
        self.alpha = Slot("alpha")
        self.beta = Slot("beta")
        self.raw = bytearray()
        self.screen = Screen()
        self.master = None
        self.proc = None
        slave = None
        try:
            self.master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            env = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none",
                   "BIRC_PREFERENCES": "none", "BIRC_IMAGES": "off", "BIRC_IMAGE_CACHE": "none"}
            for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH", "BIRC_AUTH_SECRET_FD",
                         "BIRC_AUTH_EVENT_FD"):
                env.pop(name, None)
            self.proc = subprocess.Popen(
                [program, "--plain", "--connect", "127.0.0.1", "--port", str(self.alpha.port),
                 "--server", f"127.0.0.1:{self.beta.port}", "--nick", "probe", "--channel", "#t",
                 "--frames", "0"],
                stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True,
            )
        except BaseException:
            self.close()
            raise
        finally:
            if slave is not None:
                os.close(slave)

    def close(self) -> None:
        proc = self.proc
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=2)
        self.alpha.close()
        self.beta.close()
        if self.master is not None:
            os.close(self.master)
            self.master = None

    def pump(self, duration: float = 0.05) -> None:
        fds = [self.master]
        for slot in (self.alpha, self.beta):
            fds.append(slot.listener if slot.conn is None else slot.conn)
        ready, _, _ = select.select(fds, [], [], duration)
        for fd in ready:
            if fd is self.master:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    data = b""
                extend_raw(self.raw, data)
                self.screen.feed(data)
            else:
                self._socket(fd)

    def _socket(self, fd) -> None:
        for slot in (self.alpha, self.beta):
            if fd is slot.listener:
                conn, _ = slot.listener.accept()
                conn.setblocking(False)
                if slot.conn is not None:
                    raise AssertionError(f"unexpected extra connection on {slot.name}")
                slot.conn = conn
                slot.wire = bytearray()
                slot.parsed = 0
                slot.generation += 1
                return
            if fd is slot.conn:
                try:
                    data = slot.conn.recv(65536)
                except (BlockingIOError, InterruptedError):
                    return
                if not data:
                    return
                extend_wire(slot.wire, data)
                self._pongs(slot)
                return

    def _pongs(self, slot: Slot) -> None:
        while True:
            end = slot.wire.find(b"\r\n", slot.parsed)
            if end < 0:
                return
            line = bytes(slot.wire[slot.parsed:end])
            slot.parsed = end + 2
            if line.startswith(b"PING "):
                self._send(slot, b"PONG " + line[5:])

    def _send(self, slot: Slot, line: bytes) -> None:
        if slot.conn is None:
            raise AssertionError(f"no connection on {slot.name}")
        payload = line if line.endswith(b"\r\n") else line + b"\r\n"
        view = memoryview(payload)
        while view:
            try:
                sent = slot.conn.send(view)
            except (BlockingIOError, InterruptedError):
                self.pump()
                continue
            if sent <= 0:
                raise AssertionError(f"send failed on {slot.name}")
            view = view[sent:]

    def visible(self) -> str:
        return self.screen.text()

    def until(self, predicate, label: str, timeout: float = 8) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.pump()
            if predicate():
                return
            if self.proc.poll() is not None:
                self.pump()
                if predicate():
                    return
                raise AssertionError(
                    f"child exited during {label} rc={self.proc.returncode}\n"
                    f"visible:\n{self.visible()}\n"
                    f"alpha gen={self.alpha.generation} wire={bytes(self.alpha.wire[-400:])!r}\n"
                    f"beta gen={self.beta.generation} wire={bytes(self.beta.wire[-400:])!r}"
                )
        raise AssertionError(
            f"timeout: {label}\nvisible:\n{self.visible()}\n"
            f"alpha gen={self.alpha.generation} wire={bytes(self.alpha.wire[-400:])!r}\n"
            f"beta gen={self.beta.generation} wire={bytes(self.beta.wire[-400:])!r}"
        )

    def registered(self, slot: Slot) -> bool:
        return b"NICK probe\r\n" in slot.wire and b"USER probe " in slot.wire

    def welcome(self, slot: Slot, body: str) -> None:
        self._send(slot, f":{slot.name}.test 001 probe :{body}".encode())
        self._send(slot, b":probe!p@h JOIN #t")

    def type_text(self, text: str) -> None:
        os.write(self.master, text.encode())

    def key_f7(self) -> None:
        os.write(self.master, b"\x1b[18~")

    def quit(self, clear: int = 0) -> None:
        os.write(self.master, b"\x7f" * clear + b"/quit\r")


def run(program: str) -> None:
    client = Client(program)
    try:
        client.until(lambda: client.alpha.conn is not None, "accept alpha", 8)
        client.until(lambda: client.beta.conn is not None, "accept beta", 8)
        client.until(lambda: client.registered(client.alpha), "alpha registration")
        client.until(lambda: client.registered(client.beta), "beta registration")
        assert client.alpha.generation == 1 and client.beta.generation == 1, "initial generations"

        # 001 is what releases JOIN. The welcome text lands on the server
        # tab; the channel pane is the part oracle, so a PRIVMSG is the
        # visible evidence after each numeric.
        assert b"JOIN " not in client.alpha.wire and b"JOIN " not in client.beta.wire, "JOIN before 001"
        client.welcome(client.alpha, "WELCOME-ALPHA")
        client.until(lambda: b"JOIN #t\r\n" in client.alpha.wire, "alpha 001 released JOIN")
        client.welcome(client.beta, "WELCOME-BETA")
        client.until(lambda: b"JOIN #t\r\n" in client.beta.wire, "beta 001 released JOIN")
        client._send(client.alpha, b":a!a@h PRIVMSG #t :ONLY-ALPHA")
        client.until(lambda: "ONLY-ALPHA" in client.visible(), "alpha message painted")
        assert "ONLY-BETA" not in client.visible()

        client._send(client.beta, b":b!b@h PRIVMSG #t :ONLY-BETA")
        client._send(client.beta, b"PING :beta-routed")
        client.until(lambda: b"PONG :beta-routed\r\n" in client.beta.wire, "beta message processed")
        assert "ONLY-ALPHA" in client.visible(), "alpha part lost its message"
        assert "ONLY-BETA" not in client.visible(), "beta message painted on the alpha part"

        client.type_text("draftalpha")
        client.until(lambda: "draftalpha" in client.visible(), "alpha draft painted")
        client.key_f7()
        client.until(
            lambda: "ONLY-BETA" in client.visible() and "draftalpha" not in client.visible(),
            "F7 switched to beta and stashed the alpha draft",
        )
        assert "ONLY-ALPHA" not in client.visible(), "alpha message stayed visible on beta"
        client.type_text("draftbeta")
        client.until(lambda: "draftbeta" in client.visible(), "beta draft painted")
        client.key_f7()
        client.until(
            lambda: "draftalpha" in client.visible() and "ONLY-ALPHA" in client.visible()
            and "draftbeta" not in client.visible() and "ONLY-BETA" not in client.visible(),
            "F7 restored the alpha draft and alpha part",
        )

        retired = client.alpha.generation
        client.alpha.close_conn()
        client.until(lambda: client.alpha.generation == retired + 1 and client.registered(client.alpha),
                     "alpha redial registration", 8)
        assert client.proc.poll() is None, "stale reader EOF exited the client"
        assert b"JOIN " not in client.alpha.wire, "redial joined before its own 001"
        client.welcome(client.alpha, "WELCOME-ALPHA2")
        client.until(lambda: b"JOIN #t\r\n" in client.alpha.wire, "current alpha generation 001")
        client._send(client.alpha, b":a!a@h PRIVMSG #t :GEN2-ALPHA")
        client.until(lambda: "GEN2-ALPHA" in client.visible(), "current alpha generation painted")
        assert "ONLY-BETA" not in client.visible(), "redial painted the other part"
        assert client.proc.poll() is None, "stale writer completion acknowledged shutdown"
        alpha_at_quit = len(client.alpha.wire)
        beta_at_quit = len(client.beta.wire)
        client.quit(len("draftalpha"))
        client.until(
            lambda: b"QUIT " in client.alpha.wire[alpha_at_quit:]
            and b"QUIT " in client.beta.wire[beta_at_quit:],
            "QUIT on both current generations",
        )
        client.until(lambda: client.proc.poll() is not None, "process exit after both writers", 8)
        assert client.proc.returncode == 0, f"exit {client.proc.returncode}"
        text = bytes(client.raw).decode("utf-8", "replace")
        assert "[?1049l" in text, "terminal was not restored"
        assert "birc=ok" in text, "shutdown did not report birc=ok"
        print("server_multiserver=ok")
    finally:
        client.close()


def main() -> int:
    program = sys.argv[1] if len(sys.argv) > 1 else "./build/birc"
    try:
        run(program)
    except AssertionError as exc:
        print(f"server_multiserver: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
