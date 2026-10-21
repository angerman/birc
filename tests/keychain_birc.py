#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Keychain launcher controls. All credentials, programs and files are synthetic."""
from __future__ import annotations

import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch
import warnings


SOURCE = Path(__file__).resolve().parents[1] / "tests/lib/keychain_birc.py"
spec = importlib.util.spec_from_file_location("keychain_birc", SOURCE)
assert spec is not None and spec.loader is not None
launcher = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = launcher
spec.loader.exec_module(launcher)


def executable(path: Path, body: str) -> Path:
    path.write_text(f"#!{sys.executable}\n" + body)
    path.chmod(0o700)
    return path


def config(path: Path, *, host="127.0.0.1", relay=True, extra="", account="alice") -> Path:
    path.write_text('[profiles.test]\n' + f'host = {json.dumps(host)}\naccount = {json.dumps(account)}\n'
                    + f'trusted_relay = {str(relay).lower()}\ntls = false\n' + extra)
    path.chmod(0o600)
    return path


def main() -> None:
    with patch.dict(os.environ, {"LANG": "C", "BIRC_SASL_USER": "wrong-inherited-user",
                                "BIRC_SASL_PASS": "do-not-inherit-password"}, clear=True), \
            tempfile.TemporaryDirectory(prefix="birc-keychain-test-") as name:
        root = Path(name)
        calls = root / "calls"
        security = executable(root / "security", '''
import json, os, sys
from pathlib import Path
root = Path(__file__).parent
with (root / "calls").open("a") as out:
    out.write(json.dumps({"argv":sys.argv[1:],"stdin":sys.stdin.read(),
                          "env":{k:v for k,v in os.environ.items() if k.startswith("BIRC_")}}) + "\\n")
if sys.argv[1:] == ["-i"]:
    sys.exit(int((root / "save_code").read_text()))
code = int((root / "find_code").read_text())
if code == 0:
    sys.stdout.buffer.write((root / "stored").read_bytes())
else:
    print("synthetic secret must not escape", file=sys.stderr)
sys.exit(code)
''')
        child = executable(root / "birc", '''
import json, os, sys, time
from pathlib import Path
root = Path(__file__).parent
fd = int(os.environ["BIRC_AUTH_SECRET_FD"])
secret = b""
while True:
    part = os.read(fd, 2048)
    if not part: break
    secret += part
os.close(fd)
(root / "child").write_text(json.dumps({"argv":sys.argv[1:],"secret":secret.decode(),
                                       "env":{k:v for k,v in os.environ.items() if k.startswith("BIRC_")}}))
event = (root / "event").read_bytes()
fd = int(os.environ["BIRC_AUTH_EVENT_FD"])
if event: os.write(fd, event)
if (root / "hold_event").exists():
    time.sleep(0.25)
    assert len((root / "calls").read_text().splitlines()) == 1, "stored before event EOF"
if (root / "stdout_event").exists():
    print("fake-child stdout: BIRC_AUTH_OK")
os.close(fd)
sys.exit(int((root / "child_code").read_text()))
''')
        cfg = config(root / "config.toml")
        secret = "  päss'\\\" word  "
        (root / "save_code").write_text("0")
        (root / "find_code").write_text("44")
        (root / "child_code").write_text("0")

        (root / "event").write_bytes(b"BIRC_AUTH_OK\n")
        prompts = []

        def prompt(message):
            prompts.append(message)
            return secret

        def run(*args):
            out, err = io.StringIO(), io.StringIO()
            with redirect_stdout(out), redirect_stderr(err):
                try:
                    result = launcher.main(["--profile", "test", "--config", str(cfg), *args],
                                           security=str(security), birc=str(child), prompt=prompt,
                                           platform="darwin")
                except SystemExit as error:
                    result = error.code
            text = out.getvalue() + err.getvalue()
            assert (not secret or secret not in text) and "synthetic secret" not in text, text
            return result, text

        def entries():
            return [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []

        def reset():
            calls.unlink(missing_ok=True)
            (root / "child").unlink(missing_ok=True)
            prompts.clear()

        # (+) Prompted UTF-8/spaces survive both pipes; save has no password argv/env.
        assert run("--frames", "1", "--channel", "#test")[0] == 0
        found = entries()
        assert len(found) == 2 and len(prompts) == 1
        assert found[0]["argv"][0] == "find-generic-password" and found[0]["argv"][-1] == "-w"
        assert found[1]["argv"] == ["-i"]
        assert "BIRC_SASL_PASS" not in found[0]["env"] and "BIRC_SASL_PASS" not in found[1]["env"]
        assert secret not in json.dumps(found[1]["argv"]) and "-U" not in found[1]["stdin"]
        command = found[1]["stdin"]
        encoded = command.split(" -X ")[1].rstrip("\n")
        envelope = bytes.fromhex(encoded).decode("ascii")
        assert envelope == "birc-v1:" + base64.b64encode(secret.encode()).decode()
        assert command.count("\n") == 1 and len(command.encode()) < 4096
        got = json.loads((root / "child").read_text())
        assert got["secret"] == secret and "--sasl-pass" not in got["argv"]
        assert got["argv"][:6] == ["--connect", "127.0.0.1", "--port", "6667", "--sasl-user", "alice"]
        assert "--plain" in got["argv"], "relay plaintext must be explicit to the TLS-default client"
        assert got["argv"][-4:] == ["--frames", "1", "--channel", "#test"]
        assert "BIRC_SASL_PASS" not in got["env"] and "BIRC_SASL_USER" not in got["env"]
        assert not any(secret in value for value in got["env"].values())

        # (+) Existing versioned secret is loaded once and never rewritten or prompted.
        reset()
        (root / "find_code").write_text("0")
        (root / "stored").write_bytes(envelope.encode() + b"\n")
        assert run()[0] == 0 and not prompts and len(entries()) == 1
        assert json.loads((root / "child").read_text())["secret"] == secret

        # (-) No authentication, exit-zero, malformed/prefix/duplicate success never save.
        (root / "find_code").write_text("44")
        for event in (b"", b"BIRC_AUTH_OK", b"BIRC_AUTH_OK\nextra", b"BIRC_AUTH_OK\n" * 2,
                      b"NOTICE :SASL: authentication successful\n", b"BIRC_AUTH_FAIL\n"):
            reset()
            (root / "event").write_bytes(event)
            assert run()[0] == 0 and len(entries()) == 1

        # (+) Auth success is independent of later client exit status; exact frame saves.
        reset()
        (root / "event").write_bytes(b"BIRC_AUTH_OK\n")
        (root / "child_code").write_text("7")
        assert run()[0] == 7 and len(entries()) == 2
        (root / "child_code").write_text("0")

        # (-/+) A complete-looking frame with an open writer cannot trigger early storage.
        reset()
        (root / "hold_event").touch()
        assert run()[0] == 0 and len(entries()) == 2
        (root / "hold_event").unlink()
        reset()
        (root / "event").write_bytes(b"")
        (root / "stdout_event").touch()
        assert run()[0] == 0 and len(entries()) == 1
        (root / "stdout_event").unlink()
        (root / "event").write_bytes(b"BIRC_AUTH_OK\n")

        # (-) Access/cancel errors do not prompt or spawn; helper output is never printed.
        for code in (1, 36, 128):
            reset()
            (root / "find_code").write_text(str(code))
            result, text = run()
            assert result != 0 and f"{code}" in text and not prompts
            assert not (root / "child").exists() and len(entries()) == 1

        # (-) Foreign/ambiguous, invalid UTF-8 and oversized stored values fail closed.
        (root / "find_code").write_text("0")
        for value in (b"plainpassword\n", b"birc-v1:not base64\n", b"birc-v1:/w==\n",
                      b"birc-v1:\n", b"birc-v1:" + b"A" * 5000 + b"\n"):
            reset()
            (root / "stored").write_bytes(value)
            assert run()[0] != 0 and not prompts and not (root / "child").exists()

        # (-/+) Safe relay policy; explicit unsafe permission is per invocation only.
        (root / "find_code").write_text("44")
        for host, relay in (("irc.example", True), ("localhost", True), ("127.0.0.1", False)):
            reset()
            config(cfg, host=host, relay=relay)
            assert run()[0] != 0 and not entries() and not prompts
            result, text = run("--allow-insecure-auth")
            assert result == 0 and "WARNING" in text and len(entries()) == 2
            reset()
            assert run()[0] != 0 and not entries()
        config(cfg)

        # (-) No secret config, permission repair, FIFO/symlink following or identity override.
        for extra in ('password = "do not read me"\n', 'auth = "unknown"\n',
                      'nickserv_prefix = "bad"\nauth = "nickserv"\n'):
            reset()
            config(cfg, extra=extra)
            assert run()[0] != 0 and not entries() and not prompts
        config(cfg)
        reset()
        cfg.chmod(0o666)
        assert run()[0] != 0 and cfg.stat().st_mode & 0o777 == 0o666
        cfg.chmod(0o600)
        target = root / "symlink.toml"
        target.symlink_to(cfg)
        cfg_original, cfg = cfg, target
        assert run()[0] != 0 and not entries()
        cfg = root / "blocked.toml"
        os.mkfifo(cfg)
        assert run()[0] != 0 and not entries()
        cfg = cfg_original
        with patch.object(launcher.os, "getuid", return_value=os.getuid() + 1):
            assert run()[0] != 0 and not entries()
        with patch.object(launcher.Path, "home", side_effect=RuntimeError("no synthetic home")):
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                assert launcher.main(["--profile", "test"], platform="darwin") != 0
            assert run()[0] == 0  # An explicit config never needs a home lookup.
        reset()
        cfg.write_bytes(b"x" * (launcher.MAX_CONFIG + 1))
        assert run()[0] != 0 and not entries()
        config(cfg, extra='\n[profiles.other]\npassword = "forbidden"\n')
        assert run()[0] != 0 and not entries()
        config(cfg)
        for flag in ("--connect", "--sasl-pass", "--sasl-user", "--auth", "--nick"):
            assert run(flag, "synthetic-secret")[0] != 0 and not entries()

        # (-/+) Match core Auth.valid_prefix's service-nick exclusions before credentials.
        for prefix in ("NickServ!services@services.test", "Nick-Serv!u@h"):
            reset()
            config(cfg, extra='auth = "nickserv"\n'
                              + f'nickserv_prefix = {json.dumps(prefix)}\n'
                              + 'nickserv_success = "Identified as alice."\n')
            assert run()[0] == 0 and len(entries()) == 2 and len(prompts) == 1
        for prefix in ("NickServ,other!u@h", "#room!u@h", "&room!u@h", "+room!u@h",
                       "!room!u@h", ":NickServ!u@h", "@NickServ!u@h", "@#room!u@h"):
            reset()
            config(cfg, extra='auth = "nickserv"\n'
                              + f'nickserv_prefix = {json.dumps(prefix)}\n'
                              + 'nickserv_success = "Identified as alice."\n')
            result, _ = run()
            assert result != 0 and not entries() and not prompts and not (root / "child").exists(), prefix
        reset()
        config(cfg)

        # (-) Empty/NUL/newline or oversized prompted passwords never start client or store.
        reset()
        (root / "find_code").write_text("44")
        valid_secret = secret
        for invalid in ("", "abc\x00def", "abc\ndef", "abc\rdef", "a" * 1025):
            secret = invalid
            assert run()[0] != 0 and not (root / "child").exists() and len(entries()) == 1
            reset()
        secret = valid_secret

        # (+) Explicit NickServ trust is forwarded exactly, never inferred from a notice.
        config(cfg, extra='auth = "sasl-nickserv"\nnick = "other"\n'
                          'nickserv_prefix = "NickServ!services@services.test"\n'
                          'nickserv_success = "You are now identified as alice."\n')
        assert run()[0] == 0
        argv = json.loads((root / "child").read_text())["argv"]
        assert argv[argv.index("--auth") + 1] == "sasl-nickserv"
        assert argv[argv.index("--nickserv-prefix") + 1] == "NickServ!services@services.test"
        assert argv[argv.index("--nickserv-success") + 1] == "You are now identified as alice."
        assert argv[argv.index("--nick") + 1] == "other"

        # (+) Interactive quoting round-trips quotes/backslashes; metadata never adds commands.
        reset()
        account = 'ali"ce\\name'
        config(cfg, account=account)
        assert run()[0] == 0
        words = shlex.split(entries()[1]["stdin"])
        assert words[words.index("-a") + 1] == account
        assert words[words.index("-s") + 1] == launcher.read_profile(cfg, "test").service
        assert len(words) == 7 and entries()[1]["stdin"].count("\n") == 1
        reset()
        profile = launcher.read_profile(cfg, "test")
        with patch.object(launcher, "bounded_process", return_value=(44, b"unexpected output")):
            try:
                launcher.load_secret(str(security), profile)
            except launcher.Refusal:
                pass
            else:
                raise AssertionError("noncanonical unavailable result accepted")
        with patch.object(launcher, "bounded_process", side_effect=AssertionError("must not spawn")):
            try:
                launcher.save_secret(str(security), profile._replace(service="x" * 4096), b"a")
            except launcher.Refusal:
                pass
            else:
                raise AssertionError("oversized command accepted")

        # (-) A getpass fallback must stop before an echoed stdin password can be read.
        def unsafe_prompt(message):
            warnings.warn("synthetic echo fallback", launcher.getpass.GetPassWarning)
            raise AssertionError("must not read echoed password")
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            assert launcher.main(["--profile", "test", "--config", str(cfg)],
                                 security=str(security), birc=str(child), prompt=unsafe_prompt,
                                 platform="darwin") != 0
        assert len(entries()) == 1 and not (root / "child").exists()

        # (-/+) Native helper IO has bounded stdout and timeout, including blocked stdin.
        quiet = executable(root / "quiet", 'import sys\nsys.stdin.buffer.read()\nprint("ok")\n')
        assert launcher.bounded_process([str(quiet)], b"synthetic", limit=16) == (0, b"ok\n")
        large = executable(root / "large", 'import sys\nsys.stdout.write("x" * 256)\n')
        slow = executable(root / "slow", 'import time\ntime.sleep(10)\n')
        for program, data, limit, timeout in ((large, b"", 16, 2), (slow, b"x" * (1024 * 1024), 16, 0.1)):
            try:
                launcher.bounded_process([str(program)], data, limit=limit, timeout=timeout)
            except launcher.Refusal:
                pass
            else:
                raise AssertionError("helper bounds were ignored")

        # (-/+) Partial writes preserve the exact credential; write-zero fails closed.
        read_fd, write_fd = os.pipe()
        real_write = os.write
        try:
            with patch.object(launcher.os, "write", side_effect=lambda fd, data: real_write(fd, data[:1])):
                launcher.write_secret(write_fd, secret.encode())
            assert os.read(read_fd, 2048) == secret.encode()
            with patch.object(launcher.os, "write", return_value=0):
                try:
                    launcher.write_secret(write_fd, b"a")
                except launcher.Refusal:
                    pass
                else:
                    raise AssertionError("write-zero accepted")
        finally:
            os.close(read_fd)
            os.close(write_fd)

        # (-) Failed allocation of the second pipe releases the first pipe's owned FDs.
        first = os.pipe()
        with patch.object(launcher.os, "pipe", side_effect=[first, OSError("synthetic allocation")]):
            try:
                launcher.launch(str(child), profile, b"a", [], str(security), save=False)
            except OSError:
                pass
            else:
                raise AssertionError("pipe allocation failure accepted")
        for fd in first:
            try:
                os.fstat(fd)
            except OSError:
                pass
            else:
                raise AssertionError("owned pipe fd leaked")

        # (-/+) Child exit can occur after an empty select but before poll observes exit.
        # The real pipe must still be drained, with EOF required even for an exact frame.
        def exit_race(event, *, close_writer=True):
            reader, writer = os.pipe()
            sent, selects = False, 0

            class Exited:
                def poll(self):
                    nonlocal sent, writer
                    if not sent:
                        if event:
                            os.write(writer, event)
                        if close_writer:
                            os.close(writer)
                            writer = -1
                        sent = True
                    return 0

            class TimeoutSelector:
                def __enter__(self):
                    return self

                def __exit__(self, *args):
                    return False

                def register(self, *args):
                    pass

                def select(self, timeout):
                    nonlocal selects
                    selects += 1
                    assert selects <= 3, "exited child/orphan writer must not wait indefinitely"
                    return []

            try:
                with patch.object(launcher.selectors, "DefaultSelector", TimeoutSelector):
                    return launcher.auth_succeeded(Exited(), reader)
            finally:
                os.close(reader)
                if writer >= 0:
                    os.close(writer)

        assert exit_race(b"BIRC_AUTH_OK\n") is True
        for event in (b"", b"BIRC_AUTH_OK", b"BIRC_AUTH_OK\nextra", b"BIRC_AUTH_OK\n" * 2):
            assert exit_race(event) is False
        assert exit_race(b"BIRC_AUTH_OK\n", close_writer=False) is False

        # (-) Duplicate-on-save must not replace or delete any credential.
        reset()
        (root / "save_code").write_text("99")
        result, text = run()
        assert result == 0 and "99" in text and len(entries()) == 2
        assert "delete" not in entries()[1]["stdin"] and "-U" not in entries()[1]["stdin"]

        # (+) Non-Darwin supports help; (-) refuses credential operations.
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            try:
                launcher.main(["--help"], platform="linux")
            except SystemExit as error:
                assert error.code == 0
            else:
                raise AssertionError("help must exit")
            assert launcher.main(["--profile", "test", "--config", str(cfg)], platform="linux") != 0
    print("keychain_birc=ok")


if __name__ == "__main__":
    main()
