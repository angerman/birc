#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Launch one auth profile. Keychain access is macOS-only; help is portable.

Profiles contain public metadata, never passwords. A private EOF-framed pipe
supplies UTF-8 credentials; a separate, launch-bound pipe confirms actual auth.
The child must emit exactly BIRC_AUTH_OK followed by newline and close that
pipe, only for the initial endpoint/account. Exit status and UI text are not auth.
"""
from __future__ import annotations

import argparse
import base64
import getpass
import ipaddress
import json
import os
from pathlib import Path
import re
import selectors
import stat
import subprocess
import sys
import time
import tomllib
from typing import NamedTuple
import warnings


SECURITY = "/usr/bin/security"
BIRC_PROGRAM = str(Path(__file__).resolve().parents[1] / "bin/birc")
MAX_SECRET = 1024
MAX_CONFIG = 64 * 1024
SUCCESS = b"BIRC_AUTH_OK\n"
ENVELOPE = b"birc-v1:"


class Refusal(Exception):
    """A fixed safe stage description, never child output or credential data."""


class Parser(argparse.ArgumentParser):
    def error(self, message):
        # Unknown arguments can themselves contain a password. Do not echo them.
        self.exit(2, "keychain-birc: invalid arguments; use --help\n")


class Profile(NamedTuple):
    host: str
    port: int
    account: str
    nick: str
    auth: str
    prefix: str
    confirmation: str
    relay: bool
    service: str
    tls: bool


def public_text(value, limit: int, *, spaces=False) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > limit:
        raise Refusal("invalid profile metadata")
    if any(ord(c) < 32 or ord(c) == 127 or (not spaces and c.isspace()) for c in value):
        raise Refusal("invalid profile metadata")
    return value


def read_profile(path: Path, name: str, *, tls=False) -> Profile:
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", name):
        raise Refusal("invalid profile name")
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as file:
            info = os.fstat(file.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or info.st_mode & 0o022 or info.st_size > MAX_CONFIG):
                raise Refusal("unsafe profile file")
            raw = file.read(MAX_CONFIG + 1)
        if len(raw) > MAX_CONFIG:
            raise Refusal("profile file exceeds bound")
        document = tomllib.loads(raw.decode("utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError):
        raise Refusal("cannot read profile file") from None
    if set(document) != {"profiles"} or not isinstance(document["profiles"], dict):
        raise Refusal("invalid profile file")
    entry = document["profiles"].get(name)
    allowed = {"host", "port", "account", "nick", "auth", "nickserv_prefix",
               "nickserv_success", "trusted_relay", "tls"}
    if (not isinstance(entry, dict)
            or any(not isinstance(row, dict) or set(row) - allowed
                   for row in document["profiles"].values())):
        raise Refusal("invalid profile metadata")
    host = public_text(entry.get("host"), 253)
    if not re.fullmatch(r"[A-Za-z0-9.-]+", host):
        raise Refusal("invalid IPv4 host")
    account = public_text(entry.get("account"), 128)
    profile_tls = entry.get("tls", False)
    if type(profile_tls) is not bool:
        raise Refusal("invalid profile metadata")
    use_tls = tls or profile_tls
    port = entry.get("port", 6697 if use_tls else 6667)
    relay = entry.get("trusted_relay", False)
    if type(port) is not int or not 1 <= port <= 65535 or type(relay) is not bool:
        raise Refusal("invalid profile metadata")
    use_tls = use_tls or port == 6697
    nick = public_text(entry["nick"], 64) if "nick" in entry else ""
    auth = entry.get("auth", "sasl")
    if auth not in ("sasl", "nickserv", "sasl-nickserv"):
        raise Refusal("invalid authentication mode")
    prefix, confirmation = "", ""
    if auth != "sasl":
        prefix = public_text(entry.get("nickserv_prefix"), 255)
        confirmation = public_text(entry.get("nickserv_success"), 512, spaces=True)
        parts = re.fullmatch(r"([^ !@*?]+)![^ !@*?]+@[^ !@*?]+", prefix)
        # Core Auth.valid_prefix also forbids channel/multi-target/colon nicks.
        # Refuse here, before Keychain lookup or a password prompt.
        if parts is None or parts[1][0] in "#&+!:" or "," in parts[1]:
            raise Refusal("NickServ requires an exact full prefix")
    elif "nickserv_prefix" in entry or "nickserv_success" in entry:
        raise Refusal("NickServ trust requires an explicit authentication mode")
    service = "birc.auth.v1:" + json.dumps([name, host, port], separators=(",", ":"))
    return Profile(host, port, account, nick, auth, prefix, confirmation, relay, service, use_tls)


def secret_bytes(value: str) -> bytes:
    if not isinstance(value, str):
        raise Refusal("invalid password")
    try:
        data = value.encode("utf-8")
    except UnicodeError:
        raise Refusal("invalid password encoding") from None
    if not data or len(data) > MAX_SECRET or any(c in data for c in (0, 10, 13)):
        raise Refusal("password must be 1..1024 UTF-8 bytes without NUL, CR or LF")
    return data


def child_environment() -> dict[str, str]:
    env = dict(os.environ)
    for name in ("BIRC_SASL_USER", "BIRC_SASL_PASS", "BIRC_AUTH_SECRET_FD", "BIRC_AUTH_EVENT_FD"):
        env.pop(name, None)
    return env


def bounded_process(command: list[str], data=b"", *, limit=2048, timeout=30):
    """Bound both pipes and elapsed time; never forward helper diagnostics."""
    env = child_environment()
    env["LC_ALL"] = "C"
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, env=env, close_fds=True) as proc:
        assert proc.stdin is not None and proc.stdout is not None
        output, offset = bytearray(), 0
        deadline = time.monotonic() + timeout
        try:
            with selectors.DefaultSelector() as selector:
                os.set_blocking(proc.stdout.fileno(), False)
                selector.register(proc.stdout, selectors.EVENT_READ)
                if data:
                    os.set_blocking(proc.stdin.fileno(), False)
                    selector.register(proc.stdin, selectors.EVENT_WRITE)
                else:
                    proc.stdin.close()
                while selector.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise Refusal("Keychain helper timed out")
                    for key, _ in selector.select(remaining):
                        if key.fileobj is proc.stdin:
                            offset += os.write(proc.stdin.fileno(), data[offset:])
                            if offset == len(data):
                                selector.unregister(proc.stdin)
                                proc.stdin.close()
                        else:
                            part = os.read(proc.stdout.fileno(), min(4096, limit + 1 - len(output)))
                            if not part:
                                selector.unregister(proc.stdout)
                            output.extend(part)
                            if len(output) > limit:
                                raise Refusal("Keychain helper output exceeds bound")
            return proc.wait(timeout=max(0.001, deadline - time.monotonic())), bytes(output)
        except (OSError, subprocess.TimeoutExpired):
            raise Refusal("Keychain helper failed") from None
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()


def load_secret(security: str, profile: Profile) -> bytes | None:
    code, output = bounded_process([security, "find-generic-password", "-s", profile.service,
                                    "-a", profile.account, "-w"])
    if code == 44 and not output:
        # Native search errors can also map to this status: no usable item found,
        # not proof that an item does not exist. Saving never replaces an item.
        return None
    if code != 0:
        raise Refusal(f"Keychain lookup failed (status {code})")
    if not output.endswith(b"\n") or output.count(b"\n") != 1 or not output.startswith(ENVELOPE):
        raise Refusal("unsupported Keychain credential format")
    try:
        raw = base64.b64decode(output[len(ENVELOPE):-1], validate=True)
        return secret_bytes(raw.decode("utf-8"))
    except (ValueError, UnicodeError):
        raise Refusal("invalid Keychain credential format") from None


def security_quote(value: str) -> str:
    # security's interactive parser treats backslash as escape inside quotes.
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def save_secret(security: str, profile: Profile, secret: bytes) -> int:
    envelope = ENVELOPE + base64.b64encode(secret)
    command = ("add-generic-password -a " + security_quote(profile.account)
               + " -s " + security_quote(profile.service) + " -X " + envelope.hex() + "\n").encode("utf-8")
    if len(command) >= 4096:
        raise Refusal("Keychain command exceeds bound")
    # One command, EOF, no -v/-A/-U. Do not overwrite a concurrently added item.
    # A trailing 'exit' would replace the add command's failure status with zero.
    code, _ = bounded_process([security, "-i"], command)
    return code


def auth_succeeded(child: subprocess.Popen, fd: int) -> bool:
    output = bytearray()
    os.set_blocking(fd, False)
    with selectors.DefaultSelector() as selector:
        selector.register(fd, selectors.EVENT_READ)
        while True:
            ready = selector.select(0.25)
            exited = not ready and child.poll() is not None
            if not ready and not exited:
                continue
            # A frame can arrive after select times out but before poll sees exit.
            # Drain available bytes, still requiring EOF. An orphan writer with
            # no further data must not keep an exited client's launcher waiting.
            try:
                part = os.read(fd, len(SUCCESS) + 1 - len(output))
            except BlockingIOError:
                if exited:
                    return False
                continue
            if not part:
                return bytes(output) == SUCCESS
            output.extend(part)
            if len(output) > len(SUCCESS):
                return False


def write_secret(fd: int, secret: bytes) -> None:
    offset = 0
    while offset < len(secret):
        count = os.write(fd, secret[offset:])
        if count <= 0:
            raise Refusal("credential pipe failed")
        offset += count


def launch(program: str, profile: Profile, secret: bytes, extra: list[str], security: str,
           *, save: bool) -> int:
    secret_r = secret_w = event_r = event_w = -1
    child = None
    try:
        secret_r, secret_w = os.pipe()
        event_r, event_w = os.pipe()
        # <=1024 bytes fit the empty owned pipe; EOF frames the exact UTF-8 value.
        write_secret(secret_w, secret)
        os.close(secret_w)
        secret_w = -1
        env = child_environment()
        env.update(BIRC_AUTH_SECRET_FD=str(secret_r), BIRC_AUTH_EVENT_FD=str(event_w))
        args = [program, "--connect", profile.host, "--port", str(profile.port),
                "--sasl-user", profile.account, "--auth", profile.auth]
        if profile.tls:
            args.append("--tls")
        if profile.nick:
            args.extend(["--nick", profile.nick])
        if profile.prefix:
            args.extend(["--nickserv-prefix", profile.prefix,
                         "--nickserv-success", profile.confirmation])
        args.extend(extra)
        child = subprocess.Popen(args, env=env, pass_fds=(secret_r, event_w))
        os.close(secret_r)
        secret_r = -1
        os.close(event_w)
        event_w = -1
        if auth_succeeded(child, event_r) and save:
            try:
                code = save_secret(security, profile, secret)
                if code != 0:
                    print(f"keychain-birc: password not saved (status {code})", file=sys.stderr)
            except Refusal as error:
                print(f"keychain-birc: {error}", file=sys.stderr)
        return child.wait()
    finally:
        for fd in (secret_r, secret_w, event_r, event_w):
            if fd >= 0:
                os.close(fd)
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


def main(argv=None, *, security=SECURITY, birc=None, prompt=getpass.getpass,
         platform=sys.platform) -> int:
    parser = Parser(prog="keychain-birc", description="Launch a macOS Keychain-backed IRC account profile.")
    parser.add_argument("--profile", required=True, help="name in [profiles.NAME]")
    parser.add_argument("--config", type=Path, help="metadata TOML; contains no passwords")
    parser.add_argument("--allow-insecure-auth", action="store_true",
                        help="allow plaintext credentials for this launch only")
    parser.add_argument("--tls", action="store_true",
                        help="use verified TLS; default to port 6697 unless the profile sets a port")
    parser.add_argument("--frames", type=int, help="forward birc frame cap")
    parser.add_argument("--channel", help="forward initial IRC channel")
    options = parser.parse_args(argv)
    try:
        if platform != "darwin":
            raise Refusal("macOS is required for Keychain authentication")
        path = options.config
        if path is None:
            try:
                config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
            except RuntimeError:
                raise Refusal("cannot locate profile config") from None
            path = config_home / "birc/config.toml"
        profile = read_profile(path, options.profile, tls=options.tls)
        try:
            address = ipaddress.ip_address(profile.host)
            loopback = isinstance(address, ipaddress.IPv4Address) and address.is_loopback
        except ValueError:
            loopback = False
        if not profile.tls and options.allow_insecure_auth:
            print("keychain-birc: WARNING: plaintext IRC authentication can expose your password.", file=sys.stderr)
        elif not (profile.tls or (profile.relay and loopback)):
            raise Refusal("authentication requires TLS or a trusted loopback relay; use --allow-insecure-auth to accept plaintext risk")
        extra = []
        if options.frames is not None:
            if not 0 <= options.frames <= 0xffffffff:
                raise Refusal("invalid frame cap")
            extra.extend(["--frames", str(options.frames)])
        if options.channel is not None:
            extra.extend(["--channel", public_text(options.channel, 128)])
        secret = load_secret(security, profile)
        save = secret is None
        if save:
            # getpass otherwise warns and falls back to echoed standard input.
            with warnings.catch_warnings():
                warnings.simplefilter("error", getpass.GetPassWarning)
                try:
                    secret = secret_bytes(prompt("IRC password: "))
                except getpass.GetPassWarning:
                    raise Refusal("password prompt requires a terminal with echo disabled") from None
        assert secret is not None
        return launch(birc or os.environ.get("BIRC_PROGRAM", BIRC_PROGRAM), profile, secret,
                      extra, security, save=save)
    except Refusal as error:
        print(f"keychain-birc: {error}", file=sys.stderr)
    except (OSError, EOFError, KeyboardInterrupt):
        print("keychain-birc: launch cancelled or unavailable", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
