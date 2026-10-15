#!/usr/bin/env python3
"""Real *log* flow: private copies, local helpers, and nonrecursive save errors.

All servers are loopback. Child PATH contains only temporary failing helpers;
no browser, desktop clipboard, image fetch, or supplied private URL is used.
"""
from __future__ import annotations

from contextlib import contextmanager
import fcntl
import os
import pty
import re
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

from output_stall import drain, receive
from split_identity import Screen


USER = "LogUserSynthetic"
SECRET = "LogPassSynthetic"
HOST = "log-uri.invalid"
OPENER_ERROR = "cannot open link: opener failed (exit 7)"
CLIPBOARD_ERROR = "clipboard helper failed (exit 9)"


@contextmanager
def listening():
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(8)
        yield server


class Client:
    def __init__(self, binary: str, server: socket.socket, env: dict[str, str]):
        self.master, slave = pty.openpty()
        self.saved = termios.tcgetattr(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        self.screen = Screen()
        self.conn: socket.socket | None = None
        try:
            self.proc = subprocess.Popen(
                [binary, "--plain", "--connect", "127.0.0.1", "--port", str(server.getsockname()[1]),
                 "--nick", "probe", "--channel", "#t", "--frames", "0",
                 "--sasl-user", USER, "--sasl-pass", SECRET],
                stdin=slave, stdout=slave, stderr=slave, env=env,
            )
        finally:
            os.close(slave)

    def read(self, duration: float = 0.05) -> str:
        self.screen.feed(drain(self.master, duration))
        return self.screen.text()

    def paint(self, *present: str, absent: tuple[str, ...] = ()) -> str:
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            text = self.read()
            if all(marker in text for marker in present) and all(marker not in text for marker in absent):
                return text
            assert self.proc.poll() is None, "client exited before expected paint"
        # Do not dump original error rows: they intentionally remain unredacted.
        raise AssertionError(f"expected diagnostic screen markers were not painted: {present}; excluded {absent}")

    def command(self, command: str, *present: str, absent: tuple[str, ...] = ()) -> str:
        os.write(self.master, command.encode() + b"\r")
        self.read(0.15)
        return self.paint(*present, absent=absent)

    def sasl(self, connection: socket.socket) -> None:
        # Credentials are configured, so channel joins wait behind the
        # welcome/auth barrier until this connection authenticates. Answer
        # like a real server: ACK sasl, run PLAIN, then 903 releases joins.
        connection.sendall(b":irc CAP * ACK :sasl\r\n")
        assert b"AUTHENTICATE PLAIN" in receive(connection, b"AUTHENTICATE PLAIN", 2), "missing SASL start"
        connection.sendall(b":irc AUTHENTICATE +\r\n")
        blob = receive(connection, b"\r\n", 2)
        assert blob.startswith(b"AUTHENTICATE ") and len(blob) > len(b"AUTHENTICATE \r\n"), "missing SASL blob"
        connection.sendall(b":irc 903 probe :SASL authentication successful\r\n")
        assert b"CAP END" in receive(connection, b"CAP END", 2), "missing CAP END"

    def welcome(self, server: socket.socket, marker: str, expect_auth: bool = True) -> None:
        connection, _ = server.accept()
        if self.conn is not None:
            self.conn.close()
        self.conn = connection
        assert b"USER probe" in receive(connection, b"USER probe", 2), "missing registration"
        if expect_auth:
            self.sasl(connection)
        connection.sendall(
            f":irc 001 probe :Welcome\r\n:probe!u@h JOIN #t\r\n"
            f":alice!u@h PRIVMSG #t :{marker}\r\n".encode()
        )
        self.paint(marker, "online")
        joined = receive(connection, b"JOIN #t", 2)
        assert b"JOIN #t" in joined, "missing channel join"
        if not expect_auth:
            # A new endpoint clears credentials and disables SASL negotiation,
            # so joins must flow without any authentication attempt.
            assert b"AUTHENTICATE" not in joined, "cleared endpoint attempted SASL"
        receive(connection, b"fixture-never-sent", 0.1)

    def quiet(self) -> None:
        assert self.conn is not None
        # The independent five-second heartbeat is valid background traffic,
        # not output from a local command. No other IRC line is allowed here.
        data = receive(self.conn, b"fixture-never-sent", 0.15)
        for line in data.split(b"\r\n"):
            if line:
                assert re.fullmatch(rb"PING :birc_\d+", line), "local diagnostic command emitted IRC bytes"
                self.conn.sendall(b"PONG " + line[5:] + b"\r\n")

    def pong(self, token: str) -> None:
        assert self.conn is not None
        self.conn.sendall(f"PING :{token}\r\n".encode())
        self.read(0.05)
        expected = f"PONG :{token}".encode()
        assert expected in receive(self.conn, expected, 0.8), "diagnostics blocked PONG"

    def quit(self) -> None:
        assert self.conn is not None
        os.write(self.master, b"/quit\r")
        self.read(0.2)
        assert self.proc.wait(timeout=3) == 0, "diagnostics blocked clean quit"
        assert b"QUIT" in receive(self.conn, b"QUIT", 0.3), "diagnostics dropped QUIT"
        assert termios.tcgetattr(self.master) == self.saved, "quit did not restore terminal state"

    def close(self) -> None:
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait(timeout=3)
        if self.conn is not None:
            self.conn.close()
        os.close(self.master)


def private(text: str) -> None:
    for marker in (USER, SECRET, HOST, "helper-output.invalid", "IGNORED-HELPER-STDERR"):
        assert marker not in text, "diagnostic copy leaked synthetic private input"


def clipboard(client: Client) -> None:
    # Locate a real body glyph from the shared screen, not a guessed row.
    for row in range(1, 31):
        cells = "".join(client.screen.cells.get((row, col), " ") for col in range(1, 121))
        if "SELECT-ME" in cells:
            col = cells.index("SELECT-ME") + 1
            break
    else:
        raise AssertionError("clipboard fixture body was not painted")
    for button, end, suffix in ((0, col, "M"), (32, col + 8, "M"), (0, col + 8, "m")):
        os.write(client.master, f"\x1b[<{button};{end};{row}{suffix}".encode())
        client.read(0.05)
    if sys.platform == "darwin":
        client.paint(CLIPBOARD_ERROR, "CHANNEL-KEEP")
    os.write(client.master, b"\x1b")
    client.read(0.2)
    assert client.proc.poll() is None, "selection dismissal quit the client"


def log_case(binary: str, folder: Path, env: dict[str, str], opener: Path) -> None:
    with listening() as first, listening() as second:
        client = Client(binary, first, env)
        try:
            client.welcome(first, "CHANNEL-KEEP SELECT-ME")
            for verb in (
                f"plain-{USER}-{SECRET}-https://{HOST}/{SECRET}",
                f"styled-_https://{HOST}/{SECRET}_",
                f"code-`https://{HOST}/{USER}`-{SECRET}",
            ):
                client.command("/" + verb, "unknown command:", "CHANNEL-KEEP")
                client.quiet()
            # An actual send proves unknown-command errors did not steal focus.
            os.write(client.master, b"NORMAL-SEND\r")
            client.read(0.15)
            expected = b"PRIVMSG #t :NORMAL-SEND"
            assert expected in receive(client.conn, expected, 1), "error changed the send destination"
            text = client.command("/log", "plain-", "styled-", "code-", "[redacted]", "[url]", "online")
            private(text)
            assert re.search(r"\b\d{2}:\d{2}:\d{2}\b", text), "diagnostic timestamp missing"
            client.quiet()
            for command in ("private-log-message", "/me private-log-action", "/msg *log* private-log-msg"):
                client.command(command, "read-only buffer")
                client.quiet()
            client.command("/query #t", "CHANNEL-KEEP", "SELECT-ME")
            client.command(f"/open https://{HOST}/{SECRET}", OPENER_ERROR, "CHANNEL-KEEP")
            client.quiet()
            clipboard(client)
            errors = (OPENER_ERROR, CLIPBOARD_ERROR) if sys.platform == "darwin" else (OPENER_ERROR,)
            text = client.command("/log", *errors, "online")
            private(text)
            for error in errors:
                assert text.count(error) == 1, "helper completion was logged more than once"
            assert Path(folder, "helpers").read_text().splitlines().count("opener") == 1, "fake opener not used"
            if sys.platform == "darwin":
                assert Path(folder, "helpers").read_text().splitlines().count("clipboard") == 1, "fake clipboard not used"
            # A missing fixture helper reports an OS code, not host error text.
            opener.unlink()
            text = client.command(f"/open https://{HOST}/absent", "cannot open link: opener failed (OS ")
            assert re.search(r"opener failed \(OS \d+\)", text), "helper OS code missing"
            private(text)
            client.pong("log-helper-failures")

            client.command("/close", "CHANNEL-KEEP")
            client.command("/RECREATED-ONLY", "RECREATED-ONLY", "CHANNEL-KEEP")
            text = client.command("/log", "RECREATED-ONLY", absent=("plain-", "styled-", OPENER_ERROR))
            private(text)
            client.quiet()
            # Connecting can be transient on loopback. Require registration,
            # the new channel, and retained log state, not a fleeting frame.
            os.write(client.master, f"/connect 127.0.0.1 {second.getsockname()[1]}\r".encode())
            client.read(0.15)
            client.welcome(second, "SECOND-CHANNEL", expect_auth=False)
            client.command("/log", "RECREATED-ONLY", "online", absent=("CHANNEL-KEEP",))
            client.pong("log-new-endpoint")
            client.quit()
        finally:
            client.close()
    print("diagnostic log=ok", flush=True)


def history_case(binary: str, folder: Path, env: dict[str, str]) -> None:
    history = folder / "history-is-directory"
    history.mkdir()
    with listening() as server:
        client = Client(binary, server, {**env, "BIRC_HISTORY": str(history)})
        try:
            client.welcome(server, "HISTORY-CHANNEL")
            # Discard startup diagnostics so one subsequent failed save can be
            # counted. /log and /close themselves must not append history.
            client.command("/log", "history save open failed (")
            client.command("/close", "HISTORY-CHANNEL")
            client.conn.sendall(b":alice!u@h PRIVMSG #t :SINGLE-SAVE-EVENT\r\n")
            client.paint("SINGLE-SAVE-EVENT", "HISTORY-CHANNEL")
            text = client.command("/log", "history save open failed (", "online")
            assert text.count("history save open failed (") == 1, "one failure recursively logged/saved itself"
            assert re.search(r"history save open failed \(\d+\)", text), "save OS code missing"
            assert str(history) not in text, "save diagnostic exposed its path"
            client.pong("history-save-failure")
            text = client.read(1.2)
            assert text.count("history save open failed (") == 1, "idle/PONG repeated the save failure"
            client.quit()
        finally:
            client.close()
    print("diagnostic history=ok", flush=True)


def main(binary: str) -> None:
    with tempfile.TemporaryDirectory(prefix="birc-diagnostic-") as temporary:
        folder = Path(temporary)
        helpers = folder / "fake-bin"
        helpers.mkdir()
        opener = helpers / ("open" if sys.platform == "darwin" else "xdg-open")
        for helper, label, code in ((opener, "opener", 7), (helpers / "pbcopy", "clipboard", 9)):
            helper.write_text(
                '#!/bin/sh\n' + ('while IFS= read -r line; do :; done\n' if label == "clipboard" else '') +
                f'printf "%s\\n" "{label}" >> "$BIRC_DIAGNOSTIC_HELPERS"\n'
                f'printf "%s\\n" "IGNORED-HELPER-STDERR {SECRET} https://helper-output.invalid/private" >&2\n'
                f'exit {code}\n'
            )
            helper.chmod(0o755)
        env = {**os.environ, "TERM": "xterm-256color", "BIRC_HISTORY": "none", "PATH": str(helpers),
               "BIRC_DIAGNOSTIC_HELPERS": str(folder / "helpers"), "BIRC_MEDIA_HELPER": str(helpers / "absent-media")}
        log_case(binary, folder, env, opener)
        history_case(binary, folder, env)
    print("diagnostic=ok", flush=True)


if __name__ == "__main__":
    try:
        main(sys.argv[1] if len(sys.argv) > 1 else "./build/birc")
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        print(f"diagnostic: {error}", file=sys.stderr)
        raise SystemExit(1)
